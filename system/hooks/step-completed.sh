#!/usr/bin/env bash
# No strict mode — hooks must never fail and block the session.

# Brana TaskCompleted hook — fires when a CC Task (step registry) is marked complete.
# Uses native CC TaskCompleted event — receives task metadata directly, no grep needed.
# Actions: (1) log step completion, (2) report to session log
# Input:  stdin JSON {session_id, task_id, task_subject, task_description, teammate_name, team_name}
# Output: stdout JSON {"continue": true, "additionalContext": "..."}
#
# Note: This hooks CC's built-in Task system (step registry), NOT brana backlog tasks.
# Brana backlog completions are handled by task-completed.sh (PostToolUse Bash hook).

cd /tmp 2>/dev/null || true

INPUT=$(cat) || true
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null) || true
TASK_ID=$(echo "$INPUT" | jq -r '.task_id // empty' 2>/dev/null) || true
TASK_SUBJECT=$(echo "$INPUT" | jq -r '.task_subject // empty' 2>/dev/null) || true

[ -z "$TASK_ID" ] && { echo '{"continue": true}'; exit 0; }

# ── Log step completion to session file ──────────────────
if [ -n "$SESSION_ID" ]; then
    SESSION_FILE="/tmp/brana-session-${SESSION_ID}.jsonl"
    TS=$(date +%s 2>/dev/null) || TS=0
    jq -n -c \
        --argjson ts "${TS:-0}" \
        --arg tool "TaskCompleted" \
        --arg outcome "step-done" \
        --arg detail "${TASK_SUBJECT:-unknown}" \
        '{ts: $ts, tool: $tool, outcome: $outcome, detail: $detail}' >> "$SESSION_FILE" 2>/dev/null || true
fi

# ── Report step completion as context ────────────────────
# Extract step name from subject format: "/brana:{skill} — {STEP}"
STEP_NAME=$(echo "$TASK_SUBJECT" | sed -n 's|.* — ||p' 2>/dev/null) || true

if [ -n "$STEP_NAME" ]; then
    MSG="Step completed: ${STEP_NAME}"
    ESCAPED=$(echo "$MSG" | jq -Rs '.')
    echo "{\"continue\": true, \"additionalContext\": $ESCAPED}"
else
    echo '{"continue": true}'
fi
