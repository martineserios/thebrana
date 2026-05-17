#!/usr/bin/env bash
# Tests for post-tool-use.sh — test signal parsing (t-467)
# Verifies that actual test runner output (tool_response) is parsed to
# set outcome=test-pass/test-fail and populate test_pass/test_fail counts.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/../post-tool-use.sh"
PASS=0; FAIL=0; TOTAL=0
SESSION_ID="test-signal-$(date +%s)"
SESSION_FILE="/tmp/brana-session-${SESSION_ID}.jsonl"
trap 'rm -f "$SESSION_FILE"' EXIT

assert() {
    local desc="$1" result="$2" expected="$3"
    TOTAL=$((TOTAL + 1))
    if [ "$result" = "$expected" ]; then
        echo "  PASS: $desc"; PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc"; echo "    expected: $expected"; echo "    got:      $result"
        FAIL=$((FAIL + 1))
    fi
}

run_hook() {
    local input="$1"
    rm -f "$SESSION_FILE"
    echo "$input" | bash "$HOOK" 2>/dev/null
    sleep 0.05
}

last_event_field() {
    local field="$1"
    tail -1 "$SESSION_FILE" 2>/dev/null | jq -r ".${field} // empty" 2>/dev/null
}

echo "Post Tool Use — test signal parsing (t-467)"
echo "============================================"

CARGO_PASS_OUTPUT="running 23 tests\ntest foo ... ok\ntest bar ... ok\n\ntest result: ok. 23 passed; 0 failed; 0 ignored; 0 measured"
CARGO_FAIL_OUTPUT="running 23 tests\ntest foo ... ok\ntest bar ... FAILED\n\ntest result: FAILED. 22 passed; 1 failed; 0 ignored; 0 measured"

PYTEST_PASS_OUTPUT="collected 12 items\n\ntest_main.py ............\n\n====== 12 passed in 0.42s ======"
PYTEST_FAIL_OUTPUT="collected 12 items\n\ntest_main.py ...F........\n\n====== 1 failed, 11 passed in 0.55s ======"

JEST_PASS_OUTPUT="Tests:       5 passed, 5 total\nTest Suites: 1 passed, 1 total\nTime:        1.2s"
JEST_FAIL_OUTPUT="Tests:       1 failed, 4 passed, 5 total\nTest Suites: 1 failed, 1 total"

echo ""
echo "--- cargo test: all pass ---"
INPUT=$(jq -n \
    --arg sid "$SESSION_ID" \
    --arg out "$(printf "$CARGO_PASS_OUTPUT")" \
    '{session_id: $sid, tool_name: "Bash",
      tool_input: {command: "cargo test"},
      tool_response: {content: $out},
      cwd: "/tmp"}')
run_hook "$INPUT" >/dev/null
assert "cargo pass → outcome=test-pass"  "$(last_event_field outcome)"    "test-pass"
assert "cargo pass → test_pass=23"       "$(last_event_field test_pass)"  "23"
assert "cargo pass → test_fail=0"        "$(last_event_field test_fail)"  "0"

echo ""
echo "--- cargo test: failures ---"
INPUT=$(jq -n \
    --arg sid "$SESSION_ID" \
    --arg out "$(printf "$CARGO_FAIL_OUTPUT")" \
    '{session_id: $sid, tool_name: "Bash",
      tool_input: {command: "cargo test"},
      tool_response: {content: $out},
      cwd: "/tmp"}')
run_hook "$INPUT" >/dev/null
assert "cargo fail → outcome=test-fail"  "$(last_event_field outcome)"    "test-fail"
assert "cargo fail → test_pass=22"       "$(last_event_field test_pass)"  "22"
assert "cargo fail → test_fail=1"        "$(last_event_field test_fail)"  "1"

echo ""
echo "--- pytest: all pass ---"
INPUT=$(jq -n \
    --arg sid "$SESSION_ID" \
    --arg out "$(printf "$PYTEST_PASS_OUTPUT")" \
    '{session_id: $sid, tool_name: "Bash",
      tool_input: {command: "uv run pytest"},
      tool_response: {content: $out},
      cwd: "/tmp"}')
run_hook "$INPUT" >/dev/null
assert "pytest pass → outcome=test-pass" "$(last_event_field outcome)"    "test-pass"
assert "pytest pass → test_pass=12"      "$(last_event_field test_pass)"  "12"
assert "pytest pass → test_fail=0"       "$(last_event_field test_fail)"  "0"

echo ""
echo "--- pytest: failures ---"
INPUT=$(jq -n \
    --arg sid "$SESSION_ID" \
    --arg out "$(printf "$PYTEST_FAIL_OUTPUT")" \
    '{session_id: $sid, tool_name: "Bash",
      tool_input: {command: "uv run pytest -v"},
      tool_response: {content: $out},
      cwd: "/tmp"}')
run_hook "$INPUT" >/dev/null
assert "pytest fail → outcome=test-fail" "$(last_event_field outcome)"    "test-fail"
assert "pytest fail → test_pass=11"      "$(last_event_field test_pass)"  "11"
assert "pytest fail → test_fail=1"       "$(last_event_field test_fail)"  "1"

echo ""
echo "--- jest: all pass ---"
INPUT=$(jq -n \
    --arg sid "$SESSION_ID" \
    --arg out "$(printf "$JEST_PASS_OUTPUT")" \
    '{session_id: $sid, tool_name: "Bash",
      tool_input: {command: "npx jest"},
      tool_response: {content: $out},
      cwd: "/tmp"}')
run_hook "$INPUT" >/dev/null
assert "jest pass → outcome=test-pass"   "$(last_event_field outcome)"    "test-pass"
assert "jest pass → test_pass=5"         "$(last_event_field test_pass)"  "5"
assert "jest pass → test_fail=0"         "$(last_event_field test_fail)"  "0"

echo ""
echo "--- jest: failures ---"
INPUT=$(jq -n \
    --arg sid "$SESSION_ID" \
    --arg out "$(printf "$JEST_FAIL_OUTPUT")" \
    '{session_id: $sid, tool_name: "Bash",
      tool_input: {command: "npx jest --ci"},
      tool_response: {content: $out},
      cwd: "/tmp"}')
run_hook "$INPUT" >/dev/null
assert "jest fail → outcome=test-fail"   "$(last_event_field outcome)"    "test-fail"
assert "jest fail → test_fail=1"         "$(last_event_field test_fail)"  "1"

echo ""
echo "--- no tool_response: graceful fallback ---"
INPUT=$(jq -n \
    --arg sid "$SESSION_ID" \
    '{session_id: $sid, tool_name: "Bash",
      tool_input: {command: "cargo test"},
      cwd: "/tmp"}')
run_hook "$INPUT" >/dev/null
assert "no response → outcome=test-pass" "$(last_event_field outcome)"    "test-pass"
assert "no response → test_pass empty"   "$(last_event_field test_pass)"  ""

echo ""
echo "--- non-test Bash: no test_ fields ---"
INPUT=$(jq -n \
    --arg sid "$SESSION_ID" \
    '{session_id: $sid, tool_name: "Bash",
      tool_input: {command: "ls -la"},
      tool_response: {content: "total 8\n-rw-r--r-- 1 user user 0 foo"},
      cwd: "/tmp"}')
run_hook "$INPUT" >/dev/null
assert "ls → outcome=success"            "$(last_event_field outcome)"    "success"
assert "ls → test_pass empty"            "$(last_event_field test_pass)"  ""

echo ""
echo "============================================"
echo "Results: $PASS passed, $FAIL failed of $TOTAL total"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
