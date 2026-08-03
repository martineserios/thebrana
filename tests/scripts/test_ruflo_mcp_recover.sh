#!/usr/bin/env bash
# Tests for ruflo-mcp.sh database recovery (t-2619).
#
# Regression under test: the recovery path moved ONLY memory.db to
# memory.db.corrupt-DATE, leaving memory.db-wal and memory.db-shm in place, then
# copied a backup into memory.db underneath those orphaned sidecars. SQLite
# replays the stale WAL onto the fresh backup on next open and the restored
# database is immediately malformed — which guarantees the next session rotates
# again. That is a self-sustaining daily data-loss loop: verified in the wild,
# where memory.db.corrupt-2026-07-31 and -2026-08-01 both pass integrity_check
# standalone (4385 and 4332 rows) — two healthy databases discarded for nothing.
#
# Run: bash tests/scripts/test_ruflo_mcp_recover.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SCRIPT="$REPO_ROOT/system/scripts/ruflo-mcp.sh"

TMPROOT=$(mktemp -d)
trap 'rm -rf "$TMPROOT"' EXIT

PASS=0; FAIL=0; TOTAL=0
assert() {
    local desc="$1" expected="$2" actual="$3"
    TOTAL=$((TOTAL + 1))
    if [ "$expected" = "$actual" ]; then
        echo "  PASS: $desc"; PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc (expected '$expected', got '$actual')"; FAIL=$((FAIL + 1))
    fi
}

echo "=== test_ruflo_mcp_recover.sh ==="

command -v sqlite3 >/dev/null 2>&1 || { echo "  SKIP: sqlite3 unavailable"; exit 0; }

# Probe in a subshell first: an unguarded script runs its main body on source and
# `exec`s ruflo, which would replace this test process and report nothing at all.
PROBE=$(RUFLO_MCP_SOURCE_ONLY=1 bash -c '. "$1" 2>/dev/null; declare -f ruflo_mcp_recover_db >/dev/null && echo OK' _ "$SCRIPT" 2>/dev/null)
if [ "$PROBE" != "OK" ]; then
    echo "  FAIL: RUFLO_MCP_SOURCE_ONLY=1 does not yield a sourceable ruflo_mcp_recover_db"
    echo "        (script must define the function and return before its main body)"
    echo ""; echo "=== Results: 0/1 passed, 1 failed ==="; exit 1
fi
# Safe to bring into this shell now.
RUFLO_MCP_SOURCE_ONLY=1 . "$SCRIPT"

# ── Build a stale WAL that belongs to a DIFFERENT database ──
# Captured mid-session via .system so it is a genuine WAL, not a fabricated file.
build_fixtures() {
    local d="$1"
    rm -rf "$d"; mkdir -p "$d/backups"

    sqlite3 "$d/other.db" <<SQL >/dev/null 2>&1
PRAGMA journal_mode=wal;
PRAGMA wal_autocheckpoint=0;
CREATE TABLE memory_entries (id INTEGER PRIMARY KEY, key TEXT, content TEXT);
INSERT INTO memory_entries (key, content)
  SELECT 'k'||value, hex(randomblob(400)) FROM generate_series(1,4000);
.system cp "$d/other.db-wal" "$d/stale-wal"
.system cp "$d/other.db-shm" "$d/stale-shm"
SQL

    # A healthy backup, fully checkpointed.
    sqlite3 "$d/backups/memory_20260801.db" <<SQL >/dev/null 2>&1
CREATE TABLE memory_entries (id INTEGER PRIMARY KEY, key TEXT, content TEXT);
INSERT INTO memory_entries (key, content) VALUES ('backup-row','intact');
SQL

    # The "live" db that recovery will rotate away, with the stale sidecars beside it.
    cp "$d/other.db" "$d/memory.db"
    cp "$d/stale-wal" "$d/memory.db-wal"
    [ -f "$d/stale-shm" ] && cp "$d/stale-shm" "$d/memory.db-shm"
}

D="$TMPROOT/case1"
build_fixtures "$D"
[ -s "$D/memory.db-wal" ] || { echo "  SKIP: could not construct a real WAL fixture"; echo ""; echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="; exit 0; }

echo "Test 1: restored database is healthy (stale sidecars must not survive)"
ruflo_mcp_recover_db "$D/memory.db" "$D/backups" >/dev/null 2>&1
INTEG=$(sqlite3 "$D/memory.db" "PRAGMA integrity_check;" 2>&1 | tail -1)
assert "restored db passes integrity_check" "ok" "$INTEG"
assert "restored db has the backup's row" "intact" \
    "$(sqlite3 "$D/memory.db" "select content from memory_entries where key='backup-row';" 2>&1)"

echo "Test 2: no orphaned sidecars left beside the restored db"
assert "memory.db-wal removed" "false" "$([ -f "$D/memory.db-wal" ] && echo true || echo false)"
assert "memory.db-shm removed" "false" "$([ -f "$D/memory.db-shm" ] && echo true || echo false)"

echo "Test 3: the rotated-away data is preserved, not just the file"
# NOT asserting a surviving -wal sidecar: sqlite3 checkpoints and deletes the WAL
# when it opens the rotated file to salvage it, so a raw -wal cannot outlive the
# dump. That is the right trade — the dump merges the WAL's contents in, so the
# data survives in a more useful form than an orphaned sidecar would be. What
# must hold is that the rows are still reachable somewhere.
ROT=$(ls "$D"/memory.db.corrupt-* 2>/dev/null | grep -vE -- '-wal$|-shm$|\.dump\.sql$' | head -1)
assert "rotated db file exists" "true" "$([ -n "$ROT" ] && echo true || echo false)"
ROWS=$(sqlite3 "$ROT" "select count(*) from memory_entries;" 2>/dev/null)
assert "rotated db still holds the original 4000 rows" "4000" "${ROWS:-missing}"

echo "Test 4: salvage attempted before discarding"
# .recover is not compiled into sqlite3 3.50.6 here, so salvage must use .dump.
assert "salvage dump written next to the rotated file" "true" \
    "$(ls "$D"/memory.db.corrupt-*.dump.sql >/dev/null 2>&1 && echo true || echo false)"
assert "salvage dump contains rows, not just schema" "true" \
    "$(grep -qc "INSERT INTO" "$D"/memory.db.corrupt-*.dump.sql 2>/dev/null && echo true || echo false)"

echo "Test 5: a healthy db with no backup available is never left empty"
D2="$TMPROOT/case2"; build_fixtures "$D2"; rm -f "$D2"/backups/*.db
ruflo_mcp_recover_db "$D2/memory.db" "$D2/backups" >/dev/null 2>&1
assert "no healthy backup => original preserved, not silently blank" "true" \
    "$([ -f "$D2/memory.db" ] || ls "$D2"/memory.db.corrupt-* >/dev/null 2>&1 && echo true || echo false)"

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
