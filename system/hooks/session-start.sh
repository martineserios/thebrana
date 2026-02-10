#!/usr/bin/env bash
set -euo pipefail

# Brana SessionStart hook — recall relevant patterns at session start.
# Input:  stdin JSON (session_id, cwd, hook_event_name, matcher)
# Output: stdout JSON with additionalContext field

INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')

if [ -z "$SESSION_ID" ] || [ -z "$CWD" ]; then
    echo '{"continue": true}'
    exit 0
fi

# Derive project name from git root or cwd
GIT_ROOT=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null || echo "$CWD")
PROJECT=$(basename "$GIT_ROOT")

# Write env vars for downstream hooks if CLAUDE_ENV_FILE exists
if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
    echo "BRANA_PROJECT=$PROJECT" >> "$CLAUDE_ENV_FILE"
    echo "BRANA_SESSION_ID=$SESSION_ID" >> "$CLAUDE_ENV_FILE"
fi

CONTEXT=""

# Primary path: claude-flow memory search (run from $HOME for global DB)
if command -v npx &>/dev/null; then
    CONTEXT=$(cd "$HOME" && timeout 5 npx claude-flow memory search -q "project:$PROJECT" --format json 2>/dev/null || true)
fi

# Fallback: grep native auto memory for project name
if [ -z "$CONTEXT" ]; then
    MEMORY_HIT=""
    for memfile in "$HOME"/.claude/projects/*/memory/MEMORY.md; do
        if [ -f "$memfile" ]; then
            MATCH=$(grep -i "$PROJECT" "$memfile" 2>/dev/null | head -5 || true)
            if [ -n "$MATCH" ]; then
                MEMORY_HIT="$MEMORY_HIT$MATCH"$'\n'
            fi
        fi
    done
    if [ -n "$MEMORY_HIT" ]; then
        CONTEXT="$MEMORY_HIT"
    fi
fi

# Output — only inject context if we found something
if [ -n "$CONTEXT" ]; then
    # Escape for JSON embedding
    ESCAPED=$(echo "$CONTEXT" | jq -Rs '.')
    echo "{\"continue\": true, \"additionalContext\": $ESCAPED}"
else
    echo '{"continue": true}'
fi
