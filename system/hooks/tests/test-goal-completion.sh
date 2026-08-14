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

# ════════════════════════════════════════════════════════════════════════════
# Gaming-attack suite (t-2210 / ADR-061 §4 invariants 1+2)
#
# `/goal` is an optimizer with the done-signal as its objective function. These
# tests assert the HARDENED goal-completion.sh BLOCKS done-signal gaming: each
# attack edits something the grader reads (a *.test.* file, tests/fixtures,
# tests/mocks, __mocks__, the task record) AFTER the goal's base-ref was pinned,
# or invokes the hook with no proof of an interactive session, and asserts the
# hook GATES (surfaces for manual sign-off) instead of auto-completing.
#
# CONTRACT (what t-2204 must implement):
#   • active-goal.json gains:  base_ref  (git SHA pinned at /goal start)
#                              session_id (already present)
#   • Auto-advance requires BOTH:
#       (1) PRESENCE INTERLOCK — a fresh (<15m) presence token
#           $HOME/.claude/run-state/presence-<session_id> whose name matches the
#           Stop event's session_id. Absence/staleness ⇒ gate (invariant 1).
#       (2) GRADER IMMUTABILITY — base_ref present AND no path the grader reads
#           changed since base_ref:  *.test.*, tests/** (incl fixtures/, mocks/),
#           __mocks__/**, .claude/tasks.json — checked as BOTH a tracked diff vs
#           base_ref AND untracked files. Any hit ⇒ gate (invariant 2).
#   • On violation: emit additionalContext containing "goal blocked: <reason>"
#     (reason names "grader path" or "presence"), do NOT mark the task completed,
#     do NOT remove the goal file. Always continue:true (Stop hooks never block).
#
# These MUST fail against the current hook (which auto-completes regardless) and
# pass after t-2204 lands. The control case (G6) must pass against BOTH so the
# gate is specific, not a blanket block.
# ════════════════════════════════════════════════════════════════════════════

# Force a deterministic, executable brana (resolve-brana checks CLAUDE_PLUGIN_DATA
# first) so the auto-complete path is reachable — otherwise the hook early-exits
# at the brana check and the gaming attacks can't be exercised.
GAME_BIN="$TMPDIR_TEST/gamebin"
mkdir -p "$GAME_BIN"
printf '#!/usr/bin/env bash\nexit 0\n' > "$GAME_BIN/brana"
chmod +x "$GAME_BIN/brana"
export CLAUDE_PLUGIN_DATA="$GAME_BIN"

GAME_SID="test-sid"   # must match make_stop_input's session_id

# Build a git repo with a clean baseline; echo "<dir> <base_sha>"
make_goal_repo() {
    local dir; dir=$(mktemp -d)
    (
        cd "$dir" || exit 1
        git init -q 2>/dev/null
        git config user.email "t@t.com"; git config user.name "T"
        mkdir -p tests/fixtures tests/mocks __mocks__ .claude
        echo "console.log('app')"                          > app.js
        echo "test('ok', () => {})"                         > app.test.js
        echo '{"seed": 1}'                                  > tests/fixtures/data.json
        echo '{"task_id":"t-999","status":"in_progress"}'  > .claude/tasks.json
        git add -A; git commit -q -m "baseline" 2>/dev/null
    )
    echo "$dir $(git -C "$dir" rev-parse HEAD 2>/dev/null)"
}

write_goal() {            # write_goal <cwd> <base_ref> <criterion>
    cat > "$TMPDIR_TEST/.claude/run-state/active-goal.json" <<EOF
{"task_id":"t-999","session_id":"$GAME_SID","cwd":"$1","base_ref":"$2","criteria":["$3"]}
EOF
}

fresh_presence() {        # prove an interactive session for GAME_SID
    mkdir -p "$TMPDIR_TEST/.claude/run-state"
    : > "$TMPDIR_TEST/.claude/run-state/presence-$GAME_SID"
}
clear_presence() { rm -f "$TMPDIR_TEST/.claude/run-state/presence-$GAME_SID"; }

