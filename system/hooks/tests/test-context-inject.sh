#!/usr/bin/env bash
# Tests for context-inject.sh (t-204)
# UserPromptSubmit hook: inject task context when prompt mentions t-NNN IDs.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/../context-inject.sh"
PASS=0; FAIL=0; TOTAL=0

assert_contains() {
    local desc="$1" output="$2" needle="$3"
    TOTAL=$((TOTAL + 1))
    if echo "$output" | grep -q "$needle"; then
        echo "  PASS: $desc"; PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc (expected '$needle')"
        echo "    got: $(echo "$output" | head -3)"
        FAIL=$((FAIL + 1))
    fi
}

assert_not_contains() {
    local desc="$1" output="$2" needle="$3"
    TOTAL=$((TOTAL + 1))
    if ! echo "$output" | grep -q "$needle"; then
        echo "  PASS: $desc"; PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc (unexpected '$needle')"
        echo "    got: $(echo "$output" | head -3)"
        FAIL=$((FAIL + 1))
    fi
}

assert_json_continue() {
    local desc="$1" output="$2"
    TOTAL=$((TOTAL + 1))
    if echo "$output" | jq -e '.continue == true' >/dev/null 2>&1; then
        echo "  PASS: $desc"; PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc (expected .continue == true)"
        echo "    got: $output"
        FAIL=$((FAIL + 1))
    fi
}

run_hook() {
    local input="$1"
    echo "$input" | bash "$HOOK" 2>/dev/null
}

echo "=== test-context-inject.sh ==="

echo ""
echo "--- Prompts without task IDs: fast passthrough ---"

OUT=$(run_hook '{"prompt":"what should I work on next?","session_id":"test-1"}')
assert_json_continue "no task ID: continue true" "$OUT"
assert_not_contains "no task ID: no additionalContext" "$OUT" "additionalContext"

OUT=$(run_hook '{"prompt":"fix the bug in the auth module","session_id":"test-1"}')
assert_json_continue "no task ID in fix prompt: continue true" "$OUT"
assert_not_contains "no task ID in fix: no context injection" "$OUT" "Task context"

OUT=$(run_hook '{"prompt":"","session_id":"test-1"}')
assert_json_continue "empty prompt: continue true" "$OUT"

echo ""
echo "--- Prompts with task IDs: context injected ---"

# Use a real existing task ID from the backlog
REAL_TASK=$(brana backlog query --status pending --json 2>/dev/null | jq -r 'first | .id' 2>/dev/null) || REAL_TASK=""

if [ -n "$REAL_TASK" ]; then
    OUT=$(run_hook "{\"prompt\":\"work on $REAL_TASK\",\"session_id\":\"test-2\"}")
    assert_json_continue "real task ID: continue true" "$OUT"
    assert_contains "real task ID: additionalContext injected" "$OUT" "additionalContext"
    assert_contains "real task ID: task ID in context" "$OUT" "$REAL_TASK"
else
    echo "  SKIP: no pending tasks to test with (backlog empty)"
fi

# Task ID mentioned in different positions
OUT=$(run_hook '{"prompt":"can you help me with t-999999 if it exists","session_id":"test-3"}')
assert_json_continue "nonexistent task ID: continue true" "$OUT"
# Nonexistent task should not crash, may or may not inject context

echo ""
echo "--- Multiple task IDs: all injected (capped) ---"

if [ -n "$REAL_TASK" ]; then
    OUT=$(run_hook "{\"prompt\":\"look at $REAL_TASK and also t-1\",\"session_id\":\"test-4\"}")
    assert_json_continue "multiple task IDs: continue true" "$OUT"
    assert_contains "multiple IDs: context present" "$OUT" "additionalContext"
fi

echo ""
echo "--- Non-prompt tool events: passthrough ---"

OUT=$(run_hook '{"tool_name":"Bash","tool_input":{"command":"ls"},"session_id":"test-5"}')
assert_json_continue "non-prompt event: continue true" "$OUT"

echo ""
echo "--- Injection cap: max 3 tasks ---"

OUT=$(run_hook '{"prompt":"check t-1 t-2 t-3 t-4 t-5 please","session_id":"test-6"}')
assert_json_continue "many task IDs: continue true" "$OUT"

echo ""
echo "Results: $PASS/$TOTAL passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1
exit 0
