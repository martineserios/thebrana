#!/usr/bin/env bash
# Tests for post-tool-use.sh and post-tool-use-failure.sh
# Validates test/lint command detection and outcome tagging.
set -euo pipefail

HOOKS_DIR="$(cd "$(dirname "$0")/../../system/hooks" && pwd)"
PASS=0
FAIL=0
SESSION_ID="test-$$"
SESSION_FILE="/tmp/brana-session-${SESSION_ID}.jsonl"

cleanup() { rm -f "$SESSION_FILE"; }
trap cleanup EXIT

assert_outcome() {
    local label="$1" expected="$2" actual="$3"
    if [ "$actual" = "$expected" ]; then
        PASS=$((PASS + 1))
        echo "  PASS: $label"
    else
        FAIL=$((FAIL + 1))
        echo "  FAIL: $label — expected '$expected', got '$actual'"
    fi
}

run_success_hook() {
    local tool="$1" command="$2"
    rm -f "$SESSION_FILE"
    local input
    input=$(jq -n -c --arg sid "$SESSION_ID" --arg tool "$tool" \
        --arg cmd "$command" \
        '{session_id: $sid, tool_name: $tool, tool_input: ({command: $cmd} | tostring)}')
    echo "$input" | bash "$HOOKS_DIR/post-tool-use.sh" >/dev/null 2>&1
    jq -r '.outcome' "$SESSION_FILE" 2>/dev/null | tail -1
}

run_failure_hook() {
    local tool="$1" command="$2"
    rm -f "$SESSION_FILE"
    local input
    input=$(jq -n -c --arg sid "$SESSION_ID" --arg tool "$tool" \
        --arg cmd "$command" \
        '{session_id: $sid, tool_name: $tool, tool_input: ({command: $cmd} | tostring)}')
    echo "$input" | bash "$HOOKS_DIR/post-tool-use-failure.sh" >/dev/null 2>&1
    jq -r '.outcome' "$SESSION_FILE" 2>/dev/null | tail -1
}

echo "=== post-tool-use.sh (success path) ==="

echo "Test commands → test-pass:"
assert_outcome "npm test" "test-pass" "$(run_success_hook Bash "npm test")"
assert_outcome "npx jest" "test-pass" "$(run_success_hook Bash "npx jest")"
assert_outcome "npx vitest" "test-pass" "$(run_success_hook Bash "npx vitest")"
assert_outcome "bun test" "test-pass" "$(run_success_hook Bash "bun test")"
assert_outcome "pytest" "test-pass" "$(run_success_hook Bash "pytest")"
assert_outcome "python -m pytest" "test-pass" "$(run_success_hook Bash "python -m pytest")"
assert_outcome "cargo test" "test-pass" "$(run_success_hook Bash "cargo test")"
assert_outcome "go test" "test-pass" "$(run_success_hook Bash "go test ./...")"
assert_outcome "make test" "test-pass" "$(run_success_hook Bash "make test")"
assert_outcome "./validate.sh" "test-pass" "$(run_success_hook Bash "./validate.sh")"

echo ""
echo "Lint commands → lint-pass:"
assert_outcome "eslint" "lint-pass" "$(run_success_hook Bash "eslint src/")"
assert_outcome "flake8" "lint-pass" "$(run_success_hook Bash "flake8 .")"
assert_outcome "ruff check" "lint-pass" "$(run_success_hook Bash "ruff check")"
assert_outcome "pylint" "lint-pass" "$(run_success_hook Bash "pylint module.py")"
assert_outcome "cargo clippy" "lint-pass" "$(run_success_hook Bash "cargo clippy")"
assert_outcome "shellcheck" "lint-pass" "$(run_success_hook Bash "shellcheck script.sh")"
assert_outcome "biome check" "lint-pass" "$(run_success_hook Bash "biome check")"
assert_outcome "npm run lint" "lint-pass" "$(run_success_hook Bash "npm run lint")"
assert_outcome "npx eslint" "lint-pass" "$(run_success_hook Bash "npx eslint .")"

echo ""
echo "Regular commands → success:"
assert_outcome "ls" "success" "$(run_success_hook Bash "ls -la")"
assert_outcome "git status" "success" "$(run_success_hook Bash "git status")"
assert_outcome "echo test" "success" "$(run_success_hook Bash "echo test")"

echo ""
echo "Non-Bash tools → success:"
assert_outcome "Edit tool" "success" "$(run_success_hook Edit "/tmp/foo.txt")"

