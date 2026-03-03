#!/usr/bin/env bash
# No strict mode — hooks must never fail and block the session.

# Brana PostToolUse hook — nudge pr-reviewer agent after gh pr create.
# Input:  stdin JSON (session_id, tool_name, tool_input, cwd)
# Output: stdout JSON with additionalContext nudging code review

# Ensure valid CWD
cd /tmp 2>/dev/null || true

INPUT=$(cat) || true
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null) || true

# Fast exit — only care about Bash
if [ "${TOOL_NAME:-}" != "Bash" ]; then
    echo '{"continue": true}'
    exit 0
fi

TOOL_INPUT=$(echo "$INPUT" | jq -r '.tool_input // "{}"' 2>/dev/null) || true
COMMAND=$(echo "$TOOL_INPUT" | jq -r '.command // empty' 2>/dev/null) || COMMAND=""

# Check for gh pr create
if ! echo "$COMMAND" | grep -qE '(^|\s)gh\s+pr\s+create(\s|$)' 2>/dev/null; then
    echo '{"continue": true}'
    exit 0
fi

SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null) || true

# Log to session JSONL
if [ -n "${SESSION_ID:-}" ]; then
    SESSION_FILE="/tmp/brana-session-${SESSION_ID}.jsonl"
    jq -n -c \
        --argjson ts "$(date +%s 2>/dev/null || echo 0)" \
        --arg tool "post-pr-review" \
        --arg outcome "pr-create" \
        --arg detail "gh pr create detected, nudging pr-reviewer" \
        '{ts: $ts, tool: $tool, outcome: $outcome, detail: $detail}' >> "$SESSION_FILE" 2>/dev/null || true
fi

CONTEXT="A PR was just created. Auto-delegating to pr-reviewer agent for code review feedback — reads the diff and provides structured review."
ESCAPED=$(echo "$CONTEXT" | jq -Rs '.' 2>/dev/null) || ESCAPED='""'
echo "{\"continue\": true, \"additionalContext\": $ESCAPED}"
