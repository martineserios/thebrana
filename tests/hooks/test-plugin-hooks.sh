#!/usr/bin/env bash
# test-plugin-hooks.sh — Validate plugin hook paths and executability
#
# Checks:
# 1. Every script referenced by hooks.json exists in the REPO SOURCE tree
# 2. Every referenced script is executable
# 3. All hook paths are absolute via a known root — "$HOME/.claude" (the stable
#    deploy target adopted in c1a6a7f1) or ${CLAUDE_PLUGIN_ROOT} — never relative
# 4. Hook entries use the string command form (CC dropped args[], see a6927b9f)

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

# Extract every .sh referenced by hooks.json and resolve it against the REPO
# SOURCE tree. hooks.json points at "$HOME/.claude/hooks/" — the stable deploy
# target adopted in c1a6a7f1 so a branch switch or stash in thebrana cannot break
# hooks in other projects — but the artifact under test is the repo copy, not
# whatever happens to be deployed. Commands may be a bare invocation, a `bash -c`
# compound, or an external binary with no .sh at all (reported and skipped).
ENTRIES=$(PLUGIN_ROOT="$PLUGIN_ROOT" HOOKS_JSON="$HOOKS_JSON" python3 - <<'PYEOF'
import json, os, re

plugin_root = os.environ['PLUGIN_ROOT']
with open(os.environ['HOOKS_JSON']) as f:
    data = json.load(f)

seen = set()
for event_hooks in data.get('hooks', {}).values():
    for matcher_group in event_hooks:
        for hook in matcher_group.get('hooks', []):
            cmd = hook.get('command') or ' '.join(hook.get('args', []))
            if not cmd:
                continue
            paths = re.findall(r"""[^\s"';]+\.sh""", cmd)
            if not paths:
                print('EXTERNAL\t%s\t-' % cmd)
                continue
            for p in paths:
                resolved = (p.replace('${CLAUDE_PLUGIN_ROOT}', plugin_root)
                             .replace('${HOME}/.claude', plugin_root)
                             .replace('$HOME/.claude', plugin_root))
                if resolved in seen:
                    continue
                seen.add(resolved)
                print('SCRIPT\t%s\t%s' % (p, resolved))
PYEOF
)

while IFS=$'\t' read -r kind raw resolved; do
    [ -z "$kind" ] && continue

    if [ "$kind" = "EXTERNAL" ]; then
        echo "  ⊘ skipped — external binary, not a repo script: $raw"
        continue
    fi

    name="$(basename "$resolved")"

    # Test 3a: absolute via a known root, never relative or machine-specific
    case "$raw" in
        '${CLAUDE_PLUGIN_ROOT}'/*|'$HOME'/*|'${HOME}'/*)
            pass "$name is rooted at an absolute hook root" ;;
        /*)
            fail "$name uses a machine-specific absolute path: $raw" ;;
        *)
            fail "$name uses a relative path: $raw — will fail at runtime" ;;
    esac

    # Test 3b: resolves to a real file in the repo source tree
    if [ -f "$resolved" ]; then
        pass "$name exists in repo source"
    else
        fail "$name not found at $resolved"
    fi

    # Test 3c: Script is executable
    if [ -x "$resolved" ]; then
        pass "$name is executable"
    else
        fail "$name is NOT executable"
    fi
done <<< "$ENTRIES"

# --- Test 4: Bundled cf-env.sh ---
echo ""
echo "Bundled dependencies:"
if [ -f "$PLUGIN_ROOT/hooks/lib/cf-env.sh" ]; then
    pass "hooks/lib/cf-env.sh bundled"
else
    fail "hooks/lib/cf-env.sh missing — hooks will fail without bootstrap"
fi

# --- Test 5: lib/venture.sh (sourced by session-start.sh) ---
# The standalone session-start-venture.sh hook was removed in 84d541d1 as
# orphaned; venture detection now lives in lib/venture.sh, which session-start.sh
# sources inline. The dependency is what matters, so assert on the current file.
if [ -f "$PLUGIN_ROOT/hooks/lib/venture.sh" ]; then
    pass "hooks/lib/venture.sh bundled (sourced by session-start.sh)"
else
    fail "hooks/lib/venture.sh missing — session-start.sh venture detection will fail"
fi

if grep -q 'lib/venture.sh' "$PLUGIN_ROOT/hooks/session-start.sh"; then
    pass "session-start.sh sources lib/venture.sh"
else
    fail "session-start.sh no longer sources lib/venture.sh — update this test"
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

# --- Test 7: All hook entries use the string command form ---
# t-1413 originally migrated these to an args[] exec-form, but a6927b9f reverted
# it: the CC hooks schema dropped support for args[]. An entry carrying args[]
# instead of command is now silently inert, so assert the opposite of t-1413.
echo ""
echo "Command form (a6927b9f — args[] no longer supported by CC):"
ARGS_COUNT=$(HOOKS_JSON="$HOOKS_JSON" python3 - <<'PYEOF'
import json, os
with open(os.environ['HOOKS_JSON']) as f:
    data = json.load(f)
print(sum(
    1 for ev in data.get('hooks', {}).values()
    for mg in ev
    for h in mg.get('hooks', [])
    if 'command' not in h
))
PYEOF
)

if [ "$ARGS_COUNT" -eq 0 ]; then
    pass "all hook entries use the string command form"
else
    fail "$ARGS_COUNT hook entries lack a string command — CC dropped args[] (a6927b9f)"
fi

# --- Test 8: Gate taxonomy — advisory gates have continueOnBlock:true, enforcement gates do not ---
echo ""
echo "Gate taxonomy (continueOnBlock):"

ADVISORY_GATES="feedback-gate.sh post-plan-challenge.sh post-tasks-validate.sh memory-write-gate.sh"
ENFORCEMENT_GATES="tdd-gate.sh main-guard.sh branch-verify.sh worktree-gate.sh pre-tool-use.sh"

# Echoes "true"/"false" for the first hooks.json entry invoking $1, or "" if the
# gate is not wired at all. Matching is on the BASENAME of each .sh token: the
# raw command carries shell quoting (bash "$HOME/.claude/hooks/feedback-gate.sh"),
# so splitting the whole string on '/' yields a trailing quote and never matches —
# that bug made every enforcement assertion below pass vacuously.
gate_cob() {
    GATE="$1" HOOKS_JSON="$HOOKS_JSON" python3 - <<'PYEOF'
import json, os, re
gate = os.environ['GATE']
with open(os.environ['HOOKS_JSON']) as f:
    data = json.load(f)
matches = []
for ev in data.get('hooks', {}).values():
    for mg in ev:
        for h in mg.get('hooks', []):
            cmd = h.get('command') or ' '.join(h.get('args', []))
            names = [os.path.basename(p) for p in re.findall(r"""[^\s"';]+\.sh""", cmd)]
            if gate in names:
                matches.append('true' if h.get('continueOnBlock', False) else 'false')
print(matches[0] if matches else '')
PYEOF
}

for gate in $ADVISORY_GATES; do
    cob=$(gate_cob "$gate")
    if [ -z "$cob" ]; then
        fail "advisory $gate is not wired in hooks.json — cannot verify taxonomy"
    elif [ "$cob" = "true" ]; then
        pass "advisory $gate has continueOnBlock:true"
    else
        fail "advisory $gate missing continueOnBlock:true (t-1415)"
    fi
done

for gate in $ENFORCEMENT_GATES; do
    cob=$(gate_cob "$gate")
    if [ -z "$cob" ]; then
        fail "enforcement $gate is not wired in hooks.json — hard-stop unverifiable"
    elif [ "$cob" = "false" ]; then
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
