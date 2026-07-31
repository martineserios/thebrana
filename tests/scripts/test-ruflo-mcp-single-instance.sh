#!/usr/bin/env bash
# Test: ruflo-mcp.sh must NOT reintroduce a flock mutex or orphan sweep.
#
# History: t-1858 added a flock mutex + orphan sweep to stop concurrent writers
# corrupting the ruflo DB. t-2085 REMOVED both — the orphan sweep killed live
# writers and caused the very corruption it was meant to prevent (confirmed
# 2026-06-13 with flock active). SQLite WAL mode serialises concurrent writes
# correctly, so no userspace mutex is needed. See system/scripts/ruflo-mcp.sh
# header and docs/architecture/bootstrap.md.
#
# This test was inverted in t-2492. It previously asserted the mutex was PRESENT,
# so it had been red since t-2085 landed. Its "flock present" check also passed
# for a bogus reason: grep matched the comment explaining the removal.
set -euo pipefail

SCRIPT="$(cd "$(dirname "$0")/../.." && pwd)/system/scripts/ruflo-mcp.sh"
PASS=0
FAIL=0

pass() { echo "PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

echo "=== ruflo-mcp.sh concurrency-model regression test (t-2085) ==="

# Test 1: Script is executable
if [ -x "$SCRIPT" ]; then
    pass "script is executable"
else
    fail "script is not executable at $SCRIPT"
fi

# Test 2: no flock mutex in executable code.
# Strip comments first — the removal rationale in the header mentions "flock",
# and matching it is what made the old assertion vacuous.
if grep -v '^[[:space:]]*#' "$SCRIPT" | grep -q 'flock'; then
    fail "flock mutex reintroduced — removed in t-2085 because the paired orphan sweep killed live WAL writers; SQLite WAL already serialises concurrent writes"
else
    pass "no flock mutex (t-2085: SQLite WAL handles concurrent sessions)"
fi

# Test 3: no orphan sweep — the half that actively caused corruption.
if grep -v '^[[:space:]]*#' "$SCRIPT" | grep -qE 'pkill|killall|kill +-9'; then
    fail "orphan-sweep style process kill reintroduced — removed in t-2085 (killed live writers)"
else
    pass "no orphan sweep (t-2085)"
fi

# Test 4: the WAL rationale stays documented, so the next reader does not
# "restore" the mutex as a missing safety feature.
if grep -qi 'WAL' "$SCRIPT"; then
    pass "WAL concurrency rationale documented in script"
else
    fail "WAL rationale missing from script header — removal risks being undone"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
