#!/usr/bin/env bash
set -euo pipefail

# Layer 1: Hook Smoke Test
# Pipes fake JSON to each deployed hook script and verifies:
#   1. Exit code 0
#   2. Output is valid JSON
#   3. Output contains "continue": true
#
# Run AFTER deploy.sh — tests the deployed copies in ~/.claude/hooks/

HOOKS_DIR="$HOME/.claude/hooks"
ERRORS=0
PASSED=0

echo "=== Hook Smoke Test ==="
echo ""

fail() { echo "  FAIL: $1"; ERRORS=$((ERRORS + 1)); }
pass() { echo "  PASS: $1"; PASSED=$((PASSED + 1)); }

# Test helper: run a hook with given JSON input, check output
test_hook() {
    local script="$1"
    local input="$2"
    local name
    name=$(basename "$script")

    if [ ! -x "$script" ]; then
        fail "$name — not executable or missing"
        return
    fi

    # Run the hook, capture output and exit code
    local output
    local exit_code
    output=$(echo "$input" | timeout 10 bash "$script" 2>/dev/null) && exit_code=0 || exit_code=$?

    if [ "$exit_code" -ne 0 ]; then
        fail "$name — exited with code $exit_code"
        return
    fi

    if ! echo "$output" | jq . >/dev/null 2>&1; then
        fail "$name — output is not valid JSON: $output"
        return
    fi

    local continues
    continues=$(echo "$output" | jq -r '.continue // empty')
    if [ "$continues" != "true" ]; then
        fail "$name — missing 'continue: true' in output"
        return
    fi

    pass "$name — exit 0, valid JSON, continue: true"
}

# Fake session data
FAKE_SESSION_ID="test-$(date +%s)"
FAKE_CWD="$HOME"

# Test 1: session-start.sh
echo "Testing session-start..."
test_hook "$HOOKS_DIR/session-start.sh" "$(jq -n \
    --arg sid "$FAKE_SESSION_ID" \
    --arg cwd "$FAKE_CWD" \
    '{session_id: $sid, cwd: $cwd, hook_event_name: "SessionStart", matcher: ""}')"
echo ""

# Test 2: post-tool-use.sh
echo "Testing post-tool-use..."
test_hook "$HOOKS_DIR/post-tool-use.sh" "$(jq -n \
    --arg sid "$FAKE_SESSION_ID" \
    --arg tool "Bash" \
    --arg cwd "$FAKE_CWD" \
    '{session_id: $sid, tool_name: $tool, tool_input: "{\"command\": \"echo hello\"}", cwd: $cwd}')"
echo ""

# Test 3: post-tool-use-failure.sh
echo "Testing post-tool-use-failure..."
test_hook "$HOOKS_DIR/post-tool-use-failure.sh" "$(jq -n \
    --arg sid "$FAKE_SESSION_ID" \
    --arg tool "Bash" \
    --arg cwd "$FAKE_CWD" \
    '{session_id: $sid, tool_name: $tool, tool_input: "{\"command\": \"false\"}", cwd: $cwd}')"
echo ""

# Test 4: session-end.sh
# First, create a fake session file so session-end has something to flush
SESSION_FILE="/tmp/brana-session-${FAKE_SESSION_ID}.jsonl"
jq -n -c '{ts: 1234567890, tool: "Bash", outcome: "success", detail: "echo test"}' > "$SESSION_FILE"

echo "Testing session-end..."
test_hook "$HOOKS_DIR/session-end.sh" "$(jq -n \
    --arg sid "$FAKE_SESSION_ID" \
    --arg cwd "$FAKE_CWD" \
    '{session_id: $sid, cwd: $cwd, hook_event_name: "SessionEnd", matcher: ""}')"

# Clean up any leftover test artifacts
rm -f "$SESSION_FILE"
echo ""

# Summary
echo "=== Hook Smoke Summary ==="
echo "Passed: $PASSED"
echo "Failed: $ERRORS"
if [ "$ERRORS" -gt 0 ]; then
    echo "HOOK SMOKE TEST FAILED"
    exit 1
else
    echo "HOOK SMOKE TEST PASSED"
    exit 0
fi
