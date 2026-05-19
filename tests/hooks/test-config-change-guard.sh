#!/usr/bin/env bash
# Tests for ConfigChange hook: config-change-guard.sh (t-1232).
# Validates blocking of ANTHROPIC_BASE_URL manipulation (CVE-2026-21852),
# audit logging, and graceful degradation on bad input.
#
# Run: bash tests/hooks/test-config-change-guard.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HOOK="$REPO_ROOT/system/hooks/config-change-guard.sh"
TEST_LOG_DIR="$(mktemp -d)"
AUDIT_LOG="$TEST_LOG_DIR/.claude/logs/config-changes.log"

PASS=0
FAIL=0
TOTAL=0

assert_contains() {
    local desc="$1" needle="$2" haystack="$3"
    (( TOTAL++ )) || true
    if [[ "$haystack" =~ $needle ]]; then
        echo "  PASS: $desc"
        (( PASS++ )) || true
    else
        echo "  FAIL: $desc"
        echo "         expected pattern: '$needle'"
        echo "         in output: '$haystack'"
        (( FAIL++ )) || true
    fi
}

assert_not_contains() {
    local desc="$1" needle="$2" haystack="$3"
    (( TOTAL++ )) || true
    if ! [[ "$haystack" =~ $needle ]]; then
        echo "  PASS: $desc"
        (( PASS++ )) || true
    else
        echo "  FAIL: $desc"
        echo "         unexpected pattern: '$needle'"
        echo "         in output: '$haystack'"
        (( FAIL++ )) || true
    fi
}

assert_exit_code() {
    local desc="$1" expected="$2" actual="$3"
    (( TOTAL++ )) || true
    if [ "$expected" = "$actual" ]; then
        echo "  PASS: $desc"
        (( PASS++ )) || true
    else
        echo "  FAIL: $desc"
        echo "         expected exit: $expected, got: $actual"
        (( FAIL++ )) || true
    fi
}

assert_file_exists() {
    local desc="$1" file="$2"
    (( TOTAL++ )) || true
    if [ -f "$file" ]; then
        echo "  PASS: $desc"
        (( PASS++ )) || true
    else
        echo "  FAIL: $desc — not found: $file"
        (( FAIL++ )) || true
    fi
}

assert_file_contains() {
    local desc="$1" needle="$2" file="$3"
    (( TOTAL++ )) || true
    if grep -qE "$needle" "$file" 2>/dev/null; then
        echo "  PASS: $desc"
        (( PASS++ )) || true
    else
        echo "  FAIL: $desc"
        echo "         expected pattern: '$needle' in $(basename "$file")"
        (( FAIL++ )) || true
    fi
}

invoke_hook() {
    local key="$1" value="${2:-testvalue}"
    ( export HOME="$TEST_LOG_DIR"; printf '{"key":"%s","value":"%s"}' "$key" "$value" | bash "$HOOK" 2>&1 ) || true
}

invoke_hook_exit_code() {
    local key="$1" value="${2:-testvalue}"
    local code=0
    ( export HOME="$TEST_LOG_DIR"; printf '{"key":"%s","value":"%s"}' "$key" "$value" | bash "$HOOK" > /dev/null 2>&1 ) || code=$?
    echo "$code"
}

echo "=== test-config-change-guard.sh ==="
echo ""

# ── Prerequisite: hook file exists ───────────────────────────────────────────
echo "Prerequisite: hook file"
assert_file_exists "config-change-guard.sh exists at system/hooks/" "$HOOK"
echo ""

# ── Test 1: Allow benign config change ───────────────────────────────────────
echo "Test 1: Benign change (theme) → allowed (continue:true)"
output=$(invoke_hook "theme" "dark")
assert_contains "continue:true for benign change" '"continue"[[:space:]]*:[[:space:]]*true' "$output"
assert_not_contains "no block for benign change" '"continue"[[:space:]]*:[[:space:]]*false' "$output"
echo ""

# ── Test 2: Block ANTHROPIC_BASE_URL (lowercase) ─────────────────────────────
echo "Test 2: ANTHROPIC_BASE_URL (lowercase) → blocked"
output=$(invoke_hook "anthropic_base_url" "https://evil.example.com")
assert_contains "continue:false for base_url change" '"continue"[[:space:]]*:[[:space:]]*false' "$output"
echo ""

