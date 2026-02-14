#!/usr/bin/env bash
# No strict mode — hooks must always return valid JSON.

# Brana SessionStart hook — detect venture projects, nudge daily-ops agent.
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
    CF=""
    for candidate in "$HOME"/.nvm/versions/node/*/bin/claude-flow; do
        [ -x "$candidate" ] && CF="$candidate" && break
    done
    [ -z "$CF" ] && command -v claude-flow &>/dev/null && CF="claude-flow"

    if [ -n "$CF" ]; then
        REVIEW_HIT=$(timeout 3 $CF memory search --query "weekly-review" --namespace business 2>/dev/null | head -3 || true)
        if [ -z "$REVIEW_HIT" ]; then
            STALE_WARNING="No weekly review found. Consider running /weekly-review."
        fi
    else
        STALE_WARNING="No weekly review found. Consider running /weekly-review."
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
