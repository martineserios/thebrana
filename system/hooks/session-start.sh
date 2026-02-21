#!/usr/bin/env bash
# No strict mode — hooks must always return valid JSON.

# Brana SessionStart hook — recall relevant patterns at session start.
# Input:  stdin JSON (session_id, cwd, hook_event_name, matcher)
# Output: stdout JSON with additionalContext field

# Ensure valid CWD
cd /tmp 2>/dev/null || true

INPUT=$(cat) || true
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null) || true
CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null) || true

if [ -z "${SESSION_ID:-}" ] || [ -z "${CWD:-}" ]; then
    echo '{"continue": true}'
    exit 0
fi

# Derive project name from git root or cwd
GIT_ROOT=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null || echo "$CWD")
PROJECT=$(basename "$GIT_ROOT")

# Write env vars for downstream hooks if CLAUDE_ENV_FILE exists
if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
    echo "BRANA_PROJECT=$PROJECT" >> "$CLAUDE_ENV_FILE"
    echo "BRANA_SESSION_ID=$SESSION_ID" >> "$CLAUDE_ENV_FILE"
fi

CONTEXT=""

# Locate claude-flow binary (nvm global → PATH → npx fallback)
CF=""
for candidate in "$HOME"/.nvm/versions/node/*/bin/claude-flow; do
    [ -x "$candidate" ] && CF="$candidate" && break
done
[ -z "$CF" ] && command -v claude-flow &>/dev/null && CF="claude-flow"
[ -z "$CF" ] && command -v npx &>/dev/null && CF="npx claude-flow"

# Primary path: claude-flow memory search
CF_WARNING=""
if [ -n "$CF" ]; then
    CF_OUTPUT=$(timeout 5 $CF memory search --query "project:$PROJECT" --format json 2>&1) || true
    CF_EXIT=$?
    CONTEXT=$(echo "$CF_OUTPUT" | grep -v '^\[' || true)
    if [ $CF_EXIT -eq 124 ]; then
        CF_WARNING="Memory search timed out (>5s). Patterns not recalled. Try: claude-flow memory search --query 'project:$PROJECT'"
    elif [ $CF_EXIT -ne 0 ] && [ -z "$CONTEXT" ]; then
        CF_WARNING="Memory search failed. Try: claude-flow memory search --query 'project:$PROJECT'"
    fi
else
    CF_WARNING="claude-flow not found. Memory recall unavailable. Install: npm i -g claude-flow"
fi

# Log recalled patterns to session file for promotion tracking
if [ -n "$CONTEXT" ]; then
    SESSION_FILE="/tmp/brana-session-${SESSION_ID}.jsonl"
    jq -n -c \
        --argjson ts "$(date +%s 2>/dev/null || echo 0)" \
        --arg tool "session-start" \
        --arg outcome "recall" \
        --arg detail "$CONTEXT" \
        '{ts: $ts, tool: $tool, outcome: $outcome, detail: $detail}' >> "$SESSION_FILE" 2>/dev/null || true
fi

# Fallback: grep native auto memory for project name
if [ -z "$CONTEXT" ]; then
    MEMORY_HIT=""
    for memfile in "$HOME"/.claude/projects/*/memory/MEMORY.md; do
        if [ -f "$memfile" ]; then
            MATCH=$(grep -i "$PROJECT" "$memfile" 2>/dev/null | head -5 || true)
            if [ -n "$MATCH" ]; then
                MEMORY_HIT="$MEMORY_HIT$MATCH"$'\n'
            fi
        fi
    done
    if [ -n "$MEMORY_HIT" ]; then
        CONTEXT="$MEMORY_HIT"
    fi
fi

# ── Task context injection ──────────────────────────────
TASK_CONTEXT=""
TASKS_FILE=""

# Find tasks.json in project
if [ -d "$GIT_ROOT/.claude" ] && [ -f "$GIT_ROOT/.claude/tasks.json" ]; then
    TASKS_FILE="$GIT_ROOT/.claude/tasks.json"
