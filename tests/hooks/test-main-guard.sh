#!/usr/bin/env bash
# Tests for PreToolUse hook: main-guard.sh (t-1194)
# Validates: main-branch protection, --force-main bypass, --rules-only escape hatch
#
# Run: bash tests/hooks/test-main-guard.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HOOK="$REPO_ROOT/system/hooks/main-guard.sh"

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

# Build hook input JSON for a git commit command with given staged files on a given branch
make_input() {
    local branch="$1" commit_msg="$2" git_dir="$3"
    # Use \\\" so printf emits literal \" into the JSON string (valid JSON-escaped quotes)
    printf '{"tool_name":"Bash","cwd":"%s","tool_input":{"command":"git -C %s commit -m \\\"%s\\\""}}' \
        "$git_dir" "$git_dir" "$commit_msg"
}

# Set up a temp git repo on a given branch with given staged files
setup_repo() {
    local dir="$1" branch="$2"
    shift 2
    local staged_files=("$@")
    git init -q "$dir"
    git -C "$dir" config user.email "test@test"
    git -C "$dir" config user.name "test"
    git -C "$dir" checkout -q -b "$branch" 2>/dev/null || git -C "$dir" checkout -q "$branch" 2>/dev/null || true
    # Create initial commit so branch exists
    touch "$dir/.gitkeep"
    git -C "$dir" add .gitkeep
    git -C "$dir" commit -q -m "init"
    # Stage each requested file
    for f in "${staged_files[@]}"; do
        mkdir -p "$dir/$(dirname "$f")"
        echo "content" > "$dir/$f"
        git -C "$dir" add "$f"
    done
}

echo "=== test-main-guard.sh ==="
echo ""

TMPDIR_BASE=$(mktemp -d)
trap 'rm -rf "$TMPDIR_BASE"' EXIT

# ── Prerequisite ──────────────────────────────────────────────────────────────
echo "Prerequisite: hook file"
(( TOTAL++ )) || true
if [ -f "$HOOK" ]; then
    echo "  PASS: main-guard.sh exists at system/hooks/"
    (( PASS++ )) || true
else
    echo "  FAIL: main-guard.sh not found at $HOOK"
    (( FAIL++ )) || true
fi
echo ""

# ── Test 1: Non-Bash tool passes through ──────────────────────────────────────
echo "Test 1: Non-Bash tool passes through"
input='{"tool_name":"Write","tool_input":{"command":"git commit -m \"test\""}}'
out=$(run_hook "$input")
assert_contains "continue:true for non-Bash tool" '"continue"[[:space:]]*:[[:space:]]*true' "$out"
echo ""

# ── Test 2: Non-commit command passes through ─────────────────────────────────
echo "Test 2: Non-commit Bash command passes through"
REPO="$TMPDIR_BASE/repo-nc"
setup_repo "$REPO" main "system/hooks/foo.sh"
input='{"tool_name":"Bash","cwd":"'"$REPO"'","tool_input":{"command":"ls -la"}}'
out=$(run_hook "$input")
assert_contains "continue:true for non-commit command" '"continue"[[:space:]]*:[[:space:]]*true' "$out"
echo ""

# ── Test 3: Non-main branch passes through ────────────────────────────────────
echo "Test 3: Commit on feat/* branch passes through"
REPO="$TMPDIR_BASE/repo-feat"
setup_repo "$REPO" feat/t-999-test "system/hooks/foo.sh"
input=$(make_input "feat/t-999-test" "chore: test" "$REPO")
out=$(run_hook "$input")
assert_contains "continue:true on feat branch" '"continue"[[:space:]]*:[[:space:]]*true' "$out"
echo ""

