#!/usr/bin/env bash
# Tests for marketplace auto-trigger on low-confidence routing (t-841).
# Spec: When memory_search(ns:skills) returns all results below mention_threshold,
# backlog start step 5 offers to search externally via /brana:acquire-skills.
# Run: bash tests/skills/test_marketplace_auto_trigger.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
BACKLOG_SKILL="$REPO_ROOT/system/skills/backlog/SKILL.md"
ACQUIRE_SKILL="$REPO_ROOT/system/skills/acquire-skills/SKILL.md"

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

echo "=== test_marketplace_auto_trigger.sh ==="

# ── Test 1: Backlog step 5 mentions acquire-skills on low confidence ──
echo "Test 1: Low-confidence triggers marketplace"
assert_contains "acquire-skills referenced in step 5" "acquire-skills" "$BACKLOG_SKILL"
assert_contains "externally search option" "Search externally|externally" "$BACKLOG_SKILL"

# ── Test 2: AskUserQuestion gate (no auto-install) ──
echo "Test 2: User confirmation required"
assert_contains "AskUserQuestion before external search" "AskUserQuestion" "$BACKLOG_SKILL"
assert_contains "skip option for marketplace" "Skip" "$BACKLOG_SKILL"

# ── Test 3: acquire-skills skill exists and is callable ──
echo "Test 3: acquire-skills infrastructure"
assert "acquire-skills SKILL.md exists" "true" "$([ -f "$ACQUIRE_SKILL" ] && echo true || echo false)"
assert_contains "acquire-skills has Skill invocation" "Skill.*acquire|acquire-skills" "$BACKLOG_SKILL"

# ── Test 4: Threshold-based trigger ──
echo "Test 4: Trigger condition"
assert_contains "threshold condition for gap" "0\\.3|mention_threshold|< mention" "$BACKLOG_SKILL"

# ── Test 5: Only triggers for code execution tasks ──
echo "Test 5: Code execution guard"
assert_contains "code execution check" "code.*execution|execution.*code|task.*code|execution is" "$BACKLOG_SKILL"

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
