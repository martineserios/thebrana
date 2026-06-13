#!/usr/bin/env bash
# Tests for validate.sh Check 2b: multiple always-load rules claiming first
# position at work-start (t-2080).
#
# After t-1944 consolidated 5 fragmented "go first" rules into work-start.md,
# this check prevents re-introducing the same fragmentation.
#
# Spec: system/rules/work-start.md
# Expected: exactly 1 always-load rule claims first position (work-start.md).
#           2+ claimants → fail.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

PASS=0
FAIL=0
TOTAL=0

TMPROOT=$(mktemp -d)
trap 'rm -rf "$TMPROOT"' EXIT

mkdir -p "$TMPROOT/system/rules" "$TMPROOT/system/hooks" \
         "$TMPROOT/system/skills" "$TMPROOT/system/agents" \
         "$TMPROOT/system/commands"
cp "$REPO_ROOT/validate.sh" "$TMPROOT/validate.sh"

assert_check2b_passes() {
    local desc="$1"
    TOTAL=$((TOTAL + 1))
    local out
    out=$(cd "$TMPROOT" && bash validate.sh 2>&1)
    if echo "$out" | grep -qE 'always-load rules claim first position'; then
        echo "  FAIL: $desc — expected no first-position conflict but check 2b failed"
        echo "$out" | grep -E 'always-load|first.position' | sed 's/^/    /'
        FAIL=$((FAIL + 1))
    else
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    fi
}

assert_check2b_fails() {
    local desc="$1"
    TOTAL=$((TOTAL + 1))
    local out
    out=$(cd "$TMPROOT" && bash validate.sh 2>&1)
    if echo "$out" | grep -qE 'always-load rules claim first position'; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc — expected first-position conflict but check 2b did not fire"
        echo "$out" | tail -10 | sed 's/^/    /'
        FAIL=$((FAIL + 1))
    fi
}

echo "Validate Check 2b: Work-Start First-Position Conflicts (t-2080)"
echo "================================================================"

# --- Scenario 1: No rules — passes ---
rm -f "$TMPROOT/system/rules/"*.md
assert_check2b_passes "Empty rules/ directory"

# --- Scenario 2: Only work-start.md (canonical) — passes (1 claimant) ---
rm -f "$TMPROOT/system/rules/"*.md
cat > "$TMPROOT/system/rules/work-start.md" <<'MD'
---
always-load: true
---
# Work Start — Ordered Entry Protocol

When starting any task (implementation, design, research) follow these steps in order.

**1. Read tasks.json first.**
Find the task. No task → propose one before branching.
MD
assert_check2b_passes "Only work-start.md (1 claimant) passes"

# --- Scenario 3: work-start.md + unrelated always-load rule — passes ---
cat > "$TMPROOT/system/rules/other-rule.md" <<'MD'
---
always-load: true
---
# Other Rule

Use conventional commits. No test doubles.
MD
assert_check2b_passes "work-start.md + unrelated always-load rule passes"

# --- Scenario 4: work-start.md + duplicate "go first" rule — FAILS ---
rm -f "$TMPROOT/system/rules/other-rule.md"
cat > "$TMPROOT/system/rules/duplicate-work-start.md" <<'MD'
---
always-load: true
---
# Duplicate Work Start

Always go first before starting any implementation work. Read tasks.json first
to find the task. Before implementation, check the backlog.
MD
assert_check2b_fails "work-start.md + duplicate 'go first' rule fails"

# --- Scenario 5: work-start.md + "always ask first" rule — FAILS ---
rm -f "$TMPROOT/system/rules/duplicate-work-start.md"
cat > "$TMPROOT/system/rules/another-first.md" <<'MD'
---
always-load: true
---
# Always Ask First

Always ask first before starting any task or work. Do not proceed without confirmation.
MD
assert_check2b_fails "work-start.md + 'always ask first' at work-start fails"

# --- Scenario 6: Scoped rule with first-position vocab — passes (not always-load) ---
rm -f "$TMPROOT/system/rules/another-first.md"
cat > "$TMPROOT/system/rules/scoped-first.md" <<'MD'
---
paths: ["system/**"]
---
# Scoped First

Read tasks.json first before starting implementation work.
MD
assert_check2b_passes "Scoped rule (paths:) with first-position vocab is ignored"

# --- Summary ---
echo ""
echo "$PASS/$TOTAL passed"
[ "$FAIL" -eq 0 ] || exit 1
