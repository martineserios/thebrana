#!/usr/bin/env bash
# Tests for session-end sub-scripts (t-201 split).
# Verifies that session-end-metrics.sh, session-end-persist.sh,
# and session-end-drift.sh each work independently.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOKS_DIR="$SCRIPT_DIR/.."
PASS=0
FAIL=0
TOTAL=0
TMPDIR_ROOT=$(mktemp -d)
trap 'rm -rf "$TMPDIR_ROOT"' EXIT

# ── Helpers ──────────────────────────────────────────────────

assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    TOTAL=$((TOTAL + 1))
    if [ "$expected" = "$actual" ]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc"
        echo "    expected: [$expected]"
        echo "    got:      [$actual]"
        FAIL=$((FAIL + 1))
    fi
}

assert_contains() {
    local desc="$1" needle="$2" haystack="$3"
    TOTAL=$((TOTAL + 1))
    if echo "$haystack" | grep -qF "$needle"; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc"
        echo "    expected to contain: [$needle]"
        echo "    in: [$haystack]"
        FAIL=$((FAIL + 1))
    fi
}

assert_file_exists() {
    local desc="$1" path="$2"
    TOTAL=$((TOTAL + 1))
    if [ -f "$path" ] || [ -d "$path" ]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc — not found: $path"
        FAIL=$((FAIL + 1))
    fi
}

assert_exit_zero() {
    local desc="$1" code="$2"
    TOTAL=$((TOTAL + 1))
    if [ "$code" -eq 0 ]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc (exit $code)"
        FAIL=$((FAIL + 1))
    fi
}

# Write a JSONL fixture with N events of given type
make_session_file() {
    local path="$1"
    local ts=1000
    # 3 successes
    for i in 1 2 3; do
        printf '{"ts":%d,"tool":"Edit","outcome":"success","detail":"src/main.rs"}\n' $((ts + i)) >> "$path"
    done
    # 2 failures
    printf '{"ts":1010,"tool":"Bash","outcome":"failure","detail":"src/main.rs"}\n' >> "$path"
    printf '{"ts":1011,"tool":"Bash","outcome":"test-fail","detail":"tests/test.rs"}\n' >> "$path"
    # 1 correction
    printf '{"ts":1020,"tool":"Edit","outcome":"correction","detail":"src/main.rs"}\n' >> "$path"
    # 1 test-write
    printf '{"ts":1030,"tool":"Write","outcome":"test-write","detail":"tests/new_test.rs"}\n' >> "$path"
    # 1 test-pass
    printf '{"ts":1040,"tool":"Bash","outcome":"test-pass","detail":"tests/test.rs"}\n' >> "$path"
}

# ══════════════════════════════════════════════════════════════
echo "session-end-split Tests"
echo "========================"

# ──────────────────────────────────────────────────────────────
echo ""
echo "── session-end-metrics.sh ───────────────────────────────"
# ──────────────────────────────────────────────────────────────

# T1: given a JSONL event file, env file contains correct TOTAL and CORRECTIONS
T1_SESSION_FILE="$TMPDIR_ROOT/session-t1.jsonl"
T1_ENV_FILE="$TMPDIR_ROOT/metrics-t1.env"
make_session_file "$T1_SESSION_FILE"

EXIT_CODE=0
SESSION_FILE="$T1_SESSION_FILE" \
METRICS_ENV_FILE="$T1_ENV_FILE" \
BRANA_CLI="" \
    bash "$HOOKS_DIR/session-end-metrics.sh" 2>/dev/null || EXIT_CODE=$?

assert_exit_zero "T1: metrics script exits 0 with valid session file" "$EXIT_CODE"
assert_file_exists "T1: env file created" "$T1_ENV_FILE"

