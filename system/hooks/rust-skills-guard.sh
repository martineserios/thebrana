#!/usr/bin/env bash
# PreToolUse: block *.rs writes until brana:rust-skills is loaded this session (t-1480).
#
# Enforcement complement to the build.md step 4a advisory gate (t-1479).
# Procedure text alone fails — this hook closes the gap.
#
# EXTENSIBILITY — instance #1 of the skill-gate pattern. To guard a new skill/filetype:
#   1. Copy this file; update the file-extension filter in Step 3 and the hint in Step 7
#   2. Register the new skill sentinel in skill-sentinel.sh Step 3 case block
#   3. Wire both hooks in system/hooks/hooks.json
#   4. Update inventory + gate classification in docs/architecture/hooks.md (same commit)
#
# SUNSET: t-608 (Skill Registry) — skill gates declared in SKILL.md metadata;
#   this file becomes a generic guard wrapper.
#
# Sentinel: /tmp/brana-rust-skills-loaded-{SESSION_ID}
#   Written by skill-sentinel.sh when Skill(brana:rust-skills) completes.
# Bypass: /tmp/brana-rust-skills-guard-bypass (procedure-authorized override)
#
# Ref: feedback_layer1-hook-enforcement, CLAUDE.md field note 2026-05-19
# Run: cat payload.json | bash rust-skills-guard.sh

# No strict mode — hooks must always return valid JSON.
cd /tmp 2>/dev/null || true

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/profile.sh" 2>/dev/null || true
if ! hook_should_run "standard" 2>/dev/null; then
    echo '{"continue": true}'
    exit 0
fi

INPUT=$(cat)

pass_through() {
    echo '{"continue": true}'
    exit 0
}

deny() {
    local reason="$1"
    local escaped
    escaped=$(printf '%s' "$reason" | jq -Rs '.' 2>/dev/null) || escaped='"rust-skills not loaded"'
    echo "{\"continue\": false, \"additionalContext\": $escaped}"
    exit 0
}

# Step 1: Only act on Write or Edit
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null) || pass_through
case "$TOOL_NAME" in
    Write|Edit) ;;
    *) pass_through ;;
esac

# Step 2: Extract file path
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null) || pass_through
[ -z "$FILE_PATH" ] && pass_through

# Step 3: Only act on *.rs files
case "$FILE_PATH" in
    *.rs) ;;
    *) pass_through ;;
esac

# Step 4: Always allow test and doc files
case "$FILE_PATH" in
    */tests/*|*/test/*)         pass_through ;;
    *_test.rs|*.test.rs|*.spec.rs) pass_through ;;
    */docs/*)                   pass_through ;;
    *.md)                       pass_through ;;
esac

# Step 5: Check bypass sentinel (procedure-authorized override)
[ -f /tmp/brana-rust-skills-guard-bypass ] && pass_through

# Step 6: Check skill-loaded sentinel (session-scoped)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null) || SESSION_ID=""
if [ -n "$SESSION_ID" ] && [ -f "/tmp/brana-rust-skills-loaded-${SESSION_ID}" ]; then
    pass_through
fi

# Step 7: Block — rust-skills not loaded
HINT="brana:rust-skills not loaded this session.

Load it first (step 4a of build.md):
  1. Run /brana:rust-skills
  2. Retry your edit

To bypass for non-Rust-expertise writes: touch /tmp/brana-rust-skills-guard-bypass"

deny "$HINT"
