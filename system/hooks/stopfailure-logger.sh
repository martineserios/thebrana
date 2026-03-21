#!/usr/bin/env bash
# No strict mode — failure hooks must never fail themselves.

# Brana StopFailure hook — log API errors to JSONL.
# Fires when a turn ends due to API error (rate limit, auth, billing, etc).
# Fire-and-forget: exit codes and output are ignored by CC.
# Input:  stdin JSON (session_id, transcript_path, error, error_details, cwd)
# Output: none (ignored)

cd /tmp 2>/dev/null || true

INPUT=$(cat) || true
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null) || SESSION_ID="unknown"
ERROR_TYPE=$(echo "$INPUT" | jq -r '.error // "unknown"' 2>/dev/null) || ERROR_TYPE="unknown"
ERROR_DETAILS=$(echo "$INPUT" | jq -r '.error_details // ""' 2>/dev/null) || ERROR_DETAILS=""
CWD=$(echo "$INPUT" | jq -r '.cwd // ""' 2>/dev/null) || CWD=""
TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path // ""' 2>/dev/null) || TRANSCRIPT=""

TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null) || TS="unknown"
EPOCH=$(date +%s 2>/dev/null) || EPOCH=0

# --- Log to JSONL ---
LOG_DIR="$HOME/.claude/logs"
mkdir -p "$LOG_DIR" 2>/dev/null || true
LOG_FILE="$LOG_DIR/stopfailure-errors.jsonl"

# Build record (compact JSON, one line)
RECORD=$(jq -cn \
    --arg ts "$TS" \
    --argjson epoch "$EPOCH" \
    --arg sid "$SESSION_ID" \
    --arg err "$ERROR_TYPE" \
    --arg detail "$ERROR_DETAILS" \
    --arg cwd "$CWD" \
    --arg transcript "$TRANSCRIPT" \
    '{timestamp: $ts, epoch: $epoch, session_id: $sid, error: $err, error_details: $detail, cwd: $cwd, transcript_path: $transcript}' \
    2>/dev/null) || true

if [ -n "$RECORD" ]; then
    echo "$RECORD" >> "$LOG_FILE" 2>/dev/null || true
fi

# --- Telegram alert for critical errors ---
# Set BRANA_TELEGRAM_BOT_TOKEN and BRANA_TELEGRAM_CHAT_ID in env to enable.
if [ -n "${BRANA_TELEGRAM_BOT_TOKEN:-}" ] && [ -n "${BRANA_TELEGRAM_CHAT_ID:-}" ]; then
    case "$ERROR_TYPE" in
        authentication_failed|billing_error)
            MSG="🚨 Claude Code API error: ${ERROR_TYPE}
Details: ${ERROR_DETAILS:-none}
Session: ${SESSION_ID}
CWD: ${CWD}"
            curl -s -X POST \
                "https://api.telegram.org/bot${BRANA_TELEGRAM_BOT_TOKEN}/sendMessage" \
                -d "chat_id=${BRANA_TELEGRAM_CHAT_ID}" \
                -d "text=${MSG}" \
                -d "parse_mode=Markdown" \
                >/dev/null 2>&1 || true
            ;;
    esac
fi

exit 0