# ── Test 4: Non-behavioral files on main pass through ─────────────────────────
echo "Test 4: Non-behavioral commit on main passes through"
REPO="$TMPDIR_BASE/repo-docs"
setup_repo "$REPO" main "docs/guide/cli.md"
input=$(make_input "main" "docs: update cli guide" "$REPO")
out=$(run_hook "$input")
assert_contains "continue:true for docs-only commit on main" '"continue"[[:space:]]*:[[:space:]]*true' "$out"
echo ""

# ── Test 5: Behavioral file on main is blocked ───────────────────────────────
echo "Test 5: Behavioral file (system/hooks/) staged on main is denied"
REPO="$TMPDIR_BASE/repo-block"
setup_repo "$REPO" main "system/hooks/some-hook.sh"
input=$(make_input "main" "feat: add hook" "$REPO")
out=$(run_hook "$input")
assert_contains "deny response for behavioral file on main" '"permissionDecision"[[:space:]]*:[[:space:]]*"deny"' "$out"
assert_contains "deny message mentions feature branch" "feature branch|feat/" "$out"
echo ""

# ── Test 6: --force-main bypasses the guard ───────────────────────────────────
echo "Test 6: --force-main bypasses guard"
REPO="$TMPDIR_BASE/repo-force"
setup_repo "$REPO" main "system/hooks/some-hook.sh"
input=$(make_input "main" "feat: add hook --force-main" "$REPO")
out=$(run_hook "$input")
assert_contains "continue:true with --force-main" '"continue"[[:space:]]*:[[:space:]]*true' "$out"
echo ""

# ── Test 7: --rules-only with only rules files passes ─────────────────────────
echo "Test 7: --rules-only with rules-only staged files passes"
REPO="$TMPDIR_BASE/repo-rules-ok"
setup_repo "$REPO" main ".claude/rules/my-rule.md"
input=$(make_input "main" "chore: add rule --rules-only" "$REPO")
out=$(run_hook "$input")
assert_contains "continue:true with --rules-only and rules-only files" '"continue"[[:space:]]*:[[:space:]]*true' "$out"
echo ""

# ── Test 8: --rules-only with mixed staged files is denied ────────────────────
echo "Test 8: --rules-only with non-rules behavioral files staged is denied"
REPO="$TMPDIR_BASE/repo-rules-mixed"
setup_repo "$REPO" main ".claude/rules/my-rule.md" "system/hooks/some-hook.sh"
input=$(make_input "main" "chore: add rule --rules-only" "$REPO")
out=$(run_hook "$input")
assert_contains "deny for --rules-only with non-rules files" '"permissionDecision"[[:space:]]*:[[:space:]]*"deny"' "$out"
assert_contains "deny message names the non-rules file" "some-hook.sh|non-rules" "$out"
echo ""

# ── Test 9: --rules-only with rules + docs passes ─────────────────────────────
echo "Test 9: --rules-only with rules + doc files passes (docs are not behavioral)"
REPO="$TMPDIR_BASE/repo-rules-docs"
setup_repo "$REPO" main ".claude/rules/my-rule.md" "docs/guide/cli.md"
input=$(make_input "main" "chore: add rule and update docs --rules-only" "$REPO")
out=$(run_hook "$input")
assert_contains "continue:true for rules+docs with --rules-only" '"continue"[[:space:]]*:[[:space:]]*true' "$out"
echo ""

# ── Test 10: git-hooks scripts are behavioral (t-1195) ───────────────────────
echo "Test 10: system/scripts/git-hooks/* is a behavioral path"
REPO="$TMPDIR_BASE/repo-git-hooks"
setup_repo "$REPO" main "system/scripts/git-hooks/pre-commit"
input=$(make_input "main" "fix: update pre-commit hook" "$REPO")
out=$(run_hook "$input")
assert_contains "git-hooks on main → denied" '"permissionDecision"[[:space:]]*:[[:space:]]*"deny"' "$out"
assert_contains "git-hooks deny mentions feature branch" "feature branch|feat/" "$out"
echo ""

# ── Summary ───────────────────────────────────────────────────────────────────
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
