#!/usr/bin/env bash
# Regression guard (t-2281 / ADR-066 challenger finding): no skill procedure may
# instruct reading active_epic directly from the global ~/.claude/tasks-config.json.
# This is the exact bug class found in plan.md/done-and-add.md -- a prose bypass of
# the scoped resolver that grepping for function names alone would miss. Guards
# against a THIRD skill file reintroducing it, not just the two known instances.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_DIR="$SCRIPT_DIR/../../skills"
PASS=0
FAIL=0

echo "== no raw global active_epic read in skill procedures =="

# The bad pattern: an instruction to read active_epic FROM the global path.
# Matches the original bug phrasing; does not match explanatory prose like
# "never a raw read of ~/.claude/tasks-config.json" (no "active_epic ... from" before it).
HITS=$(grep -rlEi "read[^.]*active_epic[^.]*from[^.]*~/\.claude/tasks-config\.json" "$SKILLS_DIR" --include="*.md" 2>/dev/null || true)

if [ -z "$HITS" ]; then
    PASS=1
    echo "  PASS: no skill file reads active_epic from the raw global path"
else
    FAIL=1
    echo "  FAIL: raw global active_epic read found in:"
    echo "$HITS" | sed 's/^/    /'
fi

echo ""
[ "$FAIL" -eq 0 ]
