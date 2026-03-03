#!/usr/bin/env bash
# Tests for post-tool-use.sh, post-tool-use-failure.sh, and session-end.sh
# Validates test/lint detection, outcome tagging, error categorization,
# cascade detection, correction/test-write detection, and flywheel metrics.
#
# TDD markers:
#   [BUG]     = tests expected to fail, exposing a known bug
#   [MISSING] = tests expected to fail, exposing missing coverage
#
set -euo pipefail

HOOKS_DIR="$(cd "$(dirname "$0")/../../system/hooks" && pwd)"
PASS=0
FAIL=0
XFAIL=0      # expected failures (known bugs / missing coverage)
XPASS=0       # unexpected passes (bug already fixed?)
SESSION_ID="test-$$"
SESSION_FILE="/tmp/brana-session-${SESSION_ID}.jsonl"

cleanup() { rm -f "$SESSION_FILE"; }
trap cleanup EXIT

assert_outcome() {
    local label="$1" expected="$2" actual="$3"
    if [ "$actual" = "$expected" ]; then
        PASS=$((PASS + 1))
        echo "  PASS: $label"
    else
        FAIL=$((FAIL + 1))
        echo "  FAIL: $label — expected '$expected', got '$actual'"
    fi
}

# assert_xfail: test expected to fail (known bug / missing feature).
# XFAIL if it fails as expected, XPASS if it unexpectedly passes.
assert_xfail() {
    local label="$1" expected="$2" actual="$3"
    if [ "$actual" = "$expected" ]; then
        XPASS=$((XPASS + 1))
        echo "  XPASS: $label (unexpectedly passed — bug fixed?)"
    else
        XFAIL=$((XFAIL + 1))
        echo "  XFAIL: $label — expected '$expected', got '$actual' (known)"
    fi
}

assert_field() {
    local label="$1" field="$2" expected="$3" file="$4"
    local actual
    actual=$(jq -r ".$field" "$file" 2>/dev/null | tail -1)
    if [ "$actual" = "$expected" ]; then
        PASS=$((PASS + 1))
        echo "  PASS: $label"
    else
        FAIL=$((FAIL + 1))
        echo "  FAIL: $label — expected $field='$expected', got '$actual'"
    fi
}

run_success_hook() {
    local tool="$1" detail="$2"
    rm -f "$SESSION_FILE"
    local input
    if [ "$tool" = "Bash" ]; then
        input=$(jq -n -c --arg sid "$SESSION_ID" --arg tool "$tool" \
            --arg cmd "$detail" \
            '{session_id: $sid, tool_name: $tool, tool_input: ({command: $cmd} | tostring)}')
    else
        input=$(jq -n -c --arg sid "$SESSION_ID" --arg tool "$tool" \
            --arg fp "$detail" \
            '{session_id: $sid, tool_name: $tool, tool_input: ({file_path: $fp} | tostring)}')
    fi
    echo "$input" | bash "$HOOKS_DIR/post-tool-use.sh" >/dev/null 2>&1
    jq -r '.outcome' "$SESSION_FILE" 2>/dev/null | tail -1
}

run_failure_hook() {
    local tool="$1" detail="$2"
    rm -f "$SESSION_FILE"
    local input
    if [ "$tool" = "Bash" ]; then
        input=$(jq -n -c --arg sid "$SESSION_ID" --arg tool "$tool" \
            --arg cmd "$detail" \
            '{session_id: $sid, tool_name: $tool, tool_input: ({command: $cmd} | tostring)}')
    else
        input=$(jq -n -c --arg sid "$SESSION_ID" --arg tool "$tool" \
            --arg fp "$detail" \
            '{session_id: $sid, tool_name: $tool, tool_input: ({file_path: $fp} | tostring)}')
    fi
    echo "$input" | bash "$HOOKS_DIR/post-tool-use-failure.sh" >/dev/null 2>&1
    jq -r '.outcome' "$SESSION_FILE" 2>/dev/null | tail -1
}

