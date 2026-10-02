#!/usr/bin/env bash
# Test: ruflo-mcp.sh pins the memory store to $HOME/.swarm regardless of cwd.
#
# Bug: the wrapper cd's into $CLAUDE_PROJECT_DIR, and ruflo resolves its memory
# root as <cwd>/.swarm unless CLAUDE_FLOW_MEMORY_PATH is set. The repo tracks
# .swarm as a symlink to an absolute Linux home path (a Linux path), so on any
# other machine it dangles and every MCP memory call fails with "Database not
# initialized". On a project whose .swarm is a real directory the MCP silently
# used a second, empty store instead of ~/.swarm.
#
# Fix under test: the wrapper exports CLAUDE_FLOW_MEMORY_PATH=$HOME/.swarm,
# default-if-unset so an explicit caller override still wins.
set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")/../.." && pwd)/system/scripts/ruflo-mcp.sh"
PASS=0; FAIL=0
pass() { echo "PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
FAKE_HOME="$TMP/home"
PROJ="$TMP/project"
STUBS="$TMP/stubs"
mkdir -p "$FAKE_HOME" "$PROJ" "$STUBS"
# The shape that breaks on a non-Linux machine: a dangling absolute symlink.
ln -s /nonexistent/home/someone/.swarm "$PROJ/.swarm"

# Stub ruflo: report what the wrapper handed it, then exit.
cat > "$STUBS/ruflo" <<'STUB'
#!/bin/sh
echo "MEMPATH=${CLAUDE_FLOW_MEMORY_PATH:-}"
echo "CWD=$(pwd -P)"
STUB
chmod +x "$STUBS/ruflo"

run_wrapper() {
    # Minimal PATH: stub first, system tools after. nvm is absent in FAKE_HOME,
    # so the wrapper falls through to `command -v ruflo`.
    env -i HOME="$FAKE_HOME" PATH="$STUBS:/usr/bin:/bin:/usr/sbin:/sbin" \
        CLAUDE_PROJECT_DIR="$PROJ" "$@" \
        bash "$SCRIPT" mcp start 2>/dev/null
}

# T1: unset by the caller -> wrapper pins it to $HOME/.swarm
OUT=$(run_wrapper)
if [[ "$OUT" == *"MEMPATH=$FAKE_HOME/.swarm"* ]]; then
    pass "T1: CLAUDE_FLOW_MEMORY_PATH defaults to \$HOME/.swarm"
else
    fail "T1: expected MEMPATH=$FAKE_HOME/.swarm, got: $OUT"
fi

# T2: the wrapper still starts ruflo from the project dir (CWD heuristics intact)
if [[ "$OUT" == *"CWD=$(cd "$PROJ" && pwd -P)"* ]]; then
    pass "T2: still launches from CLAUDE_PROJECT_DIR"
else
    fail "T2: expected cwd $PROJ, got: $OUT"
fi

# T3: an explicit caller override wins (default-if-unset, not unconditional)
OUT=$(run_wrapper CLAUDE_FLOW_MEMORY_PATH=/custom/store)
if [[ "$OUT" == *"MEMPATH=/custom/store"* ]]; then
    pass "T3: explicit CLAUDE_FLOW_MEMORY_PATH is respected"
else
    fail "T3: override was clobbered, got: $OUT"
fi

echo "---"
echo "passed=$PASS failed=$FAIL"
[ "$FAIL" -eq 0 ]
