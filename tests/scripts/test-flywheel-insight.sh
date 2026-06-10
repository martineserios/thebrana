#!/usr/bin/env bash
# Tests for flywheel-insight.sh (t-1937).
#
# 527 flywheel:* rows were computed every session-end and never read
# (access_count=0 across the namespace — architecture review 2026-06-10 §4).
# flywheel-insight.sh is the read path: find the project's two most recent
# flywheel rows, read them via the sanctioned `memory retrieve` (which bumps
# access_count — the loop-closure metric), emit ONE observation line.
#
# Tests:
#   T1: script exists and is executable
#   T2: two-row fixture → observation contains latest correction_rate + trend vs prior
#   T3: empty fixture → graceful "no prior" line, exit 0
#   T4: session-start.sh wires flywheel-insight.sh as a job
#   T5: access_count > 0 on the latest row after one run (AC2, mechanically)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
INSIGHT="$REPO_ROOT/system/scripts/flywheel-insight.sh"
FIXTURE_DB="$(mktemp -u /tmp/t1937-fixture-XXXX.db)"

trap 'rm -f "$FIXTURE_DB"' EXIT

PASS=0; FAIL=0; TOTAL=0

assert_contains() {
    local desc="$1" needle="$2" haystack="$3"
    TOTAL=$((TOTAL+1))
    if [[ "$haystack" == *"$needle"* ]]; then
        PASS=$((PASS+1)); echo "  PASS: $desc"
    else
        FAIL=$((FAIL+1)); echo "  FAIL: $desc — '$needle' not in: $haystack"
    fi
}

make_fixture() {
    rm -f "$FIXTURE_DB"
    sqlite3 "$FIXTURE_DB" "CREATE TABLE memory_entries (
      id TEXT PRIMARY KEY, key TEXT NOT NULL, namespace TEXT DEFAULT 'default',
      content TEXT NOT NULL, type TEXT DEFAULT 'semantic', embedding TEXT,
      embedding_model TEXT DEFAULT 'local', embedding_dimensions INTEGER,
      tags TEXT, metadata TEXT, owner_id TEXT,
      created_at INTEGER NOT NULL DEFAULT (strftime('%s','now')*1000),
      updated_at INTEGER NOT NULL DEFAULT (strftime('%s','now')*1000),
      expires_at INTEGER, last_accessed_at INTEGER,
      access_count INTEGER DEFAULT 0, status TEXT DEFAULT 'active',
      UNIQUE(namespace, key));"
}

echo "=== flywheel-insight.sh (t-1937) ==="

# T1
TOTAL=$((TOTAL+1))
if [ -x "$INSIGHT" ]; then
    PASS=$((PASS+1)); echo "  PASS: T1: script exists and is executable"
else
    FAIL=$((FAIL+1)); echo "  FAIL: T1: $INSIGHT missing or not executable"
    echo ""; echo "$PASS/$TOTAL passed"; exit 1
fi

# T2 — two rows, distinct rates, latest must win and trend vs prior shown
make_fixture
sqlite3 "$FIXTURE_DB" "INSERT INTO memory_entries (id,key,namespace,content,created_at) VALUES
  ('a1','flywheel:testproj:older','metrics','{\"project\":\"testproj\",\"session\":\"older\",\"timestamp\":\"2026-06-08T10:00:00Z\",\"correction_rate\":\"0.10\",\"test_write_rate\":\"0.50\",\"edits\":7,\"failures\":1}',1000),
  ('a2','flywheel:testproj:newer','metrics','{\"project\":\"testproj\",\"session\":\"newer\",\"timestamp\":\"2026-06-09T10:00:00Z\",\"correction_rate\":\"0.30\",\"test_write_rate\":\"0.20\",\"edits\":12,\"failures\":0}',2000),
  ('a3','flywheel:otherproj:x','metrics','{\"project\":\"otherproj\",\"correction_rate\":\"0.99\"}',3000);"
OUT=$(bash "$INSIGHT" testproj "$FIXTURE_DB" 2>&1)
assert_contains "T2: latest correction_rate surfaced" "0.30" "$OUT"
assert_contains "T2b: prior rate shown for trend" "0.10" "$OUT"
assert_contains "T2c: edit count from latest session" "12" "$OUT"
TOTAL=$((TOTAL+1))
if [[ "$OUT" == *"0.99"* ]]; then
    FAIL=$((FAIL+1)); echo "  FAIL: T2d: other project's row leaked into observation"
else
    PASS=$((PASS+1)); echo "  PASS: T2d: project-scoped (no cross-project leak)"
fi

# T3 — empty DB
make_fixture
OUT=$(bash "$INSIGHT" testproj "$FIXTURE_DB" 2>&1); RC=$?
TOTAL=$((TOTAL+1))
if [ "$RC" -eq 0 ] && [[ "$OUT" == *"no prior"* || -z "$OUT" ]]; then
    PASS=$((PASS+1)); echo "  PASS: T3: empty DB handled gracefully (rc=0)"
else
    FAIL=$((FAIL+1)); echo "  FAIL: T3: rc=$RC out=$OUT"
fi

# T4 — session-start wiring
WIRE=$(grep -c "flywheel-insight" "$REPO_ROOT/system/hooks/session-start.sh" || true)
TOTAL=$((TOTAL+1))
if [ "${WIRE:-0}" -gt 0 ]; then
    PASS=$((PASS+1)); echo "  PASS: T4: session-start.sh wires flywheel-insight.sh"
else
    FAIL=$((FAIL+1)); echo "  FAIL: T4: session-start.sh does not reference flywheel-insight"
fi

# T5 — the read bumps access_count (the loop-closure metric, AC2)
make_fixture
sqlite3 "$FIXTURE_DB" "INSERT INTO memory_entries (id,key,namespace,content,created_at) VALUES
  ('b1','flywheel:testproj:only','metrics','{\"project\":\"testproj\",\"correction_rate\":\"0.15\",\"edits\":3,\"failures\":0}',1000);"
bash "$INSIGHT" testproj "$FIXTURE_DB" > /dev/null 2>&1
AC=$(sqlite3 "$FIXTURE_DB" "SELECT access_count FROM memory_entries WHERE id='b1';")
TOTAL=$((TOTAL+1))
if [ "${AC:-0}" -gt 0 ]; then
    PASS=$((PASS+1)); echo "  PASS: T5: access_count bumped by the read ($AC)"
else
    FAIL=$((FAIL+1)); echo "  FAIL: T5: access_count still $AC after read"
fi

echo ""
echo "$PASS/$TOTAL passed"
[ "$FAIL" -eq 0 ] || exit 1
