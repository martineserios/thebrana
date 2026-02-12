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

# Test 5: session-end stores quarantine metadata
echo "Testing session-end metadata..."

# Locate claude-flow binary (same logic as hooks)
CF=""
for candidate in "$HOME"/.nvm/versions/node/*/bin/claude-flow; do
    [ -x "$candidate" ] && CF="$candidate" && break
done
[ -z "$CF" ] && command -v claude-flow &>/dev/null && CF="claude-flow"

if [ -n "$CF" ]; then
    META_SESSION_ID="test-meta-$(date +%s)"
    META_SESSION_FILE="/tmp/brana-session-${META_SESSION_ID}.jsonl"
    META_KEY="session:$(basename "$HOME"):${META_SESSION_ID}"

    # Create a fake session file with events
    jq -n -c '{ts: 1234567890, tool: "Bash", outcome: "success", detail: "echo test"}' > "$META_SESSION_FILE"
    jq -n -c '{ts: 1234567891, tool: "Read", outcome: "failure", detail: "missing.txt"}' >> "$META_SESSION_FILE"

    # Run session-end hook
    echo '{}' | jq -c --arg sid "$META_SESSION_ID" --arg cwd "$HOME" \
        '{session_id: $sid, cwd: $cwd, hook_event_name: "SessionEnd"}' | \
        timeout 15 bash "$HOOKS_DIR/session-end.sh" >/dev/null 2>&1 || true

    # Retrieve the stored value by key and verify quarantine metadata fields
    # session-end stores to namespace "patterns" with key "session:PROJECT:SESSION_ID"
    # PROJECT = basename of git root (or CWD if not a git repo)
    META_PROJECT=$(git -C "$HOME" rev-parse --show-toplevel 2>/dev/null || echo "$HOME")
    META_PROJECT=$(basename "$META_PROJECT")
    META_KEY="session:${META_PROJECT}:${META_SESSION_ID}"

    RETRIEVED=$(timeout 10 $CF memory retrieve -k "$META_KEY" --namespace patterns --format json 2>/dev/null || true)
    if [ -z "$RETRIEVED" ] || echo "$RETRIEVED" | grep -q 'Key not found'; then
        fail "session-end metadata — stored value not found (key=$META_KEY)"
    else
        CONTENT=$(echo "$RETRIEVED" | jq -r '.content // empty' 2>/dev/null || true)
        if [ -z "$CONTENT" ]; then
            fail "session-end metadata — no content field in retrieved entry"
        else
            if echo "$CONTENT" | jq -e '.confidence' >/dev/null 2>&1; then
                pass "session-end metadata — confidence field present"
            else
                fail "session-end metadata — confidence field missing from stored value"
            fi
            if echo "$CONTENT" | jq -e '.recall_count' >/dev/null 2>&1; then
                pass "session-end metadata — recall_count field present"
            else
                fail "session-end metadata — recall_count field missing from stored value"
            fi
        fi
    fi

    # Clean up
    timeout 10 $CF memory delete "$META_KEY" >/dev/null 2>&1 || true
    rm -f "$META_SESSION_FILE"
else
    echo "  SKIP: claude-flow not found — cannot test metadata storage"
fi
echo ""

# ─── PreToolUse Tests ───
# These tests create temporary git repos to test the spec-before-code hook.

echo "Testing pre-tool-use (spec-before-code enforcement)..."

PRE_HOOK="$HOOKS_DIR/pre-tool-use.sh"

if [ ! -x "$PRE_HOOK" ]; then
    fail "pre-tool-use.sh — not executable or missing"
else

# Test helper for PreToolUse: run hook with given JSON, return output
run_pre_hook() {
    echo "$1" | timeout 10 bash "$PRE_HOOK" 2>/dev/null
}

# Test 6: Allows spec files on feat/* branches
echo "  Test 6: allows spec files on feat/* branches..."
TMPDIR6=$(mktemp -d)
trap "rm -rf $TMPDIR6" EXIT
(
    cd "$TMPDIR6"
    git init -q
    git commit --allow-empty -m "init" -q
    git checkout -b feat/test -q
    mkdir -p docs/decisions
) >/dev/null 2>&1
OUTPUT6=$(run_pre_hook "$(jq -n \
    --arg tool "Write" \
    --arg cwd "$TMPDIR6" \
    --arg fp "$TMPDIR6/docs/decisions/ADR-001.md" \
    '{tool_name: $tool, cwd: $cwd, tool_input: {file_path: $fp}}')")
if echo "$OUTPUT6" | jq -e '.continue == true' >/dev/null 2>&1; then
    pass "pre-tool-use — allows spec files on feat/* branches"
else
    fail "pre-tool-use — should allow spec files, got: $OUTPUT6"
fi
rm -rf "$TMPDIR6"

# Test 7: Blocks impl files without spec activity
echo "  Test 7: blocks impl files without spec activity..."
TMPDIR7=$(mktemp -d)
(
    cd "$TMPDIR7"
    git init -q
    git commit --allow-empty -m "init" -q
    git checkout -b feat/test -q
    mkdir -p docs/decisions
) >/dev/null 2>&1
OUTPUT7=$(run_pre_hook "$(jq -n \
    --arg tool "Write" \
    --arg cwd "$TMPDIR7" \
    --arg fp "$TMPDIR7/src/app.ts" \
    '{tool_name: $tool, cwd: $cwd, tool_input: {file_path: $fp}}')")
if echo "$OUTPUT7" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null 2>&1; then
    pass "pre-tool-use — blocks impl without spec activity"
else
    fail "pre-tool-use — should deny impl without spec, got: $OUTPUT7"
fi
rm -rf "$TMPDIR7"

# Test 8: Passes through without docs/decisions/
echo "  Test 8: passes through without docs/decisions/..."
TMPDIR8=$(mktemp -d)
(
    cd "$TMPDIR8"
    git init -q
    git commit --allow-empty -m "init" -q
    git checkout -b feat/test -q
) >/dev/null 2>&1
OUTPUT8=$(run_pre_hook "$(jq -n \
    --arg tool "Write" \
    --arg cwd "$TMPDIR8" \
    --arg fp "$TMPDIR8/src/app.ts" \
    '{tool_name: $tool, cwd: $cwd, tool_input: {file_path: $fp}}')")
if echo "$OUTPUT8" | jq -e '.continue == true' >/dev/null 2>&1; then
    pass "pre-tool-use — passes through without opt-in"
else
    fail "pre-tool-use — should pass through without docs/decisions/, got: $OUTPUT8"
fi
rm -rf "$TMPDIR8"

# Test 9: Passes through on non-feat branches
echo "  Test 9: passes through on non-feat branches..."
TMPDIR9=$(mktemp -d)
(
    cd "$TMPDIR9"
    git init -q
    git commit --allow-empty -m "init" -q
    git checkout -b fix/something -q
    mkdir -p docs/decisions
) >/dev/null 2>&1
OUTPUT9=$(run_pre_hook "$(jq -n \
    --arg tool "Write" \
    --arg cwd "$TMPDIR9" \
    --arg fp "$TMPDIR9/src/app.ts" \
    '{tool_name: $tool, cwd: $cwd, tool_input: {file_path: $fp}}')")
if echo "$OUTPUT9" | jq -e '.continue == true' >/dev/null 2>&1; then
    pass "pre-tool-use — passes through on non-feat branches"
else
    fail "pre-tool-use — should pass through on fix/* branch, got: $OUTPUT9"
fi
rm -rf "$TMPDIR9"

fi # end pre-tool-use tests
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
