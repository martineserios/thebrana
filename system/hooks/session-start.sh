#!/usr/bin/env bash
# No strict mode — hooks must always return valid JSON.

# Brana SessionStart hook — recall relevant patterns at session start.
# Input:  stdin JSON (session_id, cwd, hook_event_name, matcher)
# Output: stdout JSON with additionalContext field
#
# Strategy: emit JSON response as fast as possible (additionalContext must be
# synchronous), then fork non-essential logging to background.

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

# Source cf-env.sh: plugin-bundled copy first, bootstrap fallback
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/lib/cf-env.sh" ]; then
    source "$SCRIPT_DIR/lib/cf-env.sh"
else
    source "$HOME/.claude/scripts/cf-env.sh"
fi

# Primary path: claude-flow memory search
CF_WARNING=""
if [ -n "$CF" ]; then
    CF_OUTPUT=$(timeout 5 $CF memory search --query "client:$PROJECT" --format json 2>&1) || true
    CF_EXIT=$?
    CONTEXT=$(echo "$CF_OUTPUT" | grep -v '^\[' || true)
    if [ $CF_EXIT -eq 124 ]; then
        CF_WARNING="Memory search timed out (>5s). Patterns not recalled. Try: claude-flow memory search --query 'client:$PROJECT'"
    elif [ $CF_EXIT -ne 0 ] && [ -z "$CONTEXT" ]; then
        CF_WARNING="Memory search failed. Try: claude-flow memory search --query 'client:$PROJECT'"
    fi
else
    CF_WARNING="claude-flow not found. Memory recall unavailable. Install: npm i -g claude-flow"
fi

# Wave 3: correction-pattern priority recall
CORRECTION_CONTEXT=""
if [ -n "$CF" ]; then
    CP_OUTPUT=$(timeout 5 $CF memory search --query "client:$PROJECT type:correction" --namespace patterns --format json 2>&1); CP_EXIT=$?
    if [ $CP_EXIT -eq 0 ] && [ -n "$CP_OUTPUT" ]; then
        # Extract high-confidence correction patterns (promoted via fast-track or recall)
        CP_LINES=$(echo "$CP_OUTPUT" | jq -r '.[] | select(.value | fromjson? | .confidence >= 0.8) | (.key + ": " + (.value | fromjson? | .solution // "unknown"))' 2>/dev/null | head -3) || CP_LINES=""
        if [ -n "$CP_LINES" ]; then
            CORRECTION_CONTEXT="[Correction patterns — high confidence, apply early if similar errors arise]
$CP_LINES"
        fi
    fi
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
       elif ($total > 0 and $total == $done) then "All tasks completed. Use /brana:backlog plan for next phase."
       else "" end) +
      "\nCommands: /brana:backlog next, /brana:backlog plan, /brana:backlog add, /brana:backlog start <id>"
    ' "$TASKS_FILE" 2>/dev/null) || true

    if [ -n "$TASK_SUMMARY" ]; then
        TASK_CONTEXT="[Active tasks] $TASK_SUMMARY"
    fi
