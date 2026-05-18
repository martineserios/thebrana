#!/usr/bin/env bash
# Integration test: session-end.sh → session-end-persist.sh env var chain
#
# Regression test for t-1450: PATTERN_LEARNINGS must be in session-end.sh export
# list so child (session-end-persist.sh, called via `bash`) inherits the value
# auto-populated from brana session state. Without the export, classify-then-route
# is dead code — this was the case for 6 weeks before t-1450 fixed it.
#
# Why a separate file from test-session-end-learnings.sh:
#   Those tests verify the OUTPUT (patterns.md content). This test verifies the
#   ENV VAR VALUE at the parent→child BOUNDARY, proving the export chain itself.
#
# Spy mechanism:
#   session-end.sh derives SCRIPT_DIR from BASH_SOURCE[0]. Copying it to a temp
#   dir makes SCRIPT_DIR = temp dir. All bash "${SCRIPT_DIR}/*.sh" calls resolve
#   to our stubs/spy. The spy session-end-persist.sh records $PATTERN_LEARNINGS
#   before doing anything else.
#
# Test 2 (canary) proves the test CATCHES the regression: it removes PATTERN_LEARNINGS
# from the export list in a copy of session-end.sh and asserts the spy sees empty.

set -euo pipefail

SCRIPT_DIR_TEST="$(cd "$(dirname "$0")" && pwd)"
HOOKS_DIR="$(cd "$SCRIPT_DIR_TEST/../../system/hooks" && pwd)"

PASS=0; FAIL=0
TEST_ID="chain-$$"

assert_contains() {
    local label="$1" haystack="$2" needle="$3"
    if echo "$haystack" | grep -qF "$needle"; then
        PASS=$((PASS+1)); echo "  PASS: $label"
    else
        FAIL=$((FAIL+1)); echo "  FAIL: $label — not found: '$needle' in '$haystack'"
    fi
}

assert_not_equals() {
    local label="$1" actual="$2" unexpected="$3"
    if [ "$actual" != "$unexpected" ]; then
        PASS=$((PASS+1)); echo "  PASS: $label"
    else
        FAIL=$((FAIL+1)); echo "  FAIL: $label — unexpected value: '$actual'"
    fi
}

assert_one_of() {
    local label="$1" actual="$2" opt1="$3" opt2="$4"
    if [ "$actual" = "$opt1" ] || [ "$actual" = "$opt2" ]; then
        PASS=$((PASS+1)); echo "  PASS: $label"
    else
        FAIL=$((FAIL+1)); echo "  FAIL: $label — expected '$opt1' or '$opt2', got '$actual'"
    fi
}

# Build a mirrored hooks dir with a spy persist.sh and no-op siblings.
# $dir/session-end.sh is a copy (or modified copy) of the real script.
# BASH_SOURCE[0] = $dir/session-end.sh → SCRIPT_DIR = $dir.
# All bash "${SCRIPT_DIR}/*.sh" calls resolve to $dir stubs/spy.
make_fake_hooks_dir() {
    local dir="$1" spy_file="$2" mode="${3:-normal}"
    mkdir -p "$dir"

    if [ "$mode" = "strip-export" ]; then
        # Canary: remove PATTERN_LEARNINGS from export to simulate missing export (the regression)
        sed 's/ PATTERN_LEARNINGS//' "$HOOKS_DIR/session-end.sh" > "$dir/session-end.sh"
    else
        cp "$HOOKS_DIR/session-end.sh" "$dir/session-end.sh"
    fi

    # lib/ symlink so source "${SCRIPT_DIR}/lib/resolve-brana.sh" resolves
    ln -s "$HOOKS_DIR/lib" "$dir/lib"

    # Stub metrics: writes empty env file so session-end.sh can source it without error
    cat > "$dir/session-end-metrics.sh" <<'EOF'
#!/usr/bin/env bash
[ -n "${METRICS_ENV_FILE:-}" ] && printf '' > "$METRICS_ENV_FILE"
EOF
    chmod +x "$dir/session-end-metrics.sh"

    # Spy persist: captures PATTERN_LEARNINGS value at the parent→child boundary
    # $spy_file expands NOW (absolute path); \${PATTERN_LEARNINGS:-EMPTY} expands at runtime
    cat > "$dir/session-end-persist.sh" <<FAKEPERSIST
#!/usr/bin/env bash
printf '%s' "\${PATTERN_LEARNINGS:-EMPTY}" > "$spy_file"
FAKEPERSIST
    chmod +x "$dir/session-end-persist.sh"

    # Stub drift: no-op
    cat > "$dir/session-end-drift.sh" <<'EOF'
#!/usr/bin/env bash
true
EOF
    chmod +x "$dir/session-end-drift.sh"
}

# Create a fake brana binary that returns session state with one learning entry.
# \$* escapes case argument; $learning expands NOW into the generated script.
make_fake_brana() {
    local dir="$1" learning="$2"
    cat > "$dir/brana" <<FAKEBRANA
#!/usr/bin/env bash
case "\$*" in
    "session read --json")
        echo '{"version":1,"learnings":["${learning}"]}'
        ;;
    "session path")
        echo "/tmp/fake-session-nonexistent-chain.json"
        ;;
    session\ write\ *)
        exit 0
        ;;
    *)
        exit 0
        ;;
