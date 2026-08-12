#!/usr/bin/env bash
# Integration tests for statusline end-to-end output.
#
# t-2470 (2026-07-27): this suite asserted a much richer statusline than
# system/statusline.sh renders — cache TSV reads, session score, build_step,
# bug counts, phase progress, job detection, knowledge freshness/decay,
# learning velocity and a two-line layout. 37 of its 74 assertions were
# permanently red, before and after any change, so the suite was useless as a
# regression signal. The script was deliberately simplified to a single line of
# model | project | branch | epic | CTX bar; the tests were never retired with
# it. Those scenarios are removed here rather than "fixed", because the
# features they cover no longer exist.
#
# Kept and corrected: the CTX assertions. CTX IS rendered — only its format
# changed (the bar now sits between the label and the percentage), so the
# literal "CTX 42%" needle was split in two rather than deleted.
#
# Negative assertions were added for the removed segments so the simplification
# itself is now under test.

# Tests the full pipeline: tasks.json → post-tasks-validate.sh (cache) → statusline.sh (render).
# Combines cache, width, and session score into realistic scenarios.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATUSLINE="$SCRIPT_DIR/../../statusline.sh"
HOOK="$SCRIPT_DIR/../post-tasks-validate.sh"
PASS=0
FAIL=0
TOTAL=0
TMPDIR=$(mktemp -d)

trap 'rm -rf "$TMPDIR"' EXIT

# ── Helpers ──────────────────────────────────────────────

assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    TOTAL=$((TOTAL + 1))
    if [ "$expected" = "$actual" ]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc"
        echo "    expected: $expected"
        echo "    got:      $actual"
        FAIL=$((FAIL + 1))
    fi
}

assert_contains() {
    local desc="$1" needle="$2" haystack="$3"
    TOTAL=$((TOTAL + 1))
    if [[ "$haystack" == *"$needle"* ]]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc"
        echo "    expected to contain: $needle"
        echo "    got: $haystack"
        FAIL=$((FAIL + 1))
    fi
}

assert_not_contains() {
    local desc="$1" needle="$2" haystack="$3"
    TOTAL=$((TOTAL + 1))
    if [[ "$haystack" != *"$needle"* ]]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc"
        echo "    expected NOT to contain: $needle"
        echo "    got: $haystack"
        FAIL=$((FAIL + 1))
    fi
}

strip_ansi() {
    echo -e "$1" | sed 's/\x1b\[[0-9;]*m//g'
}

visible_len() {
    printf '%s' "$(strip_ansi "$1")" | wc -m
}

# Max visible length across all lines in multi-line output
max_line_len() {
    local max=0
    while IFS= read -r line; do
        local len
        len=$(printf '%s' "$(echo "$line" | sed 's/\x1b\[[0-9;]*m//g')" | wc -m)
        (( len > max )) && max=$len
    done <<< "$(echo -e "$1")"
    echo "$max"
}

