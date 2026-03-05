#!/usr/bin/env bash
# Test: skill utilization tracking in post-tool-use.sh (t-198)
#
# Verifies:
# 1. Skill invocations via Bash (Skill tool calls) are detected and logged
# 2. Non-skill Bash commands don't produce skill-invoke outcomes
# 3. Skill name is extracted correctly from the tool_input
# 4. Events are appended to session JSONL

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

# --- Setup ---
TEST_SESSION="test-skill-$$"
SESSION_FILE="/tmp/brana-session-${TEST_SESSION}.jsonl"
rm -f "$SESSION_FILE"

echo "=== Test: Skill Utilization Tracking (t-198) ==="
echo ""

# --- Test 1: Skill tool invocation detected ---
echo "Test 1: Skill tool call detected as skill-invoke"

OUTPUT=$(echo '{"session_id":"'"$TEST_SESSION"'","tool_name":"Skill","tool_input":{"skill_name":"tasks","arguments":"status"},"cwd":"/tmp"}' \
    | bash "$HOOKS_DIR/post-tool-use.sh" 2>/dev/null)

assert_contains "hook returns valid JSON" "$OUTPUT" '"continue": true'

LAST_EVENT=$(tail -1 "$SESSION_FILE" 2>/dev/null)
assert_contains "outcome is skill-invoke" "$LAST_EVENT" '"outcome":"skill-invoke"'
assert_contains "detail has skill name" "$LAST_EVENT" '"detail":"tasks"'

# --- Test 2: Regular Bash command is NOT skill-invoke ---
echo ""
echo "Test 2: Regular Bash command — not skill-invoke"

OUTPUT=$(echo '{"session_id":"'"$TEST_SESSION"'","tool_name":"Bash","tool_input":{"command":"git status"},"cwd":"/tmp"}' \
    | bash "$HOOKS_DIR/post-tool-use.sh" 2>/dev/null)

LAST_EVENT=$(tail -1 "$SESSION_FILE" 2>/dev/null)
assert_not_contains "not skill-invoke" "$LAST_EVENT" 'skill-invoke'

# --- Test 3: Multiple skill invocations tracked ---
echo ""
echo "Test 3: Multiple skills tracked"

for skill in research build-phase debrief; do
    echo '{"session_id":"'"$TEST_SESSION"'","tool_name":"Skill","tool_input":{"skill_name":"'"$skill"'"},"cwd":"/tmp"}' \
        | bash "$HOOKS_DIR/post-tool-use.sh" 2>/dev/null > /dev/null
done

SKILL_COUNT=$(grep -c 'skill-invoke' "$SESSION_FILE" 2>/dev/null)
TOTAL=$((TOTAL + 1))
if [ "$SKILL_COUNT" -ge 4 ]; then
    echo "  PASS: $SKILL_COUNT skill invocations tracked (expected >=4)"
    PASS=$((PASS + 1))
else
    echo "  FAIL: only $SKILL_COUNT skill invocations (expected >=4)"
    FAIL=$((FAIL + 1))
fi

# --- Cleanup ---
rm -f "$SESSION_FILE"

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
