#!/usr/bin/env bash
# TDD Enforcement Gate — PreToolUse hook for Write|Edit
#
# Two-level enforcement:
# 1. Project level: blocks implementation writes when NO test file exists
#    in the project root (any branch).
# 2. Session level: blocks CREATING new code files (Write to non-existent
#    path) unless a test file was written first in this session.
#    Tracked via /tmp/tdd-gate-<hash> state files, keyed by git root.
#
# Supported: Rust, Python, JS/TS, Shell, Go
# Always allows: test files, unknown languages, non-git repos.

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

# Step 4: Detect language from extension
BASENAME=$(basename "$FILE_PATH")
LANG=""
case "$FILE_PATH" in
    *.rs)                     LANG="rust" ;;
    *.py)                     LANG="python" ;;
    *.js|*.jsx)               LANG="js" ;;
    *.ts|*.tsx)               LANG="ts" ;;
    *.sh)                     LANG="shell" ;;
    *.go)                     LANG="go" ;;
    *)                        pass_through ;;
esac

# Step 4.5: Find git root (moved before test detection for session state tracking)
GIT_ROOT=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null) || pass_through
[ -z "$GIT_ROOT" ] && pass_through

# Session state file — keyed on git root, tracks test writes per project
STATE_FILE="/tmp/tdd-gate-$(echo "$GIT_ROOT" | md5sum | cut -c1-8)"

# Helper: record test file write and pass through
record_test_and_pass() {
    echo "test:$FILE_PATH:$(date +%s)" >> "$STATE_FILE" 2>/dev/null
    pass_through
}

# Clean stale state files (>12h old)
find /tmp -maxdepth 1 -name 'tdd-gate-*' -mmin +720 -delete 2>/dev/null

