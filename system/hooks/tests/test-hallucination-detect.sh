#!/usr/bin/env bash
# Tests for hallucination-detect.sh (t-677)
# Validates: PostToolUse Bash hook warns when completion commit has no test files.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/../hallucination-detect.sh"
PASS=0; FAIL=0; TOTAL=0
TMPDIR_TEST=$(mktemp -d)
trap 'rm -rf "$TMPDIR_TEST"' EXIT

assert_contains() {
    local desc="$1" output="$2" needle="$3"
    TOTAL=$((TOTAL + 1))
    if echo "$output" | grep -q "$needle"; then
        echo "  PASS: $desc"; PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc (expected '$needle' in output)"
        echo "    got: $output"
        FAIL=$((FAIL + 1))
    fi
}

assert_not_contains() {
    local desc="$1" output="$2" needle="$3"
    TOTAL=$((TOTAL + 1))
    if ! echo "$output" | grep -q "$needle"; then
        echo "  PASS: $desc"; PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc (unexpected '$needle' in output)"
        echo "    got: $output"
        FAIL=$((FAIL + 1))
    fi
}

assert_json_continue() {
    local desc="$1" output="$2"
    TOTAL=$((TOTAL + 1))
    if echo "$output" | jq -e '.continue == true' >/dev/null 2>&1; then
        echo "  PASS: $desc"; PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc (expected .continue == true)"
        echo "    got: $output"
        FAIL=$((FAIL + 1))
    fi
}

setup_repo() {
    local dir="$1"
    mkdir -p "$dir"
    git -C "$dir" init -q -b main 2>/dev/null
    git -C "$dir" config user.email "test@test.com"
    git -C "$dir" config user.name "Test"
    echo "init" > "$dir/init.txt"
    git -C "$dir" add -A && git -C "$dir" commit -q -m "init" 2>/dev/null
}

run_hook() {
    local input="$1"
    echo "$input" | bash "$HOOK" 2>/dev/null
}

echo "=== test-hallucination-detect.sh ==="

# ── Setup ──────────────────────────────────────────────────────────────────
REPO="$TMPDIR_TEST/testrepo"
setup_repo "$REPO"

echo ""
echo "--- Non-commit Bash commands pass through ---"

# Non-git-commit command → no warning, continue
OUT=$(run_hook "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"ls -la\"},\"cwd\":\"$REPO\"}")
assert_json_continue "ls passthrough: continue true" "$OUT"
assert_not_contains "ls passthrough: no warning" "$OUT" "no test"

# git status → no warning
OUT=$(run_hook "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git status\"},\"cwd\":\"$REPO\"}")
assert_json_continue "git status passthrough: continue true" "$OUT"
assert_not_contains "git status: no warning" "$OUT" "no test"

# Non-Bash tool → no warning
OUT=$(run_hook "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$REPO/foo.py\"},\"cwd\":\"$REPO\"}")
assert_json_continue "Edit tool passthrough: continue true" "$OUT"

echo ""
echo "--- Completion commit WITH test files: no warning ---"

# Commit with completion keyword + test file → no warning
echo "def fix(): pass" > "$REPO/fix.py"
echo "def test_fix(): pass" > "$REPO/test_fix.py"
git -C "$REPO" add -A && git -C "$REPO" commit -q -m "fix(auth): resolve token expiry" 2>/dev/null

OUT=$(run_hook "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git commit -m 'fix(auth): resolve token expiry'\"},\"cwd\":\"$REPO\"}")
assert_json_continue "fix+test commit: continue true" "$OUT"
assert_not_contains "fix+test commit: no warning" "$OUT" "no test"

echo ""
echo "--- Completion commit WITHOUT test files: warn ---"

# Commit with completion keyword + NO test file → warning
echo "def complete(): pass" > "$REPO/impl.py"
git -C "$REPO" add -A && git -C "$REPO" commit -q -m "fix(parser): done with nil check" 2>/dev/null

OUT=$(run_hook "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git commit -m 'fix(parser): done with nil check'\"},\"cwd\":\"$REPO\"}")
assert_json_continue "fix-no-test commit: still continues" "$OUT"
assert_contains "fix-no-test commit: warns about tests" "$OUT" "test"

# "complete" keyword → warning
echo "def complete2(): pass" > "$REPO/impl2.py"
git -C "$REPO" add -A && git -C "$REPO" commit -q -m "feat: task complete" 2>/dev/null

OUT=$(run_hook "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git commit -m 'feat: task complete'\"},\"cwd\":\"$REPO\"}")
assert_json_continue "complete-no-test: still continues" "$OUT"
assert_contains "complete-no-test: warns" "$OUT" "test"

# "done" keyword → warning
echo "def done_fn(): pass" > "$REPO/impl3.py"
git -C "$REPO" add -A && git -C "$REPO" commit -q -m "chore: done, closing task" 2>/dev/null

OUT=$(run_hook "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git commit -m 'chore: done, closing task'\"},\"cwd\":\"$REPO\"}")
assert_json_continue "done-no-test: still continues" "$OUT"
assert_contains "done-no-test: warns" "$OUT" "test"

echo ""
echo "--- Commits without completion keywords: no warning ---"

# Regular commit, no keyword → no warning even without tests
echo "def refactor(): pass" > "$REPO/refactor.py"
git -C "$REPO" add -A && git -C "$REPO" commit -q -m "refactor(utils): extract helper method" 2>/dev/null

OUT=$(run_hook "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git commit -m 'refactor(utils): extract helper method'\"},\"cwd\":\"$REPO\"}")
assert_json_continue "refactor commit: continue true" "$OUT"
assert_not_contains "refactor commit: no warning" "$OUT" "no test"

echo ""
echo "--- Non-git-repo CWD: graceful passthrough ---"

OUT=$(run_hook "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git commit -m 'fix: thing'\"},\"cwd\":\"/tmp\"}")
assert_json_continue "non-repo CWD: continue true" "$OUT"

echo ""
echo "Results: $PASS/$TOTAL passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1
exit 0
