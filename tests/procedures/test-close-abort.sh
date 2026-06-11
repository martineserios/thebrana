#!/usr/bin/env bash
# Tests for system/scripts/close-abort.sh — the --abort orientation sequence
# (t-1986/t-1987, ADR-053 §4).
#
# Contract pinned here:
#   close-abort.sh --task-id t-NNN --reason "..." [--dirty stash|reset|leave]
#                  [--git-root DIR] [--no-task-update]
#   1. Reason required → exit 2 when missing
#   2. Refuses to abort main/master → exit 2
#   3. Dirty tree without --dirty decision → exit 2 (never a silent default)
#   4. Tag aborted/{branch-basename}-{YYYYMMDD} created; collision → time suffix
#   5. Tag pushed; push failure → loud "LOCAL ONLY" warning on stderr, exit 0
#   6. Checks out main BEFORE git branch -D (abort from the branch itself works)
#
# Run: bash tests/procedures/test-close-abort.sh

set -uo pipefail

PASS=0
FAIL=0
TOTAL=0

assert() {
    local desc="$1" cond="$2"
    TOTAL=$((TOTAL + 1))
    if eval "$cond"; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc (condition: $cond)"
        FAIL=$((FAIL + 1))
    fi
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ABORT="$SCRIPT_DIR/../../system/scripts/close-abort.sh"
if [ ! -f "$ABORT" ]; then
    echo "FAIL: $ABORT does not exist"
    exit 1
fi

WORK=$(mktemp -d /tmp/close-abort-test.XXXXXX)
trap 'rm -rf "$WORK"' EXIT

# Repo factory: main with one commit, feature branch checked out with one commit.
# $1 = repo dir name, $2 = "remote" to wire a file:// bare remote (push succeeds)
make_repo() {
    local dir="$WORK/$1" remote="${2:-}"
    git init -q -b main "$dir"
    git -C "$dir" -c user.email=t@t -c user.name=t commit -q --allow-empty -m "root"
    git -C "$dir" checkout -q -b async-close/feat/t-9999-abort-me
    echo "work" > "$dir/file.txt"
    git -C "$dir" add file.txt
    git -C "$dir" -c user.email=t@t -c user.name=t commit -q -m "feature work"
    if [ "$remote" = "remote" ]; then
        git init -q --bare "$WORK/$1-remote.git"
        git -C "$dir" remote add origin "$WORK/$1-remote.git"
    fi
    echo "$dir"
}

run_abort() {
    # $1 = repo, then extra args. Always --no-task-update (no backlog in tests).
    local repo="$1"; shift
    bash "$ABORT" --git-root "$repo" --no-task-update "$@"
}

TODAY=$(date +%Y%m%d)

echo "=== test-close-abort.sh ==="

echo ""
echo "Reason required"
R=$(make_repo r1 remote)
run_abort "$R" --task-id t-9999 >/dev/null 2>&1
assert "missing --reason → exit 2" "[ $? -eq 2 ]"
run_abort "$R" --task-id t-9999 --reason "" >/dev/null 2>&1
assert "empty --reason → exit 2" "[ $? -eq 2 ]"
assert "branch untouched after refused abort" \
    "git -C '$R' rev-parse --verify -q async-close/feat/t-9999-abort-me >/dev/null"

echo ""
echo "Happy path: clean tree, remote present"
OUT=$(run_abort "$R" --task-id t-9999 --reason "approach invalidated" 2>&1)
RC=$?
assert "exit 0" "[ $RC -eq 0 ]"
assert "tag aborted/t-9999-abort-me-$TODAY exists" \
    "git -C '$R' tag -l 'aborted/t-9999-abort-me-$TODAY' | grep -q ."
assert "branch deleted" \
    "! git -C '$R' rev-parse --verify -q async-close/feat/t-9999-abort-me >/dev/null"
assert "HEAD on main" "[ \"\$(git -C '$R' branch --show-current)\" = main ]"
assert "tag pushed to remote" \
    "git -C '$WORK/r1-remote.git' tag -l 'aborted/t-9999-abort-me-*' | grep -q ."
assert "no local-only warning when push succeeds" \
    "! echo \"$OUT\" | grep -qi 'local.only'"

echo ""
echo "Push failure → loud warning, still exit 0"
R2=$(make_repo r2)   # no remote
OUT=$(run_abort "$R2" --task-id t-9999 --reason "no remote here" 2>&1)
RC=$?
assert "exit 0 despite push failure" "[ $RC -eq 0 ]"
assert "stderr warns LOCAL ONLY" "echo \"$OUT\" | grep -qi 'local.only'"
assert "tag still created locally" \
    "git -C '$R2' tag -l 'aborted/t-9999-abort-me-*' | grep -q ."

echo ""
echo "Dirty tree: decision required, no silent default"
R3=$(make_repo r3 remote)
echo "uncommitted" >> "$R3/file.txt"
run_abort "$R3" --task-id t-9999 --reason "dirty no decision" >/dev/null 2>&1
assert "dirty + no --dirty → exit 2" "[ $? -eq 2 ]"
assert "tree still dirty (nothing touched)" \
    "[ -n \"\$(git -C '$R3' status --porcelain)\" ]"
assert "branch still exists" \
    "git -C '$R3' rev-parse --verify -q async-close/feat/t-9999-abort-me >/dev/null"

echo ""
echo "Dirty tree: --dirty stash"
OUT=$(run_abort "$R3" --task-id t-9999 --reason "stash it" --dirty stash 2>&1)
assert "exit 0" "[ $? -eq 0 ]"
assert "stash created with abort marker" \
    "git -C '$R3' stash list | grep -qi 'abort'"
assert "branch deleted after stash" \
    "! git -C '$R3' rev-parse --verify -q async-close/feat/t-9999-abort-me >/dev/null"

echo ""
echo "Dirty tree: --dirty reset"
R4=$(make_repo r4 remote)
echo "doomed change" >> "$R4/file.txt"
run_abort "$R4" --task-id t-9999 --reason "reset it" --dirty reset >/dev/null 2>&1
assert "exit 0" "[ $? -eq 0 ]"
assert "working tree clean after reset" \
    "[ -z \"\$(git -C '$R4' status --porcelain)\" ]"
assert "branch deleted after reset" \
    "! git -C '$R4' rev-parse --verify -q async-close/feat/t-9999-abort-me >/dev/null"

echo ""
echo "Dirty tree: --dirty leave"
R5=$(make_repo r5 remote)
echo "keep me visible" >> "$R5/file.txt"
OUT=$(run_abort "$R5" --task-id t-9999 --reason "leave it" --dirty leave 2>&1)
assert "exit 0" "[ $? -eq 0 ]"
assert "warns about dirty tree" "echo \"$OUT\" | grep -qi 'dirty'"
assert "changes carried over (still dirty)" \
    "[ -n \"\$(git -C '$R5' status --porcelain)\" ]"
assert "branch deleted with changes left" \
    "! git -C '$R5' rev-parse --verify -q async-close/feat/t-9999-abort-me >/dev/null"

echo ""
echo "Tag collision: re-abort same branch same day"
R6=$(make_repo r6 remote)
git -C "$R6" tag "aborted/t-9999-abort-me-$TODAY"   # simulate earlier abort today
run_abort "$R6" --task-id t-9999 --reason "second abort" >/dev/null 2>&1
assert "exit 0 on collision" "[ $? -eq 0 ]"
N=$(git -C "$R6" tag -l "aborted/t-9999-abort-me-$TODAY*" | wc -l | tr -d ' ')
assert "second tag created with suffix (count >= 2)" "[ $N -ge 2 ]"

echo ""
echo "Refuses to abort main"
R7=$(make_repo r7 remote)
git -C "$R7" checkout -q main
run_abort "$R7" --task-id t-9999 --reason "abort main itself" >/dev/null 2>&1
assert "abort on main → exit 2" "[ $? -eq 2 ]"

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="

[ "$FAIL" -eq 0 ] || exit 1
