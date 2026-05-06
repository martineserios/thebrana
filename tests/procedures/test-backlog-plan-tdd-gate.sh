#!/usr/bin/env bash
# Tests for /brana:backlog plan TDD gate (t-1032).
# Validates: step 11 gate text is hard-blocking, cannot be silently skipped.
#
# Run: bash tests/procedures/test-backlog-plan-tdd-gate.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
BACKLOG_PROC="$REPO_ROOT/system/procedures/backlog.md"

PASS=0
FAIL=0
TOTAL=0

assert_contains() {
    local desc="$1" needle="$2" file="$3"
    TOTAL=$((TOTAL + 1))
    if grep -q "$needle" "$file" 2>/dev/null; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc (pattern '$needle' not found in $(basename "$file"))"
        FAIL=$((FAIL + 1))
    fi
}

assert() {
    local desc="$1" expected="$2" actual="$3"
    TOTAL=$((TOTAL + 1))
    if [ "$expected" = "$actual" ]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc (expected '$expected', got '$actual')"
        FAIL=$((FAIL + 1))
    fi
}

echo "=== test-backlog-plan-tdd-gate.sh ==="

# ── Test 1: Procedure has a hard-block gate at step 11 ───────────────────────
echo "Test 1: backlog.md step 11 is a hard gate"
assert_contains "step 11 gate marker" "Gate.*plan completeness" "$BACKLOG_PROC"
assert_contains "hard block language" "hard block" "$BACKLOG_PROC"
assert_contains "no exception for S-sized" "no exception for S" "$BACKLOG_PROC"

# ── Test 2: Gate fires on AskUserQuestion (not silent skip) ─────────────────
echo "Test 2: gate uses AskUserQuestion — no silent progression"
assert_contains "uses AskUserQuestion" "AskUserQuestion" "$BACKLOG_PROC"
assert_contains "TDD gate header" "TDD gate" "$BACKLOG_PROC"
assert_contains "condition: code tasks but no test tasks" "code tasks exist but NO test tasks" "$BACKLOG_PROC"

# ── Test 3: REQUIRED marker prevents silent skip ────────────────────────────
echo "Test 3: explicit REQUIRED marker before step 12"
assert_contains "REQUIRED gate callout" "REQUIRED" "$BACKLOG_PROC"
assert_contains "do not proceed without completing step 11" "do not proceed" "$BACKLOG_PROC"

# ── Test 4: All three AskUserQuestion options present ───────────────────────
echo "Test 4: gate AskUserQuestion has all three options"
assert_contains "option: add test tasks now" "Add test tasks now" "$BACKLOG_PROC"
assert_contains "option: skip inline for Small" "Skip.*inline\|inline.*implementation" "$BACKLOG_PROC"
assert_contains "option: skip not-testable" "not testable" "$BACKLOG_PROC"
assert_contains "loop back to step 6 on add" "loop back.*step 6" "$BACKLOG_PROC"

# ── Test 5: Gate has escape hatches (not zero-flexibility) ──────────────────
echo "Test 5: all-docs/config plan passes gate automatically"
assert_contains "all-docs pass clause" "docs.*config.*spec.*only\|docs/config/spec only\|not docs/config" "$BACKLOG_PROC"

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
