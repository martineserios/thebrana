#!/usr/bin/env bash
# t-2805: when backup-memory.sh's integrity_check fails, it must log the
# "ruflo mcp start" process count and the active daemon PIDs to a small,
# size-bounded log — forward-looking per-event proof for the memory.db
# corruption root cause (t-2802). Forced-failure test uses a corrupted COPY of
# a database under a temp RUFLO_DATA_DIR; the real memory.db is never touched.
set -uo pipefail

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/system/scripts/backup-memory.sh"
PASS=0
FAIL=0
ok()  { echo "  PASS: $1"; PASS=$((PASS + 1)); }
bad() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

command -v sqlite3 >/dev/null 2>&1 || { echo "SKIP: sqlite3 not available"; exit 0; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

DATA="$TMP/data"
mkdir -p "$DATA" "$TMP/bin"
DB="$DATA/memory.db"
LOG="$DATA/corruption-context.log"

# A valid multi-page DB, then corrupt a middle page so integrity_check fails
# while the file stays non-zero (the failure mode the 0-byte check misses).
sqlite3 "$DB" "CREATE TABLE t(id INTEGER PRIMARY KEY, v TEXT);
  WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i<3000)
  INSERT INTO t(v) SELECT hex(randomblob(64)) FROM n;"
dd if=/dev/urandom of="$DB" bs=1 count=512 seek=8192 conv=notrunc 2>/dev/null

if sqlite3 "$DB" "PRAGMA integrity_check;" 2>/dev/null | grep -q '^ok$'; then
    echo "SETUP FAIL: corruption did not break integrity_check"; exit 1
fi

# Stub ps: two live "ruflo mcp start" daemons, plus an unrelated process.
cat > "$TMP/bin/ps" <<'EOF'
#!/usr/bin/env bash
printf '  PID COMMAND\n'
printf ' 1234 node /x/ruflo mcp start\n'
printf ' 5678 node /x/ruflo mcp start --port 9\n'
printf ' 9999 sleep 60\n'
EOF
chmod +x "$TMP/bin/ps"

run_backup() { PATH="$TMP/bin:$PATH" RUFLO_DATA_DIR="$DATA" bash "$SCRIPT" backup >"$TMP/out" 2>&1; }

echo "=== Scenario 1: forced integrity failure writes process-count + PID entry ==="
run_backup
if [ -f "$LOG" ]; then ok "corruption-context.log created"; else bad "corruption-context.log not created"; fi
if grep -q "ruflo mcp start" "$LOG" 2>/dev/null; then ok "entry names 'ruflo mcp start'"; else bad "entry lacks 'ruflo mcp start'"; fi
if grep -qE "processes: 2\b" "$LOG" 2>/dev/null; then ok "process count is 2"; else bad "process count not 2 — got: $(cat "$LOG" 2>/dev/null)"; fi
if grep -q "1234" "$LOG" 2>/dev/null && grep -q "5678" "$LOG" 2>/dev/null; then ok "both daemon PIDs recorded"; else bad "daemon PIDs missing"; fi
if grep -q "9999" "$LOG" 2>/dev/null; then bad "unrelated PID leaked into log"; else ok "unrelated process not recorded"; fi
if ls "$DATA/backups"/memory_*.db >/dev/null 2>&1; then bad "corrupt DB was backed up"; else ok "corrupt DB not backed up (existing behaviour intact)"; fi

echo "=== Scenario 2: log is size-bounded (rotates) ==="
seq 1 5000 | sed 's/^/old-entry /' > "$LOG"
BEFORE=$(wc -l < "$LOG")
run_backup
AFTER=$(wc -l < "$LOG")
if [ "$AFTER" -lt "$BEFORE" ]; then ok "log shrank from $BEFORE to $AFTER lines"; else bad "log did not rotate ($BEFORE -> $AFTER)"; fi
if [ "$AFTER" -le 500 ]; then ok "log bounded at <=500 lines ($AFTER)"; else bad "log unbounded ($AFTER lines)"; fi
if grep -qE "processes: 2\b" "$LOG"; then ok "newest entry survives rotation"; else bad "newest entry lost in rotation"; fi

echo "=== Scenario 3: healthy DB writes no corruption entry ==="
rm -f "$LOG" "$DB"
sqlite3 "$DB" "CREATE TABLE t(x); INSERT INTO t VALUES (1);"
run_backup
if [ ! -f "$LOG" ]; then ok "no log for a healthy DB"; else bad "log written for a healthy DB"; fi

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
