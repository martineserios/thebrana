#!/usr/bin/env bash
# No strict mode — hooks must never fail and block the session.

# PreToolUse: guard-explore — Log reads without prior search
#
# Observes Read|Grep|Glob tool calls:
#   - Grep/Glob: records that a search happened (search history)
#   - Read on implementation files: checks if a search preceded it
#
# Week 1: LOGGING ONLY — no blocking. Collect data on read patterns.
# Week 2+: Optionally enforce (deny gate) based on week 1 data.
#
# Whitelisted (always pass through):
#   - *.md, CLAUDE.md, package.json, Cargo.toml, pyproject.toml
#   - Config files (*.json, *.yaml, *.yml, *.toml, *.env*)
#   - Test files (*test*, *spec*, __tests__/)
#   - docs/, .claude/, system/skills/, system/hooks/, system/agents/
#
# Only logs for implementation directories: src/, lib/, system/cli/, system/scripts/

cd /tmp 2>/dev/null || true

# Profile gate: strict tier (only runs when BRANA_HOOK_PROFILE=strict)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/profile.sh" 2>/dev/null || true
if ! hook_should_run "strict" 2>/dev/null; then
    echo '{"continue": true}'
    exit 0
fi

INPUT=$(cat) || true

pass_through() {
    echo '{"continue": true}'
}

# Extract tool name and file path
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null) || true
[ -z "$TOOL_NAME" ] && { pass_through; exit 0; }

SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null) || true
SEARCH_LOG="/tmp/brana-search-${SESSION_ID}.log"
EXPLORE_LOG="/tmp/brana-explore-${SESSION_ID}.log"

# --- Track searches (Grep/Glob) ---
if [ "$TOOL_NAME" = "Grep" ] || [ "$TOOL_NAME" = "Glob" ]; then
    PATTERN=$(echo "$INPUT" | jq -r '.tool_input.pattern // empty' 2>/dev/null) || true
    echo "$(date +%H:%M:%S) $TOOL_NAME pattern=$PATTERN" >> "$SEARCH_LOG" 2>/dev/null || true
    pass_through
    exit 0
fi

# --- Only process Read from here ---
[ "$TOOL_NAME" = "Read" ] || { pass_through; exit 0; }

FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null) || true
[ -z "$FILE_PATH" ] && { pass_through; exit 0; }

BASENAME=$(basename "$FILE_PATH" 2>/dev/null) || true

# --- Whitelist: always allow these files ---

# Markdown files
case "$BASENAME" in
    *.md) pass_through; exit 0 ;;
esac

# Config files
case "$BASENAME" in
    *.json|*.yaml|*.yml|*.toml|*.lock|*.env*|.gitignore|Makefile|Dockerfile|docker-compose*) pass_through; exit 0 ;;
    package.json|Cargo.toml|pyproject.toml|tsconfig.json|jest.config.*|.eslintrc*) pass_through; exit 0 ;;
esac

# Test files
case "$FILE_PATH" in
    *test*|*spec*|*__tests__*|*_test.*|*.test.*|*.spec.*) pass_through; exit 0 ;;
esac

# Whitelisted directories
case "$FILE_PATH" in
    */docs/*|*/.claude/*|*/system/skills/*|*/system/hooks/*|*/system/agents/*|*/system/commands/*) pass_through; exit 0 ;;
    */node_modules/*|*/.git/*) pass_through; exit 0 ;;
esac

# --- Implementation file detection ---
# Only log for impl directories
IS_IMPL=false
case "$FILE_PATH" in
    */src/*|*/lib/*|*/system/cli/*|*/system/scripts/*) IS_IMPL=true ;;
esac

[ "$IS_IMPL" = "false" ] && { pass_through; exit 0; }

# --- Check for prior search ---
HAS_SEARCH=false
if [ -f "$SEARCH_LOG" ]; then
    # Check if any search happened in this session (simple: any line exists)
    SEARCH_COUNT=$(wc -l < "$SEARCH_LOG" 2>/dev/null) || SEARCH_COUNT=0
    [ "$SEARCH_COUNT" -gt 0 ] && HAS_SEARCH=true
fi

# --- Log the observation ---
if [ "$HAS_SEARCH" = "false" ]; then
    echo "$(date +%H:%M:%S) READ_WITHOUT_SEARCH file=$FILE_PATH" >> "$EXPLORE_LOG" 2>/dev/null || true
fi

# Week 1: always pass through (logging only)
pass_through
