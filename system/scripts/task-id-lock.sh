#!/usr/bin/env bash
# Task ID lock — shared across worktrees via $GIT_COMMON_DIR
#
# Usage: task-id-lock.sh next-id <repo-path> <prefix>
# Output: next ID number (e.g., "101")
#
# Uses flock on a shared lock file in the git common directory,
# which is shared across all worktrees of the same repo.
# This prevents ID collisions when parallel sessions create tasks.

set -euo pipefail

CMD="${1:-}"
REPO_PATH="${2:-}"
PREFIX="${3:-t}"

[ "$CMD" = "next-id" ] || { echo "Usage: task-id-lock.sh next-id <repo-path> <prefix>" >&2; exit 1; }
[ -n "$REPO_PATH" ] || { echo "Error: repo-path required" >&2; exit 1; }

# Find the git common dir (shared across all worktrees)
GIT_COMMON_DIR=$(git -C "$REPO_PATH" rev-parse --git-common-dir 2>/dev/null) || {
    echo "Error: not a git repo: $REPO_PATH" >&2; exit 1
}

# Lock file lives in the shared git dir
LOCK_FILE="$GIT_COMMON_DIR/.brana-task-id.lock"
COUNTER_FILE="$GIT_COMMON_DIR/.brana-task-counter"

# Atomic ID generation with flock
(
    flock -w 5 200 || { echo "Error: could not acquire lock" >&2; exit 1; }

    # Read current counter (or initialize from tasks.json)
    if [ -f "$COUNTER_FILE" ]; then
        CURRENT=$(cat "$COUNTER_FILE")
    else
        # Bootstrap from tasks.json — find highest existing ID
        TASKS_FILE="$REPO_PATH/.claude/tasks.json"
        if [ -f "$TASKS_FILE" ]; then
            CURRENT=$(jq -r "[.tasks[]?.id // .[]?.id // empty] | map(select(startswith(\"${PREFIX}-\")) | ltrimstr(\"${PREFIX}-\") | tonumber) | max // 0" "$TASKS_FILE" 2>/dev/null) || CURRENT=0
        else
            CURRENT=0
        fi
    fi

    # Increment
    NEXT=$((CURRENT + 1))

    # Write back
    echo "$NEXT" > "$COUNTER_FILE"

    # Output the new ID
    echo "$NEXT"

) 200>"$LOCK_FILE"
