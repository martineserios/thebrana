#!/usr/bin/env bash
# Tests for worktree-gate.sh (PreToolUse hook for Bash)
# Gates git checkout -b when worktree should be used instead.
#
# Two enforcement scenarios:
#   1. Uncommitted changes exist → deny checkout -b, suggest worktree
#   2. Other worktrees active on same repo → deny checkout -b, suggest worktree
#
# Also tests task ID lock mechanism (shared across worktrees).

set -euo pipefail

HOOK="$(cd "$(dirname "$0")/../../system/hooks" && pwd)/worktree-gate.sh"
LOCK_SCRIPT="$(cd "$(dirname "$0")/../../system/scripts" && pwd)/task-id-lock.sh"
PASS=0
FAIL=0
TOTAL=0

assert_continue() {
    local desc="$1" input="$2"
    TOTAL=$((TOTAL + 1))
    local result
    result=$(echo "$input" | bash "$HOOK" 2>/dev/null) || true
    if echo "$result" | jq -e '.continue == true' >/dev/null 2>&1; then
        PASS=$((PASS + 1))
        echo "  PASS: $desc"
    else
        FAIL=$((FAIL + 1))
        echo "  FAIL: $desc — expected continue, got: $result"
    fi
}

assert_deny() {
    local desc="$1" input="$2"
    TOTAL=$((TOTAL + 1))
    local result
    result=$(echo "$input" | bash "$HOOK" 2>/dev/null) || true
    if echo "$result" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null 2>&1; then
        PASS=$((PASS + 1))
        echo "  PASS: $desc"
    else
        FAIL=$((FAIL + 1))
        echo "  FAIL: $desc — expected deny, got: $result"
    fi
}

assert_reason_contains() {
    local desc="$1" input="$2" pattern="$3"
    TOTAL=$((TOTAL + 1))
    local result reason
    result=$(echo "$input" | bash "$HOOK" 2>/dev/null) || true
    reason=$(echo "$result" | jq -r '.hookSpecificOutput.permissionDecisionReason // empty' 2>/dev/null)
    if echo "$reason" | grep -qi "$pattern"; then
        PASS=$((PASS + 1))
        echo "  PASS: $desc"
    else
        FAIL=$((FAIL + 1))
        echo "  FAIL: $desc — pattern '$pattern' not in reason: $reason"
    fi
}

# --- Setup test repos ---
TMPDIR=$(mktemp -d)
trap "rm -rf '$TMPDIR'" EXIT

git init "$TMPDIR/repo" >/dev/null 2>&1
cd "$TMPDIR/repo"
git checkout -b main >/dev/null 2>&1
echo "init" > file.txt
git add file.txt && git commit -m "init" >/dev/null 2>&1

CWD="$TMPDIR/repo"

make_input() {
    local cmd="$1" cwd="${2:-$CWD}"
    printf '{"tool_name":"Bash","tool_input":{"command":"%s"},"cwd":"%s"}' "$cmd" "$cwd"
}

echo "=== 1. Non-Bash tools: pass through ==="

TOTAL=$((TOTAL + 1))
result=$(echo '{"tool_name":"Write","tool_input":{"file_path":"/tmp/x"},"cwd":"'"$CWD"'"}' | bash "$HOOK" 2>/dev/null) || true
if echo "$result" | jq -e '.continue == true' >/dev/null 2>&1; then
    PASS=$((PASS + 1)); echo "  PASS: Write tool passes through"
else
    FAIL=$((FAIL + 1)); echo "  FAIL: Write tool — got: $result"
fi

echo ""
echo "=== 2. Non-checkout Bash commands: pass through ==="

assert_continue "git status" "$(make_input 'git status')"
assert_continue "git diff" "$(make_input 'git diff HEAD')"
assert_continue "git log" "$(make_input 'git log --oneline')"
assert_continue "git worktree add" "$(make_input 'git worktree add ../foo -b feat/bar')"
assert_continue "ls -la" "$(make_input 'ls -la')"
assert_continue "git checkout (no -b)" "$(make_input 'git checkout main')"

echo ""
echo "=== 3. git checkout -b with clean state, no other worktrees: pass through ==="

assert_continue "checkout -b on clean repo" "$(make_input 'git checkout -b feat/clean')"

echo ""
echo "=== 4. git checkout -b with dirty working tree: deny ==="

echo "dirty" >> "$TMPDIR/repo/file.txt"

assert_deny "checkout -b with uncommitted changes" "$(make_input 'git checkout -b feat/dirty')"
assert_reason_contains "reason mentions worktree" "$(make_input 'git checkout -b feat/dirty')" "worktree"

# Staged but uncommitted
git add file.txt 2>/dev/null
assert_deny "checkout -b with staged changes" "$(make_input 'git checkout -b feat/staged')"

