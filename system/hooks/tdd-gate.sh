#!/usr/bin/env bash
# TDD Enforcement Gate — PreToolUse hook for Write|Edit
#
# Blocks .rs implementation file writes on feat/*/fix/* branches
# when no test file exists in the same crate.
#
# Always allows: test files, non-Rust files, non-feat/fix branches,
# non-git repos, projects without Cargo.toml.

# Ensure valid CWD
cd /tmp 2>/dev/null || true

# Profile gate: standard tier
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/profile.sh" 2>/dev/null || true
if ! hook_should_run "standard" 2>/dev/null; then
    echo '{"continue": true}'
    exit 0
fi

INPUT=$(cat)

# Helper: pass through
pass_through() {
    echo '{"continue": true}'
    exit 0
}

# Helper: deny with reason
deny() {
    local reason="$1"
    cat <<DENY_JSON
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "$reason"
  }
}
DENY_JSON
    exit 0
}

# Step 1: Parse input
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null) || pass_through
CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null) || pass_through

# Step 2: Only act on Write/Edit
case "$TOOL_NAME" in
    Write|Edit) ;;
    *) pass_through ;;
esac

# Step 3: Extract file path
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null) || pass_through
[ -z "$FILE_PATH" ] && pass_through

# Step 4: Only act on .rs files
case "$FILE_PATH" in
    *.rs) ;;
    *) pass_through ;;
esac

# Step 5: Always allow test files
BASENAME=$(basename "$FILE_PATH")
case "$BASENAME" in
    *_test.rs|test_*.rs) pass_through ;;
esac
case "$FILE_PATH" in
    */tests/*|*/test/*) pass_through ;;
esac

# Step 6: Find git root
GIT_ROOT=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null) || pass_through
[ -z "$GIT_ROOT" ] && pass_through

# Step 7: Branch check — only enforce on feat/* and fix/*
BRANCH=$(git -C "$GIT_ROOT" branch --show-current 2>/dev/null) || pass_through
case "$BRANCH" in
    feat/*|fix/*) ;;
    *) pass_through ;;
esac

# Step 8: Find crate root (nearest ancestor with Cargo.toml)
CRATE_ROOT=""
DIR=$(dirname "$FILE_PATH")
while [ "$DIR" != "/" ] && [ "$DIR" != "." ]; do
    if [ -f "$DIR/Cargo.toml" ]; then
        CRATE_ROOT="$DIR"
        break
    fi
    DIR=$(dirname "$DIR")
done
# No Cargo.toml found — not a Rust crate, pass through
[ -z "$CRATE_ROOT" ] && pass_through

# Step 9: Check for test files in the crate
# Look for: *_test.rs, test_*.rs, tests/ directory, #[cfg(test)] in any .rs file
HAS_TESTS=false

# Check tests/ directory
if [ -d "$CRATE_ROOT/tests" ] && [ "$(ls -A "$CRATE_ROOT/tests" 2>/dev/null)" ]; then
    HAS_TESTS=true
fi

# Check for test files by name pattern
if [ "$HAS_TESTS" = false ]; then
    TEST_FILES=$(find "$CRATE_ROOT/src" -name '*_test.rs' -o -name 'test_*.rs' 2>/dev/null | head -1)
    [ -n "$TEST_FILES" ] && HAS_TESTS=true
fi

# Check for #[cfg(test)] modules in existing source files
if [ "$HAS_TESTS" = false ]; then
    CFG_TEST=$(grep -rl '#\[cfg(test)\]' "$CRATE_ROOT/src" 2>/dev/null | head -1)
    [ -n "$CFG_TEST" ] && HAS_TESTS=true
fi

# Step 10: Decision
if [ "$HAS_TESTS" = true ]; then
    pass_through
else
    deny "TDD gate: write a test first. No test file found in crate at $CRATE_ROOT. Create a test file (*_test.rs, test_*.rs, or tests/ dir) or add a #[cfg(test)] module before writing implementation code."
fi
