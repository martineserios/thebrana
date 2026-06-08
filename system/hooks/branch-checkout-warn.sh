#!/usr/bin/env bash
# PreToolUse — warn when checking out a named local branch in the thebrana repo.
# git-discipline.md mandates worktrees over checkout for thebrana development.
# Narrowed per challenger W3: only fires on `git checkout <named-local-branch>`,
# not on file restores, detached HEAD, or tag checkouts.

INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null)
CWD=$(echo "$INPUT" | jq -r '.tool_input.cwd // ""' 2>/dev/null)

# Only intercept git checkout commands
echo "$CMD" | grep -qE '^git\s+checkout\s+' || { echo '{"continue": true}'; exit 0; }

# Only fire in the thebrana repo
THEBRANA_ROOT="${CLAUDE_PLUGIN_ROOT%/system}"
REAL_CWD=$(realpath "${CWD:-$(pwd)}" 2>/dev/null || echo "")
REAL_ROOT=$(realpath "$THEBRANA_ROOT" 2>/dev/null || echo "")
[[ "$REAL_CWD" == "$REAL_ROOT"* ]] || { echo '{"continue": true}'; exit 0; }

# Extract the target argument (strip flags like -b, --track, -f)
TARGET=$(echo "$CMD" | sed 's/git\s\+checkout\s*//' | tr -s ' ' | awk '{for(i=1;i<=NF;i++) if($i !~ /^-/) {print $i; exit}}')
[ -z "$TARGET" ] && { echo '{"continue": true}'; exit 0; }

# Skip if it looks like a file path (contains / or .)
echo "$TARGET" | grep -qE '[./]' && { echo '{"continue": true}'; exit 0; }

# Skip if it's a commit hash (hex string 6+ chars)
echo "$TARGET" | grep -qE '^[0-9a-f]{6,}$' && { echo '{"continue": true}'; exit 0; }

# Only warn if it's a real local branch (not a tag, not a remote)
git -C "$REAL_ROOT" show-ref --verify --quiet "refs/heads/$TARGET" 2>/dev/null || { echo '{"continue": true}'; exit 0; }

# It's a named local branch — warn and recommend worktree
cat <<JSON
{
  "continue": true,
  "additionalContext": "⚠ git checkout $TARGET in thebrana — git-discipline.md mandates worktrees. Prefer: git worktree add ../thebrana-$TARGET -b $TARGET. Direct checkout may remove hook files from working tree, breaking hooks in all projects."
}
JSON
