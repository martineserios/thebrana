#!/usr/bin/env bash
# Tests for bash-output-compress.sh (t-1716)
# Validates: PostToolUse Bash hook compresses large output, passes small output through.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/../bash-output-compress.sh"
PASS=0; FAIL=0; TOTAL=0

assert_contains() {
    local desc="$1" output="$2" needle="$3"
    TOTAL=$((TOTAL + 1))
    if echo "$output" | grep -q "$needle"; then
        echo "  PASS: $desc"; PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc (expected '$needle' in output)"
        echo "    got: $output"
        FAIL=$((FAIL + 1))
    fi
}

assert_not_contains() {
    local desc="$1" output="$2" needle="$3"
    TOTAL=$((TOTAL + 1))
    if ! echo "$output" | grep -q "$needle"; then
        echo "  PASS: $desc"; PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc (unexpected '$needle' in output)"
        echo "    got: $output"
        FAIL=$((FAIL + 1))
    fi
}

assert_json_continue() {
    local desc="$1" output="$2"
    TOTAL=$((TOTAL + 1))
    if echo "$output" | jq -e '.continue == true' >/dev/null 2>&1; then
        echo "  PASS: $desc"; PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc (expected .continue == true)"
        echo "    got: $output"
        FAIL=$((FAIL + 1))
    fi
}

assert_no_additional_context() {
    local desc="$1" output="$2"
    TOTAL=$((TOTAL + 1))
    if echo "$output" | jq -e '.additionalContext == null' >/dev/null 2>&1; then
        echo "  PASS: $desc"; PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc (expected no additionalContext)"
        echo "    got: $output"
        FAIL=$((FAIL + 1))
    fi
}

assert_has_additional_context() {
    local desc="$1" output="$2"
    TOTAL=$((TOTAL + 1))
    if echo "$output" | jq -e '.additionalContext | type == "string" and length > 0' >/dev/null 2>&1; then
        echo "  PASS: $desc"; PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc (expected non-empty additionalContext)"
        echo "    got: $output"
        FAIL=$((FAIL + 1))
    fi
}

run_hook() {
    local input="$1"
    echo "$input" | bash "$HOOK" 2>/dev/null
}

# Build a multi-line output string with N lines
make_lines() {
    local n="$1"
    python3 -c "print('\n'.join(f'line {i}' for i in range(1, $n + 1)))"
}

echo "=== test-bash-output-compress.sh ==="

echo ""
echo "--- Non-Bash tool: pass through ---"

OUT=$(run_hook '{"tool_name":"Edit","tool_input":{"file_path":"/tmp/foo.py"},"tool_result":{"output":"some output"}}')
assert_json_continue "Edit tool: continue true" "$OUT"
assert_no_additional_context "Edit tool: no additionalContext" "$OUT"

echo ""
echo "--- Small output (under threshold): pass through ---"

SMALL_OUT=$(make_lines 50)
PAYLOAD=$(jq -n --arg out "$SMALL_OUT" '{tool_name: "Bash", tool_input: {command: "ls"}, tool_result: {output: $out}}')
OUT=$(run_hook "$PAYLOAD")
assert_json_continue "50 lines: continue true" "$OUT"
assert_no_additional_context "50 lines: no additionalContext" "$OUT"

# Edge: exactly at the line threshold (100 lines) → no compress
EXACT_OUT=$(make_lines 100)
PAYLOAD=$(jq -n --arg out "$EXACT_OUT" '{tool_name: "Bash", tool_input: {command: "ls"}, tool_result: {output: $out}}')
OUT=$(run_hook "$PAYLOAD")
assert_json_continue "100 lines exactly: continue true" "$OUT"
assert_no_additional_context "100 lines exactly: no additionalContext" "$OUT"

echo ""
echo "--- Large output (over line threshold): compress ---"

LARGE_OUT=$(make_lines 200)
PAYLOAD=$(jq -n --arg out "$LARGE_OUT" '{tool_name: "Bash", tool_input: {command: "cargo test"}, tool_result: {output: $out}}')
OUT=$(run_hook "$PAYLOAD")
assert_json_continue "200 lines: continue true" "$OUT"
assert_has_additional_context "200 lines: has additionalContext" "$OUT"
assert_contains "200 lines: truncation marker present" "$OUT" "truncated"
assert_contains "200 lines: shows bash-output-compress label" "$OUT" "bash-output-compress"

echo ""
echo "--- Truncation marker contains line count ---"

PAYLOAD=$(jq -n --arg out "$LARGE_OUT" '{tool_name: "Bash", tool_input: {command: "ls"}, tool_result: {output: $out}}')
OUT=$(run_hook "$PAYLOAD")
# additionalContext should mention line count
CTX=$(echo "$OUT" | jq -r '.additionalContext // ""' 2>/dev/null)
assert_contains "200 lines: context contains '200 lines'" "$CTX" "200"
assert_contains "200 lines: context contains truncation marker" "$CTX" "lines truncated"

echo ""
echo "--- Large output via char threshold (wide lines) ---"

# 50 lines × 200 chars each = 10000 chars (over 8000 limit)
WIDE_LINE=$(python3 -c "print('x' * 200)")
WIDE_OUT=$(python3 -c "
line = 'x' * 200
print('\n'.join(f'line {i}: {line[:180]}' for i in range(1, 51)))
")
PAYLOAD=$(jq -n --arg out "$WIDE_OUT" '{tool_name: "Bash", tool_input: {command: "cat big.json"}, tool_result: {output: $out}}')
OUT=$(run_hook "$PAYLOAD")
assert_json_continue "wide 50 lines: continue true" "$OUT"
assert_has_additional_context "wide 50 lines over char threshold: has additionalContext" "$OUT"
assert_contains "wide 50 lines: truncation marker present" "$OUT" "truncated"

echo ""
echo "--- Empty output: pass through ---"

PAYLOAD=$(jq -n '{tool_name: "Bash", tool_input: {command: "echo"}, tool_result: {output: ""}}')
OUT=$(run_hook "$PAYLOAD")
assert_json_continue "empty output: continue true" "$OUT"
assert_no_additional_context "empty output: no additionalContext" "$OUT"

echo ""
echo "--- Missing tool_result: pass through gracefully ---"

PAYLOAD=$(jq -n '{tool_name: "Bash", tool_input: {command: "ls"}}')
OUT=$(run_hook "$PAYLOAD")
assert_json_continue "no tool_result: continue true" "$OUT"
assert_no_additional_context "no tool_result: no additionalContext" "$OUT"

echo ""
echo "--- tool_response fallback field ---"

LARGE_OUT2=$(make_lines 150)
PAYLOAD=$(jq -n --arg out "$LARGE_OUT2" '{tool_name: "Bash", tool_input: {command: "ls"}, tool_response: {content: $out}}')
OUT=$(run_hook "$PAYLOAD")
assert_json_continue "tool_response.content fallback: continue true" "$OUT"
assert_has_additional_context "tool_response.content fallback: has additionalContext" "$OUT"

echo ""
echo "--- Invalid JSON input: pass through ---"

OUT=$(echo "not json" | bash "$HOOK" 2>/dev/null)
assert_json_continue "invalid JSON: continue true" "$OUT"

echo ""
echo "Results: $PASS/$TOTAL passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1
exit 0
