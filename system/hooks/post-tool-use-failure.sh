#!/usr/bin/env bash
# No strict mode — failure hooks especially must never fail themselves.

# Brana PostToolUseFailure hook — log tool failures during session.
# Failures are often more valuable than successes for learning.
# Input:  stdin JSON (session_id, tool_name, tool_input, cwd)
# Output: stdout JSON (minimal — async hook)

# Ensure valid CWD (may be in deleted worktree)
cd /tmp 2>/dev/null || true

INPUT=$(cat) || true
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null) || true
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null) || true
TOOL_INPUT=$(echo "$INPUT" | jq -r '.tool_input // "{}"' 2>/dev/null) || true

if [ -n "${SESSION_ID:-}" ] && [ -n "${TOOL_NAME:-}" ]; then
    TS=$(date +%s 2>/dev/null) || TS=0
    DETAIL=""

    case "${TOOL_NAME:-}" in
        Bash)
            DETAIL=$(echo "$TOOL_INPUT" | jq -r '.command // empty' 2>/dev/null) || DETAIL=""
            ;;
        Edit|Write)
            DETAIL=$(echo "$TOOL_INPUT" | jq -r '.file_path // empty' 2>/dev/null) || DETAIL=""
            ;;
        *)
            DETAIL="${TOOL_NAME:-unknown}"
            ;;
    esac

    SESSION_FILE="/tmp/brana-session-${SESSION_ID}.jsonl"
    jq -n -c \
        --argjson ts "${TS:-0}" \
        --arg tool "${TOOL_NAME:-unknown}" \
        --arg outcome "failure" \
        --arg detail "${DETAIL:-unknown}" \
        '{ts: $ts, tool: $tool, outcome: $outcome, detail: $detail}' >> "$SESSION_FILE" 2>/dev/null || true
fi

echo '{"continue": true}'
