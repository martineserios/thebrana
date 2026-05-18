#!/usr/bin/env bash
# Tests for PreToolUse hook: branch-verify.sh (t-1424)
# Validates: behavioral path blocking, reverse-direction false positive fix,
#            non-behavioral paths pass through on main.
#
# Run: bash tests/hooks/test-branch-verify.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HOOK="$REPO_ROOT/system/hooks/branch-verify.sh"

# shellcheck source=_helpers.sh
source "$SCRIPT_DIR/_helpers.sh"

PASS=0
FAIL=0
TOTAL=0

assert_contains() {
    local desc="$1" needle="$2" haystack="$3"
    (( TOTAL++ )) || true
    if echo "$haystack" | grep -qE "$needle"; then
        echo "  PASS: $desc"
        (( PASS++ )) || true
    else
        echo "  FAIL: $desc"
        echo "         expected pattern: '$needle'"
        echo "         in output: '$haystack'"
        (( FAIL++ )) || true
    fi
}

assert_not_contains() {
    local desc="$1" needle="$2" haystack="$3"
    (( TOTAL++ )) || true
    if ! echo "$haystack" | grep -qE "$needle"; then
        echo "  PASS: $desc"
        (( PASS++ )) || true
    else
        echo "  FAIL: $desc"
        echo "         unexpected pattern found: '$needle'"
        echo "         in output: '$haystack'"
        (( FAIL++ )) || true
    fi
}

# Minimal git repo on a given branch (no staged files needed for explicit-path tests)
setup_repo() {
    local dir="$1" branch="$2"
    git init -q "$dir"
    git -C "$dir" config user.email "test@test"
    git -C "$dir" config user.name "test"
    git -C "$dir" checkout -q -b "$branch" 2>/dev/null || git -C "$dir" checkout -q "$branch" 2>/dev/null || true
    touch "$dir/.gitkeep"
    git -C "$dir" add .gitkeep
    git -C "$dir" commit -q -m "init"
}

make_add_input() {
    local repo="$1" files="$2"
    printf '{"tool_name":"Bash","cwd":"%s","tool_input":{"command":"git add %s"}}' "$repo" "$files"
}

echo "=== test-branch-verify.sh ==="
echo ""

TMPDIR_BASE=$(mktemp -d)
trap 'rm -rf "$TMPDIR_BASE"' EXIT

# ── Prerequisite ──────────────────────────────────────────────────────────────
echo "Prerequisite: hook file exists"
(( TOTAL++ )) || true
if [ -f "$HOOK" ]; then
    echo "  PASS: branch-verify.sh exists"
    (( PASS++ )) || true
else
    echo "  FAIL: branch-verify.sh not found at $HOOK"
    (( FAIL++ )) || true
fi
echo ""

# ── Test 1: Non-Bash tool passes through ─────────────────────────────────────
echo "Test 1: Non-Bash tool passes through"
input='{"tool_name":"Write","tool_input":{"command":"git add system/hooks/foo.sh"}}'
out=$(run_hook "$input")
assert_contains "continue:true for non-Bash tool" '"continue"[[:space:]]*:[[:space:]]*true' "$out"
echo ""

# ── Test 2: Non-git-add command passes through ────────────────────────────────
echo "Test 2: Non-git-add Bash command passes through"
REPO="$TMPDIR_BASE/repo-nongit"
setup_repo "$REPO" main
input='{"tool_name":"Bash","cwd":"'"$REPO"'","tool_input":{"command":"ls system/hooks/"}}'
out=$(run_hook "$input")
assert_contains "continue:true for non-git-add command" '"continue"[[:space:]]*:[[:space:]]*true' "$out"
echo ""

# ── Test 3: Feat branch passes through (behavioral file) ─────────────────────
echo "Test 3: Behavioral file on feat branch passes through"
REPO="$TMPDIR_BASE/repo-feat"
setup_repo "$REPO" feat/t-999-test
input=$(make_add_input "$REPO" "system/hooks/my-hook.sh")
out=$(run_hook "$input")
assert_contains "continue:true for behavioral file on feat branch" '"continue"[[:space:]]*:[[:space:]]*true' "$out"
echo ""

