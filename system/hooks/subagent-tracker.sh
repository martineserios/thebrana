#!/usr/bin/env bash
# No strict mode — hooks must never fail and block the session.

# Brana SubagentStart/SubagentStop hook — track agent spawns and completions.
# Logs to session JSONL at /tmp/brana-session-*.jsonl for observability.
# Input:  stdin JSON {session_id, agent_id, agent_type, agent_name, hook_event_name}
# Output: stdout JSON {"continue": true}

cd /tmp 2>/dev/null || true

INPUT=$(cat) || true

SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null) || SESSION_ID="unknown"
AGENT_ID=$(echo "$INPUT" | jq -r '.agent_id // "unknown"' 2>/dev/null) || AGENT_ID="unknown"
AGENT_TYPE=$(echo "$INPUT" | jq -r '.agent_type // "unknown"' 2>/dev/null) || AGENT_TYPE="unknown"
AGENT_NAME=$(echo "$INPUT" | jq -r '.agent_name // ""' 2>/dev/null) || AGENT_NAME=""
HOOK_EVENT=$(echo "$INPUT" | jq -r '.hook_event_name // ""' 2>/dev/null) || HOOK_EVENT=""

# Determine event type from hook_event_name
EVENT=""
case "$HOOK_EVENT" in
    SubagentStart) EVENT="subagent-start" ;;
    SubagentStop)  EVENT="subagent-stop" ;;
    *)             EVENT="subagent-unknown" ;;
esac

TS=$(date +%s 2>/dev/null) || TS=0
TS_ISO=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null) || TS_ISO="unknown"

SESSION_FILE="/tmp/brana-session-${SESSION_ID}.jsonl"

# Build and append JSONL record
RECORD=$(jq -cn \
    --argjson ts "$TS" \
    --arg ts_iso "$TS_ISO" \
    --arg event "$EVENT" \
    --arg agent_id "$AGENT_ID" \
    --arg agent_type "$AGENT_TYPE" \
    --arg agent_name "$AGENT_NAME" \
    --arg session_id "$SESSION_ID" \
    '{ts: $ts, ts_iso: $ts_iso, event: $event, agent_id: $agent_id, agent_type: $agent_type, agent_name: $agent_name, session_id: $session_id}' \
    2>/dev/null) || true

if [ -n "$RECORD" ]; then
    echo "$RECORD" >> "$SESSION_FILE" 2>/dev/null || true
fi

echo '{"continue": true}'
