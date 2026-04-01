#!/usr/bin/env bash
# Tests for source-tiered trust model (t-842) and audit incoming skill scan (t-843).
# Spec (t-842): acquire-skills classifies sources by trust tier and applies
# different install behaviors per tier. Tiers: trusted (anthropics/*),
# verified (skills.sh/official), community (quarantine), unknown (blocked).
# Spec (t-843): /brana:audit gains incoming skill scanning for dangerous
# patterns in allowed-tools, credential paths, and missing frontmatter.
# Run: bash tests/skills/test_source_tiered_trust.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ACQUIRE_SKILL="$REPO_ROOT/system/skills/acquire-skills/SKILL.md"
AUDIT_SKILL="$REPO_ROOT/system/skills/audit/SKILL.md"

PASS=0
FAIL=0
TOTAL=0

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

assert_contains() {
    local desc="$1" needle="$2" file="$3"
    TOTAL=$((TOTAL + 1))
    if grep -qE "$needle" "$file" 2>/dev/null; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc (expected '$needle' in $(basename "$file"))"
        FAIL=$((FAIL + 1))
    fi
}

echo "=== test_source_tiered_trust.sh ==="

# ══════════════════════════════════════════════
# t-842: Source-tiered trust model
# ══════════════════════════════════════════════

echo "--- t-842: Source-tiered trust model ---"

# ── Test 1: Trust tiers defined in acquire-skills ──
echo "Test 1: Trust tiers defined"
assert_contains "trusted tier documented" "trusted|Trusted" "$ACQUIRE_SKILL"
assert_contains "verified tier documented" "verified|Verified" "$ACQUIRE_SKILL"
assert_contains "quarantine tier documented" "quarantine|Quarantine" "$ACQUIRE_SKILL"
assert_contains "anthropics referenced as trusted" "anthropics" "$ACQUIRE_SKILL"

# ── Test 2: Different install behaviors per tier ──
echo "Test 2: Tier-specific behaviors"
assert_contains "full access for trusted" "full.*access|full.*tools|auto-install" "$ACQUIRE_SKILL"
assert_contains "review for verified" "review|confirm|prompt" "$ACQUIRE_SKILL"
assert_contains "restricted for quarantine" "read-only|restricted|limited" "$ACQUIRE_SKILL"

# ── Test 3: Source classification logic ──
echo "Test 3: Source classification"
assert_contains "github.com/anthropics as trusted" "anthropics.*trusted|trusted.*anthropics" "$ACQUIRE_SKILL"
assert_contains "skills.sh or official tag" "skills.sh|official" "$ACQUIRE_SKILL"

# ── Test 4: Unknown sources blocked ──
echo "Test 4: Unknown source handling"
assert_contains "unknown source blocked or warned" "blocked|unknown.*warn|reject.*unknown|add source first" "$ACQUIRE_SKILL"

# ══════════════════════════════════════════════
# t-843: Audit incoming skill scan
# ══════════════════════════════════════════════

echo "--- t-843: Audit incoming skill scan ---"

# ── Test 5: Audit skill exists ──
echo "Test 5: Audit skill exists"
assert "audit SKILL.md exists" "true" "$([ -f "$AUDIT_SKILL" ] && echo true || echo false)"

# ── Test 6: Audit has incoming skill scan section ──
echo "Test 6: Incoming skill scan"
assert_contains "incoming skill scan section" "incoming.*skill|skill.*scan|acquired.*scan" "$AUDIT_SKILL"

# ── Test 7: Dangerous patterns checked ──
echo "Test 7: Dangerous pattern detection"
assert_contains "checks allowed-tools" "allowed-tools|allowed.tools" "$AUDIT_SKILL"
assert_contains "checks for dangerous Bash" "Bash.*rm|rm -rf|dangerous" "$AUDIT_SKILL"
assert_contains "checks credential paths" "credential|.env|settings.json" "$AUDIT_SKILL"

# ── Test 8: Missing frontmatter flagged ──
echo "Test 8: Frontmatter validation"
assert_contains "missing frontmatter check" "frontmatter|missing.*field|required.*field" "$AUDIT_SKILL"

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
