#!/usr/bin/env bash
# No strict mode — failure hooks especially must never fail themselves.

# Brana PostToolUseFailure hook — log tool failures during session.
# Wave 1 (#75): error categorization, cascade detection.
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
    CASCADE=false

    # --- Cascade detection ---
    # If the last 2 events were also failures on the same target, this is a cascade (3+ consecutive).
    if [ -f "$SESSION_FILE" ] && [ -n "$DETAIL" ]; then
        RECENT_FAILS=$(tail -2 "$SESSION_FILE" 2>/dev/null | jq -r 'select(.outcome == "failure") | .detail // empty' 2>/dev/null) || RECENT_FAILS=""
        MATCH_COUNT=$(echo "$RECENT_FAILS" | grep -cxF "$DETAIL" 2>/dev/null) || MATCH_COUNT=0
        if [ "$MATCH_COUNT" -ge 2 ]; then
            CASCADE=true
        fi
    fi

    # --- Error categorization ---
    ERROR_CAT="unknown"
    case "${TOOL_NAME:-}" in
        Edit)
            ERROR_CAT="edit-mismatch"
            ;;
        Write)
            ERROR_CAT="write-fail"
            ;;
        Bash)
            ERROR_CAT="command-fail"
            ;;
        WebFetch|WebSearch)
            ERROR_CAT="network-fail"
            ;;
        *)
            ERROR_CAT="tool-fail"
            ;;
    esac

    jq -n -c \
        --argjson ts "${TS:-0}" \
        --arg tool "${TOOL_NAME:-unknown}" \
        --arg outcome "failure" \
        --arg detail "${DETAIL:-unknown}" \
        --arg error_cat "$ERROR_CAT" \
        --argjson cascade "$CASCADE" \
        '{ts: $ts, tool: $tool, outcome: $outcome, detail: $detail, error_cat: $error_cat, cascade: $cascade}' >> "$SESSION_FILE" 2>/dev/null || true
fi

echo '{"continue": true}'
