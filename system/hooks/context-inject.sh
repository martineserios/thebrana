#!/usr/bin/env bash
# No strict mode — hooks must never fail and block the session.

# Brana UserPromptSubmit hook — task context injection (t-204).
# When the user prompt mentions task IDs (t-NNN), injects each task's
# subject, description, and context into additionalContext so the model
# starts with full task context without an explicit lookup call.
#
# Limits: max 3 task IDs per prompt to avoid context bloat.
# Advisory only — always continues.
#
# Input:  stdin JSON { "prompt": "...", "session_id": "..." }
# Output: {"continue": true} or {"continue": true, "additionalContext": "..."}

cd /tmp 2>/dev/null || true

INPUT=$(cat) || true

pass_through() {
    echo '{"continue": true}'
    exit 0
}

PROMPT=$(echo "$INPUT" | jq -r '.prompt // empty' 2>/dev/null) || pass_through
[ -z "${PROMPT:-}" ] && pass_through

# Fast path: no t-NNN pattern → skip immediately
echo "$PROMPT" | grep -qE '\bt-[0-9]+\b' 2>/dev/null || pass_through

# Extract task IDs (max 3 to cap context size)
TASK_IDS=$(echo "$PROMPT" | grep -oE '\bt-[0-9]+\b' 2>/dev/null | sort -u | head -3) || pass_through
[ -z "${TASK_IDS:-}" ] && pass_through

# Resolve brana CLI and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/resolve-brana.sh" 2>/dev/null || true
[ ! -x "${BRANA:-}" ] && pass_through

# brana CLI uses CWD to locate tasks.json — cd to the project root
PROJECT_ROOT=$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null) || pass_through
cd "$PROJECT_ROOT" 2>/dev/null || pass_through

# Fetch task details and build context block
CONTEXT_PARTS=""
while IFS= read -r TASK_ID; do
    [ -z "$TASK_ID" ] && continue

    TASK_JSON=$("$BRANA" backlog get "$TASK_ID" 2>/dev/null) || continue
    [ -z "$TASK_JSON" ] && continue

    SUBJECT=$(echo "$TASK_JSON" | jq -r '.subject // empty' 2>/dev/null) || continue
    [ -z "$SUBJECT" ] && continue

    DESCRIPTION=$(echo "$TASK_JSON" | jq -r '.description // empty' 2>/dev/null) || DESCRIPTION=""
    CONTEXT=$(echo "$TASK_JSON" | jq -r '.context // empty' 2>/dev/null) || CONTEXT=""
    STATUS=$(echo "$TASK_JSON" | jq -r '.status // empty' 2>/dev/null) || STATUS=""
    EFFORT=$(echo "$TASK_JSON" | jq -r '.effort // empty' 2>/dev/null) || EFFORT=""

    PART="$TASK_ID ($STATUS, $EFFORT): $SUBJECT"
    [ -n "$DESCRIPTION" ] && PART="$PART — $DESCRIPTION"
    [ -n "$CONTEXT" ] && PART="$PART | Context: $(echo "$CONTEXT" | head -c 200)"

    CONTEXT_PARTS="${CONTEXT_PARTS}${PART}\n"
done <<< "$TASK_IDS"

[ -z "$CONTEXT_PARTS" ] && pass_through

MSG="Task context:\n${CONTEXT_PARTS}"
MSG_ESCAPED=$(printf '%s' "$(printf "$MSG")" | jq -Rs '.' 2>/dev/null) || pass_through

echo "{\"continue\": true, \"additionalContext\": $MSG_ESCAPED}"
