#!/usr/bin/env bash
# lint-heal.sh assert_allowed — the Layer-2 write allow-list (t-3383, Gate 3).
# It decides which paths lint-heal may archive/delete, so it must (a) compare on a PATH BOUNDARY
# (a raw prefix test let `projects-evil/x` through `projects`), (b) resolve symlinks before `..`,
# and (c) FAIL CLOSED when the resolver errors — an empty allow-list entry made `[[ x == "" * ]]`
# match every path, i.e. open the guard completely.
# Run: bash tests/scripts/test-lint-heal-allowlist.sh
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SRC="$ROOT/system/scripts/lint-heal.sh"
PASS=0; FAIL=0
assert() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "  PASS: $1"; else FAIL=$((FAIL+1)); echo "  FAIL: $1 (expected '$2', got '$3')"; fi; }
echo "=== test-lint-heal-allowlist.sh ==="

FN="$(sed -n '/^assert_allowed() {/,/^}/p' "$SRC")"
[ -n "$FN" ] || { echo "  FAIL: assert_allowed() not found in lint-heal.sh"; exit 1; }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
H="$T/home"; mkdir -p "$H/.claude/projects" "$H/.claude/memory/archive" "$H/.claude/memory/pre-lint-heal" "$H/.swarm" "$T/outside/deep"
ln -s "$T/outside/deep" "$H/.claude/projects/link"
# rc of assert_allowed for PATH under a fake HOME: 0 = allowed, 1 = refused
check() { # check PATH [MEMORY_ROOT]
    ( HOME="$H" MEMORY_ROOT="${2-$H/.claude/projects}"
      source "$ROOT/system/hooks/lib/portable.sh"
      eval "$FN"
      assert_allowed "$1" ) >/dev/null 2>&1
    echo $?
}
assert "a path inside an allowed root is allowed" 0 "$(check "$H/.claude/projects/p1/memory/x.md")"
assert "the root itself is allowed" 0 "$(check "$H/.claude/projects")"
assert "a path outside every root is refused" 1 "$(check "$H/elsewhere/x")"
assert "SIBLING sharing a prefix (projects-evil) is refused (boundary compare)" 1 "$(check "$H/.claude/projects-evil/x")"
assert "single-file entry: a name extending it (lint-heal.lock.evil) is refused" 1 "$(check "$H/.swarm/lint-heal.lock.evil")"
assert "single-file entry itself is allowed" 0 "$(check "$H/.swarm/lint-heal.lock")"
assert "symlink escape: projects/link/../x resolves OUTSIDE (physical) and is refused" 1 "$(check "$H/.claude/projects/link/../x")"
assert "symlink inside the root pointing outside is refused" 1 "$(check "$H/.claude/projects/link/file")"
# resolver failure must fail CLOSED
ln -s "$H/.claude/memory/archive" "$H/.claude/memory/archive.tmp" 2>/dev/null; rm -f "$H/.claude/memory/archive.tmp"
rmdir "$H/.claude/memory/archive"; ln -s "$H/.claude/memory/archive2" "$H/.claude/memory/archive"; ln -s "$H/.claude/memory/archive" "$H/.claude/memory/archive2"
assert "a symlink LOOP in an allow-list root fails closed (does not open the guard)" 1 "$(check "$H/anything/at/all")"
rm -f "$H/.claude/memory/archive" "$H/.claude/memory/archive2"; mkdir -p "$H/.claude/memory/archive"
assert "empty MEMORY_ROOT override fails closed" 1 "$(check "$H/anything/at/all" "")"
assert "MEMORY_ROOT override is honoured when valid" 0 "$(mkdir -p "$T/mroot"; check "$T/mroot/f" "$T/mroot")"
assert "the filesystem root is never an acceptable allow-list entry" 1 "$(check "$H/anything" "/")"
echo; echo "Results: $PASS passed, $FAIL failed"; [ "$FAIL" -eq 0 ]