# Run failure hook WITHOUT clearing session file (for cascade/sequence tests)
run_failure_hook_append() {
    local tool="$1" detail="$2"
    local input
    if [ "$tool" = "Bash" ]; then
        input=$(jq -n -c --arg sid "$SESSION_ID" --arg tool "$tool" \
            --arg cmd "$detail" \
            '{session_id: $sid, tool_name: $tool, tool_input: ({command: $cmd} | tostring)}')
    else
        input=$(jq -n -c --arg sid "$SESSION_ID" --arg tool "$tool" \
            --arg fp "$detail" \
            '{session_id: $sid, tool_name: $tool, tool_input: ({file_path: $fp} | tostring)}')
    fi
    echo "$input" | bash "$HOOKS_DIR/post-tool-use-failure.sh" >/dev/null 2>&1
}

# Run success hook WITHOUT clearing session file (for sequence tests)
run_success_hook_append() {
    local tool="$1" detail="$2"
    local input
    if [ "$tool" = "Bash" ]; then
        input=$(jq -n -c --arg sid "$SESSION_ID" --arg tool "$tool" \
            --arg cmd "$detail" \
            '{session_id: $sid, tool_name: $tool, tool_input: ({command: $cmd} | tostring)}')
    else
        input=$(jq -n -c --arg sid "$SESSION_ID" --arg tool "$tool" \
            --arg fp "$detail" \
            '{session_id: $sid, tool_name: $tool, tool_input: ({file_path: $fp} | tostring)}')
    fi
    echo "$input" | bash "$HOOKS_DIR/post-tool-use.sh" >/dev/null 2>&1
}

# ═══════════════════════════════════════════════════════════════
# SECTION 1: post-tool-use.sh (success path)
# ═══════════════════════════════════════════════════════════════

echo "=== post-tool-use.sh (success path) ==="

echo ""
echo "--- Test runners → test-pass ---"
assert_outcome "npm test" "test-pass" "$(run_success_hook Bash "npm test")"
assert_outcome "npx jest" "test-pass" "$(run_success_hook Bash "npx jest")"
assert_outcome "npx vitest" "test-pass" "$(run_success_hook Bash "npx vitest")"
assert_outcome "npx mocha" "test-pass" "$(run_success_hook Bash "npx mocha")"
assert_outcome "bun test" "test-pass" "$(run_success_hook Bash "bun test")"
assert_outcome "pytest" "test-pass" "$(run_success_hook Bash "pytest")"
assert_outcome "python -m pytest" "test-pass" "$(run_success_hook Bash "python -m pytest")"
assert_outcome "cargo test" "test-pass" "$(run_success_hook Bash "cargo test")"
assert_outcome "go test" "test-pass" "$(run_success_hook Bash "go test ./...")"
assert_outcome "make test" "test-pass" "$(run_success_hook Bash "make test")"
assert_outcome "./validate.sh" "test-pass" "$(run_success_hook Bash "./validate.sh")"
# With flags
assert_outcome "npx jest --coverage" "test-pass" "$(run_success_hook Bash "npx jest --coverage")"
assert_outcome "pytest -v tests/" "test-pass" "$(run_success_hook Bash "pytest -v tests/")"

echo ""
echo "--- [MISSING] Runners not yet in regex ---"
assert_xfail "yarn test" "test-pass" "$(run_success_hook Bash "yarn test")"
assert_xfail "pnpm test" "test-pass" "$(run_success_hook Bash "pnpm test")"
assert_xfail "npm run test" "test-pass" "$(run_success_hook Bash "npm run test")"