if [ -f "$T1_ENV_FILE" ]; then
    source "$T1_ENV_FILE" 2>/dev/null || true
    assert_eq "T1: TOTAL matches event count" "8" "${TOTAL:-0}"
    assert_eq "T1: CORRECTIONS counted" "1" "${CORRECTIONS:-0}"
    assert_eq "T1: FAILURES counted (failure + test-fail)" "2" "${FAILURES:-0}"
    assert_eq "T1: TEST_WRITES counted" "1" "${TEST_WRITES:-0}"
    assert_eq "T1: TEST_PASSES counted" "1" "${TEST_PASSES:-0}"
fi

# T2: empty session file → all metrics zero, exit 0
T2_SESSION_FILE="$TMPDIR_ROOT/session-t2.jsonl"
T2_ENV_FILE="$TMPDIR_ROOT/metrics-t2.env"
touch "$T2_SESSION_FILE"

EXIT_CODE=0
SESSION_FILE="$T2_SESSION_FILE" \
METRICS_ENV_FILE="$T2_ENV_FILE" \
BRANA_CLI="" \
    bash "$HOOKS_DIR/session-end-metrics.sh" 2>/dev/null || EXIT_CODE=$?

assert_exit_zero "T2: metrics script exits 0 with empty session file" "$EXIT_CODE"
if [ -f "$T2_ENV_FILE" ]; then
    unset TOTAL CORRECTIONS FAILURES 2>/dev/null || true
    source "$T2_ENV_FILE" 2>/dev/null || true
    assert_eq "T2: TOTAL is 0 for empty file" "0" "${TOTAL:-0}"
    assert_eq "T2: CORRECTIONS is 0 for empty file" "0" "${CORRECTIONS:-0}"
fi

# T3: missing SESSION_FILE → exits 0 with zero metrics (graceful degradation)
T3_ENV_FILE="$TMPDIR_ROOT/metrics-t3.env"

EXIT_CODE=0
SESSION_FILE="/tmp/nonexistent-session-$$-xyz.jsonl" \
METRICS_ENV_FILE="$T3_ENV_FILE" \
BRANA_CLI="" \
    bash "$HOOKS_DIR/session-end-metrics.sh" 2>/dev/null || EXIT_CODE=$?

assert_exit_zero "T3: missing session file exits 0 gracefully" "$EXIT_CODE"

# ──────────────────────────────────────────────────────────────
echo ""
echo "── session-end-persist.sh ───────────────────────────────"
# ──────────────────────────────────────────────────────────────

# T4: given metrics vars + LAYER0_DIR, always appends to sessions.md
# (sessions.md is unconditional; pending-learnings only when ruflo unavailable)
T4_LAYER0="$TMPDIR_ROOT/t4-layer0"
mkdir -p "$T4_LAYER0"
echo "# Auto Memory" > "$T4_LAYER0/MEMORY.md"

EXIT_CODE=0
PROJECT="test-proj" SESSION_ID="sess-t4" TIMESTAMP="2026-04-12T00:00:00Z" \
SESSION_FILE="$TMPDIR_ROOT/dummy.jsonl" \
TOTAL=9 SUCCESSES=3 FAILURES=2 CORRECTIONS=1 TEST_WRITES=1 CASCADES=0 \
PR_CREATES=0 TEST_PASSES=1 TEST_FAILS=1 LINT_PASSES=0 LINT_FAILS=0 \
EDITS=4 DELEGATIONS=0 \
CORRECTION_RATE="0.25" AUTO_FIX_RATE="0.50" TEST_WRITE_RATE="0.25" \
CASCADE_RATE="0.00" TEST_PASS_RATE="0.50" LINT_PASS_RATE="N/A" \
SUMMARY_JSON='{"project":"test-proj"}' \
TOOLS="Edit,Bash" FILES="src/main.rs" \
LAYER0_DIR="$T4_LAYER0" STORED_L1="false" \
BRANA_CLI="" \
    bash "$HOOKS_DIR/session-end-persist.sh" 2>/dev/null || EXIT_CODE=$?

