#!/usr/bin/env bash
# Tests for /brana:do alias — freeform mode for backlog start (t-834).
# Spec: /brana:do is a thin alias skill that routes freeform text through
# the same memory_search(ns:skills) routing as backlog start step 5.
# It should exist as a SKILL.md, reference backlog start, and not duplicate logic.
# Run: bash tests/skills/test_brana_do_alias.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DO_SKILL="$REPO_ROOT/system/skills/do/SKILL.md"
BACKLOG_SKILL="$REPO_ROOT/system/skills/backlog/SKILL.md"

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

echo "=== test_brana_do_alias.sh ==="

# ── Test 1: Skill file exists ──
echo "Test 1: /brana:do skill exists"
assert "SKILL.md exists" "true" "$([ -f "$DO_SKILL" ] && echo true || echo false)"

# ── Test 2: Frontmatter is correct ──
echo "Test 2: Frontmatter"
assert_contains "name is 'do'" "^name: do$" "$DO_SKILL"
assert_contains "has memory_search in allowed-tools" "mcp__ruflo__memory_search" "$DO_SKILL"
assert_contains "has Bash in allowed-tools" "Bash" "$DO_SKILL"
assert_contains "has AskUserQuestion" "AskUserQuestion" "$DO_SKILL"

# ── Test 3: References backlog start (not duplicating logic) ──
echo "Test 3: Delegates to backlog start"
assert_contains "references backlog start" "backlog start|backlog.*start|/brana:backlog" "$DO_SKILL"

# ── Test 4: Accepts freeform text as argument ──
echo "Test 4: Freeform input"
assert_contains "has argument-hint" "argument-hint" "$DO_SKILL"
assert_contains "description mentions freeform" "freeform|natural language|text" "$DO_SKILL"

# ── Test 5: Uses memory_search for routing ──
echo "Test 5: Routing via memory_search"
assert_contains "calls memory_search" "memory_search" "$DO_SKILL"
assert_contains "uses skills namespace" "skills" "$DO_SKILL"

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
