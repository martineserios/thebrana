#!/usr/bin/env bash
# Tests for /brana:retrospective classify-then-route (t-1271).
# Validates that the retrospective procedure spec implements the memory taxonomy
# routing from memory-taxonomy-sdd.md — all 6 types, cap enforcement, fallback.
# These are spec-compliance tests: they check procedure files contain required
# logic, not that Claude executes correctly (that requires integration tests).
#
# RED until t-1241 implements classify-then-route in retrospective procedure.
# Run: bash tests/skills/test_retrospective_classify_route.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
RETRO_PROC="$REPO_ROOT/system/procedures/retrospective.md"
RETRO_SKILL="$REPO_ROOT/system/skills/retrospective/SKILL.md"
DDD="$REPO_ROOT/docs/architecture/features/memory-taxonomy-ddd.md"
SDD="$REPO_ROOT/docs/architecture/features/memory-taxonomy-sdd.md"

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
        echo "  FAIL: $desc"
        echo "         expected: '$expected'"
        echo "         got:      '$actual'"
        FAIL=$((FAIL + 1))
    fi
}

assert_contains() {
    local desc="$1" needle="$2" file="$3"
    TOTAL=$((TOTAL + 1))
    if grep -iqE "$needle" "$file" 2>/dev/null; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc"
        echo "         expected pattern: '$needle'"
        echo "         in file: $(basename "$file")"
        FAIL=$((FAIL + 1))
    fi
}

assert_not_contains() {
    local desc="$1" needle="$2" file="$3"
    TOTAL=$((TOTAL + 1))
    if ! grep -iqE "$needle" "$file" 2>/dev/null; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc"
        echo "         unexpected pattern found: '$needle'"
        echo "         in file: $(basename "$file")"
        FAIL=$((FAIL + 1))
    fi
}

assert_file_exists() {
    local desc="$1" file="$2"
    TOTAL=$((TOTAL + 1))
    if [ -f "$file" ]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc — file not found: $file"
        FAIL=$((FAIL + 1))
    fi
}

echo "=== test_retrospective_classify_route.sh ==="
echo ""

# ── Prerequisite: design docs exist ──────────────────────────────────────────
echo "Prerequisite: design docs"
assert_file_exists "DDD exists" "$DDD"
assert_file_exists "SDD exists" "$SDD"
echo ""

# ── Prerequisite: procedure and skill files exist ─────────────────────────────
echo "Prerequisite: implementation files"
assert_file_exists "retrospective procedure exists" "$RETRO_PROC"
assert_file_exists "retrospective SKILL.md exists" "$RETRO_SKILL"
echo ""

# ── Test 1: classify() decision tree present ─────────────────────────────────
echo "Test 1: classify() routing is specified"
assert_contains "procedure references classify" \
    "classif" "$RETRO_PROC"
assert_contains "procedure has decision tree for type routing" \
    "rule|pattern|knowledge|decision|reference|session" "$RETRO_PROC"
echo ""

# ── Test 2: Rule type — human gate, no auto-write ────────────────────────────
echo "Test 2: Rule → human gate (AskUserQuestion, no auto-write)"
assert_contains "procedure triggers AskUserQuestion for rule type" \
    "AskUserQuestion" "$RETRO_PROC"
assert_contains "procedure references system/rules/ for rule destination" \
    "system/rules" "$RETRO_PROC"
assert_not_contains "procedure does NOT auto-write rules to system/rules/" \
    "auto.*write.*system/rules|write.*system/rules.*auto" "$RETRO_PROC"
echo ""

# ── Test 3: Pattern type → patterns.md ───────────────────────────────────────
echo "Test 3: Pattern → patterns.md append"
assert_contains "procedure routes pattern to patterns.md" \
    "patterns\.md" "$RETRO_PROC"
assert_contains "procedure appends (not overwrites) patterns.md" \
    "append" "$RETRO_PROC"
echo ""

# ── Test 4: Knowledge type → knowledge-staging.md ────────────────────────────
echo "Test 4: Knowledge → knowledge-staging.md"
assert_contains "procedure routes knowledge to knowledge-staging.md" \
    "knowledge-staging\.md" "$RETRO_PROC"
echo ""

# ── Test 5: Decision type → ADR stub, human gate ─────────────────────────────
echo "Test 5: Decision → ADR stub, human gate"
assert_contains "procedure shows ADR template for decision type" \
    "ADR" "$RETRO_PROC"
assert_contains "procedure human-gates decision (AskUserQuestion or human)" \
    "AskUserQuestion|human" "$RETRO_PROC"
echo ""

# ── Test 6: Reference type → portfolio.md ────────────────────────────────────
echo "Test 6: Reference → portfolio.md"
assert_contains "procedure routes reference to portfolio.md" \
    "portfolio\.md" "$RETRO_PROC"
echo ""

# ── Test 7: Session type → native memory dir ─────────────────────────────────
echo "Test 7: Session state → native memory dir (unchanged)"
assert_contains "procedure documents session state destination" \
    "session" "$RETRO_PROC"
echo ""

# ── Test 8: No feedback_*.md creation ────────────────────────────────────────
echo "Test 8: feedback_*.md no longer written by retrospective"
assert_not_contains "procedure does not write feedback_*.md" \
    "feedback_.*\.md" "$RETRO_PROC"
echo ""

# ── Test 9: Cap enforcement — patterns.md ────────────────────────────────────
echo "Test 9: Cap enforcement — patterns.md"
assert_contains "procedure warns at 40 patterns" \
    "40" "$RETRO_PROC"
assert_contains "procedure blocks at 50 patterns" \
    "50" "$RETRO_PROC"
echo ""

# ── Test 10: Cap enforcement — knowledge-staging.md ──────────────────────────
echo "Test 10: Cap enforcement — knowledge-staging.md"
assert_contains "procedure warns at 20 knowledge entries" \
    "20" "$RETRO_PROC"
assert_contains "procedure blocks at 30 knowledge entries" \
    "30" "$RETRO_PROC"
echo ""

# ── Test 11: MEMORY.md line budget check ─────────────────────────────────────
echo "Test 11: MEMORY.md budget enforcement"
assert_contains "procedure checks MEMORY.md line count before writing" \
    "195|200" "$RETRO_PROC"
echo ""

# ── Test 12: Fallback chain documented ───────────────────────────────────────
echo "Test 12: Fallback chain present"
assert_contains "procedure documents fallback when destination unavailable" \
    "fallback|unavailable|down" "$RETRO_PROC"
echo ""

# ── Test 13: SKILL.md references classify-then-route ─────────────────────────
echo "Test 13: SKILL.md reflects new routing"
assert_contains "SKILL.md references taxonomy or classify" \
    "classif|taxonomy|patterns\.md|knowledge-staging" "$RETRO_SKILL"
echo ""

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "Results: $PASS passed, $FAIL failed, $TOTAL total"
if [ "$FAIL" -gt 0 ]; then
    echo "STATUS: RED (expected — implement t-1241 to make green)"
    exit 1
else
    echo "STATUS: GREEN"
    exit 0
fi
