#!/usr/bin/env bash
# Tests: stale binary detection in session-start.sh
# Verifies [Stale binary] warning fires when binary predates last system/cli commit,
# and is silent when binary is fresh or no system/cli commits exist.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/../session-start.sh"
PASS=0
FAIL=0
TOTAL=0
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

FAKE_HOME="$TMPDIR/fakehome"
mkdir -p "$FAKE_HOME/.claude/projects/fake/memory"
echo "# Memory" > "$FAKE_HOME/.claude/projects/fake/memory/MEMORY.md"

SAFE_PATH="/usr/bin:/bin:/usr/sbin:/sbin"
GIT_BIN="$(dirname "$(command -v git)")"
JQ_BIN="$(dirname "$(command -v jq)")"
[[ ":$SAFE_PATH:" != *":$GIT_BIN:"* ]] && SAFE_PATH="$GIT_BIN:$SAFE_PATH"
[[ ":$SAFE_PATH:" != *":$JQ_BIN:"* ]] && SAFE_PATH="$JQ_BIN:$SAFE_PATH"

# ── Helpers ──────────────────────────────────────────────

setup_repo_with_cli_commit() {
    local dir="$1"
    mkdir -p "$dir/system/cli/rust/src"
    git -C "$dir" init -q -b main 2>/dev/null || git -C "$dir" init -q
    git -C "$dir" config user.email "test@test.com"
    git -C "$dir" config user.name "Test"
    echo "// cli" > "$dir/system/cli/rust/src/main.rs"
    git -C "$dir" add -A && git -C "$dir" commit -q -m "chore: cli init" 2>/dev/null
}

setup_repo_no_cli_commit() {
    local dir="$1"
    mkdir -p "$dir"
    git -C "$dir" init -q -b main 2>/dev/null || git -C "$dir" init -q
    git -C "$dir" config user.email "test@test.com"
    git -C "$dir" config user.name "Test"
    echo "init" > "$dir/README.md"
    git -C "$dir" add -A && git -C "$dir" commit -q -m "init" 2>/dev/null
}

make_fake_binary() {
    local dir="$1" age_seconds="$2"
    local bin="$dir/brana"
    echo '#!/usr/bin/env bash' > "$bin"
    chmod +x "$bin"
    # Set mtime to now minus age_seconds
    local target_time
    target_time=$(date -d "@$(( $(date +%s) - age_seconds ))" "+%Y%m%d%H%M.%S" 2>/dev/null || \
                  date -v "-${age_seconds}S" "+%Y%m%d%H%M.%S" 2>/dev/null) || true
    [ -n "${target_time:-}" ] && touch -t "$target_time" "$bin" 2>/dev/null || true
    echo "$bin"
}

run_hook() {
    local cwd="$1" bin_dir="$2"
    local input
    input=$(printf '{"session_id":"stale-test-%s","cwd":"%s","hook_event_name":"SessionStart","matcher":{}}' \
        "$(date +%s)" "$cwd")
    echo "$input" | \
        PATH="$bin_dir:$SAFE_PATH" \
        HOME="$FAKE_HOME" \
        CLAUDE_PLUGIN_DATA="" CLAUDE_PLUGIN_ROOT="" CLAUDE_ENV_FILE="" \
        BRANA_RECAP_OFF=1 BRANA_1M_WARN_OFF=1 BRANA_HOOK_PROFILE=standard \
        bash "$HOOK" 2>/dev/null | grep -E '^\{' | head -1
}

assert_context_contains() {
    local desc="$1" pattern="$2" output="$3"
    TOTAL=$((TOTAL + 1))
    local ctx
    ctx=$(echo "$output" | jq -r '.additionalContext // ""' 2>/dev/null)
    if echo "$ctx" | grep -qi "$pattern"; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc"
        echo "    expected context to contain: $pattern"
        echo "    got: $(echo "$ctx" | head -3)"
        FAIL=$((FAIL + 1))
    fi
}

assert_context_missing() {
    local desc="$1" pattern="$2" output="$3"
    TOTAL=$((TOTAL + 1))
    local ctx
    ctx=$(echo "$output" | jq -r '.additionalContext // ""' 2>/dev/null)
    if echo "$ctx" | grep -qi "$pattern"; then
        echo "  FAIL: $desc"
        echo "    expected context NOT to contain: $pattern"
        echo "    got: $(echo "$ctx" | grep -i "$pattern" | head -1)"
        FAIL=$((FAIL + 1))
    else
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    fi
}

# ── Tests ────────────────────────────────────────────────
echo "Stale Binary Detection Tests"
echo "============================"
echo ""

# Test 1: stale binary (older than last cli commit) → warning fires
echo "--- Stale binary ---"
REPO1="$TMPDIR/repo-stale"
setup_repo_with_cli_commit "$REPO1"
sleep 1  # ensure commit timestamp is clearly in the past

BIN_DIR1="$TMPDIR/bin-stale"
mkdir -p "$BIN_DIR1"
make_fake_binary "$BIN_DIR1" 86400  # binary is 1 day old

OUT1=$(run_hook "$REPO1" "$BIN_DIR1")
assert_context_contains "stale binary triggers warning" "Stale binary" "$OUT1"
assert_context_contains "warning contains rebuild hint" "cargo build" "$OUT1"

# Test 2: fresh binary (newer than last cli commit) → no warning
echo ""
echo "--- Fresh binary ---"
REPO2="$TMPDIR/repo-fresh"
setup_repo_with_cli_commit "$REPO2"

BIN_DIR2="$TMPDIR/bin-fresh"
mkdir -p "$BIN_DIR2"
make_fake_binary "$BIN_DIR2" 0  # binary is brand new (just created)

OUT2=$(run_hook "$REPO2" "$BIN_DIR2")
assert_context_missing "fresh binary produces no warning" "Stale binary" "$OUT2"

# Test 3: repo has no system/cli commits → no warning
echo ""
echo "--- No system/cli commits ---"
REPO3="$TMPDIR/repo-nocli"
setup_repo_no_cli_commit "$REPO3"

BIN_DIR3="$TMPDIR/bin-nocli"
mkdir -p "$BIN_DIR3"
make_fake_binary "$BIN_DIR3" 86400

OUT3=$(run_hook "$REPO3" "$BIN_DIR3")
assert_context_missing "no cli commits → no warning" "Stale binary" "$OUT3"

# Test 4: no brana binary in PATH → no warning (silent)
echo ""
echo "--- No binary in PATH ---"
REPO4="$TMPDIR/repo-nobin"
setup_repo_with_cli_commit "$REPO4"

EMPTY_BIN_DIR="$TMPDIR/bin-empty"
mkdir -p "$EMPTY_BIN_DIR"

OUT4=$(run_hook "$REPO4" "$EMPTY_BIN_DIR")
assert_context_missing "missing binary produces no warning" "Stale binary" "$OUT4"

# ── Summary ──────────────────────────────────────────────
echo ""
echo "Results: $PASS passed, $FAIL failed, $TOTAL total"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