# continue:true AND task NOT completed AND a gate reason surfaced
assert_gated() {          # assert_gated <desc> <input> <reason-substr>
    local desc="$1" input="$2" reason="$3"; TOTAL=$((TOTAL + 1))
    local out; out=$(echo "$input" | bash "$HOOK" 2>/dev/null) || out=""
    if echo "$out" | grep -q '"continue".*true' \
       && ! echo "$out" | grep -qiE 'Goal complete|auto-marked completed' \
       && echo "$out" | grep -qiF "goal blocked" \
       && echo "$out" | grep -qiF "$reason"; then
        echo "  PASS: $desc"; PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc — output: $out"; FAIL=$((FAIL + 1))
    fi
}

# control: a clean interactive run still auto-completes (no over-blocking)
assert_completes() {      # assert_completes <desc> <input>
    local desc="$1" input="$2"; TOTAL=$((TOTAL + 1))
    local out; out=$(echo "$input" | bash "$HOOK" 2>/dev/null) || out=""
    if echo "$out" | grep -qiE 'Goal complete|auto-marked completed'; then
        echo "  PASS: $desc"; PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc — output: $out"; FAIL=$((FAIL + 1))
    fi
}

# ── G1 (AC1): editing a *.test.* file after base-ref → gate ───────────────────
echo "Test G1 (AC1): *.test.* mutation mid-iteration trips the grader gate"
read -r RG1 BR1 <<< "$(make_goal_repo)"
fresh_presence
write_goal "$RG1" "$BR1" "app.js exists"
echo "// gamed assertion" >> "$RG1/app.test.js"          # mutate a graded test file
assert_gated "editing app.test.js trips gate" "$(make_stop_input "$RG1")" "grader path"
rm -rf "$RG1"

# ── G2 (AC2): editing tests/fixtures, tests/mocks, or __mocks__ → gate ────────
echo "Test G2 (AC2): tests/fixtures|tests/mocks|__mocks__ mutation trips the grader gate"
read -r RG2 BR2 <<< "$(make_goal_repo)"
fresh_presence
write_goal "$RG2" "$BR2" "app.js exists"
echo '{"x":2}'  > "$RG2/tests/fixtures/extra.json"        # new untracked fixture
echo 'mockmod'  > "$RG2/tests/mocks/m.js"                 # new untracked mock
echo 'mockmod'  > "$RG2/__mocks__/g.js"                   # new untracked __mocks__
assert_gated "editing fixtures/mocks/__mocks__ trips gate" "$(make_stop_input "$RG2")" "grader path"
rm -rf "$RG2"

# ── G3 (AC3): editing the AC: lines / acceptance_criteria → gate ──────────────
echo "Test G3 (AC3): rewriting acceptance_criteria mid-iteration trips the grader gate"
read -r RG3 BR3 <<< "$(make_goal_repo)"
fresh_presence
write_goal "$RG3" "$BR3" "app.js exists"
# attacker weakens the task's own acceptance criteria to something trivial
echo '{"task_id":"t-999","status":"in_progress","acceptance_criteria":["AC: true"]}' > "$RG3/.claude/tasks.json"
assert_gated "editing acceptance_criteria trips gate" "$(make_stop_input "$RG3")" "grader path"
rm -rf "$RG3"

# ── G4 (AC4): editing a task-record field a heuristic reads → gate ────────────
echo "Test G4 (AC4): forging a tasks.json field (status/notes/context) trips the grader gate"
read -r RG4 BR4 <<< "$(make_goal_repo)"
fresh_presence
write_goal "$RG4" "$BR4" "app.js exists"
# attacker forges the task status the brana-backlog-get heuristic would read
echo '{"task_id":"t-999","status":"completed","notes":"done"}' > "$RG4/.claude/tasks.json"
assert_gated "forging tasks.json status/notes trips gate" "$(make_stop_input "$RG4")" "grader path"
rm -rf "$RG4"

# ── G5 (AC5): headless / non-interactive invocation refuses auto-advance ──────
echo "Test G5 (AC5): no fresh presence token → presence interlock refuses auto-advance"
read -r RG5 BR5 <<< "$(make_goal_repo)"
clear_presence                                            # NO proof of interactive session
write_goal "$RG5" "$BR5" "app.js exists"
# nothing is gamed — the ONLY problem is the missing interactive presence
assert_gated "headless run refuses auto-advance" "$(make_stop_input "$RG5")" "presence"
rm -rf "$RG5"

