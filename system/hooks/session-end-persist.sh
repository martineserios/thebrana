#!/usr/bin/env bash
# session-end-persist.sh — Store session summary to ruflo (L1) + auto-memory (L0).
#
# Input (env vars — all required, defaults to empty/zero if unset):
#   PROJECT SESSION_ID TIMESTAMP SESSION_FILE
#   TOTAL SUCCESSES FAILURES CORRECTIONS TEST_WRITES CASCADES PR_CREATES
#   TEST_PASSES TEST_FAILS LINT_PASSES LINT_FAILS EDITS DELEGATIONS
#   CORRECTION_RATE AUTO_FIX_RATE TEST_WRITE_RATE CASCADE_RATE
#   TEST_PASS_RATE LINT_PASS_RATE SUMMARY_JSON TOOLS FILES
#   LAYER0_DIR         path to project auto-memory dir (may be empty)
#   STORED_L1          "true"|"false" — set externally if ruflo already stored
#   BRANA_CLI          path to brana binary (optional)
#   PATTERN_LEARNINGS  JSON array of learning strings → ~/.claude/memory/patterns.md
#   KNOWLEDGE_FINDINGS JSON array of knowledge strings → ~/.claude/memory/knowledge-staging.md
#
# Always exits 0 — storage failures are non-fatal.

# No strict mode — must not fail on missing vars
set +e

PROJECT="${PROJECT:-unknown}"
SESSION_ID="${SESSION_ID:-unknown}"
TIMESTAMP="${TIMESTAMP:-unknown}"
SESSION_FILE="${SESSION_FILE:-}"
TOTAL="${TOTAL:-0}"; SUCCESSES="${SUCCESSES:-0}"; FAILURES="${FAILURES:-0}"
CORRECTIONS="${CORRECTIONS:-0}"; TEST_WRITES="${TEST_WRITES:-0}"
CASCADES="${CASCADES:-0}"; PR_CREATES="${PR_CREATES:-0}"
TEST_PASSES="${TEST_PASSES:-0}"; TEST_FAILS="${TEST_FAILS:-0}"
LINT_PASSES="${LINT_PASSES:-0}"; LINT_FAILS="${LINT_FAILS:-0}"
EDITS="${EDITS:-0}"; DELEGATIONS="${DELEGATIONS:-0}"
CORRECTION_RATE="${CORRECTION_RATE:-0.00}"
AUTO_FIX_RATE="${AUTO_FIX_RATE:-0.00}"
TEST_WRITE_RATE="${TEST_WRITE_RATE:-0.00}"
CASCADE_RATE="${CASCADE_RATE:-0.00}"
TEST_PASS_RATE="${TEST_PASS_RATE:-N/A}"
LINT_PASS_RATE="${LINT_PASS_RATE:-N/A}"
SUMMARY_JSON="${SUMMARY_JSON:-{}}"
TOOLS="${TOOLS:-unknown}"; FILES="${FILES:-}"
LAYER0_DIR="${LAYER0_DIR:-}"
STORED_L1="${STORED_L1:-false}"
BRANA_CLI="${BRANA_CLI:-}"
PATTERN_LEARNINGS="${PATTERN_LEARNINGS:-[]}"
KNOWLEDGE_FINDINGS="${KNOWLEDGE_FINDINGS:-[]}"

# ── Layer 1: ruflo store ──────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CF_WARNING=""

