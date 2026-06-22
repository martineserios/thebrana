#!/usr/bin/env bash
# No strict mode — hooks must never fail and block the session.

# Brana UserPromptSubmit hook — presence-token refresh (t-2205, ADR-061 §4 invariant 1).
#
# Writes an interactive-presence token that goal-completion.sh's presence interlock reads
# (~/.claude/run-state/presence-<session_id>, freshness <15m) to confirm a human is driving
# the session before it auto-completes a /goal-bound task. Refreshed on every user prompt.
#
# Interactive-only: gated on /dev/tty so a headless `claude -p` runner with no controlling
# terminal cannot forge presence. Residual (deep-challenge finding #3): a pty-hosted headless
# run could still pass the tty gate — the autonomous-gaming defense is done-signal
# red-verification (t-2216), not this token. This token is the human-in-loop signal only.
#
# Input:  stdin JSON { "prompt": "...", "session_id": "..." }
# Output: {"continue": true}

INPUT=$(cat 2>/dev/null) || true
SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // ""' 2>/dev/null) || SESSION_ID=""

# Interactive gate: the controlling terminal must be openable for writing.
if [ -n "$SESSION_ID" ] && { : > /dev/tty; } 2>/dev/null; then
    mkdir -p "$HOME/.claude/run-state" 2>/dev/null || true
    : > "$HOME/.claude/run-state/presence-${SESSION_ID}" 2>/dev/null || true
fi

echo '{"continue": true}'
exit 0
