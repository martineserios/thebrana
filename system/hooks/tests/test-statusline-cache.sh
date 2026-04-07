#!/usr/bin/env bash
# Tests for statusline cache (TSV written by post-tasks-validate.sh, read by statusline.sh)
# Validates the 6-field TSV format and build_step extraction.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/../post-tasks-validate.sh"
STATUSLINE="$SCRIPT_DIR/../../statusline.sh"
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
    # Wait for async cache write
    sleep 0.3
}

# ── Test 1: Cache TSV has 6 fields ──────────────────────
echo "=== Cache field count ==="

TASKS1="$TMPDIR/t1/.claude/tasks.json"
mkdir -p "$(dirname "$TASKS1")"
write_tasks "$TASKS1" \
    '{"id":"ph-1","subject":"Phase A: work","status":"in_progress","type":"phase","stream":"roadmap"}' \
    '{"id":"t-1","subject":"Do stuff","status":"in_progress","type":"task","stream":"roadmap","build_step":"BUILD"}'

run_hook "$TASKS1"
CACHE1="${TASKS1%.json}.statusline.tsv"

FIELD_COUNT=$(awk -F'\t' '{print NF}' "$CACHE1" 2>/dev/null)
assert_eq "cache has 6 TSV fields" "6" "$FIELD_COUNT"

# ── Test 2: build_step extracted when present ────────────
echo "=== build_step present ==="

BUILD_STEP=$(cut -f6 "$CACHE1" 2>/dev/null)
assert_eq "build_step is BUILD" "BUILD" "$BUILD_STEP"

# ── Test 3: build_step empty when not set ────────────────
echo "=== build_step absent ==="

TASKS2="$TMPDIR/t2/.claude/tasks.json"
mkdir -p "$(dirname "$TASKS2")"
write_tasks "$TASKS2" \
    '{"id":"ph-2","subject":"Phase B: other","status":"in_progress","type":"phase","stream":"roadmap"}' \
    '{"id":"t-2","subject":"No step","status":"in_progress","type":"task","stream":"roadmap"}'

run_hook "$TASKS2"
CACHE2="${TASKS2%.json}.statusline.tsv"

BUILD_STEP2=$(cut -f6 "$CACHE2" 2>/dev/null)
assert_eq "build_step is empty when not set" "" "$BUILD_STEP2"

# ── Test 4: build_step picks first in_progress task ──────
echo "=== build_step picks first in_progress ==="

TASKS3="$TMPDIR/t3/.claude/tasks.json"
mkdir -p "$(dirname "$TASKS3")"
write_tasks "$TASKS3" \
    '{"id":"ph-3","subject":"Phase C: multi","status":"in_progress","type":"phase","stream":"roadmap"}' \
    '{"id":"t-3","subject":"First","status":"in_progress","type":"task","stream":"roadmap","build_step":"SPECIFY"}' \
    '{"id":"t-4","subject":"Second","status":"in_progress","type":"task","stream":"roadmap","build_step":"TEST"}'

run_hook "$TASKS3"
CACHE3="${TASKS3%.json}.statusline.tsv"

BUILD_STEP3=$(cut -f6 "$CACHE3" 2>/dev/null)
assert_eq "build_step is SPECIFY (first in_progress)" "SPECIFY" "$BUILD_STEP3"

# ── Test 5: build_step ignores completed tasks ───────────
echo "=== build_step ignores completed ==="

TASKS4="$TMPDIR/t4/.claude/tasks.json"
mkdir -p "$(dirname "$TASKS4")"
write_tasks "$TASKS4" \
    '{"id":"ph-4","subject":"Phase D: mix","status":"in_progress","type":"phase","stream":"roadmap"}' \
    '{"id":"t-5","subject":"Done","status":"completed","type":"task","stream":"roadmap","build_step":"BUILD"}' \
    '{"id":"t-6","subject":"Active","status":"in_progress","type":"subtask","stream":"roadmap","build_step":"SHIP"}'

run_hook "$TASKS4"
CACHE4="${TASKS4%.json}.statusline.tsv"

BUILD_STEP4=$(cut -f6 "$CACHE4" 2>/dev/null)
assert_eq "build_step is SHIP (skips completed)" "SHIP" "$BUILD_STEP4"

# ── Test 6: jq fallback in statusline.sh produces 6 fields
echo "=== statusline jq fallback ==="

TASKS5="$TMPDIR/t5/.claude/tasks.json"
mkdir -p "$(dirname "$TASKS5")"
write_tasks "$TASKS5" \
    '{"id":"ph-5","subject":"Phase E: fallback","status":"in_progress","type":"phase","stream":"roadmap"}' \
    '{"id":"t-7","subject":"Fallback test","status":"in_progress","type":"task","stream":"roadmap","build_step":"VERIFY"}'

FALLBACK_FIELDS=$(jq -r '[
    ([.tasks[] | select(.type == "phase" and .status == "in_progress")] | first | .subject // "" | split(":") | first | ltrimstr("Phase ") // ""),
    ([.tasks[] | select((.type == "task" or .type == "subtask") and .status == "completed")] | length),
    ([.tasks[] | select(.type == "task" or .type == "subtask")] | length),
    ([.tasks[] | select(.status == "in_progress" and (.type == "task" or .type == "subtask"))] | first | .subject // ""),
    ([.tasks[] | select(.stream == "bugs" and .status != "completed" and .status != "cancelled")] | length),
    ([.tasks[] | select(.status == "in_progress" and (.type == "task" or .type == "subtask"))] | first | .build_step // "")
  ] | @tsv' "$TASKS5" 2>/dev/null)

FALLBACK_COUNT=$(echo "$FALLBACK_FIELDS" | awk -F'\t' '{print NF}')
assert_eq "jq fallback produces 6 fields" "6" "$FALLBACK_COUNT"

FALLBACK_STEP=$(echo "$FALLBACK_FIELDS" | cut -f6)
assert_eq "jq fallback extracts build_step VERIFY" "VERIFY" "$FALLBACK_STEP"

# ── Summary ─────────────────────────────────────────────
echo ""
echo "Results: ${PASS}/${TOTAL} passed, ${FAIL} failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
