#!/usr/bin/env bash
# Tests for validate.sh rules-scoping check (t-1285).
#
# Spec: system/rules/README.md
# Every rule under system/rules/*.md must declare either:
#   - paths: [...] (scoped)
#   - always-load: true (universal)
# Otherwise validate.sh must fail.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
VALIDATE="$REPO_ROOT/validate.sh"

PASS=0
FAIL=0
TOTAL=0

# Create a throwaway working tree so we can mutate system/rules/ without
# polluting the real repo.
TMPROOT=$(mktemp -d)
trap 'rm -rf "$TMPROOT"' EXIT

# Mirror only what validate.sh reads (system/rules + minimal scaffold).
mkdir -p "$TMPROOT/system/rules" "$TMPROOT/system/hooks" "$TMPROOT/system/skills" "$TMPROOT/system/agents" "$TMPROOT/system/commands"
# Give validate.sh the minimum it expects to exist so unrelated checks
# succeed; we only care about the rules-scoping result.
cp "$REPO_ROOT/validate.sh" "$TMPROOT/validate.sh"

run_validate_check() {
    local tmp_output
    tmp_output=$(mktemp)
    ( cd "$TMPROOT" && bash validate.sh > "$tmp_output" 2>&1 )
    local rc=$?
    cat "$tmp_output"
    rm -f "$tmp_output"
    return $rc
}

assert_validate_passes_rules_check() {
    local desc="$1"
    TOTAL=$((TOTAL + 1))
    local out
    out=$(cd "$TMPROOT" && bash validate.sh 2>&1)
    # Extract just the rules-scoping portion; the scoping check must not fail.
    if echo "$out" | grep -qE "rules/.* — unscoped \(no paths: or always-load: true\)"; then
        echo "  FAIL: $desc — expected rules scoping to pass but it reported unscoped"
        FAIL=$((FAIL + 1))
    else
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    fi
}

assert_validate_fails_rules_check() {
    local desc="$1"
    TOTAL=$((TOTAL + 1))
    local out
    out=$(cd "$TMPROOT" && bash validate.sh 2>&1)
    if echo "$out" | grep -qE "rules/.* — unscoped \(no paths: or always-load: true\)"; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc — expected rules scoping to fail but did not"
        echo "    output tail:"
        echo "$out" | tail -10 | sed 's/^/      /'
        FAIL=$((FAIL + 1))
    fi
}

echo "Validate Rules Scoping Tests (t-1285)"
echo "======================================"

# --- Scenario 1: No rules at all — passes ---
rm -f "$TMPROOT/system/rules/"*.md
assert_validate_passes_rules_check "Empty rules/ directory"

# --- Scenario 2: One rule with paths: — passes ---
cat > "$TMPROOT/system/rules/scoped-ok.md" <<'MD'
---
paths: ["system/**"]
---
# Scoped OK
Test rule.
MD
assert_validate_passes_rules_check "Rule with paths: passes"

# --- Scenario 3: One rule with always-load: true — passes ---
cat > "$TMPROOT/system/rules/always-ok.md" <<'MD'
---
always-load: true
---
# Always OK
Test rule.
MD
assert_validate_passes_rules_check "Rule with always-load: true passes"

# --- Scenario 4: Rule with no frontmatter — FAILS ---
rm -f "$TMPROOT/system/rules/scoped-ok.md" "$TMPROOT/system/rules/always-ok.md"
cat > "$TMPROOT/system/rules/no-frontmatter.md" <<'MD'
# No Frontmatter
This rule is implicitly always-loaded. Should be rejected.
MD
assert_validate_fails_rules_check "Rule with no frontmatter fails"

# --- Scenario 5: Rule with frontmatter but neither field — FAILS ---
rm -f "$TMPROOT/system/rules/no-frontmatter.md"
cat > "$TMPROOT/system/rules/neither-field.md" <<'MD'
---
title: "Partial"
---
# Neither
Has frontmatter but no paths: or always-load:. Should fail.
MD
assert_validate_fails_rules_check "Rule with neither paths: nor always-load: fails"

# --- Scenario 6: Rule with legacy globs: — FAILS (migration required) ---
rm -f "$TMPROOT/system/rules/neither-field.md"
cat > "$TMPROOT/system/rules/legacy-globs.md" <<'MD'
---
globs: ["docs/**"]
alwaysApply: false
---
# Legacy globs
Should fail — globs: is not supported; use paths:.
MD
assert_validate_fails_rules_check "Legacy globs: frontmatter fails (no paths/always-load)"

# --- Summary ---
echo ""
echo "$PASS/$TOTAL passed"
[ "$FAIL" -eq 0 ] || exit 1
