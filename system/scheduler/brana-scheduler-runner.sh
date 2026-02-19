#!/usr/bin/env bash
# brana-scheduler-runner.sh — Invoked by systemd per scheduled job.
# Reads job config from scheduler.json, acquires project lock, runs job, logs output.
# Usage: brana-scheduler-runner.sh <job-name>

set -uo pipefail

JOB_NAME="${1:?Usage: brana-scheduler-runner.sh <job-name>}"
CONFIG="$HOME/.claude/scheduler/scheduler.json"
LOG_BASE="$HOME/.claude/scheduler/logs"
LOCK_DIR="$HOME/.claude/scheduler/locks"
STATUS_FILE="$HOME/.claude/scheduler/last-status.json"

# Ensure dirs exist
mkdir -p "$LOCK_DIR"

# Write job status to last-status.json (one entry per job, atomic write)
write_status() {
    local status="$1" exit_code="$2" attempts="${3:-1}"
    local tmp
    tmp=$(mktemp)
    local entry
    entry=$(jq -n --arg job "$JOB_NAME" --arg status "$status" \
        --argjson exit_code "$exit_code" --argjson attempts "$attempts" \
        --arg ts "$(date -Iseconds)" \
        '{($job): {status: $status, exit_code: $exit_code, timestamp: $ts, attempts: $attempts}}')
    if [ -f "$STATUS_FILE" ]; then
        jq --argjson new "$entry" '. * $new' "$STATUS_FILE" > "$tmp" 2>/dev/null || echo "$entry" > "$tmp"
    else
        echo "$entry" > "$tmp"
    fi
    mv "$tmp" "$STATUS_FILE"
}

# Parse job config with jq
if [ ! -f "$CONFIG" ]; then
    echo "ERROR: Config not found: $CONFIG" >&2
    exit 1
fi

JOB=$(jq -r --arg name "$JOB_NAME" '.jobs[$name] // empty' "$CONFIG")
if [ -z "$JOB" ]; then
    echo "ERROR: Job not found in config: $JOB_NAME" >&2
    exit 1
fi

JOB_TYPE=$(echo "$JOB" | jq -r '.type')
PROJECT=$(echo "$JOB" | jq -r '.project')
ENABLED=$(echo "$JOB" | jq -r 'if has("enabled") then .enabled else true end')

if [ "$ENABLED" != "true" ]; then
    echo "Job $JOB_NAME is disabled, skipping."
    exit 0
fi

# Resolve ~ in project path
PROJECT="${PROJECT/#\~/$HOME}"

if [ ! -d "$PROJECT" ]; then
    echo "ERROR: Project directory not found: $PROJECT" >&2
    exit 1
fi

# Read config with defaults
DEFAULTS_MODEL=$(jq -r '.defaults.model // "haiku"' "$CONFIG")
DEFAULTS_TOOLS=$(jq -r '.defaults.allowedTools // "Read,Glob,Grep,WebSearch"' "$CONFIG")
DEFAULTS_RETENTION=$(jq -r '.defaults.logRetention // 30' "$CONFIG")
DEFAULTS_TIMEOUT=$(jq -r '.defaults.timeoutSeconds // 300' "$CONFIG")

DEFAULTS_RETRIES=$(jq -r '.defaults.maxRetries // 0' "$CONFIG")
DEFAULTS_BACKOFF=$(jq -r '.defaults.retryBackoffSec // 30' "$CONFIG")

MODEL=$(echo "$JOB" | jq -r --arg def "$DEFAULTS_MODEL" '.model // $def')
ALLOWED_TOOLS=$(echo "$JOB" | jq -r --arg def "$DEFAULTS_TOOLS" '.allowedTools // $def')
LOG_RETENTION=$(echo "$JOB" | jq -r --arg def "$DEFAULTS_RETENTION" '.logRetention // $def')
TIMEOUT_SECS=$(echo "$JOB" | jq -r --arg def "$DEFAULTS_TIMEOUT" '.timeoutSeconds // $def')
MAX_RETRIES=$(echo "$JOB" | jq -r --arg def "$DEFAULTS_RETRIES" '.maxRetries // $def')
RETRY_BACKOFF=$(echo "$JOB" | jq -r --arg def "$DEFAULTS_BACKOFF" '.retryBackoffSec // $def')

# Set up logging
JOB_LOG_DIR="$LOG_BASE/$JOB_NAME"
mkdir -p "$JOB_LOG_DIR"
TIMESTAMP=$(date +%Y-%m-%d-%H%M%S)
LOGFILE="$JOB_LOG_DIR/$TIMESTAMP.log"

# Derive project slug for lockfile
PROJECT_SLUG=$(basename "$PROJECT")
LOCKFILE="$LOCK_DIR/$PROJECT_SLUG.lock"

