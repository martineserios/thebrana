#!/usr/bin/env bash
# Test: /brana:brainstorm skill structure and frontmatter
# Validates: t-392 — interactive idea maturation skill

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SKILL_MD="$REPO_ROOT/system/skills/brainstorm/SKILL.md"

PASS=0
FAIL=0

assert() {
  local desc="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    echo "  PASS: $desc"
    ((PASS++))
  else
    echo "  FAIL: $desc"
    ((FAIL++))
  fi
}

assert_grep() {
  local desc="$1"
  local pattern="$2"
  local file="$3"
  if grep -qE "$pattern" "$file" 2>/dev/null; then
    echo "  PASS: $desc"
    ((PASS++))
  else
    echo "  FAIL: $desc"
    ((FAIL++))
  fi
}

echo "=== Brainstorm Skill Tests ==="

# File exists
assert "SKILL.md exists" test -f "$SKILL_MD"

# Frontmatter fields
assert_grep "Has name field" "^name: brainstorm" "$SKILL_MD"
assert_grep "Has description field" "^description:" "$SKILL_MD"
assert_grep "Has group field" "^group:" "$SKILL_MD"
assert_grep "Has allowed-tools field" "^allowed-tools:" "$SKILL_MD"

# Required tools
assert_grep "AskUserQuestion in allowed-tools" "AskUserQuestion" "$SKILL_MD"
assert_grep "WebSearch in allowed-tools" "WebSearch" "$SKILL_MD"
assert_grep "Agent in allowed-tools" "Agent" "$SKILL_MD"
assert_grep "Write in allowed-tools" "Write" "$SKILL_MD"

# Core phases exist
assert_grep "Has Phase 1 (Seed)" "Phase 1.*Seed" "$SKILL_MD"
assert_grep "Has Phase 2 (Expand)" "Phase 2.*Expand" "$SKILL_MD"
assert_grep "Has Phase 3 (Discuss & Challenge)" "Phase 3.*Discuss.*Challenge" "$SKILL_MD"
assert_grep "Has Phase 4 (Shape)" "Phase 4.*Shape" "$SKILL_MD"
assert_grep "Has Phase 5 (Output)" "Phase 5.*Output" "$SKILL_MD"

# Discussion phase structure
assert_grep "Has Round 1 (proactive challenge)" "Round 1.*Proactive challenge" "$SKILL_MD"
assert_grep "Has Round 2 (flip perspective)" "Round 2.*Flip the perspective" "$SKILL_MD"
assert_grep "Has Round 3+ (follow thread)" "Round 3.*Follow the thread" "$SKILL_MD"
assert_grep "Has discussion exit mechanism" "Keep discussing.*ready to shape" "$SKILL_MD"
assert_grep "Has discussion behavior rules" "Discussion behavior rules" "$SKILL_MD"
assert_grep "One question at a time rule" "One question at a time" "$SKILL_MD"
assert_grep "Escalate don't repeat rule" "Escalate.*don.t repeat" "$SKILL_MD"
assert_grep "Research mid-discussion" "Research mid-discussion" "$SKILL_MD"

# Interactive elements
assert_grep "Uses AskUserQuestion pattern" "AskUserQuestion:" "$SKILL_MD"
assert_grep "Has header fields" "header:" "$SKILL_MD"

# Output targets
assert_grep "Writes idea doc" "docs/ideas/" "$SKILL_MD"
assert_grep "Offers backlog task" "backlog task" "$SKILL_MD"

# Anti-patterns section
assert_grep "Has anti-patterns section" "Anti-patterns" "$SKILL_MD"
assert_grep "Warns against monologuing" "monologue" "$SKILL_MD"

echo ""
echo "Results: $PASS passed, $FAIL failed"
exit $FAIL
