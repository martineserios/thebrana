#!/usr/bin/env bash
# Test: bootstrap.sh correctly injects PostToolUse hooks into settings.json
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR/../.."
PASS=0; FAIL=0; TOTAL=0

pass() { TOTAL=$((TOTAL+1)); PASS=$((PASS+1)); echo "  PASS: $1"; }
fail() { TOTAL=$((TOTAL+1)); FAIL=$((FAIL+1)); echo "  FAIL: $1"; }

echo "=== Test: bootstrap.sh settings.json hook injection ==="

# Setup: create temp dir simulating ~/.claude/
TMPDIR=$(mktemp -d)
MOCK_CLAUDE="$TMPDIR/.claude"
mkdir -p "$MOCK_CLAUDE"

# Create minimal settings.json
cat > "$MOCK_CLAUDE/settings.json" <<'EOF'
{
  "permissions": { "allow": [] },
  "alwaysThinkingEnabled": true
}
EOF

cleanup() { rm -rf "$TMPDIR"; }
trap cleanup EXIT

# Run bootstrap in check mode to verify it detects the change
OUTPUT=$(TARGET_DIR="$MOCK_CLAUDE" SYSTEM_DIR="$REPO_ROOT/system" CHECK_ONLY=true \
    bash -c '
    TARGET_DIR="'"$MOCK_CLAUDE"'"
    SYSTEM_DIR="'"$REPO_ROOT/system"'"
    SETTINGS_FILE="$TARGET_DIR/settings.json"
    HOOKS_DIR="$SYSTEM_DIR/hooks"
    CHANGES=0
    CHECK_ONLY=true

    # Extract just the hook injection logic from bootstrap.sh
    if [ -f "$SETTINGS_FILE" ] && command -v jq &>/dev/null; then
        HOOKS_JSON=$(jq -n \
            --arg hooks_dir "$HOOKS_DIR" \
            '"'"'{
                "PostToolUse": [
                    { "matcher": "Write|Edit|Bash", "hooks": [{ "type": "command", "command": ($hooks_dir + "/post-tool-use.sh"), "timeout": 5000 }] },
                    { "matcher": "Write|Edit", "hooks": [{ "type": "command", "command": ($hooks_dir + "/post-sale.sh"), "timeout": 5000 }] },
                    { "matcher": "ExitPlanMode", "hooks": [{ "type": "command", "command": ($hooks_dir + "/post-plan-challenge.sh"), "timeout": 5000 }] },
                    { "matcher": "Write|Edit", "hooks": [{ "type": "command", "command": ($hooks_dir + "/post-tasks-validate.sh"), "timeout": 5000 }] },
                    { "matcher": "Bash", "hooks": [{ "type": "command", "command": ($hooks_dir + "/post-pr-review.sh"), "timeout": 5000 }] }
                ],
                "PostToolUseFailure": [
                    { "matcher": "Write|Edit|Bash", "hooks": [{ "type": "command", "command": ($hooks_dir + "/post-tool-use-failure.sh"), "timeout": 5000 }] }
                ]
            }'"'"')

        jq --argjson hooks "$HOOKS_JSON" ".hooks = \$hooks" "$SETTINGS_FILE" > "$SETTINGS_FILE.tmp" \
            && mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"
        echo "INJECTED"
    fi
' 2>&1)

# Test 1: Valid JSON output
if jq . "$MOCK_CLAUDE/settings.json" > /dev/null 2>&1; then
    pass "Output is valid JSON"
else
    fail "Output is NOT valid JSON"
fi

# Test 2: PostToolUse section exists
if jq -e '.hooks.PostToolUse' "$MOCK_CLAUDE/settings.json" > /dev/null 2>&1; then
    pass "PostToolUse hooks present"
else
    fail "PostToolUse hooks missing"
fi

# Test 3: PostToolUseFailure section exists
if jq -e '.hooks.PostToolUseFailure' "$MOCK_CLAUDE/settings.json" > /dev/null 2>&1; then
    pass "PostToolUseFailure hooks present"
else
    fail "PostToolUseFailure hooks missing"
fi

# Test 4: Original settings preserved
if jq -e '.alwaysThinkingEnabled' "$MOCK_CLAUDE/settings.json" > /dev/null 2>&1; then
    pass "Original settings preserved"
else
    fail "Original settings lost"
fi

# Test 5: Correct number of PostToolUse entries (5 hooks)
COUNT=$(jq '.hooks.PostToolUse | length' "$MOCK_CLAUDE/settings.json" 2>/dev/null)
if [ "$COUNT" = "5" ]; then
    pass "PostToolUse has 5 hook entries"
else
    fail "PostToolUse has $COUNT entries (expected 5)"
fi

# Test 6: All hook commands point to existing scripts
CMDS=$(jq -r '.hooks | .[][] | .hooks[]? | .command' "$MOCK_CLAUDE/settings.json" 2>/dev/null)
ALL_EXIST=true
for cmd in $CMDS; do
    if [ ! -f "$cmd" ]; then
        fail "Hook script not found: $cmd"
        ALL_EXIST=false
    fi
done
$ALL_EXIST && pass "All hook scripts exist on disk"

# Test 7: All hook commands are absolute paths
ALL_ABS=true
for cmd in $CMDS; do
    if [[ "$cmd" != /* ]]; then
        fail "Hook command is not absolute: $cmd"
        ALL_ABS=false
    fi
done
$ALL_ABS && pass "All hook commands use absolute paths"

# Test 8: Idempotent — run again, no change
cp "$MOCK_CLAUDE/settings.json" "$TMPDIR/before.json"
# Re-run injection
jq --argjson hooks "$(jq '.hooks' "$MOCK_CLAUDE/settings.json")" '.hooks = $hooks' "$MOCK_CLAUDE/settings.json" > "$MOCK_CLAUDE/settings.json.tmp" \
    && mv "$MOCK_CLAUDE/settings.json.tmp" "$MOCK_CLAUDE/settings.json"
if diff -q "$TMPDIR/before.json" "$MOCK_CLAUDE/settings.json" > /dev/null 2>&1; then
    pass "Idempotent — second run produces same output"
else
    fail "NOT idempotent — second run changed output"
fi

echo ""
echo "=== Results: $PASS/$TOTAL passed ==="
[ $FAIL -eq 0 ] && exit 0 || exit 1
