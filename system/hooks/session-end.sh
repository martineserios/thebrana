#!/usr/bin/env bash
# No strict mode — hooks must always return valid JSON.

# Brana SessionEnd hook — flush accumulated session events to persistent storage.
# Wave 1 (#75): compound metrics (correction rate, test coverage, cascade count).
# Wave 4 (#75): flywheel metrics (correction_rate, auto_fix_rate, test_write_rate, cascade_rate, delegation_count).
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
FAILURES=$(jq -r 'select(.outcome == "failure" or .outcome == "test-fail" or .outcome == "lint-fail") | .outcome' "$SESSION_FILE" 2>/dev/null | wc -l) || FAILURES=0
TOOLS=$(jq -r '.tool' "$SESSION_FILE" 2>/dev/null | sort -u | paste -sd ',' || echo "unknown")
FILES=$(jq -r '.detail // empty' "$SESSION_FILE" 2>/dev/null | sort -u | head -10 | paste -sd ',' || echo "")
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null) || TIMESTAMP="unknown"

# Wave 1 compound metrics
CORRECTIONS=$(grep -c '"outcome":"correction"' "$SESSION_FILE" 2>/dev/null) || CORRECTIONS=0
TEST_WRITES=$(grep -c '"outcome":"test-write"' "$SESSION_FILE" 2>/dev/null) || TEST_WRITES=0
CASCADES=$(grep -c '"cascade":true' "$SESSION_FILE" 2>/dev/null) || CASCADES=0
TEST_PASSES=$(grep -c '"outcome":"test-pass"' "$SESSION_FILE" 2>/dev/null) || TEST_PASSES=0
TEST_FAILS=$(grep -c '"outcome":"test-fail"' "$SESSION_FILE" 2>/dev/null) || TEST_FAILS=0
LINT_PASSES=$(grep -c '"outcome":"lint-pass"' "$SESSION_FILE" 2>/dev/null) || LINT_PASSES=0
LINT_FAILS=$(grep -c '"outcome":"lint-fail"' "$SESSION_FILE" 2>/dev/null) || LINT_FAILS=0
EDITS=$(jq -r 'select(.tool == "Edit" or .tool == "Write") | .tool' "$SESSION_FILE" 2>/dev/null | wc -l) || EDITS=0

# Wave 4: flywheel metrics — rates derived from compound metrics
# correction_rate: corrections per edit (lower = better planning)
if [ "$EDITS" -gt 0 ]; then
    CORRECTION_RATE=$(awk "BEGIN {printf \"%.2f\", $CORRECTIONS / $EDITS}") || CORRECTION_RATE="0.00"
else
    CORRECTION_RATE="0.00"
fi

# test_write_rate: test writes per edit (higher = better TDD discipline)
if [ "$EDITS" -gt 0 ]; then
    TEST_WRITE_RATE=$(awk "BEGIN {printf \"%.2f\", $TEST_WRITES / $EDITS}") || TEST_WRITE_RATE="0.00"
else
    TEST_WRITE_RATE="0.00"
fi

# cascade_rate: cascades per failure (lower = better error handling)
if [ "$FAILURES" -gt 0 ]; then
    CASCADE_RATE=$(awk "BEGIN {printf \"%.2f\", $CASCADES / $FAILURES}") || CASCADE_RATE="0.00"
else
    CASCADE_RATE="0.00"
fi

