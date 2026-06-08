#!/usr/bin/env bash
# PostToolUse — auto-deploy hooks to ~/.claude/hooks/ when a hook file is edited on main.
# This is the bootstrap agent: intentionally points at ${CLAUDE_PLUGIN_ROOT} so it survives
# before the initial make hooks-deploy runs. All other hooks point at ~/.claude/hooks/.

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // ""' 2>/dev/null)

# Only fire on Write|Edit touching hook files or hooks.json
case "$TOOL" in Write|Edit) ;; *) echo '{"continue": true}'; exit 0 ;; esac

HOOKS_DIR="${CLAUDE_PLUGIN_ROOT}/hooks"
case "$FILE" in
    *system/hooks/*|*/.claude/hooks/*) ;;
    *) echo '{"continue": true}'; exit 0 ;;
esac

# Only deploy from main — never from feature branches (challenger W2)
BRANCH=$(git -C "${CLAUDE_PLUGIN_ROOT}" branch --show-current 2>/dev/null)
if [ "$BRANCH" != "main" ]; then
    echo '{"continue": true}'
    exit 0
fi

# Deploy
rsync -a --delete "${HOOKS_DIR}/" "$HOME/.claude/hooks/" 2>/dev/null
echo '{"continue": true}'
