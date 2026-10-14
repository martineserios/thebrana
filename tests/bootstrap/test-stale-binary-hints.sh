#!/usr/bin/env bash
# bootstrap.sh's stale-binary hints must point at /brana:ship Step 4's atomic rebuild+swap, not a
# bare `cp` onto a running binary (ETXTBSY, nothing atomic), and Step 4 must cover brana-mcp too —
# the MCP server embeds brana-core and lagged silently after every core change (t-3499).
# Run: bash tests/bootstrap/test-stale-binary-hints.sh
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PASS=0; FAIL=0
assert() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "  PASS: $1"; else FAIL=$((FAIL+1)); echo "  FAIL: $1 (expected '$2', got '$3')"; fi; }
has() { case "$2" in *"$1"*) echo yes;; *) echo no;; esac; }
echo "=== test-stale-binary-hints.sh ==="
B="$ROOT/bootstrap.sh"; S="$ROOT/system/skills/ship/SKILL.md"

# 7d: brana-cli hint
CLI_HINT="$(sed -n '/brana-cli binary may be stale/,/^    else/p' "$B")"
assert "brana-cli hint exists" yes "$(has 'may be stale' "$CLI_HINT")"
assert "brana-cli hint points at /brana:ship Step 4" yes "$(has '/brana:ship' "$CLI_HINT")"
assert "brana-cli hint has no bare cp onto the live binary" no "$(has 'cp target/release/brana ~/.local/bin/brana' "$CLI_HINT")"
assert "brana-cli hint's out-of-ship recipe swaps atomically (mv -f)" yes "$(has 'mv -f' "$CLI_HINT")"

# 7d2: brana-mcp hint
MCP_HINT="$(sed -n '/brana-mcp binary may be stale/,/^    else/p' "$B")"
assert "brana-mcp hint exists" yes "$(has 'may be stale' "$MCP_HINT")"
assert "brana-mcp hint points at /brana:ship Step 4" yes "$(has '/brana:ship' "$MCP_HINT")"
assert "brana-mcp hint has no bare cp onto the live binary" no "$(has 'cp target/release/brana-mcp ~/.local/bin/brana-mcp' "$MCP_HINT")"
assert "brana-mcp hint still says to restart sessions" yes "$(has 'restart' "$MCP_HINT")"

# Step 4 decision: brana-mcp is rebuilt and installed by the same atomic recipe
STEP4="$(sed -n '/Tier-2 ship: rebuild and install/,/^Report result/p' "$S")"
assert "Step 4 builds brana-mcp" yes "$(has '-p brana-mcp' "$STEP4")"
assert "Step 4 installs brana-mcp atomically" yes "$(has 'brana-mcp.new' "$STEP4")"
assert "Step 4 records the brana-mcp decision" yes "$(has 'brana-mcp' "$(printf '%s' "$STEP4" | grep -i 'decision\|lags\|embeds')")"
assert "Step 4 tells the shipper to restart sessions for the MCP server" yes "$(has 'restart' "$STEP4")"

echo; echo "Results: $PASS passed, $FAIL failed"; [ "$FAIL" -eq 0 ]
