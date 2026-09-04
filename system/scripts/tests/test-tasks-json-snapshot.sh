#!/usr/bin/env bash
# Tests: system/scripts/tasks-json-snapshot.sh push|pull (t-3284, ADR-091
# decision 5). The script does not exist yet -- these tests fail until
# t-3287 implements it. Contract under test, per ADR-091:
#
#   push: copy the live canonical .claude/tasks.json (resolved the same way
#         find_tasks_file() resolves it -- git-common-dir first) into
#         system/state/tasks-snapshot.json (tracked) and commit. Must `git
#         add` ONLY the snapshot file -- NOT the whole system/state/
#         directory the way sync-state.sh's auto_commit_state does (that
#         pattern would sweep in unrelated dirty files under system/state/
#         and recreate the attribution problem this ADR exists to fix).
#   pull: reverse -- restore .claude/tasks.json from the last tracked
#         snapshot. Used by bootstrap.sh on a fresh clone.
#
# Fixture: an isolated git repo (not the real thebrana repo), so this test
# never touches real state.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
SNAPSHOT_SCRIPT="$REPO_ROOT/system/scripts/tasks-json-snapshot.sh"

PASS=0; FAIL=0; TOTAL=0
check() {
    local desc="$1" ok="$2" detail="${3:-}"
    TOTAL=$((TOTAL + 1))
    if [ "$ok" = "0" ]; then
        PASS=$((PASS + 1)); echo "  PASS: $desc"
    else
        FAIL=$((FAIL + 1)); echo "  FAIL: $desc${detail:+ — $detail}"
    fi
}

echo "tasks-json-snapshot.sh push/pull tests"
echo "========================================"
echo ""

echo "--- script exists and is executable ---"
check "tasks-json-snapshot.sh exists" "$([ -x "$SNAPSHOT_SCRIPT" ] && echo 0 || echo 1)" \
    "not found at $SNAPSHOT_SCRIPT — this is the RED state until t-3287 lands"

if [ ! -x "$SNAPSHOT_SCRIPT" ]; then
    echo ""
    echo "Results: $PASS passed, $FAIL failed, $TOTAL total (remaining checks skipped — script absent)"
    exit 1
fi

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

FIXTURE="$TMPDIR/repo"
mkdir -p "$FIXTURE/.claude" "$FIXTURE/system/state" "$FIXTURE/system/scripts"
git -C "$FIXTURE" init -q -b dev
git -C "$FIXTURE" config user.email test@test.com
git -C "$FIXTURE" config user.name test
cp "$SNAPSHOT_SCRIPT" "$FIXTURE/system/scripts/tasks-json-snapshot.sh"
chmod +x "$FIXTURE/system/scripts/tasks-json-snapshot.sh"

cat > "$FIXTURE/.claude/tasks.json" <<'JSON'
{"version":"1","project":"fixture","tasks":[{"id":"t-1","subject":"x","status":"pending","type":"task"}]}
JSON
git -C "$FIXTURE" add -A
git -C "$FIXTURE" commit -q -m "fixture init"

# An unrelated dirty file under system/state/ -- this is the attribution
# trap: a directory-wide `git add system/state/` at push time would sweep
# this in too.
echo "unrelated in-flight edit" > "$FIXTURE/system/state/unrelated.md"

echo ""
echo "--- push: snapshot file matches live tasks.json ---"
( cd "$FIXTURE" && ./system/scripts/tasks-json-snapshot.sh push ) >/dev/null 2>&1
SNAP="$FIXTURE/system/state/tasks-snapshot.json"
check "snapshot file created" "$([ -f "$SNAP" ] && echo 0 || echo 1)" "not created at $SNAP"
if [ -f "$SNAP" ]; then
    check "snapshot content matches live tasks.json" \
        "$(diff -q "$SNAP" "$FIXTURE/.claude/tasks.json" >/dev/null 2>&1 && echo 0 || echo 1)"
fi

echo ""
echo "--- push: commits only the snapshot file, not the whole system/state/ dir ---"
LAST_COMMIT_FILES=$(git -C "$FIXTURE" show --name-only --format="" HEAD 2>/dev/null)
check "snapshot file is in the last commit" \
    "$(echo "$LAST_COMMIT_FILES" | grep -qx "system/state/tasks-snapshot.json" && echo 0 || echo 1)"
check "unrelated dirty file was NOT swept into the snapshot commit" \
    "$(echo "$LAST_COMMIT_FILES" | grep -qx "system/state/unrelated.md" && echo 1 || echo 0)" \
    "unrelated.md appeared in the snapshot commit — push is git-add'ing the whole directory, not just the snapshot file"
check "unrelated dirty file is still uncommitted (untouched, not silently discarded either)" \
    "$(git -C "$FIXTURE" status --short system/state/unrelated.md | grep -q '^??' && echo 0 || echo 1)"

echo ""
echo "--- pull: restores .claude/tasks.json from the tracked snapshot ---"
ORIGINAL_CONTENT=$(cat "$FIXTURE/.claude/tasks.json")
rm -f "$FIXTURE/.claude/tasks.json"
( cd "$FIXTURE" && ./system/scripts/tasks-json-snapshot.sh pull ) >/dev/null 2>&1
check "tasks.json restored after pull" "$([ -f "$FIXTURE/.claude/tasks.json" ] && echo 0 || echo 1)"
if [ -f "$FIXTURE/.claude/tasks.json" ]; then
    RESTORED_CONTENT=$(cat "$FIXTURE/.claude/tasks.json")
    check "restored content matches the original" \
        "$([ "$RESTORED_CONTENT" = "$ORIGINAL_CONTENT" ] && echo 0 || echo 1)"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed, $TOTAL total"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
