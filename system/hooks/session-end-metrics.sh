#!/usr/bin/env bash
# session-end-metrics.sh — Compute session metrics from JSONL event file.
#
# Input (env vars):
#   SESSION_FILE      path to the JSONL event log for this session
#   BRANA_CLI         path to brana binary (optional — falls back to grep/awk)
#   METRICS_ENV_FILE  output path for the env file (required)
#
# Output: shell env file at $METRICS_ENV_FILE with exported metric vars.
#   Source it to get: TOTAL SUCCESSES FAILURES CORRECTIONS TEST_WRITES CASCADES
#   PR_CREATES TEST_PASSES TEST_FAILS LINT_PASSES LINT_FAILS EDITS DELEGATIONS
#   TOOLS FILES CORRECTION_RATE AUTO_FIX_RATE TEST_WRITE_RATE CASCADE_RATE
#   TEST_PASS_RATE LINT_PASS_RATE SUMMARY_JSON
#
# Always exits 0 — metric errors produce zero values, not failures.

set -uo pipefail

SESSION_FILE="${SESSION_FILE:-}"
BRANA_CLI="${BRANA_CLI:-}"
OUT="${METRICS_ENV_FILE:-}"
PROJECT_FILTER="${PROJECT_FILTER:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOKS_ROOT=$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null) || HOOKS_ROOT=""

# Default all metrics to zero
TOTAL=0; SUCCESSES=0; FAILURES=0; CORRECTIONS=0; TEST_WRITES=0
CASCADES=0; PR_CREATES=0; TEST_PASSES=0; TEST_FAILS=0; LINT_PASSES=0
LINT_FAILS=0; EDITS=0; DELEGATIONS=0
TOOLS="unknown"; FILES=""
CORRECTION_RATE="0.00"; AUTO_FIX_RATE="0.00"; TEST_WRITE_RATE="0.00"
CASCADE_RATE="0.00"; TEST_PASS_RATE="N/A"; LINT_PASS_RATE="N/A"
SUMMARY_JSON="{}"

write_env() {
    cat > "$OUT" <<EOF
TOTAL=$TOTAL
SUCCESSES=$SUCCESSES
FAILURES=$FAILURES
CORRECTIONS=$CORRECTIONS
TEST_WRITES=$TEST_WRITES
CASCADES=$CASCADES
PR_CREATES=$PR_CREATES
TEST_PASSES=$TEST_PASSES
TEST_FAILS=$TEST_FAILS
LINT_PASSES=$LINT_PASSES
LINT_FAILS=$LINT_FAILS
EDITS=$EDITS
DELEGATIONS=$DELEGATIONS
TOOLS=$(printf '%q' "$TOOLS")
FILES=$(printf '%q' "$FILES")
CORRECTION_RATE=$CORRECTION_RATE
AUTO_FIX_RATE=$AUTO_FIX_RATE
TEST_WRITE_RATE=$TEST_WRITE_RATE
CASCADE_RATE=$CASCADE_RATE
TEST_PASS_RATE=$TEST_PASS_RATE
LINT_PASS_RATE=$LINT_PASS_RATE
SUMMARY_JSON=$(printf '%q' "$SUMMARY_JSON")
EOF
}

# No session file or empty → write zeros and exit
if [ -z "$SESSION_FILE" ] || [ ! -f "$SESSION_FILE" ] || [ ! -s "$SESSION_FILE" ]; then
    [ -n "$OUT" ] && write_env
    exit 0
fi

# Bucket events by repo root when PROJECT_FILTER is set.
# Events with a matching repo field OR no repo field (legacy) are included.
# Events from a different repo are excluded.
_FILTERED_FILE=""
if [ -n "$PROJECT_FILTER" ]; then
    _FILTERED_FILE=$(mktemp /tmp/brana-metrics-filtered-XXXXXX.jsonl)
    jq -c --arg p "$PROJECT_FILTER" \
        'select((.repo == null) or (.repo == "") or (.repo == $p))' \
        "$SESSION_FILE" > "$_FILTERED_FILE" 2>/dev/null || true
    SESSION_FILE="$_FILTERED_FILE"
