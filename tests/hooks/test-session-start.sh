#!/usr/bin/env bash
# Tests for session-start.sh — validates JSON output, additionalContext injection,
# and that the hook completes within timeout bounds.
#
# TDD markers:
#   [BUG]     = tests expected to fail, exposing a known bug
#   [MISSING] = tests expected to fail, exposing missing coverage
#
set -euo pipefail

HOOKS_DIR="$(cd "$(dirname "$0")/../../system/hooks" && pwd)"
PASS=0
FAIL=0
SESSION_ID="test-ss-$$"

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

assert_contains() {
    local label="$1" haystack="$2" needle="$3"
    if echo "$haystack" | grep -qF "$needle"; then
        PASS=$((PASS + 1))
        echo "  PASS: $label"
    else
        FAIL=$((FAIL + 1))
        echo "  FAIL: $label — output does not contain '$needle'"
    fi
}

assert_valid_json() {
    local label="$1" json="$2"
    if echo "$json" | jq -e '.' >/dev/null 2>&1; then
        PASS=$((PASS + 1))
        echo "  PASS: $label"
    else
        FAIL=$((FAIL + 1))
        echo "  FAIL: $label — invalid JSON: $json"
    fi
}

assert_timing() {
    local label="$1" elapsed="$2" max_ms="$3"
    if [ "$elapsed" -le "$max_ms" ]; then
        PASS=$((PASS + 1))
        echo "  PASS: $label (${elapsed}ms <= ${max_ms}ms)"
    else
        FAIL=$((FAIL + 1))
        echo "  FAIL: $label — took ${elapsed}ms, max ${max_ms}ms"
    fi
}

run_hook() {
    local input="$1"
    echo "$input" | bash "$HOOKS_DIR/session-start.sh" 2>/dev/null
}

run_hook_timed() {
    local input="$1"
    local start_ms end_ms elapsed output
    start_ms=$(date +%s%3N 2>/dev/null || echo 0)
    output=$(echo "$input" | bash "$HOOKS_DIR/session-start.sh" 2>/dev/null)
    end_ms=$(date +%s%3N 2>/dev/null || echo 0)
    elapsed=$((end_ms - start_ms))
    echo "$elapsed|$output"
}

echo "=== session-start.sh tests ==="
echo ""

# ── Test 1: Empty input returns valid JSON with continue:true ──
echo "Test 1: empty/missing input"
OUTPUT=$(run_hook '{}')
assert_valid_json "empty input → valid JSON" "$OUTPUT"
CONTINUE=$(echo "$OUTPUT" | jq -r '.continue' 2>/dev/null) || CONTINUE=""
assert_outcome "empty input → continue:true" "true" "$CONTINUE"

# ── Test 2: Missing session_id returns early ──
echo ""
echo "Test 2: missing session_id"
OUTPUT=$(run_hook '{"cwd": "/tmp"}')
assert_valid_json "missing session_id → valid JSON" "$OUTPUT"
CONTINUE=$(echo "$OUTPUT" | jq -r '.continue' 2>/dev/null) || CONTINUE=""
assert_outcome "missing session_id → continue:true" "true" "$CONTINUE"

# ── Test 3: Valid input with real CWD produces valid JSON ──
echo ""
echo "Test 3: valid input with CWD=$(pwd)"
INPUT=$(jq -n --arg sid "$SESSION_ID" --arg cwd "$(pwd)" '{session_id: $sid, cwd: $cwd}')
OUTPUT=$(run_hook "$INPUT")
assert_valid_json "valid input → valid JSON" "$OUTPUT"
CONTINUE=$(echo "$OUTPUT" | jq -r '.continue' 2>/dev/null) || CONTINUE=""
assert_outcome "valid input → continue:true" "true" "$CONTINUE"

# ── Test 4: additionalContext is string or null (never object) ──
echo ""
echo "Test 4: additionalContext type"
AC_TYPE=$(echo "$OUTPUT" | jq -r '.additionalContext | type' 2>/dev/null) || AC_TYPE="null"
if [ "$AC_TYPE" = "string" ] || [ "$AC_TYPE" = "null" ]; then
    PASS=$((PASS + 1))
    echo "  PASS: additionalContext is $AC_TYPE"
else
    FAIL=$((FAIL + 1))
    echo "  FAIL: additionalContext is '$AC_TYPE', expected string or null"
fi

# ── Test 5: Task context injected when tasks.json exists ──
echo ""
echo "Test 5: task context injection"
if [ -f "$(git rev-parse --show-toplevel 2>/dev/null)/.claude/tasks.json" ]; then
    AC=$(echo "$OUTPUT" | jq -r '.additionalContext // ""' 2>/dev/null) || AC=""
    assert_contains "tasks.json present → task context in output" "$AC" "[Active tasks]"
else
    echo "  SKIP: no tasks.json in project"
fi

# ── Test 6: Hook completes within 8s (budget for parallel CF searches) ──
echo ""
echo "Test 6: timing (must complete within 8000ms)"
INPUT=$(jq -n --arg sid "$SESSION_ID-timing" --arg cwd "$(pwd)" '{session_id: $sid, cwd: $cwd}')
RESULT=$(run_hook_timed "$INPUT")
ELAPSED="${RESULT%%|*}"
TIMED_OUTPUT="${RESULT#*|}"
assert_timing "hook completes within budget" "$ELAPSED" "8000"
assert_valid_json "timed run → valid JSON" "$TIMED_OUTPUT"

# ── Test 7: Non-git directory still works ──
echo ""
echo "Test 7: non-git directory"
INPUT=$(jq -n --arg sid "$SESSION_ID-nongit" --arg cwd "/tmp" '{session_id: $sid, cwd: $cwd}')
OUTPUT=$(run_hook "$INPUT")
assert_valid_json "non-git dir → valid JSON" "$OUTPUT"

# ── Cleanup ──
rm -f "/tmp/brana-session-${SESSION_ID}.jsonl" "/tmp/brana-session-${SESSION_ID}-timing.jsonl" "/tmp/brana-session-${SESSION_ID}-nongit.jsonl"

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
exit $FAIL
