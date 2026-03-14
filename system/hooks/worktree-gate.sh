#!/usr/bin/env bash
# PreToolUse: Worktree Enforcement Gate
#
# Intercepts Bash tool calls containing `git checkout -b` or `git switch -c`.
# Denies when:
#   1. Uncommitted changes exist (dirty working tree or staged changes)
#   2. Other worktrees are active on the same repo
# Suggests `git worktree add` or `claude --worktree` instead.
#
# Always passes through non-Bash tools, non-checkout commands, and non-git dirs.

INPUT=$(cat)

# Helper: pass through
pass_through() {
    echo '{"continue": true}'
    exit 0
}

# Helper: deny with reason
deny() {
    local reason="$1"
    local escaped
    escaped=$(echo "$reason" | sed 's/"/\\"/g')
    cat <<DENY_JSON
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "$escaped"
  }
}
DENY_JSON
    exit 0
}

# Step 1: Parse input
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null) || pass_through

# Step 2: Only intercept Bash
[ "$TOOL_NAME" = "Bash" ] || pass_through

# Step 3: Extract command
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null) || pass_through
[ -n "$CMD" ] || pass_through

# Step 4: Check if command contains branch-creating checkout
# Match: git checkout -b, git switch -c (anywhere in command, including chained)
if ! echo "$CMD" | grep -qE '(git\s+checkout\s+.*-b\s|git\s+switch\s+.*-c\s|git\s+checkout\s+.*-b$|git\s+switch\s+.*-c$)'; then
    pass_through
fi

# Step 5: Find git root from CWD
CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null) || pass_through
[ -n "$CWD" ] || pass_through

GIT_ROOT=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null) || pass_through
[ -n "$GIT_ROOT" ] || pass_through

# Step 6: Check for uncommitted changes (dirty tree or staged)
DIRTY=""
if ! git -C "$GIT_ROOT" diff --quiet 2>/dev/null; then
    DIRTY="unstaged changes"
elif ! git -C "$GIT_ROOT" diff --cached --quiet 2>/dev/null; then
    DIRTY="staged changes"
fi

# Step 7: Check for active worktrees (beyond the main one)
WORKTREE_COUNT=$(git -C "$GIT_ROOT" worktree list --porcelain 2>/dev/null | grep -c '^worktree ' || echo "0")

# Step 8: Extract branch name from the command for the suggestion
BRANCH_NAME=$(echo "$CMD" | grep -oP '(checkout\s+-b|switch\s+-c)\s+\K\S+' 2>/dev/null || echo "branch-name")

# Step 9: Decide
if [ -n "$DIRTY" ]; then
    deny "Worktree required: $DIRTY detected. Use \`git worktree add ../<repo>-${BRANCH_NAME} -b ${BRANCH_NAME}\` or \`claude --worktree ${BRANCH_NAME}\` instead of \`git checkout -b\`. See git-discipline rule."
elif [ "$WORKTREE_COUNT" -gt 1 ]; then
    WT_LIST=$(git -C "$GIT_ROOT" worktree list --porcelain 2>/dev/null | grep '^worktree ' | sed 's/^worktree /  /' | head -5)
    deny "Worktree required: ${WORKTREE_COUNT} worktrees already active on this repo. Use \`git worktree add ../<repo>-${BRANCH_NAME} -b ${BRANCH_NAME}\` instead of checkout to avoid conflicts. Active worktrees:\n${WT_LIST}"
fi

# Clean state, no other worktrees — allow
pass_through