assert_exit_zero "T4: persist script exits 0" "$EXIT_CODE"
assert_file_exists "T4: sessions.md written (unconditional path)" "$T4_LAYER0/sessions.md"
SESSIONS4=$(cat "$T4_LAYER0/sessions.md" 2>/dev/null || echo "")
assert_contains "T4: session ID in sessions.md" "sess-t4" "$SESSIONS4"
assert_contains "T4: flywheel metrics in sessions.md" "Flywheel:" "$SESSIONS4"

# T5: sessions.md written even when STORED_L1=true (ruflo-already-stored path)
T5_LAYER0="$TMPDIR_ROOT/t5-layer0"
mkdir -p "$T5_LAYER0"
echo "# Auto Memory" > "$T5_LAYER0/MEMORY.md"

EXIT_CODE=0
PROJECT="test-proj" SESSION_ID="sess-t5" TIMESTAMP="2026-04-12T00:00:00Z" \
SESSION_FILE="$TMPDIR_ROOT/dummy.jsonl" \
TOTAL=5 SUCCESSES=5 FAILURES=0 CORRECTIONS=0 TEST_WRITES=0 CASCADES=0 \
PR_CREATES=0 TEST_PASSES=0 TEST_FAILS=0 LINT_PASSES=0 LINT_FAILS=0 \
EDITS=2 DELEGATIONS=0 \
CORRECTION_RATE="0.00" AUTO_FIX_RATE="0.00" TEST_WRITE_RATE="0.00" \
CASCADE_RATE="0.00" TEST_PASS_RATE="N/A" LINT_PASS_RATE="N/A" \
SUMMARY_JSON='{}' TOOLS="Edit" FILES="" \
LAYER0_DIR="$T5_LAYER0" STORED_L1="true" \
BRANA_CLI="" \
    bash "$HOOKS_DIR/session-end-persist.sh" 2>/dev/null || EXIT_CODE=$?

assert_exit_zero "T5: persist exits 0 with STORED_L1=true" "$EXIT_CODE"
assert_file_exists "T5: sessions.md still written when STORED_L1=true" "$T5_LAYER0/sessions.md"
SESSIONS5=$(cat "$T5_LAYER0/sessions.md" 2>/dev/null || echo "")
assert_contains "T5: session ID in sessions.md" "sess-t5" "$SESSIONS5"

# T6: no LAYER0_DIR → persist exits 0 without crashing
T6_FAKE_HOME="$TMPDIR_ROOT/t6-fakehome"
mkdir -p "$T6_FAKE_HOME/.claude/scripts"
echo 'CF=""' > "$T6_FAKE_HOME/.claude/scripts/cf-env.sh"

EXIT_CODE=0
HOME="$T6_FAKE_HOME" \
PROJECT="test-proj" SESSION_ID="sess-t6" TIMESTAMP="2026-04-12T00:00:00Z" \
SESSION_FILE="$TMPDIR_ROOT/dummy.jsonl" \
TOTAL=0 SUCCESSES=0 FAILURES=0 CORRECTIONS=0 TEST_WRITES=0 CASCADES=0 \
PR_CREATES=0 TEST_PASSES=0 TEST_FAILS=0 LINT_PASSES=0 LINT_FAILS=0 \
EDITS=0 DELEGATIONS=0 \
CORRECTION_RATE="0.00" AUTO_FIX_RATE="0.00" TEST_WRITE_RATE="0.00" \
CASCADE_RATE="0.00" TEST_PASS_RATE="N/A" LINT_PASS_RATE="N/A" \
SUMMARY_JSON='{}' TOOLS="unknown" FILES="" \
LAYER0_DIR="" STORED_L1="false" \
BRANA_CLI="" \
    bash "$HOOKS_DIR/session-end-persist.sh" 2>/dev/null || EXIT_CODE=$?

assert_exit_zero "T6: persist exits 0 with empty LAYER0_DIR" "$EXIT_CODE"

