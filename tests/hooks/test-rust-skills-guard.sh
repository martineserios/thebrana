#!/usr/bin/env bash
# Tests for rust-skills-guard.sh and skill-sentinel.sh (t-1480).
# Validates: *.rs writes blocked without sentinel, allowed with sentinel,
# sentinel written when brana:rust-skills Skill completes.
#
# Run: bash tests/hooks/test-rust-skills-guard.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
GUARD_HOOK="$REPO_ROOT/system/hooks/rust-skills-guard.sh"
SENTINEL_HOOK="$REPO_ROOT/system/hooks/skill-sentinel.sh"

TEST_SESSION="brana-test-session-rust-$$"
SENTINEL="/tmp/brana-rust-skills-loaded-${TEST_SESSION}"
BYPASS="/tmp/brana-rust-skills-guard-bypass"

PASS=0
FAIL=0
TOTAL=0

cleanup() {
    rm -f "$SENTINEL" "$BYPASS" 2>/dev/null || true
}
trap cleanup EXIT

assert() {
    local desc="$1" expected="$2" actual="$3"
    TOTAL=$((TOTAL + 1))
    if [ "$expected" = "$actual" ]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc"
        echo "         expected: '$expected'"
        echo "         got:      '$actual'"
        FAIL=$((FAIL + 1))
    fi
}

assert_contains() {
    local desc="$1" needle="$2" haystack="$3"
    TOTAL=$((TOTAL + 1))
    if echo "$haystack" | grep -qE "$needle"; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc"
        echo "         expected pattern: '$needle'"
        echo "         in output: '$haystack'"
        FAIL=$((FAIL + 1))
    fi
}

assert_not_contains() {
    local desc="$1" needle="$2" haystack="$3"
    TOTAL=$((TOTAL + 1))
    if ! echo "$haystack" | grep -qE "$needle"; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc"
        echo "         unexpected pattern: '$needle'"
        echo "         in output: '$haystack'"
        FAIL=$((FAIL + 1))
    fi
}

assert_file_exists() {
    local desc="$1" file="$2"
    TOTAL=$((TOTAL + 1))
    if [ -f "$file" ]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc — file not found: $file"
        FAIL=$((FAIL + 1))
    fi
}

assert_file_not_exists() {
    local desc="$1" file="$2"
    TOTAL=$((TOTAL + 1))
    if [ ! -f "$file" ]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc — file unexpectedly exists: $file"
        FAIL=$((FAIL + 1))
    fi
}

# Invoke rust-skills-guard.sh with a simulated PreToolUse payload
invoke_guard() {
    local file_path="$1"
    local session_id="${2:-$TEST_SESSION}"
    local tool="${3:-Write}"
    local payload
    payload=$(printf '{"tool_name":"%s","tool_input":{"file_path":"%s","content":"test"},"session_id":"%s","cwd":"/tmp"}' \
        "$tool" "$file_path" "$session_id")
    echo "$payload" | bash "$GUARD_HOOK" 2>&1
}

# Invoke skill-sentinel.sh with a simulated PostToolUse payload
invoke_sentinel() {
    local skill_name="$1"
    local session_id="${2:-$TEST_SESSION}"
    local payload
    payload=$(printf '{"tool_name":"Skill","tool_input":{"skill":"%s","args":""},"session_id":"%s"}' \
        "$skill_name" "$session_id")
    echo "$payload" | bash "$SENTINEL_HOOK" 2>&1
}

echo "=== test-rust-skills-guard.sh ==="
echo ""

# ── Prerequisite: hook files exist ────────────────────────────────────────────
echo "Prerequisite: hook files exist"
assert_file_exists "rust-skills-guard.sh exists" "$GUARD_HOOK"
assert_file_exists "skill-sentinel.sh exists" "$SENTINEL_HOOK"
echo ""

# ── Guard hook tests ──────────────────────────────────────────────────────────

# Ensure clean sentinel state
rm -f "$SENTINEL" "$BYPASS"

# Test 1: Non-Write/Edit tool → pass through
echo "Test 1: Non-Write/Edit tool → pass through"
output=$(invoke_guard "/path/to/lib.rs" "$TEST_SESSION" "Read")
assert_contains "Read on *.rs → continue:true" '"continue"[[:space:]]*:[[:space:]]*true' "$output"
echo ""

# Test 2: Non-rs file → pass through regardless of sentinel state
echo "Test 2: Non-rs file → pass through"
output=$(invoke_guard "/path/to/main.py" "$TEST_SESSION")
assert_contains ".py file → continue:true" '"continue"[[:space:]]*:[[:space:]]*true' "$output"
output=$(invoke_guard "/path/to/index.ts" "$TEST_SESSION")
assert_contains ".ts file → continue:true" '"continue"[[:space:]]*:[[:space:]]*true' "$output"
echo ""

