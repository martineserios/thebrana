#!/usr/bin/env bash
# Tests for session-end.sh learnings auto-population (t-1450).
#
# Verifies that session-end.sh extracts learnings[] from brana session state
# and auto-populates PATTERN_LEARNINGS before calling session-end-persist.sh,
# so patterns.md is written without callers explicitly setting the env var.
#
# Design:
#   - Fake CLAUDE_PLUGIN_DATA/brana binary returns mock session JSON with learnings
#   - session-end.sh forks background; test waits 2s for completion
#   - Fake HOME isolates patterns.md writes
#
# TDD markers: all green post t-1450

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOKS_DIR="$(cd "$SCRIPT_DIR/../../system/hooks" && pwd)"
HOOK="$HOOKS_DIR/session-end.sh"

PASS=0; FAIL=0
TEST_ID="learnings-$$"

assert_file_exists() {
    local label="$1" path="$2"
    if [ -f "$path" ]; then
        PASS=$((PASS+1)); echo "  PASS: $label"
    else
        FAIL=$((FAIL+1)); echo "  FAIL: $label — file not found: $path"
    fi
}

assert_file_not_exists() {
    local label="$1" path="$2"
    if [ ! -f "$path" ]; then
        PASS=$((PASS+1)); echo "  PASS: $label"
    else
        FAIL=$((FAIL+1)); echo "  FAIL: $label — file unexpectedly exists: $path"
    fi
}

assert_contains() {
    local label="$1" haystack="$2" needle="$3"
    if echo "$haystack" | grep -qF "$needle"; then
        PASS=$((PASS+1)); echo "  PASS: $label"
    else
        FAIL=$((FAIL+1)); echo "  FAIL: $label — not found: '$needle'"
    fi
}

assert_not_contains() {
    local label="$1" haystack="$2" needle="$3"
    if echo "$haystack" | grep -qF "$needle"; then
        FAIL=$((FAIL+1)); echo "  FAIL: $label — unexpectedly found: '$needle'"
    else
        PASS=$((PASS+1)); echo "  PASS: $label"
    fi
}

echo "=== session-end.sh learnings auto-population tests ==="
echo ""

# ── Test 1: session state learnings[] → patterns.md ────────────────
echo "Test 1: session state learnings[] auto-populated to patterns.md"
FAKE_HOME_1=$(mktemp -d /tmp/brana-test-home-el-1-XXXXXX)
FAKE_PLUGIN_1=$(mktemp -d /tmp/brana-test-plugin-el-1-XXXXXX)
SESSION_FILE_1="/tmp/brana-session-${TEST_ID}-1.jsonl"
mkdir -p "$FAKE_HOME_1/.claude/memory"

# Minimal JSONL so session-end.sh doesn't early-exit (non-empty check)
echo '{"ts":1,"tool":"Bash","outcome":"success","detail":"test"}' > "$SESSION_FILE_1"

# Fake brana: returns session state with learnings for `session read --json`
cat > "$FAKE_PLUGIN_1/brana" <<'FAKEBRANA'
#!/usr/bin/env bash
case "$*" in
    "session read --json")
        echo '{"version":1,"learnings":["bash unset variable causes silent failure in arithmetic context"]}'
        ;;
    "session path")
        echo "/tmp/fake-session-nonexistent-el1.json"
        ;;
    session\ write\ *)
        exit 0
        ;;
    *)
        exit 0
        ;;
esac
FAKEBRANA
chmod +x "$FAKE_PLUGIN_1/brana"

INPUT_1=$(jq -n -c \
    --arg sid "${TEST_ID}-1" \
    --arg cwd "/tmp" \
    '{session_id:$sid,cwd:$cwd,hook_event_name:"Stop"}')

(
    export HOME="$FAKE_HOME_1"
    export CLAUDE_PLUGIN_DATA="$FAKE_PLUGIN_1"
    echo "$INPUT_1" | bash "$HOOK" > /dev/null 2>&1
)
sleep 2

PATTERNS_1=$(cat "$FAKE_HOME_1/.claude/memory/patterns.md" 2>/dev/null || echo "")
assert_file_exists "patterns.md created from session learnings" \
    "$FAKE_HOME_1/.claude/memory/patterns.md"
assert_contains "learning text appears in patterns.md" \
    "$PATTERNS_1" "bash unset variable causes silent failure"

rm -rf "$FAKE_HOME_1" "$FAKE_PLUGIN_1" "$SESSION_FILE_1" 2>/dev/null || true

