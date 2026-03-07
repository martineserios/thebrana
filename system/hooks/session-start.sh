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

source "$HOME/.claude/scripts/cf-env.sh"

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

# Wave 3: correction-pattern priority recall
CORRECTION_CONTEXT=""
if [ -n "$CF" ]; then
    CP_OUTPUT=$(timeout 5 $CF memory search --query "project:$PROJECT type:correction" --namespace patterns --format json 2>&1); CP_EXIT=$?
    if [ $CP_EXIT -eq 0 ] && [ -n "$CP_OUTPUT" ]; then
        # Extract high-confidence correction patterns (promoted via fast-track or recall)
        CP_LINES=$(echo "$CP_OUTPUT" | jq -r '.[] | select(.value | fromjson? | .confidence >= 0.8) | (.key + ": " + (.value | fromjson? | .solution // "unknown"))' 2>/dev/null | head -3) || CP_LINES=""
        if [ -n "$CP_LINES" ]; then
            CORRECTION_CONTEXT="[Correction patterns — high confidence, apply early if similar errors arise]
$CP_LINES"
        fi
    fi
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

# Self-learning loop: check flags from previous session
LOOP_CONTEXT=""
LAYER0_DIR=""
for projdir in "$HOME"/.claude/projects/*/; do
    if [ -d "${projdir}memory" ]; then
        if grep -qi "$PROJECT" "${projdir}memory/MEMORY.md" 2>/dev/null; then
            LAYER0_DIR="${projdir}memory"
            break
        fi
    fi
done

if [ -n "$LAYER0_DIR" ]; then
    # Check for doc drift flag
    BACKPROP_FLAG="$LAYER0_DIR/.needs-backprop"
    if [ -f "$BACKPROP_FLAG" ]; then
        DRIFT_INFO=$(cat "$BACKPROP_FLAG" 2>/dev/null) || true
        LOOP_CONTEXT="[Previous session] System files changed ($DRIFT_INFO). Consider running /back-propagate to sync specs."
        rm -f "$BACKPROP_FLAG"
    fi

    # Check for pending errata
    if [ -f "$LAYER0_DIR/pending-learnings.md" ]; then
        PENDING_COUNT=$(grep -c '^## Session' "$LAYER0_DIR/pending-learnings.md" 2>/dev/null) || PENDING_COUNT=0
        if [ "$PENDING_COUNT" -gt 0 ]; then
            LOOP_CONTEXT="${LOOP_CONTEXT:+$LOOP_CONTEXT
}[Pending learnings] $PENDING_COUNT unprocessed session(s) in pending-learnings.md. Consider running /debrief."
        fi
    fi
fi

# ── Venture project detection (absorbed from session-start-venture.sh) ──
VENTURE_CONTEXT=""
VENTURE_DIRS="docs/sops docs/okrs docs/metrics docs/pipeline docs/venture"
IS_VENTURE=false

for dir in $VENTURE_DIRS; do
    if [ -d "$CWD/$dir" ]; then
        IS_VENTURE=true
        break
    fi
done

# Fallback: grep CLAUDE.md for business keywords
if [ "$IS_VENTURE" = false ] && [ -f "$CWD/CLAUDE.md" ]; then
    if grep -qiE '(venture|business|startup|revenue|pipeline|okr|growth)' "$CWD/CLAUDE.md" 2>/dev/null; then
        IS_VENTURE=true
    fi
fi

if [ "$IS_VENTURE" = true ]; then
    VENTURE_CONTEXT="Venture project detected. Auto-delegating to daily-ops agent for morning check."

    # Weekly review staleness check
    NEWEST_REVIEW=""
    if [ -d "$CWD/docs/reviews" ]; then
        NEWEST_REVIEW=$(find "$CWD/docs/reviews" -name 'weekly-*.md' -type f -printf '%T@\n' 2>/dev/null | sort -rn | head -1 || true)
    fi

    if [ -n "$NEWEST_REVIEW" ]; then
        NOW=$(date +%s 2>/dev/null) || NOW=0
        AGE_SECONDS=$(echo "$NOW - ${NEWEST_REVIEW%.*}" | bc 2>/dev/null) || AGE_SECONDS=0
        SEVEN_DAYS=604800
        if [ "$AGE_SECONDS" -gt "$SEVEN_DAYS" ]; then
            DAYS_AGO=$(( AGE_SECONDS / 86400 ))
            VENTURE_CONTEXT="$VENTURE_CONTEXT
Weekly review is ${DAYS_AGO} days old. Consider running /review weekly."
        fi
    else
        VENTURE_CONTEXT="$VENTURE_CONTEXT
No weekly review found. Consider running /review weekly."
    fi

    # Log to session JSONL
    SESSION_FILE="/tmp/brana-session-${SESSION_ID}.jsonl"
    jq -n -c \
        --argjson ts "$(date +%s 2>/dev/null || echo 0)" \
        --arg tool "session-start-venture" \
        --arg outcome "venture-detected" \
        --arg detail "$VENTURE_CONTEXT" \
        '{ts: $ts, tool: $tool, outcome: $outcome, detail: $detail}' >> "$SESSION_FILE" 2>/dev/null || true
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
if [ -n "$CORRECTION_CONTEXT" ]; then
    OUTPUT_PARTS="${OUTPUT_PARTS:+$OUTPUT_PARTS
}$CORRECTION_CONTEXT"
fi
if [ -n "$LOOP_CONTEXT" ]; then
    OUTPUT_PARTS="${OUTPUT_PARTS:+$OUTPUT_PARTS
}$LOOP_CONTEXT"
fi
if [ -n "$VENTURE_CONTEXT" ]; then
    OUTPUT_PARTS="${OUTPUT_PARTS:+$OUTPUT_PARTS
}[Venture] $VENTURE_CONTEXT"
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
