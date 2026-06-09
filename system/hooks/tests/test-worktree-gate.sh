#!/usr/bin/env bash
# Tests for worktree-gate.sh
# Covers: checkout/switch detection, false-positive prevention, error messages.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/../worktree-gate.sh"
PASS=0; FAIL=0; TOTAL=0
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# ── Helpers ──────────────────────────────────────────────────

make_input() {
    local cmd="$1"
    local cwd="${2:-$TMPDIR/repo}"
    jq -n --arg cmd "$cmd" --arg cwd "$cwd" \
        '{tool_name:"Bash",tool_input:{command:$cmd},cwd:$cwd,session_id:"test-session"}'
}

run_hook() {
    echo "$1" | bash "$HOOK" 2>/dev/null
}

assert_pass() {
    local desc="$1" input="$2"
    TOTAL=$((TOTAL + 1))
    local out
    out=$(run_hook "$input")
    if echo "$out" | jq -e '.continue == true' >/dev/null 2>&1 && \
       ! echo "$out" | jq -e '.permissionDecision == "deny"' >/dev/null 2>&1; then
        echo "  PASS: $desc"; PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc (expected pass, got: $out)"; FAIL=$((FAIL + 1))
    fi
}

assert_deny() {
    local desc="$1" input="$2"
    TOTAL=$((TOTAL + 1))
    local out
    out=$(run_hook "$input")
    if echo "$out" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null 2>&1; then
        echo "  PASS: $desc"; PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc (expected deny, got: $out)"; FAIL=$((FAIL + 1))
    fi
}

assert_deny_msg_contains() {
    local desc="$1" input="$2" needle="$3"
    TOTAL=$((TOTAL + 1))
    local out
    out=$(run_hook "$input")
    local msg
    msg=$(echo "$out" | jq -r '.hookSpecificOutput.permissionDecisionReason // ""' 2>/dev/null)
    if echo "$out" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null 2>&1 && \
       echo "$msg" | grep -qF "$needle"; then
        echo "  PASS: $desc"; PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc"
        echo "    expected message to contain: [$needle]"
        echo "    got message: [$msg]"
        FAIL=$((FAIL + 1))
    fi
}

# ── Setup: dirty repo ────────────────────────────────────────

setup_dirty_repo() {
    local suffix="${1:-dirty-repo}"
    local repo="$TMPDIR/$suffix"
    git init -q "$repo" 2>/dev/null
    git -C "$repo" config user.email "test@test.com" 2>/dev/null
    git -C "$repo" config user.name "Test" 2>/dev/null
    # Track a file first, then modify it — makes git diff --quiet fail
    echo "original" > "$repo/tracked.txt"
    git -C "$repo" add tracked.txt 2>/dev/null
    git -C "$repo" commit -q -m "init" 2>/dev/null
    echo "modified" > "$repo/tracked.txt"  # unstaged change to tracked file
    echo "$repo"
}

setup_clean_repo() {
    local repo="$TMPDIR/clean-repo"
    git init -q "$repo" 2>/dev/null
    git -C "$repo" config user.email "test@test.com" 2>/dev/null
    git -C "$repo" config user.name "Test" 2>/dev/null
    git -C "$repo" commit --allow-empty -q -m "init" 2>/dev/null
    echo "$repo"
}

echo "worktree-gate.sh Tests"
echo "======================"

# ──────────────────────────────────────────────────────────────
echo ""
echo "── False-positive prevention (t-1120) ──────────────────"
# ──────────────────────────────────────────────────────────────

CLEAN_REPO=$(setup_clean_repo)
DIRTY_REPO=$(setup_dirty_repo "dirty-repo-a")

# T1: "git switch -c" inside a JSON string arg on DIRTY repo must NOT deny
# This was the false-positive: brana backlog add with description mentioning "git switch -c"
# would trigger the worktree gate on a dirty repo, blocking unrelated CLI operations.
T1_CMD='brana backlog add --json '"'"'{"description": "fix git switch -c behavior in hooks"}'"'"
assert_pass "T1: 'git switch -c' inside JSON arg on dirty repo is NOT denied" \
    "$(make_input "$T1_CMD" "$DIRTY_REPO")"

# T2: "git checkout -b" inside a quoted echo arg on dirty repo must NOT deny
T2_CMD="echo 'remember to use git checkout -b for branches'"
assert_pass "T2: 'git checkout -b' inside echo string on dirty repo is NOT denied" \
    "$(make_input "$T2_CMD" "$DIRTY_REPO")"

