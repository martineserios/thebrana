#!/usr/bin/env bash
# Brana PostToolUse hook — sync tasks.json changes to GitHub Issues + Projects.
# Triggered after Write/Edit to any **/tasks.json file.
# Runs the Python helper in background to avoid blocking the session.
# Input: stdin JSON (session_id, tool_name, tool_input)
# Output: stdout JSON {"continue": true}

cd /tmp 2>/dev/null || true

INPUT=$(cat) || true
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null) || true

# Only trigger on Write/Edit
case "${TOOL_NAME:-}" in
    Write|Edit) ;;
    *) echo '{"continue": true}'; exit 0 ;;
esac

# Get the file path
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null) || true

# Only trigger for tasks.json files
case "${FILE_PATH:-}" in
    */tasks.json) ;;
    *) echo '{"continue": true}'; exit 0 ;;
esac

# Must be a .claude/tasks.json (not any random tasks.json)
case "${FILE_PATH:-}" in
    */.claude/tasks.json) ;;
    *) echo '{"continue": true}'; exit 0 ;;
esac

CONFIG="$HOME/.claude/task-sync-config.json"
if [ ! -f "$CONFIG" ]; then
    echo '{"continue": true}'
    exit 0
fi

# Detect project from file path
# Path looks like: /home/user/enter_thebrana/clients/somos_mirada/.claude/tasks.json
# or: /home/user/enter_thebrana/thebrana/.claude/tasks.json
PROJECT_DIR=$(dirname "$(dirname "$FILE_PATH")")
PROJECT_SLUG=$(basename "$PROJECT_DIR")

# Check if project is configured
REPO=$(jq -r --arg slug "$PROJECT_SLUG" '.projects[$slug].repo // empty' "$CONFIG" 2>/dev/null) || true
if [ -z "$REPO" ]; then
    echo '{"continue": true}'
    exit 0
fi

# Run sync in background (non-blocking)
SYNC_SCRIPT="$(dirname "$0")/task-sync.py"
if [ -f "$SYNC_SCRIPT" ]; then
    nohup /home/martineserios/.local/bin/uv run python3 "$SYNC_SCRIPT" \
        "$PROJECT_SLUG" "$FILE_PATH" "$CONFIG" \
        >> "/tmp/brana-task-sync.log" 2>&1 &
fi

echo '{"continue": true}'
