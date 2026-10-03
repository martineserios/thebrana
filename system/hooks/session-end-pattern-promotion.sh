#!/usr/bin/env bash
# session-end-pattern-promotion.sh — Promote or demote recalled patterns (t-203).
#
# Natural selection for patterns: patterns recalled at session-start get promoted
# when the session runs clean (low correction_rate), demoted when errors recur.
#
# Input (env vars):
#   SESSION_FILE       path to /tmp/brana-session-{id}.jsonl
#   CORRECTION_RATE    float string e.g. "0.07"
#   CORRECTIONS        integer count of corrections this session
#   TOTAL              integer total events
#   PROJECT            project slug
#
# Thresholds (conservative — avoid noise):
#   PROMOTE when: correction_rate < 0.05 AND total >= 10 (enough signal)
#   DEMOTE  when: correction_rate > 0.25 AND total >= 10
#   NO-OP   when: total < 10 or rate between thresholds
#
# Confidence delta: ±0.1 per session (clamped 0.0–1.0)
# Confidence labels: quarantine (<0.4), unproven (0.4–0.7), proven (>0.9 AND recall_count>=3)
#
# Always exits 0 — promotion failures are non-fatal.

set +e

source "$(dirname "${BASH_SOURCE[0]}")/lib/portable.sh"
SESSION_FILE="${SESSION_FILE:-}"
CORRECTION_RATE="${CORRECTION_RATE:-0.00}"
CORRECTIONS="${CORRECTIONS:-0}"
TOTAL="${TOTAL:-0}"
PROJECT="${PROJECT:-unknown}"

[ -z "$SESSION_FILE" ] || [ ! -f "$SESSION_FILE" ] && exit 0
[ "$TOTAL" -lt 10 ] && exit 0

# Parse correction_rate as integer comparison (multiply by 100)
RATE_INT=$(echo "$CORRECTION_RATE" | awk '{printf "%d", $1 * 100}' 2>/dev/null) || RATE_INT=0

# Determine action
ACTION=""
if [ "$RATE_INT" -lt 5 ]; then
    ACTION="promote"
elif [ "$RATE_INT" -gt 25 ]; then
    ACTION="demote"
else
    exit 0
fi

# Extract recalled pattern keys from session JSONL
RECALLED_KEYS=$(grep '"outcome":"recall"' "$SESSION_FILE" 2>/dev/null \
    | jq -r '.keys[]? // empty' 2>/dev/null | sort -u) || RECALLED_KEYS=""

[ -z "$RECALLED_KEYS" ] && exit 0

# Load ruflo CLI
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$HOME/.claude/scripts/cf-env.sh" ]; then
    source "$HOME/.claude/scripts/cf-env.sh" 2>/dev/null || true
elif [ -f "$SCRIPT_DIR/lib/cf-env.sh" ]; then
    source "$SCRIPT_DIR/lib/cf-env.sh" 2>/dev/null || true
fi

[ -z "${CF:-}" ] && exit 0

DELTA=$([ "$ACTION" = "promote" ] && echo "0.1" || echo "-0.1")
PROMOTED=0
DEMOTED=0
SKIPPED=0
MISSING=0
STORE_FAILED=0

