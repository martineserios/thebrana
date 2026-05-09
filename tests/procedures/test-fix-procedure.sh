#!/usr/bin/env bash
# Smoke test for /brana:fix procedure (t-1361).
# Validates: step references, step registry, key rules, and workflow doc.
#
# Run: bash tests/procedures/test-fix-procedure.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
FIX_PROC="$REPO_ROOT/system/procedures/fix.md"
FIX_WORKFLOW="$REPO_ROOT/docs/guide/workflows/fix.md"

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

assert_file_exists() {
    local desc="$1" file="$2"
    TOTAL=$((TOTAL + 1))
    if [ -f "$file" ]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc (file not found: $file)"
        FAIL=$((FAIL + 1))
    fi
}

echo "=== test-fix-procedure.sh ==="

# ── Test 1: Files exist ───────────────────────────────────────────────────────
echo "Test 1: procedure and workflow docs exist"
assert_file_exists "system/procedures/fix.md exists" "$FIX_PROC"
assert_file_exists "docs/guide/workflows/fix.md exists" "$FIX_WORKFLOW"

# ── Test 2: All 5 steps present in procedure ──────────────────────────────────
echo "Test 2: all 5 steps in procedure"
assert_contains "Step 1 REPRODUCE header" "Step 1: REPRODUCE" "$FIX_PROC"
assert_contains "Step 2 DIAGNOSE header" "Step 2: DIAGNOSE" "$FIX_PROC"
assert_contains "Step 3 FIX header" "Step 3: FIX" "$FIX_PROC"
assert_contains "Step 4 VERIFY header" "Step 4: VERIFY" "$FIX_PROC"
assert_contains "Step 5 COMMIT header" "Step 5: COMMIT" "$FIX_PROC"

# ── Test 3: Step Registry present (compression resilience) ───────────────────
echo "Test 3: step registry for CC Tasks present"
assert_contains "step registry section" "Step Registry" "$FIX_PROC"
assert_contains "TaskCreate for REPRODUCE" "TaskCreate.*REPRODUCE" "$FIX_PROC"
assert_contains "TaskCreate for COMMIT" "TaskCreate.*COMMIT" "$FIX_PROC"

# ── Test 4: Key rules enforced ────────────────────────────────────────────────
echo "Test 4: key rules in procedure"
assert_contains "test-before-source rule" "Test before source" "$FIX_PROC"
assert_contains "3-strike rule" "3-strike" "$FIX_PROC"
assert_contains "minimal change rule" "Minimal change" "$FIX_PROC"
assert_contains "no refactor during fix rule" "No refactor during fix" "$FIX_PROC"

# ── Test 5: Workflow doc covers fix vs build decision ─────────────────────────
echo "Test 5: workflow doc — fix vs build table"
assert_contains "fix vs build section" "Fix vs Build" "$FIX_WORKFLOW"
assert_contains "use fix condition — tight loop" "tight" "$FIX_WORKFLOW"
assert_contains "3-strike rule in workflow doc" "3-strike\|3 or more\|three" "$FIX_WORKFLOW"

# ── Test 6: Commit message format present ─────────────────────────────────────
echo "Test 6: commit message format specified"
assert_contains "fix scope commit format" "fix({scope})" "$FIX_PROC"

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "Results: $PASS/$TOTAL passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
