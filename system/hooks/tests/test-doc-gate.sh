#!/usr/bin/env bash
# Tests for doc-gate.sh hook
# Simulates PreToolUse JSON input and checks pass/deny decisions.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/../doc-gate.sh"
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
    git -C "$dir" init -q 2>/dev/null
    git -C "$dir" config user.email "test@test.com"
    git -C "$dir" config user.name "Test"
    # Initial commit so we have HEAD
    echo "init" > "$dir/init.txt"
    git -C "$dir" add -A && git -C "$dir" commit -q -m "init" 2>/dev/null
    if [ "$branch" != "main" ] && [ "$branch" != "master" ]; then
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

echo "Doc Gate Tests"
echo "=============="

# --- Test 1: Non-Bash tool → pass through ---
assert_pass "Non-Bash tool passes through" \
    '{"tool_name":"Write","tool_input":{"file_path":"/tmp/foo.txt"},"cwd":"/tmp"}'

# --- Test 2: Non-git-commit command → pass through ---
assert_pass "Non-git-commit command passes through" \
    '{"tool_name":"Bash","tool_input":{"command":"ls -la"},"cwd":"/tmp"}'

# --- Test 3: Escape hatch --no-doc-check → pass through ---
REPO3="$TMPDIR/repo3"
setup_repo "$REPO3" "feat/test" "system/hooks/new.sh"
assert_pass "Escape hatch --no-doc-check passes through" \
    "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git commit -m 'add hook --no-doc-check'\"},\"cwd\":\"$REPO3\"}"

# --- Test 4: No behavioral files staged → pass through ---
REPO4="$TMPDIR/repo4"
setup_repo "$REPO4" "feat/docs" "README.md"
assert_pass "No behavioral files staged passes through" \
    "$(make_commit_input "$REPO4")"

# --- Test 5: Behavioral + doc files → pass through ---
REPO5="$TMPDIR/repo5"
setup_repo "$REPO5" "feat/both" "system/skills/foo.md" "docs/architecture/bar.md"
assert_pass "Behavioral + doc files together passes through" \
    "$(make_commit_input "$REPO5")"

# --- Test 6: Behavioral without doc files → deny ---
REPO6="$TMPDIR/repo6"
setup_repo "$REPO6" "feat/hooks" "system/hooks/new.sh"
assert_deny "Behavioral without doc files denies" \
    "$(make_commit_input "$REPO6")"

# --- Test 7: Non-git repo (no .git) → pass through ---
NONGIT="$TMPDIR/nongit"
mkdir -p "$NONGIT"
assert_pass "Non-git directory passes through" \
    "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git commit -m 'test'\"},\"cwd\":\"$NONGIT\"}"

# --- Summary ---
echo ""
echo "$PASS/$TOTAL passed"
[ "$FAIL" -eq 0 ] || exit 1
