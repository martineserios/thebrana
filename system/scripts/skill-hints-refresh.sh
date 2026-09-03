#!/usr/bin/env bash
# skill-hints-refresh.sh — rebuild the session-start skill-hints cache (t-2988).
#
# session-start.sh used to compute the top-6-skills-by-usage hint block inline,
# on its synchronous path, from `brana skills usage --days 30`. That command
# walks every transcript under ~/.claude/projects — 15,844 file opens and ~29.5s
# of CPU on a well-used $HOME — which on its own put session start past its 8s
# budget and was misread as the timing test being too strict.
#
# Ranking six skills over a 30-day window is slow-moving data, so it does not
# belong on a latency-critical path at all. The hook now only reads the cache
# this script writes, and calls this from its Phase 5 background block, after
# the JSON contract has already been emitted.
#
# Usage: skill-hints-refresh.sh <brana-bin> <git-root> <cache-path> [max-age-min]
# Exit is always 0: this is best-effort enrichment, never a session blocker.

BRANA_BIN="${1:-}"
GIT_ROOT="${2:-$PWD}"
CACHE="${3:-$HOME/.claude/cache/skill-hints.txt}"
MAX_AGE_MIN="${4:-720}"

[ -n "$BRANA_BIN" ] && [ -x "$BRANA_BIN" ] || exit 0

# Fresh enough? Nothing to do.
if [ -s "$CACHE" ] && [ -z "$(find "$CACHE" -mmin "+${MAX_AGE_MIN}" 2>/dev/null)" ]; then
    exit 0
fi

# Timeout-bounded even here: this runs disowned, so a hung CLI would otherwise
# leave an orphan behind for the rest of the session.
SKILLS_LIST_JSON=$(cd "$GIT_ROOT" && timeout -k 5 60 "$BRANA_BIN" skills list 2>/dev/null) || SKILLS_LIST_JSON=""
TOP_USAGE=$(cd "$GIT_ROOT" && timeout -k 5 120 "$BRANA_BIN" skills usage --days 30 --json 2>/dev/null \
    | jq -r '[.skills[].name] | .[:6] | .[]' 2>/dev/null) || TOP_USAGE=""

[ -n "$TOP_USAGE" ] && [ -n "$SKILLS_LIST_JSON" ] || exit 0

HINT_LINES=""
while IFS= read -r skill_name; do
    [ -n "$skill_name" ] || continue
    slug="${skill_name#brana:}"
    slug="${slug#plugin:brana:}"
    hint=$(echo "$SKILLS_LIST_JSON" | jq -r --arg n "$slug" \
        '.[] | select(.name == $n) | .argument_hint // ""' 2>/dev/null | head -1) || hint=""
    HINT_LINES="${HINT_LINES:+$HINT_LINES
}/$skill_name${hint:+ $hint}"
done <<< "$TOP_USAGE"

[ -n "$HINT_LINES" ] || exit 0

mkdir -p "$(dirname "$CACHE")" 2>/dev/null || true
# Write-then-rename: a concurrent session-start reading the cache must never
# see a half-written file.
if printf 'Top skills (by usage):\n%s\n' "$HINT_LINES" > "${CACHE}.$$" 2>/dev/null; then
    mv -f "${CACHE}.$$" "$CACHE" 2>/dev/null || rm -f "${CACHE}.$$" 2>/dev/null
fi
exit 0
