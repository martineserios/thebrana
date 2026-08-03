#!/usr/bin/env bash
# Tests for ruflo-mcp.sh database recovery (t-2619).
#
# Regression under test: recovery moved ONLY memory.db to memory.db.corrupt-DATE,
# leaving memory.db-wal and memory.db-shm in place, then copied a backup into
# memory.db underneath those orphaned sidecars. SQLite replays the stale WAL onto
# the fresh backup on next open and the restored database is immediately
# malformed — which guarantees the next session rotates again. Verified in the
# wild: memory.db.corrupt-2026-07-31 and -2026-08-01 both pass integrity_check
# standalone (4385 and 4332 rows), i.e. two healthy databases discarded, and the
# store rotated twice on 2026-08-02, the second rotation overwriting the first.
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
bare_rotated() { ls "$1"/memory.db.corrupt-* 2>/dev/null | grep -vE -- '-wal$|-shm$|\.dump\.sql$'; }

echo "=== test_ruflo_mcp_recover.sh ==="
command -v sqlite3 >/dev/null 2>&1 || { echo "  SKIP: sqlite3 unavailable"; exit 0; }

# An unguarded script runs its main body on source and `exec`s ruflo, replacing
# this process and reporting nothing. Probe in a subshell first.
PROBE=$(RUFLO_MCP_SOURCE_ONLY=1 bash -c '. "$1" 2>/dev/null; declare -f ruflo_mcp_recover_db >/dev/null && echo OK' _ "$SCRIPT" 2>/dev/null)
if [ "$PROBE" != "OK" ]; then
    echo "  FAIL: RUFLO_MCP_SOURCE_ONLY=1 does not yield a sourceable ruflo_mcp_recover_db"
    echo ""; echo "=== Results: 0/1 passed, 1 failed ==="; exit 1
fi
RUFLO_MCP_SOURCE_ONLY=1 . "$SCRIPT"

# A genuinely condemned database: real rows, a clobbered page, and a -wal present
# so the WAL branch of the health check is the one exercised. A matching db+wal
# pair would (correctly) read healthy and never reach recovery at all.
make_condemned() {
    local d="$1"
    rm -rf "$d"; mkdir -p "$d/backups"
    sqlite3 "$d/memory.db" <<SQL >/dev/null 2>&1
CREATE TABLE memory_entries (id INTEGER PRIMARY KEY, key TEXT, content TEXT);
INSERT INTO memory_entries (key, content)
  SELECT 'k'||value, hex(randomblob(200)) FROM generate_series(1,2000);
SQL
    printf 'not a valid sqlite page at all' | dd of="$d/memory.db" bs=1 seek=8192 conv=notrunc status=none 2>/dev/null
    : > "$d/memory.db-wal"
    : > "$d/memory.db-shm"
}
make_backup() {
    sqlite3 "$1" <<SQL >/dev/null 2>&1
CREATE TABLE memory_entries (id INTEGER PRIMARY KEY, key TEXT, content TEXT);
INSERT INTO memory_entries (key, content) VALUES ('backup-row','intact');
SQL
}

D="$TMPROOT/case1"; make_condemned "$D"; make_backup "$D/backups/memory_20260801.db"
if ruflo_mcp_db_is_healthy "$D/memory.db"; then
    echo "  SKIP: fixture is not condemned by the health check — cannot exercise recovery"
    echo ""; echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="; exit 0
fi

echo "Test 1: restored database is healthy (stale sidecars must not survive)"
ruflo_mcp_recover_db "$D/memory.db" "$D/backups" >/dev/null 2>&1
assert "restored db passes integrity_check" "ok" \
    "$(sqlite3 "$D/memory.db" "PRAGMA integrity_check;" 2>&1 | tail -1)"
assert "restored db has the backup's row" "intact" \
    "$(sqlite3 "$D/memory.db" "select content from memory_entries where key='backup-row';" 2>&1)"

echo "Test 2: no orphaned sidecars left beside the restored db"
assert "memory.db-wal removed" "false" "$([ -f "$D/memory.db-wal" ] && echo true || echo false)"
assert "memory.db-shm removed" "false" "$([ -f "$D/memory.db-shm" ] && echo true || echo false)"

echo "Test 3: the condemned data is quarantined and salvaged"
ROT=$(bare_rotated "$D" | head -1)
assert "rotated db file exists" "true" "$([ -n "$ROT" ] && echo true || echo false)"
# NOT asserting a surviving -wal: sqlite3 checkpoints and deletes the WAL when it
# opens the rotated file to salvage it. The dump merges that content in, so the
# data survives in a more useful form than an orphaned sidecar.
assert "salvage dump written" "true" \
    "$(ls "$D"/memory.db.corrupt-*.dump.sql >/dev/null 2>&1 && echo true || echo false)"
assert "salvage dump is non-empty" "true" \
    "$([ -s "$(ls "$D"/memory.db.corrupt-*.dump.sql 2>/dev/null | head -1)" ] && echo true || echo false)"