echo ""
echo "--- Linters → lint-pass ---"
assert_outcome "eslint" "lint-pass" "$(run_success_hook Bash "eslint src/")"
assert_outcome "flake8" "lint-pass" "$(run_success_hook Bash "flake8 .")"
assert_outcome "ruff check" "lint-pass" "$(run_success_hook Bash "ruff check")"
assert_outcome "ruff check src/" "lint-pass" "$(run_success_hook Bash "ruff check src/")"
assert_outcome "pylint" "lint-pass" "$(run_success_hook Bash "pylint module.py")"
assert_outcome "cargo clippy" "lint-pass" "$(run_success_hook Bash "cargo clippy")"
assert_outcome "shellcheck" "lint-pass" "$(run_success_hook Bash "shellcheck script.sh")"
assert_outcome "biome check" "lint-pass" "$(run_success_hook Bash "biome check")"
assert_outcome "npm run lint" "lint-pass" "$(run_success_hook Bash "npm run lint")"
assert_outcome "npx eslint" "lint-pass" "$(run_success_hook Bash "npx eslint .")"

echo ""
echo "--- [BUG] ruff format false positive (challenger #2) ---"
assert_xfail "ruff format ≠ lint" "success" "$(run_success_hook Bash "ruff format src/")"

echo ""
echo "--- [MISSING] Linters not yet in regex ---"
assert_xfail "mypy" "lint-pass" "$(run_success_hook Bash "mypy src/")"
assert_xfail "tsc --noEmit" "lint-pass" "$(run_success_hook Bash "tsc --noEmit")"
assert_xfail "prettier --check" "lint-pass" "$(run_success_hook Bash "prettier --check src/")"

echo ""
echo "--- Regular commands → success ---"
assert_outcome "ls" "success" "$(run_success_hook Bash "ls -la")"
assert_outcome "git status" "success" "$(run_success_hook Bash "git status")"
assert_outcome "echo test" "success" "$(run_success_hook Bash "echo test")"

echo ""
echo "--- Non-Bash tools → success ---"
assert_outcome "Edit tool" "success" "$(run_success_hook Edit "/tmp/foo.txt")"
assert_outcome "Write tool" "success" "$(run_success_hook Write "/tmp/bar.txt")"

echo ""
echo "--- Correction detection (Edit same file twice) ---"
rm -f "$SESSION_FILE"
run_success_hook_append Edit "/tmp/foo.ts"
run_success_hook_append Edit "/tmp/foo.ts"
CORRECTION_OUTCOME=$(jq -r '.outcome' "$SESSION_FILE" | tail -1)
assert_outcome "2nd edit same file → correction" "correction" "$CORRECTION_OUTCOME"

echo ""
echo "--- Correction: different files → no correction ---"
rm -f "$SESSION_FILE"
run_success_hook_append Edit "/tmp/foo.ts"
run_success_hook_append Edit "/tmp/bar.ts"
NO_CORRECTION_OUTCOME=$(jq -r '.outcome' "$SESSION_FILE" | tail -1)
assert_outcome "different file → success" "success" "$NO_CORRECTION_OUTCOME"

echo ""
echo "--- Test-file detection (Edit test file) ---"
assert_outcome ".test.ts → test-write" "test-write" "$(run_success_hook Edit "/src/auth.test.ts")"
assert_outcome ".spec.js → test-write" "test-write" "$(run_success_hook Edit "/src/auth.spec.js")"
assert_outcome "/tests/auth.ts → test-write" "test-write" "$(run_success_hook Edit "/tests/auth.ts")"
assert_outcome "/test/auth.ts → test-write" "test-write" "$(run_success_hook Edit "/test/auth.ts")"
assert_outcome "test_auth.py → test-write" "test-write" "$(run_success_hook Edit "/src/test_auth.py")"
assert_outcome "_test.go → test-write" "test-write" "$(run_success_hook Edit "/src/auth_test.go")"
assert_outcome "regular file → success" "success" "$(run_success_hook Edit "/src/auth.ts")"

echo ""
echo "--- Test-write overrides correction ---"
rm -f "$SESSION_FILE"
run_success_hook_append Edit "/src/auth.test.ts"
run_success_hook_append Edit "/src/auth.test.ts"
TESTWRITE_OVERRIDE=$(jq -r '.outcome' "$SESSION_FILE" | tail -1)
assert_outcome "test file 2nd edit → test-write (not correction)" "test-write" "$TESTWRITE_OVERRIDE"

# ═══════════════════════════════════════════════════════════════
# SECTION 2: post-tool-use-failure.sh (failure path)
# ═══════════════════════════════════════════════════════════════

