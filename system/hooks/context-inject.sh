#!/usr/bin/env bash
# No strict mode — hooks must never fail and block the session.

# Brana UserPromptSubmit hook — context injection (t-204, t-1381).
#
# Task injection (t-204): when the user prompt mentions task IDs (t-NNN),
# injects each task's subject, description, and context. Max 3 task IDs.
#
# File injection (t-1381): when the user prompt mentions file paths
# (e.g. system/hooks/foo.sh), injects the first 20 lines. Max 3 paths.
# Resolves ~ to $HOME and bare relative paths to the project root.
#
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

# Resolve project root early — used by both injection sections below
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT=$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null) || PROJECT_ROOT=""

# Fast path: nothing to inject → skip immediately
HAS_TASKS=0
HAS_FILES=0
echo "$PROMPT" | grep -qE '\bt-[0-9]+\b' 2>/dev/null           && HAS_TASKS=1 || true
echo "$PROMPT" | grep -qE '(/|[a-zA-Z_~])[a-zA-Z0-9_./~-]*/[a-zA-Z0-9_.-]+\.[a-zA-Z0-9]{1,10}' 2>/dev/null \
                                                                 && HAS_FILES=1 || true
[ "$HAS_TASKS" -eq 0 ] && [ "$HAS_FILES" -eq 0 ] && pass_through

CONTEXT_PARTS=""

# ── Task ID injection (t-204) ─────────────────────────────────────────────────
if [ "$HAS_TASKS" -eq 1 ]; then
    TASK_IDS=$(echo "$PROMPT" | grep -oE '\bt-[0-9]+\b' 2>/dev/null | sort -u | head -3) || TASK_IDS=""

    if [ -n "${TASK_IDS:-}" ]; then
        source "${SCRIPT_DIR}/lib/resolve-brana.sh" 2>/dev/null || true

        if [ -x "${BRANA:-}" ] && [ -n "${PROJECT_ROOT:-}" ]; then
            cd "$PROJECT_ROOT" 2>/dev/null || true

            while IFS= read -r TASK_ID; do
                [ -z "$TASK_ID" ] && continue

                TASK_JSON=$("$BRANA" backlog get "$TASK_ID" 2>/dev/null) || continue
                [ -z "$TASK_JSON" ] && continue

                SUBJECT=$(echo "$TASK_JSON" | jq -r '.subject // empty' 2>/dev/null) || continue
                [ -z "$SUBJECT" ] && continue

                DESCRIPTION=$(echo "$TASK_JSON" | jq -r '.description // empty' 2>/dev/null) || DESCRIPTION=""
                CONTEXT=$(echo "$TASK_JSON" | jq -r '.context // empty' 2>/dev/null)         || CONTEXT=""
                STATUS=$(echo "$TASK_JSON" | jq -r '.status // empty' 2>/dev/null)           || STATUS=""
                EFFORT=$(echo "$TASK_JSON" | jq -r '.effort // empty' 2>/dev/null)           || EFFORT=""

                PART="$TASK_ID ($STATUS, $EFFORT): $SUBJECT"
                [ -n "$DESCRIPTION" ] && PART="$PART — $DESCRIPTION"
                [ -n "$CONTEXT" ] && PART="$PART | Context: $(echo "$CONTEXT" | head -c 200)"

                CONTEXT_PARTS="${CONTEXT_PARTS}${PART}\n"
            done <<< "$TASK_IDS"
        fi
    fi
fi

# ── File path injection (t-1381) ──────────────────────────────────────────────
if [ "$HAS_FILES" -eq 1 ]; then
    FILE_PATHS=$(echo "$PROMPT" \
        | grep -oE '(/|[a-zA-Z_~])[a-zA-Z0-9_./~-]*/[a-zA-Z0-9_.-]+\.[a-zA-Z0-9]{1,10}' 2>/dev/null \
        | grep -vE '^https?://' \
        | sort -u | head -3) || FILE_PATHS=""

    if [ -n "${FILE_PATHS:-}" ]; then
        while IFS= read -r FILE_PATH; do
            [ -z "$FILE_PATH" ] && continue

            # Expand ~ and resolve relative paths to PROJECT_ROOT
            EXPANDED="${FILE_PATH/#\~/$HOME}"
            if [[ "$EXPANDED" == /* ]]; then
                RESOLVED="$EXPANDED"
            elif [ -n "${PROJECT_ROOT:-}" ]; then
                RESOLVED="${PROJECT_ROOT}/${EXPANDED}"
            else
                continue
            fi

            [ -f "$RESOLVED" ] || continue
            CONTENT=$(head -20 "$RESOLVED" 2>/dev/null) || continue
            [ -z "$CONTENT" ] && continue
            LINE_COUNT=$(wc -l < "$RESOLVED" 2>/dev/null | tr -d ' ') || LINE_COUNT="?"

            CONTEXT_PARTS="${CONTEXT_PARTS}[${FILE_PATH}] (${LINE_COUNT} lines, first 20):\n${CONTENT}\n\n"
        done <<< "$FILE_PATHS"
    fi
fi

[ -z "$CONTEXT_PARTS" ] && pass_through

MSG="Context:\n${CONTEXT_PARTS}"
MSG_ESCAPED=$(printf '%s' "$(printf "$MSG")" | jq -Rs '.' 2>/dev/null) || pass_through

echo "{\"continue\": true, \"additionalContext\": $MSG_ESCAPED}"
