#!/usr/bin/env bash
# Regression test for t-1397: post-tool-use-failure.sh detail capture

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HOOK_FILE="$PROJECT_ROOT/system/hooks/post-tool-use-failure.sh"

# Test counters
PASS=0
FAIL=0

fail() {
    echo "❌ FAIL: $1"
    ((FAIL++)) || true
}

pass() {
    echo "✅ PASS: $1"
    ((PASS++)) || true
}

# Setup
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

SESSION_ID="test-$(date +%s)"

# ============================================================================
# Test 1: Read tool failure captures file_path
# ============================================================================
echo "Test 1: Read tool failure with file_path"

SESSION_FILE="/tmp/brana-session-${SESSION_ID}-1.jsonl"
rm -f "$SESSION_FILE"

READ_INPUT=$(jq -n \
    --arg session_id "${SESSION_ID}-1" \
    --arg tool_name "Read" \
    --argjson tool_input '{"file_path":"/home/test/example.md"}' \
    '{session_id: $session_id, tool_name: $tool_name, tool_input: $tool_input}')

echo "$READ_INPUT" | bash "$HOOK_FILE" 2>&1 > /dev/null
if [ -f "$SESSION_FILE" ]; then
    SESSION_ENTRY=$(tail -1 "$SESSION_FILE" 2>/dev/null || echo '{}')
    DETAIL=$(echo "$SESSION_ENTRY" | jq -r '.detail // empty' 2>/dev/null)

    if [ "$DETAIL" = "/home/test/example.md" ]; then
        pass "Read failure detail captured file_path: $DETAIL"
    else
        fail "Read failure detail should be '/home/test/example.md', got: '$DETAIL'"
    fi
    rm -f "$SESSION_FILE"
else
    fail "Session file not created"
fi

# ============================================================================
# Test 2: Write tool failure captures file_path
# ============================================================================
echo ""
echo "Test 2: Write tool failure with file_path"

SESSION_FILE="/tmp/brana-session-${SESSION_ID}-2.jsonl"
rm -f "$SESSION_FILE"

WRITE_INPUT=$(jq -n \
    --arg session_id "${SESSION_ID}-2" \
    --arg tool_name "Write" \
    --argjson tool_input '{"file_path":"/tmp/test-write.txt"}' \
    '{session_id: $session_id, tool_name: $tool_name, tool_input: $tool_input}')

echo "$WRITE_INPUT" | bash "$HOOK_FILE" 2>&1 > /dev/null
if [ -f "$SESSION_FILE" ]; then
    SESSION_ENTRY=$(tail -1 "$SESSION_FILE" 2>/dev/null || echo '{}')
    DETAIL=$(echo "$SESSION_ENTRY" | jq -r '.detail // empty' 2>/dev/null)

    if [ "$DETAIL" = "/tmp/test-write.txt" ]; then
        pass "Write failure detail captured file_path: $DETAIL"
    else
        fail "Write failure detail should be '/tmp/test-write.txt', got: '$DETAIL'"
    fi
    rm -f "$SESSION_FILE"
else
    fail "Session file not created"
fi

# ============================================================================
# Test 3: NotebookEdit tool failure captures notebook_path
# ============================================================================
echo ""
echo "Test 3: NotebookEdit tool failure with notebook_path"

SESSION_FILE="/tmp/brana-session-${SESSION_ID}-3.jsonl"
rm -f "$SESSION_FILE"

NOTEBOOK_INPUT=$(jq -n \
    --arg session_id "${SESSION_ID}-3" \
    --arg tool_name "NotebookEdit" \
    --argjson tool_input '{"notebook_path":"/abs/path/to/notebook.ipynb","cell_id":"abc123","new_source":"code"}' \
    '{session_id: $session_id, tool_name: $tool_name, tool_input: $tool_input}')

echo "$NOTEBOOK_INPUT" | bash "$HOOK_FILE" 2>&1 > /dev/null
if [ -f "$SESSION_FILE" ]; then
    SESSION_ENTRY=$(tail -1 "$SESSION_FILE" 2>/dev/null || echo '{}')
    DETAIL=$(echo "$SESSION_ENTRY" | jq -r '.detail // empty' 2>/dev/null)

    # NotebookEdit should use notebook_path, not fall back to TOOL_NAME
    if [ "$DETAIL" != "NotebookEdit" ] && [ -n "$DETAIL" ]; then
        pass "NotebookEdit failure detail not tool name fallback: $DETAIL"
    elif [ "$DETAIL" = "NotebookEdit" ]; then
        fail "NotebookEdit failure detail fell back to TOOL_NAME (should be notebook_path)"
    else
        fail "NotebookEdit failure detail empty"
    fi
    rm -f "$SESSION_FILE"
else
    fail "Session file not created"
fi

# ============================================================================
# Test 4: MultiEdit tool failure captures file_path
# ============================================================================
echo ""
echo "Test 4: MultiEdit tool failure with file_path"

SESSION_FILE="/tmp/brana-session-${SESSION_ID}-4.jsonl"
rm -f "$SESSION_FILE"

MULTI_INPUT=$(jq -n \
    --arg session_id "${SESSION_ID}-4" \
    --arg tool_name "MultiEdit" \
    --argjson tool_input '{"file_path":"/home/multi-edit-file.py"}' \
    '{session_id: $session_id, tool_name: $tool_name, tool_input: $tool_input}')

echo "$MULTI_INPUT" | bash "$HOOK_FILE" 2>&1 > /dev/null
if [ -f "$SESSION_FILE" ]; then
    SESSION_ENTRY=$(tail -1 "$SESSION_FILE" 2>/dev/null || echo '{}')
    DETAIL=$(echo "$SESSION_ENTRY" | jq -r '.detail // empty' 2>/dev/null)

    if [ "$DETAIL" != "MultiEdit" ] && [ -n "$DETAIL" ]; then
        pass "MultiEdit failure detail not tool name fallback: $DETAIL"
    elif [ "$DETAIL" = "MultiEdit" ]; then
        fail "MultiEdit failure detail fell back to TOOL_NAME"
    else
        fail "MultiEdit failure detail empty"
    fi
    rm -f "$SESSION_FILE"
else
    fail "Session file not created"
fi

# ============================================================================
# Summary
# ============================================================================
echo ""
echo "================================"
echo "Results: $PASS passed, $FAIL failed"
echo "================================"

if [ $FAIL -gt 0 ]; then
    exit 1
fi

exit 0