echo ""
echo "=== post-tool-use-failure.sh (failure path) ==="

echo ""
echo "--- Test commands → test-fail ---"
assert_outcome "npm test fail" "test-fail" "$(run_failure_hook Bash "npm test")"
assert_outcome "pytest fail" "test-fail" "$(run_failure_hook Bash "pytest")"
assert_outcome "cargo test fail" "test-fail" "$(run_failure_hook Bash "cargo test")"
assert_outcome "npx jest fail" "test-fail" "$(run_failure_hook Bash "npx jest")"
assert_outcome "go test fail" "test-fail" "$(run_failure_hook Bash "go test ./...")"

echo ""
echo "--- Lint commands → lint-fail ---"
assert_outcome "eslint fail" "lint-fail" "$(run_failure_hook Bash "eslint src/")"
assert_outcome "shellcheck fail" "lint-fail" "$(run_failure_hook Bash "shellcheck script.sh")"
assert_outcome "ruff check fail" "lint-fail" "$(run_failure_hook Bash "ruff check")"
assert_outcome "cargo clippy fail" "lint-fail" "$(run_failure_hook Bash "cargo clippy")"

echo ""
echo "--- [BUG] ruff format failure false positive (challenger #2) ---"
assert_xfail "ruff format fail ≠ lint-fail" "failure" "$(run_failure_hook Bash "ruff format src/")"

echo ""
echo "--- Regular commands → failure ---"
assert_outcome "ls fail" "failure" "$(run_failure_hook Bash "ls nonexistent")"
assert_outcome "git fail" "failure" "$(run_failure_hook Bash "git push")"

echo ""
echo "--- Non-Bash tools → failure ---"
assert_outcome "Edit fail" "failure" "$(run_failure_hook Edit "/tmp/foo.txt")"
assert_outcome "Write fail" "failure" "$(run_failure_hook Write "/tmp/bar.txt")"

echo ""
echo "--- Error categorization (error_cat field) ---"
rm -f "$SESSION_FILE"
run_failure_hook_append Edit "/tmp/foo.txt"
assert_field "Edit → edit-mismatch" "error_cat" "edit-mismatch" "$SESSION_FILE"

rm -f "$SESSION_FILE"
run_failure_hook_append Write "/tmp/bar.txt"
assert_field "Write → write-fail" "error_cat" "write-fail" "$SESSION_FILE"

rm -f "$SESSION_FILE"
run_failure_hook_append Bash "npm test"
assert_field "Bash test → test-fail" "error_cat" "test-fail" "$SESSION_FILE"

rm -f "$SESSION_FILE"
run_failure_hook_append Bash "eslint src/"
assert_field "Bash lint → lint-fail" "error_cat" "lint-fail" "$SESSION_FILE"

rm -f "$SESSION_FILE"
run_failure_hook_append Bash "ls nonexistent"
assert_field "Bash regular → command-fail" "error_cat" "command-fail" "$SESSION_FILE"

rm -f "$SESSION_FILE"
run_failure_hook_append WebFetch "https://example.com"
assert_field "WebFetch → network-fail" "error_cat" "network-fail" "$SESSION_FILE"

rm -f "$SESSION_FILE"
run_failure_hook_append WebSearch "query"
assert_field "WebSearch → network-fail" "error_cat" "network-fail" "$SESSION_FILE"

rm -f "$SESSION_FILE"
run_failure_hook_append Glob "/some/path"
assert_field "Other tool → tool-fail" "error_cat" "tool-fail" "$SESSION_FILE"

echo ""
echo "--- Cascade detection ---"

# 3 consecutive same-detail failures → cascade on 3rd
rm -f "$SESSION_FILE"
run_failure_hook_append Bash "npm test"
run_failure_hook_append Bash "npm test"
run_failure_hook_append Bash "npm test"
CASCADE_VAL=$(jq -r '.cascade' "$SESSION_FILE" | tail -1)
assert_outcome "3 consecutive → cascade=true" "true" "$CASCADE_VAL"