# Step 5: Always allow test files (and record for session tracking)
case "$LANG" in
    rust)
        case "$BASENAME" in
            *_test.rs|test_*.rs) record_test_and_pass ;;
        esac
        case "$FILE_PATH" in
            */tests/*|*/test/*) record_test_and_pass ;;
        esac
        ;;
    python)
        case "$BASENAME" in
            test_*.py|*_test.py) record_test_and_pass ;;
        esac
        case "$FILE_PATH" in
            */tests/*|*/test/*|*/__tests__/*) record_test_and_pass ;;
        esac
        ;;
    js|ts)
        case "$BASENAME" in
            *.test.*|*.spec.*) record_test_and_pass ;;
        esac
        case "$FILE_PATH" in
            */__tests__/*|*/tests/*|*/test/*) record_test_and_pass ;;
        esac
        ;;
    shell)
        case "$BASENAME" in
            test-*|*-test.sh|test_*) record_test_and_pass ;;
        esac
        case "$FILE_PATH" in
            */tests/*|*/test/*) record_test_and_pass ;;
        esac
        ;;
    go)
        case "$BASENAME" in
            *_test.go) record_test_and_pass ;;
        esac
        ;;
esac

# Step 7: (Branch filter removed — gates fire on all branches per ADR-031 revision)

# Step 8: Find project root (nearest ancestor with a manifest file)
PROJECT_ROOT=""
DIR=$(dirname "$FILE_PATH")
while [ "$DIR" != "/" ] && [ "$DIR" != "." ]; do
    case "$LANG" in
        rust)   [ -f "$DIR/Cargo.toml" ] && PROJECT_ROOT="$DIR" && break ;;
        python) { [ -f "$DIR/pyproject.toml" ] || [ -f "$DIR/setup.py" ] || [ -f "$DIR/setup.cfg" ]; } && PROJECT_ROOT="$DIR" && break ;;
        js|ts)  [ -f "$DIR/package.json" ] && PROJECT_ROOT="$DIR" && break ;;
        go)     [ -f "$DIR/go.mod" ] && PROJECT_ROOT="$DIR" && break ;;
        shell)  PROJECT_ROOT="$GIT_ROOT" && break ;;
    esac
    DIR=$(dirname "$DIR")
done
# No project root found — pass through
[ -z "$PROJECT_ROOT" ] && pass_through

# Step 9: Check for test files in the project
HAS_TESTS=false

# Common: check tests/ directory
if [ -d "$PROJECT_ROOT/tests" ] && [ "$(ls -A "$PROJECT_ROOT/tests" 2>/dev/null)" ]; then
    HAS_TESTS=true
fi

if [ "$HAS_TESTS" = false ]; then
    case "$LANG" in
        rust)
            # Check src/ for *_test.rs, test_*.rs
            TEST_FILES=$(find "$PROJECT_ROOT/src" -name '*_test.rs' -o -name 'test_*.rs' 2>/dev/null | head -1)
            [ -n "$TEST_FILES" ] && HAS_TESTS=true
            # Check for #[cfg(test)] modules
            if [ "$HAS_TESTS" = false ]; then
                CFG_TEST=$(grep -rl '#\[cfg(test)\]' "$PROJECT_ROOT/src" 2>/dev/null | head -1)
                [ -n "$CFG_TEST" ] && HAS_TESTS=true
            fi
            ;;
        python)
            # Check for test_*.py or *_test.py anywhere in project
            TEST_FILES=$(find "$PROJECT_ROOT" -maxdepth 3 -name 'test_*.py' -o -name '*_test.py' 2>/dev/null | head -1)
            [ -n "$TEST_FILES" ] && HAS_TESTS=true
            # Check __tests__/ dir
            if [ "$HAS_TESTS" = false ] && [ -d "$PROJECT_ROOT/__tests__" ]; then
                HAS_TESTS=true
            fi
            ;;
        js|ts)
            # Check for *.test.* or *.spec.* anywhere in project
            TEST_FILES=$(find "$PROJECT_ROOT" -maxdepth 3 \( -name '*.test.*' -o -name '*.spec.*' \) ! -path '*/node_modules/*' 2>/dev/null | head -1)
            [ -n "$TEST_FILES" ] && HAS_TESTS=true
            # Check __tests__/ dir
            if [ "$HAS_TESTS" = false ] && [ -d "$PROJECT_ROOT/__tests__" ]; then
                HAS_TESTS=true
            fi
            ;;
        shell)
            # Check for test-*.sh or *-test.sh
            TEST_FILES=$(find "$PROJECT_ROOT" -maxdepth 3 \( -name 'test-*.sh' -o -name '*-test.sh' -o -name 'test_*.sh' \) 2>/dev/null | head -1)
            [ -n "$TEST_FILES" ] && HAS_TESTS=true
            ;;
        go)
            # Check for *_test.go in same directory or project root
            TEST_FILES=$(find "$PROJECT_ROOT" -maxdepth 3 -name '*_test.go' 2>/dev/null | head -1)
            [ -n "$TEST_FILES" ] && HAS_TESTS=true
            ;;
    esac
fi

# Step 9.5: Build hint string (used in both deny paths)
case "$LANG" in
    rust)   HINT="Create a test file (*_test.rs, test_*.rs, tests/ dir) or add a #[cfg(test)] module." ;;
    python) HINT="Create a test file (test_*.py, *_test.py, tests/ dir, or __tests__/)." ;;
    js|ts)  HINT="Create a test file (*.test.*, *.spec.*, __tests__/ dir, or tests/)." ;;
    shell)  HINT="Create a test file (test-*.sh, *-test.sh, or tests/ dir)." ;;
    go)     HINT="Create a test file (*_test.go)." ;;
    *)      HINT="Create a test file before writing implementation code." ;;
esac

# Step 10: Decision
if [ "$HAS_TESTS" = true ]; then
    # Project has tests. But if this is a NEW file (Write to non-existent path),
    # require that a test was written in this session first.
    # Only check Write — Edit requires existing file (CC enforces this).
    if [ "$TOOL_NAME" = "Write" ] && [ ! -f "$FILE_PATH" ]; then
        # New file — check session state for a recent test write
        if [ -f "$STATE_FILE" ] && grep -q "^test:" "$STATE_FILE" 2>/dev/null; then
            pass_through
        else
            deny "TDD gate: write a test first. Creating NEW file ($BASENAME) but no test was written yet this session. Write or edit a test file first, then create the implementation. $HINT"
        fi
    else
        pass_through
    fi
else
    deny "TDD gate: write a test first. No test file found in project at $PROJECT_ROOT. $HINT"
fi
