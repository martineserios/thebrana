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

# Extract all script paths from hooks.json — handles both string-command and args[] forms
COMMANDS=$(python3 -c "
import json
with open('$HOOKS_JSON') as f:
    data = json.load(f)
seen = set()
for event_hooks in data.get('hooks', {}).values():
    for matcher_group in event_hooks:
        for hook in matcher_group.get('hooks', []):
            # Support string-command form and exec-form args[]
            cmd = hook.get('command') or (hook['args'][1] if 'args' in hook and len(hook['args']) > 1 else '')
            if cmd and cmd not in seen:
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

# --- Test 7: All hook entries use exec-form args[] (t-1413) ---
echo ""
echo "Exec-form migration:"
STRING_COUNT=$(python3 -c "
import json
with open('$HOOKS_JSON') as f:
    data = json.load(f)
count = sum(
    1 for ev in data.get('hooks', {}).values()
    for mg in ev
    for h in mg.get('hooks', [])
    if 'command' in h
)
print(count)
")

if [ "$STRING_COUNT" -eq 0 ]; then
    pass "all hook entries use args[] exec-form (no string command form)"
else
    fail "$STRING_COUNT hook entries still use string command form — must migrate to args[] (t-1413)"
fi

# --- Test 8: Gate taxonomy — advisory gates have continueOnBlock:true, enforcement gates do not ---
echo ""
echo "Gate taxonomy (continueOnBlock):"

ADVISORY_GATES="feedback-gate.sh post-plan-challenge.sh post-tasks-validate.sh"
ENFORCEMENT_GATES="tdd-gate.sh main-guard.sh branch-verify.sh worktree-gate.sh pre-tool-use.sh"

for gate in $ADVISORY_GATES; do
    cob=$(python3 -c "
import json
with open('$HOOKS_JSON') as f:
    data = json.load(f)
for ev in data.get('hooks', {}).values():
    for mg in ev:
        for h in mg.get('hooks', []):
            path = h.get('command') or (h.get('args', ['',''])[1] if 'args' in h else '')
            if path.split('/')[-1] == '$gate':
                print('true' if h.get('continueOnBlock', False) else 'false')
" 2>/dev/null | head -1)
    if [ "$cob" = "true" ]; then
        pass "advisory $gate has continueOnBlock:true"
    else
        fail "advisory $gate missing continueOnBlock:true (t-1415)"
    fi
done

for gate in $ENFORCEMENT_GATES; do
    cob=$(python3 -c "
import json
with open('$HOOKS_JSON') as f:
    data = json.load(f)
for ev in data.get('hooks', {}).values():
    for mg in ev:
        for h in mg.get('hooks', []):
            path = h.get('command') or (h.get('args', ['',''])[1] if 'args' in h else '')
            if path.split('/')[-1] == '$gate':
                print('true' if h.get('continueOnBlock', False) else 'false')
" 2>/dev/null | head -1)
    if [ "$cob" = "false" ] || [ -z "$cob" ]; then
        pass "enforcement $gate has no continueOnBlock (hard-stop)"
    else
        fail "enforcement $gate must NOT have continueOnBlock — breaks hard-stop invariant"
    fi
done

# --- Test 9: cc-changelog-check.sh wired as async SessionStart hook (t-1419) ---
echo ""
echo "Async changelog hook (t-1419):"

CHANGELOG_FOUND=$(python3 -c "
import json
with open('$HOOKS_JSON') as f:
    data = json.load(f)
for mg in data.get('hooks', {}).get('SessionStart', []):
    for h in mg.get('hooks', []):
        path = ' '.join(h.get('args', [])) or h.get('command', '')
        if 'cc-changelog-check' in path:
            is_async = h.get('async', False)
            print('async' if is_async else 'sync')
" 2>/dev/null | head -1)

if [ "$CHANGELOG_FOUND" = "async" ]; then
    pass "cc-changelog-check.sh wired as async SessionStart hook"
elif [ "$CHANGELOG_FOUND" = "sync" ]; then
    fail "cc-changelog-check.sh wired but missing async:true — will block session start"
else
    fail "cc-changelog-check.sh not wired as SessionStart hook (t-1419)"
fi

# --- Summary ---
echo ""
echo "=== $PASS passed, $FAIL failed ==="
[ $FAIL -eq 0 ] && exit 0 || exit 1
