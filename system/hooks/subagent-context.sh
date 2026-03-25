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
source "${SCRIPT_DIR}/lib/resolve-brana.sh"
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

# Build context array (keep total under 500 tokens)
CONTEXT_PARTS=()

# 1. Active task
CONTEXT_PARTS+=("Active task: ${TASK_LINE}")

# 2. Current branch (if in git repo)
if GIT_BRANCH=$(git branch --show-current 2>/dev/null); then
  [ -n "$GIT_BRANCH" ] && CONTEXT_PARTS+=("Branch: $GIT_BRANCH")
fi

# 3. Active plan summary (if plan file exists)
if [ -f "$HOME/.claude/plans/"*.md 2>/dev/null ]; then
  PLAN_FILE=$(ls -t "$HOME/.claude/plans/"*.md 2>/dev/null | head -1)
  if [ -n "$PLAN_FILE" ]; then
    PLAN_TITLE=$(head -1 "$PLAN_FILE" 2>/dev/null | sed 's/^# //' || true)
    [ -n "$PLAN_TITLE" ] && CONTEXT_PARTS+=("Plan: $PLAN_TITLE")
  fi
fi

# 4. Last 3 decisions from decision log (if exists)
DECISION_DIR="system/state/decisions"
if [ -d "$DECISION_DIR" ]; then
  RECENT_DECISIONS=$(ls -t "$DECISION_DIR"/*.jsonl 2>/dev/null | head -3)
  if [ -n "$RECENT_DECISIONS" ]; then
    DECISIONS_TEXT=""
    while IFS= read -r decision_file; do
      if [ -f "$decision_file" ]; then
        # Extract the decision content (last 60 chars for brevity)
        decision_summary=$(tail -1 "$decision_file" 2>/dev/null | jq -r '.decision // .content // empty' 2>/dev/null | cut -c1-60)
        [ -n "$decision_summary" ] && DECISIONS_TEXT="${DECISIONS_TEXT}• ${decision_summary}... "
      fi
    done <<< "$RECENT_DECISIONS"
    [ -n "$DECISIONS_TEXT" ] && CONTEXT_PARTS+=("Recent decisions: $DECISIONS_TEXT")
  fi
fi

# Combine all parts with line breaks
CONTEXT=$(IFS=$'\n'; echo "${CONTEXT_PARTS[*]}")
ESCAPED=$(echo "$CONTEXT" | jq -Rs '.')
echo "{\"continue\": true, \"additionalContext\": $ESCAPED}"