# ── Test 3: Block ANTHROPIC_BASE_URL (uppercase) ─────────────────────────────
echo "Test 3: ANTHROPIC_BASE_URL (uppercase) → blocked"
output=$(invoke_hook "ANTHROPIC_BASE_URL" "https://evil.example.com")
assert_contains "continue:false for ANTHROPIC_BASE_URL" '"continue"[[:space:]]*:[[:space:]]*false' "$output"
echo ""

# ── Test 4: Block env.ANTHROPIC_BASE_URL variant ─────────────────────────────
echo "Test 4: env.ANTHROPIC_BASE_URL variant → blocked"
output=$(invoke_hook "env.ANTHROPIC_BASE_URL" "https://evil.example.com")
assert_contains "continue:false for env. variant" '"continue"[[:space:]]*:[[:space:]]*false' "$output"
echo ""

# ── Test 5: Block exit code is 2 ─────────────────────────────────────────────
echo "Test 5: Block returns exit code 2"
exit_code=$(invoke_hook_exit_code "ANTHROPIC_BASE_URL" "https://evil.example.com")
assert_exit_code "exit code 2 on block" "2" "$exit_code"
echo ""

# ── Test 6: Allow exit code is 0 ─────────────────────────────────────────────
echo "Test 6: Allow returns exit code 0"
exit_code=$(invoke_hook_exit_code "theme" "dark")
assert_exit_code "exit code 0 on allow" "0" "$exit_code"
echo ""

# ── Test 7: Empty input → pass through (graceful degradation) ────────────────
echo "Test 7: Empty input → pass through (graceful)"
output=$(HOME="$TEST_LOG_DIR" echo "" | bash "$HOOK" 2>&1)
assert_contains "empty input → continue:true" '"continue"[[:space:]]*:[[:space:]]*true' "$output"
echo ""

# ── Test 8: Invalid JSON → pass through (graceful degradation) ───────────────
echo "Test 8: Invalid JSON → pass through (graceful)"
output=$(HOME="$TEST_LOG_DIR" echo "not-json" | bash "$HOOK" 2>&1)
assert_contains "invalid JSON → continue:true" '"continue"[[:space:]]*:[[:space:]]*true' "$output"
echo ""

# ── Test 9: Audit log written for benign change ───────────────────────────────
echo "Test 9: Audit log written for any config change"
rm -f "$AUDIT_LOG"
invoke_hook "theme" "dark" > /dev/null 2>&1
assert_file_exists "audit log created" "$AUDIT_LOG"
assert_file_contains "audit log contains change entry" '"key"' "$AUDIT_LOG"
echo ""

# ── Test 10: Audit log written for blocked change ────────────────────────────
echo "Test 10: Audit log written even for blocked ANTHROPIC_BASE_URL change"
invoke_hook "ANTHROPIC_BASE_URL" "https://evil.example.com" > /dev/null 2>&1 || true
assert_file_contains "blocked change also logged" 'ANTHROPIC_BASE_URL|anthropic_base_url' "$AUDIT_LOG"
echo ""

# ── Test 11: ConfigChange hook wired at user level (t-1417) ──────────────────
echo "Test 11: ConfigChange wired in ~/.claude/settings.json (user-level)"
USER_SETTINGS="$HOME/.claude/settings.json"
wiring_found=$(python3 -c "
import json, sys
try:
    with open('$USER_SETTINGS') as f:
        d = json.load(f)
    hooks = d.get('hooks', {})
    for mg in hooks.get('ConfigChange', []):
        for h in mg.get('hooks', []):
            path = h.get('command') or (h.get('args', ['',''])[1] if 'args' in h else '')
            if 'config-change-guard' in path:
                print('found')
                sys.exit(0)
    print('missing')
except Exception as e:
    print('missing')
" 2>/dev/null)
assert_contains \
    "config-change-guard.sh wired to ConfigChange in ~/.claude/settings.json" \
    "found" \
    "$wiring_found"
echo ""

# ── Cleanup ───────────────────────────────────────────────────────────────────
rm -rf "$TEST_LOG_DIR"

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
