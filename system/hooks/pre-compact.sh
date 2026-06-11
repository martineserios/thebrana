#!/usr/bin/env bash
# No strict mode — hooks must always return valid JSON.

# PreCompact: inject session context into post-compaction window.
#
# Fires before automatic or manual compaction. Returns additionalContext
# so the compacted conversation retains: active task, branch, build step,
# AC lines, and pending work.
#
# Output cap: target <4KB to stay well under the 10K file-redirect threshold.

cd /tmp 2>/dev/null || true

INPUT=$(cat) || true

pass_through() {
    echo '{"continue": true}'
    exit 0
}

SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null) || true
CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null) || true
TRIGGER=$(echo "$INPUT" | jq -r '.trigger // "auto"' 2>/dev/null) || TRIGGER="auto"

[ -z "$CWD" ] && pass_through

# Resolve git root and brana CLI
GIT_ROOT=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null) || GIT_ROOT="$CWD"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/resolve-brana.sh" 2>/dev/null || true

BRANCH=$(git -C "$GIT_ROOT" branch --show-current 2>/dev/null) || BRANCH="unknown"
PROJECT=$(basename "$GIT_ROOT")

# ── Silent close snapshot (ADR-053 §5 Layer 2, t-1988) ─────────────
# Snapshot the session diff before compaction so nothing is lost if the
# user never ran /brana:close --continue (Layer 1 is the interactive ask
# in the agent loop — context-budget rule). Guards:
#   - idempotent per HEAD: marker file keyed on project + commit hash
#   - NEVER blocks compaction: every failure path falls through silently
SNAPSHOT_NOTE=""
SNAPSHOT_SCRIPT="${BRANA_SNAPSHOT_SCRIPT:-${SCRIPT_DIR}/../scripts/close-snapshot.sh}"
HEAD_HASH=$(git -C "$GIT_ROOT" rev-parse --short HEAD 2>/dev/null) || HEAD_HASH=""
if [ -n "$HEAD_HASH" ] && [ -x "$SNAPSHOT_SCRIPT" ]; then
    GUARD_DIR="${BRANA_PRECOMPACT_GUARD_DIR:-$HOME/.claude/sessions/.precompact-guards}"
    GUARD="$GUARD_DIR/${PROJECT}-${HEAD_HASH}"
    if [ ! -f "$GUARD" ]; then
        COMMIT_COUNT=$(git -C "$GIT_ROOT" log --oneline --since="6 hours ago" 2>/dev/null | wc -l | tr -d ' ') || COMMIT_COUNT=0
        if bash "$SNAPSHOT_SCRIPT" --git-root "$GIT_ROOT" --branch "$BRANCH" \
                --project "$PROJECT" --commit-count "${COMMIT_COUNT:-0}" >/dev/null 2>&1; then
            mkdir -p "$GUARD_DIR" 2>/dev/null && touch "$GUARD" 2>/dev/null
            SNAPSHOT_NOTE="Pre-compaction snapshot saved and queued (HEAD $HEAD_HASH) — nothing from this session is lost to compaction."
        fi
    fi
fi

# ── Active tasks ──────────────────────────────────────────
TASKS_BLOCK=""
if [ -x "$BRANA" ]; then
    TASKS_JSON=$(cd "$GIT_ROOT" && "$BRANA" backlog query --status in_progress --output json 2>/dev/null) || TASKS_JSON="[]"
    # Build one line per task: id, subject, build_step, AC lines from context
    TASKS_BLOCK=$(echo "$TASKS_JSON" | jq -r '
        .[] |
        "- \(.id): \(.subject)" +
        (if .build_step then " [step:\(.build_step)]" else "" end) +
        (if .context then
            (.context | split("\n") | map(select(startswith("AC:"))) | join(" | "))
            | if . != "" then " — \(.)" else "" end
         else "" end) +
        (if .notes and (.notes | length > 0) then
            "\n  notes: \(.notes | split("\n") | .[0:2] | join(" "))"
         else "" end)
    ' 2>/dev/null | head -20) || TASKS_BLOCK=""
fi

[ -z "$TASKS_BLOCK" ] && TASKS_BLOCK="(none)"

# ── Session summary (brana session read) ──────────────────
SESSION_BLOCK=""
SESSION_FILE=$(ls /tmp/brana-session-${SESSION_ID}*.jsonl 2>/dev/null | head -1) || SESSION_FILE=""
if [ -n "$SESSION_FILE" ] && [ -f "$SESSION_FILE" ]; then
    # Pull the last session-state write's accomplished field if present
    SESSION_BLOCK=$(grep '"accomplished"' "$SESSION_FILE" 2>/dev/null | tail -1 | \
        jq -r '.accomplished // ""' 2>/dev/null | head -c 500) || SESSION_BLOCK=""
fi

# ── Compose context string ────────────────────────────────
CONTEXT="[Pre-compaction snapshot | project: $PROJECT | branch: $BRANCH | trigger: $TRIGGER]

Active tasks:
$TASKS_BLOCK"

if [ -n "$SESSION_BLOCK" ]; then
    CONTEXT="$CONTEXT

Recent session work:
$SESSION_BLOCK"
fi

CONTEXT="$CONTEXT

Note: This snapshot was injected before compaction. Task details may have advanced — run \`brana backlog query --status in_progress\` to verify current state."

# ── Emit ─────────────────────────────────────────────────
ESCAPED=$(printf '%s' "$CONTEXT" | jq -Rs '.') 2>/dev/null || pass_through
echo "{\"continue\": true, \"additionalContext\": $ESCAPED}"
