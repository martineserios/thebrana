#!/usr/bin/env bash
# Tests for main-guard.sh hook
# Simulates PreToolUse JSON input and checks pass/deny decisions.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/../main-guard.sh"
PASS=0
FAIL=0
TOTAL=0
TMPDIR=$(mktemp -d)

trap 'rm -rf "$TMPDIR"' EXIT

# ── Helpers ──────────────────────────────────────────────

assert_pass() {
    local desc="$1"; shift
    TOTAL=$((TOTAL + 1))
    local output
    output=$(echo "$1" | BRANA_HOOK_PROFILE=standard bash "$HOOK" 2>/dev/null)
    if echo "$output" | jq -e '.continue == true' >/dev/null 2>&1; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc"
        echo "    expected: continue=true"
        echo "    got:      $output"
        FAIL=$((FAIL + 1))
    fi
}

assert_deny() {
    local desc="$1"; shift
    TOTAL=$((TOTAL + 1))
    local output
    output=$(echo "$1" | BRANA_HOOK_PROFILE=standard bash "$HOOK" 2>/dev/null)
    if echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null 2>&1; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc"
        echo "    expected: permissionDecision=deny"
        echo "    got:      $output"
        FAIL=$((FAIL + 1))
    fi
}

# Setup a git repo with specific staged files
# Usage: setup_repo <dir> <branch> <file1> [file2...]
setup_repo() {
    local dir="$1"; shift
    local branch="$1"; shift
    mkdir -p "$dir"
    git -C "$dir" init -q -b main 2>/dev/null
    git -C "$dir" config user.email "test@test.com"
    git -C "$dir" config user.name "Test"
    # Initial commit so we have HEAD
    echo "init" > "$dir/init.txt"
    git -C "$dir" add -A && git -C "$dir" commit -q -m "init" 2>/dev/null
    if [ "$branch" != "main" ]; then
        git -C "$dir" checkout -q -b "$branch" 2>/dev/null
    fi
    # Create and stage the requested files
    for f in "$@"; do
        mkdir -p "$dir/$(dirname "$f")"
        echo "content" > "$dir/$f"
        git -C "$dir" add "$f"
    done
}

make_commit_input() {
    local cwd="$1"; shift
    local msg="${1:-test commit}"
    cat <<JSON
{"tool_name":"Bash","tool_input":{"command":"git commit -m '$msg'"},"cwd":"$cwd"}
JSON
}

echo "Main Guard Tests"
echo "================"

# --- Test 1: Non-Bash tool → pass through ---
assert_pass "Non-Bash tool passes through" \
    '{"tool_name":"Write","tool_input":{"file_path":"/tmp/foo.txt"},"cwd":"/tmp"}'

# --- Test 2: Non-git-commit command → pass through ---
assert_pass "Non-git-commit command passes through" \
    '{"tool_name":"Bash","tool_input":{"command":"ls -la"},"cwd":"/tmp"}'

# --- Test 3: Escape hatch --force-main → pass through ---
REPO3="$TMPDIR/repo3"
setup_repo "$REPO3" "main" "system/skills/foo.md"
assert_pass "Escape hatch --force-main passes through" \
    "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git commit -m 'add skill --force-main'\"},\"cwd\":\"$REPO3\"}"

# --- Test 4: Not on main branch → pass through ---
REPO4="$TMPDIR/repo4"
setup_repo "$REPO4" "feat/something" "system/skills/foo.md"
assert_pass "Not on main branch passes through" \
    "$(make_commit_input "$REPO4")"

# --- Test 5: On main, no behavioral files → pass through ---
REPO5="$TMPDIR/repo5"
setup_repo "$REPO5" "main" "docs/README.md"
assert_pass "On main with only docs passes through" \
    "$(make_commit_input "$REPO5")"

# --- Test 6: On main, behavioral files → deny ---
REPO6="$TMPDIR/repo6"
setup_repo "$REPO6" "main" "system/skills/foo.md"
assert_deny "On main with behavioral files denies" \
    "$(make_commit_input "$REPO6")"

# --- Test 7: On main, behavioral files with --force-main escape → pass through ---
REPO7="$TMPDIR/repo7"
setup_repo "$REPO7" "main" "system/skills/bar.md"
assert_pass "On main with behavioral files but --force-main passes through" \
    "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git commit -m 'hotfix --force-main'\"},\"cwd\":\"$REPO7\"}"

# --- Test 8: git -C <other-repo-main> commit with behavioral files → deny ---
# The hook must match "git -C <path> commit" and check the -C target's branch+staged
# files. Before fix: passes through (pattern "git commit" never matches). After fix: deny.
REPO8="$TMPDIR/repo8-other"
setup_repo "$REPO8" "main" "system/skills/new.md"
assert_deny "git -C <other-repo-on-main> commit with behavioral files denied (t-1153)" \
    "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git -C $REPO8 commit -m 'add skill'\"},\"cwd\":\"/tmp\"}"

# --- Test 9: git -C <worktree-feat> commit — worktree on feature branch → pass through ---
REPO9="$TMPDIR/repo9"
WT9="$TMPDIR/wt9"
setup_repo "$REPO9" "main" "docs/init.md"
git -C "$REPO9" worktree add "$WT9" -b feat/t-1153-feat 2>/dev/null
mkdir -p "$WT9/system/skills"
echo "content" > "$WT9/system/skills/new.md"
git -C "$WT9" add system/skills/new.md
assert_pass "git -C <worktree-feat> commit passes through (t-1153 fix)" \
    "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git -C $WT9 commit -m 'add skill'\"},\"cwd\":\"$REPO9\"}"

# --- Summary ---
echo ""
echo "$PASS/$TOTAL passed"
[ "$FAIL" -eq 0 ] || exit 1