echo ""
echo "=== post-tool-use-failure.sh (failure path) ==="

echo "Test commands → test-fail:"
assert_outcome "npm test fail" "test-fail" "$(run_failure_hook Bash "npm test")"
assert_outcome "pytest fail" "test-fail" "$(run_failure_hook Bash "pytest")"
assert_outcome "cargo test fail" "test-fail" "$(run_failure_hook Bash "cargo test")"

echo ""
echo "Lint commands → lint-fail:"
assert_outcome "eslint fail" "lint-fail" "$(run_failure_hook Bash "eslint src/")"
assert_outcome "shellcheck fail" "lint-fail" "$(run_failure_hook Bash "shellcheck script.sh")"
assert_outcome "ruff check fail" "lint-fail" "$(run_failure_hook Bash "ruff check")"

echo ""
echo "Regular commands → failure:"
assert_outcome "ls fail" "failure" "$(run_failure_hook Bash "ls nonexistent")"
assert_outcome "git fail" "failure" "$(run_failure_hook Bash "git push")"

echo ""
echo "Non-Bash tools → failure:"
assert_outcome "Edit fail" "failure" "$(run_failure_hook Edit "/tmp/foo.txt")"

echo ""
echo "=== session-end.sh aggregation ==="

# Build a session file with known outcomes, then run session-end
rm -f "$SESSION_FILE"
TS=$(date +%s)
for outcome in test-pass test-pass test-fail lint-pass lint-fail success failure; do
    jq -n -c --argjson ts "$TS" --arg tool "Bash" --arg outcome "$outcome" --arg detail "cmd-$outcome" \
        '{ts: $ts, tool: $tool, outcome: $outcome, detail: $detail}' >> "$SESSION_FILE"
done

TEST_PASSES=$(grep -c '"outcome":"test-pass"' "$SESSION_FILE") || TEST_PASSES=0
TEST_FAILS=$(grep -c '"outcome":"test-fail"' "$SESSION_FILE") || TEST_FAILS=0
LINT_PASSES=$(grep -c '"outcome":"lint-pass"' "$SESSION_FILE") || LINT_PASSES=0
LINT_FAILS=$(grep -c '"outcome":"lint-fail"' "$SESSION_FILE") || LINT_FAILS=0

assert_outcome "test-pass count" "2" "$TEST_PASSES"
assert_outcome "test-fail count" "1" "$TEST_FAILS"
assert_outcome "lint-pass count" "1" "$LINT_PASSES"
assert_outcome "lint-fail count" "1" "$LINT_FAILS"

TEST_TOTAL=$((TEST_PASSES + TEST_FAILS))
if [ "$TEST_TOTAL" -gt 0 ]; then
    TEST_PASS_RATE=$(awk "BEGIN {printf \"%.2f\", $TEST_PASSES / $TEST_TOTAL}")
else
    TEST_PASS_RATE="N/A"
fi
LINT_TOTAL=$((LINT_PASSES + LINT_FAILS))
if [ "$LINT_TOTAL" -gt 0 ]; then
    LINT_PASS_RATE=$(awk "BEGIN {printf \"%.2f\", $LINT_PASSES / $LINT_TOTAL}")
else
    LINT_PASS_RATE="N/A"
fi

assert_outcome "test_pass_rate" "0.67" "$TEST_PASS_RATE"
assert_outcome "lint_pass_rate" "0.50" "$LINT_PASS_RATE"

# Zero-total → N/A
rm -f "$SESSION_FILE"
jq -n -c --argjson ts "$TS" --arg tool "Bash" --arg outcome "success" --arg detail "ls" \
    '{ts: $ts, tool: $tool, outcome: $outcome, detail: $detail}' >> "$SESSION_FILE"
ZERO_TEST_PASSES=$(grep -c '"outcome":"test-pass"' "$SESSION_FILE" 2>/dev/null) || ZERO_TEST_PASSES=0
ZERO_TEST_FAILS=$(grep -c '"outcome":"test-fail"' "$SESSION_FILE" 2>/dev/null) || ZERO_TEST_FAILS=0
ZERO_TOTAL=$((ZERO_TEST_PASSES + ZERO_TEST_FAILS))
if [ "$ZERO_TOTAL" -gt 0 ]; then
    ZERO_RATE=$(awk "BEGIN {printf \"%.2f\", $ZERO_TEST_PASSES / $ZERO_TOTAL}")
else
    ZERO_RATE="N/A"
fi
assert_outcome "zero tests → N/A" "N/A" "$ZERO_RATE"

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
