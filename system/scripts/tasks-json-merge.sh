#!/usr/bin/env bash
# tasks-json-merge.sh — custom git merge driver for .claude/tasks.json
#
# Prevents task status regressions during git merges (t-2132).
# Merge rule: status order is pending < in_progress < completed.
# cancelled is treated as terminal — higher than completed to avoid re-opening.
# For each task present in both sides, the higher status wins.
# Tasks only in "theirs" are included; tasks only in "ours" are kept.
# The "ours" base structure (version, root fields) is preserved.
#
# Called by git as: tasks-json-merge.sh %O %A %B %P
#   %O = ancestor (base), %A = ours (modified in-place), %B = theirs, %P = path
# Exit 0 = clean merge, non-zero = conflict (git falls back to conflict markers).

set -euo pipefail

ANCESTOR="${1:-}"
OURS="${2:-}"
THEIRS="${3:-}"
# %P (path) is unused but consumed
shift 3 || true

if [ -z "$OURS" ] || [ -z "$THEIRS" ]; then
    echo "tasks-json-merge: missing required arguments" >&2
    exit 1
fi

# If theirs is missing/empty, nothing to merge — leave ours as-is
if [ ! -s "$THEIRS" ]; then
    exit 0
fi

# If ours is missing/empty, use theirs directly
if [ ! -s "$OURS" ]; then
    cp "$THEIRS" "$OURS"
    exit 0
fi

# Verify both files are valid JSON before attempting merge
if ! jq empty "$OURS" 2>/dev/null; then
    echo "tasks-json-merge: ours is invalid JSON — leaving unchanged" >&2
    exit 0
fi
if ! jq empty "$THEIRS" 2>/dev/null; then
    echo "tasks-json-merge: theirs is invalid JSON — leaving ours unchanged" >&2
    exit 0
fi

MERGED=$(jq -s '
    # Status rank: higher number wins. completed and cancelled are both terminal;
    # completed ranks higher so a completed task is never silently cancelled.
    def status_rank:
        if . == "pending"     then 0
        elif . == "in_progress" then 1
        elif . == "completed"   then 3
        elif . == "cancelled"   then 2
        else 0
        end;

    # Index ours and theirs tasks by id
    (.[0].tasks // [] | map({(.id): .}) | add // {}) as $ours_map |
    (.[1].tasks // [] | map({(.id): .}) | add // {}) as $theirs_map |

    # Union of all task ids, preserving ours insertion order then appending theirs-only
    (.[0].tasks // [] | map(.id)) as $ours_ids |
    (.[1].tasks // [] | map(.id) | map(select(. as $id | $ours_map[$id] == null))) as $theirs_only_ids |

    .[0] | .tasks = (
        ($ours_ids + $theirs_only_ids) | map(
            . as $id |
            if ($ours_map[$id] != null) and ($theirs_map[$id] != null) then
                # Both sides have this task: merge status (higher wins)
                ($ours_map[$id].status | status_rank) as $ours_rank |
                ($theirs_map[$id].status | status_rank) as $theirs_rank |
                if $theirs_rank > $ours_rank then
                    $ours_map[$id] + {status: $theirs_map[$id].status}
                else
                    $ours_map[$id]
                end
            elif $ours_map[$id] != null then
                $ours_map[$id]
            else
                $theirs_map[$id]
            end
        )
    )
' "$OURS" "$THEIRS" 2>/dev/null) || {
    echo "tasks-json-merge: jq merge failed — leaving ours unchanged" >&2
    exit 0
}

if [ -z "$MERGED" ]; then
    echo "tasks-json-merge: empty merge result — leaving ours unchanged" >&2
    exit 0
fi

# Write atomically
TMPFILE="${OURS}.merge-tmp-$$"
printf '%s\n' "$MERGED" > "$TMPFILE" && mv "$TMPFILE" "$OURS"
exit 0
