#!/usr/bin/env bash
# Tests for system/hooks/lib/layer1-paths.sh (t-1317).
# Validates is_layer1_file correctly identifies CLAUDE.md as Layer 1.
#
# Run: bash tests/hooks/test-layer1-paths.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LIB="$REPO_ROOT/system/hooks/lib/layer1-paths.sh"

PASS=0
FAIL=0
TOTAL=0

assert_true() {
    local desc="$1"
    local result="$2"
    (( TOTAL++ )) || true
    if [ "$result" = "true" ]; then
        echo "  PASS: $desc"
        (( PASS++ )) || true
    else
        echo "  FAIL: $desc (expected true, got false)"
        (( FAIL++ )) || true
    fi
}

assert_false() {
    local desc="$1"
    local result="$2"
    (( TOTAL++ )) || true
    if [ "$result" = "false" ]; then
        echo "  PASS: $desc"
        (( PASS++ )) || true
    else
        echo "  FAIL: $desc (expected false, got true)"
        (( FAIL++ )) || true
    fi
}

check() {
    local path="$1"
    if is_layer1_file "$path"; then echo "true"; else echo "false"; fi
}

source "$LIB"

echo "=== layer1-paths.sh: is_layer1_file ==="

assert_true  "CLAUDE.md at repo root"              "$(check 'CLAUDE.md')"
assert_true  "CLAUDE.md in subdir"                 "$(check 'clients/foo/CLAUDE.md')"
assert_true  "CLAUDE.md deep nested"               "$(check '/home/user/project/.claude/CLAUDE.md')"
assert_true  "absolute path to CLAUDE.md"          "$(check '/abs/path/CLAUDE.md')"

assert_false "CLAUDE.md.bak is not Layer 1"        "$(check 'CLAUDE.md.bak')"
assert_false "regular .md file"                    "$(check 'README.md')"
assert_false "feedback_*.md is not Layer 1"        "$(check 'memory/feedback_hooks.md')"
assert_false "system/rules/ file is not Layer 1"   "$(check 'system/rules/task-convention.md')"
assert_false "empty string"                        "$(check '')"

echo ""
echo "=== Results ==="
echo "  Passed: $PASS / $TOTAL"
if [ "$FAIL" -gt 0 ]; then
    echo "  FAILED: $FAIL"
    exit 1
fi
