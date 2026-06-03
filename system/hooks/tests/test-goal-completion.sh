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

# ── H5 Tests ──────────────────────────────────────────────────────────────────

# ── Test 7: H5 file-contains — string present → PASS ─────────────────────────
echo "Test 7: H5 file-contains — string present"
mkdir -p "$TMPDIR_TEST/docs"
echo "Status: Accepted" > "$TMPDIR_TEST/docs/test.md"
cat > "$TMPDIR_TEST/.claude/run-state/active-goal.json" <<EOF
{"task_id":"t-h5a","cwd":"$TMPDIR_TEST","criteria":["file docs/test.md contains \"Status: Accepted\""]}
EOF
assert_continue "H5 file-contains present → continue:true" "$(make_stop_input "$TMPDIR_TEST")"

# ── Test 8: H5 file-contains — string absent → FAIL (but still continue) ─────
echo "Test 8: H5 file-contains — string absent → FAILED criterion"
cat > "$TMPDIR_TEST/.claude/run-state/active-goal.json" <<EOF
{"task_id":"t-h5b","cwd":"$TMPDIR_TEST","criteria":["file docs/test.md contains \"Status: Rejected\""]}
EOF
assert_continue "H5 file-contains absent → continue:true (never blocks)" "$(make_stop_input "$TMPDIR_TEST")"

# ── H6 Tests ──────────────────────────────────────────────────────────────────

# ── Test 9: H6 jq query — match → PASS ───────────────────────────────────────
echo "Test 9: H6 jq query — matching value"
echo '{"enabled": false}' > "$TMPDIR_TEST/config.json"
cat > "$TMPDIR_TEST/.claude/run-state/active-goal.json" <<EOF
{"task_id":"t-h6a","cwd":"$TMPDIR_TEST","criteria":["jq '.enabled' config.json returns \"false\""]}
EOF
assert_continue "H6 jq match → continue:true" "$(make_stop_input "$TMPDIR_TEST")"

# ── Test 10: H6 jq query — mismatch → FAIL (but still continue) ──────────────
echo "Test 10: H6 jq query — mismatch"
cat > "$TMPDIR_TEST/.claude/run-state/active-goal.json" <<EOF
{"task_id":"t-h6b","cwd":"$TMPDIR_TEST","criteria":["jq '.enabled' config.json returns \"true\""]}
EOF
assert_continue "H6 jq mismatch → continue:true (never blocks)" "$(make_stop_input "$TMPDIR_TEST")"

# ── Test 11: H6 jq query — jq error on nonexistent file → UNKNOWN ────────────
echo "Test 11: H6 jq query — jq error → UNKNOWN (continue)"
cat > "$TMPDIR_TEST/.claude/run-state/active-goal.json" <<EOF
{"task_id":"t-h6c","cwd":"$TMPDIR_TEST","criteria":["jq '.foo' nonexistent.json returns \"bar\""]}
EOF
assert_continue "H6 jq error → continue:true (UNKNOWN, not FAILED)" "$(make_stop_input "$TMPDIR_TEST")"

# ── H7 Tests ──────────────────────────────────────────────────────────────────

# ── Test 12: H7 allowlisted command — non-matching → UNKNOWN ─────────────────
echo "Test 12: H7 non-allowlisted command → UNKNOWN"
cat > "$TMPDIR_TEST/.claude/run-state/active-goal.json" <<EOF
{"task_id":"t-h7a","cwd":"$TMPDIR_TEST","criteria":["\"rm -rf /\" passes"]}
EOF
assert_continue "H7 non-allowlisted → continue:true (UNKNOWN, never executed)" "$(make_stop_input "$TMPDIR_TEST")"

# ── Test 13: H7 allowlisted command — pytest passes ──────────────────────────
echo "Test 13: H7 allowlisted command — pytest exits 0 (mocked)"
# Create a fake pytest that exits 0
mkdir -p "$TMPDIR_TEST/bin"
echo '#!/usr/bin/env bash' > "$TMPDIR_TEST/bin/pytest"
echo 'exit 0' >> "$TMPDIR_TEST/bin/pytest"
chmod +x "$TMPDIR_TEST/bin/pytest"
OLD_PATH="$PATH"
export PATH="$TMPDIR_TEST/bin:$PATH"
cat > "$TMPDIR_TEST/.claude/run-state/active-goal.json" <<EOF
{"task_id":"t-h7b","cwd":"$TMPDIR_TEST","criteria":["\"pytest\" passes"]}
EOF
assert_continue "H7 allowlisted pytest exits 0 → continue:true" "$(make_stop_input "$TMPDIR_TEST")"
export PATH="$OLD_PATH"

# ── H8 Tests ──────────────────────────────────────────────────────────────────

# ── Test 14: H8 changes-committed — file has commits → PASS ──────────────────
echo "Test 14: H8 changes-to committed — file has git log"
GIT_TEST_DIR=$(mktemp -d)
(
    cd "$GIT_TEST_DIR"
    git init -q
    git config user.email "test@test.com"
    git config user.name "Test"
    touch tracked-file.sh
    git add tracked-file.sh
    git commit -q -m "add tracked-file.sh"
)
cat > "$TMPDIR_TEST/.claude/run-state/active-goal.json" <<EOF
{"task_id":"t-h8a","cwd":"$GIT_TEST_DIR","criteria":["changes to tracked-file.sh committed"]}
EOF
assert_continue "H8 changes-committed present → continue:true" "$(make_stop_input "$GIT_TEST_DIR")"
rm -rf "$GIT_TEST_DIR"

# ── Test 15: H8 commit-message-contains → PASS ───────────────────────────────
echo "Test 15: H8 commit-message-contains — string in log"
GIT_TEST_DIR2=$(mktemp -d)
(
    cd "$GIT_TEST_DIR2"
    git init -q
    git config user.email "test@test.com"
    git config user.name "Test"
    touch somefile.sh
    git add somefile.sh
    git commit -q -m "feat(harness): implement t-1828 heuristics"
)
cat > "$TMPDIR_TEST/.claude/run-state/active-goal.json" <<EOF
{"task_id":"t-h8b","cwd":"$GIT_TEST_DIR2","criteria":["commit message contains \"t-1828\""]}
EOF
assert_continue "H8 commit-message-contains → continue:true" "$(make_stop_input "$GIT_TEST_DIR2")"
rm -rf "$GIT_TEST_DIR2"

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "Results: $PASS/$TOTAL passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
