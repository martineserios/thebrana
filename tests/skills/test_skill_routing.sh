#!/usr/bin/env bash
# Tests for skill routing in /brana:backlog start (t-833).
# Validates: SKILL.md has MCP tools, step 5 routing spec, fallback logic.
# Run: bash tests/skills/test_skill_routing.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
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
    if grep -q "$needle" "$file" 2>/dev/null; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc (expected '$needle' in $(basename "$file"))"
        FAIL=$((FAIL + 1))
    fi
}

echo "=== test_skill_routing.sh ==="

# ── Test 1: Backlog SKILL.md has memory_search in allowed-tools ──
echo "Test 1: MCP tools in allowed-tools"
assert_contains "memory_search in allowed-tools" "mcp__ruflo__memory_search" "$BACKLOG_SKILL"

# ── Test 2: Step 5 references memory_search MCP call ──
echo "Test 2: Step 5 uses MCP routing"
assert_contains "step 5 calls memory_search" "memory_search" "$BACKLOG_SKILL"
assert_contains "step 5 uses namespace skills" 'namespace.*skills\|ns.*skills\|"skills"' "$BACKLOG_SKILL"

# ── Test 3: CLI fallback exists ──
echo "Test 3: CLI fallback"
assert_contains "CLI fallback present" "brana skills suggest" "$BACKLOG_SKILL"
assert_contains "fallback is conditional" "unavailable\|fallback\|down" "$BACKLOG_SKILL"

# ── Test 4: Results presentation uses AskUserQuestion ──
echo "Test 4: User confirmation via AskUserQuestion"
assert_contains "AskUserQuestion for suggestion" "AskUserQuestion" "$BACKLOG_SKILL"
assert_contains "skip option exists" "Skip\|none needed\|Skip.*none" "$BACKLOG_SKILL"

# ── Test 5: Threshold-based behavior ──
echo "Test 5: Threshold-based confidence tiers"
# The spec should mention different behaviors for high/mid/low confidence
assert_contains "high confidence suggest" "suggest.*threshold\|score.*0\\.5\|suggest_threshold" "$BACKLOG_SKILL"
assert_contains "low confidence marketplace" "marketplace\|acquire-skills\|externally" "$BACKLOG_SKILL"

# ── Test 6: No auto-invoke ──
echo "Test 6: No silent/auto routing"
# Step 5 should NOT contain auto-invoke or silent route
AUTO_INVOKE=$(grep -c "auto.invoke\|silent.*route\|auto.*run" "$BACKLOG_SKILL" 2>/dev/null || true)
assert "no auto-invoke in step 5" "0" "${AUTO_INVOKE:-0}"

# ── Test 7: index-skills.sh exists and skills namespace is indexable ──
echo "Test 7: Skill index infrastructure"
assert "index-skills.sh exists" "true" "$([ -f "$REPO_ROOT/system/scripts/index-skills.sh" ] && echo true || echo false)"
assert "index-skills.sh is executable" "true" "$([ -x "$REPO_ROOT/system/scripts/index-skills.sh" ] && echo true || echo false)"
# Session-start hook should call index-skills
assert_contains "session-start indexes skills" "index-skills" "$REPO_ROOT/system/hooks/session-start.sh"

# ── Test 8: Feature brief exists ──
echo "Test 8: SDD spec exists"
SPEC="$REPO_ROOT/docs/architecture/features/skill-routing-in-backlog-start.md"
assert "feature brief exists" "true" "$([ -f "$SPEC" ] && echo true || echo false)"
assert_contains "spec references t-833" "t-833" "$SPEC"
assert_contains "spec references ADR-026" "ADR-026" "$SPEC"

# ── Test 9: skill-routing gate rule (t-1196) ─────────────────────────────────
echo "Test 9: skill-routing.md gate rule content"
GATE_RULE="$REPO_ROOT/system/rules/skill-routing.md"
assert "skill-routing.md exists" "true" "$([ -f "$GATE_RULE" ] && echo true || echo false)"
assert_contains "gate rule: always ask" "always ask\|Always ask" "$GATE_RULE"
assert_contains "gate rule: AskUserQuestion" "AskUserQuestion" "$GATE_RULE"
assert_contains "gate rule: no silent routing" "silent" "$GATE_RULE"
assert_contains "gate rule: no-double-loading" "double.load\|No double" "$GATE_RULE"
assert_contains "gate rule: surface gaps" "acquire-skills" "$GATE_RULE"
# Confirm it's always-loaded (no paths: guard so it applies globally)
HAS_PATHS=$(grep -c '^paths:' "$GATE_RULE" 2>/dev/null; true)
assert "gate rule is always-loaded (no paths: guard)" "0" "$HAS_PATHS"

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
