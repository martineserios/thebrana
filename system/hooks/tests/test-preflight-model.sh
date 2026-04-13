#!/usr/bin/env bash
# Tests for preflight-model.sh
# Verifies that the hook warns when heavy skills are invoked with extra-usage disabled.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/../preflight-model.sh"
PASS=0
FAIL=0
TMPDIR=$(mktemp -d)

trap 'rm -rf "$TMPDIR"' EXIT

assert_continue_true() {
    local desc="$1" json="$2"
    local val
    val=$(echo "$json" | jq -r '.continue' 2>/dev/null)
    if [ "$val" = "true" ]; then
        echo "  PASS: $desc (continue:true)"
        ((PASS++))
    else
        echo "  FAIL: $desc — expected continue:true, got: $json"
        ((FAIL++))
    fi
}

assert_contains() {
    local desc="$1" haystack="$2" needle="$3"
    if echo "$haystack" | grep -qF "$needle"; then
        echo "  PASS: $desc"
        ((PASS++))
    else
        echo "  FAIL: $desc — expected to contain '$needle'"
        ((FAIL++))
    fi
}

assert_no_ctx() {
    local desc="$1" json="$2"
    local val
    val=$(echo "$json" | jq -r '.additionalContext // ""' 2>/dev/null)
    if [ -z "$val" ]; then
        echo "  PASS: $desc (no additionalContext)"
        ((PASS++))
    else
        echo "  FAIL: $desc — expected no additionalContext, got: $val"
        ((FAIL++))
    fi
}

# Helper: make ~/.claude.json with given EU reason (or null)
make_claude_json() {
    local eu_reason="$1"
    if [ "$eu_reason" = "null" ]; then
        echo '{"cachedExtraUsageDisabledReason":null}' > "$TMPDIR/.claude.json"
    else
        echo "{\"cachedExtraUsageDisabledReason\":\"$eu_reason\"}" > "$TMPDIR/.claude.json"
    fi
}

# Helper: make UserPromptSubmit JSON input
make_input() {
    local prompt="$1"
    python3 -c "import json,sys; print(json.dumps({'prompt': sys.argv[1]}))" "$prompt"
}

echo "preflight-model.sh Tests"
echo "========================="

# --- Test 1: Non-heavy skill — pass through (no warning) ---
echo ""
echo "Test 1: Non-heavy skill prompt — pass through"
make_claude_json "org_disabled"
RESULT=$(make_input "continue" | HOME="$TMPDIR" bash "$HOOK")
assert_continue_true "non-heavy passthrough" "$RESULT"
assert_no_ctx "non-heavy → no warning" "$RESULT"

# --- Test 2: Heavy skill, extra-usage OK (null) — no warning ---
echo ""
echo "Test 2: Heavy skill, extra-usage enabled — no warning"
make_claude_json "null"
RESULT=$(make_input "/brana:close" | HOME="$TMPDIR" bash "$HOOK")
assert_continue_true "heavy + eu-ok → continue:true" "$RESULT"
assert_no_ctx "heavy + eu-ok → no warning" "$RESULT"

# --- Test 3: /brana:close + extra-usage disabled — warn ---
echo ""
echo "Test 3: /brana:close + extra-usage disabled — warn"
make_claude_json "org_disabled"
RESULT=$(make_input "/brana:close" | HOME="$TMPDIR" bash "$HOOK")
assert_continue_true "close + eu-disabled → continue:true (non-blocking)" "$RESULT"
CTX=$(echo "$RESULT" | jq -r '.additionalContext // ""' 2>/dev/null)
assert_contains "close + eu-disabled → warning contains skill name" "$CTX" "/brana:close"
assert_contains "close + eu-disabled → warning mentions extra-usage" "$CTX" "Extra-usage disabled"
assert_contains "close + eu-disabled → warning mentions eu reason" "$CTX" "org_disabled"

# --- Test 4: /brana:brainstorm + extra-usage disabled — warn ---
echo ""
echo "Test 4: /brana:brainstorm + extra-usage disabled — warn"
make_claude_json "plan_required"
RESULT=$(make_input "/brana:brainstorm on multi-agent orchestration" | HOME="$TMPDIR" bash "$HOOK")
assert_continue_true "brainstorm + eu-disabled → continue:true" "$RESULT"
CTX=$(echo "$RESULT" | jq -r '.additionalContext // ""' 2>/dev/null)
assert_contains "brainstorm → warning present" "$CTX" "PREFLIGHT WARNING"

# --- Test 5: /brana:build + extra-usage disabled — warn ---
echo ""
echo "Test 5: /brana:build + extra-usage disabled — warn"
make_claude_json "trial_expired"
RESULT=$(make_input "/brana:build the new session insights feature" | HOME="$TMPDIR" bash "$HOOK")
CTX=$(echo "$RESULT" | jq -r '.additionalContext // ""' 2>/dev/null)
assert_contains "build → warning present" "$CTX" "PREFLIGHT WARNING"

# --- Test 6: BRANA_1M_WARN_OFF silences the hook ---
echo ""
echo "Test 6: BRANA_1M_WARN_OFF=1 silences the hook"
make_claude_json "org_disabled"
RESULT=$(make_input "/brana:close" | HOME="$TMPDIR" BRANA_1M_WARN_OFF=1 bash "$HOOK")
assert_continue_true "BRANA_1M_WARN_OFF → continue:true" "$RESULT"
assert_no_ctx "BRANA_1M_WARN_OFF → no warning" "$RESULT"

# --- Test 7: No ~/.claude.json — pass through ---
echo ""
echo "Test 7: No ~/.claude.json — pass through"
RESULT=$(make_input "/brana:close" | HOME="$TMPDIR/nonexistent" bash "$HOOK")
assert_continue_true "no claude.json → continue:true" "$RESULT"
assert_no_ctx "no claude.json → no warning" "$RESULT"

# --- Test 8: Empty prompt → pass through ---
echo ""
echo "Test 8: Empty prompt → pass through"
make_claude_json "org_disabled"
RESULT=$(echo '{"prompt":""}' | HOME="$TMPDIR" bash "$HOOK")
assert_continue_true "empty prompt → continue:true" "$RESULT"

# --- Summary ---
echo ""
echo "========================="
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
