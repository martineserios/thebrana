#!/usr/bin/env bash
# No strict mode — hooks must always return valid JSON.

# Brana SessionEnd hook — flush accumulated session events to persistent storage.
# Input:  stdin JSON (session_id, cwd, hook_event_name, matcher)
# Output: stdout JSON with continue: true

# Ensure valid CWD
cd /tmp 2>/dev/null || true

INPUT=$(cat) || true
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null) || true
CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null) || true

if [ -z "${SESSION_ID:-}" ] || [ -z "${CWD:-}" ]; then
    echo '{"continue": true}'
    exit 0
fi

# Derive project name
GIT_ROOT=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null || echo "$CWD")
PROJECT=$(basename "$GIT_ROOT")

SESSION_FILE="/tmp/brana-session-${SESSION_ID}.jsonl"

# If no events accumulated, nothing to flush
if [ ! -f "$SESSION_FILE" ] || [ ! -s "$SESSION_FILE" ]; then
    rm -f "$SESSION_FILE"
    echo '{"continue": true}'
    exit 0
fi

# Summarize accumulated events
TOTAL=$(wc -l < "$SESSION_FILE" 2>/dev/null) || TOTAL=0
SUCCESSES=$(grep -c '"outcome":"success"' "$SESSION_FILE" 2>/dev/null) || SUCCESSES=0
FAILURES=$(grep -c '"outcome":"failure"' "$SESSION_FILE" 2>/dev/null) || FAILURES=0
TOOLS=$(jq -r '.tool' "$SESSION_FILE" 2>/dev/null | sort -u | paste -sd ',' || echo "unknown")
FILES=$(jq -r '.detail // empty' "$SESSION_FILE" 2>/dev/null | sort -u | head -10 | paste -sd ',' || echo "")
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null) || TIMESTAMP="unknown"

SUMMARY_JSON=$(jq -n \
    --arg project "${PROJECT:-unknown}" \
    --arg session "${SESSION_ID:-unknown}" \
    --arg ts "${TIMESTAMP:-unknown}" \
    --argjson total "${TOTAL:-0}" \
    --argjson ok "${SUCCESSES:-0}" \
    --argjson fail "${FAILURES:-0}" \
    --arg tools "${TOOLS:-unknown}" \
    --arg files "${FILES:-}" \
    --argjson confidence 0.5 \
    --argjson transferable false \
    --argjson recall_count 0 \
    '{project: $project, session: $session, timestamp: $ts, events: $total, successes: $ok, failures: $fail, tools: $tools, files: $files, confidence: $confidence, transferable: $transferable, recall_count: $recall_count}' 2>/dev/null) || SUMMARY_JSON="{}"

source "$HOME/.claude/scripts/cf-env.sh"

# Layer 1: try claude-flow memory store
STORED_L1=false
CF_WARNING=""
if [ -n "$CF" ]; then
    KEY="session:${PROJECT}:${SESSION_ID}"
    VALUE=$(echo "$SUMMARY_JSON" | jq -c '.' 2>/dev/null) || VALUE="$SUMMARY_JSON"
    if [ "$FAILURES" -gt 0 ]; then
        OUTCOME="mixed"
    else
        OUTCOME="success"
    fi
    TAGS="project:$PROJECT,type:session-summary,outcome:$OUTCOME,confidence:quarantine"
    CF_ERR=$(timeout 5 $CF memory store -k "$KEY" -v "$VALUE" --namespace patterns --tags "$TAGS" 2>&1) || true
    CF_EXIT=$?
    if [ $CF_EXIT -eq 0 ]; then
        STORED_L1=true
    elif [ $CF_EXIT -eq 124 ]; then
        CF_WARNING="Session summary store timed out (>5s). Try: claude-flow memory store -k '$KEY'"
    else
        CF_WARNING="Session summary store failed (exit $CF_EXIT). Try: claude-flow memory store -k '$KEY'"
    fi
else
    CF_WARNING="claude-flow not found. Session summary not persisted. Install: npm i -g claude-flow"
fi

# Log CF warning to session file for diagnostics
if [ -n "$CF_WARNING" ]; then
    jq -n -c \
        --argjson ts "$(date +%s 2>/dev/null || echo 0)" \
        --arg tool "session-end" \
        --arg outcome "cf-warning" \
        --arg detail "$CF_WARNING" \
        '{ts: $ts, tool: $tool, outcome: $outcome, detail: $detail}' >> "$SESSION_FILE" 2>/dev/null || true
fi

# Layer 0: find the project's auto memory directory
LAYER0_DIR=""
for projdir in "$HOME"/.claude/projects/*/; do
    if [ -d "${projdir}memory" ]; then
        if grep -qi "$PROJECT" "${projdir}memory/MEMORY.md" 2>/dev/null; then
            LAYER0_DIR="${projdir}memory"
            break
        fi
    fi
done

# Layer 1 fallback: write to project auto memory (not global)
if [ "$STORED_L1" = false ] && [ -n "$LAYER0_DIR" ]; then
    {
        echo ""
        echo "## Session $SESSION_ID ($TIMESTAMP)"
        echo "- Project: $PROJECT"
        echo "- Events: $TOTAL ($SUCCESSES ok, $FAILURES fail)"
        echo "- Tools: $TOOLS"
        if [ -n "$FILES" ]; then echo "- Files: $FILES"; fi
    } >> "$LAYER0_DIR/pending-learnings.md"
fi

# Layer 0: always write session summary to project auto memory
if [ -n "$LAYER0_DIR" ]; then
    {
        echo ""
        echo "### Session $SESSION_ID ($TIMESTAMP)"
        echo "- Events: $TOTAL ($SUCCESSES ok, $FAILURES fail)"
        echo "- Tools: $TOOLS"
        if [ -n "$FILES" ]; then echo "- Files: $FILES"; fi
    } >> "$LAYER0_DIR/sessions.md"
fi

# Clean up temp file
rm -f "$SESSION_FILE"

echo '{"continue": true}'
