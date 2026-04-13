#!/usr/bin/env bash
# No strict mode — hooks must never fail and block the session.

# Reference doc regeneration hook.
# Triggers: Write|Edit on hooks.json
# Action: regenerate docs/reference/ from hooks.json + frontmatter metadata

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

BRANA=$(command -v brana 2>/dev/null) || true
[ -z "$BRANA" ] && { echo '{"continue": true}'; exit 0; }

# Run async — non-blocking, regeneration can take a moment
{
    cd "$REPO_ROOT" && "$BRANA" reference generate > /dev/null 2>&1
} &

echo '{"continue": true}'
