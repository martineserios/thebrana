#!/usr/bin/env bash
# Tests for PreToolUse hook: no-attribution-commit.sh (t-1383)
# Regression: violation must exit 2 + write to stderr + leave stdout empty.
#
# Run: bash tests/hooks/test-no-attribution-commit.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HOOK="$REPO_ROOT/system/hooks/no-attribution-commit.sh"

PASS=0
FAIL=0
TOTAL=0

assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    (( TOTAL++ )) || true
    if [ "$actual" = "$expected" ]; then
        echo "  PASS: $desc"
        (( PASS++ )) || true
    else
        echo "  FAIL: $desc"
        echo "         expected: '$expected'"
        echo "         actual:   '$actual'"
        (( FAIL++ )) || true
    fi
}

assert_nonempty() {
    local desc="$1" value="$2"
    (( TOTAL++ )) || true
    if [ -n "$value" ]; then
        echo "  PASS: $desc"
        (( PASS++ )) || true
    else
        echo "  FAIL: $desc (expected non-empty, got empty)"
        (( FAIL++ )) || true
    fi
}

assert_empty() {
    local desc="$1" value="$2"
    (( TOTAL++ )) || true
    if [ -z "$value" ]; then
        echo "  PASS: $desc"
        (( PASS++ )) || true
    else
        echo "  FAIL: $desc"
        echo "         expected empty, got: '$value'"
        (( FAIL++ )) || true
    fi
}

LAST_EXIT=0
LAST_STDOUT=""
LAST_STDERR=""

invoke_hook() {
    local input="$1"
    local stderr_file
    stderr_file=$(mktemp)
    LAST_EXIT=0
    LAST_STDOUT=$(printf '%s' "$input" | bash "$HOOK" 2>"$stderr_file")
    LAST_EXIT=$?
    LAST_STDERR=$(cat "$stderr_file")
    rm -f "$stderr_file"
}

echo "=== test-no-attribution-commit.sh ==="
echo ""

# ── Prerequisite ───────────────────────────────────────────────────────────────
echo "Prerequisite: hook file exists"
(( TOTAL++ )) || true
if [ -f "$HOOK" ]; then
    echo "  PASS: no-attribution-commit.sh exists at system/hooks/"
    (( PASS++ )) || true
else
    echo "  FAIL: hook not found at $HOOK"
    (( FAIL++ )) || true
    exit 1
fi
echo ""

# ── Test 1: Co-Authored-By trailer ────────────────────────────────────────────
echo "Test 1: Co-Authored-By trailer → exit 2, stderr non-empty, stdout empty"
invoke_hook '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"fix: update\n\nCo-Authored-By: Claude\""}}'
assert_eq       "exit code 2"     "2"  "$LAST_EXIT"
assert_nonempty "stderr non-empty"     "$LAST_STDERR"
assert_empty    "stdout empty"         "$LAST_STDOUT"
echo ""

# ── Test 2: Claude Code attribution ───────────────────────────────────────────
echo "Test 2: 'Claude Code' attribution → exit 2, stderr non-empty, stdout empty"
invoke_hook '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"feat: add thing\n\nGenerated with Claude Code\""}}'
assert_eq       "exit code 2"     "2"  "$LAST_EXIT"
assert_nonempty "stderr non-empty"     "$LAST_STDERR"
assert_empty    "stdout empty"         "$LAST_STDOUT"
echo ""

# ── Test 3: Clean commit message ──────────────────────────────────────────────
echo "Test 3: Clean commit message → exit 0"
invoke_hook '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"fix: update routing\""}}'
assert_eq "exit code 0" "0" "$LAST_EXIT"
echo ""

# ── Test 4: Non-commit command passes through ─────────────────────────────────
echo "Test 4: Non-commit command → exit 0"
invoke_hook '{"tool_name":"Bash","tool_input":{"command":"ls -la"}}'
assert_eq "exit code 0 for non-commit" "0" "$LAST_EXIT"
echo ""

# ── Summary ───────────────────────────────────────────────────────────────────
echo "Results: $PASS/$TOTAL passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