# First two should not have cascade
FIRST_CASCADE=$(jq -r '.cascade' "$SESSION_FILE" | head -1)
SECOND_CASCADE=$(jq -r '.cascade' "$SESSION_FILE" | sed -n '2p')
assert_outcome "1st failure → cascade=false" "false" "$FIRST_CASCADE"
assert_outcome "2nd failure → cascade=false" "false" "$SECOND_CASCADE"

# Interleaved → no cascade
rm -f "$SESSION_FILE"
run_failure_hook_append Bash "npm test"
run_failure_hook_append Bash "eslint src/"
run_failure_hook_append Bash "npm test"
INTERLEAVED_CASCADE=$(jq -r '.cascade' "$SESSION_FILE" | tail -1)
assert_outcome "interleaved → cascade=false" "false" "$INTERLEAVED_CASCADE"

# Empty session file → no cascade
rm -f "$SESSION_FILE"
run_failure_hook_append Bash "npm test"
FIRST_EVER_CASCADE=$(jq -r '.cascade' "$SESSION_FILE" | tail -1)
assert_outcome "first failure ever → cascade=false" "false" "$FIRST_EVER_CASCADE"

# ═══════════════════════════════════════════════════════════════
# SECTION 3: session-end.sh (flywheel metrics)
# ═══════════════════════════════════════════════════════════════

echo ""
echo "=== session-end.sh (flywheel metrics) ==="

echo ""
echo "--- Outcome counting ---"
rm -f "$SESSION_FILE"
TS=$(date +%s)
for outcome in test-pass test-pass test-fail lint-pass lint-fail success failure; do
    jq -n -c --argjson ts "$TS" --arg tool "Bash" --arg outcome "$outcome" --arg detail "cmd-$outcome" \
        '{ts: $ts, tool: $tool, outcome: $outcome, detail: $detail}' >> "$SESSION_FILE"
done
TEST_PASSES=$(grep -c '"outcome":"test-pass"' "$SESSION_FILE") || TEST_PASSES=0
TEST_FAILS=$(grep -c '"outcome":"test-fail"' "$SESSION_FILE") || TEST_FAILS=0
LINT_PASSES=$(grep -c '"outcome":"lint-pass"' "$SESSION_FILE") || LINT_PASSES=0
LINT_FAILS=$(grep -c '"outcome":"lint-fail"' "$SESSION_FILE") || LINT_FAILS=0
assert_outcome "test-pass count" "2" "$TEST_PASSES"
assert_outcome "test-fail count" "1" "$TEST_FAILS"
assert_outcome "lint-pass count" "1" "$LINT_PASSES"
assert_outcome "lint-fail count" "1" "$LINT_FAILS"

echo ""
echo "--- Rate formulas ---"
TEST_TOTAL=$((TEST_PASSES + TEST_FAILS))
if [ "$TEST_TOTAL" -gt 0 ]; then
    TEST_PASS_RATE=$(awk "BEGIN {printf \"%.2f\", $TEST_PASSES / $TEST_TOTAL}")
else
    TEST_PASS_RATE="N/A"
fi
LINT_TOTAL=$((LINT_PASSES + LINT_FAILS))
if [ "$LINT_TOTAL" -gt 0 ]; then
    LINT_PASS_RATE=$(awk "BEGIN {printf \"%.2f\", $LINT_PASSES / $LINT_TOTAL}")
else
    LINT_PASS_RATE="N/A"
fi
assert_outcome "test_pass_rate 2/3" "0.67" "$TEST_PASS_RATE"
assert_outcome "lint_pass_rate 1/2" "0.50" "$LINT_PASS_RATE"

echo ""
echo "--- Zero totals → N/A ---"
rm -f "$SESSION_FILE"
jq -n -c --argjson ts "$TS" --arg tool "Bash" --arg outcome "success" --arg detail "ls" \
    '{ts: $ts, tool: $tool, outcome: $outcome, detail: $detail}' >> "$SESSION_FILE"
