#!/usr/bin/env bash
# readme-coverage.sh — diff docs/README.md against the ADR and feature-doc directories.
# Emits: MISSING (doc exists, no README row linking its actual path) and DEAD
# (README links a docs/ .md path that doesn't exist).
# Exit 1 when any gap is found. Run from the repo root (or any worktree root).
# Usage: system/scripts/readme-coverage.sh [--quiet]   (t-3031, board D5)
#
# Matches on the LINK TARGET PATH, never the bare basename — docs/architecture/
# features/ and docs/guide/features/ hold same-named files with different
# content, and a basename-only check marks the wrong one "covered" (found by
# t-3031's own challenger review: 9 architecture/features/ docs silently
# uncovered because a guide/features/ file with the same name was linked).
set -u
shopt -s nullglob
cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
README=docs/README.md
[ -f "$README" ] || { echo "no $README"; exit 2; }
quiet=0; [ "${1:-}" = "--quiet" ] && quiet=1
gaps=0
for dir in docs/architecture/decisions docs/architecture/features; do
  rel=${dir#docs/}
  for f in "$dir"/*.md; do
    b=$(basename "$f")
    [ "$b" = "README.md" ] && continue
    grep -qF "]($rel/$b)" "$README" || { gaps=$((gaps+1)); [ $quiet = 1 ] || echo "MISSING ${f#docs/}"; }
  done
done
# dead rows: relative .md links (no anchor, no leading slash) whose target is absent under docs/
while read -r p; do
  case "$p" in /*) continue ;; esac   # absolute path — not a docs/-relative link, skip
  [ -e "docs/$p" ] || { gaps=$((gaps+1)); [ $quiet = 1 ] || echo "DEAD $p"; }
done < <(grep -o '\]([^)]*\.md\(#[^)]*\)\?)' "$README" | sed 's/^](//; s/)$//; s/#.*$//' | grep -v '^http' | grep -v '^\.\./' | sort -u)
if [ $gaps -eq 0 ]; then [ $quiet = 1 ] || echo "OK: README covers every ADR and feature doc; no dead links"; exit 0; fi
[ $quiet = 1 ] || echo "$gaps gap(s)"
exit 1
