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

# --- Test 3: Source-only file (exists in source, not deployed) ---
echo ""
echo "Test 3: Source-only rule"
SRC3="$TMPDIR/src3"
DEPLOY3="$TMPDIR/deploy3"
mkdir -p "$SRC3/rules" "$DEPLOY3/rules"
echo "# Identity" > "$SRC3/CLAUDE.md"
echo "# Identity" > "$DEPLOY3/CLAUDE.md"
echo "# Rule A" > "$SRC3/rules/a.md"
echo "# Rule B" > "$SRC3/rules/b.md"
echo "# Rule A" > "$DEPLOY3/rules/a.md"

RESULT=$(BRANA_SOURCE_DIR="$SRC3" BRANA_DEPLOY_DIR="$DEPLOY3" bash "$HOOK" </dev/null 2>/dev/null)
assert_json_eq "source-only → drifted" "$RESULT" '.status' 'drifted'
assert_json_eq "source-only → type=source_only" "$RESULT" '.drifted[0].type' 'source_only'
assert_json_eq "source-only → correct name" "$RESULT" '.drifted[0].file' 'rules/b.md'

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

# --- Test 5: Multiple drift types combined ---
echo ""
echo "Test 5: Combined drift (modified + source_only + deploy_only)"
SRC5="$TMPDIR/src5"
DEPLOY5="$TMPDIR/deploy5"
mkdir -p "$SRC5/rules" "$DEPLOY5/rules"
echo "# NEW" > "$SRC5/CLAUDE.md"
echo "# OLD" > "$DEPLOY5/CLAUDE.md"
echo "# New rule" > "$SRC5/rules/new.md"
echo "# Stale" > "$DEPLOY5/rules/stale.md"
echo "# Same" > "$SRC5/rules/same.md"
echo "# Same" > "$DEPLOY5/rules/same.md"

RESULT=$(BRANA_SOURCE_DIR="$SRC5" BRANA_DEPLOY_DIR="$DEPLOY5" bash "$HOOK" </dev/null 2>/dev/null)
assert_json_eq "combined → drifted" "$RESULT" '.status' 'drifted'
assert_json_count "combined → 3 drifted" "$RESULT" '.drifted | length' '3'

# --- Test 6: Missing deploy dir → all source_only ---
echo ""
echo "Test 6: Missing deploy dir"
SRC6="$TMPDIR/src6"
DEPLOY6="$TMPDIR/deploy6-nonexistent"
mkdir -p "$SRC6/rules"
echo "# Identity" > "$SRC6/CLAUDE.md"
echo "# Rule" > "$SRC6/rules/a.md"

RESULT=$(BRANA_SOURCE_DIR="$SRC6" BRANA_DEPLOY_DIR="$DEPLOY6" bash "$HOOK" </dev/null 2>/dev/null)
assert_json_eq "missing deploy → drifted" "$RESULT" '.status' 'drifted'
assert_json_count "missing deploy → 2 source_only" "$RESULT" '.drifted | length' '2'

# --- Summary ---
echo ""
echo "==================="
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
