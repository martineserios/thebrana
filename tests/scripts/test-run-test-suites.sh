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

# ── every suite gets a throwaway HOME (t-3389): the full suite used to leave test entries in the REAL
# ~/.claude/run-state/persist-failures.log, which the next session-start reported as real failures.
# The scratch HOME also removes the operator's ~/.gitconfig from the picture, so the runner must hand
# suites a git identity itself or every suite that commits would break where it used to work.
REAL_HOME_FOR_TEST="$T/real-home"; mkdir -p "$REAL_HOME_FOR_TEST"
cat >"$T/tests/a/test-home.sh" <<'SUITE'
#!/usr/bin/env bash
echo "HOME=$HOME"; echo "RUNSTATE=${BRANA_RUN_STATE_DIR:-unset}"
touch "$HOME/marker-from-suite"
# identity must come from the scratch HOME's gitconfig, not from GIT_* env (repo-local config must still win)
unset GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL
echo "IDENT=$(git var GIT_AUTHOR_IDENT 2>/dev/null | cut -d'<' -f1)"
d="$(mktemp -d)"; git -C "$d" init -q && git -C "$d" config user.name fixture-user && : >"$d/f" && git -C "$d" add f && git -C "$d" commit -q -m x && echo "AUTHOR=$(git -C "$d" log -1 --format=%an)"; rm -rf "$d"
SUITE
runh() { ( cd "$T" && HOME="$REAL_HOME_FOR_TEST" TEST_SUITE_TIMEOUT=300 bash "$RUNNER" "$@" 2>&1 ); }
OUT="$(runh tests/a/test-home.sh)"; RC=$?
SUITE_HOME="$(printf '%s\n' "$OUT" | sed -n 's/^HOME=//p' | head -1)"
assert "scratch HOME: the suite ran green" 0 "$RC"
assert "scratch HOME: the suite's HOME is not the caller's" no "$([ "$SUITE_HOME" = "$REAL_HOME_FOR_TEST" ] && echo yes || echo no)"
assert "scratch HOME: the suite's HOME is a real directory while it runs (it wrote there)" no "$(has 'touch: ' "$OUT")"
assert "scratch HOME: nothing landed in the caller's HOME" no "$([ -e "$REAL_HOME_FOR_TEST/marker-from-suite" ] && echo yes || echo no)"
assert "scratch HOME: removed after the suite" no "$([ -n "$SUITE_HOME" ] && [ -e "$SUITE_HOME" ] && echo yes || echo no)"
# hooks pass /tmp/* through; suites that build fixtures under $HOME to escape that must keep escaping it
assert "scratch HOME: lives inside the caller's HOME, not under /tmp" yes "$(case "$SUITE_HOME" in "$REAL_HOME_FOR_TEST"/*) echo yes;; *) echo no;; esac)"
assert "scratch HOME: a git identity comes from the scratch ~/.gitconfig (GIT_* env unset)" yes "$(has 'IDENT=brana-tests' "$OUT")"
assert "scratch HOME: a fixture's repo-local user.name still wins over the test identity" yes "$(has 'AUTHOR=fixture-user' "$OUT")"
assert "scratch HOME: HOME-bypassing overrides (BRANA_RUN_STATE_DIR) are scrubbed" yes "$(BRANA_RUN_STATE_DIR=/nope; export BRANA_RUN_STATE_DIR; has 'RUNSTATE=unset' "$(runh tests/a/test-home.sh)")"
unset BRANA_RUN_STATE_DIR
TO=1 OUT="$(cd "$T" && HOME="$REAL_HOME_FOR_TEST" TEST_SUITE_KILL_AFTER=2 TEST_SUITE_TIMEOUT=1 bash "$RUNNER" tests/a/test-hang.sh 2>&1)"
assert "scratch HOME: no scratch dir remains after a TIMED OUT suite" 0 "$(find "$REAL_HOME_FOR_TEST" -maxdepth 1 -name '.brana-test-home.*' | wc -l | tr -d ' ')"
mkdir -p "$REAL_HOME_FOR_TEST/.brana-test-home.stale" && touch -t 202001010000 "$REAL_HOME_FOR_TEST/.brana-test-home.stale"
runh tests/a/test-pass.sh >/dev/null 2>&1
assert "scratch HOME: a stale leftover from a killed run is reaped at the next start" no "$([ -e "$REAL_HOME_FOR_TEST/.brana-test-home.stale" ] && echo yes || echo no)"
OUT="$(cd "$T" && HOME="$REAL_HOME_FOR_TEST" TEST_SUITE_KEEP_HOME=1 TEST_SUITE_TIMEOUT=300 bash "$RUNNER" tests/a/test-home.sh 2>&1)"
assert "TEST_SUITE_KEEP_HOME=1: the caller's HOME is passed through (diagnostic escape hatch)" "HOME=$REAL_HOME_FOR_TEST" "$(printf '%s\n' "$OUT" | sed -n 's/^\(HOME=.*\)$/\1/p' | head -1)"
assert "TEST_SUITE_KEEP_HOME=1: announced loudly (isolation is OFF)" yes "$(has 'isolation is OFF' "$OUT")"
OUT="$(cd "$T" && HOME="$REAL_HOME_FOR_TEST" CI=1 TEST_SUITE_KEEP_HOME=1 TEST_SUITE_TIMEOUT=300 bash "$RUNNER" tests/a/test-home.sh 2>&1)"; RC=$?
assert "TEST_SUITE_KEEP_HOME=1 under CI: refused (exit 2)" 2 "$RC"
rm -f "$REAL_HOME_FOR_TEST/marker-from-suite"

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

