#!/usr/bin/env bash
# check-adr-uniqueness.sh — no two ADRs may share a number (t-2515).
#
# Usage: check-adr-uniqueness.sh [decisions-dir]
#   default dir: docs/architecture/decisions relative to the repo root
#   exit 0 = every ADR number is used once
#   exit 1 = a number is used twice (or the directory is missing)
#
# WHY THIS EXISTS. On 2026-07-28 five ADR numbers were colliding at once.
# Four (002, 026, 048, 062) had sat duplicated on dev for months — the 002
# collision was even noted in an audit in March and deferred. The fifth (068)
# was created that same day: the number was chosen by listing this directory
# on a feature branch, which cannot see a newer ADR added on dev.
#
# A directory listing is not an allocator. This check is the backstop that
# makes the collision loud at the next validate instead of at merge time,
# months later. It deliberately does NOT try to suggest the next free number —
# doing that correctly also requires consulting other branches and numbers
# claimed in backlog task text, which is the separate half of t-2515.
set -uo pipefail

DIR="${1:-}"
if [ -z "$DIR" ]; then
    ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || ROOT="."
    DIR="$ROOT/docs/architecture/decisions"
fi

if [ ! -d "$DIR" ]; then
    echo "check-adr-uniqueness: directory not found: $DIR" >&2
    exit 1
fi

# Numbers used more than once. `ls` is fine here — ADR filenames are
# ASCII by convention and this runs on a flat directory.
DUPES=$(ls "$DIR" 2>/dev/null \
    | grep -oE '^ADR-[0-9]+' \
    | sort \
    | uniq -d)

if [ -z "$DUPES" ]; then
    exit 0
fi

echo "check-adr-uniqueness: duplicate ADR number(s) in $DIR" >&2
while IFS= read -r num; do
    [ -n "$num" ] || continue
    echo "  $num is used by:" >&2
    ls "$DIR" | grep -E "^${num}-" | sed 's/^/    /' >&2
done <<EOF
$DUPES
EOF
echo "  Renumber the side with fewer inbound references, then update every" >&2
echo "  filename-form reference. Bare 'ADR-NNN' citations are ambiguous —" >&2
echo "  classify each by meaning before substituting (other projects' ADRs" >&2
echo "  share this numbering space in errata docs)." >&2
exit 1
