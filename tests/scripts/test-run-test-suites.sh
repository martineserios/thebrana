#!/usr/bin/env bash
# system/scripts/run-test-suites.sh — the CI test loop, extracted so Linux and macOS jobs share it
# (stock macOS has no timeout(1); the script uses portable.sh's p_timeout). t-3376.
# Run: bash tests/scripts/test-run-test-suites.sh
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RUNNER="$ROOT/system/scripts/run-test-suites.sh"
PASS=0; FAIL=0
assert() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "  PASS: $1"; else FAIL=$((FAIL+1)); echo "  FAIL: $1 (expected '$2', got '$3')"; fi; }
has() { case "$2" in *"$1"*) echo yes;; *) echo no;; esac; }
echo "=== test-run-test-suites.sh ==="
[ -f "$RUNNER" ] || { echo "  FAIL: $RUNNER missing"; exit 1; }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/tests/a" "$T/tests/lib"
printf '#!/usr/bin/env bash\necho i-pass\nexit 0\n'        >"$T/tests/a/test-pass.sh"
printf '#!/usr/bin/env bash\necho i-fail\nexit 3\n'        >"$T/tests/a/test-fail.sh"
printf '#!/usr/bin/env bash\nsleep 30\n'                   >"$T/tests/a/test-hang.sh"
printf '#!/usr/bin/env bash\ncat >/dev/null; echo got-eof\n' >"$T/tests/a/test-stdin.sh"
printf '#!/usr/bin/env bash\necho SHOULD-NOT-RUN\nexit 9\n'  >"$T/tests/a/_helper.sh"
printf '#!/usr/bin/env bash\necho SHOULD-NOT-RUN\nexit 9\n'  >"$T/tests/lib/lib.sh"
run() { ( cd "$T" && TEST_SUITE_TIMEOUT="${TO:-300}" bash "$RUNNER" "$@" 2>&1 ); }

OUT="$(run tests/a/test-pass.sh)"; RC=$?
assert "all green: exit 0" 0 "$RC"
assert "prints the running marker" yes "$(has '=== Running tests/a/test-pass.sh ===' "$OUT")"
assert "prints the PASSED marker" yes "$(has '--- PASSED ---' "$OUT")"

OUT="$(run tests/a/test-pass.sh tests/a/test-fail.sh)"; RC=$?
assert "a failing suite: exit 1" 1 "$RC"
assert "names the exit code" yes "$(has '--- FAILED (exit 3) ---' "$OUT")"
assert "lists the failed suite at the end" yes "$(has '  - tests/a/test-fail.sh' "$OUT")"
assert "keeps running after a failure (passing suite still ran)" yes "$(has 'i-pass' "$OUT")"

OUT="$(TO=1 run tests/a/test-hang.sh)"; RC=$?
assert "a hung suite is killed: exit 1" 1 "$RC"
assert "reports the timeout with its budget" yes "$(has '--- TIMED OUT (1s) ---' "$OUT")"

OUT="$(run tests/a/_helper.sh tests/lib/lib.sh tests/a/test-pass.sh)"; RC=$?
assert "helpers (_*.sh, tests/lib/*) are skipped, not run" no "$(has 'SHOULD-NOT-RUN' "$OUT")"
assert "helpers are announced as skipped" yes "$(has '=== Skipping helper tests/a/_helper.sh ===' "$OUT")"
assert "skipping helpers does not fail the run" 0 "$RC"

OUT="$(run tests/a/test-stdin.sh)"
assert "stdin is /dev/null (a suite reading stdin gets EOF, never blocks)" yes "$(has 'got-eof' "$OUT")"

OUT="$(run)"; RC=$?
assert "no suites given: exit 0 with a note (an empty glob is not a failure)" 0 "$RC"

# ── the same, on a BSD-shaped PATH with no timeout(1): only p_timeout's fallback can satisfy these ─
_BSD_REAL_PATH="$PATH"
source "$ROOT/tests/lib/bsd-path.sh"
BSD_BIN="$(make_bsd_bin)"; trap 'rm -rf "$T" "$BSD_BIN"' EXIT
for tool in gtimeout timeout; do PATH="$BSD_BIN" command -v $tool >/dev/null 2>&1 && echo "  NOTE: $tool leaked into the BSD PATH"; done
runb() { ( cd "$T" && PATH="$BSD_BIN" TEST_SUITE_TIMEOUT="${TO:-300}" "$(command -v bash)" "$RUNNER" "$@" 2>&1 ); }
OUT="$(TO=1 runb tests/a/test-hang.sh)"; RC=$?
assert "bsd PATH: a hung suite is still killed (exit 1)" 1 "$RC"
assert "bsd PATH: reports the timeout" yes "$(has '--- TIMED OUT (1s) ---' "$OUT")"
OUT="$(runb tests/a/test-pass.sh tests/a/test-fail.sh)"; RC=$?
assert "bsd PATH: pass+fail -> exit 1" 1 "$RC"
assert "bsd PATH: failing suite named" yes "$(has '  - tests/a/test-fail.sh' "$OUT")"
OUT="$(runb tests/a/test-stdin.sh)"
assert "bsd PATH: stdin is /dev/null" yes "$(has 'got-eof' "$OUT")"

echo; echo "Results: $PASS passed, $FAIL failed"; [ "$FAIL" -eq 0 ]