ZERO_TEST_PASSES=$(grep -c '"outcome":"test-pass"' "$SESSION_FILE" 2>/dev/null) || ZERO_TEST_PASSES=0
ZERO_TEST_FAILS=$(grep -c '"outcome":"test-fail"' "$SESSION_FILE" 2>/dev/null) || ZERO_TEST_FAILS=0
ZERO_TOTAL=$((ZERO_TEST_PASSES + ZERO_TEST_FAILS))
if [ "$ZERO_TOTAL" -gt 0 ]; then
    ZERO_RATE=$(awk "BEGIN {printf \"%.2f\", $ZERO_TEST_PASSES / $ZERO_TOTAL}")
else
    ZERO_RATE="N/A"
fi
assert_outcome "zero tests → N/A" "N/A" "$ZERO_RATE"

echo ""
echo "--- Correction rate ---"
rm -f "$SESSION_FILE"
# 2 edits, 1 correction
jq -n -c --argjson ts "$TS" --arg tool "Edit" --arg outcome "success" --arg detail "/tmp/a.ts" \
    '{ts: $ts, tool: $tool, outcome: $outcome, detail: $detail}' >> "$SESSION_FILE"
jq -n -c --argjson ts "$TS" --arg tool "Edit" --arg outcome "correction" --arg detail "/tmp/a.ts" \
    '{ts: $ts, tool: $tool, outcome: $outcome, detail: $detail}' >> "$SESSION_FILE"
EDITS=$(jq -r 'select(.tool == "Edit" or .tool == "Write") | .tool' "$SESSION_FILE" 2>/dev/null | wc -l) || EDITS=0
CORRECTIONS=$(grep -c '"outcome":"correction"' "$SESSION_FILE" 2>/dev/null) || CORRECTIONS=0
CORR_RATE=$(awk "BEGIN {printf \"%.2f\", $CORRECTIONS / $EDITS}")
assert_outcome "correction_rate 1/2" "0.50" "$CORR_RATE"

echo ""
echo "--- Test write rate ---"
rm -f "$SESSION_FILE"
# 3 edits, 1 test-write
jq -n -c --argjson ts "$TS" --arg tool "Edit" --arg outcome "success" --arg detail "/src/a.ts" \
    '{ts: $ts, tool: $tool, outcome: $outcome, detail: $detail}' >> "$SESSION_FILE"
jq -n -c --argjson ts "$TS" --arg tool "Edit" --arg outcome "test-write" --arg detail "/src/a.test.ts" \
    '{ts: $ts, tool: $tool, outcome: $outcome, detail: $detail}' >> "$SESSION_FILE"
jq -n -c --argjson ts "$TS" --arg tool "Write" --arg outcome "success" --arg detail "/src/b.ts" \
    '{ts: $ts, tool: $tool, outcome: $outcome, detail: $detail}' >> "$SESSION_FILE"
TW_EDITS=$(jq -r 'select(.tool == "Edit" or .tool == "Write") | .tool' "$SESSION_FILE" 2>/dev/null | wc -l) || TW_EDITS=0
TW_WRITES=$(grep -c '"outcome":"test-write"' "$SESSION_FILE" 2>/dev/null) || TW_WRITES=0
TW_RATE=$(awk "BEGIN {printf \"%.2f\", $TW_WRITES / $TW_EDITS}")
assert_outcome "test_write_rate 1/3" "0.33" "$TW_RATE"

echo ""
echo "--- Cascade rate ---"
rm -f "$SESSION_FILE"
# 3 failures, 1 cascade
jq -n -c --argjson ts "$TS" --arg tool "Bash" --arg outcome "failure" --arg detail "npm test" \
    --arg error_cat "test-fail" --argjson cascade false \
    '{ts: $ts, tool: $tool, outcome: $outcome, detail: $detail, error_cat: $error_cat, cascade: $cascade}' >> "$SESSION_FILE"