else
    # No tasks.json — suggest creating one, with portfolio fallback
    TASK_CONTEXT="[Tasks] No tasks.json found. Use /brana:backlog plan to create one."
    PORTFOLIO_FILE="$HOME/.claude/tasks-portfolio.json"
    if [ -f "$PORTFOLIO_FILE" ]; then
        PORTFOLIO_SUMMARY=$(jq -r '
          if .clients then
            [.clients[] | .slug] | join(", ")
          elif .projects then
            [.projects[] | .slug] | join(", ")
          else empty end
        ' "$PORTFOLIO_FILE" 2>/dev/null) || true
        if [ -n "$PORTFOLIO_SUMMARY" ]; then
            TASK_CONTEXT="[Task portfolio] Clients: $PORTFOLIO_SUMMARY. No tasks.json — use /brana:backlog plan to create one."
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
        # Separate system drift from feature doc staleness
        DOCS_STALE=$(echo "$DRIFT_INFO" | grep "^docs-stale:" | sed 's/^docs-stale: //' || true)
        SYS_DRIFT=$(echo "$DRIFT_INFO" | grep -v "^docs-stale:" || true)
        if [ -n "$SYS_DRIFT" ]; then
            LOOP_CONTEXT="[Previous session] System files changed ($SYS_DRIFT). Consider running /brana:reconcile to sync specs."
        fi
        if [ -n "$DOCS_STALE" ]; then
            LOOP_CONTEXT="$LOOP_CONTEXT
[Stale feature docs] These docs may need updating: $DOCS_STALE. Review or run /brana:reconcile."
        fi
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
Weekly review is ${DAYS_AGO} days old. Consider running /brana:review weekly."
        fi
    else
        VENTURE_CONTEXT="$VENTURE_CONTEXT
No weekly review found. Consider running /brana:review weekly."
    fi

fi

# ── Spec graph staleness check ────────────────────────────
STALE_WARNING=""
SPEC_GRAPH="$GIT_ROOT/docs/spec-graph.json"
if [ -f "$SPEC_GRAPH" ]; then
    GENERATED=$(python3 -c "import json,sys; print(json.load(sys.stdin).get('_meta',{}).get('generated',''))" < "$SPEC_GRAPH" 2>/dev/null || echo "")
    if [ -n "$GENERATED" ]; then
        DAYS_OLD=$(python3 -c "from datetime import datetime,timezone; print((datetime.now(timezone.utc)-datetime.fromisoformat('$GENERATED'.replace('Z','+00:00'))).days)" 2>/dev/null || echo "0")
        if [ "$DAYS_OLD" -gt 7 ]; then
            STALE_WARNING="Spec graph is stale (generated: $GENERATED, ${DAYS_OLD}d ago). Run: uv run python3 system/scripts/spec_graph.py generate"
        fi
    fi
fi
# No warning if graph doesn't exist — session-end auto-generates it

# ── Decision log: inject HIGH findings from last session ──
DECISION_CONTEXT=""
DECISIONS_PY="$SCRIPT_DIR/../scripts/decisions.py"
if [ -f "$DECISIONS_PY" ]; then
    HIGH_FINDINGS=$(uv run python3 "$DECISIONS_PY" read --last 10 --severity HIGH 2>/dev/null || echo "")
    if [ -n "$HIGH_FINDINGS" ]; then
        DECISION_CONTEXT="Recent HIGH findings from last session:
$HIGH_FINDINGS"
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
if [ -n "$STALE_WARNING" ]; then
    OUTPUT_PARTS="${OUTPUT_PARTS:+$OUTPUT_PARTS
}[Spec graph] $STALE_WARNING"
fi
if [ -n "$DECISION_CONTEXT" ]; then
    OUTPUT_PARTS="${OUTPUT_PARTS:+$OUTPUT_PARTS
}[Decision log] $DECISION_CONTEXT"
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

# ── Fork non-essential work to background ───────────────
# Logging and metrics don't affect the response — run after JSON is emitted.
(
    SESSION_FILE="/tmp/brana-session-${SESSION_ID}.jsonl"

    # Log recalled patterns to session file for promotion tracking
    if [ -n "$CONTEXT" ]; then
        jq -n -c \
            --argjson ts "$(date +%s 2>/dev/null || echo 0)" \
            --arg tool "session-start" \
            --arg outcome "recall" \
            --arg detail "$CONTEXT" \
            '{ts: $ts, tool: $tool, outcome: $outcome, detail: $detail}' >> "$SESSION_FILE" 2>/dev/null || true
    fi

    # Log venture detection to session file
    if [ "$IS_VENTURE" = true ] && [ -n "$VENTURE_CONTEXT" ]; then
        jq -n -c \
            --argjson ts "$(date +%s 2>/dev/null || echo 0)" \
            --arg tool "session-start-venture" \
            --arg outcome "venture-detected" \
            --arg detail "$VENTURE_CONTEXT" \
            '{ts: $ts, tool: $tool, outcome: $outcome, detail: $detail}' >> "$SESSION_FILE" 2>/dev/null || true
    fi

    # ADR-015: sync operational state from cache to repos (push)
    SYNC_SCRIPT="$SCRIPT_DIR/../scripts/sync-state.sh"
    if [ -x "$SYNC_SCRIPT" ]; then
        "$SYNC_SCRIPT" push 2>/dev/null || true
    fi
) &
disown 2>/dev/null || true
