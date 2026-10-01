#!/usr/bin/env bash
# system/hooks/lib/ruflo-discovery.sh — where is the ruflo binary? (t-3381)
# bootstrap.sh only looked under ~/.nvm, but the Mac guide says `brew install node` + `npm i -g ruflo`
# (Homebrew/npm-prefix bin on PATH): ruflo was "not found", so the sql.js install and the
# ControllerRegistry shim were silently skipped while the MCP wrapper still registered.
# Run: bash tests/hooks/test-ruflo-discovery.sh
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
LIB="$ROOT/system/hooks/lib/ruflo-discovery.sh"
PASS=0; FAIL=0
assert() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "  PASS: $1"; else FAIL=$((FAIL+1)); echo "  FAIL: $1 (expected '$2', got '$3')"; fi; }
echo "=== test-ruflo-discovery.sh ==="
[ -f "$LIB" ] || { echo "  FAIL: $LIB missing"; exit 1; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mk() { mkdir -p "$(dirname "$1")"; printf '#!/bin/sh\nexit 0\n' >"$1"; chmod +x "$1"; }
run() { HOME="$1" PATH="$2" "$(command -v bash)" -c "source '$LIB'; ruflo_find_bin"; }

H="$T/home"; mkdir -p "$H"
assert "nothing installed -> empty, rc 1" "|1" "$(run "$H" "/usr/bin:/bin" | tr -d '\n'; echo "|$(HOME=$H PATH=/usr/bin:/bin bash -c "source '$LIB'; ruflo_find_bin >/dev/null; echo \$?")")"

mk "$H/.nvm/versions/node/v20.1.0/bin/ruflo"
assert "nvm install is found" "$H/.nvm/versions/node/v20.1.0/bin/ruflo" "$(run "$H" "/usr/bin:/bin")"

H2="$T/home2"; mkdir -p "$H2"; mk "$T/brew/bin/ruflo"
assert "Homebrew / npm-prefix ruflo on PATH is found (the Mac case)" "$T/brew/bin/ruflo" "$(run "$H2" "$T/brew/bin:/usr/bin:/bin")"

mk "$H/.nvm/versions/node/v20.1.0/bin/ruflo"; mk "$T/brew/bin/ruflo"
assert "nvm wins over PATH (existing behaviour preserved)" "$H/.nvm/versions/node/v20.1.0/bin/ruflo" "$(run "$H" "$T/brew/bin:/usr/bin:/bin")"

H3="$T/home3"; mkdir -p "$H3"; mk "$T/old/bin/claude-flow"
assert "legacy claude-flow name still found" "$T/old/bin/claude-flow" "$(run "$H3" "$T/old/bin:/usr/bin:/bin")"

H4="$T/home4"; mkdir -p "$H4"; mk "$T/a/bin/ruflo"; mk "$T/b/bin/claude-flow"
assert "ruflo is preferred over claude-flow" "$T/a/bin/ruflo" "$(run "$H4" "$T/b/bin:$T/a/bin:/usr/bin:/bin")"

H5="$T/home5"; mkdir -p "$H5"; mkdir -p "$T/noexec/bin"; printf 'x\n' >"$T/noexec/bin/ruflo"; chmod -x "$T/noexec/bin/ruflo"
assert "a non-executable file named ruflo is not a binary" "" "$(run "$H5" "$T/noexec/bin:/usr/bin:/bin")"
echo; echo "Results: $PASS passed, $FAIL failed"; [ "$FAIL" -eq 0 ]