fi
trap '[ -n "${_FILTERED_FILE:-}" ] && rm -f "$_FILTERED_FILE"' EXIT

METRICS_JSON=""

# Fast path: Rust CLI
if [ -n "$BRANA_CLI" ] && [ -x "$BRANA_CLI" ]; then
    METRICS_JSON=$(cd "${HOOKS_ROOT:-.}" && "$BRANA_CLI" ops metrics "$SESSION_FILE" 2>/dev/null) || METRICS_JSON=""
    if [ -n "$METRICS_JSON" ]; then
        TOTAL=$(echo "$METRICS_JSON" | jq -r '.events // 0') || TOTAL=0
        SUCCESSES=$(echo "$METRICS_JSON" | jq -r '.successes // 0') || SUCCESSES=0
        FAILURES=$(echo "$METRICS_JSON" | jq -r '.failures // 0') || FAILURES=0
        CORRECTIONS=$(echo "$METRICS_JSON" | jq -r '.corrections // 0') || CORRECTIONS=0
        TEST_WRITES=$(echo "$METRICS_JSON" | jq -r '.test_writes // 0') || TEST_WRITES=0
        CASCADES=$(echo "$METRICS_JSON" | jq -r '.cascades // 0') || CASCADES=0
        PR_CREATES=$(echo "$METRICS_JSON" | jq -r '.pr_creates // 0') || PR_CREATES=0
        TEST_PASSES=$(echo "$METRICS_JSON" | jq -r '.test_passes // 0') || TEST_PASSES=0
        TEST_FAILS=$(echo "$METRICS_JSON" | jq -r '.test_fails // 0') || TEST_FAILS=0
        LINT_PASSES=$(echo "$METRICS_JSON" | jq -r '.lint_passes // 0') || LINT_PASSES=0
        LINT_FAILS=$(echo "$METRICS_JSON" | jq -r '.lint_fails // 0') || LINT_FAILS=0
        EDITS=$(echo "$METRICS_JSON" | jq -r '.edits // 0') || EDITS=0
        DELEGATIONS=$(echo "$METRICS_JSON" | jq -r '.delegations // 0') || DELEGATIONS=0
        TOOLS=$(echo "$METRICS_JSON" | jq -r '.tools // "unknown"') || TOOLS="unknown"
        FILES=$(echo "$METRICS_JSON" | jq -r '.files // ""') || FILES=""
        CORRECTION_RATE=$(echo "$METRICS_JSON" | jq -r '.flywheel.correction_rate // "0.00"') || CORRECTION_RATE="0.00"
        AUTO_FIX_RATE=$(echo "$METRICS_JSON" | jq -r '.flywheel.auto_fix_rate // "0.00"') || AUTO_FIX_RATE="0.00"
        TEST_WRITE_RATE=$(echo "$METRICS_JSON" | jq -r '.flywheel.test_write_rate // "0.00"') || TEST_WRITE_RATE="0.00"
        CASCADE_RATE=$(echo "$METRICS_JSON" | jq -r '.flywheel.cascade_rate // "0.00"') || CASCADE_RATE="0.00"
        TEST_PASS_RATE=$(echo "$METRICS_JSON" | jq -r '.flywheel.test_pass_rate // "N/A"') || TEST_PASS_RATE="N/A"
        LINT_PASS_RATE=$(echo "$METRICS_JSON" | jq -r '.flywheel.lint_pass_rate // "N/A"') || LINT_PASS_RATE="N/A"
    fi
fi

