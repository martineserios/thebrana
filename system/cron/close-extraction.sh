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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAX_RETRIES=3
STALE_DAYS=3
SNAPSHOT_RETENTION_DAYS=14
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
        fail_entry "snapshot file missing: $SNAP"
        continue
    fi

    # Inline at most MAX_DIFF_BYTES of the diff: a single argv string is capped at
    # MAX_ARG_STRLEN (~128KB) — inlining a larger diff makes exec fail E2BIG before
    # agy even runs, poisoning the entry (t-2055). Stdin is not a viable carrier:
    # agy drops large stdin payloads and goes agentic looking for the diff.
    SNAP_BYTES=$(wc -c < "$SNAP")
    DIFF_CONTENT=$(head -c "$MAX_DIFF_BYTES" "$SNAP")

    PROMPT="You are extracting learnings from a coding session diff for project '$PROJECT' (branch $BRANCH, commits $RANGE)."
    [ "$TRUNCATED" = "true" ] && PROMPT="$PROMPT The diff was truncated at 500KB — extract from what is present, do not flag the truncation."
    [ "$SNAP_BYTES" -gt "$MAX_DIFF_BYTES" ] && PROMPT="$PROMPT Only the first ${MAX_DIFF_BYTES} bytes of the diff are included — extract from what is present, do not flag the truncation."
    PROMPT="$PROMPT Return ONLY a JSON object, no markdown fences, matching exactly:
{\"learnings\": [{\"type\": \"errata|pattern|field-note\", \"size\": \"SMALL|LARGE\", \"title\": \"...\", \"body\": \"...\", \"confidence\": 0.0}]}
Rules: SMALL = incremental/known-class insight; LARGE = novel pattern or decision-worthy finding. Only include learnings actually evidenced in the diff (bug fixes, workarounds, API mismatches, reusable patterns). Empty array if nothing notable.

--- DIFF ---
$DIFF_CONTENT"

    OUT_FILE="/tmp/close-extract-$$-${EID}.json"
    AGY_EXIT=0
    "$AGY" -p "$PROMPT" > "$OUT_FILE" 2>/dev/null || AGY_EXIT=$?
    if [ "$AGY_EXIT" -ne 0 ]; then
        # $? inside an `if ! cmd` branch reports the negated test (always 0) — capture explicitly (t-2004)
        fail_entry "agy invocation failed (exit $AGY_EXIT)"
        rm -f "$OUT_FILE"
        continue
    fi

    # Validate output contract (ADR-052 §6): parseable JSON with .learnings array.
    LEARNINGS=$(python3 - "$OUT_FILE" <<'PYEOF'
import json, sys, re
raw = open(sys.argv[1]).read().strip()
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
    print(json.dumps(ls))
except Exception:
    sys.exit(1)
PYEOF
) || {
        fail_entry "agy output failed contract validation"
        rm -f "$OUT_FILE"
        continue
    }
    rm -f "$OUT_FILE"

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
            --dedup-key "extract:$PROJECT:$L_SLUG" \
            --project "$PROJECT" \
            --tags "extraction,$L_TYPE" || true
        i=$((i + 1))
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

echo "close-extraction: processed=$PROCESSED failed=$FAILED stale=$STALE_COUNT"
exit "$EXIT_CODE"
