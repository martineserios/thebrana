#!/usr/bin/env bash
# Test: ruflo-mcp.sh prevents multiple simultaneous instances
# t-1858 — flock mutex prevents DB corruption from concurrent writers
set -euo pipefail

SCRIPT="$(cd "$(dirname "$0")/../.." && pwd)/system/scripts/ruflo-mcp.sh"
LOCK="$HOME/.swarm/ruflo-mcp.lock"
TMPDIR_TEST="$(mktemp -d)"
PASS=0
FAIL=0

pass() { echo "PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

cleanup() {
    rm -rf "$TMPDIR_TEST"
    # Release any test locks
    rm -f "${TMPDIR_TEST}/ruflo-mcp.lock" 2>/dev/null || true
}
trap cleanup EXIT

echo "=== ruflo-mcp.sh single-instance gate test ==="

# Test 1: Script is executable
if [ -x "$SCRIPT" ]; then
    pass "script is executable"
else
    fail "script is not executable at $SCRIPT"
fi

# Test 2: flock pattern exists in script
if grep -q "flock" "$SCRIPT"; then
    pass "flock mutex pattern present in script"
else
    fail "flock mutex pattern MISSING from script — multi-instance DB corruption possible"
fi

# Test 3: Lock file path uses .swarm directory
if grep -q '\.swarm.*\.lock' "$SCRIPT"; then
    pass "lock file uses .swarm directory"
else
    fail "lock file not using .swarm directory"
fi

# Test 4: Second instance exits when lock is held
# Hold the real lock file, then verify a second script call exits non-zero
REAL_LOCK="$HOME/.swarm/ruflo-mcp.lock"
mkdir -p "$HOME/.swarm"
# Acquire the lock ourselves (non-blocking), then call the script
(
    exec 9>"$REAL_LOCK"
    flock -n 9 || { echo "Could not acquire test lock — lock already held, skipping test 4"; exit 0; }
    # Lock held; now run the real script — it should exit 1 immediately
    _r=0; timeout 5 bash "$SCRIPT" --version 2>/dev/null || _r=$?
    echo "$_r"
) > /tmp/t4_exit.txt 2>&1 || true
T4_EXIT="$(cat /tmp/t4_exit.txt | tail -1 | tr -d '[:space:]')"
if [ "$T4_EXIT" = "1" ]; then
    pass "second instance exits non-zero when lock is held (exit: $T4_EXIT)"
else
    fail "second instance did NOT exit when lock was held (got: '$T4_EXIT') — flock not enforced"
fi
rm -f /tmp/t4_exit.txt

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
