#!/usr/bin/env bash
# test-plugin-hooks.sh — Validate plugin hook paths and executability
#
# Checks:
# 1. Every command in hooks.json references a file that exists
# 2. Every referenced script is executable
# 3. All hooks use ${CLAUDE_PLUGIN_ROOT}, not relative paths
# 4. session-start-venture.sh exists (referenced by session-start.sh, not in hooks.json)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PLUGIN_ROOT="$REPO_ROOT/system"
HOOKS_JSON="$PLUGIN_ROOT/hooks/hooks.json"

PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  ✓ $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  ✗ $1"; }

echo "=== Plugin Hook Validation ==="
echo ""

# --- Test 1: hooks.json exists ---
echo "hooks.json:"
if [ -f "$HOOKS_JSON" ]; then
    pass "hooks.json exists"
else
    fail "hooks.json not found at $HOOKS_JSON"
    echo ""
    echo "=== $PASS passed, $FAIL failed ==="
    exit 1
fi

# --- Test 2: Valid JSON ---
if python3 -c "import json; json.load(open('$HOOKS_JSON'))" 2>/dev/null; then
    pass "hooks.json is valid JSON"
else
    fail "hooks.json is not valid JSON"
fi

# --- Test 3: Extract and validate all command paths ---
echo ""
echo "Hook scripts:"

# Extract all command values from hooks.json
COMMANDS=$(python3 -c "
import json
with open('$HOOKS_JSON') as f:
    data = json.load(f)
seen = set()
for event_hooks in data.get('hooks', {}).values():
    for matcher_group in event_hooks:
        for hook in matcher_group.get('hooks', []):
            cmd = hook.get('command', '')
            if cmd not in seen:
                seen.add(cmd)
                print(cmd)
")

while IFS= read -r cmd; do
    [ -z "$cmd" ] && continue

    # Test 3a: Uses ${CLAUDE_PLUGIN_ROOT}
    if echo "$cmd" | grep -q '${CLAUDE_PLUGIN_ROOT}'; then
        pass "$cmd uses \${CLAUDE_PLUGIN_ROOT}"
    else
        fail "$cmd does NOT use \${CLAUDE_PLUGIN_ROOT} — will fail at runtime"
    fi

    # Test 3b: Resolve path relative to plugin root and check existence
    resolved=$(echo "$cmd" | sed "s|\${CLAUDE_PLUGIN_ROOT}|$PLUGIN_ROOT|g")
    if [ -f "$resolved" ]; then
        pass "$(basename "$resolved") exists"
    else
        fail "$(basename "$resolved") not found at $resolved"
    fi

    # Test 3c: Script is executable
    if [ -x "$resolved" ]; then
        pass "$(basename "$resolved") is executable"
    else
        fail "$(basename "$resolved") is NOT executable"
    fi
done <<< "$COMMANDS"

# --- Test 4: Bundled cf-env.sh ---
echo ""
echo "Bundled dependencies:"
if [ -f "$PLUGIN_ROOT/hooks/lib/cf-env.sh" ]; then
    pass "hooks/lib/cf-env.sh bundled"
else
    fail "hooks/lib/cf-env.sh missing — hooks will fail without bootstrap"
fi

# --- Test 5: session-start-venture.sh (sourced by session-start.sh) ---
if [ -f "$PLUGIN_ROOT/hooks/session-start-venture.sh" ]; then
    pass "session-start-venture.sh exists (sourced by session-start.sh)"
else
    fail "session-start-venture.sh missing"
fi

if [ -x "$PLUGIN_ROOT/hooks/session-start-venture.sh" ]; then
    pass "session-start-venture.sh is executable"
else
    fail "session-start-venture.sh is NOT executable"
fi

# --- Test 6: plugin.json exists ---
echo ""
echo "Plugin manifest:"
if [ -f "$PLUGIN_ROOT/.claude-plugin/plugin.json" ]; then
    pass "plugin.json exists"
else
    fail "plugin.json not found"
fi

if python3 -c "import json; json.load(open('$PLUGIN_ROOT/.claude-plugin/plugin.json'))" 2>/dev/null; then
    pass "plugin.json is valid JSON"
else
    fail "plugin.json is not valid JSON"
fi

# --- Summary ---
echo ""
echo "=== $PASS passed, $FAIL failed ==="
[ $FAIL -eq 0 ] && exit 0 || exit 1
