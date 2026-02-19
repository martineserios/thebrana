#!/usr/bin/env bash
# brana-scheduler-runner.sh — Invoked by systemd per scheduled job.
# Reads job config from scheduler.json, acquires project lock, runs job, logs output.
# Usage: brana-scheduler-runner.sh <job-name>

set -uo pipefail

JOB_NAME="${1:?Usage: brana-scheduler-runner.sh <job-name>}"
CONFIG="$HOME/.claude/scheduler/scheduler.json"
LOG_BASE="$HOME/.claude/scheduler/logs"
LOCK_DIR="$HOME/.claude/scheduler/locks"

# Ensure dirs exist
mkdir -p "$LOCK_DIR"

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

MODEL=$(echo "$JOB" | jq -r --arg def "$DEFAULTS_MODEL" '.model // $def')
ALLOWED_TOOLS=$(echo "$JOB" | jq -r --arg def "$DEFAULTS_TOOLS" '.allowedTools // $def')
LOG_RETENTION=$(echo "$JOB" | jq -r --arg def "$DEFAULTS_RETENTION" '.logRetention // $def')
TIMEOUT_SECS=$(echo "$JOB" | jq -r --arg def "$DEFAULTS_TIMEOUT" '.timeoutSeconds // $def')

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

# Acquire project lock (non-blocking — skip if locked)
exec 9>"$LOCKFILE"
if ! flock -n 9; then
    echo "SKIPPED: Another scheduled job is running in $PROJECT_SLUG" >> "$LOGFILE"
    exit 75  # EX_TEMPFAIL
fi

# Run the job
EXIT_CODE=0
cd "$PROJECT"

case "$JOB_TYPE" in
    skill)
        SKILL=$(echo "$JOB" | jq -r '.skill')
        # Build a natural language prompt that triggers skill invocation
        PROMPT="Execute the $SKILL skill for this project. Follow all skill instructions completely."

        # Resolve model to full Claude model ID
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

# Release lock
flock -u 9

# Log exit status
{
    echo ""
    echo "==="
    if [ "$EXIT_CODE" -eq 124 ]; then
        echo "TIMEOUT after ${TIMEOUT_SECS}s"
    elif [ "$EXIT_CODE" -eq 0 ]; then
        echo "SUCCESS"
    else
        echo "FAILED (exit code: $EXIT_CODE)"
    fi
    echo "Finished: $(date -Iseconds)"
} >> "$LOGFILE"

# Prune old logs (keep last N)
PRUNE_COUNT=$(ls -t "$JOB_LOG_DIR"/*.log 2>/dev/null | tail -n +"$((LOG_RETENTION + 1))" | wc -l)
if [ "$PRUNE_COUNT" -gt 0 ]; then
    ls -t "$JOB_LOG_DIR"/*.log | tail -n +"$((LOG_RETENTION + 1))" | xargs rm -f
fi

exit "$EXIT_CODE"
