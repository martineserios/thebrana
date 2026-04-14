#!/usr/bin/env bash
# PreToolUse: Advisory gate on feedback_*.md writes.
# Wave 1: warns, does not block. Wave 2 (t-1245b): blocking mode.
# Spec: ADR-037, memory-taxonomy-sdd.md §4
# Run: cat payload.json | bash feedback-gate.sh

# No strict mode — hooks must always return valid JSON.
cd /tmp 2>/dev/null || true

INPUT=$(cat)

pass_through() {
    echo '{"continue": true}'
    exit 0
}

# Parse tool name and file path
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null) || pass_through
case "$TOOL_NAME" in
    Write|Edit) ;;
    *) pass_through ;;
esac

FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null) || pass_through
[ -z "$FILE_PATH" ] && pass_through

# Match: ~/.claude/projects/*/memory/feedback_*.md only
# Pattern: any path with /memory/feedback_ that ends in .md
case "$FILE_PATH" in
    */memory/feedback_*.md) ;;
    *) pass_through ;;
esac

# Respect override flag
if [ "${BRANA_MEMORY_OVERRIDE:-}" = "1" ]; then
    OVERRIDE_LOG="${HOME}/.claude/memory/override-log.md"
    DATE=$(date +%Y-%m-%d)
    {
        echo "- ${DATE} | BRANA_MEMORY_OVERRIDE=1 | bypassed feedback-gate for: $(basename "$FILE_PATH")"
    } >> "$OVERRIDE_LOG" 2>/dev/null || true
    pass_through
fi

# Advisory warning — continue:true, inject context
WARNING="⚠ feedback_*.md creation detected: $(basename "$FILE_PATH")

The memory taxonomy routes learnings by type — not to feedback_*.md files.
Use /brana:retrospective to classify and route correctly:

  Rule (always/never)    → system/rules/ draft (human gate)
  Decision (why X/Y)     → ADR stub (human gate)
  Reference (where X is) → ~/.claude/memory/portfolio.md
  Pattern (reusable fix) → ~/.claude/memory/patterns.md
  Knowledge (domain fact) → ~/.claude/memory/knowledge-staging.md

To suppress this warning: set BRANA_MEMORY_OVERRIDE=1 in your shell."

ESCAPED=$(echo "$WARNING" | jq -Rs '.' 2>/dev/null) || ESCAPED='"[feedback-gate warning — jq unavailable]"'

echo "{\"continue\": true, \"additionalContext\": $ESCAPED}"
exit 0
