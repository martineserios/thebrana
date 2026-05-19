#!/usr/bin/env bash
# Tests for validate.sh Check 33 — SKILL.md keywords field for code-strategy skills (t-1482).
#
# The step 4a tech-detection gate matches installed skills by their SKILL.md keywords field.
# Any SKILL.md with task_strategies containing a code-work strategy (feature, refactor,
# bug-fix, tech-debt) must declare a non-empty keywords list or the gate silently bypasses.
#
# Tests verify:
#   T1: --check 33 runs Check 33 and emits its output label
#   T2: --check 33 does not emit Check 32 or Check 1 (isolation)
#   T3: clean repo → all current code-strategy skills have keywords → PASS emitted
#   T4: synthetic dirty skill (missing keywords) → FAIL emitted with count
#   T5: FAIL message references t-1482 for traceability

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VALIDATE="$SCRIPT_DIR/../../validate.sh"
CANARY_DIR="$SCRIPT_DIR/../../system/skills/test-33-canary"

trap 'rm -rf "$CANARY_DIR"' EXIT

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

echo "=== validate.sh Check 33 — SKILL.md keywords field for code-strategy skills (t-1482) ==="
echo ""

# ── T1: --check 33 emits Check 33 output label ──────────────────────────────
echo "T1: --check 33 → Check 33 output present"
OUT1=$(bash "$VALIDATE" --check 33 2>&1) || true
assert_contains "T1: Check 33 output label present" "Check 33" "$OUT1"

# ── T2: isolation — no other checks run ─────────────────────────────────────
echo ""
echo "T2: --check 33 isolation → Check 32 and Check 1 absent"
OUT2=$(bash "$VALIDATE" --check 33 2>&1) || true
assert_not_contains "T2: Check 32 absent" "Check 32" "$OUT2"
assert_not_contains "T2: Check 1 frontmatter absent" "Checking skill frontmatter" "$OUT2"

# ── T3: clean repo → PASS (all current code-strategy skills have keywords) ──
echo ""
echo "T3: clean repo → PASS emitted"
OUT3=$(bash "$VALIDATE" --check 33 2>&1) || true
assert_contains "T3: PASS emitted for clean repo" "PASS" "$OUT3"
assert_not_contains "T3: FAIL absent in clean repo" "FAIL: Check 33" "$OUT3"

# ── T4: synthetic dirty skill → FAIL emitted ────────────────────────────────
echo ""
echo "T4: synthetic SKILL.md missing keywords → FAIL emitted"
mkdir -p "$CANARY_DIR"
cat > "$CANARY_DIR/SKILL.md" <<'SKILL'
---
name: test-33-canary
description: "Canary skill for validate.sh Check 33 test — missing keywords field."
task_strategies: [feature, refactor]
stream_affinity: [roadmap]
---
SKILL
OUT4=$(bash "$VALIDATE" --check 33 2>&1) || true
assert_contains "T4: FAIL emitted for missing keywords" "FAIL" "$OUT4"
assert_contains "T4: canary skill name in output" "test-33-canary" "$OUT4"

# ── T5: FAIL message references t-1482 (traceability) ───────────────────────
echo ""
echo "T5: FAIL message includes task reference t-1482"
OUT5=$(bash "$VALIDATE" --check 33 2>&1) || true
assert_contains "T5: t-1482 referenced in FAIL" "t-1482" "$OUT5"

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo "Results: $PASS passed, $FAIL failed (of $TOTAL total)"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