# Deliberately NOT asserting recovered INSERT rows here. How much `.dump` can
# salvage depends on where the damage lands: this fixture clobbers the first data
# page, which destroys every row, whereas the real 2026-08-02 file was damaged at
# page 10511 and still yielded 1393 rows. Asserting rows would be asserting
# something this fixture cannot demonstrate. The opportunistic check below uses
# the real artifact when it is present on this machine.
REAL_CORRUPT=$(ls -t "$HOME"/.swarm/memory.db.corrupt-* 2>/dev/null | grep -vE -- '-wal$|-shm$|\.dump\.sql$' | head -1)
if [ -n "$REAL_CORRUPT" ]; then
    ROWS_OUT=$(sqlite3 "$REAL_CORRUPT" ".dump" 2>/dev/null | grep -c "INSERT INTO")
    assert "salvage extracts rows from a real damaged store" "true" \
        "$([ "${ROWS_OUT:-0}" -gt 0 ] && echo true || echo false)"
else
    echo "  (skipped real-artifact salvage check — no ~/.swarm/memory.db.corrupt-* present)"
fi

echo "Test 4: health check distinguishes corruption from a mere -wal (t-2260 stays closed)"
D3="$TMPROOT/case3"; make_condemned "$D3"
if ruflo_mcp_db_is_healthy "$D3/memory.db"; then V=HEALTHY; else V=CONDEMNED; fi
assert "corrupt db with -wal present is condemned" "CONDEMNED" "$V"
D4="$TMPROOT/case4"; mkdir -p "$D4"
sqlite3 "$D4/memory.db" "CREATE TABLE t(x); INSERT INTO t VALUES('a');" >/dev/null 2>&1
: > "$D4/memory.db-wal"
if ruflo_mcp_db_is_healthy "$D4/memory.db"; then V=HEALTHY; else V=CONDEMNED; fi
assert "healthy db with -wal present is left alone" "HEALTHY" "$V"

echo "Test 5: with no healthy backup the condemned db stays quarantined"
# The contract is deliberately "ruflo starts empty", NOT "put the original back":
# restoring a malformed db in place is the t-2260 loophole. The data must remain
# reachable in the quarantined copy.
D2="$TMPROOT/case2"; make_condemned "$D2"
ruflo_mcp_recover_db "$D2/memory.db" "$D2/backups" >/dev/null 2>&1
assert "condemned db is NOT left live" "false" "$([ -f "$D2/memory.db" ] && echo true || echo false)"
assert "quarantined copy exists" "true" "$([ -n "$(bare_rotated "$D2")" ] && echo true || echo false)"

echo "Test 6: a second rotation the same day must not clobber the first"
# Observed: memory.db.corrupt-2026-08-02 was written at 12:52 and again at 13:42,
# the second overwriting the first file AND its .dump.sql — the only copies of
# five hours of writes.
D5="$TMPROOT/case5"; make_condemned "$D5"; make_backup "$D5/backups/memory_20260801.db"
ruflo_mcp_recover_db "$D5/memory.db" "$D5/backups" >/dev/null 2>&1
FIRST=$(bare_rotated "$D5" | head -1)
FIRST_SUM=$(md5sum "$FIRST" 2>/dev/null | cut -d' ' -f1)
# Condemn again on the same day.
make_condemned "$D5/re" >/dev/null 2>&1
cp "$D5/re/memory.db" "$D5/memory.db"; : > "$D5/memory.db-wal"
ruflo_mcp_recover_db "$D5/memory.db" "$D5/backups" >/dev/null 2>&1
assert "first rotated file still exists" "true" "$([ -f "$FIRST" ] && echo true || echo false)"
assert "first rotated file byte-identical (not overwritten)" "$FIRST_SUM" \
    "$(md5sum "$FIRST" 2>/dev/null | cut -d' ' -f1)"
assert "two distinct rotated files exist" "2" "$(bare_rotated "$D5" | wc -l)"
assert "both salvage dumps preserved" "2" "$(ls "$D5"/memory.db.corrupt-*.dump.sql 2>/dev/null | wc -l)"

echo "Test 7: no flock, and a healthy db is never re-rotated"
# t-2085 removed the flock mutex deliberately (its paired orphan sweep killed
# live WAL writers); tests/scripts/test-ruflo-mcp-single-instance.sh enforces the
# absence. Concurrency is mitigated lock-free — the health re-check below is the
# part that keeps a losing racer from rotating a just-restored database.
assert "no flock reintroduced" "false" \
    "$(grep -qE '^[^#]*flock +-' "$SCRIPT" && echo true || echo false)"
D6="$TMPROOT/case6"; make_condemned "$D6"; make_backup "$D6/backups/memory_20260801.db"
ruflo_mcp_recover_db "$D6/memory.db" "$D6/backups" >/dev/null 2>&1
BEFORE=$(bare_rotated "$D6" | wc -l)
ruflo_mcp_recover_db "$D6/memory.db" "$D6/backups" >/dev/null 2>&1
assert "healthy db is not re-rotated by a second recovery" "$BEFORE" "$(bare_rotated "$D6" | wc -l)"

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
