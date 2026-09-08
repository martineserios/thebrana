#!/usr/bin/env bash
# Tests: ADR-094 decisions 1 + 3 through the real `brana` binary in a scratch repo
# (t-3323, RED until t-3324 lands). Each block names the ADR decision it encodes.
#
#   A. the 2026-09-07 sequence, checkout half: with the ledger seeded by brana itself,
#      `git checkout <tracking-tag>` then back must leave the ledger intact.
#   B. the 2026-09-07 sequence, fast-forward half: `git checkout <tracking-branch>`
#      then `git merge --ff-only main` past the untracking commit — the exact step
#      that deleted the ledger — must leave it intact. (post-checkout never fires on
#      a ff-merge; only relocation protects here.)
#   C. brana run FROM INSIDE a linked worktree checked out at a tracking ref reads the
#      common-dir ledger, leaves the worktree's stale copy untouched, and the canonical
#      file is <git-common-dir>/brana/tasks.json (d1, gate anchored at the common root).
#   D. a missing ledger is an error naming the path and both remedies; nothing is
#      auto-created at either path (d3).
#
# Expected to FAIL today: the resolver still uses <common-root>/.claude/tasks.json,
# which git clobbers on checkout to any of the 145 refs that track it, and
# auto-creates {"tasks":[]} when the file is missing.

set -uo pipefail

TDD_RED_UNTIL=t-3324
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_tdd-red.sh
source "$SCRIPT_DIR/_tdd-red.sh"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

# Prefer this worktree's own build; fall back to the main checkout's (t-3286 pattern).
BRANA="$REPO_ROOT/system/cli/rust/target/release/brana"
if [ ! -x "$BRANA" ]; then
    COMMON_DIR=$(git -C "$REPO_ROOT" rev-parse --git-common-dir 2>/dev/null) || COMMON_DIR=""
    MAIN_CHECKOUT="$REPO_ROOT"
    [ -n "$COMMON_DIR" ] && MAIN_CHECKOUT="$(cd "$(dirname "$COMMON_DIR")" && pwd)"
    BRANA="$MAIN_CHECKOUT/system/cli/rust/target/release/brana"
fi
if [ ! -x "$BRANA" ]; then
    echo "SKIP: brana binary not built at $BRANA — run 'cargo build --release' first"
    exit 0
fi

PASS=0; FAIL=0; TOTAL=0
check() {
    local desc="$1" ok="$2" detail="${3:-}"
    TOTAL=$((TOTAL + 1))
    if [ "$ok" = "0" ]; then
        PASS=$((PASS + 1)); echo "  PASS: $desc"
    else
        FAIL=$((FAIL + 1)); echo "  FAIL: $desc${detail:+ — $detail}"
    fi
}

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"      # no global git hooks/config, no ~/.claude
unset CLAUDE_PROJECT_DIR GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR

# A repo that tracked .claude/tasks.json at tag v-old and on branch `pre`, then
# untracked it on main (rm --cached + .gitignore) — thebrana's topology after ADR-091.
make_repo() {
    local r="$1"
    mkdir -p "$r/.claude"
    git -C "$r" init -q -b main
    git -C "$r" config user.email t@t; git -C "$r" config user.name t
    git -C "$r" config core.hooksPath /dev/null
    echo '{"version":3,"tasks":[{"id":"t-1","subject":"stale"},{"id":"t-2","subject":"stale"},{"id":"t-3","subject":"stale"}]}' > "$r/.claude/tasks.json"
    git -C "$r" add -A && git -C "$r" commit -qm "track ledger"
    git -C "$r" tag v-old
    git -C "$r" branch pre
    git -C "$r" rm -q --cached .claude/tasks.json
    echo '.claude/tasks.json' > "$r/.gitignore"
    git -C "$r" add -A && git -C "$r" commit -qm "untrack ledger (ADR-091)"
    rm -f "$r/.claude/tasks.json"
}

# Seed 5 tasks through the binary so IT chooses the ledger location.
seed() {
    local r="$1" i
    for i in 1 2 3 4 5; do
        ( cd "$r" && "$BRANA" backlog add --subject "seed $i" >/dev/null 2>&1 ) || return 1
    done
}
count() { ( cd "$1" && "$BRANA" backlog stats 2>/dev/null | jq -r '.total // empty' ); }
common_dir() { git -C "$1" rev-parse --path-format=absolute --git-common-dir; }

echo "ADR-094 — ledger in <git-common-dir>/brana/ (via the brana binary)"
echo "======================================================================"