while IFS= read -r KEY; do
    [ -z "$KEY" ] && continue

    # Exact-key read. Two defects lived here (t-3455): (a) `memory search --format json` returns
    # {results:[{key,score,preview}]} — an OBJECT with no value field — so the old
    # `.[]? | select(.key==$k) | .value` was empty on EVERY call and the else-branch below upserted a
    # key-only confidence stub over the real entry on every promote (20 of 158 pattern rows were
    # such stubs on 2026-10-03); (b) a semantic search by key text is not an existence check.
    # `memory retrieve -k` is exact: model-load noise goes to stderr; stdout carries one JSON
    # object on a hit (rc 0) or "[WARN] Key not found: <key>" on a clean miss (rc 1 on the pinned
    # 3.34 CLI, probed 2026-10-03 without a pipe). The miss text is checked BEFORE the rc so the
    # classification does not depend on which exit code a CLI version picks for a miss. A WRITE
    # must never follow a FAILED READ: any other non-zero rc (p_timeout ceiling 124, missing CF
    # 127), no JSON and no WARN, a JSON object for another key, or content that is not a JSON
    # object → skip the key, count it, write nothing.
    READ_OUT=$(cd "$HOME" && p_timeout 5 $CF memory retrieve -k "$KEY" --namespace pattern --format json 2>/dev/null); READ_RC=$?
    if printf '%s' "$READ_OUT" | grep -q 'Key not found'; then
        MISSING=$((MISSING + 1)); continue   # a key that no longer exists gets no confidence update and never a placeholder
    fi
    if [ "$READ_RC" -ne 0 ]; then SKIPPED=$((SKIPPED + 1)); continue; fi
    READ_JSON=$(printf '%s\n' "$READ_OUT" | sed -n '/^{/,$p')
    if [ -z "$READ_JSON" ]; then SKIPPED=$((SKIPPED + 1)); continue; fi
    # .content is the stored value: a JSON object, or a JSON-encoded string (double- or
    # triple-encoded rows exist). Decode strings until an object appears; anything else is skipped.
    # -s: slurp, so a stray JSON noise document before the row cannot produce two outputs; the row
    # is the first object whose .key matches. Numbers are coerced in jq so bash arithmetic never
    # sees a fraction or a string. The row's own tags travel with it (see the store below).
    ROW=$(printf '%s' "$READ_JSON" | jq -cs --arg k "$KEY" '
        def dec: if type == "string" then (fromjson? // .) else . end;
        [.[] | select(type == "object" and .key == $k)] | first // null
        | if . == null then null else {
            inner: (.content | dec | dec | dec | if type == "object" then . else null end),
            tags:  ((.tags // []) | if type == "string" then [.] else . end
                    | map(tostring | gsub("[\\[\\]\"\\\\ ]"; "")) | map(select(length > 0 and (startswith("confidence:") | not))))
          } end' 2>/dev/null) || ROW="null"
    INNER=$(printf '%s' "$ROW" | jq -c '.inner // empty' 2>/dev/null)
    if [ -z "$INNER" ] || [ "$INNER" = "null" ]; then SKIPPED=$((SKIPPED + 1)); continue; fi
    ROW_TAGS=$(printf '%s' "$ROW" | jq -r '.tags | join(",")' 2>/dev/null) || ROW_TAGS=""

    CURRENT_CONF=$(printf '%s' "$INNER" | jq -r '(.confidence // 0.5) | tonumber? // 0.5' 2>/dev/null) || CURRENT_CONF="0.5"
    RECALL_COUNT=$(printf '%s' "$INNER" | jq -r '(.recall_count // 0) | (tonumber? // 0) | floor' 2>/dev/null) || RECALL_COUNT="0"

    # Compute new confidence (clamped 0.0–1.0)
    NEW_CONF=$(awk -v c="$CURRENT_CONF" -v d="$DELTA" 'BEGIN {
        v = c + d
        if (v > 1.0) v = 1.0
        if (v < 0.0) v = 0.0
        printf "%.2f", v
    }' 2>/dev/null) || NEW_CONF="$CURRENT_CONF"

    # Increment recall_count on promote
    # (bash arithmetic has no string compare: `ACTION == "promote"` read both sides as unset
    #  variables → 0 == 0 → always true, so demotes also bumped recall_count — t-3455 gate finding)
    if [ "$ACTION" = "promote" ]; then NEW_RECALL=$(( RECALL_COUNT + 1 )); else NEW_RECALL=$RECALL_COUNT; fi

    # Compute confidence label
    CONF_LABEL="unproven"
    CONF_INT=$(echo "$NEW_CONF" | awk '{printf "%d", $1 * 100}' 2>/dev/null) || CONF_INT=50
    if [ "$CONF_INT" -lt 40 ]; then
        CONF_LABEL="quarantine"
    elif [ "$CONF_INT" -gt 90 ] && [ "$NEW_RECALL" -ge 3 ]; then
        CONF_LABEL="proven"
    fi

    # Merge the confidence fields into the existing object (never a fresh placeholder)
    UPDATED_INNER=$(printf '%s' "$INNER" | jq -c \
        --argjson conf "$NEW_CONF" \
        --argjson rc "$NEW_RECALL" \
        --arg label "$CONF_LABEL" \
        '. + {confidence: $conf, recall_count: $rc, confidence_label: $label}' 2>/dev/null) || { SKIPPED=$((SKIPPED + 1)); continue; }
    NEW_VALUE="$UPDATED_INNER"

    # Re-store with updated confidence. Tags are the ROW's own tags plus the new confidence tag: the
    # old `client:$PROJECT,type:pattern,...` relabelled a cosmos-trading row as client:thebrana when
    # it was promoted from a thebrana session (gate finding). A row without tags gets the old default.
    if [ -n "$ROW_TAGS" ]; then TAGS="$ROW_TAGS,confidence:$CONF_LABEL"; else TAGS="client:$PROJECT,type:pattern,confidence:$CONF_LABEL"; fi
    (cd "$HOME" && p_timeout 5 $CF memory store -k "$KEY" -v "$NEW_VALUE" \
        --namespace pattern --tags "$TAGS" --upsert >/dev/null 2>&1); STORE_RC=$?
    if [ "$STORE_RC" -ne 0 ]; then STORE_FAILED=$((STORE_FAILED + 1)); continue; fi   # a failed store is not a promotion

    if [ "$ACTION" = "promote" ]; then
        PROMOTED=$((PROMOTED + 1))
    else
        DEMOTED=$((DEMOTED + 1))
    fi
done <<< "$RECALLED_KEYS"

# Log result to a lightweight audit file (not the session JSONL — that's already done)
LOG_FILE="$HOME/.claude/logs/pattern-promotion.jsonl"
mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
jq -n -c \
    --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)" \
    --arg project "$PROJECT" \
    --arg action "$ACTION" \
    --argjson promoted "$PROMOTED" \
    --argjson demoted "$DEMOTED" \
    --argjson skipped "$SKIPPED" \
    --argjson missing "$MISSING" \
    --argjson store_failed "$STORE_FAILED" \
    --arg rate "$CORRECTION_RATE" \
    '{ts: $ts, project: $project, action: $action, promoted: $promoted, demoted: $demoted, skipped_unreadable: $skipped, missing: $missing, store_failed: $store_failed, correction_rate: $rate}' \
    >> "$LOG_FILE" 2>/dev/null || true

exit 0
