#!/usr/bin/env bash
# No strict mode — hooks must never fail and block the session.

# Brana PostToolUse hook — detect deal closures, snapshot to ReasoningBank.
# Input:  stdin JSON (session_id, tool_name, tool_input, cwd)
# Output: stdout JSON with additionalContext on deal closure

# Ensure valid CWD
cd /tmp 2>/dev/null || true

INPUT=$(cat) || true
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null) || true
FILE_PATH=""

# Extract file path based on tool type
case "${TOOL_NAME:-}" in
    Write)
        FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null) || FILE_PATH=""
        ;;
    Edit)
        FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null) || FILE_PATH=""
        ;;
    *)
        echo '{"continue": true}'
        exit 0
        ;;
esac

# Fast early exit — only care about pipeline deal files
case "${FILE_PATH:-}" in
    */docs/pipeline/deal-*.md|*/docs/pipeline/deals.md|*/docs/pipeline/closed.md)
        ;; # match — continue
    *)
        echo '{"continue": true}'
        exit 0
        ;;
esac

# Check content for "closed-won"
CONTENT=""
case "${TOOL_NAME:-}" in
    Write)
        CONTENT=$(echo "$INPUT" | jq -r '.tool_input.content // empty' 2>/dev/null) || CONTENT=""
        ;;
    Edit)
        CONTENT=$(echo "$INPUT" | jq -r '.tool_input.new_string // empty' 2>/dev/null) || CONTENT=""
        ;;
esac

if ! echo "$CONTENT" | grep -qi 'closed.won' 2>/dev/null; then
    echo '{"continue": true}'
    exit 0
fi

# --- Deal closure detected ---
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null) || true

# Extract deal name from filename
DEAL_NAME=$(basename "$FILE_PATH" .md | sed 's/^deal-//' | tr '-' ' ') || DEAL_NAME="unknown"

# Attempt to extract deal value from content
DEAL_VALUE=$(echo "$CONTENT" | grep -oiE '(value|amount|revenue|deal.size)[^0-9]*[0-9][0-9,.]+' 2>/dev/null | grep -oE '[0-9][0-9,.]+' | head -1 || true)

SNAPSHOT="Deal closed: ${DEAL_NAME}"
if [ -n "$DEAL_VALUE" ]; then
    SNAPSHOT="$SNAPSHOT (value: \$${DEAL_VALUE})"
fi

# Store snapshot in ReasoningBank
CF=""
for candidate in "$HOME"/.nvm/versions/node/*/bin/claude-flow; do
    [ -x "$candidate" ] && CF="$candidate" && break
done
[ -z "$CF" ] && command -v claude-flow &>/dev/null && CF="claude-flow"

CF_WARNING=""
if [ -n "$CF" ]; then
    STORE_KEY="deal-closed-$(date +%Y%m%d-%H%M%S 2>/dev/null || echo unknown)"
    CF_ERR=$(timeout 3 $CF memory store \
        -k "$STORE_KEY" \
        -v "$SNAPSHOT" \
        --namespace business \
        --tags "deal,closed-won,pipeline" 2>&1) || true
    CF_EXIT=$?
    if [ $CF_EXIT -eq 124 ]; then
        CF_WARNING="Deal snapshot store timed out. Manual: claude-flow memory store -k '$STORE_KEY' -v '$SNAPSHOT' --namespace business"
    elif [ $CF_EXIT -ne 0 ]; then
        CF_WARNING="Deal snapshot store failed. Manual: claude-flow memory store -k '$STORE_KEY' -v '$SNAPSHOT' --namespace business"
    fi
else
    CF_WARNING="claude-flow not found. Deal snapshot not persisted. Manual backup recommended."
fi

# Log to session JSONL
if [ -n "${SESSION_ID:-}" ]; then
    SESSION_FILE="/tmp/brana-session-${SESSION_ID}.jsonl"
    jq -n -c \
        --argjson ts "$(date +%s 2>/dev/null || echo 0)" \
        --arg tool "post-sale" \
        --arg outcome "deal-closed" \
        --arg detail "$SNAPSHOT" \
        '{ts: $ts, tool: $tool, outcome: $outcome, detail: $detail}' >> "$SESSION_FILE" 2>/dev/null || true
fi

# Output with additionalContext
CONTEXT="Deal closure detected: ${DEAL_NAME}. Consider updating Google Sheets via MCP integration and running /growth-check to refresh metrics."
if [ -n "$CF_WARNING" ]; then
    CONTEXT="$CONTEXT
[Hook warning] $CF_WARNING"
fi
ESCAPED=$(echo "$CONTEXT" | jq -Rs '.' 2>/dev/null) || ESCAPED='""'
echo "{\"continue\": true, \"additionalContext\": $ESCAPED}"