# ──────────────────────────────────────────────────────────────
echo ""
echo "── session-end-drift.sh ─────────────────────────────────"
# ──────────────────────────────────────────────────────────────

# T7: no sync script, no brana CLI → exits 0 cleanly
EXIT_CODE=0
GIT_ROOT="$TMPDIR_ROOT" \
BRANA_CLI="" \
SCRIPT_DIR="$HOOKS_DIR" \
CORRECTIONS=0 TEST_WRITES=0 CASCADES=0 EDITS=0 \
    bash "$HOOKS_DIR/session-end-drift.sh" 2>/dev/null || EXIT_CODE=$?

assert_exit_zero "T7: drift script exits 0 when no sync/brana available" "$EXIT_CODE"

# T8: with a stub sync script that records calls, verify it gets invoked
T8_SYNC_CALLED="$TMPDIR_ROOT/sync-called"
T8_SCRIPT_DIR="$TMPDIR_ROOT/t8-scripts"
mkdir -p "$T8_SCRIPT_DIR/../scripts"
cat > "$T8_SCRIPT_DIR/../scripts/sync-state.sh" <<'SYNCEOF'
#!/usr/bin/env bash
echo "sync-push-called" >> "$TMPDIR_ROOT_T8/sync-called"
SYNCEOF
chmod +x "$T8_SCRIPT_DIR/../scripts/sync-state.sh"

# Create a real git repo for T8
T8_GIT="$TMPDIR_ROOT/t8-git"
git init -q "$T8_GIT" 2>/dev/null
git -C "$T8_GIT" commit --allow-empty -q -m "init" 2>/dev/null || true

EXIT_CODE=0
TMPDIR_ROOT_T8="$TMPDIR_ROOT" \
GIT_ROOT="$T8_GIT" \
BRANA_CLI="" \
SCRIPT_DIR="$T8_SCRIPT_DIR" \
CORRECTIONS=1 TEST_WRITES=0 CASCADES=0 EDITS=2 \
    bash "$HOOKS_DIR/session-end-drift.sh" 2>/dev/null || EXIT_CODE=$?

assert_exit_zero "T8: drift exits 0 with stub sync script" "$EXIT_CODE"
assert_file_exists "T8: sync-state push was called" "$T8_SYNC_CALLED"

# ──────────────────────────────────────────────────────────────
echo ""
echo "── session-end-persist.sh: CWD drift (t-1349) ──────────"
# ──────────────────────────────────────────────────────────────

# T9: persist.sh called from CWD=/tmp with GIT_ROOT=/real/project
#     must write session-state.json to the real project path, not to /tmp.
#     Root cause: session-end.sh does `cd /tmp`; without `cd "$GIT_ROOT"` before
#     `brana session path`, the CLI resolves -tmp- instead of the real project.

T9_PROJECT="$TMPDIR_ROOT/t9-project"
T9_FAKE_HOME="$TMPDIR_ROOT/t9-home"
T9_SESSION="$TMPDIR_ROOT/t9-session.jsonl"
BRANA_REAL="/home/martineserios/.local/bin/brana"

# Build a real git repo so brana session path resolves correctly from T9_PROJECT
mkdir -p "$T9_PROJECT"
git -C "$T9_PROJECT" init -q -b main 2>/dev/null
git -C "$T9_PROJECT" config user.email "test@test.com"
git -C "$T9_PROJECT" config user.name "Test"
echo "init" > "$T9_PROJECT/init.txt"
git -C "$T9_PROJECT" add -A && git -C "$T9_PROJECT" commit -q -m "init" 2>/dev/null

# Fake home: disable ruflo (CF="") so persist.sh falls through to brana session write
mkdir -p "$T9_FAKE_HOME/.claude/scripts"
echo 'CF=""' > "$T9_FAKE_HOME/.claude/scripts/cf-env.sh"

