#!/usr/bin/env bash
# Tests for system/scripts/tasks-json-backup.sh (ADR-094 / t-3326 interim hourly backup).
# Isolated: scratch git repo + scratch TASKS_JSON_BACKUP_DIR; never touches the real ledger.
set -uo pipefail

PASS=0; FAIL=0
assert_true() { local d="$1" c="$2"; if [ "$c" = "true" ]; then echo "  PASS: $d"; PASS=$((PASS+1)); else echo "  FAIL: $d"; FAIL=$((FAIL+1)); fi; }

REPO_ROOT=$(git rev-parse --show-toplevel)
SCRIPT="$REPO_ROOT/system/scripts/tasks-json-backup.sh"
[ -f "$SCRIPT" ] || { echo "ERROR: $SCRIPT missing"; exit 1; }

T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
export TASKS_JSON_BACKUP_DIR="$T/backups"
R="$T/repo"; mkdir -p "$R/.claude"; git -C "$T" init -q "$R"
ledger() { printf '{"tasks":[%s]}' "$1" > "$R/.claude/tasks.json"; }
three='{"id":"t-1"},{"id":"t-2"},{"id":"t-3"}'

echo "=== tasks-json-backup.sh ==="

# 1. first backup lands under <root>/<slug>/ with the task count reported
ledger "$three"
OUT=$(bash "$SCRIPT" --repo "$R" 2>&1); rc=$?
assert_true "backup exits 0 and reports 3 tasks"       "$([ $rc -eq 0 ] && echo "$OUT" | grep -q '(3 tasks)' && echo true || echo false)"
assert_true "backup file created under <dir>/repo/"    "$([ "$(ls "$T/backups/repo"/tasks.json.*.json 2>/dev/null | wc -l)" -eq 1 ] && echo true || echo false)"

# 2. rotation keeps only MAX_BACKUPS newest
for i in 1 2 3 4; do sleep 1; MAX_BACKUPS=3 bash "$SCRIPT" --repo "$R" >/dev/null 2>&1; done
assert_true "rotation keeps MAX_BACKUPS=3 newest"      "$([ "$(ls "$T/backups/repo"/tasks.json.*.json | wc -l)" -eq 3 ] && echo true || echo false)"

# 3. a wiped ledger (0 tasks) must be REFUSED and must not rotate good copies out
ledger ""
before=$(ls "$T/backups/repo"/tasks.json.*.json | wc -l)
OUT=$(MAX_BACKUPS=3 bash "$SCRIPT" --repo "$R" 2>&1); rc=$?
assert_true "wiped ledger is refused (exit 2)"          "$([ $rc -eq 2 ] && echo "$OUT" | grep -q REFUSED && echo true || echo false)"
assert_true "good backups untouched after refusal"      "$([ "$(ls "$T/backups/repo"/tasks.json.*.json | wc -l)" -eq "$before" ] && echo true || echo false)"

# 4. --check flags the collapse with exit 2
bash "$SCRIPT" --check --repo "$R" >/dev/null 2>&1; rc=$?
assert_true "--check exits 2 on collapse"               "$([ $rc -eq 2 ] && echo true || echo false)"

# 5. --restore --latest brings the 3-task ledger back and keeps the wiped copy aside
bash "$SCRIPT" --restore --latest --repo "$R" >/dev/null 2>&1; rc=$?
n=$(python3 -c 'import json;print(len(json.load(open("'"$R"'/.claude/tasks.json"))["tasks"]))')
assert_true "--restore --latest restores 3 tasks"       "$([ $rc -eq 0 ] && [ "$n" -eq 3 ] && echo true || echo false)"
assert_true "pre-restore copy of the wiped ledger kept" "$(ls "$R/.claude"/tasks.json.pre-restore.* >/dev/null 2>&1 && echo true || echo false)"

# 6. invalid JSON source is refused
echo 'not json' > "$R/.claude/tasks.json"
bash "$SCRIPT" --repo "$R" >/dev/null 2>&1; rc=$?
assert_true "invalid JSON ledger is refused (exit 2)"   "$([ $rc -eq 2 ] && echo true || echo false)"

# 7. missing ledger is refused, --list still works
rm -f "$R/.claude/tasks.json"
bash "$SCRIPT" --repo "$R" >/dev/null 2>&1; rc=$?
assert_true "missing ledger is refused (exit 2)"        "$([ $rc -eq 2 ] && echo true || echo false)"
# capture first, then grep — `cmd | grep -q` under pipefail reports SIGPIPE as failure once
# grep closes the pipe after the first of several lines (validate.sh Check 32 class)
LIST_OUT=$(bash "$SCRIPT" --list --repo "$R" 2>&1)
assert_true "--list prints backups"                     "$(printf '%s\n' "$LIST_OUT" | grep -c 'tasks.json\.' | grep -qv '^0$' && echo true || echo false)"

# 8. prefers the ADR-094 location when it exists
ledger "$three"; mkdir -p "$R/.git/brana"; printf '{"tasks":[{"id":"t-1"}]}' > "$R/.git/brana/tasks.json"
OUT=$(bash "$SCRIPT" --repo "$R" 2>&1)
assert_true "prefers .git/brana/tasks.json once it exists" "$(echo "$OUT" | grep -q '/.git/brana/tasks.json (1 tasks)' && echo true || echo false)"

echo ""; echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