if [ "$STORED_L1" != "true" ]; then
    # Source cf-env.sh to get $CF
    # HOME-based config takes priority over bundled lib/ (enables test isolation via fake HOME)
    if [ -f "$HOME/.claude/scripts/cf-env.sh" ]; then
        source "$HOME/.claude/scripts/cf-env.sh" 2>/dev/null || true
    elif [ -f "$SCRIPT_DIR/lib/cf-env.sh" ]; then
        source "$SCRIPT_DIR/lib/cf-env.sh" 2>/dev/null || true
    fi

    if [ -n "${CF:-}" ]; then
        KEY="session:${PROJECT}:${SESSION_ID}"
        VALUE=$(echo "$SUMMARY_JSON" | jq -c '.' 2>/dev/null) || VALUE="$SUMMARY_JSON"
        if [ "$FAILURES" -gt 0 ]; then OUTCOME="mixed"; else OUTCOME="success"; fi
        TAGS="client:$PROJECT,type:session-summary,outcome:$OUTCOME,confidence:quarantine"

        CF_ERR=$(cd "$HOME" && timeout 5 $CF memory store -k "$KEY" -v "$VALUE" \
            --namespace session --tags "$TAGS" 2>&1) || true
        CF_EXIT=$?
        if [ $CF_EXIT -eq 0 ]; then
            STORED_L1=true
        elif [ $CF_EXIT -eq 124 ]; then
            CF_WARNING="Session summary store timed out (>5s). Try: ruflo memory store -k '$KEY'"
        else
            CF_WARNING="Session summary store failed (exit $CF_EXIT). Try: ruflo memory store -k '$KEY'"
        fi

        # Wave 4: flywheel metrics as separate key
        if [ "$STORED_L1" = "true" ]; then
            FW_KEY="flywheel:${PROJECT}:${SESSION_ID}"
            FW_VALUE=$(jq -n -c \
                --arg project "$PROJECT" --arg session "$SESSION_ID" --arg ts "$TIMESTAMP" \
                --arg correction_rate "$CORRECTION_RATE" --arg auto_fix_rate "$AUTO_FIX_RATE" \
                --arg test_write_rate "$TEST_WRITE_RATE" --arg cascade_rate "$CASCADE_RATE" \
                --arg test_pass_rate "$TEST_PASS_RATE" --arg lint_pass_rate "$LINT_PASS_RATE" \
                --argjson test_passes "${TEST_PASSES}" --argjson test_fails "${TEST_FAILS}" \
                --argjson lint_passes "${LINT_PASSES}" --argjson lint_fails "${LINT_FAILS}" \
                --argjson delegations "${DELEGATIONS}" --argjson edits "${EDITS}" \
                --argjson failures "${FAILURES}" \
                '{project:$project,session:$session,timestamp:$ts,
                  correction_rate:$correction_rate,auto_fix_rate:$auto_fix_rate,
                  test_write_rate:$test_write_rate,cascade_rate:$cascade_rate,
                  test_pass_rate:$test_pass_rate,lint_pass_rate:$lint_pass_rate,
                  test_passes:$test_passes,test_fails:$test_fails,
                  lint_passes:$lint_passes,lint_fails:$lint_fails,
                  delegations:$delegations,edits:$edits,failures:$failures}' 2>/dev/null) || FW_VALUE="{}"
            (cd "$HOME" && timeout 5 $CF memory store -k "$FW_KEY" -v "$FW_VALUE" \
                --namespace metrics --tags "client:$PROJECT,type:flywheel" 2>/dev/null) || true
        fi
    else
        CF_WARNING="ruflo not found. Session summary not persisted."
    fi

    # Log CF warning to session file for diagnostics
    if [ -n "$CF_WARNING" ] && [ -n "$SESSION_FILE" ] && [ -f "$SESSION_FILE" ]; then
        jq -n -c \
            --argjson ts "$(date +%s 2>/dev/null || echo 0)" \
            --arg tool "session-end" --arg outcome "cf-warning" --arg detail "$CF_WARNING" \
            '{ts:$ts,tool:$tool,outcome:$outcome,detail:$detail}' \
            >> "$SESSION_FILE" 2>/dev/null || true
    fi
fi

# ── Layer 0: auto-memory write ────────────────────────────────

if [ -n "$LAYER0_DIR" ]; then
    # sessions.md (always)
    {
        echo ""
        echo "### Session $SESSION_ID ($TIMESTAMP)"
        echo "- Events: $TOTAL ($SUCCESSES ok, $FAILURES fail)"
        echo "- Corrections: $CORRECTIONS | Test writes: $TEST_WRITES | Cascades: $CASCADES | PR creates: $PR_CREATES"
        echo "- Tests: $TEST_PASSES pass, $TEST_FAILS fail (rate=$TEST_PASS_RATE) | Lint: $LINT_PASSES pass, $LINT_FAILS fail (rate=$LINT_PASS_RATE)"
        echo "- Flywheel: corr=$CORRECTION_RATE fix=$AUTO_FIX_RATE test=$TEST_WRITE_RATE casc=$CASCADE_RATE deleg=$DELEGATIONS prs=$PR_CREATES"
        echo "- Tools: $TOOLS"
        [ -n "$FILES" ] && echo "- Files: $FILES"
    } >> "$LAYER0_DIR/sessions.md" 2>/dev/null || true
