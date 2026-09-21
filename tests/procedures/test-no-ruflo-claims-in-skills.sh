#!/usr/bin/env bash
# t-2963: ruflo claims_* is retired from skills. The board was stale (precision
# 1/6) because claimant = current branch at claim time but close/done rebuilt it
# from whatever branch was checked out after merge (`dev`) -> release mismatch.
# Everything the board could show is derivable from tasks.json in_progress+branch,
# `git worktree list` and ~/.claude/run-state. Retire, don't repair.
# No skill body, allowed-tools list or ToolSearch preamble may reference
# mcp__ruflo__claims_*.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HITS=$(grep -rn "mcp__ruflo__claims_" "$ROOT/system/skills" 2>/dev/null || true)

if [ -z "$HITS" ]; then
    echo "  PASS: no mcp__ruflo__claims_* references under system/skills/"
    exit 0
fi

echo "  FAIL: mcp__ruflo__claims_* still referenced:"
echo "$HITS" | sed 's|^'"$ROOT"'/||' | cut -c1-140 | sed 's/^/    /'
exit 1
