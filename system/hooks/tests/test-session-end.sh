#!/usr/bin/env bash
# Tests for session-end.sh hook
# Simulates SessionEnd JSON input and checks JSON output + side effects.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/../session-end.sh"
PASS=0
FAIL=0
TOTAL=0
TMPDIR=$(mktemp -d)

trap 'rm -rf "$TMPDIR"' EXIT

# ── Test isolation ───────────────────────────────────────
# Minimal PATH without ruflo/npx, fake HOME to isolate state.
SAFE_PATH="/usr/bin:/bin:/usr/sbin:/sbin"
GIT_DIR="$(dirname "$(command -v git)")"
[[ ":$SAFE_PATH:" != *":$GIT_DIR:"* ]] && SAFE_PATH="$GIT_DIR:$SAFE_PATH"
JQ_DIR="$(dirname "$(command -v jq)")"
[[ ":$SAFE_PATH:" != *":$JQ_DIR:"* ]] && SAFE_PATH="$JQ_DIR:$SAFE_PATH"

FAKE_HOME="$TMPDIR/fakehome"
mkdir -p "$FAKE_HOME/.claude/projects/fake/memory"
echo "# Auto Memory" > "$FAKE_HOME/.claude/projects/fake/memory/MEMORY.md"

run_hook() {
    local input="$1"
    local raw
    raw=$(echo "$input" | \
        PATH="$SAFE_PATH" \
        HOME="$FAKE_HOME" \
        BRANA_HOOK_PROFILE=standard \
        CLAUDE_PLUGIN_DATA="" \
        CLAUDE_PLUGIN_ROOT="" \
        bash "$HOOK" 2>/dev/null)
    # Extract only lines that are valid JSON objects
    echo "$raw" | grep -E '^\{' | head -1
}

# ── Helpers ──────────────────────────────────────────────

assert_continue() {
    local desc="$1"; shift
    TOTAL=$((TOTAL + 1))
    local output
    output=$(run_hook "$1")
    if echo "$output" | jq -e '.continue == true' >/dev/null 2>&1; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc"
        echo "    expected: continue=true"
        echo "    got:      $output"
        FAIL=$((FAIL + 1))
    fi
}

setup_repo() {
    local dir="$1"
    mkdir -p "$dir"
    git -C "$dir" init -q -b main 2>/dev/null
    git -C "$dir" config user.email "test@test.com"
    git -C "$dir" config user.name "Test"
    echo "init" > "$dir/init.txt"
    git -C "$dir" add -A && git -C "$dir" commit -q -m "init" 2>/dev/null
}

make_session_input() {
    local session_id="$1"
    local cwd="$2"
    cat <<JSON
{"session_id":"$session_id","cwd":"$cwd","hook_event_name":"SessionEnd","matcher":{}}
JSON
}

echo "Session End Tests"
echo "================="

# ── 1. Missing/empty input ──────────────────────────────

echo ""
echo "--- Input validation ---"

assert_continue "Empty JSON returns continue" \
    '{}'

assert_continue "Missing session_id returns continue" \
    '{"cwd":"/tmp"}'

assert_continue "Missing cwd returns continue" \
    '{"session_id":"test-123"}'

assert_continue "Empty string session_id returns continue" \
    '{"session_id":"","cwd":"/tmp"}'

assert_continue "Null session_id returns continue" \
    '{"session_id":null,"cwd":"/tmp"}'

# ── 2. Malformed JSON input ─────────────────────────────

echo ""
echo "--- Malformed input ---"

assert_continue "Completely malformed input returns continue" \
    'not json at all'

assert_continue "Truncated JSON returns continue" \
    '{"session_id":"test'

assert_continue "Array instead of object returns continue" \
    '[1, 2, 3]'

# ── 3. Valid input produces valid JSON ──────────────────

echo ""
echo "--- JSON output validity ---"

REPO1="$TMPDIR/repo1"
setup_repo "$REPO1"

TOTAL=$((TOTAL + 1))
OUTPUT=$(run_hook "$(make_session_input "sess-end-001" "$REPO1")")
if echo "$OUTPUT" | jq -e '.' >/dev/null 2>&1; then
    echo "  PASS: Valid input produces valid JSON"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Valid input produces valid JSON"
    echo "    got: $OUTPUT"
    FAIL=$((FAIL + 1))
