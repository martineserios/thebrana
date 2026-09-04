#!/usr/bin/env bash
# memory-dir-cache.sh — resolve a project's auto-memory dir, cached (t-2988).
#
# The answer is "the first ~/.claude/projects/*/memory whose MEMORY.md mentions
# this project". Finding it means looking at every entry under
# ~/.claude/projects, which holds one directory per CC session ever started
# (14,676 on the machine this was found on, 57 of them with a memory/MEMORY.md).
# There is no way to know which dirs qualify without touching all of them, so
# the lookup is inherently O(sessions-ever) and cannot be made fast in place:
# measured 45s as a stat-per-entry bash loop, and still 0.3s warm / 9.6s cold as
# a direct MEMORY.md glob. Session start cannot afford either on its critical
# path, so it reads this cache and refreshes it in its Phase 5 background block.
#
# Usage: memory-dir-cache.sh <project> <cache-path> [max-age-min]
# Exit is always 0; the cache is written only when a directory is found.

PROJECT="${1:-}"
CACHE="${2:-}"
MAX_AGE_MIN="${3:-720}"

[ -n "$PROJECT" ] && [ -n "$CACHE" ] || exit 0

# Fresh enough? Nothing to do.
if [ -s "$CACHE" ] && [ -z "$(find "$CACHE" -mmin "+${MAX_AGE_MIN}" 2>/dev/null)" ]; then
    exit 0
fi

FOUND=""
for memfile in "$HOME"/.claude/projects/*/memory/MEMORY.md; do
    [ -f "$memfile" ] || continue
    if grep -qi "$PROJECT" "$memfile" 2>/dev/null; then
        FOUND="${memfile%/MEMORY.md}"
        break
    fi
done

[ -n "$FOUND" ] || exit 0

mkdir -p "$(dirname "$CACHE")" 2>/dev/null || true
# Write-then-rename: a concurrent session-start reading the cache must never
# see a half-written file.
if printf '%s\n' "$FOUND" > "${CACHE}.$$" 2>/dev/null; then
    mv -f "${CACHE}.$$" "$CACHE" 2>/dev/null || rm -f "${CACHE}.$$" 2>/dev/null
fi
exit 0