# Reset
git checkout -- file.txt 2>/dev/null || git restore file.txt 2>/dev/null

echo ""
echo "=== 5. git checkout -b with active worktrees: deny ==="

git worktree add "$TMPDIR/wt1" -b feat/other-session >/dev/null 2>&1

assert_deny "checkout -b with active worktree" "$(make_input 'git checkout -b feat/collision')"
assert_reason_contains "reason mentions existing worktree" "$(make_input 'git checkout -b feat/collision')" "worktree"

git worktree remove "$TMPDIR/wt1" 2>/dev/null || true

echo ""
echo "=== 6. git switch -c (alternative syntax): deny when dirty ==="

echo "dirty" >> "$TMPDIR/repo/file.txt"
assert_deny "switch -c with uncommitted changes" "$(make_input 'git switch -c feat/switch-dirty')"
git checkout -- file.txt 2>/dev/null || git restore file.txt 2>/dev/null

echo ""
echo "=== 7. Chained commands containing checkout -b: deny when dirty ==="

echo "dirty" >> "$TMPDIR/repo/file.txt"
assert_deny "chained checkout -b" "$(make_input 'git add . && git checkout -b feat/chained')"
git checkout -- file.txt 2>/dev/null || git restore file.txt 2>/dev/null

echo ""
echo "=== 8. Non-git directory: pass through ==="

NOGIT=$(mktemp -d)
assert_continue "checkout -b in non-git dir" "$(make_input 'git checkout -b feat/nogit' "$NOGIT")"
rm -rf "$NOGIT"

echo ""
echo "=== 9. Task ID lock (if lock script exists) ==="

if [ -f "$LOCK_SCRIPT" ]; then
    # Setup tasks.json in test repo
    mkdir -p "$TMPDIR/repo/.claude"
    echo '{"next_id": {"t": 100}, "tasks": []}' > "$TMPDIR/repo/.claude/tasks.json"

    # Get two IDs — they must be different
    ID1=$(bash "$LOCK_SCRIPT" next-id "$TMPDIR/repo" "t" 2>/dev/null)
    ID2=$(bash "$LOCK_SCRIPT" next-id "$TMPDIR/repo" "t" 2>/dev/null)

    TOTAL=$((TOTAL + 1))
    if [ "$ID1" != "$ID2" ]; then
        PASS=$((PASS + 1)); echo "  PASS: sequential IDs are unique ($ID1 != $ID2)"
    else
        FAIL=$((FAIL + 1)); echo "  FAIL: sequential IDs collided ($ID1 == $ID2)"
    fi

    # Parallel ID generation — 5 concurrent calls
    TOTAL=$((TOTAL + 1))
    for i in $(seq 1 5); do
        bash "$LOCK_SCRIPT" next-id "$TMPDIR/repo" "t" > "$TMPDIR/id-$i" 2>/dev/null &
    done
    wait

    ALL_IDS=$(cat "$TMPDIR"/id-* | sort)
    UNIQUE_IDS=$(echo "$ALL_IDS" | sort -u)
    if [ "$ALL_IDS" = "$UNIQUE_IDS" ]; then
        PASS=$((PASS + 1)); echo "  PASS: 5 parallel IDs all unique"
    else
        FAIL=$((FAIL + 1)); echo "  FAIL: parallel ID collision: $(cat "$TMPDIR"/id-*)"
    fi

    # Worktree gets correct ID from shared state
    TOTAL=$((TOTAL + 1))
    git -C "$TMPDIR/repo" worktree add "$TMPDIR/wt-lock" -b feat/lock-test >/dev/null 2>&1
    cp "$TMPDIR/repo/.claude/tasks.json" "$TMPDIR/wt-lock/.claude/tasks.json" 2>/dev/null || true
    ID_MAIN=$(bash "$LOCK_SCRIPT" next-id "$TMPDIR/repo" "t" 2>/dev/null)
    ID_WT=$(bash "$LOCK_SCRIPT" next-id "$TMPDIR/wt-lock" "t" 2>/dev/null)
    if [ "$ID_MAIN" != "$ID_WT" ]; then
        PASS=$((PASS + 1)); echo "  PASS: main and worktree IDs differ ($ID_MAIN != $ID_WT)"
    else
        FAIL=$((FAIL + 1)); echo "  FAIL: main and worktree got same ID ($ID_MAIN)"
    fi
    git -C "$TMPDIR/repo" worktree remove "$TMPDIR/wt-lock" 2>/dev/null || true
else
    echo "  SKIP: $LOCK_SCRIPT not found"
fi

echo ""
echo "=== Results ==="
echo "$PASS/$TOTAL passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
