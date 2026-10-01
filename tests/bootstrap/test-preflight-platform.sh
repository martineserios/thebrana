#!/usr/bin/env bash
# bootstrap.sh platform preflight (t-3378): PATH `bash` must be >= 4 (hooks run as `bash script`,
# and 9 scripts use mapfile/declare -A); a missing flock(1) warns but does not block.
# Runs only the preflight function, extracted from bootstrap.sh, against fake `bash`/`flock` on PATH.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PASS=0; FAIL=0
assert() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "  PASS: $1"; else FAIL=$((FAIL+1)); echo "  FAIL: $1 (expected '$2', got '$3')"; fi; }

FN="$(sed -n '/^platform_preflight() {/,/^}/p' "$ROOT/bootstrap.sh")"
[ -n "$FN" ] || { echo "  FAIL: platform_preflight() not found in bootstrap.sh"; exit 1; }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
REAL_BASH="$(command -v bash)"
mkbin() { # mkbin DIR BASH_MAJOR HAVE_FLOCK
    mkdir -p "$1"; ln -sf "$(command -v uname)" "$1/uname"; ln -sf "$REAL_BASH" "$1/realbash"
    printf '#!/bin/sh\n[ "$1" = "-c" ] && { echo %s; exit 0; }\nexec realbash "$@"\n' "$2" >"$1/bash"; chmod +x "$1/bash"
    [ "$3" = yes ] && { printf '#!/bin/sh\nexit 0\n' >"$1/flock"; chmod +x "$1/flock"; }
}
run() { # run DIR OSNAME -> "rc|output"
    local out rc
    out="$(PATH="$1" "$REAL_BASH" -c "$FN
BRANA_TEST_OS=$2 platform_preflight" 2>&1)"; rc=$?; echo "$rc|$out"
}
echo "=== test-preflight-platform.sh ==="
mkbin "$T/b3" 3 no;  mkbin "$T/b5f" 5 yes;  mkbin "$T/b5" 5 no
r="$(run "$T/b3" Darwin)";  assert "darwin + bash 3 -> blocks (rc 1)" 1 "${r%%|*}"
case "$r" in *"brew install bash"*) assert "bash-3 message names brew install bash" ok ok;; *) assert "bash-3 message names brew install bash" ok "$r";; esac
# portable-ok-next: assertion text names flock; no GNU flock is invoked
r="$(run "$T/b5" Darwin)";  assert "darwin + bash 5, no flock -> passes" 0 "${r%%|*}"
case "$r" in *"discoteq/discoteq/flock"*) assert "no-flock warning names the brew package" ok ok;; *) assert "no-flock warning names the brew package" ok "$r";; esac
# portable-ok-next: assertion text names flock; no GNU flock is invoked
r="$(run "$T/b5f" Darwin)"; assert "darwin + bash 5 + flock -> silent pass" "0|" "$r"
r="$(run "$T/b3" Linux)";   assert "linux + bash 3 -> still blocks (hooks need bash>=4 anywhere)" 1 "${r%%|*}"
# portable-ok-next: assertion text names flock; no GNU flock is invoked
r="$(run "$T/b5" Linux)";   assert "linux + no flock -> silent (flock warning is macOS-only)" "0|" "$r"
echo; echo "Results: $PASS passed, $FAIL failed"; [ "$FAIL" -eq 0 ]
