#!/usr/bin/env bash
# Tests for plan-mode-gate.sh — blocks EnterPlanMode during active /brana:build
#
# Validates:
#   1. EnterPlanMode denied when build_step is active (specify/plan/build/close)
#   2. EnterPlanMode allowed when no build is active (no matching task)
#   3. EnterPlanMode allowed when no tasks.json exists

set -euo pipefail

HOOKS_DIR="$(cd "$(dirname "$0")/../../system/hooks" && pwd)"
HOOK="$HOOKS_DIR/plan-mode-gate.sh"
PASS=0
FAIL=0

# Setup: temp git repo
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

git -C "$TMPDIR" init -q
mkdir -p "$TMPDIR/.claude" "$TMPDIR/src"
echo "# test" > "$TMPDIR/README.md"
git -C "$TMPDIR" add -A
git -C "$TMPDIR" commit -q -m "init"

# Create a build branch
git -C "$TMPDIR" checkout -q -b refactor/t-505-test

assert_decision() {
    local label="$1" expected="$2" build_step="$3"

    # Write tasks.json with the given build_step
    cat > "$TMPDIR/.claude/tasks.json" << TASKS
{
  "version": "1",
  "project": "test",
  "tasks": [
    {
      "id": "t-505",
      "subject": "Test task",
      "status": "in_progress",
      "type": "task",
      "stream": "tech-debt",
      "branch": "refactor/t-505-test",
      "build_step": "$build_step"
    }
  ]
}
TASKS

    local input
    input=$(jq -n \
        --arg tool "EnterPlanMode" \
        --arg cwd "$TMPDIR" \
        --arg session "test-$$" \
        '{tool_name: $tool, cwd: $cwd, tool_input: {}, session_id: $session}')

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

echo "=== EnterPlanMode gate: active build ==="

# Gate denies: any active build_step
assert_decision "specify blocks EnterPlanMode" "deny" "specify"
assert_decision "decompose blocks EnterPlanMode" "deny" "decompose"
assert_decision "build blocks EnterPlanMode" "deny" "build"
assert_decision "close blocks EnterPlanMode" "deny" "close"

echo ""
echo "=== EnterPlanMode gate: no active build ==="

# No matching task — build_step null
cat > "$TMPDIR/.claude/tasks.json" << 'TASKS'
{
  "version": "1",
  "project": "test",
  "tasks": [
    {
      "id": "t-505",
      "subject": "Test task",
      "status": "in_progress",
      "type": "task",
      "stream": "tech-debt",
      "branch": "refactor/t-505-test",
      "build_step": null
    }
  ]
}
TASKS

input=$(jq -n \
    --arg tool "EnterPlanMode" \
    --arg cwd "$TMPDIR" \
    --arg session "test-$$" \
    '{tool_name: $tool, cwd: $cwd, tool_input: {}, session_id: $session}')

output=$(echo "$input" | bash "$HOOK" 2>/dev/null) || true
decision=$(echo "$output" | jq -r '.hookSpecificOutput.permissionDecision // "allow"' 2>/dev/null) || decision="allow"

if [ "$decision" = "allow" ]; then
    PASS=$((PASS + 1))
    echo "  PASS: null build_step allows EnterPlanMode"
else
    FAIL=$((FAIL + 1))
    echo "  FAIL: null build_step — expected 'allow', got '$decision'"
fi

echo ""
echo "=== EnterPlanMode gate: no tasks.json ==="

# Remove tasks.json entirely
rm -f "$TMPDIR/.claude/tasks.json"

input=$(jq -n \
    --arg tool "EnterPlanMode" \
    --arg cwd "$TMPDIR" \
    --arg session "test-$$" \
    '{tool_name: $tool, cwd: $cwd, tool_input: {}, session_id: $session}')

output=$(echo "$input" | bash "$HOOK" 2>/dev/null) || true
decision=$(echo "$output" | jq -r '.hookSpecificOutput.permissionDecision // "allow"' 2>/dev/null) || decision="allow"

if [ "$decision" = "allow" ]; then
    PASS=$((PASS + 1))
    echo "  PASS: no tasks.json allows EnterPlanMode"
else
    FAIL=$((FAIL + 1))
    echo "  FAIL: no tasks.json — expected 'allow', got '$decision'"
fi

echo ""
echo "=== EnterPlanMode gate: different branch ==="

# Task on different branch — should not match
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
      "build_step": "build"
    }
  ]
}
TASKS

input=$(jq -n \
    --arg tool "EnterPlanMode" \
    --arg cwd "$TMPDIR" \
    --arg session "test-$$" \
    '{tool_name: $tool, cwd: $cwd, tool_input: {}, session_id: $session}')

output=$(echo "$input" | bash "$HOOK" 2>/dev/null) || true
decision=$(echo "$output" | jq -r '.hookSpecificOutput.permissionDecision // "allow"' 2>/dev/null) || decision="allow"

if [ "$decision" = "allow" ]; then
    PASS=$((PASS + 1))
    echo "  PASS: different branch allows EnterPlanMode"
else
    FAIL=$((FAIL + 1))
    echo "  FAIL: different branch — expected 'allow', got '$decision'"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
