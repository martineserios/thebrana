#!/usr/bin/env bash
# Tests for config-drift.sh
# Creates mock source/deployed directories and verifies drift detection.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/../config-drift.sh"
PASS=0
FAIL=0
TMPDIR=$(mktemp -d)

trap 'rm -rf "$TMPDIR"' EXIT

# Helper: assert JSON field equals expected value
assert_json_eq() {
    local desc="$1" json="$2" path="$3" expected="$4"
    local actual
    actual=$(echo "$json" | jq -r "$path" 2>/dev/null)
    if [ "$actual" = "$expected" ]; then
        echo "  PASS: $desc"
        ((PASS++))
    else
        echo "  FAIL: $desc — expected '$expected', got '$actual'"
        ((FAIL++))
    fi
}

assert_json_count() {
    local desc="$1" json="$2" path="$3" expected="$4"
    local actual
    actual=$(echo "$json" | jq "$path" 2>/dev/null)
    if [ "$actual" = "$expected" ]; then
        echo "  PASS: $desc"
        ((PASS++))
    else
        echo "  FAIL: $desc — expected $expected, got $actual"
        ((FAIL++))
    fi
}

echo "Config Drift Tests"
echo "==================="

# --- Test 1: No drift (identical files) ---
echo ""
echo "Test 1: No drift"
SRC1="$TMPDIR/src1"
DEPLOY1="$TMPDIR/deploy1"
mkdir -p "$SRC1/rules" "$DEPLOY1/rules"
echo "# Identity" > "$SRC1/CLAUDE.md"
echo "# Identity" > "$DEPLOY1/CLAUDE.md"
echo "# Rule A" > "$SRC1/rules/a.md"
echo "# Rule A" > "$DEPLOY1/rules/a.md"

RESULT=$(BRANA_SOURCE_DIR="$SRC1" BRANA_DEPLOY_DIR="$DEPLOY1" bash "$HOOK" </dev/null 2>/dev/null)
assert_json_eq "no drift → clean status" "$RESULT" '.status' 'clean'
assert_json_count "no drift → 0 drifted files" "$RESULT" '.drifted | length' '0'

# --- Test 2: Modified file detected ---
echo ""
echo "Test 2: Modified CLAUDE.md"
SRC2="$TMPDIR/src2"
DEPLOY2="$TMPDIR/deploy2"
mkdir -p "$SRC2/rules" "$DEPLOY2/rules"
echo "# Identity v2" > "$SRC2/CLAUDE.md"
echo "# Identity v1" > "$DEPLOY2/CLAUDE.md"
echo "# Rule A" > "$SRC2/rules/a.md"
echo "# Rule A" > "$DEPLOY2/rules/a.md"

RESULT=$(BRANA_SOURCE_DIR="$SRC2" BRANA_DEPLOY_DIR="$DEPLOY2" bash "$HOOK" </dev/null 2>/dev/null)
assert_json_eq "modified file → drifted status" "$RESULT" '.status' 'drifted'
assert_json_count "modified file → 1 drifted" "$RESULT" '.drifted | length' '1'
assert_json_eq "modified file → type=modified" "$RESULT" '.drifted[0].type' 'modified'
assert_json_eq "modified file → correct name" "$RESULT" '.drifted[0].file' 'CLAUDE.md'

# --- Test 3: Source-only rule — suppressed (plugin-served, bootstrap.sh doesn't deploy rules/) ---
echo ""
echo "Test 3: Source-only rule is suppressed (rules/ are plugin-served)"
SRC3="$TMPDIR/src3"
DEPLOY3="$TMPDIR/deploy3"
mkdir -p "$SRC3/rules" "$DEPLOY3/rules"
echo "# Identity" > "$SRC3/CLAUDE.md"
echo "# Identity" > "$DEPLOY3/CLAUDE.md"
echo "# Rule A" > "$SRC3/rules/a.md"
echo "# Rule B" > "$SRC3/rules/b.md"  # exists in source only
echo "# Rule A" > "$DEPLOY3/rules/a.md"

RESULT=$(BRANA_SOURCE_DIR="$SRC3" BRANA_DEPLOY_DIR="$DEPLOY3" bash "$HOOK" </dev/null 2>/dev/null)
# rules/ source_only is suppressed — should be clean (no CLAUDE.md drift)
assert_json_eq "source-only rule suppressed → clean status" "$RESULT" '.status' 'clean'
assert_json_count "source-only rule suppressed → 0 drifted" "$RESULT" '.drifted | length' '0'

# --- Test 4: Deploy-only file (exists in deployed, not in source — stale) ---
echo ""
echo "Test 4: Deploy-only rule (stale)"
SRC4="$TMPDIR/src4"
DEPLOY4="$TMPDIR/deploy4"
mkdir -p "$SRC4/rules" "$DEPLOY4/rules"
echo "# Identity" > "$SRC4/CLAUDE.md"
echo "# Identity" > "$DEPLOY4/CLAUDE.md"
echo "# Rule A" > "$SRC4/rules/a.md"
echo "# Rule A" > "$DEPLOY4/rules/a.md"
echo "# Stale Rule" > "$DEPLOY4/rules/stale.md"

