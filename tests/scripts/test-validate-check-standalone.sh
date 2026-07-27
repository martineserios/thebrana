#!/usr/bin/env bash
# Regression tests for validate.sh --check <N> self-containment (t-2471).
#
# validate.sh runs under `set -u`. A variable assigned inside one check's
# `if should_run N; ... fi` block is unset when the --check selector skips that
# block, so any other check referencing it aborts with "unbound variable".
#
# TASKS_FILE used to be assigned inside the Check 25 block while checks
# 26/62/63/64 all read it — so `./validate.sh --check 63` aborted, making the
# selector unusable for targeted iteration on exactly the checks most likely to
# need it (the tasks.json schema checks).
#
# Coverage:
#   - each tasks.json-consuming check runs standalone without unbound errors
#   - no check leaks a variable that another check depends on (static scan)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
VALIDATE="$REPO_ROOT/validate.sh"

PASS=0; FAIL=0; TOTAL=0

# Checks that read $TASKS_FILE.
TASKS_CHECKS=(25 26 62 63 64)

assert_no_unbound() {
    local check="$1" out
    TOTAL=$((TOTAL+1))
    out="$(timeout 60 "$VALIDATE" --check "$check" 2>&1)"
    if grep -q 'unbound variable' <<<"$out"; then
        FAIL=$((FAIL+1))
        echo "  FAIL: --check $check aborted with an unbound variable"
        echo "        $(grep 'unbound variable' <<<"$out" | head -1)"
    else
        PASS=$((PASS+1))
        echo "  PASS: --check $check runs standalone"
    fi
}

echo "=== validate.sh --check self-containment (t-2471) ==="

if [ ! -x "$VALIDATE" ]; then
    echo "  SKIP: $VALIDATE not found or not executable"
    exit 0
fi

for c in "${TASKS_CHECKS[@]}"; do
    assert_no_unbound "$c"
done

# Static guard: TASKS_FILE must be assigned at global scope, not inside a
# should_run block. Catches a re-introduction without paying for a full run.
echo "=== static: TASKS_FILE assigned at global scope ==="
TOTAL=$((TOTAL+1))
if awk '
    /^if should_run [0-9]+;/ { depth=1 }
    /^fi[[:space:]]*#[[:space:]]*should_run/ { depth=0 }
    /^[[:space:]]*TASKS_FILE=/ { if (depth==1) { found=1 } }
    END { exit(found?1:0) }
' "$VALIDATE"; then
    PASS=$((PASS+1)); echo "  PASS: TASKS_FILE not assigned inside a should_run block"
else
    FAIL=$((FAIL+1)); echo "  FAIL: TASKS_FILE is assigned inside a should_run block — hoist it to global scope"
fi

echo ""
echo "Total: $TOTAL  Passed: $PASS  Failed: $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
