#!/usr/bin/env bash
# No strict mode — hooks must never fail and block the session.

# Brana PostToolUse hook — nudge challenger agent after plan finalization.
# Input:  stdin JSON (session_id, tool_name, tool_input, cwd)
# Output: stdout JSON with additionalContext nudging adversarial review

# Ensure valid CWD
cd /tmp 2>/dev/null || true

INPUT=$(cat) || true
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null) || true

# Fast exit — only care about ExitPlanMode
if [ "${TOOL_NAME:-}" != "ExitPlanMode" ]; then
    echo '{"continue": true}'
    exit 0
fi

SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null) || true

# Log to session JSONL
if [ -n "${SESSION_ID:-}" ]; then
    SESSION_FILE="/tmp/brana-session-${SESSION_ID}.jsonl"
    jq -n -c \
        --argjson ts "$(date +%s 2>/dev/null || echo 0)" \
        --arg tool "post-plan-challenge" \
        --arg outcome "plan-finalized" \
        --arg detail "ExitPlanMode detected, nudging challenger" \
        '{ts: $ts, tool: $tool, outcome: $outcome, detail: $detail}' >> "$SESSION_FILE" 2>/dev/null || true
fi

CONTEXT="A plan was just finalized. Auto-delegating to challenger agent for adversarial review — stress-test the plan for blind spots, missing edge cases, and architectural risks before the user approves."
ESCAPED=$(echo "$CONTEXT" | jq -Rs '.' 2>/dev/null) || ESCAPED='""'
echo "{\"continue\": true, \"additionalContext\": $ESCAPED}"
