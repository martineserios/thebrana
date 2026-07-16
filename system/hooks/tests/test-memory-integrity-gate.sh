#!/usr/bin/env bash
# Tests for integrity-gated ruflo memory backup/restore (t-2236, t-2260).
#
# Bug (t-2236): backup-memory.sh and ruflo-mcp.sh only treated a 0-BYTE file as
# corrupt. Real corruption is a malformed PAGE in a normal-sized file, so a
# corrupt DB sailed through every guard: it got backed up (poisoning the
# backup set) and restored (the restore-newest logic picked a corrupt
# backup). The fix gated both backup and restore on `PRAGMA integrity_check`.
#
# Bug (t-2260): that gate unconditionally SKIPPED the check whenever a
# .db-wal sidecar existed, to dodge a false-positive on a live WAL reader.
# ruflo's MCP server keeps a .db-wal present most of the time, so the gate
# was skipped on most days — a real corrupt DB got copied into the backup
# set unchecked for 10 straight days. The fix: when .db-wal is present,
# checkpoint a COPY of the db+wal pair (never the live files) and integrity
# check the copy — this still avoids the live-writer false-positive while
# actually catching real corruption under a live WAL.
#
# These tests fail against the pre-fix scripts and pass after the fix.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$SCRIPT_DIR/../../scripts"
BACKUP_SH="$SCRIPTS_DIR/backup-memory.sh"
RUFLO_SH="$SCRIPTS_DIR/ruflo-mcp.sh"
PASS=0
FAIL=0

assert_pass() { echo "  PASS: $1"; ((PASS++)); }
assert_fail() { echo "  FAIL: $1 — $2"; ((FAIL++)); }

if ! command -v sqlite3 >/dev/null 2>&1; then
    echo "SKIP: sqlite3 not installed — cannot test integrity gates"
    exit 0
fi

# --- helpers ----------------------------------------------------------------
make_valid_db() {  # $1 = path
    rm -f "$1"
    sqlite3 "$1" "CREATE TABLE t(x TEXT); WITH RECURSIVE c(n) AS (SELECT 1 UNION ALL SELECT n+1 FROM c WHERE n<1000) INSERT INTO t SELECT 'row-'||n FROM c;"
}
make_corrupt_db() {  # $1 = path — non-zero file that fails integrity_check
    make_valid_db "$1"
    # Clobber a btree page (page 2 starts at offset 4096) to force a malformed
    # page while keeping the file multi-KB and the header intact.
    dd if=/dev/urandom of="$1" bs=1 seek=4096 count=400 conv=notrunc status=none
}
is_ok() { sqlite3 "$1" "PRAGMA integrity_check;" 2>/dev/null | grep -q '^ok$'; }

TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT

echo "memory integrity-gate Tests (t-2236)"
echo "===================================="

# Sanity: the corrupt-db generator actually produces a non-zero, malformed DB.
SANITY="$TMPROOT/sanity.db"
make_corrupt_db "$SANITY"
if [ -s "$SANITY" ] && ! is_ok "$SANITY"; then
    assert_pass "fixture: corrupt DB is non-zero and fails integrity_check"
else
    assert_fail "fixture: corrupt DB is non-zero and fails integrity_check" \
        "size=$(stat -c%s "$SANITY" 2>/dev/null) integrity=$(sqlite3 "$SANITY" 'PRAGMA integrity_check;' 2>&1 | head -1)"
fi

# --- Test 1: backup-memory.sh refuses to back up a corrupt (non-zero) DB ----
echo ""
echo "Test 1: backup refuses corrupt non-zero DB"
T1="$TMPROOT/t1"; mkdir -p "$T1/swarm/backups"
make_corrupt_db "$T1/swarm/memory.db"
HOME="$T1" RUFLO_DATA_DIR="$T1/swarm" bash "$BACKUP_SH" backup >/dev/null 2>&1 || true
if find "$T1/swarm/backups" -name 'memory_*.db' | grep -q .; then
    assert_fail "backup skips corrupt DB" "a backup was written from a corrupt source DB"
else
    assert_pass "backup skips corrupt DB"
fi

# --- Test 2: restore selects newest CLEAN backup, skipping a corrupt newest --
echo ""
echo "Test 2: restore picks newest clean backup"
T2="$TMPROOT/t2"; mkdir -p "$T2/swarm/backups"
make_valid_db   "$T2/swarm/backups/memory_20260101.db"   # older, clean
make_corrupt_db "$T2/swarm/backups/memory_20260201.db"   # newer, corrupt
sleep 0.01; touch "$T2/swarm/backups/memory_20260201.db" # ensure it's newest by mtime too
HOME="$T2" RUFLO_DATA_DIR="$T2/swarm" bash "$BACKUP_SH" --restore >/dev/null 2>&1 || true
if [ -f "$T2/swarm/memory.db" ] && is_ok "$T2/swarm/memory.db"; then
    assert_pass "restore yields a healthy DB (skipped corrupt newest)"
else
    assert_fail "restore yields a healthy DB (skipped corrupt newest)" \
        "restored DB missing or still corrupt"
fi

