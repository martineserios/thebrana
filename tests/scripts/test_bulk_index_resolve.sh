#!/usr/bin/env bash
# Tests for bulk-index.mjs dynamic ruflo path resolution.
# Run: bash tests/scripts/test_bulk_index_resolve.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
BULK_SCRIPT="$REPO_ROOT/system/scripts/bulk-index.mjs"

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

assert_not_contains() {
    local desc="$1" needle="$2" haystack="$3"
    TOTAL=$((TOTAL + 1))
    if echo "$haystack" | grep -qF -- "$needle"; then
        echo "  FAIL: $desc (should NOT contain '$needle')"
        FAIL=$((FAIL + 1))
    else
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    fi
}

assert_contains() {
    local desc="$1" needle="$2" haystack="$3"
    TOTAL=$((TOTAL + 1))
    if echo "$haystack" | grep -qF -- "$needle"; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc (expected to contain '$needle')"
        FAIL=$((FAIL + 1))
    fi
}

echo "=== test_bulk_index_resolve.sh ==="

# ── Test 1: No hardcoded nvm version path ──
echo "Test 1: No hardcoded node version path"
SCRIPT_CONTENT=$(cat "$BULK_SCRIPT")
assert_not_contains "no hardcoded v20.19.0" "v20.19.0" "$SCRIPT_CONTENT"
assert_not_contains "no hardcoded .nvm/versions/node/" ".nvm/versions/node/" "$SCRIPT_CONTENT"

# ── Test 2: Uses dynamic resolution ──
echo "Test 2: Dynamic ruflo resolution"
# Should use execPath, npm root -g, or which ruflo to find the path
assert_contains "uses dynamic resolution" "resolve" "$SCRIPT_CONTENT"

# ── Test 3: ruflo is actually findable on this system ──
echo "Test 3: ruflo is installed and findable"
RUFLO_PATH=$(which ruflo 2>/dev/null || echo "")
assert "ruflo binary exists" "true" "$([ -n "$RUFLO_PATH" ] && echo true || echo false)"

# If ruflo exists, verify its node_modules has the deps we need
if [ -n "$RUFLO_PATH" ]; then
    # Follow symlinks to get real path
    REAL_RUFLO=$(readlink -f "$RUFLO_PATH" 2>/dev/null || realpath "$RUFLO_PATH" 2>/dev/null || echo "$RUFLO_PATH")
    RUFLO_DIR=$(dirname "$(dirname "$REAL_RUFLO")")

    echo "Test 4: ruflo deps exist at resolved path"
    assert "better-sqlite3 exists" "true" "$([ -d "$RUFLO_DIR/node_modules/better-sqlite3" ] && echo true || echo false)"
    assert "@xenova/transformers exists" "true" "$([ -d "$RUFLO_DIR/node_modules/@xenova" ] && echo true || echo false)"
fi

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
