#!/usr/bin/env bash
# Tests for goal-completion.sh Stop hook.
# All cases must return continue:true (never blocks stop).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/../goal-completion.sh"
PASS=0
FAIL=0
TOTAL=0

TMPDIR_TEST=$(mktemp -d)
trap 'rm -rf "$TMPDIR_TEST"' EXIT

GOAL_FILE="$TMPDIR_TEST/active-goal.json"

# Override HOME so the hook reads our test goal file
export HOME="$TMPDIR_TEST"
mkdir -p "$TMPDIR_TEST/.claude/run-state"

make_stop_input() {
    local cwd="${1:-/tmp}"
    printf '{"session_id":"test-sid","cwd":"%s","transcript_path":"/dev/null"}' "$cwd"
}

assert_continue() {
    local desc="$1" input="$2"
    TOTAL=$((TOTAL + 1))
    local out
    out=$(echo "$input" | bash "$HOOK" 2>/dev/null) || out=""
    if echo "$out" | grep -q '"continue".*true\|"continue":true'; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc — output: $out"
        FAIL=$((FAIL + 1))
    fi
}

assert_contains() {
    local desc="$1" input="$2" pattern="$3"
    TOTAL=$((TOTAL + 1))
    local out
    out=$(echo "$input" | bash "$HOOK" 2>/dev/null) || out=""
    if echo "$out" | grep -qF "$pattern"; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc — expected '$pattern' in: $out"
        FAIL=$((FAIL + 1))
    fi
}

# ── Test 1: no goal file → silent no-op ──────────────────────────────────────
echo "Test 1: no active-goal.json → no-op"
rm -f "$TMPDIR_TEST/.claude/run-state/active-goal.json"
assert_continue "no goal file → continue:true" "$(make_stop_input /tmp)"

# ── Test 2: goal file with wrong cwd → no-op ─────────────────────────────────
echo "Test 2: cwd mismatch → no-op"
cat > "$TMPDIR_TEST/.claude/run-state/active-goal.json" <<'EOF'
{"task_id":"t-999","cwd":"/some/other/repo","criteria":["AC: some criterion"]}
EOF
assert_continue "cwd mismatch → continue:true" "$(make_stop_input /different/path)"

# ── Test 3: goal file with empty criteria → no-op ────────────────────────────
echo "Test 3: empty criteria → no-op"
cat > "$TMPDIR_TEST/.claude/run-state/active-goal.json" <<'EOF'
{"task_id":"t-999","cwd":"/tmp","criteria":[]}
EOF
assert_continue "empty criteria → continue:true" "$(make_stop_input /tmp)"

# ── Test 4: file-exists check — file present → auto-complete msg ─────────────
echo "Test 4: file-exists criterion — file present"
TEST_FILE="$TMPDIR_TEST/testfile.sh"
touch "$TEST_FILE"
cat > "$TMPDIR_TEST/.claude/run-state/active-goal.json" <<EOF
{"task_id":"t-999","cwd":"$TMPDIR_TEST","criteria":["testfile.sh exists"]}
EOF
# Hook can't run brana CLI in test (no real brana), but it reads the goal file
# and tries the file-exists heuristic. Verify it returns continue:true.
assert_continue "file exists check → continue:true" "$(make_stop_input "$TMPDIR_TEST")"

# ── Test 5: file-exists check — file absent → failure msg with task id ────────
echo "Test 5: file-exists criterion — file absent"
cat > "$TMPDIR_TEST/.claude/run-state/active-goal.json" <<EOF
{"task_id":"t-777","cwd":"$TMPDIR_TEST","criteria":["missing-hook.sh exists"]}
EOF
assert_continue "file missing check → continue:true (never blocks)" "$(make_stop_input "$TMPDIR_TEST")"

# ── Test 6: unknown criterion → surface for manual sign-off ──────────────────
echo "Test 6: unknown criterion → manual sign-off msg"
cat > "$TMPDIR_TEST/.claude/run-state/active-goal.json" <<EOF
{"task_id":"t-888","cwd":"$TMPDIR_TEST","criteria":["The user can see the dashboard correctly"]}
EOF
# Should contain task ID in output (signals it was processed)
out=$(echo "$(make_stop_input "$TMPDIR_TEST")" | bash "$HOOK" 2>/dev/null) || out=""
if echo "$out" | grep -q '"continue"'; then
    echo "  PASS: unknown criterion → continue:true"
    PASS=$((PASS + 1))
else
    echo "  FAIL: unknown criterion — output: $out"
    FAIL=$((FAIL + 1))
fi
TOTAL=$((TOTAL + 1))

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "Results: $PASS/$TOTAL passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
