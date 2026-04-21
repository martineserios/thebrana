#!/usr/bin/env bash
# Main Branch Guard — PreToolUse hook for Bash (git commit)
#
# Blocks commits on main/master when behavioral files are staged.
# Forces work onto feat/*/fix/* branches for proper gate enforcement.
#
# Always allows: non-behavioral commits on main (docs, config, chore),
# commits with --force-main flag, non-git-commit commands.

# Ensure valid CWD
cd /tmp 2>/dev/null || true

# Profile gate: standard tier
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/profile.sh" 2>/dev/null || true
source "${SCRIPT_DIR}/lib/git-helpers.sh" 2>/dev/null || true
if ! hook_should_run "standard" 2>/dev/null; then
    echo '{"continue": true}'
    exit 0
fi

INPUT=$(cat)

# Helper: pass through
pass_through() {
    echo '{"continue": true}'
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

# Step 1: Parse input — only act on Bash tool
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null) || pass_through
case "$TOOL_NAME" in
    Bash) ;;
    *) pass_through ;;
esac

# Step 2: Extract command — only fire on git commit
CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null) || pass_through
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null) || pass_through
[ -z "$COMMAND" ] && pass_through
case "$COMMAND" in
    *"git commit"*)       ;;   # direct: git commit -m "..."
    *"git -C"*"commit"*)  ;;   # worktree: git -C <path> commit -m "..."
    *) pass_through ;;
esac

# Step 3: Escape hatch — --force-main in commit message
case "$COMMAND" in
    *"--force-main"*) pass_through ;;
esac

# Step 4: Find git root — use -C path if present (worktree support, same fix as branch-verify)
LOOKUP_DIR=$(resolve_lookup_dir "$COMMAND" "$CWD")
GIT_ROOT=$(git -C "$LOOKUP_DIR" rev-parse --show-toplevel 2>/dev/null) || pass_through
[ -z "$GIT_ROOT" ] && pass_through

BRANCH=$(git -C "$LOOKUP_DIR" branch --show-current 2>/dev/null) || pass_through
case "$BRANCH" in
    main|master) ;;
    *) pass_through ;;  # Not on main — let other gates handle it
esac

# Step 5: Check staged files for behavioral patterns (use LOOKUP_DIR — worktrees have own index)
STAGED=$(git -C "$LOOKUP_DIR" diff --cached --name-only 2>/dev/null) || pass_through
[ -z "$STAGED" ] && pass_through

BEHAVIORAL_FILES=""
while IFS= read -r file; do
    case "$file" in
        system/skills/*|system/hooks/*|system/agents/*|system/commands/*|system/cli/*|*/rules/*)
            if [ -z "$BEHAVIORAL_FILES" ]; then
                BEHAVIORAL_FILES="$file"
            else
                BEHAVIORAL_FILES="$BEHAVIORAL_FILES, $file"
            fi
            ;;
    esac
done <<< "$STAGED"

# No behavioral files — allow commit on main (docs, config, chore are fine)
[ -z "$BEHAVIORAL_FILES" ] && pass_through

# Step 6: Deny — behavioral files on main
deny "Main guard: behavioral files should be committed on a feature branch, not main. Files: $BEHAVIORAL_FILES. Create a branch first: git checkout -b feat/your-feature. Use --force-main to bypass."
