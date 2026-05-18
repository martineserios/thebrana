#!/usr/bin/env bash
# Tests for validate.sh Check 32 — echo|grep-q pipefail anti-pattern (t-1454).
#
# The anti-pattern: echo "$x" | grep -q under set -o pipefail.
# grep -q exits early on match; echo gets SIGPIPE 141; pipefail returns 141;
# if-condition evaluates false → false negative on successful match.
# Fix: use [[ "$x" == *"$needle"* ]] for simple contains checks.
#
# Tests verify:
#   T1: --check 32 runs Check 32 and emits its output label
#   T2: --check 32 does not emit Check 31 or Check 1 (isolation)
#   T3: current repo has violations → WARN emitted
#   T4: WARN message references t-1454 for traceability

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VALIDATE="$SCRIPT_DIR/../../validate.sh"

PASS=0; FAIL=0; TOTAL=0

assert_contains() {
    local desc="$1" needle="$2" haystack="$3"
    TOTAL=$((TOTAL+1))
    if [[ "$haystack" == *"$needle"* ]]; then
        PASS=$((PASS+1)); echo "  PASS: $desc"
    else
        FAIL=$((FAIL+1)); echo "  FAIL: $desc — '$needle' not found in output"
    fi
}

assert_not_contains() {
    local desc="$1" needle="$2" haystack="$3"
    TOTAL=$((TOTAL+1))
    if [[ "$haystack" == *"$needle"* ]]; then
        FAIL=$((FAIL+1)); echo "  FAIL: $desc — '$needle' unexpectedly found in output"
    else
        PASS=$((PASS+1)); echo "  PASS: $desc"
    fi
}

echo "=== validate.sh Check 32 — echo|grep-q pipefail anti-pattern (t-1454) ==="
echo ""

# ── T1: --check 32 emits Check 32 output label ──────────────────────────────
echo "T1: --check 32 → Check 32 output present"
OUT1=$(bash "$VALIDATE" --check 32 2>&1) || true
assert_contains "T1: Check 32 output label present" "Check 32" "$OUT1"

# ── T2: --check 32 does not emit other check labels (isolation) ──────────────
echo ""
echo "T2: --check 32 isolation → Check 31 and Check 1 absent"
OUT2=$(bash "$VALIDATE" --check 32 2>&1) || true
assert_not_contains "T2: Check 31 absent" "Check 31" "$OUT2"
assert_not_contains "T2: Check 1 frontmatter absent" "Checking skill frontmatter" "$OUT2"

# ── T3: existing repo violations → WARN present ─────────────────────────────
# tests/ already contains echo|grep-q in several helper files.
echo ""
echo "T3: existing violations in tests/ → WARN emitted"
OUT3=$(bash "$VALIDATE" --check 32 2>&1) || true
assert_contains "T3: WARN emitted for existing violations" "WARN" "$OUT3"

# ── T4: WARN message references t-1454 ──────────────────────────────────────
echo ""
echo "T4: WARN message includes task reference t-1454"
OUT4=$(bash "$VALIDATE" --check 32 2>&1) || true
assert_contains "T4: t-1454 referenced in WARN" "t-1454" "$OUT4"

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo "Results: $PASS passed, $FAIL failed (of $TOTAL total)"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
