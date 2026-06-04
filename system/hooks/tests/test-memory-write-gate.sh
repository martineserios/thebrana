#!/usr/bin/env bash
# Tests for memory-write-gate.sh hook
# Verifies output format uses permissionDecision:deny (not continue:false).
# Regression guard for t-1847: continue:false hard-stopped CC auto-memory writes.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/../memory-write-gate.sh"
PASS=0
FAIL=0

make_input() {
    local tool="$1" path="$2"
    printf '{"tool_name":"%s","tool_input":{"file_path":"%s"}}' "$tool" "$path"
}

assert_passes() {
    local desc="$1" input="$2"
    local result
    result=$(echo "$input" | bash "$HOOK" 2>/dev/null)
    if echo "$result" | jq -e '.continue == true' >/dev/null 2>&1; then
        echo "  PASS: $desc"
        ((PASS++))
    else
        echo "  FAIL: $desc — expected pass-through, got: $result"
        ((FAIL++))
    fi
}

assert_denies() {
    local desc="$1" input="$2"
    local result
    result=$(echo "$input" | bash "$HOOK" 2>/dev/null)
    # Must use permissionDecision:deny — not continue:false
    if echo "$result" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null 2>&1; then
        echo "  PASS: $desc"
        ((PASS++))
    else
        echo "  FAIL: $desc — expected permissionDecision:deny, got: $result"
        ((FAIL++))
    fi
}

assert_no_continue_false() {
    local desc="$1" input="$2"
    local result
    result=$(echo "$input" | bash "$HOOK" 2>/dev/null)
    if echo "$result" | jq -e '.continue == false' >/dev/null 2>&1; then
        echo "  FAIL: $desc — regression: output contains continue:false (hard-stop bug)"
        ((FAIL++))
    else
        echo "  PASS: $desc"
        ((PASS++))
    fi
}

echo "Memory Write Gate Tests"
echo "========================"

# --- Pass-through cases ---

assert_passes "non-Write tool is ignored" \
    "$(make_input "Bash" "/project/memory/feedback_foo.md")"

assert_passes "Edit to non-memory path is ignored" \
    "$(make_input "Edit" "/project/src/main.rs")"

assert_passes "Write to MEMORY.md index is allowed" \
    "$(make_input "Write" "/project/memory/MEMORY.md")"

assert_passes "Write to event-log.md is allowed" \
    "$(make_input "Write" "/project/memory/event-log.md")"

assert_passes "Write to pending-learnings.md is allowed" \
    "$(make_input "Write" "/project/memory/pending-learnings.md")"

# ~/.claude/ auto-memory exemption (t-1847 root cause)
assert_passes "Write to ~/.claude/projects/*/memory/ is exempt" \
    "$(make_input "Write" "$HOME/.claude/projects/-home-foo-bar/memory/feedback_test.md")"

assert_passes "Write to /home/*/.claude/ is exempt (HOME unset fallback)" \
    "$(make_input "Write" "/home/someuser/.claude/projects/foo/memory/pattern_x.md")"

# Sentinel bypass
SENTINEL=$(mktemp /tmp/brana-memory-write-active.XXXXXX)
mv "$SENTINEL" /tmp/brana-memory-write-active
assert_passes "sentinel bypass: /tmp/brana-memory-write-active present" \
    "$(make_input "Write" "/project/memory/feedback_test.md")"
rm -f /tmp/brana-memory-write-active

# --- Deny cases ---

assert_denies "Write to typed feedback_ file is denied" \
    "$(make_input "Write" "/project/memory/feedback_my-rule.md")"

assert_denies "Edit to typed project_ file is denied" \
    "$(make_input "Edit" "/project/memory/project_status.md")"

assert_denies "Write to typed pattern_ file is denied" \
    "$(make_input "Write" "/project/memory/pattern_some-thing.md")"

assert_denies "Write to typed user_ file is denied" \
    "$(make_input "Write" "/project/memory/user_profile.md")"

assert_denies "Write to typed convention_ file is denied" \
    "$(make_input "Write" "/project/memory/convention_naming.md")"

assert_denies "Write to typed field-note_ file is denied" \
    "$(make_input "Write" "/project/memory/field-note_hook-escape.md")"

assert_denies "Write to typed adr_ file is denied" \
    "$(make_input "Write" "/project/memory/adr_design.md")"

# --- Regression guard: no continue:false in deny output ---

assert_no_continue_false "deny output must not contain continue:false (t-1847 regression)" \
    "$(make_input "Write" "/project/memory/feedback_regression-test.md")"

assert_no_continue_false "pass-through output may use continue:true but not continue:false" \
    "$(make_input "Bash" "/project/memory/feedback_irrelevant.md")"

# --- Summary ---

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