# Test 3: *.rs file + no sentinel → block
echo "Test 3: *.rs file + no sentinel → block (continue:false)"
rm -f "$SENTINEL"
output=$(invoke_guard "/home/user/project/src/lib.rs" "$TEST_SESSION")
assert_contains "*.rs + no sentinel → blocked" '"continue"[[:space:]]*:[[:space:]]*false' "$output"
echo ""

# Test 4: Block message contains "brana:rust-skills"
echo "Test 4: Block message references brana:rust-skills"
rm -f "$SENTINEL"
output=$(invoke_guard "/home/user/project/src/main.rs" "$TEST_SESSION")
assert_contains "hint references brana:rust-skills" "brana:rust-skills|rust.skills" "$output"
echo ""

# Test 5: Block message references step 4a
echo "Test 5: Block message references step 4a"
rm -f "$SENTINEL"
output=$(invoke_guard "/home/user/project/src/main.rs" "$TEST_SESSION")
assert_contains "hint references step 4a" "step 4a|build\.md" "$output"
echo ""

# Test 6: *.rs file + sentinel present → pass through
echo "Test 6: *.rs file + sentinel present → pass through"
touch "$SENTINEL"
output=$(invoke_guard "/home/user/project/src/lib.rs" "$TEST_SESSION")
assert_contains "*.rs + sentinel → continue:true" '"continue"[[:space:]]*:[[:space:]]*true' "$output"
rm -f "$SENTINEL"
echo ""

# Test 7: *.rs file + bypass sentinel → pass through
echo "Test 7: *.rs file + bypass sentinel → pass through"
rm -f "$SENTINEL"
touch "$BYPASS"
output=$(invoke_guard "/home/user/project/src/lib.rs" "$TEST_SESSION")
assert_contains "*.rs + bypass → continue:true" '"continue"[[:space:]]*:[[:space:]]*true' "$output"
rm -f "$BYPASS"
echo ""

# Test 8: Test files (*/tests/*.rs) → always pass through
echo "Test 8: Test *.rs file → pass through (never block test files)"
rm -f "$SENTINEL"
output=$(invoke_guard "/home/user/project/tests/integration_test.rs" "$TEST_SESSION")
assert_contains "tests/*.rs → continue:true" '"continue"[[:space:]]*:[[:space:]]*true' "$output"
output=$(invoke_guard "/home/user/project/src/lib.spec.rs" "$TEST_SESSION")
assert_contains "*.spec.rs → continue:true" '"continue"[[:space:]]*:[[:space:]]*true' "$output"
echo ""

# Test 9: docs files → pass through
echo "Test 9: docs/*.md → pass through"
rm -f "$SENTINEL"
output=$(invoke_guard "/home/user/project/docs/architecture/hooks.md" "$TEST_SESSION")
assert_contains "docs/*.md → continue:true" '"continue"[[:space:]]*:[[:space:]]*true' "$output"
echo ""

# ── Sentinel hook tests ───────────────────────────────────────────────────────

# Test 10: Skill(brana:rust-skills) → writes sentinel
echo "Test 10: Skill(brana:rust-skills) → writes sentinel file"
rm -f "$SENTINEL"
invoke_sentinel "brana:rust-skills" "$TEST_SESSION" > /dev/null 2>&1 || true
assert_file_exists "sentinel written after brana:rust-skills" "$SENTINEL"
echo ""

# Test 11: Skill(brana:rust-skills) → returns continue:true
echo "Test 11: skill-sentinel.sh always returns continue:true"
rm -f "$SENTINEL"
output=$(invoke_sentinel "brana:rust-skills" "$TEST_SESSION")
assert_contains "sentinel hook → continue:true" '"continue"[[:space:]]*:[[:space:]]*true' "$output"
echo ""

# Test 12: Skill(brana:build) → does NOT write rust sentinel
echo "Test 12: Skill(brana:build) → no rust sentinel written"
rm -f "$SENTINEL"
invoke_sentinel "brana:build" "$TEST_SESSION" > /dev/null 2>&1 || true
assert_file_not_exists "no sentinel for brana:build" "$SENTINEL"
echo ""

# Test 13: Non-Skill tool → pass through, no sentinel
echo "Test 13: Non-Skill tool payload → pass through"
rm -f "$SENTINEL"
payload='{"tool_name":"Write","tool_input":{"file_path":"/tmp/x.rs"},"session_id":"'"$TEST_SESSION"'"}'
output=$(echo "$payload" | bash "$SENTINEL_HOOK" 2>&1)
assert_contains "non-Skill tool → continue:true" '"continue"[[:space:]]*:[[:space:]]*true' "$output"
assert_file_not_exists "non-Skill tool → no sentinel written" "$SENTINEL"
echo ""

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "Results: $PASS passed, $FAIL failed, $TOTAL total"
if [ "$FAIL" -gt 0 ]; then
    echo "STATUS: RED"
    exit 1
else
    echo "STATUS: GREEN"
    exit 0
fi
