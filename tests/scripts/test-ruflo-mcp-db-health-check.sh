#!/usr/bin/env bash
# Test: ruflo_mcp_db_is_healthy() (t-2085/t-2260 checkpoint-copy corruption
# check in system/scripts/ruflo-mcp.sh) actually detects healthy vs corrupt
# DBs when a live -wal sidecar is present.
#
# Why this test exists (t-2634 / t-2627, 2026-08-05): neither
# test-ruflo-mcp-single-instance.sh nor test-ruflo-cli-wrapper.sh ever calls
# this function — they only assert the removed flock/orphan-sweep code stays
# removed. That gap is exactly the one t-2260 left unchecked for 10 days
# before real corruption resulted. The function's target defect (missing
# PRAGMA busy_timeout, hardcoded dualWrite in the vendored @claude-flow/memory
# backend) is confirmed STILL PRESENT upstream as of ruflo v3.34.0
# (ruvnet/ruflo#2512 open, unmerged) — this check is expected to stay load-
# bearing indefinitely, not just until the next upgrade.
#
# ruflo-mcp.sh ends in an unconditional `exec "$RUFLO" "$@"` with no
# test-mode hatch (unlike ruflo-cli.sh's RUFLO_CLI_DRYRUN=1), so we extract
# the function body via sed rather than sourcing the live script — sourcing
# would run the exec and never return.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
MCP_SCRIPT="$REPO_ROOT/system/scripts/ruflo-mcp.sh"
PASS=0
FAIL=0

pass() { echo "PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

echo "=== ruflo_mcp_db_is_healthy() regression test (t-2085/t-2260/t-2634) ==="

# Extract the function body (between its definition and the matching closing
# brace) rather than sourcing the live script.
FUNC_SRC="$(sed -n '/^ruflo_mcp_db_is_healthy() {/,/^}/p' "$MCP_SCRIPT")"
if [ -z "$FUNC_SRC" ]; then
    fail "could not extract ruflo_mcp_db_is_healthy() from $MCP_SCRIPT — has the function been renamed or removed?"
    echo ""
    echo "Results: $PASS passed, $FAIL failed"
    exit 1
fi
pass "extracted function body via sed"

TESTDIR="$(mktemp -d)"
HOLDER_PID=""
cleanup() {
    # Guard against HOLDER_PID being empty/0 — `kill 0` signals the entire
    # process group, not a no-op, and would take down the calling shell too.
    if [ -n "$HOLDER_PID" ] && [ "$HOLDER_PID" -gt 0 ] 2>/dev/null; then
        kill "$HOLDER_PID" 2>/dev/null
        wait "$HOLDER_PID" 2>/dev/null
    fi
    rm -rf "$TESTDIR"
}
trap cleanup EXIT

# ── Fixture 1: healthy DB with a live -wal sidecar ─────────────────────────
# A background reader holds a connection open so the -wal file persists on
# disk (a closed connection auto-checkpoints and removes it) — this is what
# makes the fixture representative of the real "another session has the DB
# open" scenario the function exists to handle.
python3 -c "
import sqlite3, time
conn = sqlite3.connect('$TESTDIR/healthy.db')
conn.execute('PRAGMA journal_mode=WAL')
conn.execute('CREATE TABLE t(x INTEGER)')
conn.execute('INSERT INTO t VALUES (1)')
conn.commit()
conn2 = sqlite3.connect('$TESTDIR/healthy.db')
list(conn2.execute('SELECT * FROM t'))
time.sleep(20)
" &
HOLDER_PID=$!
sleep 1

if [ ! -f "$TESTDIR/healthy.db-wal" ]; then
    fail "fixture setup failed — no -wal sidecar produced (test environment issue, not the function under test)"
else
    pass "fixture: -wal sidecar present for the healthy DB"

    # Test 1: healthy DB with -wal present -> function returns healthy (exit 0)
    if (eval "$FUNC_SRC"; ruflo_mcp_db_is_healthy "$TESTDIR/healthy.db"); then
        pass "healthy WAL-present DB returns healthy"
    else
        fail "healthy WAL-present DB was reported unhealthy — false positive would trigger unnecessary recovery on every upgrade"
    fi
fi

kill "$HOLDER_PID" 2>/dev/null; wait "$HOLDER_PID" 2>/dev/null; HOLDER_PID=""

# ── Fixture 2 (boundary case): corrupted DB, no -wal ───────────────────────
# Corrupt a plain (non-WAL, no sidecar) DB by truncating it mid-file — the
# function's non-WAL branch (plain PRAGMA integrity_check) must catch this.
sqlite3 "$TESTDIR/corrupt.db" "CREATE TABLE t(x INTEGER); INSERT INTO t VALUES (1);" >/dev/null 2>&1
FULL_SIZE=$(stat -c%s "$TESTDIR/corrupt.db" 2>/dev/null || stat -f%z "$TESTDIR/corrupt.db")
truncate -s $((FULL_SIZE / 2)) "$TESTDIR/corrupt.db"

if (eval "$FUNC_SRC"; ruflo_mcp_db_is_healthy "$TESTDIR/corrupt.db"); then
    fail "truncated/corrupt DB (no -wal) was reported healthy — false negative would let real corruption through unchecked, the exact t-982/t-2261 failure mode"
else
    pass "truncated/corrupt DB (no -wal) correctly reported unhealthy"
fi

# ── Boundary observation (not a pass/fail assertion): non-existent DB path.
# sqlite3's CLI auto-creates an empty DB file when given a path that doesn't
# exist, and PRAGMA integrity_check on an empty DB returns "ok" — so the
# function reports "healthy" (and side-effects an empty DB into existence)
# for a path that was never a real database. This is a latent footgun in the
# function taken alone, but NOT a live bug: its one production call site
# (ruflo-mcp.sh:54-55) always guards with `[ -f "$DB_PATH" ]` first, so this
# path is unreachable in practice. Documented rather than asserted as a
# failure — asserting it would make this test permanently red over an
# unreachable code path, and the fix (an existence check inside the function)
# isn't warranted without a second call site that could actually hit it.
(eval "$FUNC_SRC"; ruflo_mcp_db_is_healthy "$TESTDIR/does-not-exist.db") \
    && echo "NOTE: standalone call on a non-existent path reports healthy (side-effects an empty DB) — inert today, guarded by the sole call site's -f check" \
    || echo "NOTE: standalone call on a non-existent path reports unhealthy"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
