#!/usr/bin/env bash
# brana-scheduler-digest.sh — Daily Telegram summary of all scheduler runs.
# Runs on Oracle VM. Reads local last-status.json + SSHs to laptop for remote.
# Sends one Telegram message summarizing pass/fail/skip across all environments.
#
# Usage: brana-scheduler-digest.sh
# Requires: ~/.hub-secrets (TELEGRAM_BOT_TOKEN, OWNER_CHAT_ID)
#           SSH access to laptop (optional — degrades gracefully)

set -uo pipefail

STATUS_FILE="$HOME/.claude/scheduler/last-status.json"
SECRETS_FILE="$HOME/.hub-secrets"
CONFIG_FILE="$HOME/.claude/scheduler/scheduler.json"

# ── Load secrets ──────────────────────────────────────────────────────

if [ ! -f "$SECRETS_FILE" ]; then
    echo "No secrets file at $SECRETS_FILE — cannot send Telegram." >&2
    exit 1
fi
# shellcheck source=/dev/null
source "$SECRETS_FILE"
if [ -z "${TELEGRAM_BOT_TOKEN:-}" ] || [ -z "${OWNER_CHAT_ID:-}" ]; then
    echo "Missing TELEGRAM_BOT_TOKEN or OWNER_CHAT_ID in $SECRETS_FILE" >&2
    exit 1
fi

# ── Collect status from each environment ──────────────────────────────

collect_env_summary() {
    local env_name="$1"
    local status_json="$2"
    local config_json="$3"

    if [ -z "$status_json" ] || [ "$status_json" = "{}" ]; then
        echo "📋 *${env_name}*: no runs recorded"
        return
    fi

    local pass=0 fail=0 skip=0 timeout=0 total=0
    local failures=""

    # Get enabled job names from config
    local enabled_jobs
    enabled_jobs=$(echo "$config_json" | jq -r '.jobs | to_entries[] | select(.value.enabled == true) | .key' 2>/dev/null)

    for job in $enabled_jobs; do
        local st
        st=$(echo "$status_json" | jq -r --arg j "$job" '.[$j].status // "—"' 2>/dev/null)
        case "$st" in
            SUCCESS) pass=$((pass + 1)) ;;
            FAILED) fail=$((fail + 1)); failures="${failures}  ✗ ${job}\n" ;;
            TIMEOUT) timeout=$((timeout + 1)); failures="${failures}  ⏱ ${job}\n" ;;
            SKIPPED) skip=$((skip + 1)) ;;
            *) ;;  # no status yet
        esac
        total=$((total + 1))
    done

    local line="📋 *${env_name}*: ✓${pass}"
    [ "$fail" -gt 0 ] && line="${line} ✗${fail}"
    [ "$timeout" -gt 0 ] && line="${line} ⏱${timeout}"
    [ "$skip" -gt 0 ] && line="${line} ⊘${skip}"
    line="${line} (${total} jobs)"

    echo "$line"
    [ -n "$failures" ] && echo -e "$failures"
}

# ── Oracle (local to this machine) ────────────────────────────────────

ORACLE_STATUS=$(cat "$STATUS_FILE" 2>/dev/null || echo "{}")
ORACLE_CONFIG=$(cat "$CONFIG_FILE" 2>/dev/null || echo '{"jobs":{}}')
ORACLE_SUMMARY=$(collect_env_summary "oracle" "$ORACLE_STATUS" "$ORACLE_CONFIG")

# ── Laptop (remote via SSH) ───────────────────────────────────────────

LAPTOP_SUMMARY=""
LAPTOP_SSH_OUTPUT=$(ssh -o ConnectTimeout=5 -o BatchMode=yes "$LAPTOP_HOST" \
    'cat ~/.claude/scheduler/last-status.json 2>/dev/null; echo "---SEP---"; cat ~/.claude/scheduler/scheduler.json 2>/dev/null' 2>/dev/null) || true

if [ -n "$LAPTOP_SSH_OUTPUT" ] && echo "$LAPTOP_SSH_OUTPUT" | grep -q "---SEP---"; then
    LAPTOP_STATUS=$(echo "$LAPTOP_SSH_OUTPUT" | sed 's/---SEP---.*//')
    LAPTOP_CONFIG=$(echo "$LAPTOP_SSH_OUTPUT" | sed 's/.*---SEP---//')
    LAPTOP_SUMMARY=$(collect_env_summary "local" "$LAPTOP_STATUS" "$LAPTOP_CONFIG")
else
    LAPTOP_SUMMARY="📋 *local*: unreachable"
fi

# ── Compose message ───────────────────────────────────────────────────

# Check if there are any failures across both environments
HAS_FAILURES=false
echo "$ORACLE_STATUS" | jq -e 'to_entries[] | select(.value.status == "FAILED" or .value.status == "TIMEOUT")' >/dev/null 2>&1 && HAS_FAILURES=true

DATE=$(date '+%Y-%m-%d')
HEADER="📊 *Scheduler Digest — ${DATE}*"

MSG="${HEADER}

${ORACLE_SUMMARY}
${LAPTOP_SUMMARY}"

# Only send if there are failures, or always send (configurable)
# Default: always send for visibility
SEND_ON_GREEN="${BRANA_DIGEST_SEND_ON_GREEN:-true}"

if [ "$HAS_FAILURES" = true ] || [ "$SEND_ON_GREEN" = true ]; then
    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
        -d "chat_id=${OWNER_CHAT_ID}" \
        -d "text=${MSG}" \
        -d "parse_mode=Markdown" \
        >/dev/null 2>&1

    echo "Digest sent."
else
    echo "All green — digest suppressed (set BRANA_DIGEST_SEND_ON_GREEN=true to always send)."
fi
