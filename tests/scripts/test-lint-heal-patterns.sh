#!/usr/bin/env bash
# test-lint-heal-patterns.sh — Tests for lint-heal.sh Pass 5 + Pass 6
#
# Pass 5: patterns.md duplicate slug detection
# Pass 6: knowledge-staging.md cap/warn check
#
# Uses LINT_HEAL_PATTERNS_FILE and LINT_HEAL_STAGING_FILE env overrides.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LINT_SCRIPT="$REPO_ROOT/system/scripts/lint-heal.sh"

PASS=0
FAIL=0
TMPFILES=()

pass() { PASS=$((PASS + 1)); echo "  ✓ $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  ✗ $1"; }
cleanup() { for f in "${TMPFILES[@]:-}"; do rm -rf "$f"; done; }
trap cleanup EXIT

mkfixture() {
    local f
    f=$(mktemp /tmp/lint-heal-test-XXXXXX.md)
    TMPFILES+=("$f")
    echo "$f"
}

echo "=== lint-heal.sh — Pass 5 + Pass 6 Tests ==="
echo ""

# --- Prerequisites ---
echo "Prerequisites:"
if [ -f "$LINT_SCRIPT" ] && [ -x "$LINT_SCRIPT" ]; then
    pass "lint-heal.sh exists and is executable"
else
    fail "lint-heal.sh missing or not executable"
    echo "=== $PASS passed, $FAIL failed ==="
    exit 1
fi

# --- Test 1: Pass 5 — detects duplicate slugs in patterns.md ---
echo ""
echo "Pass 5 (patterns.md dedup):"

PATTERNS_DUP=$(mkfixture)
cat > "$PATTERNS_DUP" << 'EOF'
# Pattern Store

<!-- cap: 50 | warn-at: 40 -->

## my-unique-pattern

**Problem:** First.
**Confidence:** quarantine
**Added:** 2026-01-01

## my-duplicate-slug

**Problem:** Original.
**Confidence:** quarantine
**Added:** 2026-01-02

## my-duplicate-slug

**Problem:** Duplicate — same slug.
**Confidence:** quarantine
**Added:** 2026-01-03

## another-unique

**Problem:** Also unique.
**Confidence:** proven
**Added:** 2026-01-04
EOF

MEM_ROOT=$(mktemp -d /tmp/lint-heal-memroot-XXXXXX)
TMPFILES+=("$MEM_ROOT")

output=$(LINT_HEAL_PATTERNS_FILE="$PATTERNS_DUP" \
         LINT_HEAL_MEMORY_ROOT="$MEM_ROOT" \
         bash "$LINT_SCRIPT" --dry-run 2>&1) || true

if echo "$output" | grep -q "Pass 5"; then
    pass "Pass 5 runs"
else
    fail "Pass 5 not found in output"
fi

if echo "$output" | grep -q "my-duplicate-slug"; then
    pass "Pass 5 detects duplicate slug 'my-duplicate-slug'"
else
    fail "Pass 5 did not surface duplicate slug"
fi

# --- Test 2: Pass 5 — no duplicates = clean report ---
echo ""
PATTERNS_CLEAN=$(mkfixture)
cat > "$PATTERNS_CLEAN" << 'EOF'
# Pattern Store

<!-- cap: 50 | warn-at: 40 -->

## alpha-pattern

**Problem:** Unique.
**Confidence:** quarantine
**Added:** 2026-01-01

## beta-pattern

**Problem:** Also unique.
**Confidence:** proven
**Added:** 2026-01-02
EOF

output=$(LINT_HEAL_PATTERNS_FILE="$PATTERNS_CLEAN" \
         LINT_HEAL_MEMORY_ROOT="$MEM_ROOT" \
         bash "$LINT_SCRIPT" --dry-run 2>&1) || true

if echo "$output" | grep -qE "Pass 5 done: 0"; then
    pass "Pass 5 reports 0 duplicates on clean file"
else
    fail "Pass 5 clean file: unexpected output ($(echo "$output" | grep 'Pass 5' | head -1))"
fi

# --- Test 3: Pass 6 — warns when at or above warn-at threshold ---
echo ""
echo "Pass 6 (knowledge-staging.md cap check):"

STAGING_AT_WARN=$(mkfixture)
# Build a staging file with exactly 20 sections (warn-at: 20)
{
    echo "# Knowledge Staging"
    echo ""
    echo "<!-- cap: 30 | warn-at: 20 | stale-after: 30 days -->"
    echo ""
    for i in $(seq 1 20); do
        echo "## section-$i"
        echo ""
        echo "**Claim:** Entry $i."
        echo "**Confidence:** medium"
        echo "**Added:** 2026-01-01"
        echo "**Promote to:** MEMORY.md"
        echo "**Promoted:** —"
        echo ""
    done
} > "$STAGING_AT_WARN"

output=$(LINT_HEAL_STAGING_FILE="$STAGING_AT_WARN" \
         LINT_HEAL_MEMORY_ROOT="$MEM_ROOT" \
         bash "$LINT_SCRIPT" --dry-run 2>&1) || true

if echo "$output" | grep -q "Pass 6"; then
    pass "Pass 6 runs"
else
    fail "Pass 6 not found in output"
fi

if echo "$output" | grep -qE "(warn|WARNING|promote|prune)"; then
    pass "Pass 6 warns at warn-at threshold (20 entries)"
else
    fail "Pass 6 did not warn at threshold — output: $(echo "$output" | grep 'Pass 6' | head -2)"
fi

# --- Test 4: Pass 6 — no warning below threshold ---
echo ""
STAGING_BELOW=$(mkfixture)
{
    echo "# Knowledge Staging"
    echo ""
    echo "<!-- cap: 30 | warn-at: 20 | stale-after: 30 days -->"
    echo ""
    for i in $(seq 1 5); do
        echo "## small-entry-$i"
        echo ""
        echo "**Claim:** Small entry $i."
        echo "**Confidence:** low"
        echo "**Added:** 2026-01-01"
        echo "**Promote to:** MEMORY.md"
        echo "**Promoted:** —"
        echo ""
    done
} > "$STAGING_BELOW"

output=$(LINT_HEAL_STAGING_FILE="$STAGING_BELOW" \
         LINT_HEAL_MEMORY_ROOT="$MEM_ROOT" \
         bash "$LINT_SCRIPT" --dry-run 2>&1) || true

if echo "$output" | grep -qE "Pass 6 done: 5"; then
    pass "Pass 6 reports 5 entries, no warning"
else
    fail "Pass 6 below-threshold: unexpected ($(echo "$output" | grep 'Pass 6' | head -2))"
fi

# --- Test 5: Pass 6 — missing staging file is skipped gracefully ---
echo ""
MISSING_STAGING="/tmp/does-not-exist-$(date +%s).md"
output=$(LINT_HEAL_STAGING_FILE="$MISSING_STAGING" \
         LINT_HEAL_MEMORY_ROOT="$MEM_ROOT" \
         bash "$LINT_SCRIPT" --dry-run 2>&1) || true

if echo "$output" | grep -q "Pass 6"; then
    pass "Pass 6 skips gracefully when staging file missing"
else
    fail "Pass 6 missing file: script may have errored ($(echo "$output" | tail -3))"
fi

# --- Summary ---
echo ""
echo "=== $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] || exit 1