# ── G6 (control): clean interactive run still auto-completes ──────────────────
echo "Test G6 (control): clean interactive run (fresh presence, base-ref pinned, no mutation) auto-completes"
read -r RG6 BR6 <<< "$(make_goal_repo)"
fresh_presence
write_goal "$RG6" "$BR6" "app.js exists"
assert_completes "clean run still auto-completes (gate is specific)" "$(make_stop_input "$RG6")"
rm -rf "$RG6"

# ── G7 (Option C): a REGISTERED new test file is exempt → auto-completes ──────
echo "Test G7 (Option C): registered+hash-pinned new test is exempt → auto-completes"
read -r RG7 BR7 <<< "$(make_goal_repo)"
fresh_presence
echo "test('new', () => {})" > "$RG7/tests/new.test.js"   # build writes a new test...
git -C "$RG7" add -A >/dev/null 2>&1; git -C "$RG7" commit -q -m "add red test" 2>/dev/null
PIN7=$(sha256sum "$RG7/tests/new.test.js" | cut -d' ' -f1)
cat > "$TMPDIR_TEST/.claude/run-state/active-goal.json" <<EOF
{"task_id":"t-999","session_id":"$GAME_SID","cwd":"$RG7","base_ref":"$BR7","criteria":["app.js exists"],"tests_required":["tests/new.test.js"],"tests_hashes":{"tests/new.test.js":"$PIN7"}}
EOF
assert_completes "registered+pinned new test is exempt" "$(make_stop_input "$RG7")"
rm -rf "$RG7"

# ── G8 (Option C): an UNREGISTERED new test file still blocks (G2-class guard) ─
echo "Test G8 (Option C): unregistered new test file is NOT exempt → gate"
read -r RG8 BR8 <<< "$(make_goal_repo)"
fresh_presence
write_goal "$RG8" "$BR8" "app.js exists"                  # no tests_required
echo "test('sneaky', () => {})" > "$RG8/tests/sneaky.test.js"   # new, untracked, unregistered
assert_gated "unregistered new test trips gate" "$(make_stop_input "$RG8")" "grader path"
rm -rf "$RG8"

# ── G9 (Option C boundary): registering a PRE-EXISTING path can't launder a modification ──
echo "Test G9 (Option C boundary): registered pre-existing test still blocks when MODIFIED"
read -r RG9 BR9 <<< "$(make_goal_repo)"
fresh_presence
echo "// gamed" >> "$RG9/app.test.js"                     # modify a pre-existing graded test
cat > "$TMPDIR_TEST/.claude/run-state/active-goal.json" <<EOF
{"task_id":"t-999","session_id":"$GAME_SID","cwd":"$RG9","base_ref":"$BR9","criteria":["app.js exists"],"tests_required":["app.test.js"]}
EOF
assert_gated "registering a pre-existing path can't exempt its modification" "$(make_stop_input "$RG9")" "grader path"
rm -rf "$RG9"

# ── G10 (ADR-082 §5): a registered test WEAKENED after red registration → gate ─
# Closes the residual gap: a path in tests_required[] was skipped forever after
# registration (Added stays Added vs base_ref), so post-registration weakening was
# invisible. The content hash pinned at registration (tests_hashes) must catch it.
echo "Test G10 (ADR-082): weakening a registered test after hash-pinning trips the gate"
read -r RG10 BR10 <<< "$(make_goal_repo)"
fresh_presence
echo "test('real assertion', () => {})" > "$RG10/tests/new.test.js"
git -C "$RG10" add -A >/dev/null 2>&1; git -C "$RG10" commit -q -m "add red test" 2>/dev/null
PINNED=$(sha256sum "$RG10/tests/new.test.js" | cut -d' ' -f1)
echo "// weakened to a stub" > "$RG10/tests/new.test.js"   # builder guts the test post-registration
git -C "$RG10" add -A >/dev/null 2>&1; git -C "$RG10" commit -q -m "weaken" 2>/dev/null
cat > "$TMPDIR_TEST/.claude/run-state/active-goal.json" <<EOF
{"task_id":"t-999","session_id":"$GAME_SID","cwd":"$RG10","base_ref":"$BR10","criteria":["app.js exists"],"tests_required":["tests/new.test.js"],"tests_hashes":{"tests/new.test.js":"$PINNED"}}
EOF
assert_gated "weakened registered test trips hash gate" "$(make_stop_input "$RG10")" "hash"
rm -rf "$RG10"

