#!/usr/bin/env bash
# Tests: system/scripts/tasks-json-merge.sh — custom merge driver for .claude/tasks.json
# Verifies that task statuses are never downgraded during a git merge.
# Pattern: tasks-json-wip-lost-on-merge-theirs (t-2132)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRIVER="$SCRIPT_DIR/../../scripts/tasks-json-merge.sh"
PASS=0
FAIL=0
TOTAL=0
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

check() {
    local desc="$1" expected="$2" actual="$3"
    TOTAL=$((TOTAL + 1))
    if [ "$expected" = "$actual" ]; then
        PASS=$((PASS + 1))
        echo "  PASS: $desc"
    else
        FAIL=$((FAIL + 1))
        echo "  FAIL: $desc"
        echo "    expected: $expected"
        echo "    actual:   $actual"
    fi
}

echo "tasks-json merge driver tests"
echo "============================="
echo ""

# Prereq: driver script exists and is executable
TOTAL=$((TOTAL + 1))
if [ -x "$DRIVER" ]; then
    PASS=$((PASS + 1))
    echo "  PASS: driver script exists and is executable"
else
    FAIL=$((FAIL + 1))
    echo "  FAIL: driver script missing or not executable ($DRIVER)"
    echo ""
    echo "test-tasks-json-merge: $PASS/$TOTAL passed, $FAIL failed"
    exit 1
fi

# ── helper ────────────────────────────────────────────────────────────────────

tasks_json() {
    local t1_status="$1" t2_status="$2"
    printf '{"version":1,"tasks":[{"id":"t-1","subject":"first","status":"%s","type":"task","kind":"fix"},{"id":"t-2","subject":"second","status":"%s","type":"task","kind":"feature"}]}\n' \
        "$t1_status" "$t2_status"
}

run_driver() {
    # Run the merge driver directly: ancestor ours theirs path
    local ancestor="$1" ours="$2" theirs="$3"
    bash "$DRIVER" "$ancestor" "$ours" "$theirs" ".claude/tasks.json"
}

# ── Test 1: completed + in_progress merge → completed wins ────────────────────
echo "Case 1: completed in ours, in_progress in theirs → completed preserved"
ANC="$TMPDIR/anc1.json"; OURS="$TMPDIR/ours1.json"; THEIRS="$TMPDIR/theirs1.json"
tasks_json "completed" "pending" > "$ANC"
tasks_json "completed" "in_progress" > "$OURS"
tasks_json "in_progress" "in_progress" > "$THEIRS"
cp "$OURS" "$OURS.bak"
run_driver "$ANC" "$OURS" "$THEIRS"
check "completed preserved over in_progress" \
    "completed" \
    "$(jq -r '.tasks[] | select(.id=="t-1") | .status' "$OURS" 2>/dev/null)"
check "in_progress preserved (theirs higher)" \
    "in_progress" \
    "$(jq -r '.tasks[] | select(.id=="t-2") | .status' "$OURS" 2>/dev/null)"

# ── Test 2: in_progress in ours, completed in theirs → completed wins ─────────
echo ""
echo "Case 2: in_progress in ours, completed in theirs → completed adopted"
ANC="$TMPDIR/anc2.json"; OURS="$TMPDIR/ours2.json"; THEIRS="$TMPDIR/theirs2.json"
tasks_json "pending" "pending" > "$ANC"
tasks_json "in_progress" "pending" > "$OURS"
tasks_json "completed" "pending" > "$THEIRS"
run_driver "$ANC" "$OURS" "$THEIRS"
check "completed from theirs adopted" \
    "completed" \
    "$(jq -r '.tasks[] | select(.id=="t-1") | .status' "$OURS" 2>/dev/null)"