echo ""
echo "--- A. checkout to a tracking tag and back (d1: relocation) ---"
R="$TMP/a"; make_repo "$R"
if seed "$R"; then
    check "seeded 5 tasks" "$([ "$(count "$R")" = "5" ] && echo 0 || echo 1)" "count=$(count "$R")"
    git -C "$R" checkout -q v-old 2>/dev/null
    check "after checkout v-old the ledger still reports 5 (not the tag's stale 3)" \
        "$([ "$(count "$R")" = "5" ] && echo 0 || echo 1)" "count=$(count "$R")"
    git -C "$R" checkout -q main 2>/dev/null
    check "after checkout back to main the ledger still reports 5 (not auto-created 0)" \
        "$([ "$(count "$R")" = "5" ] && echo 0 || echo 1)" "count=$(count "$R")"
else
    check "seed via brana backlog add" 1 "binary refused to add — see stderr"
fi

echo ""
echo "--- B. checkout to a tracking branch, then ff-merge past the untracking commit ---"
R="$TMP/b"; make_repo "$R"
if seed "$R"; then
    git -C "$R" checkout -q pre 2>/dev/null
    check "after checkout pre (tracks the path) the ledger still reports 5" \
        "$([ "$(count "$R")" = "5" ] && echo 0 || echo 1)" "count=$(count "$R")"
    git -C "$R" merge -q --ff-only main 2>/dev/null
    check "after merge --ff-only past the untracking commit the ledger still reports 5 (the step that deleted it on 2026-09-07)" \
        "$([ "$(count "$R")" = "5" ] && echo 0 || echo 1)" "count=$(count "$R")"
else
    check "seed via brana backlog add" 1
fi

echo ""
echo "--- C. brana from inside a worktree at a tracking ref (d1: gate anchored at common root) ---"
R="$TMP/c"; make_repo "$R"
if seed "$R"; then
    CANON="$(common_dir "$R")/brana/tasks.json"
    check "canonical ledger exists at <git-common-dir>/brana/tasks.json" "$([ -f "$CANON" ] && echo 0 || echo 1)" "$CANON"
    WT="$TMP/c-wt"
    git -C "$R" worktree add -q "$WT" v-old 2>/dev/null
    check "fixture: the v-old worktree materialised a stale tracked copy" "$([ -f "$WT/.claude/tasks.json" ] && echo 0 || echo 1)"
    check "brana run inside the tracking-ref worktree reports the canonical 5, not the stale 3" \
        "$([ "$(count "$WT")" = "5" ] && echo 0 || echo 1)" "count=$(count "$WT")"
    check "the worktree's stale copy is untouched (never read, never rewritten)" \
        "$(grep -q '"stale"' "$WT/.claude/tasks.json" && [ "$(jq '.tasks|length' "$WT/.claude/tasks.json")" = "3" ] && echo 0 || echo 1)"
    check "no ledger was auto-created at the main checkout's legacy path" \
        "$([ ! -f "$R/.claude/tasks.json" ] || head -c 5 "$R/.claude/tasks.json" | grep -q '^MOVED' && echo 0 || echo 1)"
else
    check "seed via brana backlog add" 1
fi

echo ""
echo "--- D. missing ledger fails loud and creates nothing (d3) ---"
R="$TMP/d"; make_repo "$R"
COMMON="$(common_dir "$R")"
rm -f "$R/.claude/tasks.json" "$COMMON/brana/tasks.json"
OUT=$( cd "$R" && "$BRANA" backlog stats 2>&1 ); RC=$?
check "brana backlog stats exits non-zero when no ledger exists" "$([ "$RC" -ne 0 ] && echo 0 || echo 1)" "rc=$RC"
check "error names the canonical path" "$(echo "$OUT" | grep -q 'brana/tasks.json' && echo 0 || echo 1)" "$OUT"
check "error names the two remedies (backlog init / restore)" \
    "$(echo "$OUT" | grep -q 'backlog init' && echo "$OUT" | grep -qi 'restore' && echo 0 || echo 1)" "$OUT"
check "nothing was created at the legacy path" "$([ ! -e "$R/.claude/tasks.json" ] && echo 0 || echo 1)"
check "nothing was created at the canonical path" "$([ ! -e "$COMMON/brana/tasks.json" ] && echo 0 || echo 1)"

echo ""
echo "Results: $PASS passed, $FAIL failed, $TOTAL total"
tdd_red_exit "$FAIL"
