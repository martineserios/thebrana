#!/usr/bin/env bash
# Test: challenger fixes for cascade throttle and skill tracking
#
# Verifies:
# 1. Cascade flags are cleared on successful Edit/Write
# 2. Bash failures don't write cascade flags (only file-targeted tools)
# 3. Path sanitization is collision-resistant (hash-based)
# 4. Skill tracking handles missing skill_name gracefully

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
        echo "  FAIL: $label — expected '$expected'"
        echo "        got: $output"
        FAIL=$((FAIL + 1))
    fi
}

assert_not_contains() {
    local label="$1" output="$2" unexpected="$3"
    TOTAL=$((TOTAL + 1))
    if echo "$output" | grep -qF "$unexpected" 2>/dev/null; then
        echo "  FAIL: $label — unexpected '$unexpected' found"
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

# --- Setup ---
TEST_SESSION="test-challenger-$$"
SESSION_FILE="/tmp/brana-session-${TEST_SESSION}.jsonl"
CASCADE_DIR="/tmp/brana-cascade"
rm -f "$SESSION_FILE"
rm -f "$CASCADE_DIR/${TEST_SESSION}-"* 2>/dev/null

echo "=== Test: Challenger Fixes ==="
echo ""

# --- Test 1: Cascade flag cleared on successful Edit ---
echo "Test 1: Cascade flag cleared after successful Edit"

# Create a cascade flag manually (simulating 3+ failures)
mkdir -p "$CASCADE_DIR" 2>/dev/null
# We need to know the hash-based name — first trigger a real cascade to get the flag
# Simulate: 3 consecutive Edit failures on /tmp/src/auth.ts
for i in 1 2 3; do
    echo '{"session_id":"'"$TEST_SESSION"'","tool_name":"Edit","tool_input":{"file_path":"/tmp/src/auth.ts"},"cwd":"/tmp"}' \
        | bash "$HOOKS_DIR/post-tool-use-failure.sh" 2>/dev/null > /dev/null
done

# Verify cascade flag exists
FLAG_EXISTS=false
for f in "$CASCADE_DIR/${TEST_SESSION}-"*; do
    if [ -f "$f" ] && grep -qF "/tmp/src/auth.ts" "$f" 2>/dev/null; then
        FLAG_EXISTS=true
        CASCADE_FLAG_PATH="$f"
        break
    fi
done
TOTAL=$((TOTAL + 1))
if [ "$FLAG_EXISTS" = true ]; then
    echo "  PASS: cascade flag created for /tmp/src/auth.ts"
    PASS=$((PASS + 1))
else
    echo "  FAIL: cascade flag not found for /tmp/src/auth.ts"
    FAIL=$((FAIL + 1))
fi

# Now simulate a SUCCESSFUL Edit on the same file
echo '{"session_id":"'"$TEST_SESSION"'","tool_name":"Edit","tool_input":{"file_path":"/tmp/src/auth.ts"},"cwd":"/tmp"}' \
    | bash "$HOOKS_DIR/post-tool-use.sh" 2>/dev/null > /dev/null

# Flag should be cleared
assert_file_not_exists "cascade flag cleared after success" "${CASCADE_FLAG_PATH:-/tmp/brana-cascade/${TEST_SESSION}-NONE}"

# --- Test 2: Bash failures don't create cascade flags ---
echo ""
echo "Test 2: Bash failures don't create cascade flags"

rm -f "$SESSION_FILE"
rm -f "$CASCADE_DIR/${TEST_SESSION}-"* 2>/dev/null

for i in 1 2 3; do
    echo '{"session_id":"'"$TEST_SESSION"'","tool_name":"Bash","tool_input":{"command":"npm test"},"cwd":"/tmp"}' \
        | bash "$HOOKS_DIR/post-tool-use-failure.sh" 2>/dev/null > /dev/null
done

# Count cascade flags for this session
BASH_FLAGS=$(ls "$CASCADE_DIR/${TEST_SESSION}-"* 2>/dev/null | wc -l)
TOTAL=$((TOTAL + 1))
if [ "$BASH_FLAGS" -eq 0 ]; then
    echo "  PASS: no cascade flags from Bash failures"
    PASS=$((PASS + 1))
else
    echo "  FAIL: $BASH_FLAGS cascade flags created from Bash failures"
    FAIL=$((FAIL + 1))
fi

# --- Test 3: Path sanitization — no collisions ---
echo ""
echo "Test 3: Path sanitization collision resistance"

rm -f "$SESSION_FILE"
rm -f "$CASCADE_DIR/${TEST_SESSION}-"* 2>/dev/null

# These two paths would collide with naive tr '/' '-':
# src/auth-utils.ts -> src-auth-utils.ts
# src-auth/utils.ts -> src-auth-utils.ts
for i in 1 2 3; do
    echo '{"session_id":"'"$TEST_SESSION"'","tool_name":"Edit","tool_input":{"file_path":"/tmp/src/auth-utils.ts"},"cwd":"/tmp"}' \
        | bash "$HOOKS_DIR/post-tool-use-failure.sh" 2>/dev/null > /dev/null
done

for i in 1 2 3; do
    echo '{"session_id":"'"$TEST_SESSION"'","tool_name":"Edit","tool_input":{"file_path":"/tmp/src-auth/utils.ts"},"cwd":"/tmp"}' \
        | bash "$HOOKS_DIR/post-tool-use-failure.sh" 2>/dev/null > /dev/null
done

# Should have 2 distinct flag files, not 1
FLAG_COUNT=$(ls "$CASCADE_DIR/${TEST_SESSION}-"* 2>/dev/null | wc -l)
TOTAL=$((TOTAL + 1))
if [ "$FLAG_COUNT" -ge 2 ]; then
    echo "  PASS: $FLAG_COUNT distinct flags (no collision)"
    PASS=$((PASS + 1))
else
    echo "  FAIL: only $FLAG_COUNT flag(s) — collision detected"
    FAIL=$((FAIL + 1))
fi

# --- Test 4: Skill tracking with missing skill_name ---
echo ""
echo "Test 4: Skill tracking graceful fallback"

rm -f "$SESSION_FILE"

# Skill tool with no skill_name field
OUTPUT=$(echo '{"session_id":"'"$TEST_SESSION"'","tool_name":"Skill","tool_input":{},"cwd":"/tmp"}' \
    | bash "$HOOKS_DIR/post-tool-use.sh" 2>/dev/null)

assert_contains "hook returns valid JSON" "$OUTPUT" '{"continue": true}'

LAST_EVENT=$(tail -1 "$SESSION_FILE" 2>/dev/null)
assert_contains "still logs skill-invoke" "$LAST_EVENT" '"outcome":"skill-invoke"'
assert_contains "detail is unknown (not empty)" "$LAST_EVENT" '"detail":"unknown"'

# --- Cleanup ---
rm -f "$SESSION_FILE"
rm -f "$CASCADE_DIR/${TEST_SESSION}-"* 2>/dev/null

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
