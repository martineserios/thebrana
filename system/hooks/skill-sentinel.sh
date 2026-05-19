#!/usr/bin/env bash
# PostToolUse: write skill-loaded sentinels when known gated skills complete (t-1480).
#
# Currently gated skills:
#   brana:rust-skills → /tmp/brana-rust-skills-loaded-{SESSION_ID}
#
# Add entries to GATED_SKILLS map below when new skill gates are introduced.
# Pair with a corresponding PreToolUse guard hook.
# Ref: feedback_layer1-hook-enforcement, CLAUDE.md field note 2026-05-19

# No strict mode — hooks must always return valid JSON.
cd /tmp 2>/dev/null || true

INPUT=$(cat)

pass_through() {
    echo '{"continue": true}'
    exit 0
}

# Step 1: Only act on Skill tool completions
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null) || pass_through
[ "$TOOL_NAME" = "Skill" ] || pass_through

# Step 2: Extract skill name and session ID
SKILL_NAME=$(echo "$INPUT" | jq -r '.tool_input.skill // empty' 2>/dev/null) || pass_through
[ -z "$SKILL_NAME" ] && pass_through

SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null) || SESSION_ID=""
[ -z "$SESSION_ID" ] && pass_through

# Step 3: Map skill → sentinel path
# Add entries here when new guard hooks are introduced.
SENTINEL=""
case "$SKILL_NAME" in
    brana:rust-skills|plugin:brana:rust-skills)
        SENTINEL="/tmp/brana-rust-skills-loaded-${SESSION_ID}"
        ;;
esac

# Step 4: Write sentinel if mapped
if [ -n "$SENTINEL" ]; then
    touch "$SENTINEL" 2>/dev/null || true
fi

pass_through
