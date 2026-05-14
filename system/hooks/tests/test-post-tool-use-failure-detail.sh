#!/usr/bin/env bash
# Regression test for PostToolUseFailure detail extraction (t-1406).
# Guards against Read/Edit/Write falling through to the TOOL_NAME fallback
# (the original bug that collapsed 572 Read failures into one signature bucket).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/../post-tool-use-failure.sh"
PASS=0
FAIL=0

# Each test uses a unique session ID to avoid JSONL cross-contamination.
SESSION_BASE="test-detail-$$"

assert_eq() {
    local desc="$1" actual="$2" expected="$3"
    if [ "$actual" = "$expected" ]; then
        echo "  PASS: $desc"
        (( PASS++ )) || true
    else
        echo "  FAIL: $desc — expected '$expected', got '$actual'"
        (( FAIL++ )) || true
    fi
}

assert_contains() {
    local desc="$1" haystack="$2" needle="$3"
    if echo "$haystack" | grep -qF "$needle"; then
        echo "  PASS: $desc"
        (( PASS++ )) || true
    else
        echo "  FAIL: $desc — expected to contain '$needle', got: $haystack"
        (( FAIL++ )) || true
    fi
}

# Feed a synthetic failure event and return the last JSONL line written.
run_hook() {
    local session="$1" input="$2"
    local session_file="/tmp/brana-session-${session}.jsonl"
    rm -f "$session_file"
    echo "$input" | bash "$HOOK" > /dev/null 2>&1 || true
    tail -1 "$session_file" 2>/dev/null || echo '{}'
}

echo "post-tool-use-failure.sh — detail extraction tests"
echo "==================================================="

# --- Test 1: Read tool captures file_path, not "Read" ---
echo ""
echo "Test 1: Read — detail = file_path"
SID="${SESSION_BASE}-1"
INPUT=$(jq -n --arg sid "$SID" '{
    session_id: $sid,
    tool_name: "Read",
    tool_input: {"file_path": "/home/user/project/src/main.rs"},
    duration_ms: 120
}')
ENTRY=$(run_hook "$SID" "$INPUT")
DETAIL=$(echo "$ENTRY" | jq -r '.detail // ""')
assert_eq "Read detail is file_path" "$DETAIL" "/home/user/project/src/main.rs"
assert_eq "Read outcome is failure" "$(echo "$ENTRY" | jq -r '.outcome')" "failure"

# --- Test 2: Edit tool captures file_path ---
echo ""
echo "Test 2: Edit — detail = file_path"
SID="${SESSION_BASE}-2"
INPUT=$(jq -n --arg sid "$SID" '{
    session_id: $sid,
    tool_name: "Edit",
    tool_input: {"file_path": "/home/user/project/system/hooks/pre-tool-use.sh"},
    duration_ms: 50
}')
ENTRY=$(run_hook "$SID" "$INPUT")
DETAIL=$(echo "$ENTRY" | jq -r '.detail // ""')
assert_eq "Edit detail is file_path" "$DETAIL" "/home/user/project/system/hooks/pre-tool-use.sh"

# --- Test 3: Write tool captures file_path ---
echo ""
echo "Test 3: Write — detail = file_path"
SID="${SESSION_BASE}-3"
INPUT=$(jq -n --arg sid "$SID" '{
    session_id: $sid,
    tool_name: "Write",
    tool_input: {"file_path": "/tmp/output.json"},
    duration_ms: 30
}')
ENTRY=$(run_hook "$SID" "$INPUT")
DETAIL=$(echo "$ENTRY" | jq -r '.detail // ""')
assert_eq "Write detail is file_path" "$DETAIL" "/tmp/output.json"

# --- Test 4: Bash tool captures command ---
echo ""
echo "Test 4: Bash — detail = command"
SID="${SESSION_BASE}-4"
INPUT=$(jq -n --arg sid "$SID" '{
    session_id: $sid,
    tool_name: "Bash",
    tool_input: {"command": "cargo build --release"},
    duration_ms: 8000
}')
ENTRY=$(run_hook "$SID" "$INPUT")
DETAIL=$(echo "$ENTRY" | jq -r '.detail // ""')
assert_contains "Bash detail contains command" "$DETAIL" "cargo build"

# --- Test 5: Unknown tool falls back to tool name (expected behavior) ---
echo ""
echo "Test 5: Unknown tool — detail = tool name"
SID="${SESSION_BASE}-5"
INPUT=$(jq -n --arg sid "$SID" '{
    session_id: $sid,
    tool_name: "WebSearch",
    tool_input: {"query": "rust lifetimes"},
    duration_ms: 200
}')
ENTRY=$(run_hook "$SID" "$INPUT")
DETAIL=$(echo "$ENTRY" | jq -r '.detail // ""')
assert_eq "WebSearch fallback detail is tool name" "$DETAIL" "WebSearch"

# --- Test 6: error_cat is correct for each tool ---
echo ""
echo "Test 6: error_cat classification"
SID="${SESSION_BASE}-6a"
INPUT=$(jq -n --arg sid "$SID" '{session_id: $sid, tool_name: "Edit", tool_input: {"file_path": "/a/b.md"}, duration_ms: 0}')
ENTRY=$(run_hook "$SID" "$INPUT")
assert_eq "Edit error_cat=edit-mismatch" "$(echo "$ENTRY" | jq -r '.error_cat')" "edit-mismatch"

SID="${SESSION_BASE}-6b"
INPUT=$(jq -n --arg sid "$SID" '{session_id: $sid, tool_name: "Write", tool_input: {"file_path": "/a/b.md"}, duration_ms: 0}')
ENTRY=$(run_hook "$SID" "$INPUT")
assert_eq "Write error_cat=write-fail" "$(echo "$ENTRY" | jq -r '.error_cat')" "write-fail"

SID="${SESSION_BASE}-6c"
INPUT=$(jq -n --arg sid "$SID" '{session_id: $sid, tool_name: "Read", tool_input: {"file_path": "/a/b.md"}, duration_ms: 0}')
ENTRY=$(run_hook "$SID" "$INPUT")
assert_eq "Read error_cat=tool-fail (fallthrough — Read has no dedicated cat)" "$(echo "$ENTRY" | jq -r '.error_cat')" "tool-fail"

# --- Test 7: duration_ms logged correctly ---
echo ""
echo "Test 7: duration_ms preserved in log entry"
SID="${SESSION_BASE}-7"
INPUT=$(jq -n --arg sid "$SID" '{session_id: $sid, tool_name: "Read", tool_input: {"file_path": "/x"}, duration_ms: 999}')
ENTRY=$(run_hook "$SID" "$INPUT")
assert_eq "duration_ms=999 logged" "$(echo "$ENTRY" | jq -r '.duration_ms')" "999"

# --- Test 8: Missing session_id — hook still outputs continue:true, writes nothing ---
echo ""
echo "Test 8: Missing session_id — hook exits cleanly, no JSONL written"
INPUT='{"tool_name": "Read", "tool_input": {"file_path": "/x"}, "duration_ms": 0}'
OUTPUT=$(echo "$INPUT" | bash "$HOOK" 2>/dev/null)
CONTINUE=$(echo "$OUTPUT" | jq -r '.continue' 2>/dev/null)
assert_eq "No session_id → continue:true" "$CONTINUE" "true"

# --- Cleanup ---
rm -f /tmp/brana-session-${SESSION_BASE}-*.jsonl 2>/dev/null || true

echo ""
echo "==================================================="
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