# ── G12 (panel repair): registered path with NO hash entry → gate (fail-closed) ─
# A tests_required[] entry missing from tests_hashes kept the exact pre-ADR-082
# exemption (panel finding: channel 3 iterated tests_hashes, not tests_required).
echo "Test G12 (panel): registered-but-unhashed test trips the gate"
read -r RG12 BR12 <<< "$(make_goal_repo)"
fresh_presence
echo "test('unpinned', () => {})" > "$RG12/tests/new.test.js"
git -C "$RG12" add -A >/dev/null 2>&1; git -C "$RG12" commit -q -m "add test" 2>/dev/null
cat > "$TMPDIR_TEST/.claude/run-state/active-goal.json" <<EOF
{"task_id":"t-999","session_id":"$GAME_SID","cwd":"$RG12","base_ref":"$BR12","criteria":["app.js exists"],"tests_required":["tests/new.test.js"]}
EOF
assert_gated "registered path without pinned hash trips gate" "$(make_stop_input "$RG12")" "hash"
rm -rf "$RG12"

# ── G11 (control): registered test with MATCHING pinned hash still auto-completes ─
echo "Test G11 (control): untouched registered test with matching hash auto-completes"
read -r RG11 BR11 <<< "$(make_goal_repo)"
fresh_presence
echo "test('real assertion', () => {})" > "$RG11/tests/new.test.js"
git -C "$RG11" add -A >/dev/null 2>&1; git -C "$RG11" commit -q -m "add red test" 2>/dev/null
PIN11=$(sha256sum "$RG11/tests/new.test.js" | cut -d' ' -f1)
cat > "$TMPDIR_TEST/.claude/run-state/active-goal.json" <<EOF
{"task_id":"t-999","session_id":"$GAME_SID","cwd":"$RG11","base_ref":"$BR11","criteria":["app.js exists"],"tests_required":["tests/new.test.js"],"tests_hashes":{"tests/new.test.js":"$PIN11"}}
EOF
assert_completes "matching hash does not over-block" "$(make_stop_input "$RG11")"
rm -rf "$RG11"

# ── A1 (Option C audit, t-2218): per-criterion audit jsonl + registered_as_red ─
echo "Test A1 (audit): goal-completion emits per-criterion audit jsonl + registered_as_red"
read -r RA1 BR_A1 <<< "$(make_goal_repo)"
fresh_presence
rm -f "$TMPDIR_TEST/.claude/run-state/t-999-audit.jsonl"
echo "test('new', () => {})" > "$RA1/tests/new.test.js"
git -C "$RA1" add -A >/dev/null 2>&1; git -C "$RA1" commit -q -m "red" 2>/dev/null
cat > "$TMPDIR_TEST/.claude/run-state/active-goal.json" <<EOF
{"task_id":"t-999","session_id":"$GAME_SID","cwd":"$RA1","base_ref":"$BR_A1","criteria":["app.js exists"],"tests_required":["tests/new.test.js"]}
EOF
echo "$(make_stop_input "$RA1")" | bash "$HOOK" >/dev/null 2>&1
AUDIT="$TMPDIR_TEST/.claude/run-state/t-999-audit.jsonl"
TOTAL=$((TOTAL+1))
if [ -f "$AUDIT" ] && grep -q '"criterion"' "$AUDIT" && grep -q '"verdict":"pass"' "$AUDIT" && grep -q '"registered_as_red":true' "$AUDIT"; then
    echo "  PASS: audit jsonl has criterion verdict + registered_as_red"; PASS=$((PASS+1))
else
    echo "  FAIL: audit jsonl missing/incomplete — $(cat "$AUDIT" 2>/dev/null)"; FAIL=$((FAIL+1))
fi
rm -rf "$RA1"

# ── H9 (t-2206): "validate.sh passes" full-run heuristic ─────────────────────
# Reconcile's /goal done-signal is validate.sh exit 0 (full run, not a single check).
echo "Test H9a: 'validate.sh passes' with green validate.sh → auto-completes"
read -r RH9 BRH9 <<< "$(make_goal_repo)"
fresh_presence
printf '#!/usr/bin/env bash\nexit 0\n' > "$RH9/validate.sh"; chmod +x "$RH9/validate.sh"
write_goal "$RH9" "$BRH9" "validate.sh passes"
assert_completes "green validate.sh → criterion passes → auto-complete" "$(make_stop_input "$RH9")"
rm -rf "$RH9"