# ── Test 2: empty learnings[] → patterns.md NOT created ─────────────
echo ""
echo "Test 2: empty learnings[] — patterns.md not created"
FAKE_HOME_2=$(mktemp -d /tmp/brana-test-home-el-2-XXXXXX)
FAKE_PLUGIN_2=$(mktemp -d /tmp/brana-test-plugin-el-2-XXXXXX)
SESSION_FILE_2="/tmp/brana-session-${TEST_ID}-2.jsonl"
mkdir -p "$FAKE_HOME_2/.claude/memory"

echo '{"ts":1,"tool":"Bash","outcome":"success","detail":"test"}' > "$SESSION_FILE_2"

cat > "$FAKE_PLUGIN_2/brana" <<'FAKEBRANA'
#!/usr/bin/env bash
case "$*" in
    "session read --json")
        echo '{"version":1,"learnings":[]}'
        ;;
    "session path")
        echo "/tmp/fake-session-nonexistent-el2.json"
        ;;
    session\ write\ *)
        exit 0
        ;;
    *)
        exit 0
        ;;
esac
FAKEBRANA
chmod +x "$FAKE_PLUGIN_2/brana"

INPUT_2=$(jq -n -c \
    --arg sid "${TEST_ID}-2" \
    --arg cwd "/tmp" \
    '{session_id:$sid,cwd:$cwd,hook_event_name:"Stop"}')

(
    export HOME="$FAKE_HOME_2"
    export CLAUDE_PLUGIN_DATA="$FAKE_PLUGIN_2"
    echo "$INPUT_2" | bash "$HOOK" > /dev/null 2>&1
)
sleep 2

assert_file_not_exists "patterns.md NOT created for empty learnings" \
    "$FAKE_HOME_2/.claude/memory/patterns.md"

rm -rf "$FAKE_HOME_2" "$FAKE_PLUGIN_2" "$SESSION_FILE_2" 2>/dev/null || true

# ── Test 3: pre-set PATTERN_LEARNINGS not overwritten ───────────────
echo ""
echo "Test 3: pre-set PATTERN_LEARNINGS takes precedence over session state"
FAKE_HOME_3=$(mktemp -d /tmp/brana-test-home-el-3-XXXXXX)
FAKE_PLUGIN_3=$(mktemp -d /tmp/brana-test-plugin-el-3-XXXXXX)
SESSION_FILE_3="/tmp/brana-session-${TEST_ID}-3.jsonl"
mkdir -p "$FAKE_HOME_3/.claude/memory"

echo '{"ts":1,"tool":"Bash","outcome":"success","detail":"test"}' > "$SESSION_FILE_3"

# Fake brana returns different learning than the pre-set value
cat > "$FAKE_PLUGIN_3/brana" <<'FAKEBRANA'
#!/usr/bin/env bash
case "$*" in
    "session read --json")
        echo '{"version":1,"learnings":["from session state SHOULD NOT appear"]}'
        ;;
    "session path")
        echo "/tmp/fake-session-nonexistent-el3.json"
        ;;
    session\ write\ *)
        exit 0
        ;;
    *)
        exit 0
        ;;
esac
FAKEBRANA
chmod +x "$FAKE_PLUGIN_3/brana"

INPUT_3=$(jq -n -c \
    --arg sid "${TEST_ID}-3" \
    --arg cwd "/tmp" \
    '{session_id:$sid,cwd:$cwd,hook_event_name:"Stop"}')

(
    export HOME="$FAKE_HOME_3"
    export CLAUDE_PLUGIN_DATA="$FAKE_PLUGIN_3"
    export PATTERN_LEARNINGS='["pre-set caller learning SHOULD appear"]'
    echo "$INPUT_3" | bash "$HOOK" > /dev/null 2>&1
)
sleep 2

PATTERNS_3=$(cat "$FAKE_HOME_3/.claude/memory/patterns.md" 2>/dev/null || echo "")
assert_file_exists "patterns.md written from pre-set PATTERN_LEARNINGS" \
    "$FAKE_HOME_3/.claude/memory/patterns.md"
assert_contains "pre-set learning appears in patterns.md" \
    "$PATTERNS_3" "pre-set caller learning SHOULD appear"
assert_not_contains "session state does NOT overwrite pre-set" \
    "$PATTERNS_3" "from session state SHOULD NOT appear"

rm -rf "$FAKE_HOME_3" "$FAKE_PLUGIN_3" "$SESSION_FILE_3" 2>/dev/null || true

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
