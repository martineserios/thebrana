#!/usr/bin/env bash
# Tests for ruflo-mcp.sh exec pattern.
# Regression guard: ensures the wrapper uses `exec` (not `& wait`), which is
# required for correct MCP stdio stdin delivery (CC bug #40207 history).
#
# Test 1: static — script contains `exec` and NOT `& wait`
# Test 2: live   — pipe JSON-RPC init, assert jsonrpc response (skip if ruflo absent)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WRAPPER="$SCRIPT_DIR/../../scripts/ruflo-mcp.sh"
PASS=0
FAIL=0

assert_pass() {
    local desc="$1"
    echo "  PASS: $desc"
    ((PASS++))
}

assert_fail() {
    local desc="$1" reason="$2"
    echo "  FAIL: $desc — $reason"
    ((FAIL++))
}

echo "ruflo-mcp.sh Tests"
echo "==================="

# --- Test 1: Static analysis — exec present, & wait absent ---
echo ""
echo "Test 1: Static analysis — exec pattern"

if [ ! -f "$WRAPPER" ]; then
    assert_fail "wrapper exists" "not found at $WRAPPER"
else
    assert_pass "wrapper exists"

    # Must contain `exec "$RUFLO"` (the correct pattern)
    if grep -qE '^exec "\$RUFLO"' "$WRAPPER"; then
        assert_pass "wrapper uses exec"
    else
        assert_fail "wrapper uses exec" "no 'exec \"\$RUFLO\"' line found — stdin forwarding broken"
    fi

    # Must NOT contain backgrounding pattern (& wait) that broke stdin delivery.
    # Skip comment lines (lines starting with optional whitespace then #).
    if grep -vE '^\s*#' "$WRAPPER" | grep -qE '&\s*wait'; then
        assert_fail "wrapper does NOT use & wait" "found '& wait' in non-comment line — this breaks MCP stdin forwarding"
    else
        assert_pass "wrapper does NOT use & wait"
    fi

    # Must `cd "$HOME"` (the fallback when CLAUDE_PROJECT_DIR is unset) so ruflo
    # resolves ~/.swarm/memory.db. Unanchored: the cd is now an indented else-branch
    # after the CLAUDE_PROJECT_DIR check, not a top-level statement (t-2236 drive-by:
    # the old '^cd' anchor went stale when that conditional was added).
    if grep -qE '[[:space:]]*cd "\$HOME"' "$WRAPPER"; then
        assert_pass "wrapper cds to HOME"
    else
        assert_fail "wrapper cds to HOME" "missing 'cd \"\$HOME\"' — ruflo may read wrong DB"
    fi
fi

# --- Test 2: Live handshake (skip if ruflo not available) ---
echo ""
echo "Test 2: Live JSON-RPC handshake"

RUFLO_BIN=""
if [ -f "$HOME/.nvm/nvm.sh" ]; then
    export NVM_DIR="$HOME/.nvm"
    . "$NVM_DIR/nvm.sh" --no-use 2>/dev/null
    CANDIDATE="$(nvm which default 2>/dev/null | sed 's|/node$||')/ruflo"
    [ -x "$CANDIDATE" ] && RUFLO_BIN="$CANDIDATE"
fi
[ -z "$RUFLO_BIN" ] && RUFLO_BIN="$(command -v ruflo 2>/dev/null || true)"

if [ -z "$RUFLO_BIN" ]; then
    echo "  SKIP: ruflo not found — skipping live handshake test"
else
    # Send JSON-RPC initialize request, expect a response within 10s
    INIT_JSON='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"0.1"}}}'
    RESPONSE=$(printf '%s\n' "$INIT_JSON" | timeout 10 bash "$WRAPPER" mcp start 2>/dev/null | head -1 || true)

    if [ -n "$RESPONSE" ] && echo "$RESPONSE" | jq -e '.jsonrpc' >/dev/null 2>&1; then
        assert_pass "live handshake returns jsonrpc response"
    elif [ -z "$RESPONSE" ]; then
        assert_fail "live handshake returns jsonrpc response" "empty response — stdin may not be forwarded"
    else
        assert_fail "live handshake returns jsonrpc response" "response is not valid JSON: $RESPONSE"
    fi
fi

# --- Summary ---
echo ""
echo "==================="
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