esac
FAKEBRANA
    chmod +x "$dir/brana"
}

echo "=== session-end.sh → session-end-persist.sh env var chain integration tests ==="
echo ""

# ── Test 1: PATTERN_LEARNINGS flows through export to child process ──────────
echo "Test 1: PATTERN_LEARNINGS auto-populated and exported to session-end-persist.sh"

FAKE_DIR_1=$(mktemp -d /tmp/brana-test-chain-XXXXXX)
FAKE_PLUGIN_1=$(mktemp -d /tmp/brana-test-chain-plugin-XXXXXX)
FAKE_HOME_1=$(mktemp -d /tmp/brana-test-home-chain-XXXXXX)
SPY_FILE_1=$(mktemp /tmp/brana-test-chain-spy-XXXXXX)
SESSION_FILE_1="/tmp/brana-session-${TEST_ID}-1.jsonl"
echo '{"ts":1,"tool":"Bash","outcome":"success","detail":"test"}' > "$SESSION_FILE_1"

make_fake_hooks_dir "$FAKE_DIR_1" "$SPY_FILE_1" normal
make_fake_brana "$FAKE_PLUGIN_1" "export-chain learning must reach persist"

INPUT_1=$(jq -n -c --arg sid "${TEST_ID}-1" --arg cwd "/tmp" \
    '{session_id:$sid,cwd:$cwd,hook_event_name:"Stop"}')

# PATTERN_LEARNINGS intentionally NOT set — auto-populate + export chain is what we test
(
    export HOME="$FAKE_HOME_1"
    export CLAUDE_PLUGIN_DATA="$FAKE_PLUGIN_1"
    echo "$INPUT_1" | bash "$FAKE_DIR_1/session-end.sh" > /dev/null 2>&1
)
sleep 2

SPY_VALUE_1=$(cat "$SPY_FILE_1" 2>/dev/null || echo "SPY_NOT_WRITTEN")
assert_not_equals "spy: session-end-persist.sh was invoked" \
    "$SPY_VALUE_1" "SPY_NOT_WRITTEN"
assert_not_equals "spy: PATTERN_LEARNINGS not empty at persist boundary" \
    "$SPY_VALUE_1" "EMPTY"
assert_not_equals "spy: PATTERN_LEARNINGS not default empty array" \
    "$SPY_VALUE_1" "[]"
assert_contains "spy: learning text reached persist via export chain" \
    "$SPY_VALUE_1" "export-chain learning must reach persist"

rm -rf "$FAKE_DIR_1" "$FAKE_PLUGIN_1" "$FAKE_HOME_1" "$SPY_FILE_1" \
    "$SESSION_FILE_1" 2>/dev/null || true

# ── Test 2: Canary — missing export → child sees empty ──────────────────────
echo ""
echo "Test 2: canary — removing export from session-end.sh causes persist to see empty"

FAKE_DIR_2=$(mktemp -d /tmp/brana-test-chain-XXXXXX)
FAKE_PLUGIN_2=$(mktemp -d /tmp/brana-test-chain-plugin-XXXXXX)
FAKE_HOME_2=$(mktemp -d /tmp/brana-test-home-chain-XXXXXX)
SPY_FILE_2=$(mktemp /tmp/brana-test-chain-spy-XXXXXX)
SESSION_FILE_2="/tmp/brana-session-${TEST_ID}-2.jsonl"
echo '{"ts":1,"tool":"Bash","outcome":"success","detail":"test"}' > "$SESSION_FILE_2"

make_fake_hooks_dir "$FAKE_DIR_2" "$SPY_FILE_2" strip-export
make_fake_brana "$FAKE_PLUGIN_2" "this learning should not reach persist without export"

INPUT_2=$(jq -n -c --arg sid "${TEST_ID}-2" --arg cwd "/tmp" \
    '{session_id:$sid,cwd:$cwd,hook_event_name:"Stop"}')

(
    export HOME="$FAKE_HOME_2"
    export CLAUDE_PLUGIN_DATA="$FAKE_PLUGIN_2"
    echo "$INPUT_2" | bash "$FAKE_DIR_2/session-end.sh" > /dev/null 2>&1
)
sleep 2

SPY_VALUE_2=$(cat "$SPY_FILE_2" 2>/dev/null || echo "SPY_NOT_WRITTEN")
# Without export, child inherits nothing from parent's local PATTERN_LEARNINGS.
# Spy must see EMPTY or [] (default from ${PATTERN_LEARNINGS:-EMPTY}).
assert_one_of "canary: missing export → persist sees empty or default" \
    "$SPY_VALUE_2" "EMPTY" "[]"

rm -rf "$FAKE_DIR_2" "$FAKE_PLUGIN_2" "$FAKE_HOME_2" "$SPY_FILE_2" \
    "$SESSION_FILE_2" 2>/dev/null || true

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
