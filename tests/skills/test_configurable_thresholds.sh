#!/usr/bin/env bash
# Tests for configurable routing thresholds in settings (t-835).
# Spec: skill_routing config in ~/.claude/tasks-config.json controls
# suggest_threshold, mention_threshold, and enabled flag.
# Backlog SKILL.md must reference these settings.
# Run: bash tests/skills/test_configurable_thresholds.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
BACKLOG_SKILL="$REPO_ROOT/system/skills/backlog/SKILL.md"
BACKLOG_BODY="$REPO_ROOT/system/procedures/backlog.md"
grep -q PROCEDURE_FILE "$BACKLOG_SKILL" || BACKLOG_BODY="$BACKLOG_SKILL"

PASS=0
FAIL=0
TOTAL=0

assert() {
    local desc="$1" expected="$2" actual="$3"
    TOTAL=$((TOTAL + 1))
    if [ "$expected" = "$actual" ]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc (expected '$expected', got '$actual')"
        FAIL=$((FAIL + 1))
    fi
}

assert_contains() {
    local desc="$1" needle="$2" file="$3"
    TOTAL=$((TOTAL + 1))
    if grep -qE "$needle" "$file" 2>/dev/null; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc (expected '$needle' in $(basename "$file"))"
        FAIL=$((FAIL + 1))
    fi
}

echo "=== test_configurable_thresholds.sh ==="

# ── Test 1: Backlog skill references tasks-config.json ──
echo "Test 1: Config file reference"
assert_contains "references tasks-config.json" "tasks-config.json" "$BACKLOG_BODY"

# ── Test 2: Skill routing config keys documented ──
echo "Test 2: Config keys"
assert_contains "suggest_threshold documented" "suggest_threshold" "$BACKLOG_BODY"
assert_contains "mention_threshold documented" "mention_threshold" "$BACKLOG_BODY"
assert_contains "enabled flag documented" "enabled" "$BACKLOG_BODY"

# ── Test 3: Default values specified ──
echo "Test 3: Default values"
assert_contains "default suggest threshold 0.5" "0\\.5" "$BACKLOG_BODY"
assert_contains "default mention threshold 0.3" "0\\.3" "$BACKLOG_BODY"

# ── Test 4: Enabled false skips routing ──
echo "Test 4: Disable behavior"
assert_contains "enabled false skips" "enabled.*false.*skip|skip.*step 5|enabled: false" "$BACKLOG_BODY"

# ── Test 5: /brana:do also references thresholds ──
echo "Test 5: /brana:do uses same thresholds"
DO_SKILL="$REPO_ROOT/system/skills/do/SKILL.md"
if [ -f "$DO_SKILL" ]; then
    # do is a pure alias since the start-routing merge — thresholds live in backlog start 1a
    assert_contains "do delegates to backlog start" "backlog.*start|brana:backlog" "$DO_SKILL"
else
    echo "  SKIP: /brana:do not yet created"
    TOTAL=$((TOTAL + 1))
    PASS=$((PASS + 1))
fi

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
