#!/usr/bin/env bash
set -euo pipefail

# Brana PostToolUse hook — log significant tool successes during session.
# Input:  stdin JSON (session_id, tool_name, tool_input, cwd)
# Output: stdout JSON (minimal — async hook)

INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')
TOOL_INPUT=$(echo "$INPUT" | jq -r '.tool_input // "{}"')

if [ -z "$SESSION_ID" ] || [ -z "$TOOL_NAME" ]; then
    echo '{"continue": true}'
    exit 0
fi

TS=$(date +%s)
DETAIL=""

case "$TOOL_NAME" in
    Bash)
        CMD=$(echo "$TOOL_INPUT" | jq -r '.command // empty' 2>/dev/null)
        DETAIL="$CMD"
        ;;
    Edit|Write)
        DETAIL=$(echo "$TOOL_INPUT" | jq -r '.file_path // empty' 2>/dev/null)
        ;;
    *)
        DETAIL="$TOOL_NAME"
        ;;
esac

# Append event to session temp file
SESSION_FILE="/tmp/brana-session-${SESSION_ID}.jsonl"
jq -n -c \
    --argjson ts "$TS" \
    --arg tool "$TOOL_NAME" \
    --arg outcome "success" \
    --arg detail "$DETAIL" \
    '{ts: $ts, tool: $tool, outcome: $outcome, detail: $detail}' >> "$SESSION_FILE"

echo '{"continue": true}'
