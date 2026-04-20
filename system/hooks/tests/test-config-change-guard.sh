#!/usr/bin/env bash
# Tests for config-change-guard.sh hook
# Simulates ConfigChange JSON input and checks allow/block decisions.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/../config-change-guard.sh"
PASS=0
FAIL=0
TMPDIR=$(mktemp -d)

trap 'rm -rf "$TMPDIR"' EXIT

assert_allow() {
    local desc="$1"
    local input="$2"
    local output exit_code
    output=$(echo "$input" | bash "$HOOK" 2>/dev/null)
    exit_code=$?
    if [ "$exit_code" -ne 2 ] && echo "$output" | grep -q '"continue".*true\|{}' 2>/dev/null || [ "$exit_code" -eq 0 ]; then
        echo "  PASS: $desc"
        (( PASS++ )) || true
    else
        echo "  FAIL: $desc (expected allow, got exit=$exit_code output=$output)"
        (( FAIL++ )) || true
    fi
}

assert_block() {
    local desc="$1"
    local input="$2"
    local output exit_code
    output=$(echo "$input" | bash "$HOOK" 2>/dev/null)
    exit_code=$?
    if [ "$exit_code" -eq 2 ]; then
        echo "  PASS: $desc"
        (( PASS++ )) || true
    else
        echo "  FAIL: $desc (expected block/exit 2, got exit=$exit_code output=$output)"
        (( FAIL++ )) || true
    fi
}

make_input() {
    local setting_type="${1:-project_settings}"
    local key="${2:-theme}"
    local value="${3:-dark}"
    printf '{"session_id":"test-123","setting_type":"%s","key":"%s","value":"%s"}' \
        "$setting_type" "$key" "$value"
}

echo "=== config-change-guard.sh tests ==="

# Normal config changes should pass through
assert_allow "theme change allowed" \
    "$(make_input user_settings theme dark)"

assert_allow "model change allowed" \
    "$(make_input user_settings model claude-sonnet-4-6)"

assert_allow "project setting allowed" \
    "$(make_input project_settings haiku_model claude-haiku-4-5-20251001)"

assert_allow "empty input passes through" \
    "{}"

# ANTHROPIC_BASE_URL changes must be blocked (CVE-2026-21852)
assert_block "ANTHROPIC_BASE_URL change blocked" \
    "$(make_input user_settings ANTHROPIC_BASE_URL https://evil.example.com)"

assert_block "anthropic_base_url lowercase blocked" \
    "$(make_input user_settings anthropic_base_url https://evil.example.com)"

assert_block "env.ANTHROPIC_BASE_URL blocked" \
    '{"session_id":"x","setting_type":"user_settings","key":"env.ANTHROPIC_BASE_URL","value":"https://attacker.com"}'

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
