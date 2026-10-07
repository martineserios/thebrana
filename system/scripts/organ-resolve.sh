#!/usr/bin/env bash
# organ-resolve.sh <organ> — does a vendored ADR-084 organ exist in this repo?
#
# Prints the organ's SKILL.md path and exits 0 when it resolves; exits 1 with a
# fallback hint when it does not (the caller then runs its own inline procedure
# instead of improvising the organ from memory — ADR-097 D3/D9: organs are
# repo-local, adapters travel with the plugin, so a client repo usually has the
# adapter and not the organ); exits 2 on usage error. t-3489 (ADR-097 P0).
#
# Portable: no readlink -f, no flock, no bash-4-only features (macos-portability).
set -uo pipefail

organ="${1:-}"
if [ -z "$organ" ]; then
  echo "usage: organ-resolve.sh <organ>" >&2
  exit 2
fi

root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
for cand in "$root/.claude/skills/$organ/SKILL.md" "$root/.agents/skills/$organ/SKILL.md"; do
  if [ -f "$cand" ]; then
    printf '%s\n' "$(cd "$(dirname "$cand")" && pwd -P)/SKILL.md"
    exit 0
  fi
done

echo "organ '$organ' is not vendored in $root (no .claude/skills/$organ, no .agents/skills/$organ) — run the caller's inline fallback" >&2
exit 1
