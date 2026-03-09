#!/usr/bin/env bash
# No strict mode — hooks must always return valid JSON.

# Brana SessionStart hook — detect venture clients, nudge daily-ops agent.
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

# --- Venture project detection ---
# Check for venture-specific directories
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

# Not a venture project — early exit
if [ "$IS_VENTURE" = false ]; then
    echo '{"continue": true}'
    exit 0
fi

# --- Weekly review staleness check ---
STALE_WARNING=""
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
        STALE_WARNING="Weekly review is ${DAYS_AGO} days old. Consider running /weekly-review."
    fi
else
    # No weekly review found — check ReasoningBank as fallback
    # Source cf-env.sh: plugin-bundled copy first, bootstrap fallback
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [ -f "$SCRIPT_DIR/lib/cf-env.sh" ]; then
        source "$SCRIPT_DIR/lib/cf-env.sh"
    else
        source "$HOME/.claude/scripts/cf-env.sh"
    fi

    if [ -n "$CF" ]; then
        CF_OUTPUT=$(timeout 3 $CF memory search --query "weekly-review" --namespace business 2>&1) || true
        CF_EXIT=$?
        REVIEW_HIT=$(echo "$CF_OUTPUT" | head -3 || true)
        if [ $CF_EXIT -eq 124 ]; then
            STALE_WARNING="Weekly review check timed out. Consider running /weekly-review."
        elif [ -z "$REVIEW_HIT" ]; then
            STALE_WARNING="No weekly review found. Consider running /weekly-review."
        fi
    else
        STALE_WARNING="claude-flow not found — weekly review status unknown. Consider running /weekly-review."
    fi
fi

# --- Build context ---
CONTEXT="Venture project detected. Auto-delegating to daily-ops agent for morning check."
if [ -n "$STALE_WARNING" ]; then
    CONTEXT="$CONTEXT
$STALE_WARNING"
fi

# Log to session JSONL
SESSION_FILE="/tmp/brana-session-${SESSION_ID}.jsonl"
jq -n -c \
    --argjson ts "$(date +%s 2>/dev/null || echo 0)" \
    --arg tool "session-start-venture" \
    --arg outcome "venture-detected" \
    --arg detail "$CONTEXT" \
    '{ts: $ts, tool: $tool, outcome: $outcome, detail: $detail}' >> "$SESSION_FILE" 2>/dev/null || true

# Output with additionalContext
ESCAPED=$(echo "$CONTEXT" | jq -Rs '.' 2>/dev/null) || ESCAPED='""'
echo "{\"continue\": true, \"additionalContext\": $ESCAPED}"