# ── the watchdog must END a stuck suite, not just signal it (t-3390: a Mac run hung 16 min under a 300s ceiling) ──
# term:   the suite ignores TERM (and so does its child) — only a KILL escalation ends it.
# orphan: the suite's grandchild keeps the output pipe open after its parent is killed — a runner whose
#         output is piped (`| tee`, `$(...)`) blocks until it exits unless the whole process GROUP is signalled.
printf '#!/usr/bin/env bash\ntrap "" TERM\nsleep 40\n'          >"$T/tests/a/test-term.sh"
printf '#!/usr/bin/env bash\n( sleep 40; true ) &\nwait\n'            >"$T/tests/a/test-orphan.sh"
printf '#!/usr/bin/env bash\nsleep 4\necho quiet-done\n'         >"$T/tests/a/test-quiet.sh"
printf '#!/usr/bin/env bash\n( trap "" TERM; sleep 40; true ) &\nwait\n' >"$T/tests/a/test-stubborn-child.sh"
timed() { local t0=$SECONDS; OUT="$("$@")"; RC=$?; ELAPSED=$((SECONDS - t0)); }
for mode in native bsd; do
    if [ "$mode" = bsd ]; then runner=runb; else runner=run; fi
    export TEST_SUITE_KILL_AFTER=2
    TO=1 timed $runner tests/a/test-term.sh
    assert "$mode: a TERM-ignoring suite ends within ceiling+grace (took ${ELAPSED}s, limit 12)" yes "$([ "$ELAPSED" -le 12 ] && echo yes || echo no)"
    assert "$mode: a TERM-ignoring suite is reported TIMED OUT" yes "$(has '--- TIMED OUT (1s) ---' "$OUT")"
    TO=1 timed $runner tests/a/test-stubborn-child.sh
    assert "$mode: a TERM-ignoring grandchild of a suite that died on TERM is KILLed (took ${ELAPSED}s, limit 12)" yes "$([ "$ELAPSED" -le 12 ] && echo yes || echo no)"
    TO=1 timed $runner tests/a/test-orphan.sh
    assert "$mode: a grandchild holding stdout does not block the runner (took ${ELAPSED}s, limit 12)" yes "$([ "$ELAPSED" -le 12 ] && echo yes || echo no)"
    assert "$mode: orphan suite is reported TIMED OUT" yes "$(has '--- TIMED OUT (1s) ---' "$OUT")"
    unset TEST_SUITE_KILL_AFTER
    TEST_SUITE_HEARTBEAT=1 TO=30 timed $runner tests/a/test-quiet.sh
    assert "$mode: a long silent suite gets a heartbeat line" yes "$(has 'still running' "$OUT")"
    assert "$mode: heartbeat names the suite" yes "$(has 'tests/a/test-quiet.sh' "$(printf '%s' "$OUT" | grep 'still running')")"
    assert "$mode: heartbeat does not change the verdict" yes "$(has 'quiet-done' "$OUT")"
    TEST_SUITE_HEARTBEAT=abc timed $runner tests/a/test-pass.sh
    assert "$mode: a non-numeric heartbeat setting is ignored, not an error" no "$(has 'syntax error' "$OUT")"
done

echo; echo "Results: $PASS passed, $FAIL failed"; [ "$FAIL" -eq 0 ]
