#!/usr/bin/env bash
# Test: cascade-aware PreToolUse throttle (t-196)
#
# Verifies:
# 1. post-tool-use-failure.sh writes cascade flag when cascade=true
# 2. pre-tool-use.sh reads cascade flag and injects additionalContext (not deny)
# 3. Flag is per-session and per-file (no cross-contamination)
# 4. Non-cascade failures don't create flags
# 5. Graceful degradation: missing flag dir doesn't break hooks

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOKS_DIR="$(cd "$SCRIPT_DIR/../../system/hooks" && pwd)"
PASS=0
FAIL=0
TOTAL=0

assert_contains() {
    local label="$1" output="$2" expected="$3"
    TOTAL=$((TOTAL + 1))
    if echo "$output" | grep -qF "$expected" 2>/dev/null; then
        echo "  PASS: $label"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $label — expected '$expected' in output"
        echo "        got: $output"
        FAIL=$((FAIL + 1))
    fi
}

assert_not_contains() {
    local label="$1" output="$2" unexpected="$3"
    TOTAL=$((TOTAL + 1))
    if echo "$output" | grep -qF "$unexpected" 2>/dev/null; then
        echo "  FAIL: $label — unexpected '$unexpected' found in output"
        echo "        got: $output"
        FAIL=$((FAIL + 1))
    else
        echo "  PASS: $label"
        PASS=$((PASS + 1))
    fi
}

assert_file_exists() {
    local label="$1" path="$2"
    TOTAL=$((TOTAL + 1))
    if [ -f "$path" ]; then
        echo "  PASS: $label"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $label — file not found: $path"
        FAIL=$((FAIL + 1))
    fi
}

assert_file_not_exists() {
    local label="$1" path="$2"
    TOTAL=$((TOTAL + 1))
    if [ ! -f "$path" ]; then
        echo "  PASS: $label"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $label — file should not exist: $path"
        FAIL=$((FAIL + 1))
    fi
}

# Helper: compute flag path (must match hook's hash logic)
flag_path() {
    local session="$1" filepath="$2"
    local hash
    hash=$(echo -n "$filepath" | md5sum 2>/dev/null | cut -c1-12)
    echo "/tmp/brana-cascade/${session}-${hash}"
}

# --- Setup ---
TEST_SESSION="test-cascade-$$"
SESSION_FILE="/tmp/brana-session-${TEST_SESSION}.jsonl"
CASCADE_DIR="/tmp/brana-cascade"
rm -f "$SESSION_FILE"
rm -rf "$CASCADE_DIR"

echo "=== Test: Cascade Throttle (t-196) ==="
echo ""

# --- Test 1: Non-cascade failure does NOT create flag ---
echo "Test 1: Non-cascade failure — no flag"

# Write 1 failure event (not enough for cascade)
echo '{"ts":1000,"tool":"Edit","outcome":"failure","detail":"/src/app.ts","error_cat":"edit-mismatch","cascade":false}' > "$SESSION_FILE"

OUTPUT=$(echo '{"session_id":"'"$TEST_SESSION"'","tool_name":"Edit","tool_input":{"file_path":"/src/app.ts"},"cwd":"/tmp"}' \
    | bash "$HOOKS_DIR/post-tool-use-failure.sh" 2>/dev/null)

assert_contains "hook returns valid JSON" "$OUTPUT" '"continue": true'
assert_file_not_exists "no cascade flag created" "$(flag_path "$TEST_SESSION" "/src/app.ts")"

# --- Test 2: Cascade detected — flag IS created ---
echo ""
echo "Test 2: Cascade detected (3 consecutive failures) — flag created"

# Pre-populate 2 failures on same file
rm -f "$SESSION_FILE"
echo '{"ts":1000,"tool":"Edit","outcome":"failure","detail":"/src/app.ts","error_cat":"edit-mismatch","cascade":false}' >> "$SESSION_FILE"
echo '{"ts":1001,"tool":"Edit","outcome":"failure","detail":"/src/app.ts","error_cat":"edit-mismatch","cascade":false}' >> "$SESSION_FILE"

OUTPUT=$(echo '{"session_id":"'"$TEST_SESSION"'","tool_name":"Edit","tool_input":{"file_path":"/src/app.ts"},"cwd":"/tmp"}' \
    | bash "$HOOKS_DIR/post-tool-use-failure.sh" 2>/dev/null)

assert_contains "hook returns valid JSON" "$OUTPUT" '"continue": true'
assert_file_exists "cascade flag created" "$(flag_path "$TEST_SESSION" "/src/app.ts")"

# --- Test 3: PreToolUse reads cascade flag — injects context (not deny) ---
echo ""
echo "Test 3: PreToolUse detects cascade flag — injects stop-and-reassess nudge"

# PreToolUse needs a git repo context. We'll test the cascade-check portion
# by setting up the flag and calling with a non-feat branch (bypasses spec-first gate)
OUTPUT=$(echo '{"session_id":"'"$TEST_SESSION"'","tool_name":"Edit","tool_input":{"file_path":"/src/app.ts"},"cwd":"/tmp"}' \
    | bash "$HOOKS_DIR/pre-tool-use.sh" 2>/dev/null)

assert_contains "hook continues (not deny)" "$OUTPUT" '"continue": true'
assert_contains "injects cascade warning" "$OUTPUT" 'Cascade detected'

# --- Test 4: Different file — no cascade contamination ---
echo ""
echo "Test 4: Different file has no cascade flag"

OUTPUT=$(echo '{"session_id":"'"$TEST_SESSION"'","tool_name":"Edit","tool_input":{"file_path":"/src/other.ts"},"cwd":"/tmp"}' \
    | bash "$HOOKS_DIR/pre-tool-use.sh" 2>/dev/null)

assert_not_contains "no cascade warning for different file" "$OUTPUT" 'cascade'

# --- Test 5: Different session — no cascade contamination ---
echo ""
echo "Test 5: Different session has no cascade flag"

OUTPUT=$(echo '{"session_id":"other-session","tool_name":"Edit","tool_input":{"file_path":"/src/app.ts"},"cwd":"/tmp"}' \
    | bash "$HOOKS_DIR/pre-tool-use.sh" 2>/dev/null)

assert_not_contains "no cascade warning for different session" "$OUTPUT" 'cascade'

# --- Cleanup ---
rm -f "$SESSION_FILE"
rm -rf "$CASCADE_DIR"

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