echo "Test H9b: 'validate.sh passes' with red validate.sh → NOT complete, surfaces failure"
read -r RH9B BRH9B <<< "$(make_goal_repo)"
fresh_presence
printf '#!/usr/bin/env bash\nexit 1\n' > "$RH9B/validate.sh"; chmod +x "$RH9B/validate.sh"
write_goal "$RH9B" "$BRH9B" "validate.sh passes"
TOTAL=$((TOTAL + 1))
OUT_H9B=$(echo "$(make_stop_input "$RH9B")" | bash "$HOOK" 2>/dev/null) || OUT_H9B=""
if echo "$OUT_H9B" | grep -qiF "Failed:" && ! echo "$OUT_H9B" | grep -qiE 'Goal complete|auto-marked completed'; then
    echo "  PASS: red validate.sh → not completed, failure surfaced"; PASS=$((PASS + 1))
else
    echo "  FAIL: red validate.sh handling — output: $OUT_H9B"; FAIL=$((FAIL + 1))
fi
rm -rf "$RH9B"

echo "Test H9c: 'validate.sh Check 18 passes' still routes to single-check heuristic (no regression)"
read -r RH9C BRH9C <<< "$(make_goal_repo)"
fresh_presence
# A validate.sh that fails the full run but the harness only asks for --check; prove H9 didn't
# swallow the check-N form. Here validate.sh exits 0 for any args, so check passes.
printf '#!/usr/bin/env bash\nexit 0\n' > "$RH9C/validate.sh"; chmod +x "$RH9C/validate.sh"
write_goal "$RH9C" "$BRH9C" "validate.sh Check 18 passes"
assert_completes "check-N form still grades (heuristic 3 precedence intact)" "$(make_stop_input "$RH9C")"
rm -rf "$RH9C"

# ── H10 (t-2856): "demoable: <command>" heuristic ────────────────────────────
# Pocock demoability (ac-grammar.md #10): the criterion names a command a human can
# run to watch the feature work. Auto-check runs it under the SAME allowlist as
# heuristic 7; a non-allowlisted command is NEVER executed → UNKNOWN (demo pending
# a human sitting).
echo "Test H10a: 'demoable: pytest' with green mocked pytest → auto-completes"
read -r RH10 BRH10 <<< "$(make_goal_repo)"
fresh_presence
mkdir -p "$TMPDIR_TEST/bin10"
printf '#!/usr/bin/env bash\nexit 0\n' > "$TMPDIR_TEST/bin10/pytest"; chmod +x "$TMPDIR_TEST/bin10/pytest"
OLD_PATH="$PATH"; export PATH="$TMPDIR_TEST/bin10:$PATH"
write_goal "$RH10" "$BRH10" "demoable: pytest"
assert_completes "green demoable command → criterion passes → auto-complete" "$(make_stop_input "$RH10")"
export PATH="$OLD_PATH"
rm -rf "$RH10"

echo "Test H10b: 'demoable: pytest' with red mocked pytest → NOT complete, failure surfaced"
read -r RH10B BRH10B <<< "$(make_goal_repo)"
fresh_presence
mkdir -p "$TMPDIR_TEST/bin10b"
printf '#!/usr/bin/env bash\nexit 1\n' > "$TMPDIR_TEST/bin10b/pytest"; chmod +x "$TMPDIR_TEST/bin10b/pytest"
OLD_PATH="$PATH"; export PATH="$TMPDIR_TEST/bin10b:$PATH"
write_goal "$RH10B" "$BRH10B" "demoable: pytest"
TOTAL=$((TOTAL + 1))
OUT_H10B=$(echo "$(make_stop_input "$RH10B")" | bash "$HOOK" 2>/dev/null) || OUT_H10B=""
if echo "$OUT_H10B" | grep -qiF "Failed:" && ! echo "$OUT_H10B" | grep -qiE 'Goal complete|auto-marked completed'; then
    echo "  PASS: red demoable command → not completed, failure surfaced"; PASS=$((PASS + 1))
