#!/usr/bin/env bash
# No strict mode — hooks must always return valid JSON.
# This hook uses || pass_through for graceful fallback.

# Ensure valid CWD (may be in deleted worktree)
cd /tmp 2>/dev/null || true

# PreToolUse: Spec-Before-Code Enforcement
#
# Blocks Write|Edit on implementation files when:
#   1. Project has opted in (docs/decisions/ exists)
#   2. On a feat/* branch
#   3. Task's build_step is "specify" or "plan" (hard gate), OR
#   4. No spec or test activity exists on the branch yet (soft gate)
#
# Always allows spec/test/doc file writes.
# Passes through on non-feat branches, non-git repos, and projects without docs/decisions/.
# Graceful degradation: any git failure → pass through.

INPUT=$(cat)

# Helper: pass through (allow the tool call, optionally with cascade context)
pass_through() {
    if [ -n "${CASCADE_CONTEXT:-}" ]; then
        local escaped
        escaped=$(echo "$CASCADE_CONTEXT" | jq -Rs '.' 2>/dev/null) || escaped='""'
        echo "{\"continue\": true, \"additionalContext\": $escaped}"
    else
        echo '{"continue": true}'
    fi
    exit 0
}

# Helper: deny with reason
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

# Step 2: Early exit — not Write or Edit
case "$TOOL_NAME" in
    Write|Edit) ;;
    *) pass_through ;;
esac

# Step 3: Extract file path and session ID
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null) || pass_through
[ -z "$FILE_PATH" ] && pass_through
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null) || true

# Step 3b: Cascade throttle check
# If post-tool-use-failure.sh flagged this file as cascading, inject a nudge (not a deny).
CASCADE_CONTEXT=""
if [ -n "$SESSION_ID" ] && [ -n "$FILE_PATH" ]; then
    PATH_HASH=$(echo -n "$FILE_PATH" | md5sum 2>/dev/null | cut -c1-12) || PATH_HASH=$(echo "$FILE_PATH" | tr '/' '-' | sed 's/^-//')
    CASCADE_FLAG="/tmp/brana-cascade/${SESSION_ID}-${PATH_HASH}"
    if [ -f "$CASCADE_FLAG" ]; then
        CASCADE_CONTEXT="[Cascade detected] This file has failed 3+ times consecutively. Stop and reassess your approach — the current strategy is not working. Consider: different edit strategy, reading the file first, or asking the user for guidance."
    fi
fi

# Step 4: Find git root
GIT_ROOT=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null) || pass_through
[ -z "$GIT_ROOT" ] && pass_through

# Step 5: Opt-in check — does a decisions directory exist?
# Support both layouts: docs/decisions/ and docs/architecture/decisions/
[ ! -d "$GIT_ROOT/docs/decisions" ] && [ ! -d "$GIT_ROOT/docs/architecture/decisions" ] && pass_through

# Step 6: Branch check — enforce on feat/*, fix/*, refactor/* branches
BRANCH=$(git -C "$GIT_ROOT" branch --show-current 2>/dev/null) || pass_through
case "$BRANCH" in
    feat/*|fix/*|refactor/*) ;;
    *) pass_through ;;
esac

# Step 7: Target file check — always allow spec/test/doc writes
# Make path relative to git root for pattern matching
REL_PATH="${FILE_PATH#"$GIT_ROOT/"}"

case "$REL_PATH" in
    docs/*) pass_through ;;
    test/*|tests/*|__tests__/*) pass_through ;;
    *.test.*|*.spec.*) pass_through ;;
    *.md) pass_through ;;
esac

# Step 8: build_step gate — check if the branch's task is past SPECIFY/PLAN
# If tasks.json has a task matching this branch with build_step in {specify, plan},
# deny implementation writes even if spec files exist (spec is still in progress).
TASKS_FILE="$GIT_ROOT/.claude/tasks.json"
if [ -f "$TASKS_FILE" ]; then
    # Use Rust CLI if available (fast), fall back to jq
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

    case "$BUILD_STEP" in
        specify|decompose)
            deny "Build step is '$BUILD_STEP' — complete the spec/decomposition before writing implementation code. Run /brana:build to advance to BUILD step."
            ;;
    esac
    # build, close, or empty/null → proceed to spec activity check
fi

# Step 9: Spec activity check — has any spec/test been touched on this branch?
MERGE_BASE=$(git -C "$GIT_ROOT" merge-base HEAD main 2>/dev/null || \
             git -C "$GIT_ROOT" merge-base HEAD master 2>/dev/null || echo "")
[ -z "$MERGE_BASE" ] && pass_through

SPEC_FILES=""

# Committed changes on this branch
SPEC_FILES="$SPEC_FILES$(git -C "$GIT_ROOT" diff --name-only "$MERGE_BASE"..HEAD -- \
    'docs/' 'test/' 'tests/' '__tests__/' '*.test.*' '*.spec.*' 2>/dev/null || true)"

# Staged changes
SPEC_FILES="$SPEC_FILES$(git -C "$GIT_ROOT" diff --cached --name-only -- \
    'docs/' 'test/' 'tests/' '__tests__/' '*.test.*' '*.spec.*' 2>/dev/null || true)"

# Unstaged changes
SPEC_FILES="$SPEC_FILES$(git -C "$GIT_ROOT" diff --name-only -- \
    'docs/' 'test/' 'tests/' '__tests__/' '*.test.*' '*.spec.*' 2>/dev/null || true)"

# Step 10: Decision
SPEC_FILES_TRIMMED=$(echo "$SPEC_FILES" | tr -d '[:space:]')
[ -n "$SPEC_FILES_TRIMMED" ] && pass_through

# Step 11: Block — no spec activity found
deny "Spec-first: write tests before implementation on feat/fix/refactor branches. No spec or test activity found on this branch yet."
