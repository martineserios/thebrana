#!/usr/bin/env bash
# PreToolUse: Blocking gate on feedback_*.md writes — Wave 2.
# Blocks write. Set BRANA_MEMORY_OVERRIDE=1 to bypass (logs to override-log.md).
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

# Layer 1 guard: CLAUDE.md is human-authored, never LLM-written.
# Unconditional — no sentinel bypass, no override bypass.
case "$FILE_PATH" in
    *CLAUDE.md)
        ESCAPED=$(printf '{"continue": false, "additionalContext": "🚫 CLAUDE.md is Layer 1 (human-authored only). Add conventions via PR — /brana:close must not write here."}')
        echo "$ESCAPED"
        exit 0 ;;
esac

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

# Whitelist: /brana:close Step 5b writes git-durable backup files — sentinel set by procedure
if [ -f /tmp/brana-close-active ]; then
    pass_through
fi

# Blocking response — continue:false, inject routing context
WARNING="🚫 feedback_*.md write BLOCKED: $(basename "$FILE_PATH")

feedback_*.md is a legacy path. Use /brana:retrospective to classify and route:

  Rule (always/never)    → system/rules/ draft (human gate)
  Decision (why X/Y)     → ADR stub (human gate)
  Reference (where X is) → ~/.claude/memory/portfolio.md
  Pattern (reusable fix) → ~/.claude/memory/patterns.md
  Knowledge (domain fact) → ~/.claude/memory/knowledge-staging.md

To bypass: set BRANA_MEMORY_OVERRIDE=1 in your shell (logs to override-log.md)."

ESCAPED=$(echo "$WARNING" | jq -Rs '.' 2>/dev/null) || ESCAPED='"[feedback-gate warning — jq unavailable]"'

echo "{\"continue\": false, \"additionalContext\": $ESCAPED}"
exit 0
