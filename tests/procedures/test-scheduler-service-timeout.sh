#!/usr/bin/env bash
# Regression test: resolve_service_timeout() — the systemd TimeoutStartSec budget must
# bound the runner's DESIGNED maximum wall clock, lock wait included (t-2611).
#
# THE BUG. brana-scheduler-runner.sh waits up to lockWaitSeconds (default 600) on the
# per-project flock BEFORE the job's own `timeout` budget starts, and it does so inside
# the retry loop. The unit generator computed
#     TimeoutStartSec = (timeoutSeconds + 60) * (maxRetries + 1)
# which never accounted for that wait. With defaults that is 360s of systemd budget
# against 900s+ of designed runner wall clock, so the kill window sat exactly between
# the two configured waits: systemd killed the unit as "start operation timed out"
# before flock -w could return and let the runner log its graceful SKIPPED.
#
# THE HARM. A killed unit writes no status and logs nothing past the header block, so
# the designed, documented graceful-SKIP path was unreachable for any job whose project
# lock was contended longer than TimeoutStartSec. Observed live 2026-08-02 on the first
# oracle-brana-drift smoke run: thebrana.lock was held by another job and the unit was
# killed at exactly +180s with an empty log — indistinguishable from a hang.
#
# THE RESOLUTION. The budget is derived from every wait the runner can legitimately
# spend: per-attempt (lock wait + job timeout), plus the exponential retry backoff
# between attempts, plus a fixed margin. systemd stays a true outer safety net — it can
# still kill a genuinely wedged runner — but it can no longer fire INSIDE the window the
# runner was configured to spend waiting.
#
# noProjectLock jobs (t-2292) never open the lock fd, so they must NOT be charged the
# lock wait — otherwise opting out of the lock would inflate the very budget it avoids.
#
# The function under test is extracted from system/scheduler/brana-scheduler so this
# test exercises the shipped source, not a copy (t-1978 rot class).
#
# Run: bash tests/procedures/test-scheduler-service-timeout.sh

set -uo pipefail

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
        echo "  FAIL: $desc — expected [$expected], got [$actual]"
        FAIL=$((FAIL + 1))
    fi
}

REPO_ROOT=$(git rev-parse --show-toplevel)
GENERATOR="$REPO_ROOT/system/scheduler/brana-scheduler"
RUNNER="$REPO_ROOT/system/scheduler/brana-scheduler-runner.sh"
TMPDIR_T=$(mktemp -d)
trap 'rm -rf "$TMPDIR_T"' EXIT

if [ ! -f "$GENERATOR" ]; then
    echo "ERROR: $GENERATOR does not exist"
    exit 1
fi

# Extract by NAMED MARKER, not by position or content substring (t-2493).
sed -n '/# SERVICE-TIMEOUT-BLOCK$/,/# \/SERVICE-TIMEOUT-BLOCK$/p' "$GENERATOR" \
| sed '1d;$d' > "$TMPDIR_T/timeout.sh"

if [ ! -s "$TMPDIR_T/timeout.sh" ]; then
    echo "ERROR: SERVICE-TIMEOUT-BLOCK markers missing or empty in $GENERATOR"
    exit 1
fi
if ! grep -q 'resolve_service_timeout' "$TMPDIR_T/timeout.sh"; then
    echo "ERROR: SERVICE-TIMEOUT-BLOCK does not contain resolve_service_timeout() — markers drifted"
    exit 1
fi

source "$TMPDIR_T/timeout.sh"

# resolve_service_timeout <job_timeout> <max_retries> <retry_backoff> <lock_wait> <no_project_lock>

echo "=== AC: the budget covers the lock wait (the reported bug) ==="
# Scheduler defaults: timeoutSeconds 300, maxRetries 0, lockWaitSeconds 600.
# Runner may spend 600s waiting + 300s running = 900s, +60s margin.
# Old formula gave (300+60)*1 = 360 — less than the 600s wait alone.
assert_eq "defaults: budget exceeds lockWait+timeout" "960" \
    "$(resolve_service_timeout 300 0 30 600 false)"
