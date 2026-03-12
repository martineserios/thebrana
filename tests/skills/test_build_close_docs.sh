#!/usr/bin/env bash
# Test: /brana:build CLOSE step doc generation templates exist and are well-formed
# Validates: t-382 — auto-generate tech docs + user guide in CLOSE step

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SKILL_MD="$REPO_ROOT/system/skills/build/SKILL.md"
TECH_TEMPLATE="$REPO_ROOT/system/skills/build/templates/tech-doc.md"
USER_TEMPLATE="$REPO_ROOT/system/skills/build/templates/user-guide.md"

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

echo "=== Build CLOSE Docs Tests ==="

# Template files exist
assert "Tech doc template exists" test -f "$TECH_TEMPLATE"
assert "User guide template exists" test -f "$USER_TEMPLATE"

# Templates have required sections
assert "Tech template has Goal section" grep -q "## Goal" "$TECH_TEMPLATE"
assert "Tech template has Design Decisions section" grep -q "## Design Decisions" "$TECH_TEMPLATE"
assert "Tech template has Code Flow section" grep -q "## Code Flow" "$TECH_TEMPLATE"
assert "Tech template has Testing section" grep -qi "## Test" "$TECH_TEMPLATE"

assert "User guide has Quick Start section" grep -qi "## Quick [Ss]tart" "$USER_TEMPLATE"
assert "User guide has How It Works section" grep -qi "## How [Ii]t [Ww]orks" "$USER_TEMPLATE"
assert "User guide has Examples section" grep -qi "## Examples" "$USER_TEMPLATE"

# SKILL.md references the templates
assert "SKILL.md references tech doc template" grep -q "tech-doc.md\|tech doc template" "$SKILL_MD"
assert "SKILL.md references user guide template" grep -q "user-guide.md\|user guide template" "$SKILL_MD"

# SKILL.md has strategy routing (which strategies get which docs)
assert "SKILL.md mentions strategy-aware doc generation" grep -q "feature.*greenfield\|strategy.*doc" "$SKILL_MD"

# Output directories referenced
assert "SKILL.md references docs/architecture/features/" grep -q "docs/architecture/features/" "$SKILL_MD"
assert "SKILL.md references docs/guide/features/" grep -q "docs/guide/features/" "$SKILL_MD"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
