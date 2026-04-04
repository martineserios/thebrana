#!/usr/bin/env bash
# No strict mode — hooks must always return valid JSON.

# Ensure valid CWD (may be in deleted worktree)
cd /tmp 2>/dev/null || true

# PreToolUse: Plan Mode Gate
#
# Blocks EnterPlanMode when /brana:build is in an execution phase (BUILD/CLOSE).
# Allows plan mode during read-only analysis phases (CLASSIFY/SPECIFY/DECOMPOSE/APPROVE).
#
# Rationale: Plan mode is valuable for SPECIFY and DECOMPOSE — they're read-only
# analysis where structured planning output helps. But during BUILD, plan mode
# conflicts with the build step registry and locks the session read-only.
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

# Step 6: Allow plan mode during read-only phases, block during execution phases
# Pre-BUILD phases (CLASSIFY, SPECIFY, DECOMPOSE, APPROVE) benefit from plan mode.
# BUILD and CLOSE phases conflict with the step registry and need write access.
case "$BUILD_STEP" in
    ""|null) pass_through ;;
    CLASSIFY|SPECIFY|DECOMPOSE|APPROVE) pass_through ;;
    BUILD|CLOSE) deny "/brana:build is in execution phase (step: $BUILD_STEP). Plan mode conflicts with the build step registry during BUILD/CLOSE. Use AskUserQuestion for approval instead." ;;
    *) deny "/brana:build is active (step: $BUILD_STEP). Exit the build step or complete it before entering plan mode." ;;
esac
