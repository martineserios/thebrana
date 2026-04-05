#!/usr/bin/env bash
# Documentation Enforcement Gate — PreToolUse hook for Bash (git commit)
#
# Blocks git commit on feat/*/fix/* branches when behavioral files
# (skills, hooks, agents, commands, cli, rules) are staged but no
# documentation file is staged alongside them.
#
# Always allows: non-git-commit bash commands, non-feat/fix branches,
# commits with --no-doc-check flag, commits that include doc files.

# Ensure valid CWD
cd /tmp 2>/dev/null || true

# Profile gate: standard tier
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/profile.sh" 2>/dev/null || true
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

# Step 1: Parse input
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null) || pass_through
CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null) || pass_through

# Step 2: Only act on Bash tool
case "$TOOL_NAME" in
    Bash) ;;
    *) pass_through ;;
esac

# Step 3: Extract command — only fire on git commit
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null) || pass_through
[ -z "$COMMAND" ] && pass_through
case "$COMMAND" in
    *"git commit"*) ;;
    *) pass_through ;;
esac

# Step 4: Escape hatch — --no-doc-check in commit message
case "$COMMAND" in
    *"--no-doc-check"*) pass_through ;;
esac

# Step 5: Find git root
GIT_ROOT=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null) || pass_through
[ -z "$GIT_ROOT" ] && pass_through

# Step 6: Branch check — only enforce on feat/* and fix/*
BRANCH=$(git -C "$GIT_ROOT" branch --show-current 2>/dev/null) || pass_through
case "$BRANCH" in
    feat/*|fix/*) ;;
    *) pass_through ;;
esac

# Step 7: Check staged files for behavioral and doc patterns
STAGED=$(git -C "$GIT_ROOT" diff --cached --name-only 2>/dev/null) || pass_through
[ -z "$STAGED" ] && pass_through

# Collect behavioral files
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

# No behavioral files staged — pass through
[ -z "$BEHAVIORAL_FILES" ] && pass_through

# Check for doc files
HAS_DOCS=false
while IFS= read -r file; do
    case "$file" in
        docs/architecture/*|docs/guide/*|docs/reference/*|*CLAUDE.md)
            HAS_DOCS=true
            break
            ;;
    esac
done <<< "$STAGED"

# Step 8: Decision
if [ "$HAS_DOCS" = true ]; then
    pass_through
else
    deny "Doc gate: behavioral files staged without documentation. Files: $BEHAVIORAL_FILES. Add a doc update (docs/architecture/, docs/guide/, CLAUDE.md) or use --no-doc-check to bypass."
fi
