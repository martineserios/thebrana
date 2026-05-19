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
    if [[ "$haystack" == *"$needle"* ]]; then
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
    if [[ "$haystack" == *"$needle"* ]]; then
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

# ── Test 3: ruflo is findable via at least one resolution strategy ──
echo "Test 3: ruflo is installed and findable"
# Load nvm if available (needed in non-interactive shells)
export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh" 2>/dev/null || true

# Try the same strategies as bulk-index.mjs
RUFLO_PATH=""
# Strategy 1: npm root -g
NPM_ROOT=$(npm root -g 2>/dev/null || echo "")
[ -n "$NPM_ROOT" ] && [ -d "$NPM_ROOT/ruflo/node_modules" ] && RUFLO_PATH="$NPM_ROOT/ruflo/node_modules"
# Strategy 2: node execPath prefix
if [ -z "$RUFLO_PATH" ]; then
    NODE_BIN=$(command -v node 2>/dev/null || echo "")
    if [ -n "$NODE_BIN" ]; then
        NODE_DIR=$(dirname "$(dirname "$NODE_BIN")")
        [ -d "$NODE_DIR/lib/node_modules/ruflo/node_modules" ] && RUFLO_PATH="$NODE_DIR/lib/node_modules/ruflo/node_modules"
    fi
fi
# Strategy 3: which ruflo → follow symlink
if [ -z "$RUFLO_PATH" ]; then
    RUFLO_BIN=$(command -v ruflo 2>/dev/null || echo "")
    if [ -n "$RUFLO_BIN" ]; then
        REAL_RUFLO=$(readlink -f "$RUFLO_BIN" 2>/dev/null || echo "$RUFLO_BIN")
        CAND=$(dirname "$(dirname "$REAL_RUFLO")")/node_modules
        [ -d "$CAND" ] && RUFLO_PATH="$CAND"
    fi
fi

assert "ruflo findable via at least one strategy" "true" "$([ -n "$RUFLO_PATH" ] && echo true || echo false)"

if [ -n "$RUFLO_PATH" ]; then
    echo "Test 4: ruflo deps exist at resolved path ($RUFLO_PATH)"
    assert "better-sqlite3 exists" "true" "$([ -d "$RUFLO_PATH/better-sqlite3" ] && echo true || echo false)"
    assert "@xenova/transformers exists" "true" "$([ -d "$RUFLO_PATH/@xenova" ] && echo true || echo false)"
fi

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
