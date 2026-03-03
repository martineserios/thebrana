#!/usr/bin/env bash
# Tests for post-pr-review.sh hook
# Validates: gh pr create detection, non-matching commands, JSONL logging, JSON output.
#
set -euo pipefail

HOOKS_DIR="$(cd "$(dirname "$0")/../../system/hooks" && pwd)"
PASS=0
FAIL=0
SESSION_ID="test-pr-$$"
SESSION_FILE="/tmp/brana-session-${SESSION_ID}.jsonl"

cleanup() { rm -f "$SESSION_FILE"; }
trap cleanup EXIT

assert_outcome() {
    local label="$1" expected="$2" actual="$3"
    if [ "$actual" = "$expected" ]; then
        PASS=$((PASS + 1))
        echo "  PASS: $label"
    else
        FAIL=$((FAIL + 1))
        echo "  FAIL: $label — expected '$expected', got '$actual'"
    fi
}

# Run the pr-review hook and capture stdout JSON
run_pr_hook() {
    local tool="$1" command="$2"
    rm -f "$SESSION_FILE"
    local input
    input=$(jq -n -c --arg sid "$SESSION_ID" --arg tool "$tool" \
        --arg cmd "$command" \
        '{session_id: $sid, tool_name: $tool, tool_input: ({command: $cmd} | tostring)}')
    echo "$input" | bash "$HOOKS_DIR/post-pr-review.sh" 2>/dev/null
}

# Run hook and return just the additionalContext field (or "null")
get_additional_context() {
    local output
    output=$(run_pr_hook "$1" "$2")
    echo "$output" | jq -r '.additionalContext // "null"' 2>/dev/null
}

# Run hook and return just the continue field
get_continue() {
    local output
    output=$(run_pr_hook "$1" "$2")
    echo "$output" | jq -r '.continue' 2>/dev/null
}

# ═══════════════════════════════════════════════════════════════
# SECTION 1: Detection — gh pr create commands
# ═══════════════════════════════════════════════════════════════

echo "=== post-pr-review.sh (PR create detection) ==="

echo ""
echo "--- Commands that SHOULD trigger pr-review nudge ---"

# Basic gh pr create
CTX=$(get_additional_context "Bash" "gh pr create")
assert_outcome "gh pr create → has additionalContext" "true" "$([ "$CTX" != "null" ] && echo true || echo false)"

# With flags
CTX=$(get_additional_context "Bash" "gh pr create --title \"Fix auth bug\" --body \"Fixes #123\"")
assert_outcome "gh pr create --title → has additionalContext" "true" "$([ "$CTX" != "null" ] && echo true || echo false)"

# With --draft flag
CTX=$(get_additional_context "Bash" "gh pr create --draft")
assert_outcome "gh pr create --draft → has additionalContext" "true" "$([ "$CTX" != "null" ] && echo true || echo false)"

# With --base flag
CTX=$(get_additional_context "Bash" "gh pr create --base main --head feat/thing")
assert_outcome "gh pr create --base → has additionalContext" "true" "$([ "$CTX" != "null" ] && echo true || echo false)"

echo ""
echo "--- Commands that should NOT trigger ---"

# gh pr view (not create)
CTX=$(get_additional_context "Bash" "gh pr view 123")
assert_outcome "gh pr view → no additionalContext" "null" "$CTX"

# gh pr list
CTX=$(get_additional_context "Bash" "gh pr list")
assert_outcome "gh pr list → no additionalContext" "null" "$CTX"

# gh issue create (not pr)
CTX=$(get_additional_context "Bash" "gh issue create --title \"Bug\"")
assert_outcome "gh issue create → no additionalContext" "null" "$CTX"

# Regular commands
CTX=$(get_additional_context "Bash" "ls -la")
assert_outcome "ls -la → no additionalContext" "null" "$CTX"

CTX=$(get_additional_context "Bash" "git push origin main")
assert_outcome "git push → no additionalContext" "null" "$CTX"

CTX=$(get_additional_context "Bash" "npm test")
assert_outcome "npm test → no additionalContext" "null" "$CTX"

echo ""
echo "--- Non-Bash tools → fast exit, no additionalContext ---"

# Non-Bash tools should not match
OUTPUT=$(run_pr_hook "Edit" "")
CTX=$(echo "$OUTPUT" | jq -r '.additionalContext // "null"' 2>/dev/null)
assert_outcome "Edit tool → no additionalContext" "null" "$CTX"

OUTPUT=$(run_pr_hook "Write" "")
CTX=$(echo "$OUTPUT" | jq -r '.additionalContext // "null"' 2>/dev/null)
assert_outcome "Write tool → no additionalContext" "null" "$CTX"

# ═══════════════════════════════════════════════════════════════
# SECTION 2: Output format — always valid JSON with continue: true
# ═══════════════════════════════════════════════════════════════

echo ""
echo "=== Output format ==="

echo ""
echo "--- All outputs have continue: true ---"

CONT=$(get_continue "Bash" "gh pr create")
assert_outcome "pr create → continue: true" "true" "$CONT"

CONT=$(get_continue "Bash" "ls -la")
assert_outcome "regular cmd → continue: true" "true" "$CONT"

CONT=$(get_continue "Edit" "")
assert_outcome "non-Bash → continue: true" "true" "$CONT"

echo ""
echo "--- Output is valid JSON ---"

OUTPUT=$(run_pr_hook "Bash" "gh pr create")
VALID=$(echo "$OUTPUT" | jq -e '.' >/dev/null 2>&1 && echo "true" || echo "false")
assert_outcome "pr create output is valid JSON" "true" "$VALID"

OUTPUT=$(run_pr_hook "Bash" "ls")
VALID=$(echo "$OUTPUT" | jq -e '.' >/dev/null 2>&1 && echo "true" || echo "false")
assert_outcome "regular cmd output is valid JSON" "true" "$VALID"

# ═══════════════════════════════════════════════════════════════
# SECTION 3: JSONL logging
# ═══════════════════════════════════════════════════════════════

echo ""
echo "=== JSONL session logging ==="

echo ""
echo "--- pr-create outcome logged to session file ---"

rm -f "$SESSION_FILE"
run_pr_hook "Bash" "gh pr create" >/dev/null
assert_outcome "session file created" "true" "$([ -f "$SESSION_FILE" ] && echo true || echo false)"

LOGGED_OUTCOME=$(jq -r '.outcome' "$SESSION_FILE" 2>/dev/null | tail -1)
assert_outcome "logged outcome = pr-create" "pr-create" "$LOGGED_OUTCOME"

LOGGED_TOOL=$(jq -r '.tool' "$SESSION_FILE" 2>/dev/null | tail -1)
assert_outcome "logged tool = post-pr-review" "post-pr-review" "$LOGGED_TOOL"

echo ""
echo "--- Non-matching commands do NOT log ---"

rm -f "$SESSION_FILE"
run_pr_hook "Bash" "ls -la" >/dev/null
assert_outcome "no session file for non-matching cmd" "false" "$([ -f "$SESSION_FILE" ] && echo true || echo false)"

rm -f "$SESSION_FILE"
run_pr_hook "Edit" "" >/dev/null
assert_outcome "no session file for non-Bash tool" "false" "$([ -f "$SESSION_FILE" ] && echo true || echo false)"

# ═══════════════════════════════════════════════════════════════
# Results
# ═══════════════════════════════════════════════════════════════

echo ""
echo "==========================================="
echo "Results: $PASS passed, $FAIL failed"
echo "==========================================="

[ "$FAIL" -eq 0 ] && exit 0 || exit 1
