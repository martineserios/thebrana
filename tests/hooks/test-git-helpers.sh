#!/usr/bin/env bash
# Tests for system/hooks/lib/git-helpers.sh (t-1310).
# Validates extract_git_c_dir and resolve_lookup_dir helper functions.
#
# Run: bash tests/hooks/test-git-helpers.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LIB="$REPO_ROOT/system/hooks/lib/git-helpers.sh"

PASS=0
FAIL=0
TOTAL=0

assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    (( TOTAL++ )) || true
    if [ "$expected" = "$actual" ]; then
        echo "  PASS: $desc"
        (( PASS++ )) || true
    else
        echo "  FAIL: $desc"
        echo "         expected: '$expected'"
        echo "         got:      '$actual'"
        (( FAIL++ )) || true
    fi
}

source "$LIB"

echo "=== git-helpers.sh: extract_git_c_dir ==="

assert_eq "extracts -C path from simple command" \
    "/repo/path" \
    "$(extract_git_c_dir 'git -C /repo/path commit -m "msg"')"

assert_eq "extracts -C path from add command" \
    "/some/worktree" \
    "$(extract_git_c_dir 'git -C /some/worktree add file.txt')"

assert_eq "returns empty when no -C flag" \
    "" \
    "$(extract_git_c_dir 'git commit -m "msg"')"

assert_eq "returns empty for non-git command" \
    "" \
    "$(extract_git_c_dir 'echo hello')"

assert_eq "handles path with hyphens" \
    "/home/user/my-project" \
    "$(extract_git_c_dir 'git -C /home/user/my-project status')"

echo ""
echo "=== git-helpers.sh: resolve_lookup_dir ==="

assert_eq "returns -C path when present" \
    "/worktree/path" \
    "$(resolve_lookup_dir 'git -C /worktree/path commit -m "x"' "/cwd")"

assert_eq "falls back to CWD when no -C" \
    "/current/dir" \
    "$(resolve_lookup_dir 'git commit -m "msg"' "/current/dir")"

assert_eq "returns CWD for non-git command" \
    "/my/cwd" \
    "$(resolve_lookup_dir 'echo hello' "/my/cwd")"

assert_eq "prefers -C over CWD" \
    "/explicit/path" \
    "$(resolve_lookup_dir 'git -C /explicit/path add .' "/cwd/ignored")"

echo ""
echo "=== Results ==="
echo "  Passed: $PASS / $TOTAL"
if [ "$FAIL" -gt 0 ]; then
    echo "  FAILED: $FAIL"
    exit 1
fi