jq -n -c --argjson ts "$TS" --arg tool "Bash" --arg outcome "failure" --arg detail "npm test" \
    --arg error_cat "test-fail" --argjson cascade false \
    '{ts: $ts, tool: $tool, outcome: $outcome, detail: $detail, error_cat: $error_cat, cascade: $cascade}' >> "$SESSION_FILE"
jq -n -c --argjson ts "$TS" --arg tool "Bash" --arg outcome "failure" --arg detail "npm test" \
    --arg error_cat "test-fail" --argjson cascade true \
    '{ts: $ts, tool: $tool, outcome: $outcome, detail: $detail, error_cat: $error_cat, cascade: $cascade}' >> "$SESSION_FILE"
CR_FAILURES=$(jq -r 'select(.outcome == "failure" or .outcome == "test-fail" or .outcome == "lint-fail") | .outcome' "$SESSION_FILE" 2>/dev/null | wc -l) || CR_FAILURES=0
CR_CASCADES=$(grep -c '"cascade":true' "$SESSION_FILE" 2>/dev/null) || CR_CASCADES=0
CR_RATE=$(awk "BEGIN {printf \"%.2f\", $CR_CASCADES / $CR_FAILURES}")
assert_outcome "cascade_rate 1/3" "0.33" "$CR_RATE"

echo ""
echo "--- Auto-fix state machine ---"
rm -f "$SESSION_FILE"
# Sequence: fail(npm test) → pass(npm test) = 1 fix
# Then: fail(eslint) → no matching success = 0 fix
jq -n -c --argjson ts "$TS" --arg tool "Bash" --arg outcome "test-fail" --arg detail "npm test" \
    '{ts: $ts, tool: $tool, outcome: $outcome, detail: $detail}' >> "$SESSION_FILE"
jq -n -c --argjson ts "$TS" --arg tool "Bash" --arg outcome "test-pass" --arg detail "npm test" \
    '{ts: $ts, tool: $tool, outcome: $outcome, detail: $detail}' >> "$SESSION_FILE"
jq -n -c --argjson ts "$TS" --arg tool "Bash" --arg outcome "lint-fail" --arg detail "eslint" \
    '{ts: $ts, tool: $tool, outcome: $outcome, detail: $detail}' >> "$SESSION_FILE"