fi

# ── Classify-then-route: patterns.md + knowledge-staging.md ──
# Routes PATTERN_LEARNINGS and KNOWLEDGE_FINDINGS to flat taxonomy files.
# Runs regardless of STORED_L1 — flat files are git-durable fallback.

MEMORY_DIR="$HOME/.claude/memory"

_slugify() {
    echo "$1" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/^-//;s/-$//' | cut -c1-60
}

_date_today() {
    date +%Y-%m-%d 2>/dev/null || echo "$TIMESTAMP"
}

if command -v jq >/dev/null 2>&1; then
    TODAY=$(_date_today)

    # Patterns → ~/.claude/memory/patterns.md
    PATTERN_COUNT=$(echo "$PATTERN_LEARNINGS" | jq 'length' 2>/dev/null) || PATTERN_COUNT=0
    if [ "${PATTERN_COUNT:-0}" -gt 0 ]; then
        PATTERNS_FILE="$MEMORY_DIR/patterns.md"
        if [ ! -f "$PATTERNS_FILE" ]; then
            mkdir -p "$MEMORY_DIR" 2>/dev/null || true
            printf '# Pattern Store\n\n<!-- cap: 50 | warn-at: 40 | auto-pruned: oldest quarantine first -->\n' \
                > "$PATTERNS_FILE" 2>/dev/null || true
        fi
        while IFS= read -r learning; do
            [ -z "$learning" ] && continue
            slug=$(_slugify "$learning")
            if ! grep -q "^## $slug" "$PATTERNS_FILE" 2>/dev/null; then
                {
                    echo ""
                    echo "## $slug"
                    echo ""
                    echo "$learning"
                    echo "**Confidence:** quarantine"
                    echo "**Source:** session-end auto-capture $SESSION_ID"
                    echo "**Added:** $TODAY"
                } >> "$PATTERNS_FILE" 2>/dev/null || true
            fi
        done < <(echo "$PATTERN_LEARNINGS" | jq -r '.[]' 2>/dev/null)
    fi

    # Knowledge → ~/.claude/memory/knowledge-staging.md
    KNOWLEDGE_COUNT=$(echo "$KNOWLEDGE_FINDINGS" | jq 'length' 2>/dev/null) || KNOWLEDGE_COUNT=0
    if [ "${KNOWLEDGE_COUNT:-0}" -gt 0 ]; then
        KNOWLEDGE_FILE="$MEMORY_DIR/knowledge-staging.md"
        if [ ! -f "$KNOWLEDGE_FILE" ]; then
            mkdir -p "$MEMORY_DIR" 2>/dev/null || true
            printf '# Knowledge Staging\n\n<!-- cap: 30 | warn-at: 20 | stale-after: 30 days -->\n' \
                > "$KNOWLEDGE_FILE" 2>/dev/null || true
        fi
        while IFS= read -r finding; do
            [ -z "$finding" ] && continue
            slug=$(_slugify "$finding")
            if ! grep -q "^## $slug" "$KNOWLEDGE_FILE" 2>/dev/null; then
                {
                    echo ""
                    echo "## $slug"
                    echo ""
                    echo "**Claim:** $finding"
                    echo "**Source:** session-end auto-capture $SESSION_ID"
                    echo "**Confidence:** medium"
                    echo "**Added:** $TODAY"
                } >> "$KNOWLEDGE_FILE" 2>/dev/null || true
            fi
        done < <(echo "$KNOWLEDGE_FINDINGS" | jq -r '.[]' 2>/dev/null)
    fi
fi

# ── Session state via CLI ─────────────────────────────────────

