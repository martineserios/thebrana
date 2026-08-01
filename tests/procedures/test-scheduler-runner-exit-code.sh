#!/usr/bin/env bash
# Regression test for scheduler runner exit-code propagation (t-2588).
#
# Pins the invariant that a wrapped job's non-zero exit becomes the runner's
# own exit status, so systemd records Result=exit-code and OnFailure fires.
# t-2588 was filed claiming the runner swallows exit codes; the diagnosis was
# an observation error (a Persistent-timer catch-up run overwrote the unit
# state minutes after the failed run — two runs, one query). The propagation
# was correct all along but untested; this test keeps it that way.
#
# Run: bash tests/procedures/test-scheduler-runner-exit-code.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
RUNNER="$REPO_ROOT/system/scheduler/brana-scheduler-runner.sh"

PASS=0
FAIL=0
TOTAL=0

assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    TOTAL=$((TOTAL + 1))
    if [ "$expected" = "$actual" ]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc (expected '$expected', got '$actual')"
        FAIL=$((FAIL + 1))
    fi
}

assert_log_contains() {
    local desc="$1" needle="$2" job="$3"
    TOTAL=$((TOTAL + 1))
    local logfile
    logfile=$(ls -t "$TESTHOME/.claude/scheduler/logs/$job"/*.log 2>/dev/null | head -1)
    if [ -n "$logfile" ] && grep -q "$needle" "$logfile"; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc (pattern '$needle' not in ${logfile:-<no log>})"
        FAIL=$((FAIL + 1))
    fi
}

# Sandbox HOME so the runner reads/writes only the fixture tree.
TESTHOME=$(mktemp -d)
trap 'rm -rf "$TESTHOME"' EXIT
mkdir -p "$TESTHOME/.claude/scheduler" "$TESTHOME/proj"

# captureOutput:false keeps the runner off cf-env/ruflo; maxRetries:0 keeps
# failing runs single-attempt (no backoff sleeps).
cat > "$TESTHOME/.claude/scheduler/scheduler.json" <<JSON
{
  "defaults": {"timeoutSeconds": 30, "maxRetries": 0, "logRetention": 5, "captureOutput": false},
  "jobs": {
    "fail-job": {"type": "command", "project": "$TESTHOME/proj", "command": "exit 7"},
    "ok-job":   {"type": "command", "project": "$TESTHOME/proj", "command": "true"}
  }
}
JSON

run_job() {
    local runner="$1" job="$2" rc=0
    HOME="$TESTHOME" bash "$runner" "$job" >/dev/null 2>&1 || rc=$?
    echo "$rc"
}

status_field() {
    local job="$1" field="$2"
    jq -r --arg j "$job" ".[\$j].$field" "$TESTHOME/.claude/scheduler/last-status.json"
}

echo "=== test-scheduler-runner-exit-code.sh ==="

# ── Test 1: failing job's exit code propagates to the runner ─────────────────
echo "Test 1: job exiting 7 makes the runner exit 7"
RC=$(run_job "$RUNNER" fail-job)
assert_eq "runner exit code is the job's" "7" "$RC"
assert_log_contains "log footer records FAILED" "FAILED (exit code: 7)" fail-job
assert_eq "last-status.json status is FAILED" "FAILED" "$(status_field fail-job status)"
assert_eq "last-status.json exit_code is 7" "7" "$(status_field fail-job exit_code)"

# ── Test 2: clean job exits 0 ────────────────────────────────────────────────
echo "Test 2: job exiting 0 makes the runner exit 0"
RC=$(run_job "$RUNNER" ok-job)
assert_eq "runner exit code is 0" "0" "$RC"
assert_log_contains "log footer records SUCCESS" "SUCCESS" ok-job
assert_eq "last-status.json status is SUCCESS" "SUCCESS" "$(status_field ok-job status)"

# ── Test 3: mutation sanity — a propagation-stripped runner is caught ────────
# Proves Test 1's assertion is load-bearing: if someone replaces the final
# `exit "$EXIT_CODE"` with a bare success exit (the bug t-2588 alleged), the
# runner reports 0 for a failing job and Test 1 would fail.
echo "Test 3: mutant runner without propagation would be caught"
MUTANT="$TESTHOME/runner-mutant.sh"
sed 's/^exit "\$EXIT_CODE"$/exit 0/' "$RUNNER" > "$MUTANT"
TOTAL=$((TOTAL + 1))
if grep -q '^exit 0$' "$MUTANT" && ! grep -q '^exit "\$EXIT_CODE"$' "$MUTANT"; then
    echo "  PASS: mutant generated (propagation line stripped)"
    PASS=$((PASS + 1))
else
    echo "  FAIL: mutation did not apply — runner's exit line changed shape?"
    FAIL=$((FAIL + 1))
fi
RC=$(run_job "$MUTANT" fail-job)
assert_eq "mutant swallows the failure (exits 0)" "0" "$RC"

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo "Results: $PASS/$TOTAL passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