# ── Test 3: both completed → completed stays ──────────────────────────────────
echo ""
echo "Case 3: both completed → completed stays"
ANC="$TMPDIR/anc3.json"; OURS="$TMPDIR/ours3.json"; THEIRS="$TMPDIR/theirs3.json"
tasks_json "completed" "completed" > "$ANC"
tasks_json "completed" "completed" > "$OURS"
tasks_json "completed" "completed" > "$THEIRS"
run_driver "$ANC" "$OURS" "$THEIRS"
check "completed stays completed" \
    "completed" \
    "$(jq -r '.tasks[] | select(.id=="t-1") | .status' "$OURS" 2>/dev/null)"

# ── Test 4: new task only in theirs → appears in merged ───────────────────────
echo ""
echo "Case 4: task only in theirs → appears in merged output"
ANC="$TMPDIR/anc4.json"; OURS="$TMPDIR/ours4.json"; THEIRS="$TMPDIR/theirs4.json"
printf '{"version":1,"tasks":[{"id":"t-1","subject":"first","status":"in_progress","type":"task","kind":"fix"}]}\n' > "$ANC"
printf '{"version":1,"tasks":[{"id":"t-1","subject":"first","status":"in_progress","type":"task","kind":"fix"}]}\n' > "$OURS"
printf '{"version":1,"tasks":[{"id":"t-1","subject":"first","status":"completed","type":"task","kind":"fix"},{"id":"t-99","subject":"new task","status":"pending","type":"task","kind":"feature"}]}\n' > "$THEIRS"
run_driver "$ANC" "$OURS" "$THEIRS"
check "new task from theirs appears in merged" \
    "pending" \
    "$(jq -r '.tasks[] | select(.id=="t-99") | .status' "$OURS" 2>/dev/null)"
check "existing task status also merged correctly" \
    "completed" \
    "$(jq -r '.tasks[] | select(.id=="t-1") | .status' "$OURS" 2>/dev/null)"

# ── Test 5: cancelled in theirs, completed in ours → completed wins ───────────
echo ""
echo "Case 5: completed in ours, cancelled in theirs → completed wins (completed > cancelled)"
ANC="$TMPDIR/anc5.json"; OURS="$TMPDIR/ours5.json"; THEIRS="$TMPDIR/theirs5.json"
tasks_json "in_progress" "pending" > "$ANC"
tasks_json "completed" "pending" > "$OURS"
tasks_json "cancelled" "pending" > "$THEIRS"
run_driver "$ANC" "$OURS" "$THEIRS"
check "completed beats cancelled" \
    "completed" \
    "$(jq -r '.tasks[] | select(.id=="t-1") | .status' "$OURS" 2>/dev/null)"

# ── Test 6: corrupt theirs → ours preserved unchanged ─────────────────────────
echo ""
echo "Case 6: corrupt theirs JSON → ours preserved"
ANC="$TMPDIR/anc6.json"; OURS="$TMPDIR/ours6.json"; THEIRS="$TMPDIR/theirs6.json"
tasks_json "completed" "in_progress" > "$ANC"
tasks_json "completed" "in_progress" > "$OURS"
printf '{not json\n' > "$THEIRS"
# Driver should exit non-zero on corrupt input (git falls back to conflict markers)
run_driver "$ANC" "$OURS" "$THEIRS" || true
# Ours should be unchanged (corrupt input = no modification to ours)
check "ours preserved on corrupt theirs" \
    "completed" \
    "$(jq -r '.tasks[] | select(.id=="t-1") | .status' "$OURS" 2>/dev/null)"

# ── Test 7: driver exits 0 for clean merge ────────────────────────────────────
echo ""
echo "Case 7: driver exit code"
ANC="$TMPDIR/anc7.json"; OURS="$TMPDIR/ours7.json"; THEIRS="$TMPDIR/theirs7.json"
tasks_json "in_progress" "pending" > "$ANC"
tasks_json "completed" "pending" > "$OURS"
tasks_json "in_progress" "pending" > "$THEIRS"
run_driver "$ANC" "$OURS" "$THEIRS"
EXIT=$?
check "driver exits 0 on clean merge" "0" "$EXIT"

echo ""
echo "test-tasks-json-merge: $PASS/$TOTAL passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