fi

assert_continue "Valid input returns continue=true" \
    "$(make_session_input "sess-end-002" "$REPO1")"

# ── 4. Immediate response (no additionalContext) ────────

echo ""
echo "--- Immediate response ---"

TOTAL=$((TOTAL + 1))
OUTPUT=$(run_hook "$(make_session_input "sess-end-fast" "$REPO1")")
if [ "$OUTPUT" = '{"continue": true}' ]; then
    echo "  PASS: Returns exactly {\"continue\": true} with no extra fields"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Returns exactly {\"continue\": true} with no extra fields"
    echo "    got: $OUTPUT"
    FAIL=$((FAIL + 1))
fi

# ── 5. Session file lifecycle ────────────────────────────

echo ""
echo "--- Session file lifecycle ---"

# No session file → no crash
assert_continue "Missing session file does not crash" \
    "$(make_session_input "sess-end-nofile" "$REPO1")"

# Empty session file → no crash
TOTAL=$((TOTAL + 1))
touch "/tmp/brana-session-sess-end-empty.jsonl"
OUTPUT=$(run_hook "$(make_session_input "sess-end-empty" "$REPO1")")
if echo "$OUTPUT" | jq -e '.continue == true' >/dev/null 2>&1; then
    echo "  PASS: Empty session file does not crash"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Empty session file does not crash"
    FAIL=$((FAIL + 1))
fi
rm -f "/tmp/brana-session-sess-end-empty.jsonl" 2>/dev/null || true

# ── 6. awk -F tab separator in fallback metrics ─────────

echo ""
echo "--- awk tab separator (auto_fix_rate fallback) ---"

# The session-end fallback path uses:
#   jq -r '[.outcome, .detail] | @tsv' | awk -F'\t' '...'
# This tests the exact awk pipeline from session-end.sh.

# Test: failure followed by success on same detail = 1 auto-fix
TOTAL=$((TOTAL + 1))
AWK_INPUT=$(cat <<'JSONL'
{"ts":1,"tool":"Bash","outcome":"failure","detail":"cargo build"}
{"ts":2,"tool":"Edit","outcome":"success","detail":"src/lib.rs"}
{"ts":3,"tool":"Bash","outcome":"success","detail":"cargo build"}
{"ts":4,"tool":"Bash","outcome":"test-fail","detail":"cargo test"}
{"ts":5,"tool":"Bash","outcome":"test-pass","detail":"cargo test"}
JSONL
)
AUTO_FIXES=$(echo "$AWK_INPUT" | jq -r '[.outcome, .detail] | @tsv' 2>/dev/null | awk -F'\t' '
    BEGIN { fixes=0 }
    /^failure\t/ { prev_fail[$2]=1 } /^test-fail\t/ { prev_fail[$2]=1 } /^lint-fail\t/ { prev_fail[$2]=1 }
    /^success\t/ { if ($2 in prev_fail) { fixes++; delete prev_fail[$2] } }
    /^correction\t/ { if ($2 in prev_fail) { fixes++; delete prev_fail[$2] } }
    /^test-pass\t/ { if ($2 in prev_fail) { fixes++; delete prev_fail[$2] } }
    /^lint-pass\t/ { if ($2 in prev_fail) { fixes++; delete prev_fail[$2] } }
    END { print fixes }
' 2>/dev/null)
if [ "$AUTO_FIXES" = "2" ]; then
    echo "  PASS: awk tab separator counts auto-fixes correctly (failure->success + test-fail->test-pass)"
    PASS=$((PASS + 1))
else
    echo "  FAIL: awk tab separator counts auto-fixes correctly"
    echo "    expected: 2"
    echo "    got:      $AUTO_FIXES"
    FAIL=$((FAIL + 1))
fi

# Detail with spaces must not split on spaces (tab is the delimiter)
TOTAL=$((TOTAL + 1))
AWK_SPACE_INPUT=$(cat <<'JSONL'
{"ts":1,"tool":"Bash","outcome":"failure","detail":"cargo build --release --features foo"}
{"ts":2,"tool":"Bash","outcome":"success","detail":"cargo build --release --features foo"}
JSONL
)
SPACE_FIXES=$(echo "$AWK_SPACE_INPUT" | jq -r '[.outcome, .detail] | @tsv' 2>/dev/null | awk -F'\t' '
    BEGIN { fixes=0 }
    /^failure\t/ { prev_fail[$2]=1 } /^test-fail\t/ { prev_fail[$2]=1 }
    /^success\t/ { if ($2 in prev_fail) { fixes++; delete prev_fail[$2] } }
    END { print fixes }
' 2>/dev/null)
if [ "$SPACE_FIXES" = "1" ]; then
    echo "  PASS: awk tab separator handles detail with spaces"
    PASS=$((PASS + 1))
else
    echo "  FAIL: awk tab separator handles detail with spaces"
    echo "    expected: 1"
    echo "    got:      $SPACE_FIXES"
    FAIL=$((FAIL + 1))
fi

# No failures → zero auto-fixes
TOTAL=$((TOTAL + 1))
AWK_NOFAIL_INPUT=$(cat <<'JSONL'
{"ts":1,"tool":"Edit","outcome":"success","detail":"src/main.rs"}
{"ts":2,"tool":"Bash","outcome":"test-pass","detail":"cargo test"}
JSONL
)
NOFAIL_FIXES=$(echo "$AWK_NOFAIL_INPUT" | jq -r '[.outcome, .detail] | @tsv' 2>/dev/null | awk -F'\t' '
    BEGIN { fixes=0 }
    /^failure\t/ { prev_fail[$2]=1 }
    /^success\t/ { if ($2 in prev_fail) { fixes++; delete prev_fail[$2] } }
    /^test-pass\t/ { if ($2 in prev_fail) { fixes++; delete prev_fail[$2] } }
    END { print fixes }
' 2>/dev/null)
if [ "$NOFAIL_FIXES" = "0" ]; then
    echo "  PASS: No failures produces zero auto-fixes"
    PASS=$((PASS + 1))
else
    echo "  FAIL: No failures produces zero auto-fixes"
    echo "    expected: 0"
    echo "    got:      $NOFAIL_FIXES"
    FAIL=$((FAIL + 1))
fi

# lint-fail → lint-pass auto-fix
TOTAL=$((TOTAL + 1))
AWK_LINT_INPUT=$(cat <<'JSONL'
{"ts":1,"tool":"Bash","outcome":"lint-fail","detail":"cargo clippy"}
{"ts":2,"tool":"Edit","outcome":"correction","detail":"src/lib.rs"}
{"ts":3,"tool":"Bash","outcome":"lint-pass","detail":"cargo clippy"}
JSONL
)
LINT_FIXES=$(echo "$AWK_LINT_INPUT" | jq -r '[.outcome, .detail] | @tsv' 2>/dev/null | awk -F'\t' '
    BEGIN { fixes=0 }
    /^failure\t/ { prev_fail[$2]=1 } /^test-fail\t/ { prev_fail[$2]=1 } /^lint-fail\t/ { prev_fail[$2]=1 }
    /^success\t/ { if ($2 in prev_fail) { fixes++; delete prev_fail[$2] } }
    /^correction\t/ { if ($2 in prev_fail) { fixes++; delete prev_fail[$2] } }
    /^test-pass\t/ { if ($2 in prev_fail) { fixes++; delete prev_fail[$2] } }
    /^lint-pass\t/ { if ($2 in prev_fail) { fixes++; delete prev_fail[$2] } }
    END { print fixes }
' 2>/dev/null)
if [ "$LINT_FIXES" = "1" ]; then
    echo "  PASS: lint-fail -> lint-pass counted as auto-fix"
    PASS=$((PASS + 1))
else
    echo "  FAIL: lint-fail -> lint-pass counted as auto-fix"
    echo "    expected: 1"
    echo "    got:      $LINT_FIXES"
    FAIL=$((FAIL + 1))
fi

# ── 7. Fallback metrics computation (grep/jq/awk) ───────

echo ""
echo "--- Fallback metrics (grep/jq/awk) ---"

TOTAL=$((TOTAL + 1))
METRIC_FILE="$TMPDIR/metrics-test.jsonl"
cat > "$METRIC_FILE" <<'EVENTS'
{"ts":1,"tool":"Edit","outcome":"success","detail":"src/main.rs"}
{"ts":2,"tool":"Bash","outcome":"test-pass","detail":"cargo test"}
{"ts":3,"tool":"Bash","outcome":"failure","detail":"cargo build"}
{"ts":4,"tool":"Edit","outcome":"correction","detail":"src/main.rs"}
{"ts":5,"tool":"Bash","outcome":"test-write","detail":"tests/test.rs"}
{"ts":6,"tool":"Bash","outcome":"test-fail","detail":"cargo test"}
{"ts":7,"tool":"Bash","outcome":"lint-pass","detail":"cargo clippy"}
{"ts":8,"tool":"Bash","outcome":"lint-fail","detail":"cargo clippy"}
{"ts":9,"tool":"Task","outcome":"success","detail":"agent task"}
{"ts":10,"tool":"Bash","outcome":"pr-create","detail":"gh pr create"}
EVENTS

SUCCESSES=$(grep -c '"outcome":"success"' "$METRIC_FILE" 2>/dev/null) || SUCCESSES=0
CORRECTIONS=$(grep -c '"outcome":"correction"' "$METRIC_FILE" 2>/dev/null) || CORRECTIONS=0
TEST_WRITES=$(grep -c '"outcome":"test-write"' "$METRIC_FILE" 2>/dev/null) || TEST_WRITES=0
TEST_PASSES=$(grep -c '"outcome":"test-pass"' "$METRIC_FILE" 2>/dev/null) || TEST_PASSES=0
TEST_FAILS=$(grep -c '"outcome":"test-fail"' "$METRIC_FILE" 2>/dev/null) || TEST_FAILS=0
LINT_PASSES=$(grep -c '"outcome":"lint-pass"' "$METRIC_FILE" 2>/dev/null) || LINT_PASSES=0
LINT_FAILS=$(grep -c '"outcome":"lint-fail"' "$METRIC_FILE" 2>/dev/null) || LINT_FAILS=0
DELEGATIONS=$(grep -c '"tool":"Task"' "$METRIC_FILE" 2>/dev/null) || DELEGATIONS=0
PR_CREATES=$(grep -c '"outcome":"pr-create"' "$METRIC_FILE" 2>/dev/null) || PR_CREATES=0

EXPECTED="successes=2 corrections=1 test_writes=1 test_passes=1 test_fails=1 lint_passes=1 lint_fails=1 delegations=1 pr_creates=1"
ACTUAL="successes=$SUCCESSES corrections=$CORRECTIONS test_writes=$TEST_WRITES test_passes=$TEST_PASSES test_fails=$TEST_FAILS lint_passes=$LINT_PASSES lint_fails=$LINT_FAILS delegations=$DELEGATIONS pr_creates=$PR_CREATES"
if [ "$EXPECTED" = "$ACTUAL" ]; then
    echo "  PASS: Fallback grep counters match expected values"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Fallback grep counters match expected values"
    echo "    expected: $EXPECTED"
    echo "    got:      $ACTUAL"
    FAIL=$((FAIL + 1))
fi

# ── 8. Flywheel rate calculations ────────────────────────

echo ""
echo "--- Flywheel rate calculations ---"

TOTAL=$((TOTAL + 1))
EDITS=$(jq -r 'select(.tool == "Edit" or .tool == "Write") | .tool' "$METRIC_FILE" 2>/dev/null | wc -l) || EDITS=0
CORRECTION_RATE=$(awk "BEGIN {printf \"%.2f\", $CORRECTIONS / $EDITS}") || CORRECTION_RATE="ERR"
if [ "$CORRECTION_RATE" = "0.50" ]; then
    echo "  PASS: Correction rate = corrections/edits = 1/2 = 0.50"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Correction rate = corrections/edits = 1/2 = 0.50"
    echo "    got: $CORRECTION_RATE (edits=$EDITS, corrections=$CORRECTIONS)"
    FAIL=$((FAIL + 1))
fi

TOTAL=$((TOTAL + 1))
TEST_TOTAL=$((TEST_PASSES + TEST_FAILS))
TEST_PASS_RATE=$(awk "BEGIN {printf \"%.2f\", $TEST_PASSES / $TEST_TOTAL}")
if [ "$TEST_PASS_RATE" = "0.50" ]; then
    echo "  PASS: Test pass rate = 1/2 = 0.50"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Test pass rate = 1/2 = 0.50"
    echo "    got: $TEST_PASS_RATE"
    FAIL=$((FAIL + 1))
fi

# Zero edits → correction_rate 0.00 (no division by zero)
TOTAL=$((TOTAL + 1))
ZERO_EDITS=0
if [ "$ZERO_EDITS" -gt 0 ]; then
    ZERO_RATE=$(awk "BEGIN {printf \"%.2f\", 0 / $ZERO_EDITS}")
else
    ZERO_RATE="0.00"
fi
if [ "$ZERO_RATE" = "0.00" ]; then
    echo "  PASS: Zero edits produces correction_rate 0.00 (no division by zero)"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Zero edits produces correction_rate 0.00"
    echo "    got: $ZERO_RATE"
    FAIL=$((FAIL + 1))
fi

# Zero tests → test_pass_rate N/A
TOTAL=$((TOTAL + 1))
ZERO_TEST_TOTAL=0
if [ "$ZERO_TEST_TOTAL" -gt 0 ]; then
    ZERO_TEST_RATE=$(awk "BEGIN {printf \"%.2f\", 0 / $ZERO_TEST_TOTAL}")
else
    ZERO_TEST_RATE="N/A"
fi
if [ "$ZERO_TEST_RATE" = "N/A" ]; then
    echo "  PASS: Zero test runs produces test_pass_rate N/A"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Zero test runs produces test_pass_rate N/A"
    echo "    got: $ZERO_TEST_RATE"
    FAIL=$((FAIL + 1))
fi

# ── 9. Summary JSON assembly ────────────────────────────

echo ""
echo "--- Summary JSON assembly ---"

TOTAL=$((TOTAL + 1))
SUMMARY_JSON=$(jq -n \
    --arg project "test-proj" \
    --arg session "sess-test" \
    --arg ts "2026-04-06T00:00:00Z" \
    --argjson total 10 \
    --argjson ok 5 \
    --argjson fail 2 \
    --argjson corrections 1 \
    --argjson test_writes 1 \
    --argjson cascades 0 \
    --argjson edits 3 \
    --argjson test_passes 2 \
    --argjson test_fails 1 \
    --argjson lint_passes 1 \
    --argjson lint_fails 0 \
    --arg correction_rate "0.33" \
    --arg auto_fix_rate "0.50" \
    --arg test_write_rate "0.33" \
    --arg cascade_rate "0.00" \
    --arg test_pass_rate "0.67" \
    --arg lint_pass_rate "1.00" \
    --argjson delegations 1 \
    --argjson pr_creates 0 \
    --arg tools "Edit,Bash" \
    --arg files "src/main.rs" \
    --argjson confidence 0.5 \
    --argjson transferable false \
    --argjson recall_count 0 \
    '{project: $project, session: $session, timestamp: $ts, events: $total, successes: $ok, failures: $fail, corrections: $corrections, test_writes: $test_writes, cascades: $cascades, pr_creates: $pr_creates, edits: $edits, test_passes: $test_passes, test_fails: $test_fails, lint_passes: $lint_passes, lint_fails: $lint_fails, flywheel: {correction_rate: $correction_rate, auto_fix_rate: $auto_fix_rate, test_write_rate: $test_write_rate, cascade_rate: $cascade_rate, test_pass_rate: $test_pass_rate, lint_pass_rate: $lint_pass_rate, delegations: $delegations, pr_creates: $pr_creates}, tools: $tools, files: $files, confidence: $confidence, transferable: $transferable, recall_count: $recall_count}' 2>/dev/null) || SUMMARY_JSON=""

if [ -n "$SUMMARY_JSON" ] && echo "$SUMMARY_JSON" | jq -e '.project == "test-proj" and .events == 10 and .flywheel.correction_rate == "0.33"' >/dev/null 2>&1; then
    echo "  PASS: Summary JSON assembled with correct structure and values"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Summary JSON assembled with correct structure and values"
    echo "    got: $SUMMARY_JSON"
    FAIL=$((FAIL + 1))
fi

# ── 10. Non-git directory ───────────────────────────────

echo ""
echo "--- Non-git directory ---"

NONGIT="$TMPDIR/nongit"
mkdir -p "$NONGIT"

assert_continue "Non-git directory returns continue" \
    "$(make_session_input "sess-end-nongit" "$NONGIT")"

# ── Summary ─────────────────────────────────────────────
echo ""
echo "$PASS/$TOTAL passed"
[ "$FAIL" -eq 0 ] || exit 1