RESULT=$(BRANA_SOURCE_DIR="$SRC4" BRANA_DEPLOY_DIR="$DEPLOY4" bash "$HOOK" </dev/null 2>/dev/null)
assert_json_eq "deploy-only → drifted" "$RESULT" '.status' 'drifted'
assert_json_eq "deploy-only → type=deploy_only" "$RESULT" '.drifted[0].type' 'deploy_only'
assert_json_eq "deploy-only → correct name" "$RESULT" '.drifted[0].file' 'rules/stale.md'

# --- Test 5: Combined drift — rules/ source_only suppressed, deploy_only still reported ---
echo ""
echo "Test 5: Combined drift (modified CLAUDE.md + rules/source_only suppressed + rules/deploy_only shown)"
SRC5="$TMPDIR/src5"
DEPLOY5="$TMPDIR/deploy5"
mkdir -p "$SRC5/rules" "$DEPLOY5/rules"
echo "# NEW" > "$SRC5/CLAUDE.md"
echo "# OLD" > "$DEPLOY5/CLAUDE.md"
echo "# New rule" > "$SRC5/rules/new.md"  # source_only — suppressed
echo "# Stale" > "$DEPLOY5/rules/stale.md"  # deploy_only — still reported
echo "# Same" > "$SRC5/rules/same.md"
echo "# Same" > "$DEPLOY5/rules/same.md"

RESULT=$(BRANA_SOURCE_DIR="$SRC5" BRANA_DEPLOY_DIR="$DEPLOY5" bash "$HOOK" </dev/null 2>/dev/null)
assert_json_eq "combined → drifted" "$RESULT" '.status' 'drifted'
# 2 items: CLAUDE.md modified + rules/stale.md deploy_only (NOT rules/new.md source_only)
assert_json_count "combined → 2 drifted (source_only suppressed)" "$RESULT" '.drifted | length' '2'

# --- Test 6: Missing deploy dir → CLAUDE.md source_only shown, rules/ source_only suppressed ---
echo ""
echo "Test 6: Missing deploy dir — CLAUDE.md shown, rules/ suppressed"
SRC6="$TMPDIR/src6"
DEPLOY6="$TMPDIR/deploy6-nonexistent"
mkdir -p "$SRC6/rules"
echo "# Identity" > "$SRC6/CLAUDE.md"
echo "# Rule" > "$SRC6/rules/a.md"

RESULT=$(BRANA_SOURCE_DIR="$SRC6" BRANA_DEPLOY_DIR="$DEPLOY6" bash "$HOOK" </dev/null 2>/dev/null)
assert_json_eq "missing deploy → drifted (CLAUDE.md source_only)" "$RESULT" '.status' 'drifted'
# rules/a.md source_only suppressed — only CLAUDE.md reported
assert_json_count "missing deploy → 1 source_only (rules/ suppressed)" "$RESULT" '.drifted | length' '1'
assert_json_eq "missing deploy → CLAUDE.md is the drifted file" "$RESULT" '.drifted[0].file' 'CLAUDE.md'

# --- Test 7: rules/ deploy_only still reported (no over-suppression) ---
echo ""
echo "Test 7: rules/ deploy_only still reported"
SRC7="$TMPDIR/src7"
DEPLOY7="$TMPDIR/deploy7"
mkdir -p "$SRC7/rules" "$DEPLOY7/rules"
echo "# Identity" > "$SRC7/CLAUDE.md"
echo "# Identity" > "$DEPLOY7/CLAUDE.md"
echo "# Stale rule" > "$DEPLOY7/rules/stale.md"  # deploy_only — should still be reported

RESULT=$(BRANA_SOURCE_DIR="$SRC7" BRANA_DEPLOY_DIR="$DEPLOY7" bash "$HOOK" </dev/null 2>/dev/null)
assert_json_eq "deploy-only rule → drifted" "$RESULT" '.status' 'drifted'
assert_json_count "deploy-only rule → 1 drifted" "$RESULT" '.drifted | length' '1'
assert_json_eq "deploy-only rule → type=deploy_only" "$RESULT" '.drifted[0].type' 'deploy_only'

# --- Test 8: rules/ modified (both exist, different) still reported ---
echo ""
echo "Test 8: rules/ modified still reported"
SRC8="$TMPDIR/src8"
DEPLOY8="$TMPDIR/deploy8"
mkdir -p "$SRC8/rules" "$DEPLOY8/rules"
echo "# Identity" > "$SRC8/CLAUDE.md"
echo "# Identity" > "$DEPLOY8/CLAUDE.md"
echo "# Rule v2" > "$SRC8/rules/a.md"
echo "# Rule v1" > "$DEPLOY8/rules/a.md"

RESULT=$(BRANA_SOURCE_DIR="$SRC8" BRANA_DEPLOY_DIR="$DEPLOY8" bash "$HOOK" </dev/null 2>/dev/null)
assert_json_eq "modified rule → drifted" "$RESULT" '.status' 'drifted'
assert_json_count "modified rule → 1 drifted" "$RESULT" '.drifted | length' '1'
assert_json_eq "modified rule → type=modified" "$RESULT" '.drifted[0].type' 'modified'

# --- Summary ---
echo ""
echo "==================="
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