{
    echo "=== brana-scheduler: $JOB_NAME ==="
    echo "Time: $(date -Iseconds)"
    echo "Type: $JOB_TYPE"
    echo "Project: $PROJECT"
    echo "Model: $MODEL"
    echo "Timeout: ${TIMEOUT_SECS}s"
    echo "==="
    echo ""
} > "$LOGFILE"

# Run the job with retry loop
MAX_ATTEMPTS=$((MAX_RETRIES + 1))
EXIT_CODE=0
ATTEMPT=0

cd "$PROJECT"

for ATTEMPT in $(seq 1 "$MAX_ATTEMPTS"); do
    # Acquire project lock (non-blocking — skip if locked)
    exec 9>"$LOCKFILE"
    if ! flock -n 9; then
        echo "SKIPPED: Another scheduled job is running in $PROJECT_SLUG" >> "$LOGFILE"
        write_status "SKIPPED" 75
        exit 75  # EX_TEMPFAIL — no retry on lock conflict
    fi

    if [ "$ATTEMPT" -gt 1 ]; then
        echo "" >> "$LOGFILE"
        echo "--- Retry attempt $ATTEMPT/$MAX_ATTEMPTS ---" >> "$LOGFILE"
    fi

    EXIT_CODE=0
    case "$JOB_TYPE" in
        skill)
            SKILL=$(echo "$JOB" | jq -r '.skill')
            PROMPT="Execute the $SKILL skill for this project. Follow all skill instructions completely."

            case "$MODEL" in
                haiku)  MODEL_ID="haiku" ;;
                sonnet) MODEL_ID="sonnet" ;;
                opus)   MODEL_ID="opus" ;;
                *)      MODEL_ID="$MODEL" ;;
            esac

            timeout "$TIMEOUT_SECS" claude -p "$PROMPT" \
                --model "$MODEL_ID" \
                --allowedTools "$ALLOWED_TOOLS" \
                >> "$LOGFILE" 2>&1 || EXIT_CODE=$?
            ;;
        command)
            COMMAND=$(echo "$JOB" | jq -r '.command')
            timeout "$TIMEOUT_SECS" bash -c "$COMMAND" >> "$LOGFILE" 2>&1 || EXIT_CODE=$?
            ;;
        *)
            echo "ERROR: Unknown job type: $JOB_TYPE" >> "$LOGFILE"
            EXIT_CODE=1
            ;;
    esac

    # Release lock between attempts (prevents blocking other jobs)
    flock -u 9

    # Success — stop retrying
    if [ "$EXIT_CODE" -eq 0 ]; then
        break
    fi

    # Retries remaining — backoff and continue
    if [ "$ATTEMPT" -lt "$MAX_ATTEMPTS" ]; then
        BACKOFF=$((RETRY_BACKOFF * (1 << (ATTEMPT - 1))))
        echo "FAILED (exit code: $EXIT_CODE), retrying in ${BACKOFF}s (attempt $ATTEMPT/$MAX_ATTEMPTS)" >> "$LOGFILE"
        sleep "$BACKOFF"
    fi
done

# Determine status label
if [ "$EXIT_CODE" -eq 124 ]; then
    STATUS_LABEL="TIMEOUT"
elif [ "$EXIT_CODE" -eq 0 ]; then
    STATUS_LABEL="SUCCESS"
else
    STATUS_LABEL="FAILED"
fi

# Log exit status
{
    echo ""
    echo "==="
    if [ "$STATUS_LABEL" = "TIMEOUT" ]; then
        echo "TIMEOUT after ${TIMEOUT_SECS}s"
    elif [ "$STATUS_LABEL" = "SUCCESS" ]; then
        echo "SUCCESS"
    else
        echo "FAILED (exit code: $EXIT_CODE)"
    fi
    if [ "$ATTEMPT" -gt 1 ]; then
        echo "Attempts: $ATTEMPT/$MAX_ATTEMPTS"
    fi
    echo "Finished: $(date -Iseconds)"
} >> "$LOGFILE"

# Write status for statusline and notifications
write_status "$STATUS_LABEL" "$EXIT_CODE" "$ATTEMPT"

# Prune old logs (keep last N)
PRUNE_COUNT=$(ls -t "$JOB_LOG_DIR"/*.log 2>/dev/null | tail -n +"$((LOG_RETENTION + 1))" | wc -l)
if [ "$PRUNE_COUNT" -gt 0 ]; then
    ls -t "$JOB_LOG_DIR"/*.log | tail -n +"$((LOG_RETENTION + 1))" | xargs rm -f
fi

exit "$EXIT_CODE"