if [ -n "$BRANA_CLI" ] && [ -x "$BRANA_CLI" ]; then
    # cd to GIT_ROOT before calling brana — session-end.sh does `cd /tmp` and
    # brana session path/write resolve the project from CWD, not from GIT_ROOT.
    # Without this, both commands target -tmp- instead of the real project.
    SESSION_STATE_PATH=$(cd "${GIT_ROOT:-/tmp}" && "$BRANA_CLI" session path 2>/dev/null) || SESSION_STATE_PATH=""
    ALREADY_WRITTEN=false
    if [ -n "$SESSION_STATE_PATH" ] && [ -f "$SESSION_STATE_PATH" ]; then
        WRITTEN_AT=$(jq -r '.written_at // ""' "$SESSION_STATE_PATH" 2>/dev/null) || WRITTEN_AT=""
        TODAY=$(date +%Y-%m-%d)
        echo "$WRITTEN_AT" | grep -q "$TODAY" 2>/dev/null && ALREADY_WRITTEN=true
    fi

    if [ "$ALREADY_WRITTEN" = "true" ] && [ -n "$SESSION_STATE_PATH" ] && command -v jq &>/dev/null; then
        METRICS_PATCH=$(jq -n -c \
            --argjson events "${TOTAL}" --argjson corrections "${CORRECTIONS}" \
            --argjson test_writes "${TEST_WRITES}" \
            --arg correction_rate "${CORRECTION_RATE}" \
            --arg test_write_rate "${TEST_WRITE_RATE}" \
            --arg cascade_rate "${CASCADE_RATE}" \
            --argjson delegations "${DELEGATIONS}" \
            '{events:$events,corrections:$corrections,test_writes:$test_writes,
              correction_rate:($correction_rate|tonumber),
              test_write_rate:($test_write_rate|tonumber),
              cascade_rate:($cascade_rate|tonumber),
              delegation_count:$delegations}' 2>/dev/null) || METRICS_PATCH=""
        if [ -n "$METRICS_PATCH" ]; then
            jq --argjson m "$METRICS_PATCH" '.metrics = $m' "$SESSION_STATE_PATH" \
                > "${SESSION_STATE_PATH}.tmp" 2>/dev/null && \
                mv "${SESSION_STATE_PATH}.tmp" "$SESSION_STATE_PATH" 2>/dev/null || true
        fi
    fi

    if [ "$ALREADY_WRITTEN" = "false" ]; then
        MINIMAL_JSON=$(jq -n -c \
            --argjson version 1 \
            --arg written_at "${TIMESTAMP}" \
            --arg branch "$(git -C "${GIT_ROOT:-/tmp}" branch --show-current 2>/dev/null || echo '')" \
            --arg session_label "auto-captured (session-end hook)" \
            --argjson events "${TOTAL}" --argjson corrections "${CORRECTIONS}" \
            --argjson test_writes "${TEST_WRITES}" \
            --arg correction_rate "${CORRECTION_RATE}" \
            --arg test_write_rate "${TEST_WRITE_RATE}" \
            --arg cascade_rate "${CASCADE_RATE}" \
            --argjson delegations "${DELEGATIONS}" \
            '{version:$version,written_at:$written_at,
              branch:(if $branch=="" then null else $branch end),
              session_label:$session_label,
              metrics:{events:$events,corrections:$corrections,test_writes:$test_writes,
                correction_rate:($correction_rate|tonumber),
                test_write_rate:($test_write_rate|tonumber),
                cascade_rate:($cascade_rate|tonumber),
                delegation_count:$delegations}}' 2>/dev/null) || MINIMAL_JSON=""
        if [ -n "$MINIMAL_JSON" ]; then
            TMPFILE="/tmp/session-end-minimal-$$.json"
            echo "$MINIMAL_JSON" > "$TMPFILE"
            (cd "${GIT_ROOT:-/tmp}" && "$BRANA_CLI" session write --file "$TMPFILE" 2>/dev/null) || true
            rm -f "$TMPFILE"
        else
            (cd "${GIT_ROOT:-/tmp}" && "$BRANA_CLI" session write --minimal 2>/dev/null) || true
        fi
    fi
fi

exit 0