# auto_fix_rate: failure→success recovery on same target (higher = better autonomous recovery)
AUTO_FIXES=0
if [ "$FAILURES" -gt 0 ]; then
    AUTO_FIXES=$(jq -r '[.outcome, .detail] | @tsv' "$SESSION_FILE" 2>/dev/null | awk '
        BEGIN { fixes=0 }
        /^failure\t/ { prev_fail[$2]=1 }
        /^test-fail\t/ { prev_fail[$2]=1 }
        /^lint-fail\t/ { prev_fail[$2]=1 }
        /^success\t/ { if ($2 in prev_fail) { fixes++; delete prev_fail[$2] } }
        /^correction\t/ { if ($2 in prev_fail) { fixes++; delete prev_fail[$2] } }
        /^test-pass\t/ { if ($2 in prev_fail) { fixes++; delete prev_fail[$2] } }
        /^lint-pass\t/ { if ($2 in prev_fail) { fixes++; delete prev_fail[$2] } }
        END { print fixes }
    ' 2>/dev/null) || AUTO_FIXES=0
    AUTO_FIX_RATE=$(awk "BEGIN {printf \"%.2f\", $AUTO_FIXES / $FAILURES}") || AUTO_FIX_RATE="0.00"
else
    AUTO_FIX_RATE="0.00"
fi

# test_pass_rate: test passes / total test runs (higher = better test health)
TEST_TOTAL=$((TEST_PASSES + TEST_FAILS))
if [ "$TEST_TOTAL" -gt 0 ]; then
    TEST_PASS_RATE=$(awk "BEGIN {printf \"%.2f\", $TEST_PASSES / $TEST_TOTAL}") || TEST_PASS_RATE="N/A"
else
    TEST_PASS_RATE="N/A"
fi

# lint_pass_rate: lint passes / total lint runs (higher = cleaner code)
LINT_TOTAL=$((LINT_PASSES + LINT_FAILS))
if [ "$LINT_TOTAL" -gt 0 ]; then
    LINT_PASS_RATE=$(awk "BEGIN {printf \"%.2f\", $LINT_PASSES / $LINT_TOTAL}") || LINT_PASS_RATE="N/A"
else
    LINT_PASS_RATE="N/A"
fi

# delegation_count: Task tool invocations (proxy for subagent delegation)
DELEGATIONS=$(grep -c '"tool":"Task"' "$SESSION_FILE" 2>/dev/null) || DELEGATIONS=0

SUMMARY_JSON=$(jq -n \
    --arg project "${PROJECT:-unknown}" \
    --arg session "${SESSION_ID:-unknown}" \
    --arg ts "${TIMESTAMP:-unknown}" \
    --argjson total "${TOTAL:-0}" \
    --argjson ok "${SUCCESSES:-0}" \
    --argjson fail "${FAILURES:-0}" \
    --argjson corrections "${CORRECTIONS:-0}" \
    --argjson test_writes "${TEST_WRITES:-0}" \
    --argjson cascades "${CASCADES:-0}" \
    --argjson edits "${EDITS:-0}" \
    --argjson test_passes "${TEST_PASSES:-0}" \
    --argjson test_fails "${TEST_FAILS:-0}" \
    --argjson lint_passes "${LINT_PASSES:-0}" \
    --argjson lint_fails "${LINT_FAILS:-0}" \
    --arg correction_rate "${CORRECTION_RATE:-0.00}" \
    --arg auto_fix_rate "${AUTO_FIX_RATE:-0.00}" \
    --arg test_write_rate "${TEST_WRITE_RATE:-0.00}" \
    --arg cascade_rate "${CASCADE_RATE:-0.00}" \
    --arg test_pass_rate "${TEST_PASS_RATE:-N/A}" \
    --arg lint_pass_rate "${LINT_PASS_RATE:-N/A}" \
    --argjson delegations "${DELEGATIONS:-0}" \
    --arg tools "${TOOLS:-unknown}" \
    --arg files "${FILES:-}" \
    --argjson confidence 0.5 \
    --argjson transferable false \
    --argjson recall_count 0 \
    '{project: $project, session: $session, timestamp: $ts, events: $total, successes: $ok, failures: $fail, corrections: $corrections, test_writes: $test_writes, cascades: $cascades, edits: $edits, test_passes: $test_passes, test_fails: $test_fails, lint_passes: $lint_passes, lint_fails: $lint_fails, flywheel: {correction_rate: $correction_rate, auto_fix_rate: $auto_fix_rate, test_write_rate: $test_write_rate, cascade_rate: $cascade_rate, test_pass_rate: $test_pass_rate, lint_pass_rate: $lint_pass_rate, delegations: $delegations}, tools: $tools, files: $files, confidence: $confidence, transferable: $transferable, recall_count: $recall_count}' 2>/dev/null) || SUMMARY_JSON="{}"

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
    # Wave 4: store flywheel metrics as separate key for trending
    if [ "$STORED_L1" = true ]; then
        FW_KEY="flywheel:${PROJECT}:${SESSION_ID}"
        FW_VALUE=$(jq -n -c \
            --arg project "$PROJECT" \
            --arg session "$SESSION_ID" \
            --arg ts "$TIMESTAMP" \
            --arg correction_rate "$CORRECTION_RATE" \
            --arg auto_fix_rate "$AUTO_FIX_RATE" \
            --arg test_write_rate "$TEST_WRITE_RATE" \
            --arg cascade_rate "$CASCADE_RATE" \
            --arg test_pass_rate "$TEST_PASS_RATE" \
            --arg lint_pass_rate "$LINT_PASS_RATE" \
            --argjson test_passes "${TEST_PASSES:-0}" \
            --argjson test_fails "${TEST_FAILS:-0}" \
            --argjson lint_passes "${LINT_PASSES:-0}" \
            --argjson lint_fails "${LINT_FAILS:-0}" \
            --argjson delegations "${DELEGATIONS:-0}" \
            --argjson edits "${EDITS:-0}" \
            --argjson failures "${FAILURES:-0}" \
            '{project: $project, session: $session, timestamp: $ts, correction_rate: $correction_rate, auto_fix_rate: $auto_fix_rate, test_write_rate: $test_write_rate, cascade_rate: $cascade_rate, test_pass_rate: $test_pass_rate, lint_pass_rate: $lint_pass_rate, test_passes: $test_passes, test_fails: $test_fails, lint_passes: $lint_passes, lint_fails: $lint_fails, delegations: $delegations, edits: $edits, failures: $failures}' 2>/dev/null) || FW_VALUE="{}"
        timeout 5 $CF memory store -k "$FW_KEY" -v "$FW_VALUE" --namespace metrics --tags "project:$PROJECT,type:flywheel" 2>/dev/null || true
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
        echo "- Corrections: $CORRECTIONS | Test writes: $TEST_WRITES | Cascades: $CASCADES"
        echo "- Tests: $TEST_PASSES pass, $TEST_FAILS fail (rate=$TEST_PASS_RATE) | Lint: $LINT_PASSES pass, $LINT_FAILS fail (rate=$LINT_PASS_RATE)"
        echo "- Flywheel: corr=$CORRECTION_RATE fix=$AUTO_FIX_RATE test=$TEST_WRITE_RATE casc=$CASCADE_RATE deleg=$DELEGATIONS"
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
        echo "- Corrections: $CORRECTIONS | Test writes: $TEST_WRITES | Cascades: $CASCADES"
        echo "- Tests: $TEST_PASSES pass, $TEST_FAILS fail (rate=$TEST_PASS_RATE) | Lint: $LINT_PASSES pass, $LINT_FAILS fail (rate=$LINT_PASS_RATE)"
        echo "- Flywheel: corr=$CORRECTION_RATE fix=$AUTO_FIX_RATE test=$TEST_WRITE_RATE casc=$CASCADE_RATE deleg=$DELEGATIONS"
        echo "- Tools: $TOOLS"
        if [ -n "$FILES" ]; then echo "- Files: $FILES"; fi
    } >> "$LAYER0_DIR/sessions.md"
