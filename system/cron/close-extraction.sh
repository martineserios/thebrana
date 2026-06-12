#!/usr/bin/env bash
# Nightly extraction worker — async-close Track 2 (t-1974, ADR-052 §6-7).
#
# Processes unprocessed close-queue entries chronologically: one agy (Gemini
# Flash, Layer A) pass per snapshot, validates the structured-JSON output
# contract, routes ALL learnings to the reminder store (v1 — human routes to
# memory at review), appends to the daily summary, then housekeeping (stale
# monitor, prune, snapshot cleanup).
#
# Hard rules (ADR-052):
#   - Queue access EXCLUSIVELY via `brana close-queue` subcommands. jq/python
#     parse CLI stdout and /tmp worker output only — never the store file.
#   - agy output missing/empty/unparseable → mark-failed (never partial
#     writes, never skip-and-mark-processed). 3 strikes → failure reminder.
#   - agy binary unreachable → exit non-zero so scheduler health surfaces it.
#
# Env overrides (tests): BRANA, AGY_BIN.

set -uo pipefail

# systemd/cron environments may not export HOME — everything below
# (stores, summaries, write_reminder) depends on it (t-1979 #6).
: "${HOME:=$(getent passwd "$(id -u)" | cut -d: -f6)}"
export HOME

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAX_RETRIES=3
STALE_DAYS=3
SNAPSHOT_RETENTION_DAYS=30
MAX_LEARNINGS_PER_ENTRY=3
MIN_CONFIDENCE=0.5
# Max diff bytes inlined into the agy prompt — must stay safely under the
# kernel's per-argv-string cap MAX_ARG_STRLEN (131072 bytes); see t-2055.
MAX_DIFF_BYTES=100000

# ── binary resolution ──────────────────────────────────────────────────
BRANA_BIN="${BRANA:-}"
if [ -z "$BRANA_BIN" ] || [ ! -x "$BRANA_BIN" ]; then
    BRANA_BIN="$SCRIPT_DIR/../cli/rust/target/release/brana"
fi
if [ ! -x "$BRANA_BIN" ]; then
    BRANA_BIN="$(command -v brana 2>/dev/null)" || true
fi
if [ -z "$BRANA_BIN" ] || [ ! -x "$BRANA_BIN" ]; then
    echo "close-extraction: brana binary not found — cannot touch the queue" >&2
    exit 1
fi

AGY="${AGY_BIN:-$(command -v agy 2>/dev/null)}" || true
if [ -z "${AGY:-}" ] || [ ! -x "$AGY" ]; then
    echo "close-extraction: agy binary not found — queue left untouched" >&2
    exit 1
fi

# Reminder writes go through the shared hook wrapper (marshalling only).
# write_reminder resolves $BRANA itself; export ours so it matches.
export BRANA="$BRANA_BIN"
source "$SCRIPT_DIR/../hooks/lib/remind.sh"

TODAY=$(date +%Y-%m-%d)
SUMMARY_FILE="$HOME/.claude/sessions/daily-summary-${TODAY}.md"
mkdir -p "$HOME/.claude/sessions"

EXIT_CODE=0
PROCESSED=0
FAILED=0