# T3: actual "git switch -c feat/foo" on clean repo passes through (allowed)
T3_CMD="git switch -c feat/foo"
assert_pass "T3: actual git switch -c on clean repo passes" \
    "$(make_input "$T3_CMD" "$CLEAN_REPO")"

# T4: actual "git checkout -b feat/bar" on clean repo passes through (allowed)
T4_CMD="git checkout -b feat/bar"
assert_pass "T4: actual git checkout -b on clean repo passes" \
    "$(make_input "$T4_CMD" "$CLEAN_REPO")"

# T5: actual git switch -c after && on dirty repo IS denied (real command, not string arg)
DIRTY_REPO2=$(setup_dirty_repo "dirty-repo-b")
T5_CMD="cd /some/path && git switch -c feat/baz"
assert_deny "T5: actual git switch -c after && on dirty repo is denied" \
    "$(make_input "$T5_CMD" "$DIRTY_REPO2")"

# ──────────────────────────────────────────────────────────────
echo ""
echo "── Error message accuracy (t-1126) ─────────────────────"
# ──────────────────────────────────────────────────────────────

DIRTY_REPO3=$(setup_dirty_repo "dirty-repo-c")

# T6: git switch -c on dirty repo → error message says "git switch -c" not "git checkout -b"
T6_CMD="git switch -c feat/myfeature"
assert_deny_msg_contains "T6: git switch -c error mentions 'git switch -c'" \
    "$(make_input "$T6_CMD" "$DIRTY_REPO3")" "git switch -c"

# T7: git switch -c on dirty repo → error message does NOT say "git checkout -b"
T7_OUT=$(run_hook "$(make_input "git switch -c feat/other" "$DIRTY_REPO3")")
T7_MSG=$(echo "$T7_OUT" | jq -r '.hookSpecificOutput.permissionDecisionReason // ""' 2>/dev/null)
TOTAL=$((TOTAL + 1))
if echo "$T7_MSG" | grep -qF "git checkout -b"; then
    echo "  FAIL: T7: git switch -c error should not mention 'git checkout -b'"
    echo "    got: $T7_MSG"
    FAIL=$((FAIL + 1))
else
    echo "  PASS: T7: git switch -c error does not say 'git checkout -b'"; PASS=$((PASS + 1))
fi

# T8: git checkout -b on dirty repo → error message mentions "git checkout -b"
DIRTY_REPO4=$(setup_dirty_repo "dirty-repo-d")
assert_deny_msg_contains "T8: git checkout -b error mentions 'git checkout -b'" \
    "$(make_input "git checkout -b feat/checkoutfeat" "$DIRTY_REPO4")" "git checkout -b"

# ──────────────────────────────────────────────────────────────
echo ""
echo "── Baseline: non-git commands pass through ─────────────"
# ──────────────────────────────────────────────────────────────

# T9: plain bash command not involving git passes through
assert_pass "T9: ls command passes through" \
    "$(make_input "ls -la" "$CLEAN_REPO")"

# T10: git commit passes through gate A (no dirty/disk check triggered artificially)
assert_pass "T10: git commit on clean repo passes worktree gate" \
    "$(make_input "git commit -m 'test'" "$CLEAN_REPO")"

# ──────────────────────────────────────────────────────────────
echo ""
echo "── IS_STASH passthrough (t-1928) ────────────────────────"
# Regression: compound commands containing 'git stash' must pass through on a
# dirty repo — the user is explicitly handling dirty state inline. Tests the
# IS_STASH branch added in t-1927 (lines 171-174 of worktree-gate.sh).
# ──────────────────────────────────────────────────────────────

DIRTY_REPO5=$(setup_dirty_repo "dirty-repo-e")

# T11: git stash && git checkout -b on dirty repo → allowed (IS_STASH=true)
assert_pass "T11: 'git stash && git checkout -b' on dirty repo passes (IS_STASH)" \
    "$(make_input "git stash && git checkout -b feat/new-feature" "$DIRTY_REPO5")"

# T12: git stash push -u && git checkout -b on dirty repo → allowed
assert_pass "T12: 'git stash push -u && git checkout -b' on dirty repo passes (IS_STASH)" \
    "$(make_input "git stash push -u && git checkout -b fix/t-123-quick-fix" "$DIRTY_REPO5")"

# ──────────────────────────────────────────────────────────────
echo ""
echo "── Results ──────────────────────────────────────────────"
echo "  Total: $TOTAL  Pass: $PASS  Fail: $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
echo "PASSED"
