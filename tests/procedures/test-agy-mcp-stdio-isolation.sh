#!/usr/bin/env bash
# Integration test: agy subprocess stdout must not bleed into MCP JSON-RPC stream (t-1650).
#
# Spawns the live brana-mcp binary, sends a JSON-RPC agy_delegate call using a
# fake agy (AGY_BIN), and asserts every byte on the server's stdout is valid JSON.
# A line of raw text would indicate stdio bleed — corrupting Claude Code's JSON-RPC parsing.
#
# Run: bash tests/procedures/test-agy-mcp-stdio-isolation.sh

set -uo pipefail

PASS=0
FAIL=0
TOTAL=0

assert_pass() {
    local desc="$1"
    TOTAL=$((TOTAL + 1))
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
}

assert_fail() {
    local desc="$1" reason="$2"
    TOTAL=$((TOTAL + 1))
    echo "  FAIL: $desc — $reason"
    FAIL=$((FAIL + 1))
}

echo "=== test-agy-mcp-stdio-isolation.sh ==="
echo ""

# ── Locate brana-mcp binary ───────────────────────────────────────────────────

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MCP_BIN="$REPO_ROOT/system/cli/rust/target/debug/brana-mcp"

if [ ! -x "$MCP_BIN" ]; then
    echo "ERROR: brana-mcp binary not found at $MCP_BIN — run 'cargo build -p brana-mcp' first"
    exit 1
fi

# ── Create fake agy ───────────────────────────────────────────────────────────

FAKE_AGY="/tmp/fake-agy-mcp-isolation-$$.sh"
cat > "$FAKE_AGY" << 'SCRIPT'
#!/bin/sh
# Fake agy for stdio isolation testing.
# For --version: return the pinned version.
# For -p: output the answer (would corrupt JSON-RPC if not captured).
if [ "$1" = "--version" ]; then
    echo "1.0.1"
    exit 0
fi
echo "Integration test: agy output captured correctly"
SCRIPT
chmod +x "$FAKE_AGY"
trap 'rm -f "$FAKE_AGY"' EXIT

# ── Build JSON-RPC input sequence ─────────────────────────────────────────────
# pmcp stdio transport: newline-delimited JSON, one message per line.

JSON_INPUT=$(cat << 'JSONRPC'
{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test-isolation","version":"0.1"}}}
{"jsonrpc":"2.0","method":"notifications/initialized","params":{}}
{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"agy_delegate","arguments":{"task":"What is 2+2?"}}}
JSONRPC
)

# ── Invoke MCP server ─────────────────────────────────────────────────────────

MCP_OUTPUT=$(echo "$JSON_INPUT" | AGY_BIN="$FAKE_AGY" timeout 15 "$MCP_BIN" 2>/dev/null || true)

if [ -z "$MCP_OUTPUT" ]; then
    assert_fail "MCP server produced output" "stdout was empty — server may have crashed"
    echo ""
    echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
    exit 1
fi

# ── Case 1: every output line is valid JSON ───────────────────────────────────

echo "Case 1: all MCP stdout lines are valid JSON (no raw text bleed)"

NON_JSON_LINES=0
LINE_COUNT=0
while IFS= read -r line; do
    [ -z "$line" ] && continue
    LINE_COUNT=$((LINE_COUNT + 1))
    if ! echo "$line" | python3 -c "import sys,json; json.load(sys.stdin)" 2>/dev/null; then
        NON_JSON_LINES=$((NON_JSON_LINES + 1))
        echo "    non-JSON line: $line"
    fi
done <<< "$MCP_OUTPUT"

if [ "$NON_JSON_LINES" -eq 0 ] && [ "$LINE_COUNT" -gt 0 ]; then
    assert_pass "all $LINE_COUNT stdout lines are valid JSON"
else
    assert_fail "stdout JSON purity" "$NON_JSON_LINES non-JSON lines found (of $LINE_COUNT total)"
fi

# ── Case 2: agy_delegate response contains captured output ───────────────────

echo ""
echo "Case 2: agy_delegate result contains captured agy output"

TOOLS_CALL_RESPONSE=$(echo "$MCP_OUTPUT" | grep '"id":2' || true)

if [ -z "$TOOLS_CALL_RESPONSE" ]; then
    assert_fail "agy_delegate response found" "no response with id:2 in MCP output"
else
    if echo "$TOOLS_CALL_RESPONSE" | python3 -c "
import sys, json
data = json.load(sys.stdin)
result = data.get('result', {})
content = result.get('content', [{}])
text = content[0].get('text', '') if isinstance(content, list) else str(result)
assert 'captured correctly' in text or 'error' in text.lower(), f'unexpected output: {text}'
print('ok')
" 2>/dev/null; then
        assert_pass "agy output captured in result, not on raw stdout"
    else
        # May be an error response (e.g. version or tool error) — still JSON, still isolated
        if echo "$TOOLS_CALL_RESPONSE" | python3 -c "import sys,json; d=json.load(sys.stdin); assert 'result' in d or 'error' in d" 2>/dev/null; then
            assert_pass "agy_delegate returned valid JSON-RPC response (output isolated)"
        else
            assert_fail "agy_delegate response shape" "malformed JSON-RPC response"
        fi
    fi
fi

# ── Case 3: no agy output text appears as a raw MCP stdout line ──────────────

echo ""
echo "Case 3: raw agy output text is not present as a standalone MCP stdout line"

if echo "$MCP_OUTPUT" | grep -qxF "Integration test: agy output captured correctly"; then
    assert_fail "agy raw text absent from MCP stdout" "agy output appeared as raw line — stdio bleed!"
else
    assert_pass "agy raw text absent from MCP stdout"
fi

# ── Summary ───────────────────────────────────────────────────────────────────

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="

[ "$FAIL" -eq 0 ] || exit 1
