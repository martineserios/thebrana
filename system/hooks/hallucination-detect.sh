#!/usr/bin/env bash
# No strict mode — hooks must never fail and block the session.

# retire-when: default model ≥ Fable-class
#   Compensates for weaker models claiming completion ("fixed", "done") in
#   commit messages without touching test files. Frontier models rarely do
#   this; audit with: grep -r "retire-when:" system/  (t-1945)
# Brana PostToolUse hook — hallucination detection (t-677).
# Fires after Bash tool calls. Warns when a commit message contains completion
# keywords (fix/done/complete/close/resolve) but no test files were modified.
# Advisory only — never blocks.
#
# Input:  stdin JSON (tool_name, tool_input, cwd)
# Output: {"continue": true} or {"continue": true, "additionalContext": "..."}

cd /tmp 2>/dev/null || true

INPUT=$(cat) || true

pass_through() {
    echo '{"continue": true}'
    exit 0
}

warn() {
    local msg="$1"
    local escaped
    escaped=$(printf '%s' "$msg" | jq -Rs '.' 2>/dev/null) || escaped='"[hallucination-detect: warning]"'
    echo "{\"continue\": true, \"additionalContext\": $escaped}"
    exit 0
}

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null) || pass_through

# Only act on Bash tool calls
[ "${TOOL_NAME:-}" != "Bash" ] && pass_through

COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null) || pass_through
[ -z "${COMMAND:-}" ] && pass_through

# Only inspect git commit commands
case "$COMMAND" in
    *"git commit"*) ;;
    *) pass_through ;;
esac

# Extract the commit message from the command
# Handles: -m "msg", -m 'msg', -m $(cat <<'EOF'...), heredoc forms
COMMIT_MSG=""

# Try -m "..." or -m '...' patterns
MSG_MATCH=$(echo "$COMMAND" | grep -oP '(?<=-m\s)["\047]([^"'\'']+)["\047]' 2>/dev/null | tr -d '"\047') || MSG_MATCH=""
[ -n "$MSG_MATCH" ] && COMMIT_MSG="$MSG_MATCH"

# Heredoc fallback: extract text between EOF markers
if [ -z "$COMMIT_MSG" ]; then
    COMMIT_MSG=$(echo "$COMMAND" | sed -n '/EOF/,/EOF/{ /EOF/d; p; }' 2>/dev/null | head -5 | tr '\n' ' ') || COMMIT_MSG=""
fi

# If no message extracted, can't check — pass through
[ -z "$COMMIT_MSG" ] && pass_through

# Check for completion keywords (case-insensitive)
HAS_KEYWORD=false
case "$(echo "$COMMIT_MSG" | tr '[:upper:]' '[:lower:]')" in
    *fix*|*done*|*complete*|*close*|*resolve*) HAS_KEYWORD=true ;;
esac

[ "$HAS_KEYWORD" = false ] && pass_through

# Completion keyword found — check what was committed
CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null) || CWD=""
[ -z "${CWD:-}" ] && pass_through

GIT_ROOT=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null) || pass_through
[ -z "${GIT_ROOT:-}" ] && pass_through

# Get files in the most recent commit
COMMITTED_FILES=$(git -C "$GIT_ROOT" show --name-only --format="" HEAD 2>/dev/null) || pass_through

# Check for test file patterns
HAS_TEST_FILES=false
while IFS= read -r f; do
    [ -z "$f" ] && continue
    case "$f" in
        test_*|*_test.*|*.test.*|*.spec.*) HAS_TEST_FILES=true; break ;;
        */tests/*|*/test/*|*/__tests__/*) HAS_TEST_FILES=true; break ;;
        test-*|*-test.sh) HAS_TEST_FILES=true; break ;;
    esac
done <<< "$COMMITTED_FILES"

[ "$HAS_TEST_FILES" = true ] && pass_through

# Completion keyword + no test files → warn
warn "[hallucination-detect] Commit contains '$(echo "$COMMIT_MSG" | cut -c1-60)' but no test files were modified. Verify the fix is actually tested — if tests exist elsewhere, ignore this warning."
