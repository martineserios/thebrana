#!/usr/bin/env bash
# No strict mode — hooks must never fail and block the session.

# Reference doc regeneration hook.
# Triggers: Write|Edit on hooks.json
# Action: regenerate docs/reference/hooks.md from hooks.json metadata
# Migration: tracked in t-1191 (replace with brana reference generate)

cd /tmp 2>/dev/null || true

INPUT=$(cat) || true
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null) || true

# Only trigger on hooks.json writes
case "$FILE_PATH" in
    */hooks/hooks.json) ;;
    *) echo '{"continue": true}'; exit 0 ;;
esac

REPO_ROOT=$(git -C "$(dirname "$FILE_PATH")" rev-parse --show-toplevel 2>/dev/null) || true
[ -z "$REPO_ROOT" ] && { echo '{"continue": true}'; exit 0; }

SCRIPT="$REPO_ROOT/system/scripts/generate-reference.py"
[ ! -f "$SCRIPT" ] && { echo '{"continue": true}'; exit 0; }

# Run async — non-blocking, regeneration can take a moment
{
    cd "$REPO_ROOT" && uv run python3 "$SCRIPT" > /dev/null 2>&1
} &

echo '{"continue": true}'