# --- Test 3: ruflo-mcp.sh restore recovers from corrupt live DB --------------
echo ""
echo "Test 3: ruflo-mcp restore picks a clean backup"
T3="$TMPROOT/t3"; mkdir -p "$T3/.swarm/backups" "$T3/bin"
make_corrupt_db "$T3/.swarm/memory.db"                    # corrupt live DB
make_valid_db   "$T3/.swarm/backups/memory_20260101.db"  # older, clean
make_corrupt_db "$T3/.swarm/backups/memory_20260201.db"  # newer, corrupt (the trap)
sleep 0.01; touch "$T3/.swarm/backups/memory_20260201.db"
printf '#!/usr/bin/env bash\nexit 0\n' > "$T3/bin/ruflo"; chmod +x "$T3/bin/ruflo"
# HOME has no .nvm, so the wrapper resolves ruflo from PATH (our stub).
HOME="$T3" PATH="$T3/bin:$PATH" bash "$RUFLO_SH" mcp start >/dev/null 2>&1 || true
if [ -f "$T3/.swarm/memory.db" ] && is_ok "$T3/.swarm/memory.db"; then
    assert_pass "ruflo-mcp restored a healthy DB"
else
    assert_fail "ruflo-mcp restored a healthy DB" "live DB still corrupt after wrapper ran"
fi

# --- Test 4: ruflo-mcp.sh catches real corruption even with .db-wal present --
# t-2260: the OLD gate skipped the check outright whenever .db-wal existed —
# this fixture is genuinely corrupt (clobbered page) and must now be caught.
echo ""
echo "Test 4: ruflo-mcp catches real corruption despite a live .db-wal sidecar"
T4="$TMPROOT/t4"; mkdir -p "$T4/.swarm/backups" "$T4/bin"
make_corrupt_db "$T4/.swarm/memory.db"
touch "$T4/.swarm/memory.db-wal"
printf '#!/usr/bin/env bash\nexit 0\n' > "$T4/bin/ruflo"; chmod +x "$T4/bin/ruflo"
HOME="$T4" PATH="$T4/bin:$PATH" bash "$RUFLO_SH" mcp start >/dev/null 2>&1 || true
if [ -f "$T4/.swarm/memory.db.corrupt-$(date +%Y-%m-%d)" ]; then
    assert_pass "corrupt DB quarantined despite live .db-wal sidecar (t-2260 gap closed)"
else
    assert_fail "corrupt DB quarantined despite live .db-wal sidecar (t-2260 gap closed)" \
        "corrupt DB was left in place — the WAL-present skip loophole is still open"
fi

# --- Test 5: backup-memory.sh refuses corruption even with .db-wal present ---
echo ""
echo "Test 5: backup-memory.sh refuses corrupt DB despite a live .db-wal sidecar"
T5="$TMPROOT/t5"; mkdir -p "$T5/swarm/backups"
make_corrupt_db "$T5/swarm/memory.db"
touch "$T5/swarm/memory.db-wal"
HOME="$T5" RUFLO_DATA_DIR="$T5/swarm" bash "$BACKUP_SH" backup >/dev/null 2>&1 || true
if find "$T5/swarm/backups" -name 'memory_*.db' | grep -q .; then
    assert_fail "backup refuses corrupt DB despite live .db-wal sidecar" \
        "a backup was written from a corrupt source DB while .db-wal was present"
else
    assert_pass "backup refuses corrupt DB despite live .db-wal sidecar"
fi

# --- Test 6: genuinely busy WAL with VALID data is still not a false positive
# Regression guard for the original t-2236 concern: a real concurrent writer
# holding an uncommitted transaction (real WAL frames, valid underlying data)
# must not get treated as corrupt just because .db-wal exists.
echo ""
echo "Test 6: valid DB with a genuinely busy WAL still backs up (no false positive)"
T6="$TMPROOT/t6"; mkdir -p "$T6/swarm/backups"
make_valid_db "$T6/swarm/memory.db"
sqlite3 "$T6/swarm/memory.db" "PRAGMA journal_mode=WAL;" >/dev/null
FIFO="$TMPROOT/t6.fifo"
mkfifo "$FIFO"
( { printf 'BEGIN;\n'; printf "INSERT INTO t VALUES('pending-uncommitted');\n"; sleep 0.5; printf 'COMMIT;\n'; } > "$FIFO" ) &
FEEDER_PID=$!
sqlite3 "$T6/swarm/memory.db" < "$FIFO" >/dev/null 2>&1 &
SQLITE_PID=$!
sleep 0.2
if [ ! -f "$T6/swarm/memory.db-wal" ]; then
    assert_fail "fixture: busy WAL sidecar exists" "no -wal file appeared after BEGIN+INSERT"
else
    HOME="$T6" RUFLO_DATA_DIR="$T6/swarm" bash "$BACKUP_SH" backup >/dev/null 2>&1 || true
    if find "$T6/swarm/backups" -name 'memory_*.db' | grep -q .; then
        assert_pass "valid DB with busy WAL still backs up (no false positive)"
    else
        assert_fail "valid DB with busy WAL still backs up (no false positive)" \
            "backup was skipped even though the underlying data is valid"
    fi
fi
wait "$FEEDER_PID" "$SQLITE_PID" 2>/dev/null

# --- Summary ----------------------------------------------------------------
echo ""
echo "===================================="
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1
exit 0
