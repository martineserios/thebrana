#!/usr/bin/env bash
# No strict mode — hooks must always return valid JSON.

# Brana SessionEnd hook — orchestrator.
# Responds immediately, forks background processing to 3 sub-scripts:
#   session-end-metrics.sh  → compute flywheel metrics from JSONL log
#   session-end-persist.sh  → store to ruflo (L1) + auto-memory (L0)
#   session-end-drift.sh    → sync-state push + spec graph + decisions log
#
# Input:  stdin JSON (session_id, cwd, hook_event_name, matcher)
# Output: stdout JSON with continue: true

cd /tmp 2>/dev/null || true

INPUT=$(cat) || true
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null) || true
CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null) || true

if [ -z "${SESSION_ID:-}" ] || [ -z "${CWD:-}" ]; then
    echo '{"continue": true}'
    exit 0
fi

# Respond immediately — all processing in background
echo '{"continue": true}'

(
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "${SCRIPT_DIR}/lib/resolve-brana.sh"
    BRANA_CLI="$BRANA"

    GIT_ROOT=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null || echo "$CWD")
    export GIT_ROOT
    PROJECT=$(basename "$GIT_ROOT")
    SESSION_FILE="/tmp/brana-session-${SESSION_ID}.jsonl"
    TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null) || TIMESTAMP="unknown"

    # If no events accumulated, nothing to process
    if [ ! -f "$SESSION_FILE" ] || [ ! -s "$SESSION_FILE" ]; then
        rm -f "$SESSION_FILE"
        exit 0
    fi

    # ── Phase 1: Compute metrics ──────────────────────────────
    METRICS_ENV_FILE=$(mktemp /tmp/brana-metrics-XXXXXX.env)
    SESSION_FILE="$SESSION_FILE" \
    BRANA_CLI="$BRANA_CLI" \
    METRICS_ENV_FILE="$METRICS_ENV_FILE" \
    PROJECT_FILTER="$PROJECT" \
        bash "${SCRIPT_DIR}/session-end-metrics.sh" 2>/dev/null || true

    # Load computed metrics into this shell
    [ -f "$METRICS_ENV_FILE" ] && source "$METRICS_ENV_FILE" 2>/dev/null || true
    rm -f "$METRICS_ENV_FILE"

    # Defaults if metrics script failed
    TOTAL="${TOTAL:-0}"; SUCCESSES="${SUCCESSES:-0}"; FAILURES="${FAILURES:-0}"
    CORRECTIONS="${CORRECTIONS:-0}"; TEST_WRITES="${TEST_WRITES:-0}"
    CASCADES="${CASCADES:-0}"; PR_CREATES="${PR_CREATES:-0}"
    TEST_PASSES="${TEST_PASSES:-0}"; TEST_FAILS="${TEST_FAILS:-0}"
    LINT_PASSES="${LINT_PASSES:-0}"; LINT_FAILS="${LINT_FAILS:-0}"
    EDITS="${EDITS:-0}"; DELEGATIONS="${DELEGATIONS:-0}"
    TOOLS="${TOOLS:-unknown}"; FILES="${FILES:-}"
    CORRECTION_RATE="${CORRECTION_RATE:-0.00}"; AUTO_FIX_RATE="${AUTO_FIX_RATE:-0.00}"
    TEST_WRITE_RATE="${TEST_WRITE_RATE:-0.00}"; CASCADE_RATE="${CASCADE_RATE:-0.00}"
    TEST_PASS_RATE="${TEST_PASS_RATE:-N/A}"; LINT_PASS_RATE="${LINT_PASS_RATE:-N/A}"

    # Build summary JSON for ruflo storage
    SUMMARY_JSON=$(jq -n \
        --arg project "${PROJECT}" --arg session "${SESSION_ID}" --arg ts "${TIMESTAMP}" \
        --argjson total "${TOTAL}" --argjson ok "${SUCCESSES}" --argjson fail "${FAILURES}" \
        --argjson corrections "${CORRECTIONS}" --argjson test_writes "${TEST_WRITES}" \
        --argjson cascades "${CASCADES}" --argjson edits "${EDITS}" \
        --argjson test_passes "${TEST_PASSES}" --argjson test_fails "${TEST_FAILS}" \
        --argjson lint_passes "${LINT_PASSES}" --argjson lint_fails "${LINT_FAILS}" \
        --arg correction_rate "${CORRECTION_RATE}" --arg auto_fix_rate "${AUTO_FIX_RATE}" \
        --arg test_write_rate "${TEST_WRITE_RATE}" --arg cascade_rate "${CASCADE_RATE}" \
        --arg test_pass_rate "${TEST_PASS_RATE}" --arg lint_pass_rate "${LINT_PASS_RATE}" \
        --argjson delegations "${DELEGATIONS}" --argjson pr_creates "${PR_CREATES}" \
        --arg tools "${TOOLS}" --arg files "${FILES}" \
        --argjson confidence 0.5 --argjson transferable false --argjson recall_count 0 \
        '{project:$project,session:$session,timestamp:$ts,events:$total,successes:$ok,
          failures:$fail,corrections:$corrections,test_writes:$test_writes,cascades:$cascades,
          pr_creates:$pr_creates,edits:$edits,test_passes:$test_passes,test_fails:$test_fails,
          lint_passes:$lint_passes,lint_fails:$lint_fails,
          flywheel:{correction_rate:$correction_rate,auto_fix_rate:$auto_fix_rate,
            test_write_rate:$test_write_rate,cascade_rate:$cascade_rate,
            test_pass_rate:$test_pass_rate,lint_pass_rate:$lint_pass_rate,
            delegations:$delegations,pr_creates:$pr_creates},
          tools:$tools,files:$files,confidence:$confidence,
          transferable:$transferable,recall_count:$recall_count}' 2>/dev/null) || SUMMARY_JSON="{}"

    # Resolve Layer 0 auto-memory dir
    LAYER0_DIR=""
    for projdir in "$HOME"/.claude/projects/*/; do
        if [ -d "${projdir}memory" ]; then
            if grep -qi "$PROJECT" "${projdir}memory/MEMORY.md" 2>/dev/null; then
                LAYER0_DIR="${projdir}memory"
                break
            fi
        fi
    done

    # ── Phase 2: Persist ──────────────────────────────────────
    export PROJECT SESSION_ID TIMESTAMP SESSION_FILE GIT_ROOT
    export TOTAL SUCCESSES FAILURES CORRECTIONS TEST_WRITES CASCADES PR_CREATES
    export TEST_PASSES TEST_FAILS LINT_PASSES LINT_FAILS EDITS DELEGATIONS
    export TOOLS FILES CORRECTION_RATE AUTO_FIX_RATE TEST_WRITE_RATE
    export CASCADE_RATE TEST_PASS_RATE LINT_PASS_RATE SUMMARY_JSON
    export LAYER0_DIR BRANA_CLI
    STORED_L1=false; export STORED_L1

    bash "${SCRIPT_DIR}/session-end-persist.sh" 2>/dev/null || true

    # ── Phase 3: Drift / sync ─────────────────────────────────
    SCRIPT_DIR="$SCRIPT_DIR" \
    GIT_ROOT="$GIT_ROOT" \
    BRANA_CLI="$BRANA_CLI" \
    CORRECTIONS="$CORRECTIONS" \
    TEST_WRITES="$TEST_WRITES" \
    CASCADES="$CASCADES" \
    EDITS="$EDITS" \
        bash "${SCRIPT_DIR}/session-end-drift.sh" 2>/dev/null || true

    # Clean up event log
    rm -f "$SESSION_FILE"
) &

disown 2>/dev/null || true
