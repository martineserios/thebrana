#!/usr/bin/env bash
# run-test-suites.sh — run standalone test suites one by one, each under a ceiling; report all; exit 1
# if any failed. The CI test loop (Linux `tests` job + macOS job), extracted so both share it and so
# it works where timeout(1) does not exist (stock macOS): the ceiling is portable.sh's p_timeout.
#
#   bash system/scripts/run-test-suites.sh tests/*/*.sh system/hooks/tests/*.sh
#
# Env: TEST_SUITE_TIMEOUT  per-suite ceiling in seconds (default 300)
#
# Behaviour carried over from the inline CI loop (t-3023 / t-3319):
#  - per-suite ceiling so one hang names itself instead of stalling the job
#  - stdin from /dev/null: a suite that (even indirectly) reads stdin would block forever on the
#    runner's open, never-closing stdin (test-validate-reference-check.sh hung run 33873752281)
#  - sourced helper libraries (_*.sh, */lib/*) are announced and skipped — they define functions
#  - keep going after a failure; list every failed suite at the end
set -u
source "$(dirname "${BASH_SOURCE[0]}")/../hooks/lib/portable.sh"

TIMEOUT="${TEST_SUITE_TIMEOUT:-300}"
FAIL=0
FAILED_TESTS=""

if [ "$#" -eq 0 ]; then echo "run-test-suites: no suites given — nothing to run"; exit 0; fi

for test in "$@"; do
    case "$test" in
        */_*|_*|*/lib/*) echo "=== Skipping helper $test ==="; continue ;;
    esac
    echo "=== Running $test ==="
    if [ ! -f "$test" ]; then
        echo "--- MISSING (no such file — an unexpanded glob?) ---"
        FAIL=1; FAILED_TESTS="$FAILED_TESTS $test"; echo ""; continue
    fi
    p_timeout "$TIMEOUT" bash "$test" </dev/null
    rc=$?
    if [ "$rc" -eq 0 ]; then
        echo "--- PASSED ---"
    else
        # 124 = p_timeout/timeout(1) timed out; 137 = it had to escalate to KILL
        if [ "$rc" -eq 124 ] || [ "$rc" -eq 137 ]; then echo "--- TIMED OUT (${TIMEOUT}s) ---"; else echo "--- FAILED (exit $rc) ---"; fi
        FAIL=1
        FAILED_TESTS="$FAILED_TESTS $test"
    fi
    echo ""
done

if [ -n "$FAILED_TESTS" ]; then
    echo "Failed tests:"
    for t in $FAILED_TESTS; do echo "  - $t"; done
fi
exit $FAIL
