#!/usr/bin/env bash
# PostToolUse hook — sync MEMORY.md after a memory file is written.
# Fires on Write|Edit for */memory/*.md (excluding MEMORY.md itself).
# Appends a one-line pointer if not already present — dedup-only, preserves sections.
# No strict mode: hooks must never block the session.

INPUT=$(cat) || true
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null) || true
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null) || true

# Only care about Write|Edit
case "${TOOL_NAME:-}" in Write|Edit) ;; *) exit 0 ;; esac

# Path must be inside a memory/ directory
[[ "${FILE_PATH:-}" == */memory/*.md ]] || exit 0

# Skip MEMORY.md itself
[[ "$(basename "${FILE_PATH:-}")" == "MEMORY.md" ]] && exit 0

# File must exist
[ -f "${FILE_PATH:-}" ] || exit 0

MEMORY_DIR="$(dirname "$FILE_PATH")"
MEMORY_FILE="$MEMORY_DIR/MEMORY.md"
FILENAME="$(basename "$FILE_PATH")"

# Extract name and description from YAML frontmatter
FRONT=$(awk 'BEGIN{f=0} /^---$/{f++; next} f==1{print} f>=2{exit}' "$FILE_PATH" 2>/dev/null)
NAME=$(echo "$FRONT" | grep -E '^name:' | sed 's/^name:[[:space:]]*//' | tr -d '"'"'" | head -1)
DESC=$(echo "$FRONT" | grep -E '^description:' | sed 's/^description:[[:space:]]*//' | tr -d '"'"'" | head -1)

# Skip files without a name field — not a canonical memory file
[ -z "${NAME:-}" ] && exit 0

POINTER="- [${NAME}](${FILENAME}) — ${DESC:-(no description)}"

# Append only if this filename is not already referenced
if [ -f "$MEMORY_FILE" ]; then
    grep -qF "$FILENAME" "$MEMORY_FILE" && exit 0
    echo "$POINTER" >> "$MEMORY_FILE"
else
    printf '# Auto Memory\n\n%s\n' "$POINTER" > "$MEMORY_FILE"
fi
