#!/usr/bin/env bash
# brana-scheduler-notify.sh — OnFailure handler for systemd scheduler units.
# Called by brana-sched-notify@.service when a job unit fails.
# Usage: brana-scheduler-notify.sh <failed-unit-name>
#
# Guard: checks if the runner already recorded SUCCESS for this job.
# systemd OnFailure can fire when the ruflo store (backgrounded) outlives
# the systemd TimeoutStartSec, even though the actual job succeeded.
#
# Notifications:
#   1. last-status.json — always (primary, headless-safe)
#   2. Telegram         — if ~/.hub-secrets exists (Oracle VM)
#   3. notify-send      — best-effort (requires desktop session)

set -uo pipefail

FAILED_UNIT="${1:?Usage: brana-scheduler-notify.sh <failed-unit-name>}"
STATUS_FILE="$HOME/.claude/scheduler/last-status.json"
SECRETS_FILE="$HOME/.hub-secrets"

# Extract job name from unit name: brana-sched-<job>.service → <job>
# Handle slashed names from systemd escaping: brana/sched/sync/state.service
JOB_NAME="${FAILED_UNIT#brana-sched-}"
JOB_NAME="${JOB_NAME%.service}"
# Convert slashes back to dashes for lookup: brana/sched/sync/state → sync-state
LOOKUP_NAME=$(echo "$JOB_NAME" | sed 's|.*/||; s|/|-|g')
# If the unit name had no prefix stripping (slash-escaped names), extract manually
if echo "$FAILED_UNIT" | grep -q '/'; then
    # Format: brana/sched/<name-parts>.service
    LOOKUP_NAME=$(echo "$FAILED_UNIT" | sed 's|^brana/sched/||; s|\.service$||; s|/|-|g')
fi

# Guard: check if the runner already recorded SUCCESS for this job
# This prevents false-positive notifications when systemd timeout kills
# a backgrounded ruflo store after the actual job already succeeded.
if [ -f "$STATUS_FILE" ]; then
    RUNNER_STATUS=$(jq -r --arg job "$LOOKUP_NAME" '.[$job].status // empty' "$STATUS_FILE" 2>/dev/null)
    if [ "$RUNNER_STATUS" = "SUCCESS" ] || [ "$RUNNER_STATUS" = "SKIPPED" ]; then
        # Runner recorded success — this OnFailure is a false positive
        exit 0
    fi
fi

# Write failure to last-status.json (atomic)
write_status() {
    local tmp
    tmp=$(mktemp)
    local entry
    entry=$(jq -n --arg job "$LOOKUP_NAME" --arg ts "$(date -Iseconds)" \
        '{($job): {status: "FAILED", exit_code: 1, timestamp: $ts, attempts: 1, notified: true}}')
    if [ -f "$STATUS_FILE" ]; then
        jq --argjson new "$entry" '. * $new' "$STATUS_FILE" > "$tmp" 2>/dev/null || echo "$entry" > "$tmp"
    else
        echo "$entry" > "$tmp"
    fi
    mv "$tmp" "$STATUS_FILE"
}

write_status

# Telegram notification (Oracle VM — requires ~/.hub-secrets)
if [ -f "$SECRETS_FILE" ]; then
    # shellcheck source=/dev/null
    source "$SECRETS_FILE"
    if [ -n "${TELEGRAM_BOT_TOKEN:-}" ] && [ -n "${OWNER_CHAT_ID:-}" ]; then
        msg="⚠️ *Scheduler: ${LOOKUP_NAME} FAILED*
Unit: \`${FAILED_UNIT}\`
Time: $(date '+%Y-%m-%d %H:%M:%S')"
        # DELIBERATE: independent of brana binary — do not migrate to brana notify
        curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
            -d "chat_id=${OWNER_CHAT_ID}" \
            -d "text=${msg}" \
            -d "parse_mode=Markdown" \
            >/dev/null 2>&1 || true
    fi
fi

# Best-effort desktop notification (graceful degradation if headless)
if command -v notify-send &>/dev/null; then
    if [ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]; then
        DBUS_SESSION_BUS_ADDRESS=$(systemctl --user show-environment 2>/dev/null \
            | grep '^DBUS_SESSION_BUS_ADDRESS=' | cut -d= -f2-) || true
        export DBUS_SESSION_BUS_ADDRESS
    fi
    if [ -z "${DISPLAY:-}" ]; then
        DISPLAY=$(systemctl --user show-environment 2>/dev/null \
            | grep '^DISPLAY=' | cut -d= -f2-) || true
        export DISPLAY
    fi

    notify-send -u critical \
        "brana-scheduler: $LOOKUP_NAME failed" \
        "Unit $FAILED_UNIT entered failed state." \
        2>/dev/null || true
fi
