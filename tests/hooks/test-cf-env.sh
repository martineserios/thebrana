#!/usr/bin/env bash
# Tests for cf-env.sh — ruflo binary resolution and cf_run() wrapper.
# Run: bash tests/hooks/test-cf-env.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

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
        echo "  FAIL: $desc (expected '$expected', got '$actual')"
        FAIL=$((FAIL + 1))
    fi
}

echo "=== test-cf-env.sh ==="

# ── Test 1: Plugin cf-env.sh exists and defines cf_run ──
echo "Test 1: cf-env.sh structure"
PLUGIN_CF="$REPO_ROOT/system/hooks/lib/cf-env.sh"
assert "plugin cf-env.sh exists" "true" "$([ -f "$PLUGIN_CF" ] && echo true || echo false)"

# Source and check
source "$PLUGIN_CF"
assert "CF variable is set" "true" "$([ -n "${CF:-}" ] && echo true || echo false)"
assert "cf_run function exists" "true" "$(type cf_run &>/dev/null && echo true || echo false)"

# ── Test 2: Bootstrap cf-env.sh also has cf_run ──
echo "Test 2: Bootstrap cf-env.sh"
BOOTSTRAP_CF="$HOME/.claude/scripts/cf-env.sh"
if [ -f "$BOOTSTRAP_CF" ]; then
    # Source in subshell to avoid conflicts
    HAS_CF_RUN=$(bash -c "source '$BOOTSTRAP_CF' && type cf_run &>/dev/null && echo true || echo false")
    assert "bootstrap cf-env.sh has cf_run" "true" "$HAS_CF_RUN"
else
    echo "  SKIP: bootstrap cf-env.sh not found (not deployed)"
    TOTAL=$((TOTAL + 1))
    PASS=$((PASS + 1))
fi

# ── Test 3: cf_run() changes to $HOME ──
echo "Test 3: cf_run() runs from HOME"
# Create a test that verifies cwd inside cf_run
# We can't easily test $CF execution, but we can verify the cd happens
CF_RUN_CWD=$(bash -c "
    source '$PLUGIN_CF'
    CF='pwd'  # Override CF to just print cwd
    cf_run
")
assert "cf_run runs from HOME" "$HOME" "$CF_RUN_CWD"

# ── Test 4: Session hooks use cd HOME before $CF ──
echo "Test 4: Hooks use 'cd \$HOME' before \$CF calls"
SESSION_START="$REPO_ROOT/system/hooks/session-start.sh"
SESSION_END="$REPO_ROOT/system/hooks/session-end.sh"

# Count $CF calls that DON'T have cd "$HOME" before them
# All $CF memory calls should be preceded by cd "$HOME" &&
if [ -f "$SESSION_START" ]; then
    # Find lines with $CF memory that are NOT preceded by cd "$HOME"
    BAD_CF_START=$(grep -c '$CF memory' "$SESSION_START" 2>/dev/null || true)
    GOOD_CF_START=$(grep '$CF memory' "$SESSION_START" 2>/dev/null | grep -c 'cd "$HOME"' 2>/dev/null || true)
    assert "session-start: all \$CF memory calls have cd HOME" "${BAD_CF_START:-0}" "${GOOD_CF_START:-0}"
fi

if [ -f "$SESSION_END" ]; then
    BAD_CF_END=$(grep -c '$CF memory' "$SESSION_END" 2>/dev/null || true)
    GOOD_CF_END=$(grep '$CF memory' "$SESSION_END" 2>/dev/null | grep -c 'cd "$HOME"' 2>/dev/null || true)
    assert "session-end: all \$CF memory calls have cd HOME" "${BAD_CF_END:-0}" "${GOOD_CF_END:-0}"
fi

# ── Test 5: CF resolves to a real binary ──
echo "Test 5: CF resolves to executable"
if [ -n "${CF:-}" ]; then
    # CF might be "npx ruflo" (two words) — check first word
    CF_BIN="${CF%% *}"
    assert "CF binary exists" "true" "$(command -v "$CF_BIN" &>/dev/null && echo true || echo false)"
else
    echo "  SKIP: CF not set"
    TOTAL=$((TOTAL + 1))
    PASS=$((PASS + 1))
fi

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
