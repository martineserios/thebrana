#!/usr/bin/env bash
# brana-scheduler-notify.sh — OnFailure handler for systemd scheduler units.
# Called by brana-sched-notify@.service when a job unit fails.
# Usage: brana-scheduler-notify.sh <failed-unit-name>
#
# Notifications:
#   1. last-status.json — always (primary, headless-safe)
#   2. notify-send     — best-effort (requires desktop session)

set -uo pipefail

FAILED_UNIT="${1:?Usage: brana-scheduler-notify.sh <failed-unit-name>}"
STATUS_FILE="$HOME/.claude/scheduler/last-status.json"

# Extract job name from unit name: brana-sched-<job>.service → <job>
JOB_NAME="${FAILED_UNIT#brana-sched-}"
JOB_NAME="${JOB_NAME%.service}"

# Write failure to last-status.json (atomic)
write_status() {
    local tmp
    tmp=$(mktemp)
    local entry
    entry=$(jq -n --arg job "$JOB_NAME" --arg ts "$(date -Iseconds)" \
        '{($job): {status: "FAILED", exit_code: 1, timestamp: $ts, attempts: 1, notified: true}}')
    if [ -f "$STATUS_FILE" ]; then
        jq --argjson new "$entry" '. * $new' "$STATUS_FILE" > "$tmp" 2>/dev/null || echo "$entry" > "$tmp"
    else
        echo "$entry" > "$tmp"
    fi
    mv "$tmp" "$STATUS_FILE"
}

write_status

# Best-effort desktop notification (graceful degradation if headless)
if command -v notify-send &>/dev/null; then
    # Try to get DBUS address from systemd user session if not set
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
        "brana-scheduler: $JOB_NAME failed" \
        "Unit $FAILED_UNIT entered failed state." \
        2>/dev/null || true
fi
