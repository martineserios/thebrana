#!/usr/bin/env bash
# No strict mode — hooks must always return valid JSON.

# Ensure valid CWD (may be in deleted worktree)
cd /tmp 2>/dev/null || true

# PreToolUse: Plan Mode Gate
#
# Blocks EnterPlanMode when an active /brana:build session exists
# (any task on the current branch with a non-null build_step).
#
# Rationale: /brana:build manages its own approval flow via AskUserQuestion
# and CC Tasks. CC plan mode conflicts with this — it locks the session into
# read-only mode and bypasses the build step registry.
#
# Graceful degradation: any failure → pass through (allow).

INPUT=$(cat)

pass_through() {
    echo '{"continue": true}'
    exit 0
}

deny() {
    local reason="$1"
    cat <<DENY_JSON
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "$reason"
  }
}
DENY_JSON
    exit 0
}

# Step 1: Parse input
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null) || pass_through
CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null) || pass_through

# Step 2: Only gate EnterPlanMode
case "$TOOL_NAME" in
    EnterPlanMode) ;;
    *) pass_through ;;
esac

# Step 3: Find git root
GIT_ROOT=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null) || pass_through
[ -z "$GIT_ROOT" ] && pass_through

# Step 4: Get current branch
BRANCH=$(git -C "$GIT_ROOT" branch --show-current 2>/dev/null) || pass_through
[ -z "$BRANCH" ] && pass_through

# Step 5: Check tasks.json for active build on this branch
TASKS_FILE="$GIT_ROOT/.claude/tasks.json"
[ ! -f "$TASKS_FILE" ] && pass_through

# Try brana CLI first (fast), fall back to jq
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/resolve-brana.sh"

BUILD_STEP=""
if [ -x "$BRANA" ]; then
    BUILD_STEP=$("$BRANA" backlog query --status active --output json 2>/dev/null | \
        jq -r --arg branch "$BRANCH" \
        '[.[] | select(.branch == $branch)] | first | .build_step // empty' 2>/dev/null) || BUILD_STEP=""
fi
if [ -z "$BUILD_STEP" ]; then
    BUILD_STEP=$(jq -r --arg branch "$BRANCH" \
        '[.tasks[] | select(.branch == $branch and .status == "in_progress")] | first | .build_step // empty' \
        "$TASKS_FILE" 2>/dev/null) || BUILD_STEP=""
fi

# Step 6: If build_step is set (any value), deny EnterPlanMode
case "$BUILD_STEP" in
    ""|null) pass_through ;;
    *) deny "/brana:build is active (step: $BUILD_STEP). Use the build skill's approval flow (AskUserQuestion) instead of CC plan mode. Plan mode conflicts with the build step registry." ;;
esac