elif [ -d "$CWD/.claude" ] && [ -f "$CWD/.claude/tasks.json" ]; then
    TASKS_FILE="$CWD/.claude/tasks.json"
fi

if [ -n "$TASKS_FILE" ] && [ -f "$TASKS_FILE" ]; then
    # Extract summary + next unblocked task in single jq call
    TASK_SUMMARY=$(jq -r '
      .project as $proj |
      ([.tasks[] | select(.status == "completed") | .id]) as $completed |
      ([.tasks[] | select(.type == "phase" and .status == "in_progress")] | first) as $phase |
      ([.tasks[] | select(.type == "task" or .type == "subtask")] | length) as $total |
      ([.tasks[] | select((.type == "task" or .type == "subtask") and .status == "completed")] | length) as $done |
      ([.tasks[] | select(.stream == "bugs" and .status != "completed" and .status != "cancelled")] | length) as $bugs |
      ([.tasks[] | select(
        (.type == "task" or .type == "subtask") and
        .status == "pending" and
        ((.blocked_by // []) | all(. as $b | $completed | index($b) != null))
      )] | sort_by(.order) | first) as $next |
      "Project: \($proj)" +
      (if $phase then " | Phase: \($phase.subject) (\($done)/\($total))" else "" end) +
      (if $bugs > 0 then " | Bugs: \($bugs) open" else "" end) +
      "\n" +
      (if $next then "Next unblocked: \($next.id) \($next.subject) (pending)"
       elif ($total > 0 and $total == $done) then "All tasks completed. Use /tasks plan for next phase."
       else "" end) +
      "\nCommands: /tasks next, /tasks plan, /tasks add, /tasks start <id>"
    ' "$TASKS_FILE" 2>/dev/null) || true

    if [ -n "$TASK_SUMMARY" ]; then
        TASK_CONTEXT="[Active tasks] $TASK_SUMMARY"
    fi
else
    # No tasks.json — suggest creating one, with portfolio fallback
    TASK_CONTEXT="[Tasks] No tasks.json found. Use /tasks plan to create one."
    PORTFOLIO_FILE="$HOME/.claude/tasks-portfolio.json"
    if [ -f "$PORTFOLIO_FILE" ]; then
        PORTFOLIO_SUMMARY=$(jq -r '
          [.projects[] |
            .slug as $slug |
            (.path | gsub("^~/"; env.HOME + "/")) as $path |
            {slug: $slug, path: $path}
          ] | map(.slug) | join(", ")
        ' "$PORTFOLIO_FILE" 2>/dev/null) || true
        if [ -n "$PORTFOLIO_SUMMARY" ]; then
            TASK_CONTEXT="[Task portfolio] Projects: $PORTFOLIO_SUMMARY. No tasks.json — use /tasks plan to create one."
        fi
    fi
fi

# Output — only inject context if we found something
OUTPUT_PARTS=""
if [ -n "$CONTEXT" ]; then
    OUTPUT_PARTS="[Recalled patterns — confidence:quarantine means unproven, treat with caution. confidence:proven means validated across 3+ sessions.]
$CONTEXT"
fi
if [ -n "$TASK_CONTEXT" ]; then
    OUTPUT_PARTS="${OUTPUT_PARTS:+$OUTPUT_PARTS
}$TASK_CONTEXT"
fi
if [ -n "$CF_WARNING" ]; then
    OUTPUT_PARTS="${OUTPUT_PARTS:+$OUTPUT_PARTS
}[Hook warning] $CF_WARNING"
fi

if [ -n "$OUTPUT_PARTS" ]; then
    ESCAPED=$(echo "$OUTPUT_PARTS" | jq -Rs '.' 2>/dev/null) || ESCAPED='""'
    echo "{\"continue\": true, \"additionalContext\": $ESCAPED}"
else
    echo '{"continue": true}'
fi
