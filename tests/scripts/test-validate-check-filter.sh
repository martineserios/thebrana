#!/usr/bin/env bash
# Tests for validate.sh --check N flag (t-1449).
#
# Verifies that --check N runs only the targeted check and skips others.
# Tests use output label detection: each check emits "Check N" in its pass/warn/fail lines.
# We verify presence of targeted check output and absence of non-targeted check output.

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

assert_exits_nonzero() {
    local desc="$1"; shift
    TOTAL=$((TOTAL+1))
    if "$@" > /dev/null 2>&1; then
        FAIL=$((FAIL+1)); echo "  FAIL: $desc — expected nonzero exit, got 0"
    else
        PASS=$((PASS+1)); echo "  PASS: $desc"
    fi
}

echo "=== validate.sh --check N filter (t-1449) ==="
echo ""

# ── T1: --check 31 runs Check 31, skips Check 1 frontmatter loop ────────────
echo "T1: --check 31 → Check 31 output present, Check 1 frontmatter absent"
OUT1=$(bash "$VALIDATE" --check 31 2>&1) || true
assert_contains     "T1: Check 31a output present"     "Check 31a" "$OUT1"
assert_not_contains "T1: Check 1 frontmatter absent"   "Checking skill frontmatter" "$OUT1"
assert_not_contains "T1: Check 15 absent"              "Check 15" "$OUT1"

# ── T2: --check 1 runs Check 1 block, skips Check 31 ───────────────────────
echo ""
echo "T2: --check 1 → Check 1 (frontmatter) present, Check 31 absent"
OUT2=$(bash "$VALIDATE" --check 1 2>&1) || true
assert_contains     "T2: Check 1 frontmatter label present" "Checking skill frontmatter" "$OUT2"
assert_not_contains "T2: Check 31 absent"                   "Check 31" "$OUT2"
assert_not_contains "T2: Check 15 absent"                   "Check 15" "$OUT2"

# ── T3: --check 29 → Check 29 output present, others absent ────────────────
echo ""
echo "T3: --check 29 → Check 29 output present, Check 1 and Check 31 absent"
OUT3=$(bash "$VALIDATE" --check 29 2>&1) || true
assert_contains     "T3: Check 29 output present"    "Check 29" "$OUT3"
assert_not_contains "T3: Check 31 absent"            "Check 31" "$OUT3"
assert_not_contains "T3: Check 1 frontmatter absent" "Checking skill frontmatter" "$OUT3"

# ── T4: --check 5 runs 5 and 5b, skips high-numbered checks ─────────────────
# Note: checks 1-14 are in a single inline block; --check N for N in 1-14
# runs the whole 1-14 block (acceptable tradeoff). The main win is skipping
# the slower checks 15-31.
echo ""
echo "T4: --check 5 → Check 5 and Check 5b present, Check 31 absent"
OUT4=$(bash "$VALIDATE" --check 5 2>&1) || true
assert_contains     "T4: Check 5 (context budget) output present"  "Checking context budget" "$OUT4"
assert_contains     "T4: Check 5b (instruction density) output present" "Checking instruction density" "$OUT4"
assert_not_contains "T4: Check 31 absent"         "Check 31" "$OUT4"

# ── T5: no --check flag → runs all checks (sanity) ─────────────────────────
echo ""
echo "T5: no --check → full run includes Check 1 and Check 31"
OUT5=$(bash "$VALIDATE" 2>&1) || true
assert_contains "T5: Check 1 present in full run"  "Checking skill frontmatter" "$OUT5"
assert_contains "T5: Check 31 present in full run" "Check 31" "$OUT5"

# ── T6: missing arg for --check exits with error ────────────────────────────
echo ""
echo "T6: --check with no argument → exits nonzero"
assert_exits_nonzero "T6: missing --check arg exits nonzero" bash "$VALIDATE" --check

# ── T7: --check N skips Checks A-D ──────────────────────────────────────────
echo ""
echo "T7: --check 32 → Checks A-D absent"
OUT7=$(bash "$VALIDATE" --check 32 2>&1) || true
assert_not_contains "T7: Check A absent with --check 32" "Check A:" "$OUT7"
assert_not_contains "T7: Check B absent with --check 32" "Check B:" "$OUT7"
assert_not_contains "T7: Check C absent with --check 32" "Check C:" "$OUT7"
assert_not_contains "T7: Check D absent with --check 32" "Check D:" "$OUT7"

echo ""
echo "T8: --check 31 → Checks A-D absent"
OUT8=$(bash "$VALIDATE" --check 31 2>&1) || true
assert_not_contains "T8: Check A absent with --check 31" "Check A:" "$OUT8"
assert_not_contains "T8: Check B absent with --check 31" "Check B:" "$OUT8"

# ── T9: --semantic → Checks A-D present ─────────────────────────────────────
echo ""
echo "T9: --semantic → Checks A-D present"
OUT9=$(bash "$VALIDATE" --semantic 2>&1) || true
assert_contains "T9: Check A present with --semantic" "Check A:" "$OUT9"
assert_contains "T9: Check B present with --semantic" "Check B:" "$OUT9"

# ── T10: full run → Checks A-D present ──────────────────────────────────────
echo ""
echo "T10: full run → Checks A-D present"
assert_contains "T10: Check A present in full run" "Check A:" "$OUT5"
assert_contains "T10: Check B present in full run" "Check B:" "$OUT5"

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo "Results: $PASS passed, $FAIL failed (of $TOTAL total)"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