assert_eq "defaults: budget strictly greater than the lock wait alone" "yes" \
    "$( [ "$(resolve_service_timeout 300 0 30 600 false)" -gt 600 ] && echo yes || echo no )"

echo "=== AC: the live oracle-brana-drift case ==="
# timeoutSeconds 120, maxRetries 0, noProjectLock true. This job opted out of the lock
# precisely to dodge the kill window, so its budget must be UNCHANGED at 180s — opting
# out of the lock must not inflate the budget it avoids.
assert_eq "noProjectLock: lock wait not charged" "180" \
    "$(resolve_service_timeout 120 0 30 600 true)"
# Same job WITHOUT the opt-out is what the bug killed at +180s.
assert_eq "same job holding the lock: budget covers the wait" "780" \
    "$(resolve_service_timeout 120 0 30 600 false)"

echo "=== AC: retries multiply the per-attempt wait and add exponential backoff ==="
# 2 attempts: 2*(600+300) = 1800, backoff after attempt 1 = 30, margin 60 => 1890.
assert_eq "1 retry: per-attempt wait counted twice + backoff" "1890" \
    "$(resolve_service_timeout 300 1 30 600 false)"
# 3 attempts: 3*900 = 2700, backoff 30 + 60 = 90, margin 60 => 2850.
assert_eq "2 retries: exponential backoff summed (30+60)" "2850" \
    "$(resolve_service_timeout 300 2 30 600 false)"
# noProjectLock with retries: 3*300 = 900, backoff 90, margin 60 => 1050.
assert_eq "2 retries, noProjectLock: no lock wait charged" "1050" \
    "$(resolve_service_timeout 300 2 30 600 true)"

echo "=== AC: budget always exceeds the runner's own worst case ==="
# Property check across a spread of configs: whatever the runner can legitimately spend
# must be strictly less than what systemd allows, or the kill window reopens.
prop_fail=0
for jt in 30 120 300 900; do
    for mr in 0 1 2; do
        for lw in 1 60 600; do
            for npl in true false; do
                budget=$(resolve_service_timeout "$jt" "$mr" 30 "$lw" "$npl")
                attempts=$((mr + 1))
                per=$jt
                [ "$npl" != "true" ] && per=$((jt + lw))
                backoff=$(( 30 * ((1 << mr) - 1) ))
                worst=$(( attempts * per + backoff ))
                if [ "$budget" -le "$worst" ]; then
                    echo "    budget $budget <= worst case $worst (jt=$jt mr=$mr lw=$lw npl=$npl)"
                    prop_fail=1
                fi
            done
        done
    done
done
assert_eq "budget > runner worst case across 72 configs" "0" "$prop_fail"

echo "=== AC: guards against malformed input (never emits an empty/zero budget) ==="
assert_eq "absent lock wait treated as 0, still positive" "yes" \
    "$( [ "$(resolve_service_timeout 300 0 30 '' false)" -gt 0 ] && echo yes || echo no )"
assert_eq "null literals from jq --field degrade safely" "yes" \
    "$( [ "$(resolve_service_timeout 300 null null null false)" -gt 0 ] && echo yes || echo no )"

echo "=== AC: the runner's waits are still the ones the formula models ==="
# Guards against the formula drifting away from the runner it is meant to bound.
assert_eq "runner still waits with flock -w \$LOCK_WAIT_SECS" "yes" \
    "$(grep -q 'flock -w "\$LOCK_WAIT_SECS"' "$RUNNER" && echo yes || echo no)"
assert_eq "runner still backs off RETRY_BACKOFF * 2^(n-1)" "yes" \
    "$(grep -q 'RETRY_BACKOFF \* (1 << (ATTEMPT - 1))' "$RUNNER" && echo yes || echo no)"
assert_eq "runner still skips the lock for noProjectLock" "yes" \
    "$(grep -q 'NO_PROJECT_LOCK' "$RUNNER" && echo yes || echo no)"

echo ""
echo "test-scheduler-service-timeout: $PASS/$TOTAL passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
