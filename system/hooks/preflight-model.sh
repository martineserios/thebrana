#!/usr/bin/env bash
#
# preflight-model.sh — UserPromptSubmit hook (advisory, non-blocking)
#
# When the user invokes a heavy skill (/brana:close, /brana:brainstorm,
# /brana:build), checks if extra-usage is disabled in ~/.claude.json.
# If disabled, injects an additionalContext warning BEFORE the model
# starts consuming the context window.
#
# Complements the session-start warning (t-1034): that warning fires
# once at session start and may be missed. This one fires exactly at
# the point where it matters.
#
# Behavior: ADVISORY (non-blocking). continue:true always.
# Silence: BRANA_1M_WARN_OFF=1
#
# Input: UserPromptSubmit hook receives JSON on stdin.
#   { "prompt": "user message text", "session_id": "..." }

set -uo pipefail

# Silence env var
if [ -n "${BRANA_1M_WARN_OFF:-}" ]; then
    echo '{"continue":true}'; exit 0
fi

input=$(cat)

# Extract prompt text (UserPromptSubmit format)
PROMPT=$(echo "$input" | jq -r '.prompt // .message // empty' 2>/dev/null) || PROMPT=""

if [ -z "$PROMPT" ]; then
    echo '{"continue":true}'; exit 0
fi

# Heavy skills that require 1M context / extra-usage
HEAVY_SKILLS=("/brana:close" "/brana:brainstorm" "/brana:build")
IS_HEAVY=false
for skill in "${HEAVY_SKILLS[@]}"; do
    if echo "$PROMPT" | grep -qF "$skill"; then
        IS_HEAVY=true
        break
    fi
done

if [ "$IS_HEAVY" = "false" ]; then
    echo '{"continue":true}'; exit 0
fi

# Check extra-usage disabled state
if [ ! -f "$HOME/.claude.json" ]; then
    echo '{"continue":true}'; exit 0
fi

EU_REASON=$(jq -r '.cachedExtraUsageDisabledReason // empty' "$HOME/.claude.json" 2>/dev/null) || EU_REASON=""

if [ -z "$EU_REASON" ]; then
    echo '{"continue":true}'; exit 0
fi

# Extra-usage disabled AND heavy skill invoked — warn
INVOKED_SKILL=$(echo "$PROMPT" | grep -oE '/brana:[a-z]+' | head -1)
WARNING="PREFLIGHT WARNING: Extra-usage disabled (${EU_REASON})."
WARNING="$WARNING ${INVOKED_SKILL} uses extended context and will fail around the 200K-token mark with an API error."
WARNING="$WARNING Run /model to switch to standard Opus 4.7 or Sonnet 4.6 before proceeding."
WARNING="$WARNING Silence with: BRANA_1M_WARN_OFF=1"

jq -n --arg ctx "$WARNING" '{"continue":true,"additionalContext":$ctx}'
