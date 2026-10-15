#!/usr/bin/env bash
# _p_lock_not_plain must not refuse a lock file that merely VANISHES between its two checks (t-3545).
# The function tests -e/-L, then -f/-L; a holder releasing the lock in between made the second test see
# nothing and the caller got rc 3 REFUSED (symlink/dir/device) — test-lock-stress.sh lost a contender
# (127/128) on PR #1109 CI. A real symlink/dir must still be refused.
# Run: bash tests/hooks/test-lock-not-plain-race.sh
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
LIB="${PORTABLE_LIB:-$ROOT/system/hooks/lib/portable.sh}"   # override only for mutation testing
source "$LIB"
PASS=0; FAIL=0
assert() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "  PASS: $1"; else FAIL=$((FAIL+1)); echo "  FAIL: $1 (expected '$2', got '$3')"; fi; }
echo "=== test-lock-not-plain-race.sh ==="
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

# 1. a plain file and a missing path are not refused
: >"$T/plain"
_p_lock_not_plain "$T/plain" 2>/dev/null; assert "a plain file is not refused" "1" "$?"
_p_lock_not_plain "$T/missing" 2>/dev/null; assert "a missing path is not refused" "1" "$?"

# 2. a symlink and a directory are refused (the safety this function exists for)
ln -s /dev/null "$T/link"; _p_lock_not_plain "$T/link" 2>/dev/null; assert "a symlink is refused" "0" "$?"
mkdir "$T/dir"; _p_lock_not_plain "$T/dir" 2>/dev/null; assert "a directory is refused" "0" "$?"

# 3. MUST-FIRE: a path that appears and disappears under the checker is never refused.
( while :; do : >"$T/churn"; rm -f "$T/churn"; done ) &
CHURN=$!
refused=0
for _ in $(seq 1 20000); do
    _p_lock_not_plain "$T/churn" 2>/dev/null && refused=$((refused + 1))
done
kill "$CHURN" 2>/dev/null; wait "$CHURN" 2>/dev/null
assert "a lock file released mid-check is never refused (20000 checks)" "0" "$refused"

echo; echo "Results: $PASS passed, $FAIL failed"; [ "$FAIL" -eq 0 ]