write_tasks() {
    local file="$1"; shift
    cat > "$file" <<'TASKS_HEAD'
{
  "version": "1.0",
  "project": "test",
  "last_modified": "2026-04-06T00:00:00Z",
  "tasks": [
TASKS_HEAD
    local first=true
    for task in "$@"; do
        $first || echo "," >> "$file"
        first=false
        echo "$task" >> "$file"
    done
    echo "]}" >> "$file"
}

run_hook() {
    local tasks_file="$1"
    local input
    input=$(printf '{"tool_name":"Write","tool_input":{"file_path":"%s"}}' "$tasks_file")
    echo "$input" | bash "$HOOK" 2>/dev/null
    sleep 0.3
}

make_statusline_input() {
    local cwd="$1"
    local session_id="${2:-}"
    local session_field=""
    [ -n "$session_id" ] && session_field="  \"session_id\": \"$session_id\","
    cat <<JSON
{
$session_field
  "model": {"display_name": "Haiku"},
  "workspace": {"current_dir": "$cwd", "project_dir": "$cwd"},
  "context_window": {"used_percentage": 42},
  "cost": {"total_lines_added": 100, "total_lines_removed": 20}
}
JSON
}

run_statusline() {
    local cwd="$1"
    shift
    local env_args=("$@")
    make_statusline_input "$cwd" | env "${env_args[@]}" bash "$STATUSLINE" 2>/dev/null
}


echo "Statusline Integration Tests"
echo "============================="
echo ""
echo "--- 1. Full render: the segments statusline.sh actually emits ---"

DIR1="$TMPDIR/int1"
mkdir -p "$DIR1/.claude"
cd "$DIR1" && git init -q && git commit --allow-empty -m "init" -q

write_tasks "$DIR1/.claude/tasks.json" \
    '{"id":"t-2","subject":"Add statusline segments","status":"in_progress","type":"task"}'

OUTPUT1=$(make_statusline_input "$DIR1" | env \
    BRANA_STATUSLINE_COLS=200 \
    bash "$STATUSLINE" 2>/dev/null)
STRIPPED1=$(strip_ansi "$OUTPUT1")

assert_contains "full: has model" "Haiku" "$STRIPPED1"
assert_contains "full: has project" "int1" "$STRIPPED1"
# CTX renders as "CTX <bar> NN%" — the bar sits between the label and the
# percentage, so these are two needles, not the literal "CTX 42%" (t-2470).
assert_contains "full: has CTX label" "CTX" "$STRIPPED1"
assert_contains "full: has CTX percentage" "42%" "$STRIPPED1"

# Retired segments must stay gone — these are the guards that keep the
# simplified statusline simple (t-2470).
assert_not_contains "full: no current-task segment" "Add statusline segments" "$STRIPPED1"
assert_not_contains "full: no build step" "[BUILD]" "$STRIPPED1"
assert_not_contains "full: no phase progress" "PhA" "$STRIPPED1"

echo ""
echo "--- 2. Single-line contract ---"
LINE_COUNT=$(printf '%s' "$OUTPUT1" | grep -c '' )
TOTAL=$((TOTAL + 1))
if [ "$LINE_COUNT" -eq 1 ]; then
    echo "  PASS: statusline renders exactly one line"
    PASS=$((PASS + 1))
else
    echo "  FAIL: expected 1 line, got $LINE_COUNT"
    FAIL=$((FAIL + 1))
fi

echo ""
echo "--- 3. Empty/missing state (no tasks, no cache, no score) ---"

DIR5="$TMPDIR/int5"
mkdir -p "$DIR5"
cd "$DIR5" && git init -q && git commit --allow-empty -m "init" -q

OUTPUT5=$(run_statusline "$DIR5" BRANA_STATUSLINE_COLS=200)
STRIPPED5=$(strip_ansi "$OUTPUT5")

assert_contains "empty: has model" "Haiku" "$STRIPPED5"
assert_contains "empty: has CTX label" "CTX" "$STRIPPED5"
assert_contains "empty: has CTX percentage" "42%" "$STRIPPED5"
assert_not_contains "empty: no phase info" "Ph" "$STRIPPED5"
assert_not_contains "empty: no session score" "S:" "$STRIPPED5"

EXIT5=$(make_statusline_input "$DIR5" | env \
    BRANA_STATUSLINE_COLS=200 \
    bash "$STATUSLINE" >/dev/null 2>&1; echo $?)
assert_eq "empty: exits cleanly" "0" "$EXIT5"

echo ""
echo "--- 4. Session-id segment (t-2731) ---"

DIR4="$TMPDIR/int4"
mkdir -p "$DIR4"
cd "$DIR4" && git init -q && git commit --allow-empty -m "init" -q

OUTPUT4=$(make_statusline_input "$DIR4" "e48d4fcb-1234-5678-9abc-def012345678" | env \
    BRANA_STATUSLINE_COLS=200 \
    bash "$STATUSLINE" 2>/dev/null)
STRIPPED4=$(strip_ansi "$OUTPUT4")

assert_contains "session: has short session id prefix" "e48d4fcb" "$STRIPPED4"
assert_not_contains "session: does not leak full uuid" "e48d4fcb-1234-5678-9abc-def012345678" "$STRIPPED4"

LINE_COUNT4=$(printf '%s' "$OUTPUT4" | grep -c '')
assert_eq "session: still single line" "1" "$LINE_COUNT4"

echo ""
echo "--- 5. Missing session id degrades gracefully ---"

OUTPUT5B=$(make_statusline_input "$DIR4" | env \
    BRANA_STATUSLINE_COLS=200 \
    bash "$STATUSLINE" 2>/dev/null)
STRIPPED5B=$(strip_ansi "$OUTPUT5B")

assert_not_contains "no-session: no dangling icon" "🪪" "$STRIPPED5B"
LINE_COUNT5B=$(printf '%s' "$OUTPUT5B" | grep -c '')
assert_eq "no-session: still single line, no crash" "1" "$LINE_COUNT5B"

EXIT5B=$(make_statusline_input "$DIR4" | env \
    BRANA_STATUSLINE_COLS=200 \
    bash "$STATUSLINE" >/dev/null 2>&1; echo $?)
assert_eq "no-session: exits cleanly" "0" "$EXIT5B"

echo ""
echo "Results: ${PASS}/${TOTAL} passed, ${FAIL} failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
