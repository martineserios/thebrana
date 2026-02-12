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

# Locate claude-flow binary (nvm global → PATH → npx fallback)
CF=""
for candidate in "$HOME"/.nvm/versions/node/*/bin/claude-flow; do
    [ -x "$candidate" ] && CF="$candidate" && break
done
[ -z "$CF" ] && command -v claude-flow &>/dev/null && CF="claude-flow"
[ -z "$CF" ] && command -v npx &>/dev/null && CF="npx claude-flow"

# Primary path: claude-flow memory search
if [ -n "$CF" ]; then
    CONTEXT=$(timeout 5 $CF memory search --query "project:$PROJECT" --format json 2>&1 | grep -v '^\[' || true)
fi

# Log recalled patterns to session file for promotion tracking
if [ -n "$CONTEXT" ]; then
    SESSION_FILE="/tmp/brana-session-${SESSION_ID}.jsonl"
    jq -n -c \
        --argjson ts "$(date +%s)" \
        --arg tool "session-start" \
        --arg outcome "recall" \
        --arg detail "$CONTEXT" \
        '{ts: $ts, tool: $tool, outcome: $outcome, detail: $detail}' >> "$SESSION_FILE"
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
    # Prepend confidence note so the model knows pattern maturity
    CONTEXT_WITH_NOTE="[Recalled patterns — confidence:quarantine means unproven, treat with caution. confidence:proven means validated across 3+ sessions.]
$CONTEXT"
    # Escape for JSON embedding
    ESCAPED=$(echo "$CONTEXT_WITH_NOTE" | jq -Rs '.')
    echo "{\"continue\": true, \"additionalContext\": $ESCAPED}"
else
    echo '{"continue": true}'
fi
