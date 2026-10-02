#!/usr/bin/env bash
# A non-GNU host WITH flock installed (a Mac after `brew install flock`) must still get a green
# portability suite AND a real stress run of the no-flock fallback (t-3391).
#
# The first real macOS run showed the gap: on stock macOS test-portable.sh was 112/0, but after
# installing flock it dropped to 105/7 — every failure a 'fallback lock:' assertion — and
# test-lock-stress.sh only printed SKIP. Cause: both tests assumed "non-GNU host" == "no flock",
# so with flock present the real flock path ran where the fallback was under test.
#
# Reproduction on a GNU host: run both tests under a BSD-shaped PATH (host_is_gnu says no) that
# ALSO carries flock — the brew-flock Mac, simulated. GNU host only (needs the BSD simulation).
# Run: bash tests/hooks/test-portable-flock-present.sh
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
_BSD_REAL_PATH="$PATH"
source "$ROOT/tests/lib/bsd-path.sh"
PASS=0; FAIL=0
assert() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "  PASS: $1"; else FAIL=$((FAIL+1)); echo "  FAIL: $1 (expected '$2', got '$3')"; fi; }
has() { case "$2" in *"$1"*) echo yes;; *) echo no;; esac; }
echo "=== test-portable-flock-present.sh ==="
if ! host_is_gnu; then echo "  SKIP: needs a GNU host to simulate a BSD PATH"; exit 0; fi
FLOCK="$(command -v flock 2>/dev/null)" || { echo "  SKIP: no flock on this host to plant"; exit 0; }   # portable-ok: presence check

BSD_BIN="$(make_bsd_bin)"; FLOCK_DIR="$(mktemp -d)"; T="$(mktemp -d)"
trap 'rm -rf "$BSD_BIN" "$FLOCK_DIR" "$T"' EXIT
ln -s "$FLOCK" "$FLOCK_DIR/flock"
MAC_PATH="$FLOCK_DIR:$BSD_BIN"          # BSD userland + brew flock   # portable-ok: the planted flock IS the scenario under test
assert "sanity: the simulated PATH is non-GNU (date -d fails)" 1 "$(PATH="$MAC_PATH" bash -c 'date -d @0 >/dev/null 2>&1; echo $?')"   # portable-ok: GNU form used as the non-GNU probe, failure expected
assert "sanity: the simulated PATH HAS flock" yes "$(PATH="$MAC_PATH" bash -c 'command -v flock >/dev/null 2>&1 && echo yes || echo no')"   # portable-ok: presence check, not a flock use

PATH="$MAC_PATH" bash "$ROOT/tests/hooks/test-portable.sh" >"$T/portable.log" 2>&1; RC=$?
assert "test-portable.sh is green on a non-GNU host that has flock" 0 "$RC"
assert "test-portable.sh: no 'fallback lock:' assertion failed" no "$(has 'FAIL: fallback lock' "$(cat "$T/portable.log")")"
assert "test-portable.sh: the fallback-lock group really ran under a no-flock PATH (sanity line present)" yes "$(has 'noflock: sanity' "$(cat "$T/portable.log")")"
[ "$RC" -eq 0 ] || grep 'FAIL' "$T/portable.log" | head -8

PATH="$MAC_PATH" LOCK_STRESS_ROUNDS=2 LOCK_STRESS_WORKERS=6 bash "$ROOT/tests/hooks/test-lock-stress.sh" >"$T/stress.log" 2>&1; RC=$?
assert "test-lock-stress.sh exits 0 on a non-GNU host that has flock" 0 "$RC"
assert "test-lock-stress.sh does NOT skip" no "$(has 'SKIP' "$(cat "$T/stress.log")")"
assert "test-lock-stress.sh really ran the contenders" yes "$(has 'every contender in every round acquired' "$(cat "$T/stress.log")")"
[ "$RC" -eq 0 ] || tail -5 "$T/stress.log"

echo; echo "Results: $PASS passed, $FAIL failed"; [ "$FAIL" -eq 0 ]
