#!/usr/bin/env bash
# Tests for no-attribution-commit.sh hook
# Verifies forbidden attribution patterns are blocked, clean commits pass,
# and the /tmp/brana-test-mode sentinel enables pass-through.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/../no-attribution-commit.sh"
PASS=0
FAIL=0

make_bash_input() {
    local cmd="$1"
    printf '{"tool_name":"Bash","tool_input":{"command":"%s"}}' "$cmd"
}

assert_passes() {
    local desc="$1" input="$2"
    local result exit_code
    result=$(echo "$input" | bash "$HOOK" 2>/dev/null)
    exit_code=$?
    if [ "$exit_code" -eq 0 ]; then
        echo "  PASS: $desc"
        ((PASS++))
    else
        echo "  FAIL: $desc — expected exit 0, got exit $exit_code (output: $result)"
        ((FAIL++))
    fi
}

assert_blocks() {
    local desc="$1" input="$2"
    local result exit_code
    result=$(echo "$input" | bash "$HOOK" 2>&1)
    exit_code=$?
    if [ "$exit_code" -eq 2 ]; then
        echo "  PASS: $desc"
        ((PASS++))
    else
        echo "  FAIL: $desc — expected exit 2, got exit $exit_code"
        ((FAIL++))
    fi
}

echo "No-Attribution-Commit Hook Tests"
echo "================================="

# --- Pass-through cases ---

assert_passes "non-git command is ignored" \
    "$(make_bash_input "ls -la")"

assert_passes "git status is not intercepted" \
    "$(make_bash_input "git status")"

assert_passes "clean commit message passes" \
    "$(make_bash_input "git commit -m 'feat: add new feature'")"

assert_passes "gh pr create with clean body passes" \
    "$(make_bash_input "gh pr create --title 'feat: something' --body 'adds a thing'")"

# --- Block cases ---

assert_blocks "Co-Authored-By trailer is blocked" \
    "$(make_bash_input "git commit -m 'feat: thing\n\nCo-Authored-By: Claude'")"

assert_blocks "co-authored-by (lowercase) is blocked" \
    "$(make_bash_input "git commit -m 'fix: stuff\n\nco-authored-by: assistant'")"

assert_blocks "Claude Code attribution is blocked" \
    "$(make_bash_input "git commit -m 'feat: x\n\nGenerated with Claude Code'")"

assert_blocks "Generated with Claude is blocked" \
    "$(make_bash_input "git commit -m 'docs: update\n\nGenerated with Claude'")"

assert_blocks "anthropic.com domain is blocked" \
    "$(make_bash_input "gh pr create --title 'fix: y' --body 'via anthropic.com/claude'")"

assert_blocks "Signed-off-by trailer is blocked" \
    "$(make_bash_input "git commit -m 'chore: x\n\nSigned-off-by: model'")"

assert_blocks "emoji attribution is blocked" \
    "$(make_bash_input "git commit -m 'feat: x\n🤖 Generated with Claude Code'")"

# --- Test-mode sentinel bypass ---

# sentinel present: all patterns pass through
touch /tmp/brana-test-mode

assert_passes "sentinel bypass: Co-Authored-By passes when /tmp/brana-test-mode present" \
    "$(make_bash_input "git commit -m 'feat: x\n\nCo-Authored-By: Claude'")"

assert_passes "sentinel bypass: Claude Code passes when /tmp/brana-test-mode present" \
    "$(make_bash_input "git commit -m 'feat: x\n\nClaude Code generated'")"

rm -f /tmp/brana-test-mode

# after removal: blocks resume
assert_blocks "after sentinel removed: Co-Authored-By is blocked again" \
    "$(make_bash_input "git commit -m 'feat: x\n\nCo-Authored-By: Claude'")"

# --- Summary ---

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
