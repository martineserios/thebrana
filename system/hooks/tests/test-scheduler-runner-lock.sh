#!/usr/bin/env bash
# Tests: system/scheduler/brana-scheduler-runner.sh — project-lock contention (t-2004).
# Catch-up runs (systemd Persistent=true firing at wake) must WAIT for a contended
# lock and then run — not silently SKIP. The wait is bounded by defaults.lockWaitSeconds.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNNER="$SCRIPT_DIR/../../scheduler/brana-scheduler-runner.sh"
PASS=0; FAIL=0; TOTAL=0
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

check() {
    local desc="$1" expected="$2" actual="$3"
    TOTAL=$((TOTAL + 1))
    if [ "$expected" = "$actual" ]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        echo "FAIL: $desc"
        echo "  expected: $expected"
        echo "  actual:   $actual"
    fi
}

if [ ! -f "$RUNNER" ]; then echo "FAIL: $RUNNER does not exist"; exit 1; fi

# Isolated HOME with a command-type job and a given lock wait window.
make_home() {
    local home="$1" lock_wait="$2"
    mkdir -p "$home/.claude/scheduler" "$home/project"
    jq -n --arg proj "$home/project" --argjson wait "$lock_wait" '{
        defaults: {timeoutSeconds: 30, captureOutput: false, lockWaitSeconds: $wait},
        jobs: {testjob: {type: "command", project: $proj, command: "echo ran"}}
    }' > "$home/.claude/scheduler/scheduler.json"
}

# Hold the project lock for N seconds from a background process.
hold_lock() {
    local home="$1" secs="$2"
    mkdir -p "$home/.claude/scheduler/locks"
    local lock="$home/.claude/scheduler/locks/project.lock"
    ( exec 9>"$lock"; flock 9; sleep "$secs" ) &
    HOLDER_PID=$!
    sleep 0.3  # let the holder acquire before the runner starts
}

status_of() { jq -r '.testjob.status // "MISSING"' "$1/.claude/scheduler/last-status.json" 2>/dev/null || echo MISSING; }

# ── 1. contended lock released within the wait window → job waits, then runs ──
H1="$TMPDIR/h1"; make_home "$H1" 10
hold_lock "$H1" 2
HOME="$H1" bash "$RUNNER" testjob >/dev/null 2>&1
rc=$?
check "contended lock: waits then runs (not SKIPPED)" "SUCCESS" "$(status_of "$H1")"
check "contended lock: exit 0 after waiting" "0" "$rc"
check "contended lock: job output logged" "1" "$(grep -rc '^ran$' "$H1/.claude/scheduler/logs/testjob/" 2>/dev/null | awk -F: '{s+=$2} END {print s+0}')"
wait "$HOLDER_PID" 2>/dev/null

# ── 2. lock held past the wait window → bounded: graceful SKIP, exit 0 ──
H2="$TMPDIR/h2"; make_home "$H2" 1
hold_lock "$H2" 5
HOME="$H2" bash "$RUNNER" testjob >/dev/null 2>&1
rc=$?
check "wait timeout: skips gracefully" "SKIPPED" "$(status_of "$H2")"
check "wait timeout: exit 0 (no systemd OnFailure)" "0" "$rc"
wait "$HOLDER_PID" 2>/dev/null

# ── 3. uncontended lock → runs immediately (no regression) ──
H3="$TMPDIR/h3"; make_home "$H3" 10
HOME="$H3" bash "$RUNNER" testjob >/dev/null 2>&1
rc=$?
check "uncontended: runs" "SUCCESS" "$(status_of "$H3")"
check "uncontended: exit 0" "0" "$rc"

echo ""
echo "test-scheduler-runner-lock: $PASS/$TOTAL passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
