#!/usr/bin/env bash
# No strict mode — hooks must never fail and block the session.

# retire-when: default model ≥ Fable-class
#   Compensates for context-window pressure on smaller models by truncating
#   Bash output — at the cost of hiding diagnostic detail the model may need
#   (t-1711 flagged exactly that). Frontier models manage long outputs
#   natively; audit with: grep -r "retire-when:" system/  (t-1945)
# PostToolUse hook — compress verbose Bash output to save context budget (t-1716).
# Fires after every Bash tool call.
# If the output exceeds 100 lines OR 8000 chars, injects a compressed view via
# additionalContext (first 30 lines + truncation marker + last 10 lines).
# Under threshold → {"continue": true}, no context injection.
#
# Input:  stdin JSON (session_id, tool_name, tool_input, tool_result, cwd)
# Output: {"continue": true} or {"continue": true, "additionalContext": "..."}

cd /tmp 2>/dev/null || true

INPUT=$(cat) || true

pass_through() {
    echo '{"continue": true}'
    exit 0
}

# Bail out quickly if jq is unavailable — never break the session
command -v jq &>/dev/null || pass_through

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null) || pass_through
[ "${TOOL_NAME:-}" != "Bash" ] && pass_through

# Extract output — CC uses tool_result for PostToolUse; fall back to tool_response
OUTPUT=$(echo "$INPUT" | jq -r '
  .tool_result.output //
  .tool_result.content //
  .tool_result //
  .tool_response.content //
  .tool_response //
  empty
' 2>/dev/null) || pass_through

# Nothing to compress
[ -z "${OUTPUT:-}" ] && pass_through

LINE_COUNT=$(echo "$OUTPUT" | wc -l 2>/dev/null) || pass_through
CHAR_COUNT=${#OUTPUT}

# Under both thresholds — pass through unchanged
if [ "${LINE_COUNT:-0}" -le 100 ] && [ "${CHAR_COUNT:-0}" -le 8000 ]; then
    pass_through
fi

# Compress: first 30 lines + marker + last 10 lines
HEAD=$(echo "$OUTPUT" | head -30 2>/dev/null) || HEAD=""
TAIL=$(echo "$OUTPUT" | tail -10 2>/dev/null) || TAIL=""
OMITTED=$(( LINE_COUNT - 40 ))
[ "$OMITTED" -lt 0 ] && OMITTED=0

COMPRESSED="${HEAD}
[... ${OMITTED} lines truncated — use Read or grep for details ...]
${TAIL}"

COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null) || COMMAND=""
LABEL=""
[ -n "$COMMAND" ] && LABEL="($(echo "$COMMAND" | head -1 | cut -c1-60)) "

MSG="[bash-output-compress] ${LABEL}Output ${LINE_COUNT} lines / ${CHAR_COUNT} chars — compressed to first 30 + last 10:

${COMPRESSED}"

ESCAPED=$(printf '%s' "$MSG" | jq -Rs '.' 2>/dev/null) || pass_through
[ -z "${ESCAPED:-}" ] && pass_through

echo "{\"continue\": true, \"additionalContext\": $ESCAPED}"
