#!/usr/bin/env bash
# Tests for MCP wrapper scripts — validate binary resolution and execution.
set -euo pipefail

SCRIPTS_DIR="$(cd "$(dirname "$0")/../../system/scripts" && pwd)"
PASS=0
FAIL=0

assert_outcome() {
    local label="$1" expected="$2" actual="$3"
    if [ "$actual" = "$expected" ]; then
        PASS=$((PASS + 1))
        echo "  PASS: $label"
    else
        FAIL=$((FAIL + 1))
        echo "  FAIL: $label — expected '$expected', got '$actual'"
    fi
}

assert_contains() {
    local label="$1" haystack="$2" needle="$3"
    if echo "$haystack" | grep -qF "$needle"; then
        PASS=$((PASS + 1))
        echo "  PASS: $label"
    else
        FAIL=$((FAIL + 1))
        echo "  FAIL: $label — output does not contain '$needle'"
    fi
}

echo "=== MCP wrapper script tests ==="
echo ""

# ── Test 1: ruflo-mcp.sh resolves and runs ──
echo "Test 1: ruflo-mcp.sh"
if [ -x "$SCRIPTS_DIR/ruflo-mcp.sh" ]; then
    PASS=$((PASS + 1))
    echo "  PASS: ruflo-mcp.sh is executable"
else
    FAIL=$((FAIL + 1))
    echo "  FAIL: ruflo-mcp.sh not executable"
fi
OUTPUT=$(bash "$SCRIPTS_DIR/ruflo-mcp.sh" --version 2>&1) || OUTPUT=""
assert_contains "ruflo version output" "$OUTPUT" "ruflo"

# ── Test 2: No hardcoded paths in wrapper scripts ──
echo ""
echo "Test 2: no hardcoded /home/ paths"
for script in ruflo-mcp.sh; do
    HARDCODED=$(grep -c '/home/' "$SCRIPTS_DIR/$script" 2>/dev/null) || HARDCODED=0
    if [ "$HARDCODED" -eq 0 ]; then
        PASS=$((PASS + 1))
        echo "  PASS: $script has no hardcoded /home/ paths"
    else
        FAIL=$((FAIL + 1))
        echo "  FAIL: $script has $HARDCODED hardcoded /home/ paths"
    fi
done

# ── Test 3: No hardcoded paths in .mcp.json ──
echo ""
echo "Test 3: .mcp.json uses CLAUDE_PLUGIN_ROOT"
MCP_JSON="$(cd "$SCRIPTS_DIR/../.." && pwd)/.mcp.json"
if [ -f "$MCP_JSON" ]; then
    HARDCODED=$(grep -c '/home/' "$MCP_JSON" 2>/dev/null) || HARDCODED=0
    if [ "$HARDCODED" -eq 0 ]; then
        PASS=$((PASS + 1))
        echo "  PASS: .mcp.json has no hardcoded /home/ paths"
    else
        FAIL=$((FAIL + 1))
        echo "  FAIL: .mcp.json has $HARDCODED hardcoded /home/ paths"
    fi
    PLUGIN_ROOT=$(grep -c 'CLAUDE_PLUGIN_ROOT' "$MCP_JSON" 2>/dev/null) || PLUGIN_ROOT=0
    if [ "$PLUGIN_ROOT" -ge 1 ]; then
        PASS=$((PASS + 1))
        echo "  PASS: .mcp.json uses CLAUDE_PLUGIN_ROOT ($PLUGIN_ROOT refs)"
    else
        FAIL=$((FAIL + 1))
        echo "  FAIL: .mcp.json has only $PLUGIN_ROOT CLAUDE_PLUGIN_ROOT refs (expected >=1)"
    fi
else
    FAIL=$((FAIL + 2))
    echo "  FAIL: .mcp.json not found"
    echo "  FAIL: (skipped CLAUDE_PLUGIN_ROOT check)"
fi

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
exit $FAIL