else
    echo "  FAIL: red demoable handling — output: $OUT_H10B"; FAIL=$((FAIL + 1))
fi
export PATH="$OLD_PATH"
rm -rf "$RH10B"

echo "Test H10c: 'demoable: <non-allowlisted>' → UNKNOWN, never executed"
read -r RH10C BRH10C <<< "$(make_goal_repo)"
fresh_presence
rm -f "$TMPDIR_TEST/.claude/run-state/t-999-audit.jsonl"
CANARY="$TMPDIR_TEST/h10-canary"
write_goal "$RH10C" "$BRH10C" "demoable: touch $CANARY"
TOTAL=$((TOTAL + 1))
OUT_H10C=$(echo "$(make_stop_input "$RH10C")" | bash "$HOOK" 2>/dev/null) || OUT_H10C=""
AUD10="$TMPDIR_TEST/.claude/run-state/t-999-audit.jsonl"
if [ ! -f "$CANARY" ] && ! echo "$OUT_H10C" | grep -qiE 'Goal complete|auto-marked completed' \
   && grep -q '"verdict":"unknown"' "$AUD10" 2>/dev/null; then
    echo "  PASS: non-allowlisted demoable → unknown, never executed"; PASS=$((PASS + 1))
else
    echo "  FAIL: non-allowlisted demoable — canary=$([ -f "$CANARY" ] && echo executed) output: $OUT_H10C"; FAIL=$((FAIL + 1))
fi
rm -rf "$RH10C"

# ── Injection hardening (t-2856 challenger finding 1): allowlist is prefix-anchored,
# so "pytest; <anything>" matched and reached eval. Commands containing shell
# metacharacters must fall to UNKNOWN — never executed — for BOTH H7 and H10.
echo "Test INJ-H7: '\"pytest; touch canary\" passes' → UNKNOWN, never executed"
read -r RINJ BRINJ <<< "$(make_goal_repo)"
fresh_presence
mkdir -p "$TMPDIR_TEST/bininj"
printf '#!/usr/bin/env bash\nexit 0\n' > "$TMPDIR_TEST/bininj/pytest"; chmod +x "$TMPDIR_TEST/bininj/pytest"
OLD_PATH="$PATH"; export PATH="$TMPDIR_TEST/bininj:$PATH"
CANARY7="$TMPDIR_TEST/inj-canary-h7"
write_goal "$RINJ" "$BRINJ" "\\\"pytest; touch $CANARY7\\\" passes"
TOTAL=$((TOTAL + 1))
OUT_INJ7=$(echo "$(make_stop_input "$RINJ")" | bash "$HOOK" 2>/dev/null) || OUT_INJ7=""
if [ ! -f "$CANARY7" ] && ! echo "$OUT_INJ7" | grep -qiE 'Goal complete|auto-marked completed'; then
    echo "  PASS: H7 metachar command never executed, not completed"; PASS=$((PASS + 1))
else
    echo "  FAIL: H7 injection — canary=$([ -f "$CANARY7" ] && echo executed) output: $OUT_INJ7"; FAIL=$((FAIL + 1))
fi
export PATH="$OLD_PATH"
rm -rf "$RINJ"

echo "Test INJ-H10: 'demoable: pytest && touch canary' → UNKNOWN, never executed"
read -r RINJB BRINJB <<< "$(make_goal_repo)"
fresh_presence
export PATH="$TMPDIR_TEST/bininj:$PATH"
CANARY10="$TMPDIR_TEST/inj-canary-h10"
write_goal "$RINJB" "$BRINJB" "demoable: pytest && touch $CANARY10"
TOTAL=$((TOTAL + 1))
OUT_INJ10=$(echo "$(make_stop_input "$RINJB")" | bash "$HOOK" 2>/dev/null) || OUT_INJ10=""
if [ ! -f "$CANARY10" ] && ! echo "$OUT_INJ10" | grep -qiE 'Goal complete|auto-marked completed'; then
    echo "  PASS: H10 metachar command never executed, not completed"; PASS=$((PASS + 1))
else
    echo "  FAIL: H10 injection — canary=$([ -f "$CANARY10" ] && echo executed) output: $OUT_INJ10"; FAIL=$((FAIL + 1))
fi
export PATH="$OLD_PATH"
rm -rf "$RINJB"

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "Results: $PASS/$TOTAL passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
