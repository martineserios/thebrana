#!/usr/bin/env bash
# No strict mode — hooks must never fail and block the session.

# Brana SubagentStart hook — inject active task context into spawned subagents.
# Every scout, explorer, and delegated agent automatically knows what task it supports.
# Input:  stdin JSON {session_id, agent_id, agent_type}
# Output: stdout JSON {"continue": true, "additionalContext": "..."}

cd /tmp 2>/dev/null || true

INPUT=$(cat) || true
AGENT_TYPE=$(echo "$INPUT" | jq -r '.agent_type // empty' 2>/dev/null) || true

# Skip if no agent type (shouldn't happen, but graceful)
[ -z "$AGENT_TYPE" ] && { echo '{"continue": true}'; exit 0; }

# Locate brana CLI
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BRANA="${SCRIPT_DIR}/../cli/rust/target/release/brana"
[ ! -x "$BRANA" ] && BRANA="$(command -v brana 2>/dev/null)" || true
[ ! -x "${BRANA:-}" ] && { echo '{"continue": true}'; exit 0; }

# Find active task (in_progress with build_step set = actively building)
ACTIVE=$("$BRANA" backlog query --status in_progress --output json 2>/dev/null) || true
[ -z "$ACTIVE" ] || [ "$ACTIVE" = "[]" ] && { echo '{"continue": true}'; exit 0; }

# Extract first in_progress task with a build_step (the one being built)
TASK_LINE=$(echo "$ACTIVE" | jq -r '
  [.[] | select(.build_step != null)] | first //
  [.[] ] | first //
  empty
  | "\(.id) | \(.subject) | strategy: \(.strategy // "unknown") | step: \(.build_step // "none") | tags: \(.tags // [] | join(", "))"
' 2>/dev/null) || true

[ -z "$TASK_LINE" ] && { echo '{"continue": true}'; exit 0; }

# Inject as additionalContext — subagent sees this in its first turn
CONTEXT="Active task: ${TASK_LINE}"
ESCAPED=$(echo "$CONTEXT" | jq -Rs '.')
echo "{\"continue\": true, \"additionalContext\": $ESCAPED}"
