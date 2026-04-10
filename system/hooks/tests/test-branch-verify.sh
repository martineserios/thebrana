#!/usr/bin/env bash
# Tests for branch-verify.sh hook
# Simulates PreToolUse JSON input and checks pass/deny decisions.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/../branch-verify.sh"
PASS=0
FAIL=0
TOTAL=0
TMPDIR_BASE=$(mktemp -d)

trap 'rm -rf "$TMPDIR_BASE"' EXIT

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

# Setup a git repo with modified (unstaged) files
# Usage: setup_repo <dir> <branch> <file1> [file2...]
setup_repo() {
    local dir="$1"; shift
    local branch="$1"; shift
    mkdir -p "$dir"
    git -C "$dir" init -q -b main 2>/dev/null
    git -C "$dir" config user.email "test@test.com"
    git -C "$dir" config user.name "Test"
    echo "init" > "$dir/init.txt"
    git -C "$dir" add -A && git -C "$dir" commit -q -m "init" 2>/dev/null
    if [ "$branch" != "main" ]; then
        git -C "$dir" checkout -q -b "$branch" 2>/dev/null
    fi
    # Create modified (not staged) files
    for f in "$@"; do
        mkdir -p "$dir/$(dirname "$f")"
        echo "content" > "$dir/$f"
    done
}

make_add_input() {
    local cwd="$1"
    local files="$2"
    cat <<JSON
{"tool_name":"Bash","tool_input":{"command":"git add $files"},"cwd":"$cwd"}
JSON
}

echo "Branch Verify Tests"
echo "==================="

# --- Test 1: Non-Bash tool → pass through ---
assert_pass "Non-Bash tool passes through" \
    '{"tool_name":"Write","tool_input":{"file_path":"/tmp/foo.txt"},"cwd":"/tmp"}'

# --- Test 2: Non-git-add command → pass through ---
assert_pass "Non-git-add Bash command passes through" \
    '{"tool_name":"Bash","tool_input":{"command":"git commit -m test"},"cwd":"/tmp"}'

# --- Test 3: git status → pass through (not git add) ---
assert_pass "git status passes through" \
    '{"tool_name":"Bash","tool_input":{"command":"git status --porcelain"},"cwd":"/tmp"}'

# --- Test 4: Not on main, behavioral file → pass through ---
REPO4="$TMPDIR_BASE/repo4"
setup_repo "$REPO4" "feat/my-feature" "system/hooks/foo.sh"
assert_pass "Feature branch with behavioral file passes through" \
    "$(make_add_input "$REPO4" "system/hooks/foo.sh")"

# --- Test 5: On main, non-behavioral file → pass through ---
REPO5="$TMPDIR_BASE/repo5"
setup_repo "$REPO5" "main" "docs/README.md"
assert_pass "Main branch with docs-only passes through" \
    "$(make_add_input "$REPO5" "docs/README.md")"

# --- Test 6: On main, explicit behavioral file → deny ---
REPO6="$TMPDIR_BASE/repo6"
setup_repo "$REPO6" "main" "system/hooks/my-hook.sh"
assert_deny "Main branch with explicit behavioral file denies" \
    "$(make_add_input "$REPO6" "system/hooks/my-hook.sh")"

# --- Test 7: On main, system/skills/ → deny ---
REPO7="$TMPDIR_BASE/repo7"
setup_repo "$REPO7" "main" "system/skills/my-skill.md"
assert_deny "Main branch with skills file denies" \
    "$(make_add_input "$REPO7" "system/skills/my-skill.md")"

# --- Test 8: On main, system/procedures/ → deny ---
REPO8="$TMPDIR_BASE/repo8"
setup_repo "$REPO8" "main" "system/procedures/build.md"
assert_deny "Main branch with procedures file denies" \
    "$(make_add_input "$REPO8" "system/procedures/build.md")"

# --- Test 9: On main, git add . with behavioral changes → deny ---
REPO9="$TMPDIR_BASE/repo9"
setup_repo "$REPO9" "main" "system/hooks/another.sh"
assert_deny "Main branch with git add . and behavioral changes denies" \
    "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git add .\"},\"cwd\":\"$REPO9\"}"

# --- Test 10: On main, git add -A with behavioral changes → deny ---
REPO10="$TMPDIR_BASE/repo10"
setup_repo "$REPO10" "main" "system/cli/src/main.rs"
assert_deny "Main branch with git add -A and behavioral changes denies" \
    "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git add -A\"},\"cwd\":\"$REPO10\"}"

# --- Test 11: On main, git add . with only doc changes → pass through ---
REPO11="$TMPDIR_BASE/repo11"
setup_repo "$REPO11" "main" "docs/guide/overview.md"
assert_pass "Main branch with git add . and docs-only passes through" \
    "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git add .\"},\"cwd\":\"$REPO11\"}"

# --- Test 12: Escape hatch --force-main → pass through ---
REPO12="$TMPDIR_BASE/repo12"
setup_repo "$REPO12" "main" "system/hooks/forced.sh"
assert_pass "Escape hatch --force-main passes through" \
    "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git add system/hooks/forced.sh --force-main\"},\"cwd\":\"$REPO12\"}"

# --- Test 13: .claude/rules/ → deny ---
REPO13="$TMPDIR_BASE/repo13"
setup_repo "$REPO13" "main" ".claude/rules/my-rule.md"
assert_deny "Main branch with .claude/rules/ file denies" \
    "$(make_add_input "$REPO13" ".claude/rules/my-rule.md")"

# --- Summary ---
echo ""
echo "$PASS/$TOTAL passed"
[ "$FAIL" -eq 0 ] || exit 1
