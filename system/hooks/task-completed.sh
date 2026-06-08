#!/usr/bin/env bash
# No strict mode — hooks must never fail and block the session.

# Brana PostToolUse hook — task completion pipeline.
# Triggers: Bash commands matching "brana backlog set <id> status completed"
# Actions: (1) parent rollup, (2) close linked GitHub issue, (3) log to decision log
# Input:  stdin JSON (session_id, tool_name, tool_input)
# Output: stdout JSON {"continue": true, "additionalContext": "..."}

cd /tmp 2>/dev/null || true

INPUT=$(cat) || true
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null) || true

# Only trigger on Bash
[ "${TOOL_NAME:-}" != "Bash" ] && { echo '{"continue": true}'; exit 0; }

COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null) || true

# Detect: brana backlog set <id> status completed
# Matches patterns like:
#   brana backlog set t-199 status completed
#   brana backlog set t-199 status completed && brana backlog set ...
if ! echo "$COMMAND" | grep -qE 'brana\s+backlog\s+set\s+\S+\s+status\s+completed' 2>/dev/null; then
    echo '{"continue": true}'
    exit 0
fi

# Extract task ID(s) — there may be multiple in a chained command
TASK_IDS=$(echo "$COMMAND" | grep -oE 'brana\s+backlog\s+set\s+(\S+)\s+status\s+completed' | awk '{print $4}' 2>/dev/null) || true

[ -z "$TASK_IDS" ] && { echo '{"continue": true}'; exit 0; }

# Locate brana CLI
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/resolve-brana.sh"
[ ! -x "${BRANA:-}" ] && { echo '{"continue": true}'; exit 0; }

GIT_ROOT="${CLAUDE_PROJECT_DIR:-$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null)}"

MESSAGES=""

for TASK_ID in $TASK_IDS; do
    [ -z "$TASK_ID" ] && continue

    # ── 0. Increment session score counter ──────────────────
    SS_FILE="$HOME/.claude/session-score.tsv"
    if [ -f "$SS_FILE" ]; then
        IFS=$'\t' read -r SS_DONE SS_CORR < "$SS_FILE"
        printf '%d\t%d\n' "$(( ${SS_DONE:-0} + 1 ))" "${SS_CORR:-0}" > "$SS_FILE" 2>/dev/null || true
    fi

    # ── 1. Parent rollup ──────────────────────────────────
    ROLLUP_OUT=$(cd "$GIT_ROOT" && "$BRANA" backlog rollup 2>/dev/null) || true
    ROLLUP_IDS=$(echo "$ROLLUP_OUT" | jq -r '.rollup // [] | join(", ")' 2>/dev/null) || true
    if [ -n "$ROLLUP_IDS" ]; then
        MESSAGES="${MESSAGES}Auto-rollup: completed parents [${ROLLUP_IDS}]. "
    fi

    # ── 2. Close linked GitHub issue ──────────────────────
    CONFIG="$HOME/.claude/task-sync-config.json"
    if [ -f "$CONFIG" ]; then
        GITHUB_ISSUE=$(cd "$GIT_ROOT" && "$BRANA" backlog get "$TASK_ID" --field github_issue 2>/dev/null) || true
        # Strip quotes and check for non-null
        GITHUB_ISSUE=$(echo "$GITHUB_ISSUE" | tr -d '"' 2>/dev/null) || true
        if [ -n "$GITHUB_ISSUE" ] && [ "$GITHUB_ISSUE" != "null" ]; then
            SYNC_SCRIPT="${SCRIPT_DIR}/gh-sync.sh"
            if [ -x "$SYNC_SCRIPT" ]; then
                "$SYNC_SCRIPT" close "$GITHUB_ISSUE" >> /tmp/brana-task-sync.log 2>&1 &
                MESSAGES="${MESSAGES}GitHub issue #${GITHUB_ISSUE} close triggered. "
            fi
        fi
    fi

    # ── 3. Log to decision log ────────────────────────────
    SUBJECT=$(cd "$GIT_ROOT" && "$BRANA" backlog get "$TASK_ID" --field subject 2>/dev/null) || true
    SUBJECT=$(echo "$SUBJECT" | tr -d '"' 2>/dev/null) || true
    STRATEGY=$(cd "$GIT_ROOT" && "$BRANA" backlog get "$TASK_ID" --field strategy 2>/dev/null) || true
    STRATEGY=$(echo "$STRATEGY" | tr -d '"' 2>/dev/null) || true
    if [ -n "$SUBJECT" ]; then
        (cd "$GIT_ROOT" && "$BRANA" decisions log main decision \
            "Completed ${TASK_ID} (${STRATEGY:-unknown}): ${SUBJECT}" \
            --refs "$TASK_ID") >> /tmp/brana-decisions.log 2>&1 &
    fi
done

# ── Ambient signal: window title (last completed task) ───
LAST_ID=$(echo "$TASK_IDS" | awk 'NR==1' 2>/dev/null)
if [ -n "$LAST_ID" ]; then
    printf "\033]0;brana: %s done\007" "$LAST_ID" > /dev/tty 2>/dev/null || true
fi

if [ -n "$MESSAGES" ]; then
    ESCAPED=$(echo "$MESSAGES" | jq -Rs '.')
    echo "{\"continue\": true, \"additionalContext\": $ESCAPED}"
else
    echo '{"continue": true}'
fi
