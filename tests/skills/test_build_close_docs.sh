#!/usr/bin/env bash
# Test: CLOSE-step doc generation is specified and reachable
# Validates: t-382 — auto-generate tech docs + user guide in CLOSE step
#
# t-476 moved generation out of /brana:build and into /brana:docs, and the
# standalone templates under system/skills/build/templates/ were removed with it.
# /brana:docs generates inline, so the doc STRUCTURE now lives in that skill's
# Output tables rather than in template files. The contract under test is
# therefore: docs/SKILL.md specifies the sections and the output paths, and
# build's CLOSE phase delegates to it.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DOCS_SKILL="$REPO_ROOT/system/skills/docs/SKILL.md"
CLOSE_PHASE="$REPO_ROOT/system/skills/build/phases/close.md"

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

# The two files that carry the contract
assert "docs SKILL.md exists" test -f "$DOCS_SKILL"
assert "build CLOSE phase exists" test -f "$CLOSE_PHASE"

# Tech doc structure is specified
assert "tech doc specifies Goal section" grep -q "## Goal" "$DOCS_SKILL"
assert "tech doc specifies Design Decisions section" grep -q "## Design Decisions" "$DOCS_SKILL"
assert "tech doc specifies Code Flow section" grep -q "## Code Flow" "$DOCS_SKILL"
assert "tech doc specifies Testing section" grep -qi "## Test" "$DOCS_SKILL"

# User guide structure is specified
assert "user guide specifies Quick Start section" grep -qi "## Quick [Ss]tart" "$DOCS_SKILL"
assert "user guide specifies How It Works section" grep -qi "## How [Ii]t [Ww]orks" "$DOCS_SKILL"
assert "user guide specifies Examples section" grep -qi "## Examples" "$DOCS_SKILL"

# CLOSE delegates rather than generating inline (t-476)
assert "CLOSE delegates doc generation to /brana:docs" grep -q "brana:docs" "$CLOSE_PHASE"

# No dangling references to the removed templates — these outlived the files
# once already, which is how /brana:docs ended up pointing at nothing.
assert "no stale build/templates references in docs skill" \
  bash -c '! grep -q "build/templates" "$0"' "$DOCS_SKILL"
assert "no stale build/templates references in CLOSE phase" \
  bash -c '! grep -q "build/templates" "$0"' "$CLOSE_PHASE"

# Strategy routing decides which docs a build gets
assert "docs skill has strategy-aware generation" grep -q "feature.*greenfield\|Strategy.*Tech Doc\|strategy.*doc" "$DOCS_SKILL"

# Output directories
assert "docs skill references docs/architecture/features/" grep -q "docs/architecture/features/" "$DOCS_SKILL"
assert "docs skill references docs/guide/features/" grep -q "docs/guide/features/" "$DOCS_SKILL"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