# ── Test 4: Behavioral file on main is denied ────────────────────────────────
echo "Test 4: Behavioral file (system/hooks/) staged on main is denied"
REPO="$TMPDIR_BASE/repo-block"
setup_repo "$REPO" main
input=$(make_add_input "$REPO" "system/hooks/my-hook.sh")
out=$(run_hook "$input")
assert_contains "deny for behavioral file on main" '"permissionDecision"[[:space:]]*:[[:space:]]*"deny"' "$out"
assert_contains "deny message mentions feature branch" "feature branch|feat/" "$out"
echo ""

# ── Test 5: --force-main bypass works ────────────────────────────────────────
echo "Test 5: --force-main bypasses the guard"
REPO="$TMPDIR_BASE/repo-force"
setup_repo "$REPO" main
input='{"tool_name":"Bash","cwd":"'"$REPO"'","tool_input":{"command":"git add system/hooks/my-hook.sh --force-main"}}'
out=$(run_hook "$input")
assert_contains "continue:true with --force-main" '"continue"[[:space:]]*:[[:space:]]*true' "$out"
echo ""

# ── Test 6 (regression t-1424): .claude/tasks.json passes through on main ────
echo "Test 6 (regression t-1424): .claude/tasks.json passes through on main"
REPO="$TMPDIR_BASE/repo-tasks"
setup_repo "$REPO" main
input=$(make_add_input "$REPO" ".claude/tasks.json")
out=$(run_hook "$input")
assert_contains "continue:true for .claude/tasks.json on main" '"continue"[[:space:]]*:[[:space:]]*true' "$out"
assert_not_contains "no deny for .claude/tasks.json" '"permissionDecision"[[:space:]]*:[[:space:]]*"deny"' "$out"
echo ""

# ── Test 7 (regression t-1424): docs/ideas/foo.md passes through on main ─────
echo "Test 7 (regression t-1424): docs/ideas/foo.md passes through on main"
REPO="$TMPDIR_BASE/repo-docs"
setup_repo "$REPO" main
input=$(make_add_input "$REPO" "docs/ideas/foo.md")
out=$(run_hook "$input")
assert_contains "continue:true for docs/ideas/foo.md on main" '"continue"[[:space:]]*:[[:space:]]*true' "$out"
assert_not_contains "no deny for docs/ideas/foo.md" '"permissionDecision"[[:space:]]*:[[:space:]]*"deny"' "$out"
echo ""

# ── Test 8 (regression t-1424): bare parent dir "system" passes through ──────
# Before fix: is_behavioral("system") returned true via reverse-direction case
# (system/hooks matches system/*). After fix: returns false — staging a bare
# parent dir is not a real behavioral-file add.
echo "Test 8 (regression t-1424): bare dir 'system' passes through on main"
REPO="$TMPDIR_BASE/repo-bare-dir"
setup_repo "$REPO" main
input=$(make_add_input "$REPO" "system")
out=$(run_hook "$input")
assert_contains "continue:true for bare 'system' on main" '"continue"[[:space:]]*:[[:space:]]*true' "$out"
assert_not_contains "no deny for bare 'system'" '"permissionDecision"[[:space:]]*:[[:space:]]*"deny"' "$out"
echo ""

# ── Test 9: .claude/rules/ is still behavioral ───────────────────────────────
echo "Test 9: .claude/rules/ file on main is denied"
REPO="$TMPDIR_BASE/repo-rules"
setup_repo "$REPO" main
input=$(make_add_input "$REPO" ".claude/rules/my-rule.md")
out=$(run_hook "$input")
assert_contains "deny for .claude/rules/ on main" '"permissionDecision"[[:space:]]*:[[:space:]]*"deny"' "$out"
echo ""

# ── Results ───────────────────────────────────────────────────────────────────
echo ""
echo "=== Results ==="
echo "  Passed: $PASS / $TOTAL"
if [ "$FAIL" -gt 0 ]; then
    echo "  FAILED: $FAIL"
    exit 1
fi