# ── stale-queue self-monitor FIRST (>3 days unprocessed → reminder) ────
# Checked before processing so a recovering run still surfaces that the
# pipeline had stalled — staleness is a fact about the backlog at 2am,
# not about what this run manages to clear.
STALE_COUNT=$("$BRANA_BIN" close-queue list --unprocessed | python3 -c "
import json, sys, datetime
cutoff = datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(days=$STALE_DAYS)
n = 0
for e in json.load(sys.stdin):
    ts = datetime.datetime.fromisoformat(e['timestamp'].replace('Z', '+00:00'))
    if ts < cutoff:
        n += 1
print(n)")
if [ "${STALE_COUNT:-0}" -gt 0 ]; then
    write_reminder \
        --text "close-queue has $STALE_COUNT entr(ies) unprocessed for >$STALE_DAYS days — extraction cron failing or off" \
        --action "brana ops status && brana close-queue list --unprocessed" \
        --priority medium \
        --dedup-key "stale-close-queue" || true
fi

# ── per-entry extraction ───────────────────────────────────────────────
# Re-read the queue per iteration via the CLI (ADR-052 §2 — no cached
# shell-variable view across mutations). Each entry is attempted at most
# once per run — a failure costs one retry per night, not all three.
ATTEMPTED=""
while :; do
    # Next eligible entry: unprocessed, retry budget left, not yet tried
    # this run, oldest first.
    ENTRY=$("$BRANA_BIN" close-queue list --unprocessed | python3 -c "
import json, sys
attempted = set('''$ATTEMPTED'''.split())
entries = [e for e in json.load(sys.stdin)
           if e.get('retry_count', 0) < $MAX_RETRIES and e['id'] not in attempted]
print(json.dumps(entries[0]) if entries else '')")
    [ -z "$ENTRY" ] && break

    EID=$(echo "$ENTRY" | python3 -c "import json,sys; print(json.load(sys.stdin)['id'])")
    ATTEMPTED="$ATTEMPTED $EID"
    SNAP=$(echo "$ENTRY" | python3 -c "import json,sys; print(json.load(sys.stdin)['snapshot_path'])")
    PROJECT=$(echo "$ENTRY" | python3 -c "import json,sys; print(json.load(sys.stdin)['project'])")
    BRANCH=$(echo "$ENTRY" | python3 -c "import json,sys; print(json.load(sys.stdin)['branch'])")
    RANGE=$(echo "$ENTRY" | python3 -c "import json,sys; print(json.load(sys.stdin)['git_range'])")
    RETRIES=$(echo "$ENTRY" | python3 -c "import json,sys; print(json.load(sys.stdin).get('retry_count', 0))")
    TRUNCATED=$(echo "$ENTRY" | python3 -c "import json,sys; print(str(json.load(sys.stdin).get('snapshot_truncated', False)).lower())")

    fail_entry() {
        local reason="$1"
        "$BRANA_BIN" close-queue mark-failed "$EID" --error "$reason" >/dev/null
        FAILED=$((FAILED + 1))
        EXIT_CODE=1
        if [ $((RETRIES + 1)) -ge $MAX_RETRIES ]; then
            write_reminder \
                --text "Extraction failed 3x for $PROJECT $BRANCH ($RANGE): $reason" \
                --action "brana close-queue list --unprocessed" \
                --priority high \
                --dedup-key "extraction-failed:$EID" \
                --project "$PROJECT" || true
        fi
    }

    if [ ! -f "$SNAP" ]; then
        fail_entry "snapshot-missing: $SNAP"
        continue
    fi

    # Inline at most MAX_DIFF_BYTES of the diff: a single argv string is capped at
    # MAX_ARG_STRLEN (~128KB) — inlining a larger diff makes exec fail E2BIG before
    # agy even runs, poisoning the entry (t-2055). Stdin is not a viable carrier:
    # agy drops large stdin payloads and goes agentic looking for the diff.
    SNAP_BYTES=$(wc -c < "$SNAP")
    DIFF_CONTENT=$(head -c "$MAX_DIFF_BYTES" "$SNAP")

    # Contract portion of the prompt is a versioned file (t-1979 #7) — prompt
    # drift is reviewable in git instead of buried in shell string edits.
    PROMPT="You are extracting learnings from a coding session diff for project '$PROJECT' (branch $BRANCH, commits $RANGE)."
    # One truncation note only: the argv cap subsumes the 500KB snapshot note
    if [ "$SNAP_BYTES" -gt "$MAX_DIFF_BYTES" ]; then
        PROMPT="$PROMPT Only the first ${MAX_DIFF_BYTES} bytes of the diff are included — extract from what is present, do not flag the truncation."
    elif [ "$TRUNCATED" = "true" ]; then
        PROMPT="$PROMPT The diff was truncated at 500KB — extract from what is present, do not flag the truncation."
    fi
    PROMPT="$PROMPT
$(cat "$SCRIPT_DIR/prompts/close-extraction.txt")

--- DIFF ---
$DIFF_CONTENT"

    OUT_FILE="/tmp/close-extract-$$-${EID}.json"
    AGY_EXIT=0
    "$AGY" -p "$PROMPT" > "$OUT_FILE" 2>/dev/null || AGY_EXIT=$?
    if [ "$AGY_EXIT" -ne 0 ]; then
        # $? inside an `if ! cmd` branch reports the negated test (always 0) — capture explicitly (t-2004)
        # Categorized reasons (t-1979 #4) so failure analysis can group causes.
        if [ "$AGY_EXIT" -eq 124 ] || [ "$AGY_EXIT" -eq 137 ]; then
            fail_entry "timeout: agy invocation timed out (exit $AGY_EXIT)"
        elif grep -qiE '429|rate.?limit|resource_exhausted' "$OUT_FILE" 2>/dev/null; then
            fail_entry "rate-limit: agy rate-limited (exit $AGY_EXIT)"
        else
            fail_entry "agy-error: agy invocation failed (exit $AGY_EXIT)"
        fi
        rm -f "$OUT_FILE"
        continue
    fi

    # Validate output contract (ADR-052 §6): parseable JSON with .learnings array.
    LEARNINGS=$(python3 - "$OUT_FILE" "$MIN_CONFIDENCE" "$MAX_LEARNINGS_PER_ENTRY" <<'PYEOF'
import json, sys, re
raw = open(sys.argv[1]).read().strip()
min_conf, cap = float(sys.argv[2]), int(sys.argv[3])
# tolerate accidental markdown fences
raw = re.sub(r'^```(json)?\s*|\s*```$', '', raw)
try:
    data = json.loads(raw)
    ls = data["learnings"]
    assert isinstance(ls, list)
    for l in ls:
        assert l["type"] in ("errata", "pattern", "field-note")
        assert l["size"] in ("SMALL", "LARGE")
        assert l["title"].strip()
    # low-confidence filter + per-entry cap (t-1979 #7) — after contract
    # validation so a malformed low-conf item still fails the whole output
    ls = [l for l in ls if float(l.get("confidence", 1.0)) >= min_conf][:cap]
    print(json.dumps(ls))
except Exception:
    sys.exit(1)
PYEOF
) || {
        fail_entry "schema-invalid: agy output failed contract validation"
        rm -f "$OUT_FILE"
        continue
    }
    rm -f "$OUT_FILE"

    # ── L3 propagation pass (ADR-056 §4): entries flagged propagate:true ──
    # Runs BEFORE any reminder routing so a contract failure marks the entry
    # failed with zero partial writes. Repo state is read at CRON time, with
    # post-close commits surfaced so already-resolved gaps are suppressed.
    PROPAGATE=$(echo "$ENTRY" | python3 -c "import json,sys; print(str(json.load(sys.stdin).get('propagate', False)).lower())")
    GAPS="[]"
    if [ "$PROPAGATE" = "true" ]; then
        GROOT=$(echo "$ENTRY" | python3 -c "import json,sys; print(json.load(sys.stdin)['git_root'])")
        # Repo-state gathering only when git_root still exists (SEC-2: no git/file
        # ops on unvalidated paths). A vanished root is NORMAL — worktree closes
        # are reaped after merge — so degrade to diff-only audit, never fail_entry.
        POST_COMMITS=""
        TASK_STATE="unavailable"
        if [ -d "$GROOT/.git" ]; then
            POST_COMMITS=$(git -C "$GROOT" log --oneline "$RANGE..HEAD" 2>/dev/null | head -20)
            # Current task state (best-effort — challenger W2: feeds category (b) detection)
            TASK_STATE=$(cd "$GROOT" && "$BRANA_BIN" backlog query --status in_progress --output json 2>/dev/null | head -c 2000)
            [ -n "$TASK_STATE" ] || TASK_STATE="unavailable"
        else
            GROOT=""
        fi
        DOC_STATE=""
        for f in $(grep -oE '^diff --git a/[^ ]+' "$SNAP" | sed 's|^diff --git a/||' | grep '\.md$' | head -10); do
            [ -n "$GROOT" ] && [ -f "$GROOT/$f" ] || continue
            DOC_STATE="$DOC_STATE
--- $f (current) ---
$(grep -m1 -iE '^[*]*status' "$GROOT/$f" 2>/dev/null)
$(awk '/^#+ Documentation Plan/{flag=1; next} /^#+ /{flag=0} flag' "$GROOT/$f" | head -30)"
        done
        MEM_STATE=""
        MEM_N=0
        for m in "$GROOT"/.claude/memory/*.md; do
            [ -f "$m" ] || continue
            [ "$MEM_N" -ge 5 ] && break
            MEM_STATE="$MEM_STATE
--- $(basename "$m") ---
$(head -40 "$m")"
            MEM_N=$((MEM_N + 1))
        done
        PROP_DIFF=$(printf '%s' "$DIFF_CONTENT" | head -c 60000)
        PROP_PROMPT="You are auditing knowledge-propagation debt for project '$PROJECT' (branch $BRANCH, commits $RANGE).
Below: (1) the session diff, (2) CURRENT content of touched specs' Status + Documentation Plan sections, (3) current in-progress task state, (4) current project memory files, (5) post-close commits ($RANGE..HEAD).
Detect gaps in categories: (a) unfulfilled committed artifacts ('- [ ]' items, 'al cerrar'/'on close' promises), (b) Status fields contradicting completed work, (c) docs named in 'Existing docs to update' lines not updated, (d) memory claims contradicted by current state. Suppress any gap the current state or post-close commits show as already resolved. Return ONLY JSON, no markdown fences, matching exactly:
{\"gaps\": [{\"category\": \"a|b|c|d\", \"title\": \"...\", \"evidence\": \"...\", \"proposed_fix\": \"...\"}]}
Empty array if no gaps.

--- DIFF ---
$PROP_DIFF
--- CURRENT DOC STATE ---
$DOC_STATE
--- TASK STATE ---
$TASK_STATE
--- MEMORY ---
$MEM_STATE
--- POST-CLOSE COMMITS ---
$POST_COMMITS"
        PROP_OUT="/tmp/close-prop-$$-${EID}.json"
        PROP_AGY_EXIT=0
        "$AGY" -p "$PROP_PROMPT" > "$PROP_OUT" 2>/dev/null || PROP_AGY_EXIT=$?
        if [ "$PROP_AGY_EXIT" -ne 0 ]; then
            # $? inside an `if ! cmd` branch reports the negated test — capture explicitly (t-2004)
            fail_entry "agy propagation pass failed (exit $PROP_AGY_EXIT)"
            rm -f "$PROP_OUT"
            continue
        fi
        GAPS=$(python3 - "$PROP_OUT" <<'PYEOF'
import json, sys, re
raw = open(sys.argv[1]).read().strip()
raw = re.sub(r'^```(json)?\s*|\s*```$', '', raw)
try:
    data = json.loads(raw)
    gs = data["gaps"]
    assert isinstance(gs, list)
    for g in gs:
        assert g["category"] in ("a", "b", "c", "d")
        assert g["title"].strip()
    print(json.dumps(gs))
except Exception:
    sys.exit(1)
PYEOF
) || {
            fail_entry "agy propagation output failed contract validation"
            rm -f "$PROP_OUT"
            continue
        }
        rm -f "$PROP_OUT"
    fi

    # Route every learning to the reminder store (v1: human reviews → memory).
    COUNT=$(echo "$LEARNINGS" | python3 -c "import json,sys; print(len(json.load(sys.stdin)))")
    i=0
    while [ "$i" -lt "$COUNT" ]; do
        L_TYPE=$(echo "$LEARNINGS" | python3 -c "import json,sys; print(json.load(sys.stdin)[$i]['type'])")
        L_SIZE=$(echo "$LEARNINGS" | python3 -c "import json,sys; print(json.load(sys.stdin)[$i]['size'])")
        L_TITLE=$(echo "$LEARNINGS" | python3 -c "import json,sys; print(json.load(sys.stdin)[$i]['title'])")
        L_BODY=$(echo "$LEARNINGS" | python3 -c "import json,sys; print(json.load(sys.stdin)[$i]['body'])")
        L_PRIO="low"; [ "$L_SIZE" = "LARGE" ] && L_PRIO="high"
        L_SLUG=$(echo "$L_TITLE" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | cut -c1-48)
        write_reminder \
            --text "[$L_TYPE/$L_SIZE] $L_TITLE — $L_BODY" \
            --priority "$L_PRIO" \
            --dedup-key "extract:$PROJECT:$L_TYPE:$L_SLUG" \
            --project "$PROJECT" \
            --tags "extraction,$L_TYPE" || true
        i=$((i + 1))
    done

    # Propagation gaps → reminder store (ADR-056: same v1 human-review routing).
    GAP_COUNT=$(echo "$GAPS" | python3 -c "import json,sys; print(len(json.load(sys.stdin)))")
    g=0
    while [ "$g" -lt "$GAP_COUNT" ]; do
        G_CAT=$(echo "$GAPS" | python3 -c "import json,sys; print(json.load(sys.stdin)[$g]['category'])")
        G_TITLE=$(echo "$GAPS" | python3 -c "import json,sys; print(json.load(sys.stdin)[$g]['title'])")
        G_EVID=$(echo "$GAPS" | python3 -c "import json,sys; print(json.load(sys.stdin)[$g].get('evidence',''))")
        G_FIX=$(echo "$GAPS" | python3 -c "import json,sys; print(json.load(sys.stdin)[$g].get('proposed_fix',''))")
        G_SLUG=$(echo "$G_TITLE" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | cut -c1-48)
        write_reminder \
            --text "[propagation/$G_CAT] $G_TITLE — $G_EVID → $G_FIX" \
            --priority medium \
            --dedup-key "prop:$PROJECT:$G_SLUG" \
            --project "$PROJECT" \
            --tags "propagation,$G_CAT" || true
        g=$((g + 1))
    done

    # Daily summary: APPEND, never replace (ADR-052, challenger M9).
    {
        echo "## $PROJECT $BRANCH ($RANGE) — entry $EID"
        echo "$LEARNINGS" | python3 -c "
import json, sys
for l in json.load(sys.stdin):
    print(f\"- [{l['type']}/{l['size']}] {l['title']}: {l['body']}\")"
        [ "$COUNT" -eq 0 ] && echo "- no notable learnings"
        echo ""
    } >> "$SUMMARY_FILE"

    "$BRANA_BIN" close-queue mark-processed "$EID" --summary-path "$SUMMARY_FILE" >/dev/null
    PROCESSED=$((PROCESSED + 1))
done

# ── weekly unrouted-learnings review nudge (t-1979 #8) ─────────────────
# Auto-routing to memory stays deferred per ADR-052 §6 — the human is the
# router until the worker is proven. Dedup per ISO week, not per night.
PENDING_EXTRACT=$("$BRANA_BIN" remind list | python3 -c "
import json, sys
rs = json.load(sys.stdin)
print(sum(1 for r in rs if 'extraction' in (r.get('tags') or []) and r.get('status', 'pending') == 'pending'))" 2>/dev/null) || PENDING_EXTRACT=0
if [ "${PENDING_EXTRACT:-0}" -gt 0 ]; then
    write_reminder \
        --text "$PENDING_EXTRACT extracted learning(s) awaiting human routing to memory — review the daily summaries" \
        --action "brana remind list && ls ~/.claude/sessions/daily-summary-*.md" \
        --priority low \
        --dedup-key "weekly-learnings-review:$(date +%G-W%V)" || true
fi

# ── housekeeping: prune old terminal entries, delete old snapshots ─────
"$BRANA_BIN" close-queue list | python3 -c "
import json, sys, datetime, os
cutoff = datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(days=$SNAPSHOT_RETENTION_DAYS)
for e in json.load(sys.stdin):
    pa = e.get('processed_at')
    if e.get('processed') and pa:
        ts = datetime.datetime.fromisoformat(pa.replace('Z', '+00:00'))
        if ts < cutoff and e.get('snapshot_path') and os.path.isfile(e['snapshot_path']):
            os.remove(e['snapshot_path'])"
"$BRANA_BIN" close-queue prune >/dev/null

# Defensive, status-blind sweep (t-1979 #5/#9): failed and orphaned snapshots
# age out at 30d regardless of queue bookkeeping, as do old daily summaries —
# aligned with the 30d entry retention in queue.rs (PRUNE_DAYS).
find "$HOME/.claude/sessions" -maxdepth 1 -name 'snap-*.diff' -mtime +30 -delete 2>/dev/null || true
find "$HOME/.claude/sessions" -maxdepth 1 -name 'daily-summary-*.md' -mtime +30 -delete 2>/dev/null || true

echo "close-extraction: processed=$PROCESSED failed=$FAILED stale=$STALE_COUNT"
exit "$EXIT_CODE"
