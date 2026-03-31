#!/usr/bin/env bash
# Tests for subagent-tracker.sh hook
# Simulates SubagentStart/Stop JSON input and verifies JSONL output.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/../subagent-tracker.sh"
PASS=0
FAIL=0
TMPDIR=$(mktemp -d)

trap 'rm -rf "$TMPDIR"' EXIT

# Helper: assert JSONL file contains a line matching a jq filter
assert_jsonl_match() {
    local desc="$1" file="$2" filter="$3"
    if [ ! -f "$file" ]; then
        echo "  FAIL: $desc — JSONL file not found: $file"
        ((FAIL++))
        return
    fi
    if jq -e "$filter" "$file" >/dev/null 2>&1; then
        echo "  PASS: $desc"
        ((PASS++))
    else
        echo "  FAIL: $desc — no line matches filter: $filter"
        echo "  File contents:"
        cat "$file" 2>/dev/null | head -5
        ((FAIL++))
    fi
}

assert_jsonl_line_count() {
    local desc="$1" file="$2" expected="$3"
    local actual
    actual=$(wc -l < "$file" 2>/dev/null | tr -d ' ')
    if [ "$actual" = "$expected" ]; then
        echo "  PASS: $desc"
        ((PASS++))
    else
        echo "  FAIL: $desc — expected $expected lines, got $actual"
        ((FAIL++))
    fi
}

assert_hook_continues() {
    local desc="$1" result="$2"
    if echo "$result" | jq -e '.continue == true' >/dev/null 2>&1; then
        echo "  PASS: $desc"
        ((PASS++))
    else
        echo "  FAIL: $desc — expected continue:true, got: $result"
        ((FAIL++))
    fi
}

echo "Subagent Tracker Tests"
echo "======================"

# Use a unique session ID per test run
TEST_SESSION="test-$$"
SESSION_FILE="/tmp/brana-session-${TEST_SESSION}.jsonl"
rm -f "$SESSION_FILE" 2>/dev/null

# --- Test 1: SubagentStart logs spawn event ---
echo ""
echo "Test 1: SubagentStart logs spawn event"
START_INPUT=$(cat <<JSON
{"session_id":"$TEST_SESSION","agent_id":"agent-001","agent_type":"scout","agent_name":"research-scout","hook_event_name":"SubagentStart"}
JSON
)
RESULT=$(echo "$START_INPUT" | bash "$HOOK" 2>/dev/null)
assert_hook_continues "SubagentStart returns continue:true" "$RESULT"
assert_jsonl_match "JSONL has spawn event" "$SESSION_FILE" \
    'select(.event == "subagent-start" and .agent_type == "scout" and .agent_id == "agent-001")'

# --- Test 2: SubagentStop logs completion event ---
echo ""
echo "Test 2: SubagentStop logs completion event"
STOP_INPUT=$(cat <<JSON
{"session_id":"$TEST_SESSION","agent_id":"agent-001","agent_type":"scout","agent_name":"research-scout","hook_event_name":"SubagentStop"}
JSON
)
RESULT=$(echo "$STOP_INPUT" | bash "$HOOK" 2>/dev/null)
assert_hook_continues "SubagentStop returns continue:true" "$RESULT"
assert_jsonl_match "JSONL has stop event" "$SESSION_FILE" \
    'select(.event == "subagent-stop" and .agent_id == "agent-001")'

# --- Test 3: Two events produce two lines ---
echo ""
echo "Test 3: Line count matches event count"
assert_jsonl_line_count "JSONL has exactly 2 lines" "$SESSION_FILE" "2"

# --- Test 4: Missing session_id still works (uses fallback) ---
echo ""
echo "Test 4: Missing session_id uses fallback"
FALLBACK_INPUT='{"agent_id":"agent-002","agent_type":"explorer","hook_event_name":"SubagentStart"}'
RESULT=$(echo "$FALLBACK_INPUT" | bash "$HOOK" 2>/dev/null)
assert_hook_continues "Missing session_id returns continue:true" "$RESULT"
# Should write to a fallback session file
FALLBACK_FILE="/tmp/brana-session-unknown.jsonl"
if [ -f "$FALLBACK_FILE" ]; then
    assert_jsonl_match "Fallback file has event" "$FALLBACK_FILE" \
        'select(.event == "subagent-start" and .agent_type == "explorer")'
    rm -f "$FALLBACK_FILE" 2>/dev/null
else
    echo "  FAIL: Missing session_id — no fallback file created"
    ((FAIL++))
fi

# --- Test 5: Empty input produces continue:true and no crash ---
echo ""
echo "Test 5: Empty input does not crash"
RESULT=$(echo '{}' | bash "$HOOK" 2>/dev/null)
assert_hook_continues "Empty input returns continue:true" "$RESULT"

# --- Test 6: Multiple agents tracked in same session ---
echo ""
echo "Test 6: Multiple agents in same session"
MULTI_SESSION="test-multi-$$"
MULTI_FILE="/tmp/brana-session-${MULTI_SESSION}.jsonl"
rm -f "$MULTI_FILE" 2>/dev/null

for i in 1 2 3; do
    echo "{\"session_id\":\"$MULTI_SESSION\",\"agent_id\":\"agent-m$i\",\"agent_type\":\"scout\",\"hook_event_name\":\"SubagentStart\"}" \
        | bash "$HOOK" >/dev/null 2>&1
    echo "{\"session_id\":\"$MULTI_SESSION\",\"agent_id\":\"agent-m$i\",\"agent_type\":\"scout\",\"hook_event_name\":\"SubagentStop\"}" \
        | bash "$HOOK" >/dev/null 2>&1
done

assert_jsonl_line_count "6 events for 3 agents (start+stop each)" "$MULTI_FILE" "6"
rm -f "$MULTI_FILE" 2>/dev/null

# --- Cleanup ---
rm -f "$SESSION_FILE" 2>/dev/null

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
