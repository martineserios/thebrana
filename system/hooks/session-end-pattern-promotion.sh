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

while IFS= read -r KEY; do
    [ -z "$KEY" ] && continue

    # Fetch current pattern value
    CURRENT_JSON=$(cd "$HOME" && timeout 3 $CF memory search \
        --query "$KEY" --namespace pattern --format json 2>/dev/null \
        | jq -r --arg k "$KEY" '.[]? | select(.key == $k) | .value' 2>/dev/null | head -1) || CURRENT_JSON=""

    # Parse current confidence (default 0.5 if unset or pattern not found)
    if [ -n "$CURRENT_JSON" ]; then
        CURRENT_CONF=$(echo "$CURRENT_JSON" | jq -r 'fromjson? | .confidence // 0.5' 2>/dev/null) || CURRENT_CONF="0.5"
        RECALL_COUNT=$(echo "$CURRENT_JSON" | jq -r 'fromjson? | .recall_count // 0' 2>/dev/null) || RECALL_COUNT="0"
    else
        CURRENT_CONF="0.5"
        RECALL_COUNT="0"
    fi

    # Compute new confidence (clamped 0.0–1.0)
    NEW_CONF=$(awk -v c="$CURRENT_CONF" -v d="$DELTA" 'BEGIN {
        v = c + d
        if (v > 1.0) v = 1.0
        if (v < 0.0) v = 0.0
        printf "%.2f", v
    }' 2>/dev/null) || NEW_CONF="$CURRENT_CONF"

    # Increment recall_count on promote
    NEW_RECALL=$(( RECALL_COUNT + (ACTION == "promote" ? 1 : 0) ))

    # Compute confidence label
    CONF_LABEL="unproven"
    CONF_INT=$(echo "$NEW_CONF" | awk '{printf "%d", $1 * 100}' 2>/dev/null) || CONF_INT=50
    if [ "$CONF_INT" -lt 40 ]; then
        CONF_LABEL="quarantine"
    elif [ "$CONF_INT" -gt 90 ] && [ "$NEW_RECALL" -ge 3 ]; then
        CONF_LABEL="proven"
    fi

    # Build updated value — merge into existing JSON or create new
    if [ -n "$CURRENT_JSON" ]; then
        INNER=$(echo "$CURRENT_JSON" | jq -c 'fromjson? // {}' 2>/dev/null) || INNER="{}"
        UPDATED_INNER=$(echo "$INNER" | jq -c \
            --argjson conf "$NEW_CONF" \
            --argjson rc "$NEW_RECALL" \
            --arg label "$CONF_LABEL" \
            '. + {confidence: $conf, recall_count: $rc, confidence_label: $label}' 2>/dev/null) || UPDATED_INNER="$INNER"
        NEW_VALUE=$(echo "$UPDATED_INNER" | jq -c '.' 2>/dev/null) || NEW_VALUE="{}"
    else
        NEW_VALUE=$(jq -n -c \
            --argjson conf "$NEW_CONF" \
            --argjson rc "$NEW_RECALL" \
            --arg label "$CONF_LABEL" \
            --arg key "$KEY" \
            '{key: $key, confidence: $conf, recall_count: $rc, confidence_label: $label}' 2>/dev/null) || continue
    fi

    # Re-store with updated confidence
    TAGS="client:$PROJECT,type:pattern,confidence:$CONF_LABEL"
    cd "$HOME" && timeout 5 $CF memory store -k "$KEY" -v "$NEW_VALUE" \
        --namespace pattern --tags "$TAGS" >/dev/null 2>&1 || true

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
    --arg rate "$CORRECTION_RATE" \
    '{ts: $ts, project: $project, action: $action, promoted: $promoted, demoted: $demoted, correction_rate: $rate}' \
    >> "$LOG_FILE" 2>/dev/null || true

exit 0
