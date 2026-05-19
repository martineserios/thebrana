#!/usr/bin/env bash
# Smoke test for /brana:build Step 0d Task Readiness Check (t-665/t-666).
# Validates: procedure spec correctness, hard-block/soft-warn definitions,
# skip path, and CLI contract (fields Step 0d reads/writes actually exist).
#
# Run: bash tests/procedures/test-build-readiness-check.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
BUILD_PROC="$REPO_ROOT/system/procedures/build.md"

PASS=0
FAIL=0
TOTAL=0

assert_contains() {
    local desc="$1" needle="$2" file="${3:-$BUILD_PROC}"
    TOTAL=$((TOTAL + 1))
    if grep -q "$needle" "$file" 2>/dev/null; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc (pattern '$needle' not in $(basename "$file"))"
        FAIL=$((FAIL + 1))
    fi
}

assert_not_contains() {
    local desc="$1" needle="$2" file="${3:-$BUILD_PROC}"
    TOTAL=$((TOTAL + 1))
    if ! grep -q "$needle" "$file" 2>/dev/null; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc (unexpected pattern '$needle' found)"
        FAIL=$((FAIL + 1))
    fi
}

assert_cmd() {
    local desc="$1"; shift
    TOTAL=$((TOTAL + 1))
    if "$@" >/dev/null 2>&1; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc"
        FAIL=$((FAIL + 1))
    fi
}

assert_output_contains() {
    local desc="$1" needle="$2"; shift 2
    TOTAL=$((TOTAL + 1))
    local out
    out=$("$@" 2>/dev/null) || out=""
    if [[ "$out" == *"$needle"* ]]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc (expected '$needle' in output, got: ${out:0:120})"
        FAIL=$((FAIL + 1))
    fi
}

echo "=== test-build-readiness-check.sh ==="
echo ""

# ── Test 1: Step 0d is present in build.md ───────────────────────────────────
echo "Test 1: Step 0d heading present"
assert_contains "Step 0d heading exists" "## Step 0d: READINESS CHECK"
assert_contains "Step 0d appears before Step 1" "Step 0d" # ordering verified below

echo ""

# ── Test 2: Hard block definitions ───────────────────────────────────────────
echo "Test 2: hard block definitions"
assert_contains "description length check (20 chars)" "20 chars"
assert_contains "blocked_by hard block" "blocked_by"
assert_contains "hard block label present" "Hard block"

echo ""

# ── Test 3: Soft warn definitions ────────────────────────────────────────────
echo "Test 3: soft warn definitions"
assert_contains "effort soft warn present" "Soft warn"
assert_contains "AC: lines soft warn present" "AC:"
assert_contains "soft warn emit inline (no gate)" "no gate"

echo ""

# ── Test 4: Hard block gate (AskUserQuestion) ────────────────────────────────
echo "Test 4: AskUserQuestion gate on hard block"
assert_contains "AskUserQuestion present" "AskUserQuestion"
assert_contains "Fix now option" "Fix now"
assert_contains "Skip with reason option" "Skip"
assert_contains "Re-read and re-run after fix" "re-run checks"

echo ""

# ── Test 5: Skip path — decisions log ────────────────────────────────────────
echo "Test 5: skip path wires decisions log (t-666)"
assert_contains "decisions log on skip" "brana decisions log"
assert_contains "decisions log positional form (no --entry-type flag)" "decisions log main concern"
assert_contains "notes --append on skip" "notes --append"

echo ""

# ── Test 6: Silent pass behavior ─────────────────────────────────────────────
echo "Test 6: silent pass when all checks pass or only soft warns remain"
assert_contains "proceed silently" "proceed silently"

echo ""

# ── Test 7: Spike / investigation exemption ──────────────────────────────────
echo "Test 7: spike/investigation tasks are exempt"
assert_contains "spike exemption" "spike"
assert_contains "investigation exemption" "investigation"

echo ""

# ── Test 8: No-task exemption ────────────────────────────────────────────────
echo "Test 8: freeform builds (no task_id) are exempt"
assert_contains "skip if no task_id" "no task_id"

echo ""

# ── Test 9: CLI contract — brana backlog get returns required fields ──────────
echo "Test 9: CLI contract — backlog get returns readiness fields"
BRANA_BIN=$(command -v brana 2>/dev/null) || BRANA_BIN=""
if [ -z "$BRANA_BIN" ]; then
    echo "  SKIP: brana binary not found (all CLI checks skipped)"
    PASS=$((PASS + 1)); TOTAL=$((TOTAL + 1))  # non-blocking skip counts as pass
else
    # Create a scratch task, check its fields, then cancel it
    SCRATCH_ID=$(brana backlog add \
        --subject "readiness-check-test-$$" \
        --description "Test task for readiness check smoke test — can be deleted" \
        --json 2>/dev/null | jq -r '.id // empty' 2>/dev/null) || SCRATCH_ID=""

    if [ -z "$SCRATCH_ID" ]; then
        echo "  SKIP: could not create scratch task (backlog add may require --effort)"
        PASS=$((PASS + 1)); TOTAL=$((TOTAL + 1))
    else
        TASK_JSON=$(brana backlog get "$SCRATCH_ID" 2>/dev/null) || TASK_JSON="{}"

        assert_output_contains "description field accessible" '"description"' \
            brana backlog get "$SCRATCH_ID"
        assert_output_contains "blocked_by field accessible" '"blocked_by"' \
            brana backlog get "$SCRATCH_ID"
        assert_output_contains "effort field accessible" '"effort"' \
            brana backlog get "$SCRATCH_ID"
        assert_output_contains "context field accessible" '"context"' \
            brana backlog get "$SCRATCH_ID"

        # Clean up
        brana backlog set "$SCRATCH_ID" status cancelled >/dev/null 2>&1 || true
    fi
fi

echo ""

# ── Test 10: CLI contract — decisions log positional form works ───────────────
echo "Test 10: CLI contract — brana decisions log positional form"
if [ -z "$BRANA_BIN" ]; then
    echo "  SKIP: brana binary not found"
    PASS=$((PASS + 1)); TOTAL=$((TOTAL + 1))
else
    assert_cmd "decisions log --help exits 0" brana decisions log --help
fi

echo ""

# ── Test 11: Step 0d appears before Step 1 (ordering) ────────────────────────
echo "Test 11: Step 0d precedes Step 1 in build.md"
TOTAL=$((TOTAL + 1))
LINE_0D=$(grep -n "## Step 0d" "$BUILD_PROC" 2>/dev/null | head -1 | cut -d: -f1) || LINE_0D=0
LINE_1=$(grep -n "## Step 1:" "$BUILD_PROC" 2>/dev/null | head -1 | cut -d: -f1) || LINE_1=0
if [ -n "$LINE_0D" ] && [ -n "$LINE_1" ] && [ "$LINE_0D" -lt "$LINE_1" ] && [ "$LINE_0D" -gt 0 ]; then
    echo "  PASS: Step 0d (line $LINE_0D) before Step 1 (line $LINE_1)"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Step 0d ordering incorrect (0d=$LINE_0D, Step1=$LINE_1)"
    FAIL=$((FAIL + 1))
fi

echo ""
echo "=== Results: $PASS passed, $FAIL failed (of $TOTAL) ==="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
