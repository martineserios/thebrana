#!/usr/bin/env bash
# Branch Verify — PreToolUse hook for Bash (git add)
#
# Blocks `git add` of behavioral files when on main/master.
# Root cause: ephemeral branch switches don't persist across Bash invocations —
# this gate catches the mistake at staging time, before main-guard at commit time.
#
# Behavioral paths: system/hooks/, system/skills/, system/procedures/,
#                   system/agents/, system/commands/, system/cli/, .claude/rules/
#
# Escape hatch: --force-main anywhere in the command

cd /tmp 2>/dev/null || true

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/profile.sh" 2>/dev/null || true
source "${SCRIPT_DIR}/lib/git-helpers.sh" 2>/dev/null || true
if ! hook_should_run "standard" 2>/dev/null; then
    echo '{"continue": true}'
    exit 0
fi

INPUT=$(cat)

pass_through() {
    echo '{"continue": true}'
    exit 0
}

deny() {
    local reason="$1"
    local escaped
    escaped=$(printf '%s' "$reason" | sed 's/\\/\\\\/g; s/"/\\"/g')
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

# Step 1: Only intercept Bash
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null) || pass_through
[ "$TOOL_NAME" = "Bash" ] || pass_through

# Step 2: Only fire on git add
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null) || pass_through
[ -n "$COMMAND" ] || pass_through
echo "$COMMAND" | grep -qE 'git\s+add\b' || pass_through

# Step 3: Escape hatch
echo "$COMMAND" | grep -q '\-\-force-main' && pass_through

# Step 4: Find git root and check branch
# If the command uses `git -C <path>`, check that repo's branch (worktree support).
# Otherwise fall back to CWD (the session's working directory).
CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null) || pass_through
[ -n "$CWD" ] || pass_through
LOOKUP_DIR=$(resolve_lookup_dir "$COMMAND" "$CWD")
GIT_ROOT=$(git -C "$LOOKUP_DIR" rev-parse --show-toplevel 2>/dev/null) || pass_through
[ -n "$GIT_ROOT" ] || pass_through

BRANCH=$(git -C "$GIT_ROOT" branch --show-current 2>/dev/null) || pass_through
case "$BRANCH" in
    main|master) ;;
    *) pass_through ;;
esac

# Step 5: Determine which behavioral files would be staged
BEHAVIORAL_PATHS="system/hooks system/skills system/procedures system/agents system/commands system/cli .claude/rules"

is_behavioral() {
    local file="$1"
    file=$(echo "$file" | sed 's|^\./||; s|/$||')  # strip leading ./ and trailing /
    for bpath in $BEHAVIORAL_PATHS; do
        case "$file" in
            # File is under a behavioral path, or IS a behavioral path
            ${bpath}|${bpath}/*) return 0 ;;
        esac
    done
    return 1
}

BEHAVIORAL_FILES=""

add_behavioral() {
    local f="$1"
    if is_behavioral "$f"; then
        BEHAVIORAL_FILES="${BEHAVIORAL_FILES:+${BEHAVIORAL_FILES}, }${f}"
    fi
}

# Broad add (git add . / -A / --all) — inspect working tree including untracked
if echo "$COMMAND" | grep -qE 'git\s+add\s+(-A|--all|\.)(\s|$)'; then
    while IFS= read -r status_line; do
        [ -z "$status_line" ] && continue
        file="${status_line:3}"
        add_behavioral "$file"
    done < <(git -C "$GIT_ROOT" status --porcelain 2>/dev/null)
else
    # Explicit paths — strip the 'git add' prefix and any flags
    args_str=$(echo "$COMMAND" | sed 's/.*git[[:space:]]\+add[[:space:]]*//')
    while IFS= read -r arg; do
        [ -z "$arg" ] && continue
        case "$arg" in -*)  continue ;; esac
        add_behavioral "$arg"
    done < <(echo "$args_str" | tr ' ' '\n')
fi

[ -z "$BEHAVIORAL_FILES" ] && pass_through

deny "Branch verify: cannot stage behavioral files on '${BRANCH}'. Files: ${BEHAVIORAL_FILES}. Branch switches are ephemeral — verify with 'git branch --show-current' before staging. Create a feature branch first: git switch -c feat/your-task. Use --force-main to bypass."
