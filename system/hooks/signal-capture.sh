#!/usr/bin/env bash
# No strict mode — hooks must never fail and block the session.

# Brana UserPromptSubmit hook — signal capture (t-251).
# Detects explicit ratings (N/5, N/10, emoji) and implicit sentiment
# (positive/negative language) in user prompts. Writes to ratings.jsonl.
# On negative signals, also captures context to FAILURES/.
#
# Storage:
#   ${BRANA_RATINGS_DIR:-~/.claude/ratings}/ratings.jsonl  — all signals
#   ${BRANA_FAILURES_DIR:-~/.claude/ratings/FAILURES}/     — negative context
#
# Advisory only — always continues.
#
# Input:  stdin JSON { "prompt": "...", "session_id": "..." }
# Output: {"continue": true}

cd /tmp 2>/dev/null || true

INPUT=$(cat) || true

pass_through() {
    echo '{"continue": true}'
    exit 0
}

PROMPT=$(echo "$INPUT" | jq -r '.prompt // empty' 2>/dev/null) || pass_through
[ -z "${PROMPT:-}" ] && pass_through

SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null) || SESSION_ID=""

# ── Signal detection ──────────────────────────────────────────────────────────
CATEGORY=""
SIGNAL=""

PROMPT_LOWER=$(echo "$PROMPT" | tr '[:upper:]' '[:lower:]')

# 1. Explicit numeric ratings: N/5 or N/10
if echo "$PROMPT" | grep -qE '\b([0-9])/5\b|\b([0-9]|10)/10\b' 2>/dev/null; then
    NUM=$(echo "$PROMPT" | grep -oE '\b([0-9])/5\b|\b([0-9]|10)/10\b' | head -1)
    RAW=$(echo "$NUM" | grep -oE '^[0-9]+')
    DENOM=$(echo "$NUM" | grep -oE '[0-9]+$')
    SCORE=$(( RAW * 5 / DENOM ))  # normalize to /5
    SIGNAL="$NUM"
    [ "$SCORE" -ge 4 ] && CATEGORY="positive" || CATEGORY="negative"
fi

# 2. Emoji signals
if [ -z "$CATEGORY" ]; then
    case "$PROMPT" in
        *"👍"*|*"🎉"*|*"✅"*|*"🙌"*) CATEGORY="positive"; SIGNAL="emoji-positive" ;;
        *"👎"*|*"❌"*|*"😞"*|*"🤦"*) CATEGORY="negative"; SIGNAL="emoji-negative" ;;
    esac
fi

# 3. Explicit positive phrases
if [ -z "$CATEGORY" ]; then
    case "$PROMPT_LOWER" in
        *"perfect"*|*"exactly right"*|*"exactly what"*|*"great job"*|*"well done"*|\
        *"that's correct"*|*"that's right"*|*"nailed it"*|*"excellent"*|*"vamo"*|\
        *"dale"*|*"genial"*|*"bueno"*|*"bárbaro"*|*"barbaro"*)
            CATEGORY="positive"; SIGNAL="phrase-positive" ;;
    esac
fi

# 4. Explicit negative phrases
if [ -z "$CATEGORY" ]; then
    case "$PROMPT_LOWER" in
        *"that's wrong"*|*"that is wrong"*|*"you missed"*|*"completely wrong"*|\
        *"not right"*|*"that's incorrect"*|*"you're wrong"*|*"stop doing that"*|\
        *"don't do that"*|*"you broke"*|*"broken"*|*"nada que ver"*|\
        *"pésimo"*|*"pesimo"*)
            CATEGORY="negative"; SIGNAL="phrase-negative" ;;
    esac
fi

# No signal detected — pass through
[ -z "$CATEGORY" ] && pass_through

# ── Write to ratings.jsonl ────────────────────────────────────────────────────
RATINGS_DIR="${BRANA_RATINGS_DIR:-$HOME/.claude/ratings}"
FAILURES_DIR="${BRANA_FAILURES_DIR:-$RATINGS_DIR/FAILURES}"
mkdir -p "$RATINGS_DIR" "$FAILURES_DIR" 2>/dev/null || pass_through

RATINGS_FILE="$RATINGS_DIR/ratings.jsonl"
TS=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null) || TS="unknown"

# Truncate prompt for log (avoid bloating JSONL)
PROMPT_SHORT=$(echo "$PROMPT" | head -c 120 | tr '\n' ' ')
PROMPT_ESCAPED=$(echo "$PROMPT_SHORT" | jq -Rs '.' 2>/dev/null) || PROMPT_ESCAPED='""'
SIGNAL_ESCAPED=$(echo "$SIGNAL" | jq -Rs '.' 2>/dev/null) || SIGNAL_ESCAPED='""'
SESSION_ESCAPED=$(echo "$SESSION_ID" | jq -Rs '.' 2>/dev/null) || SESSION_ESCAPED='""'

jq -n -c \
    --arg ts "$TS" \
    --arg session_id "$SESSION_ID" \
    --arg signal "$SIGNAL" \
    --arg category "$CATEGORY" \
    --arg prompt "$PROMPT_SHORT" \
    '{ts: $ts, session_id: $session_id, signal: $signal, category: $category, prompt: $prompt}' \
    >> "$RATINGS_FILE" 2>/dev/null || true

# ── Capture failure context ───────────────────────────────────────────────────
if [ "$CATEGORY" = "negative" ]; then
    TS_SLUG=$(date -u +%Y-%m-%dT%H-%M-%S 2>/dev/null) || TS_SLUG="unknown"
    FAIL_FILE="$FAILURES_DIR/${TS_SLUG}-${SESSION_ID:-nosession}.txt"
    {
        echo "=== Failure Signal ==="
        echo "Timestamp: $TS"
        echo "Session: $SESSION_ID"
        echo "Signal: $SIGNAL"
        echo ""
        echo "=== User Prompt ==="
        echo "$PROMPT"
    } > "$FAIL_FILE" 2>/dev/null || true
fi

pass_through
