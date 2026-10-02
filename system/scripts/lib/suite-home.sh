#!/usr/bin/env bash
# suite-home.sh — a throwaway HOME per test suite, shared by BOTH suite runners (t-3389):
# system/scripts/run-test-suites.sh (CI loop) and system/scripts/hook-test-sweep.sh (validate Check 70).
#
# Why: the first real macOS run found the full suite leaving test entries in the REAL
# ~/.claude/run-state/persist-failures.log (a suite ran a hook with no HOME override) and the next
# session-start reported them as real failed memory writes. Isolating at the runner closes the whole
# class — no suite can reach the operator's ~/.claude, whatever it forgets to fake. Two runners execute
# the same suites, so the mechanism lives here once (a challenger finding: fixing one runner left the
# operator's most frequent path, Check 70, un-isolated).
#
# Shape:
#  - The scratch HOME lives INSIDE the caller's HOME, not /tmp: hooks pass /tmp/* through untouched
#    (tdd-gate.sh), and four suites build fixture repos under $HOME precisely to escape that exemption
#    (test-tdd-gate, test-e2e-hooks, test-spec-first-gate, test-hooks) — a /tmp scratch HOME would turn
#    their deny assertions into silent pass-throughs.
#  - It is empty except for a .gitconfig carrying a test identity: the scratch HOME hides the operator's
#    ~/.gitconfig and seven suites commit without setting one. A gitconfig (not GIT_* env) keeps git's
#    precedence — a fixture's repo-local user.name still wins.
#  - Deletion is pinned to the name pattern under the caller's HOME, never a bare rm -rf of a variable.
#  - Leftovers happen (SIGKILL mid-suite; a detached survivor — ruflo was seen doing it — recreating
#    $HOME/.claude-flow after its suite ended). suite_home_reap removes leftovers older than 2h at every
#    runner start, and the runner re-drops every dir it created at exit. The "created" list is a FILE
#    (suite_home_init), not a shell variable: suite_home_make runs inside $(...) and the sweep runs
#    suites as background jobs, so a variable append would be lost in the subshell (Gate 3 finding).
#  - BRANA_RUN_STATE_DIR / BRANA_GOAL_FILE / BRANA_DIGEST_DIR are HOME-bypassing overrides read by hooks;
#    suite_env_scrub unsets them so an operator's export cannot route a suite back to real state.
#  - TEST_SUITE_KEEP_HOME=1 passes the caller's HOME through for diagnosis only: it is announced
#    loudly and refused under CI (where it would silently disable the fix).
#
# Usage (sourced): suite_env_scrub; suite_home_reap "$HOME"; suite_home_init
#                  run_suite_isolated "$HOME" cmd args...   # cmd's exit status is returned
#                  trap 'suite_home_drop_all "$HOME"' EXIT  # re-drops every dir this run created
SUITE_HOME_PREFIX=".brana-test-home."
SUITE_HOME_CURRENT=""
SUITE_HOME_LEDGER=""

# suite_home_init — open the created-dirs ledger (a temp file; one path per line)
suite_home_init() { [ -n "$SUITE_HOME_LEDGER" ] || SUITE_HOME_LEDGER="$(mktemp)"; }

# Every HOME-bypassing override a hook reads (grep 'BRANA_[A-Z_]*_\(DIR\|FILE\|TMPROOT\)' system/hooks when adding one)
suite_env_scrub() {
    unset BRANA_RUN_STATE_DIR BRANA_GOAL_FILE BRANA_DIGEST_DIR \
          BRANA_RATINGS_DIR BRANA_FAILURES_DIR BRANA_PRECOMPACT_GUARD_DIR BRANA_SS_TMPROOT \
          BRANA_DEPLOY_DIR BRANA_SOURCE_DIR
}

# suite_home_keep -> 0 when the caller asked to keep the real HOME (announced once; refused under CI)
suite_home_keep() {
    [ "${TEST_SUITE_KEEP_HOME:-0}" = 1 ] || return 1
    if [ -n "${CI:-}" ]; then
        echo "suite-home: TEST_SUITE_KEEP_HOME=1 is refused under CI — suites would run in the real HOME" >&2
        exit 2
    fi
    if [ -z "${_SUITE_HOME_KEEP_ANNOUNCED:-}" ]; then
        echo "!!! TEST_SUITE_KEEP_HOME=1: suites run under the REAL HOME ($HOME) — diagnosis only, isolation is OFF" >&2
        _SUITE_HOME_KEEP_ANNOUNCED=1
    fi
    return 0
}

# suite_home_reap REAL_HOME — remove scratch dirs older than 2h (a killed runner, a detached survivor)
suite_home_reap() {
    find "$1" -maxdepth 1 -type d -name "${SUITE_HOME_PREFIX}*" -mmin +120 -exec rm -rf {} + 2>/dev/null || true
}

# suite_home_make REAL_HOME — prints a fresh scratch HOME seeded with a git identity
suite_home_make() {
    local d
    d="$(mktemp -d "$1/${SUITE_HOME_PREFIX}XXXXXX")" || return 1
    printf '[user]\n\tname = brana-tests\n\temail = brana-tests@localhost\n' >"$d/.gitconfig"
    [ -n "$SUITE_HOME_LEDGER" ] && printf '%s\n' "$d" >>"$SUITE_HOME_LEDGER"
    printf '%s' "$d"
}

# suite_home_drop DIR REAL_HOME — delete only a name-pinned scratch dir under REAL_HOME
suite_home_drop() {
    case "$1" in "$2/${SUITE_HOME_PREFIX}"*) rm -rf "$1" ;; esac
}

# suite_home_drop_all REAL_HOME — second pass at exit: a survivor may have recreated a dir we dropped
suite_home_drop_all() {
    local d
    if [ -n "$SUITE_HOME_LEDGER" ] && [ -f "$SUITE_HOME_LEDGER" ]; then
        while IFS= read -r d; do [ -n "$d" ] && suite_home_drop "$d" "$1"; done <"$SUITE_HOME_LEDGER"
        rm -f "$SUITE_HOME_LEDGER"
    fi
    [ -n "$SUITE_HOME_CURRENT" ] && suite_home_drop "$SUITE_HOME_CURRENT" "$1"
    return 0
}

# run_suite_isolated REAL_HOME cmd args... — run cmd under a scratch HOME; returns cmd's exit status
run_suite_isolated() {
    local real="$1" rc; shift
    if suite_home_keep; then "$@"; return $?; fi
    SUITE_HOME_CURRENT="$(suite_home_make "$real")" || {
        echo "suite-home: cannot create a scratch HOME under $real (unwritable HOME is fatal — nothing runs un-isolated)" >&2
        return 2
    }
    HOME="$SUITE_HOME_CURRENT" "$@"; rc=$?
    suite_home_drop "$SUITE_HOME_CURRENT" "$real"; SUITE_HOME_CURRENT=""
    return $rc
}