# Session events: 5 edits + 1 correction = correction_rate 0.20, events > 0
for i in 1 2 3 4 5; do
    printf '{"ts":%d,"tool":"Edit","outcome":"success","detail":"src/main.rs"}\n' $i >> "$T9_SESSION"
done
printf '{"ts":6,"tool":"Edit","outcome":"correction","detail":"src/main.rs"}\n' >> "$T9_SESSION"

# Find the correct session-state.json path (what brana would write when CWD=T9_PROJECT)
CORRECT_PATH=$(cd "$T9_PROJECT" && HOME="$T9_FAKE_HOME" "$BRANA_REAL" session path 2>/dev/null) || CORRECT_PATH=""

if [ -z "$CORRECT_PATH" ]; then
    TOTAL=$((TOTAL + 1))
    echo "  SKIP: T9: brana session path unavailable — skipping CWD drift test"
    PASS=$((PASS + 1))
else
    # Run persist.sh from CWD=/tmp (simulating session-end.sh's `cd /tmp`)
    # GIT_ROOT is set to the real project, but CWD is /tmp — the bug
    EXIT_CODE=0
    (
        cd /tmp
        HOME="$T9_FAKE_HOME" \
        GIT_ROOT="$T9_PROJECT" \
        PROJECT="t9-project" SESSION_ID="sess-t9" \
        TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        SESSION_FILE="$T9_SESSION" \
        TOTAL=6 SUCCESSES=5 FAILURES=0 CORRECTIONS=1 TEST_WRITES=0 CASCADES=0 \
        PR_CREATES=0 TEST_PASSES=0 TEST_FAILS=0 LINT_PASSES=0 LINT_FAILS=0 \
        EDITS=6 DELEGATIONS=0 \
        CORRECTION_RATE="0.17" AUTO_FIX_RATE="0.00" TEST_WRITE_RATE="0.00" \
        CASCADE_RATE="0.00" TEST_PASS_RATE="N/A" LINT_PASS_RATE="N/A" \
        SUMMARY_JSON='{}' TOOLS="Edit" FILES="src/main.rs" \
        LAYER0_DIR="" STORED_L1="false" \
        BRANA_CLI="$BRANA_REAL" \
            bash "$HOOKS_DIR/session-end-persist.sh" 2>/dev/null
    ) || EXIT_CODE=$?

    TOTAL=$((TOTAL + 1))
    if [ -f "$CORRECT_PATH" ]; then
        EVENTS_IN_STATE=$(jq -r '.metrics.events // 0' "$CORRECT_PATH" 2>/dev/null) || EVENTS_IN_STATE=0
        if [ "${EVENTS_IN_STATE}" -gt 0 ] 2>/dev/null; then
            echo "  PASS: T9: persist.sh with CWD=/tmp writes metrics to correct project path (events=$EVENTS_IN_STATE)"
            PASS=$((PASS + 1))
        else
            echo "  FAIL: T9: persist.sh with CWD=/tmp wrote to correct path but metrics.events=0 (expected >0)"
            echo "    correct_path: $CORRECT_PATH"
            echo "    content: $(jq -c '.metrics' "$CORRECT_PATH" 2>/dev/null || echo 'unreadable')"
            FAIL=$((FAIL + 1))
        fi
    else
        echo "  FAIL: T9: persist.sh did not write session-state.json to correct project path"
        echo "    expected: $CORRECT_PATH"
        echo "    (CWD=/tmp caused brana to write to wrong location — t-1349)"
        FAIL=$((FAIL + 1))
    fi
fi

# ──────────────────────────────────────────────────────────────
echo ""
echo "── Results ──────────────────────────────────────────────"
echo "  Total: $TOTAL  Pass: $PASS  Fail: $FAIL"
if [ "$FAIL" -gt 0 ]; then
    echo "FAILED"
    exit 1
else
    echo "PASSED"
    exit 0
fi
