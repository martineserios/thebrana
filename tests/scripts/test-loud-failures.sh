#!/usr/bin/env bash
# Tests for the loud-failure fixes (t-1938).
#
# The architecture review's dominant finding: polite, silent failure.
# Three silences get voices here:
#   1. session-end-persist.sh swallowed ruflo write failures (set +e, || true)
#   2. validate.sh Check 48 reported hooks parity gaps as WARN (and its parser
#      emitted 14 false positives from a trailing-quote bug)
#   3. scheduler job failures were visible only as an emoji in brana ops status
#
# Tests:
#   T1: session-end-persist with failing CF → persist-failures.log entry
#   T2: session-start surfaces planted persist-failures.log, then rotates it
#   T3: session-start surfaces failing scheduler job from last-status.json
#   T4: Check 48 uses fail (not warn) — source contract
#   T5: Check 48 passes clean on the current repo (parser fixed, stale rows gone)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
FAKE_HOME="$(mktemp -d /tmp/t1938-home-XXXX)"

trap 'rm -rf "$FAKE_HOME"' EXIT

PASS=0; FAIL=0; TOTAL=0

assert_contains() {
    local desc="$1" needle="$2" haystack="$3"
    TOTAL=$((TOTAL+1))
    if [[ "$haystack" == *"$needle"* ]]; then
        PASS=$((PASS+1)); echo "  PASS: $desc"
    else
        FAIL=$((FAIL+1)); echo "  FAIL: $desc — '$needle' not in: ${haystack:0:200}"
    fi
}

echo "=== loud failures (t-1938) ==="

# T1 — persist failure is logged, not swallowed
mkdir -p "$FAKE_HOME/.claude/scripts" "$FAKE_HOME/.claude/run-state"
cat > "$FAKE_HOME/.claude/scripts/cf-env.sh" <<'EOF'
CF="/bin/false"
export CF
cf_run() { /bin/false; }
EOF
HOME="$FAKE_HOME" PROJECT=testproj SESSION_ID=s1 TIMESTAMP=2026-06-10T00:00:00Z \
    STORED_L1=false SUMMARY_JSON='{}' \
    bash "$REPO_ROOT/system/hooks/session-end-persist.sh" > /dev/null 2>&1
PFLOG="$FAKE_HOME/.claude/run-state/persist-failures.log"
TOTAL=$((TOTAL+1))
if [ -s "$PFLOG" ] && grep -q "testproj" "$PFLOG"; then
    PASS=$((PASS+1)); echo "  PASS: T1: failed ruflo write logged to persist-failures.log"
else
    FAIL=$((FAIL+1)); echo "  FAIL: T1: no entry in $PFLOG"
fi

# T2 — session-start surfaces and rotates the failure log
# (uses real session-start.sh with BRANA_RUN_STATE_DIR override for isolation)
RS_DIR="$FAKE_HOME/run-state-2"
mkdir -p "$RS_DIR"
echo "2026-06-10T00:00:00Z testproj L1 store failed (exit 1)" > "$RS_DIR/persist-failures.log"
OUT=$(BRANA_RUN_STATE_DIR="$RS_DIR" BRANA_SCHED_STATUS=/nonexistent timeout 60 bash -c \
    "echo '{\"session_id\":\"t1938-test\",\"cwd\":\"$REPO_ROOT\",\"hook_event_name\":\"SessionStart\",\"matcher\":\"startup\"}' | bash '$REPO_ROOT/system/hooks/session-start.sh'" 2>/dev/null | head -1)
assert_contains "T2: persist failure surfaced at session start" "Memory persist" "$OUT"
TOTAL=$((TOTAL+1))
if [ ! -s "$RS_DIR/persist-failures.log" ]; then
    PASS=$((PASS+1)); echo "  PASS: T2b: failure log rotated after surfacing"
else
    FAIL=$((FAIL+1)); echo "  FAIL: T2b: persist-failures.log still has content"
fi

# T3 — scheduler failure surfaced at session start
SCHED="$FAKE_HOME/last-status.json"
cat > "$SCHED" <<'EOF'
{"good-job": {"status": "SUCCESS", "exit_code": 0, "timestamp": "2026-06-10T08:00:00-03:00"},
 "broken-job": {"status": "FAILURE", "exit_code": 1, "timestamp": "2026-06-09T19:17:20-03:00"}}
EOF
OUT=$(BRANA_RUN_STATE_DIR="$RS_DIR" BRANA_SCHED_STATUS="$SCHED" timeout 60 bash -c \
    "echo '{\"session_id\":\"t1938-test2\",\"cwd\":\"$REPO_ROOT\",\"hook_event_name\":\"SessionStart\",\"matcher\":\"startup\"}' | bash '$REPO_ROOT/system/hooks/session-start.sh'" 2>/dev/null | head -1)
assert_contains "T3: failing scheduler job surfaced" "broken-job" "$OUT"

# T4 — Check 48 fails loudly (source contract)
TOTAL=$((TOTAL+1))
if grep -q 'fail "Check 48' "$REPO_ROOT/validate.sh" && ! grep -q 'warn "Check 48' "$REPO_ROOT/validate.sh"; then
    PASS=$((PASS+1)); echo "  PASS: T4: Check 48 promoted to fail"
else
    FAIL=$((FAIL+1)); echo "  FAIL: T4: Check 48 still warn (or fail missing)"
fi

# T5 — Check 48 clean on current repo (parser fixed: no trailing-quote ghosts)
OUT=$(cd "$REPO_ROOT" && bash validate.sh --check 48 < /dev/null 2>&1)
assert_contains "T5: Check 48 passes clean" "PASS" "$OUT"
TOTAL=$((TOTAL+1))
if [[ "$OUT" == *'.sh"'* ]]; then
    FAIL=$((FAIL+1)); echo "  FAIL: T5b: trailing-quote ghost names still present"
else
    PASS=$((PASS+1)); echo "  PASS: T5b: no trailing-quote parser ghosts"
fi

echo ""
echo "$PASS/$TOTAL passed"
[ "$FAIL" -eq 0 ] || exit 1