# Fallback: grep/jq/awk
if [ -z "$METRICS_JSON" ]; then
    TOTAL=$(wc -l < "$SESSION_FILE" 2>/dev/null | tr -d ' ') || TOTAL=0
    SUCCESSES=$(grep -c '"outcome":"success"' "$SESSION_FILE" 2>/dev/null) || SUCCESSES=0
    FAILURES=$(jq -r 'select(.outcome == "failure" or .outcome == "test-fail" or .outcome == "lint-fail") | .outcome' \
        "$SESSION_FILE" 2>/dev/null | wc -l | tr -d ' ') || FAILURES=0
    TOOLS=$(jq -r '.tool' "$SESSION_FILE" 2>/dev/null | sort -u | paste -sd ',' || echo "unknown")
    FILES=$(jq -r '.detail // empty' "$SESSION_FILE" 2>/dev/null | sort -u | head -10 | paste -sd ',' || echo "")
    CORRECTIONS=$(grep -c '"outcome":"correction"' "$SESSION_FILE" 2>/dev/null) || CORRECTIONS=0
    TEST_WRITES=$(grep -c '"outcome":"test-write"' "$SESSION_FILE" 2>/dev/null) || TEST_WRITES=0
    CASCADES=$(grep -c '"cascade":true' "$SESSION_FILE" 2>/dev/null) || CASCADES=0
    PR_CREATES=$(grep -c '"outcome":"pr-create"' "$SESSION_FILE" 2>/dev/null) || PR_CREATES=0
    TEST_PASSES=$(grep -c '"outcome":"test-pass"' "$SESSION_FILE" 2>/dev/null) || TEST_PASSES=0
    TEST_FAILS=$(grep -c '"outcome":"test-fail"' "$SESSION_FILE" 2>/dev/null) || TEST_FAILS=0
    LINT_PASSES=$(grep -c '"outcome":"lint-pass"' "$SESSION_FILE" 2>/dev/null) || LINT_PASSES=0
    LINT_FAILS=$(grep -c '"outcome":"lint-fail"' "$SESSION_FILE" 2>/dev/null) || LINT_FAILS=0
    EDITS=$(jq -r 'select(.tool == "Edit" or .tool == "Write") | .tool' "$SESSION_FILE" 2>/dev/null | wc -l | tr -d ' ') || EDITS=0
    DELEGATIONS=$(grep -c '"tool":"Task"' "$SESSION_FILE" 2>/dev/null) || DELEGATIONS=0

    if [ "${EDITS:-0}" -gt 0 ]; then
        CORRECTION_RATE=$(awk "BEGIN {printf \"%.2f\", ${CORRECTIONS:-0} / ${EDITS}}")
        TEST_WRITE_RATE=$(awk "BEGIN {printf \"%.2f\", ${TEST_WRITES:-0} / ${EDITS}}")
    fi
    if [ "${FAILURES:-0}" -gt 0 ]; then
        CASCADE_RATE=$(awk "BEGIN {printf \"%.2f\", ${CASCADES:-0} / ${FAILURES}}")
        AUTO_FIXES=$(jq -r '[.outcome, .detail] | @tsv' "$SESSION_FILE" 2>/dev/null | awk -F'\t' '
            BEGIN { fixes=0 }
            /^failure\t/  { prev_fail[$2]=1 } /^test-fail\t/ { prev_fail[$2]=1 }
            /^lint-fail\t/{ prev_fail[$2]=1 }
            /^success\t/   { if ($2 in prev_fail) { fixes++; delete prev_fail[$2] } }
            /^correction\t/{ if ($2 in prev_fail) { fixes++; delete prev_fail[$2] } }
            /^test-pass\t/ { if ($2 in prev_fail) { fixes++; delete prev_fail[$2] } }
            /^lint-pass\t/ { if ($2 in prev_fail) { fixes++; delete prev_fail[$2] } }
            END { print fixes }
        ' 2>/dev/null) || AUTO_FIXES=0
        AUTO_FIX_RATE=$(awk "BEGIN {printf \"%.2f\", ${AUTO_FIXES:-0} / ${FAILURES}}")
    fi
    TEST_TOTAL=$((${TEST_PASSES:-0} + ${TEST_FAILS:-0}))
    if [ "$TEST_TOTAL" -gt 0 ]; then
        TEST_PASS_RATE=$(awk "BEGIN {printf \"%.2f\", ${TEST_PASSES:-0} / $TEST_TOTAL}")
    fi
    LINT_TOTAL=$((${LINT_PASSES:-0} + ${LINT_FAILS:-0}))
    if [ "$LINT_TOTAL" -gt 0 ]; then
        LINT_PASS_RATE=$(awk "BEGIN {printf \"%.2f\", ${LINT_PASSES:-0} / $LINT_TOTAL}")
    fi
fi

[ -n "$OUT" ] && write_env
exit 0
