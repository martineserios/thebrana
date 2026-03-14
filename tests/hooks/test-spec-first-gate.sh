#!/usr/bin/env bash
# Tests for pre-tool-use.sh spec-first gate (t-429 build_step enforcement)
#
# Validates:
#   1. build_step=specify → denies implementation writes
#   2. build_step=plan → denies implementation writes
#   3. build_step=build → allows implementation writes (with spec activity)
#   4. build_step=close → allows implementation writes
#   5. No matching task → falls through to spec activity check
#   6. Spec/doc/test writes always pass regardless of build_step

set -euo pipefail

HOOKS_DIR="$(cd "$(dirname "$0")/../../system/hooks" && pwd)"
HOOK="$HOOKS_DIR/pre-tool-use.sh"
PASS=0
FAIL=0

# Setup: temp git repo with docs/decisions/ (opts in to enforcement)
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

git -C "$TMPDIR" init -q
mkdir -p "$TMPDIR/docs/decisions" "$TMPDIR/.claude" "$TMPDIR/src"

# Create initial commit on main
echo "# test" > "$TMPDIR/docs/decisions/ADR-001.md"
git -C "$TMPDIR" add -A
git -C "$TMPDIR" commit -q -m "init"

# Create feat branch
git -C "$TMPDIR" checkout -q -b feat/t-999-test-feature

# Add spec activity so step 9/10 passes
echo "# spec" > "$TMPDIR/docs/decisions/ADR-002.md"
git -C "$TMPDIR" add -A
git -C "$TMPDIR" commit -q -m "add spec"

assert_decision() {
    local label="$1" expected="$2" build_step="$3" file_path="$4"

    # Write tasks.json with the given build_step
    cat > "$TMPDIR/.claude/tasks.json" << TASKS
{
  "version": "1",
  "project": "test",
  "tasks": [
    {
      "id": "t-999",
      "subject": "Test feature",
      "status": "in_progress",
      "type": "task",
      "stream": "roadmap",
      "branch": "feat/t-999-test-feature",
      "build_step": "$build_step"
    }
  ]
}
TASKS

    local input
    input=$(jq -n \
        --arg tool "Write" \
        --arg cwd "$TMPDIR" \
        --arg file "$file_path" \
        --arg session "test-$$" \
        '{tool_name: $tool, cwd: $cwd, tool_input: {file_path: $file}, session_id: $session}')

    local output
    output=$(echo "$input" | bash "$HOOK" 2>/dev/null) || true

    local decision
    decision=$(echo "$output" | jq -r '.hookSpecificOutput.permissionDecision // "allow"' 2>/dev/null) || decision="allow"

    if [ "$decision" = "$expected" ]; then
        PASS=$((PASS + 1))
        echo "  PASS: $label"
    else
        FAIL=$((FAIL + 1))
        echo "  FAIL: $label — expected '$expected', got '$decision'"
        echo "        output: $output"
    fi
}

echo "=== build_step gate tests ==="

# Gate denies: specify and plan
assert_decision "specify blocks implementation writes" "deny" "specify" "$TMPDIR/src/main.rs"
assert_decision "plan blocks implementation writes" "deny" "plan" "$TMPDIR/src/main.rs"

# Gate allows: build and close
assert_decision "build allows implementation writes" "allow" "build" "$TMPDIR/src/main.rs"
assert_decision "close allows implementation writes" "allow" "close" "$TMPDIR/src/main.rs"

# Spec/doc writes always pass regardless of build_step
assert_decision "specify allows doc writes" "allow" "specify" "$TMPDIR/docs/decisions/ADR-003.md"
assert_decision "specify allows test writes" "allow" "specify" "$TMPDIR/tests/test_main.py"
assert_decision "plan allows markdown writes" "allow" "plan" "$TMPDIR/README.md"

echo ""
echo "=== No matching task (empty build_step) ==="

# Task with different branch — should not match, falls through to spec activity check
cat > "$TMPDIR/.claude/tasks.json" << 'TASKS'
{
  "version": "1",
  "project": "test",
  "tasks": [
    {
      "id": "t-888",
      "subject": "Other task",
      "status": "in_progress",
      "type": "task",
      "stream": "roadmap",
      "branch": "feat/t-888-other",
      "build_step": "specify"
    }
  ]
}
TASKS

input=$(jq -n \
    --arg tool "Write" \
    --arg cwd "$TMPDIR" \
    --arg file "$TMPDIR/src/main.rs" \
    --arg session "test-$$" \
    '{tool_name: $tool, cwd: $cwd, tool_input: {file_path: $file}, session_id: $session}')

output=$(echo "$input" | bash "$HOOK" 2>/dev/null) || true
decision=$(echo "$output" | jq -r '.hookSpecificOutput.permissionDecision // "allow"' 2>/dev/null) || decision="allow"

if [ "$decision" = "allow" ]; then
    PASS=$((PASS + 1))
    echo "  PASS: non-matching task allows (spec activity exists)"
else
    FAIL=$((FAIL + 1))
    echo "  FAIL: non-matching task — expected 'allow', got '$decision'"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
