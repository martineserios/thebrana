#!/usr/bin/env bash
# bootstrap.sh's stale-binary hints must point at /brana:ship Step 4's atomic rebuild+swap, not a
# bare `cp` onto a running binary (ETXTBSY, nothing atomic), and Step 4 must cover brana-mcp too —
# the MCP server embeds brana-core and a stale one can write corrupt data (branching.md, ADR-067).
# Three layers: the printed hints (run the real 7d/7d2 block on a stale fixture), the Step 4 text,
# and a must-fire check of the brana-mcp liveness probe Step 4 uses (t-3499).
# Run: bash tests/bootstrap/test-stale-binary-hints.sh
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PASS=0; FAIL=0
assert() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "  PASS: $1"; else FAIL=$((FAIL+1)); echo "  FAIL: $1 (expected '$2', got '$3')"; fi; }
has() { case "$2" in *"$1"*) echo yes;; *) echo no;; esac; }
echo "=== test-stale-binary-hints.sh ==="
B="$ROOT/bootstrap.sh"; S="$ROOT/system/skills/ship/SKILL.md"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

# ── 1. What bootstrap PRINTS: run the 7d/7d2 block against a stale fixture ──────────────
mkdir -p "$T/home/.local/bin" "$T/system/cli/rust/crates/x/src"
printf '#!/bin/sh\n' > "$T/home/.local/bin/brana";     chmod +x "$T/home/.local/bin/brana"
printf '#!/bin/sh\n' > "$T/home/.local/bin/brana-mcp"; chmod +x "$T/home/.local/bin/brana-mcp"
touch -t 202601010000 "$T/home/.local/bin/brana" "$T/home/.local/bin/brana-mcp"   # POSIX -t: older than any source written now
echo 'fn main(){}' > "$T/system/cli/rust/crates/x/src/lib.rs"          # newer than both binaries
BLOCK="$(sed -n '/^# 7d: Check brana binary freshness/,/^# 7e: /p' "$B" | sed '$d')"
OUT="$(HOME="$T/home" SYSTEM_DIR="$T/system" bash -c "$BLOCK" 2>&1)"; RC=$?
assert "7d/7d2 block runs on a stale fixture" 0 "$RC"
assert "brana-cli hint fires" yes "$(has 'brana-cli binary may be stale' "$OUT")"
assert "brana-mcp hint fires" yes "$(has 'brana-mcp binary may be stale' "$OUT")"
assert "hints point at /brana:ship" yes "$(has '/brana:ship' "$OUT")"
assert "hints name Step 4" yes "$(has 'Step 4' "$OUT")"
assert "no bare cp onto the live brana (boundary match)" "" "$(printf '%s' "$OUT" | grep -E 'cp target/release/brana ~/\.local/bin/brana([^.[:alnum:]_-]|$)')"
assert "no bare cp onto the live brana-mcp (boundary match)" "" "$(printf '%s' "$OUT" | grep -E 'cp target/release/brana-mcp ~/\.local/bin/brana-mcp([^.[:alnum:]_-]|$)')"
assert "out-of-ship one-liners swap atomically (mv -f)" yes "$(has 'mv -f' "$OUT")"
assert "brana-mcp hint still says to restart sessions" yes "$(has 'restart' "$OUT")"
assert "hint text is inert (no command substitution ran)" no "$(has 'command not found' "$OUT")"

# ── 2. Step 4 text: one build, both binaries, atomic, verify both, restore both ──────────
STEP4="$(sed -n '/Tier-2 ship: rebuild and install/,/^Report result/p' "$S")"
assert "Step 4 builds brana-mcp in the same cargo build as brana-cli" yes "$(has '-p brana-cli -p brana-mcp' "$STEP4")"
assert "Step 4 installs brana-mcp via a .new rename" yes "$(printf '%s' "$STEP4" | grep -qE 'MCP\.new|brana-mcp\.new' && echo yes || echo no)"
assert "Step 4 records why brana-mcp is included (corruption hazard)" yes "$(has 'corrupt' "$STEP4")"
assert "Step 4 tells the shipper to restart sessions for the MCP server" yes "$(has 'restart' "$STEP4")"
assert "Step 4 restores both on failure" yes "$(printf '%s' "$STEP4" | grep -qE 'MCP\.bak" "\$MCP"|brana-mcp\.bak' && echo yes || echo no)"
assert "rollback rule names brana-mcp.bak" yes "$(has 'brana-mcp.bak' "$(sed -n '/Rollback is always optional/p' "$S")")"

# ── 3. Must-fire: the brana-mcp liveness probe Step 4 uses ──────────────────────────────
# Extracted from SKILL.md's MCP-ALIVE-BLOCK so the test always exercises the shipped probe.
PROBE="$(sed -n '/<!-- MCP-ALIVE-BLOCK -->/,/<!-- \/MCP-ALIVE-BLOCK -->/p' "$S" | sed '1d;$d' | sed '1d;$d')"
assert "SKILL.md carries an MCP-ALIVE-BLOCK" yes "$(has 'mcp_alive' "$PROBE")"
if [ -n "$PROBE" ]; then
  eval "$PROBE"
  printf '#!/bin/sh\ncat >/dev/null; exit 0\n' > "$T/silent"; chmod +x "$T/silent"
  printf '#!/bin/sh\ncat >/dev/null; printf %%s "{\\"jsonrpc\\":\\"2.0\\",\\"id\\":1,\\"result\\":{\\"serverInfo\\":{\\"name\\":\\"brana-mcp\\",\\"version\\":\\"0.0.0\\"}}}"\n' > "$T/talks"; chmod +x "$T/talks"
  printf '#!/bin/sh\nsleep 30\n' > "$T/hangs"; chmod +x "$T/hangs"
  mcp_alive "$T/silent" >/dev/null 2>&1; assert "must-fire: a server that prints nothing FAILS the probe" 1 "$?"
  mcp_alive "$T/talks"  >/dev/null 2>&1; assert "a server that answers initialize PASSES the probe" 0 "$?"
  mcp_alive "$T/hangs"  >/dev/null 2>&1; assert "a server that never answers FAILS (bounded wait)" 1 "$?"
fi

echo; echo "Results: $PASS passed, $FAIL failed"; [ "$FAIL" -eq 0 ]
