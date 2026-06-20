#!/usr/bin/env bash
# stale-branches-reap.sh — reap MERGED local branches; report (never delete) unmerged ones (t-2148).
#
# SAFE BY CONSTRUCTION: only deletes branches fully merged into the integration/production line
# (git branch -d refuses anything not merged). Unmerged branches are reported for human review,
# NEVER force-deleted — losing unmerged work is exactly what this must not do.
#
# Env:
#   REAP_APPLY=1     actually delete merged branches (default 0 = dry-run / report only)
#   REAP_BASE        ref to test merge against (default: main)
#   REAP_PROTECT     space-separated branches to never touch (default "main dev")
set -u

BASE="${REAP_BASE:-main}"
PROTECT="${REAP_PROTECT:-main dev}"
APPLY="${REAP_APPLY:-0}"
CUR="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo HEAD)"

git fetch origin --prune --quiet 2>/dev/null || true

is_protected() { local b; for b in $PROTECT "$CUR"; do [ "$1" = "$b" ] && return 0; done; return 1; }

merged=0; unmerged=0; deleted=0
echo "[reap] base=$BASE apply=$APPLY (dry-run unless REAP_APPLY=1)"
while IFS= read -r b; do
  [ -z "$b" ] && continue
  is_protected "$b" && continue
  if git merge-base --is-ancestor "$b" "$BASE" 2>/dev/null; then
    merged=$((merged+1))
    if [ "$APPLY" = "1" ]; then
      if git branch -d "$b" -q 2>/dev/null; then deleted=$((deleted+1)); echo "[reap] deleted (merged): $b"; fi
    else
      echo "[reap] would delete (merged): $b"
    fi
  else
    unmerged=$((unmerged+1))
    echo "[reap] KEEP (unmerged, +$(git rev-list --count "$BASE".."$b" 2>/dev/null) commits, last $(git log -1 --format=%cs "$b" 2>/dev/null)): $b"
  fi
done < <(git for-each-ref --format='%(refname:short)' refs/heads/)

echo "[reap] summary: merged=$merged unmerged-kept=$unmerged deleted=$deleted"
[ "$APPLY" != "1" ] && [ "$merged" -gt 0 ] && echo "[reap] re-run with REAP_APPLY=1 to delete the $merged merged branch(es)"
exit 0
