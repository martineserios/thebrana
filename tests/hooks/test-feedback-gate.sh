#!/usr/bin/env bash
# Tests for PreToolUse hook: feedback_*.md creation gate (t-1272, t-1312).
# Validates blocking behavior (Wave 2) and sentinel bypass contract.
# Spec: docs/architecture/decisions/ADR-037-memory-enforcement-and-migration.md
#       docs/architecture/features/memory-taxonomy-sdd.md §4
#
# Run: bash tests/hooks/test-feedback-gate.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HOOK="$REPO_ROOT/system/hooks/feedback-gate.sh"
ADR="$REPO_ROOT/docs/architecture/decisions/ADR-037-memory-enforcement-and-migration.md"
SDD="$REPO_ROOT/docs/architecture/features/memory-taxonomy-sdd.md"

PASS=0
FAIL=0
TOTAL=0

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
    if echo "$haystack" | grep -iqE "$needle"; then
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
    if ! echo "$haystack" | grep -iqE "$needle"; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc"
        echo "         unexpected pattern found: '$needle'"
        echo "         in output: '$haystack'"
        FAIL=$((FAIL + 1))
    fi
}

assert_file_contains() {
    local desc="$1" needle="$2" file="$3"
    TOTAL=$((TOTAL + 1))
    if grep -iqE "$needle" "$file" 2>/dev/null; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc"
        echo "         expected pattern: '$needle'"
        echo "         in file: $(basename "$file")"
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

assert_exit_code() {
    local desc="$1" expected="$2" actual="$3"
    TOTAL=$((TOTAL + 1))
    if [ "$expected" = "$actual" ]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc"
        echo "         expected exit code: $expected"
        echo "         got: $actual"
        FAIL=$((FAIL + 1))
    fi
}

# Helper: invoke hook with a simulated CC PreToolUse JSON payload
invoke_hook() {
    local file_path="$1"
    local override="${2:-}"
    local payload
    payload=$(printf '{"tool_name":"Write","tool_input":{"file_path":"%s","content":"test"}}' "$file_path")
    if [ -n "$override" ]; then
        BRANA_MEMORY_OVERRIDE="$override" echo "$payload" | bash "$HOOK" 2>&1
    else
        echo "$payload" | bash "$HOOK" 2>&1
    fi
}

echo "=== test-feedback-gate.sh ==="
echo ""

# ── Prerequisite: spec docs exist ──────────────────────────────────────────────
echo "Prerequisite: spec docs"
assert_file_exists "ADR-037 exists" "$ADR"
assert_file_exists "memory-taxonomy SDD exists" "$SDD"
echo ""

# ── Prerequisite: hook file exists ────────────────────────────────────────────
echo "Prerequisite: hook file"
assert_file_exists "feedback-gate.sh exists at system/hooks/" "$HOOK"
echo ""

# ── Test 1: Advisory warning on feedback_*.md write ───────────────────────────
echo "Test 1: Advisory warning fires for feedback_*.md path"
if [ -f "$HOOK" ]; then
    output=$(invoke_hook "$HOME/.claude/projects/-home-user-project/memory/feedback_test.md")
    assert_contains "warning message mentions feedback_*.md" "feedback" "$output"
    assert_contains "warning suggests /brana:retrospective" "retrospective" "$output"
else
    assert "hook exists (skip advisory test)" "exists" "missing"
    assert "hook exists (skip advisory test)" "exists" "missing"
fi
echo ""

# ── Test 2: Wave 2 — write IS blocked (continue:false) ───────────────────────
echo "Test 2: Wave 2 blocking — feedback_*.md write returns continue:false"
if [ -f "$HOOK" ]; then
    output=$(invoke_hook "$HOME/.claude/projects/-home-user-project/memory/feedback_test.md")
    assert_contains "output contains continue:false" '"continue"[[:space:]]*:[[:space:]]*false' "$output"
    invoke_hook "$HOME/.claude/projects/-home-user-project/memory/feedback_test.md" > /dev/null 2>&1
    exit_code=$?
    assert_exit_code "exit code 0 (hook exits cleanly even when blocking)" "0" "$exit_code"
else
    assert "hook exists (skip block test)" "exists" "missing"
    assert "hook exists (skip block test)" "exists" "missing"
fi
echo ""

# ── Test 3: Allowed path — patterns.md not intercepted ────────────────────────
echo "Test 3: Write to patterns.md — hook does not fire"
if [ -f "$HOOK" ]; then
    output=$(invoke_hook "$HOME/.claude/memory/patterns.md")
    assert_not_contains "no warning for patterns.md" "feedback|retrospective|warning" "$output"
else
    assert "hook exists (skip patterns test)" "exists" "missing"
fi
echo ""

# ── Test 4: Allowed path — knowledge-staging.md not intercepted ───────────────
echo "Test 4: Write to knowledge-staging.md — hook does not fire"
if [ -f "$HOOK" ]; then
    output=$(invoke_hook "$HOME/.claude/memory/knowledge-staging.md")
    assert_not_contains "no warning for knowledge-staging.md" "feedback|warning" "$output"
else
    assert "hook exists (skip knowledge test)" "exists" "missing"
fi
echo ""

# ── Test 5: Allowed path — session state not intercepted ─────────────────────
echo "Test 5: Write to session JSON — hook does not fire"
if [ -f "$HOOK" ]; then
    output=$(invoke_hook "$HOME/.claude/projects/-home-user-project/memory/session-state.json")
    assert_not_contains "no warning for session-state.json" "feedback|warning" "$output"
else
    assert "hook exists (skip session test)" "exists" "missing"
fi
echo ""

# ── Test 6: Path outside memory/ — hook does not fire ─────────────────────────
echo "Test 6: Write to non-memory path — hook does not fire"
if [ -f "$HOOK" ]; then
    output=$(invoke_hook "/home/user/projects/src/feedback_handler.py")
    assert_not_contains "no warning for non-memory feedback file" "retrospective|warning" "$output"
else
    assert "hook exists (skip path test)" "exists" "missing"
fi
echo ""

# ── Test 7: BRANA_MEMORY_OVERRIDE=1 suppresses warning ────────────────────────
echo "Test 7: BRANA_MEMORY_OVERRIDE=1 suppresses warning"
if [ -f "$HOOK" ]; then
    output=$(BRANA_MEMORY_OVERRIDE=1 invoke_hook "$HOME/.claude/projects/-home-user-project/memory/feedback_test.md")
    assert_not_contains "warning suppressed with override" "⚠|warning" "$output"
else
    assert "hook exists (skip override test)" "exists" "missing"
fi
echo ""

# ── Test 8: Spec — SDD documents PreToolUse hook ──────────────────────────────
echo "Test 8: SDD spec documents the hook"
assert_file_contains "SDD references PreToolUse" "PreToolUse" "$SDD"
assert_file_contains "SDD references feedback_*.md glob" "feedback_.*\.md" "$SDD"
assert_file_contains "SDD documents BRANA_MEMORY_OVERRIDE" "BRANA_MEMORY_OVERRIDE" "$SDD"
echo ""

# ── Test 9: ADR documents Wave 1 advisory and Wave 2 blocking ─────────────────
echo "Test 9: ADR documents advisory and blocking phases"
assert_file_contains "ADR documents advisory behavior" "advisory" "$ADR"
assert_file_contains "ADR documents blocking behavior" "block" "$ADR"
assert_file_contains "ADR documents cooling-off constraint" "cooling.off|cooling_off" "$ADR"
echo ""

# ── Test 10: Sentinel bypass — /tmp/brana-close-active allows write ──────────
echo "Test 10: Sentinel bypass — /tmp/brana-close-active → continue:true"
if [ -f "$HOOK" ]; then
    SENTINEL=/tmp/brana-close-active
    touch "$SENTINEL"
    output=$(invoke_hook "$HOME/.claude/projects/-home-user-project/memory/feedback_test.md")
    rm -f "$SENTINEL"
    assert_contains "sentinel present → continue:true" '"continue"[[:space:]]*:[[:space:]]*true' "$output"
    assert_not_contains "sentinel present → no block message" "BLOCKED" "$output"
else
    assert "hook exists (skip sentinel test)" "exists" "missing"
    assert "hook exists (skip sentinel test)" "exists" "missing"
fi
echo ""

# ── Test 11: No sentinel — blocking resumes after sentinel removed ────────────
echo "Test 11: No sentinel — blocking resumes (continue:false)"
if [ -f "$HOOK" ]; then
    rm -f /tmp/brana-close-active
    output=$(invoke_hook "$HOME/.claude/projects/-home-user-project/memory/feedback_test.md")
    assert_contains "no sentinel → continue:false" '"continue"[[:space:]]*:[[:space:]]*false' "$output"
else
    assert "hook exists (skip no-sentinel test)" "exists" "missing"
fi
echo ""

# ── Test 12: Sentinel does not bypass BRANA_MEMORY_OVERRIDE path ─────────────
echo "Test 12: Both sentinel + BRANA_MEMORY_OVERRIDE → continue:true (BRANA_MEMORY_OVERRIDE wins first)"
if [ -f "$HOOK" ]; then
    SENTINEL=/tmp/brana-close-active
    touch "$SENTINEL"
    output=$(BRANA_MEMORY_OVERRIDE=1 invoke_hook "$HOME/.claude/projects/-home-user-project/memory/feedback_test.md")
    rm -f "$SENTINEL"
    assert_contains "override+sentinel → continue:true" '"continue"[[:space:]]*:[[:space:]]*true' "$output"
else
    assert "hook exists (skip override+sentinel test)" "exists" "missing"
fi
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
