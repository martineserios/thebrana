#!/usr/bin/env bash
# PreToolUse: Advisory gate on direct Write/Edit to typed memory files.
# All typed memory writes should go through `brana memory write` (ADR-038).
# Spec: ADR-038 §C (CLI gateway), ADR-037 §Wave2 (enforcement)
# Bypass: create /tmp/brana-memory-write-active before the write.
# Run: cat payload.json | bash memory-write-gate.sh

# No strict mode — hooks must always return valid JSON.
cd /tmp 2>/dev/null || true

INPUT=$(cat)

pass_through() {
    echo '{"continue": true}'
    exit 0
}

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null) || pass_through
case "$TOOL_NAME" in
    Write|Edit) ;;
    *) pass_through ;;
esac

FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null) || pass_through
[ -z "$FILE_PATH" ] && pass_through

# Only care about paths inside a memory/ directory
case "$FILE_PATH" in
    */memory/*.md) ;;
    *) pass_through ;;
esac

FNAME=$(basename "$FILE_PATH")

# Pass through: only block typed memory files ({type}_{slug}*.md)
# MEMORY.md (index), event-log.md, pending-learnings.md, and other non-typed
# files are allowed through.
case "$FNAME" in
    feedback_*.md|project_*.md|user_*.md|pattern_*.md|convention_*.md|field-note_*.md|adr_*.md) ;;
    *) pass_through ;;
esac

# Sentinel bypass — procedure explicitly authorized this direct write
[ -f /tmp/brana-memory-write-active ] && pass_through

# Derive the routing hint from the filename
TYPE=$(echo "$FNAME" | sed 's/_.*//')
SLUG=$(echo "$FNAME" | sed "s/^${TYPE}_//" | sed 's/_[0-9]\{4\}-.*//' | sed 's/\.md$//')

WARNING="⚠ Direct write to typed memory file: $FNAME

Route through the CLI (ADR-038):

  brana memory write \\
    --type ${TYPE} \\
    --scope project \\
    --slug ${SLUG} \\
    --content '...'

For global scope: --scope global
For cross-project patterns: --type pattern (writes to ~/.claude/memory/)

Bypass: touch /tmp/brana-memory-write-active before the write (removed after)."

ESCAPED=$(echo "$WARNING" | jq -Rs '.' 2>/dev/null) || ESCAPED='"[memory-write-gate warning]"'
echo "{\"continue\": false, \"additionalContext\": $ESCAPED}"
exit 0