# 2 failures, 1 auto-fix
AF_FAILURES=2
AF_FIXES=$(jq -r '[.outcome, .detail] | @tsv' "$SESSION_FILE" 2>/dev/null | awk '
    BEGIN { fixes=0 }
    /^failure\t/ { prev_fail[$2]=1 }
    /^test-fail\t/ { prev_fail[$2]=1 }
    /^lint-fail\t/ { prev_fail[$2]=1 }
    /^success\t/ { if ($2 in prev_fail) { fixes++; delete prev_fail[$2] } }
    /^correction\t/ { if ($2 in prev_fail) { fixes++; delete prev_fail[$2] } }
    /^test-pass\t/ { if ($2 in prev_fail) { fixes++; delete prev_fail[$2] } }
    /^lint-pass\t/ { if ($2 in prev_fail) { fixes++; delete prev_fail[$2] } }
    END { print fixes }
' 2>/dev/null) || AF_FIXES=0
AF_RATE=$(awk "BEGIN {printf \"%.2f\", $AF_FIXES / $AF_FAILURES}")
assert_outcome "auto_fix count" "1" "$AF_FIXES"
assert_outcome "auto_fix_rate 1/2" "0.50" "$AF_RATE"

echo ""
echo "--- Auto-fix: interleaved sequence ---"
rm -f "$SESSION_FILE"
# fail(A) → fail(B) → pass(A) → pass(B) = 2 fixes
jq -n -c --argjson ts "$TS" --arg tool "Bash" --arg outcome "test-fail" --arg detail "npm test" \
    '{ts: $ts, tool: $tool, outcome: $outcome, detail: $detail}' >> "$SESSION_FILE"
jq -n -c --argjson ts "$TS" --arg tool "Bash" --arg outcome "lint-fail" --arg detail "eslint" \
    '{ts: $ts, tool: $tool, outcome: $outcome, detail: $detail}' >> "$SESSION_FILE"
jq -n -c --argjson ts "$TS" --arg tool "Bash" --arg outcome "test-pass" --arg detail "npm test" \
    '{ts: $ts, tool: $tool, outcome: $outcome, detail: $detail}' >> "$SESSION_FILE"
jq -n -c --argjson ts "$TS" --arg tool "Bash" --arg outcome "lint-pass" --arg detail "eslint" \
    '{ts: $ts, tool: $tool, outcome: $outcome, detail: $detail}' >> "$SESSION_FILE"
AF2_FIXES=$(jq -r '[.outcome, .detail] | @tsv' "$SESSION_FILE" 2>/dev/null | awk '
    BEGIN { fixes=0 }
    /^failure\t/ { prev_fail[$2]=1 }
    /^test-fail\t/ { prev_fail[$2]=1 }
    /^lint-fail\t/ { prev_fail[$2]=1 }
    /^success\t/ { if ($2 in prev_fail) { fixes++; delete prev_fail[$2] } }
    /^correction\t/ { if ($2 in prev_fail) { fixes++; delete prev_fail[$2] } }
    /^test-pass\t/ { if ($2 in prev_fail) { fixes++; delete prev_fail[$2] } }
    /^lint-pass\t/ { if ($2 in prev_fail) { fixes++; delete prev_fail[$2] } }
    END { print fixes }
' 2>/dev/null) || AF2_FIXES=0
assert_outcome "interleaved auto_fix count" "2" "$AF2_FIXES"

echo ""
echo "--- Auto-fix: no failures → rate 0.00 ---"
rm -f "$SESSION_FILE"
jq -n -c --argjson ts "$TS" --arg tool "Bash" --arg outcome "success" --arg detail "ls" \
    '{ts: $ts, tool: $tool, outcome: $outcome, detail: $detail}' >> "$SESSION_FILE"
AF3_FAILURES=0
AF3_RATE="0.00"
assert_outcome "no failures → auto_fix_rate 0.00" "0.00" "$AF3_RATE"

echo ""
echo "--- Delegation count ---"
rm -f "$SESSION_FILE"
jq -n -c --argjson ts "$TS" --arg tool "Task" --arg outcome "success" --arg detail "spawn agent" \
    '{ts: $ts, tool: $tool, outcome: $outcome, detail: $detail}' >> "$SESSION_FILE"
jq -n -c --argjson ts "$TS" --arg tool "Task" --arg outcome "success" --arg detail "spawn agent 2" \
    '{ts: $ts, tool: $tool, outcome: $outcome, detail: $detail}' >> "$SESSION_FILE"
jq -n -c --argjson ts "$TS" --arg tool "Bash" --arg outcome "success" --arg detail "ls" \
    '{ts: $ts, tool: $tool, outcome: $outcome, detail: $detail}' >> "$SESSION_FILE"
DELEGATIONS=$(grep -c '"tool":"Task"' "$SESSION_FILE" 2>/dev/null) || DELEGATIONS=0
assert_outcome "delegation_count" "2" "$DELEGATIONS"

# ═══════════════════════════════════════════════════════════════
# Results
# ═══════════════════════════════════════════════════════════════

echo ""
echo "═══════════════════════════════════════════"
echo "Results: $PASS passed, $FAIL failed, $XFAIL expected-fail, $XPASS unexpected-pass"
echo "═══════════════════════════════════════════"

if [ "$XFAIL" -gt 0 ]; then
    echo ""
    echo "Expected failures (known bugs / missing features):"
    echo "  - ruff format classified as lint (challenger bug #2)"
    echo "  - Missing runners: yarn test, pnpm test, npm run test"
    echo "  - Missing linters: mypy, tsc --noEmit, prettier --check"
fi

if [ "$XPASS" -gt 0 ]; then
    echo ""
    echo "WARNING: $XPASS tests passed unexpectedly — bugs may have been fixed already."
    echo "Convert assert_xfail → assert_outcome for these tests."
fi

# Exit 0 if only expected failures, exit 1 if unexpected failures
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
