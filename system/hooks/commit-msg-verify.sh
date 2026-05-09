#!/usr/bin/env bash
#
# commit-msg-verify.sh — PreToolUse hook for Bash (advisory, non-blocking)
#
# Warns when a commit message mentions filenames that are NOT in the staged diff.
# This catches misleading commit messages like "fix skills.rs" when skills.rs
# wasn't actually staged.
#
# The incident: commit f7b10bd claimed skills.rs was present but it wasn't staged.
# This hook would have caught it.
#
# Behavior: ADVISORY (not a block). Outputs additionalContext with the warning.
# The model sees the warning and can correct the commit message or re-stage files.
#
# Input: PreToolUse hook receives JSON on stdin.
# Reads: tool_input.command for the Bash command being run.

set -uo pipefail

input=$(cat)
command=$(echo "$input" | jq -r '.tool_input.command // .input.command // empty' 2>/dev/null)

# Only inspect git commit calls that have an inline message (-m flag)
case "$command" in
    *"git commit"*) ;;
    *) echo '{"continue":true}'; exit 0 ;;
esac

# Extract the commit message from -m "..." or -m '...'
# Handles: git commit -m "msg", git commit -m 'msg', git commit ... -m "$(cat <<'EOF' ... EOF)"
MSG=$(echo "$command" | grep -oP '(?<=-m\s)"[^"]*"' | head -1 | tr -d '"')
if [ -z "$MSG" ]; then
    MSG=$(echo "$command" | grep -oP "(?<=-m\s)'[^']*'" | head -1 | tr -d "'")
fi
if [ -z "$MSG" ]; then
    # No parseable inline message (e.g. heredoc, --reuse-message) — skip
    echo '{"continue":true}'; exit 0
fi

# Extract filenames mentioned in the commit message.
# Pattern: words ending in a known source/config extension.
MENTIONED=$(echo "$MSG" | grep -oE '[a-zA-Z0-9_/.-]+\.(rs|sh|md|ts|js|mjs|py|json|toml|yaml|yml|txt|lock|sql|html|css|go|rb|java|c|cpp|h|hpp|swift|kt)' 2>/dev/null || true)

if [ -z "$MENTIONED" ]; then
    echo '{"continue":true}'; exit 0
fi

# Get staged filenames (basenames only for comparison)
# Run from cwd extracted from hook input, or fall back to CWD
CWD=$(echo "$input" | jq -r '.cwd // empty' 2>/dev/null || true)
if [ -z "$CWD" ]; then CWD="$(pwd)"; fi

STAGED=$(git -C "$CWD" diff --cached --name-only 2>/dev/null || true)
if [ -z "$STAGED" ]; then
    # No staged files — skip (other hooks handle this)
    echo '{"continue":true}'; exit 0
fi

# Check each mentioned file against staged files (basename match)
MISSING=()
while IFS= read -r mentioned; do
    basename_mentioned=$(basename "$mentioned")
    # Check if any staged file's basename matches
    if ! echo "$STAGED" | xargs -I{} basename {} | grep -qF "$basename_mentioned"; then
        # Also check full path match (in case message uses relative path)
        if ! echo "$STAGED" | grep -qF "$mentioned"; then
            MISSING+=("$mentioned")
        fi
    fi
done <<< "$MENTIONED"

if [ ${#MISSING[@]} -eq 0 ]; then
    echo '{"continue":true}'; exit 0
fi

# Build warning message and output via jq (no python3 dependency)
MISSING_LIST=""
for f in "${MISSING[@]}"; do
    MISSING_LIST="${MISSING_LIST}  - ${f}\n"
done
STAGED_FLAT=$(echo "$STAGED" | tr '\n' ' ')

WARNING="WARNING: commit message mentions file(s) not in staged diff:\n${MISSING_LIST}\nStaged files: ${STAGED_FLAT}\n\nVerify: did you forget to stage these files, or should the commit message be revised?"

# Output as additionalContext (non-blocking — model sees the warning)
jq -n --arg ctx "$(printf '%b' "$WARNING")" '{"continue":true,"additionalContext":$ctx}' 2>/dev/null \
    || echo '{"continue":true}'