fi

# Self-learning loop: detect system file changes for next session
if [ -n "$LAYER0_DIR" ]; then
    DRIFT_FILES=$(git -C "$GIT_ROOT" diff --name-only HEAD~10..HEAD 2>/dev/null | grep -E '(skills/|agents/|hooks/|rules/|commands/|CLAUDE\.md|settings\.json|deploy\.sh)' | tr '\n' ',' || true)
    if [ -n "$DRIFT_FILES" ]; then
        echo "$(date +%Y-%m-%d) $DRIFT_FILES" > "$LAYER0_DIR/.needs-backprop"
    fi
fi

# Self-learning loop: auto-generate minimal handoff if not written today
if [ -n "$LAYER0_DIR" ]; then
    HANDOFF="$LAYER0_DIR/session-handoff.md"
    TODAY=$(date +%Y-%m-%d)
    if [ -f "$HANDOFF" ] && ! grep -q "## $TODAY" "$HANDOFF" 2>/dev/null; then
        COMMITS=$(git -C "$GIT_ROOT" log --oneline --since="8 hours ago" 2>/dev/null | head -5) || COMMITS=""
        BRANCH=$(git -C "$GIT_ROOT" branch --show-current 2>/dev/null) || BRANCH="unknown"
        if [ -n "$COMMITS" ]; then
            {
                echo ""
                echo "## $TODAY — auto-captured (session-end hook)"
                echo ""
                echo "**Accomplished:**"
                echo "$COMMITS" | while read -r line; do echo "- $line"; done
                echo ""
                echo "**State:**"
                echo "- Branch: $BRANCH"
                echo "- Events: $TOTAL ($SUCCESSES ok, $FAILURES fail, $CORRECTIONS corrections, $CASCADES cascades)"
                echo "- Tests: $TEST_PASSES pass, $TEST_FAILS fail (rate=$TEST_PASS_RATE) | Lint: $LINT_PASSES pass, $LINT_FAILS fail (rate=$LINT_PASS_RATE)"
                echo "- Flywheel: corr=$CORRECTION_RATE fix=$AUTO_FIX_RATE test=$TEST_WRITE_RATE casc=$CASCADE_RATE deleg=$DELEGATIONS"
                echo ""
                echo "**Next:**"
                echo "- (auto-generated — run /session-handoff for full close)"
            } >> "$HANDOFF"
        fi
    fi
fi

# Clean up temp file
rm -f "$SESSION_FILE"

echo '{"continue": true}'
