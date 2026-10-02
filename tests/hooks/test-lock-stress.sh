#!/usr/bin/env bash
# Stress test for the no-flock fallback lock (portable.sh p_lock_acquire/p_lock_release, t-3383).
# N contenders race for ONE lock, every round starting from a STALE lock (dead pid) so the reclaim path
# — the part that once double-granted — runs every round, not once. The overlap detector is the shell's
# own noclobber create (O_EXCL), NOT mkdir: uutils' mkdir is not a safe detector (it lets concurrent
# callers "win" one directory).
#
# Env: LOCK_STRESS_ROUNDS (default 8), LOCK_STRESS_WORKERS (default 16)
# Where: on a GNU host the no-flock condition is simulated (BSD PATH); on a non-GNU host it runs under
# the host's own tools minus flock (make_noflock_bin) — so a Mac with `brew install flock` still
# stress-tests the fallback instead of skipping (t-3391).
# Run: bash tests/hooks/test-lock-stress.sh
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
LIB="${PORTABLE_LIB:-$ROOT/system/hooks/lib/portable.sh}"   # override only for mutation testing
ROUNDS="${LOCK_STRESS_ROUNDS:-8}"; WORKERS="${LOCK_STRESS_WORKERS:-16}"
_BSD_REAL_PATH="$PATH"
source "$ROOT/tests/lib/bsd-path.sh"
PASS=0; FAIL=0
assert() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "  PASS: $1"; else FAIL=$((FAIL+1)); echo "  FAIL: $1 (expected '$2', got '$3')"; fi; }
echo "=== test-lock-stress.sh (${WORKERS} contenders x ${ROUNDS} rounds) ==="

T="$(mktemp -d)"; BSD_BIN=""
if host_is_gnu; then BSD_BIN="$(make_bsd_bin)"; else BSD_BIN="$(make_noflock_bin)"; fi
trap 'rm -rf "$T" "$BSD_BIN"' EXIT
# Guard the guard: the contenders' PATH must have no flock, or this stresses the wrong code path.
assert "sanity: no flock under the contenders' PATH, bash present" "11" "$(noflock_sanity "$BSD_BIN")"   # portable-ok: presence check (guard the guard), not a flock use
BASH_BIN="$(command -v bash)"

total=0; overlaps=0; starved=0
for round in $(seq 1 "$ROUNDS"); do
    rm -f "$T/inside" "$T/count" "$T/viol" "$T/lock.lk" "$T/lock.lk.reclaim"
    echo 999999 >"$T/lock.lk"      # a stale lock (no such pid) — forces the reclaim path
    : >"$T/count"; : >"$T/viol"
    for _ in $(seq 1 "$WORKERS"); do
        ( PATH="${BSD_BIN:-$PATH}" "$BASH_BIN" -c "
            source '$LIB'
            p_lock_acquire 9 '$T/lock' -w 60 || { echo NOACQ >>'$T/viol'; exit 0; }   # portable-ok: runs in the child shell, which sources the lib above
            if ! ( set -C; : >'$T/inside' ) 2>/dev/null; then echo OVERLAP >>'$T/viol'; fi
            echo x >>'$T/count'; sleep 0.01
            rm -f '$T/inside'
            p_lock_release 9 '$T/lock'   # portable-ok: child shell" ) &
    done
    wait
    got="$(wc -l <"$T/count" | tr -d ' ')"
    total=$((total + got))
    overlaps=$((overlaps + $(grep -c OVERLAP "$T/viol" 2>/dev/null || true)))
    starved=$((starved + $(grep -c NOACQ "$T/viol" 2>/dev/null || true)))
done
assert "every contender in every round acquired the lock" "$((WORKERS * ROUNDS))" "$total"
assert "never two holders at once (overlaps across all rounds)" "0" "$overlaps"
assert "no contender starved (gave up after the wait budget)" "0" "$starved"
echo; echo "Results: $PASS passed, $FAIL failed"; [ "$FAIL" -eq 0 ]
