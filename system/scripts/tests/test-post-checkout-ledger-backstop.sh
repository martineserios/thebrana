#!/usr/bin/env bash
# Tests: ADR-094 decision 6 — the post-checkout / post-merge backstop
# (t-3323, RED until t-3328 lands).
#
# Hook under test: system/scripts/git-hooks/post-checkout — the same file is installed
# under BOTH hook names (a fast-forward merge fires post-merge only; verified on git
# 2.53.0, 2026-09-08). It runs in a scratch repo whose ledger already lives at
# <git-common-dir>/brana/tasks.json with one backup in <git-common-dir>/brana/backups/.
#
#   A. ledger missing after a HEAD change → restored from the newest backup, banner
#      names the ref transition, exit non-zero (post-checkout argv: <old> <new> 1).
#   B. ledger collapsed (>50% drop vs the newest backup) → restored, exit non-zero
#      (post-merge argv: <squash-flag>).
#   C. intact ledger → exit 0, no output.
#   D. out of scope (repo still git-tracks .claude/tasks.json, no .git/brana) → exit 0,
#      no output, nothing created — the guard that keeps a global core.hooksPath from
#      firing in portfolio repos.
#   E. runs in under 100 ms on a 3000-task ledger.
#
# Expected to FAIL today: the hook does not exist.

set -uo pipefail

TDD_RED_UNTIL=t-3328
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_tdd-red.sh
source "$SCRIPT_DIR/_tdd-red.sh"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
HOOK="$REPO_ROOT/system/scripts/git-hooks/post-checkout"

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

echo "ADR-094 — post-checkout / post-merge ledger backstop"
echo "====================================================="
echo ""
check "hook exists and is executable at system/scripts/git-hooks/post-checkout" \
    "$([ -x "$HOOK" ] && echo 0 || echo 1)" "absent — RED until t-3328"
if [ ! -x "$HOOK" ]; then
    echo ""
    echo "Results: $PASS passed, $FAIL failed, $TOTAL total (remaining checks skipped — hook absent)"
    tdd_red_exit "$FAIL"
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"
unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR

ledger_json() {
    local n="$1" i items=""
    for ((i = 1; i <= n; i++)); do items="$items${items:+,}{\"id\":\"t-$i\"}"; done
    printf '{"version":3,"tasks":[%s]}\n' "$items"
}
# Repo with the path untracked, ledger + one backup under .git/brana/
scoped_repo() {
    local r="$1" n="$2" common
    mkdir -p "$r"
    git -C "$r" init -q -b main
    git -C "$r" config user.email t@t; git -C "$r" config user.name t
    git -C "$r" config core.hooksPath /dev/null
    echo '.claude/tasks.json' > "$r/.gitignore"
    git -C "$r" add -A && git -C "$r" commit -qm init
    common=$(git -C "$r" rev-parse --path-format=absolute --git-common-dir)
    mkdir -p "$common/brana/backups"
    ledger_json "$n" > "$common/brana/tasks.json"
    ledger_json "$n" > "$common/brana/backups/tasks.json.20260908T000000Z.json"
    echo "$common"
}
count() { jq '.tasks|length' "$1" 2>/dev/null; }
OLD=0000000000000000000000000000000000000000
NEW=1111111111111111111111111111111111111111

echo ""
echo "--- A. missing ledger → restored, banner, non-zero (post-checkout argv) ---"
R="$TMP/a"; C=$(scoped_repo "$R" 10)
rm -f "$C/brana/tasks.json"
OUT=$( cd "$R" && bash "$HOOK" "$OLD" "$NEW" 1 2>&1 ); RC=$?
check "exit non-zero" "$([ "$RC" -ne 0 ] && echo 0 || echo 1)" "rc=$RC"
check "ledger restored from the newest backup (10 tasks)" "$([ "$(count "$C/brana/tasks.json")" = "10" ] && echo 0 || echo 1)"
check "banner names the ref transition" "$(echo "$OUT" | grep -q "${OLD:0:7}" && echo "$OUT" | grep -q "${NEW:0:7}" && echo 0 || echo 1)" "$OUT"

echo ""
echo "--- B. collapsed ledger → restored, non-zero (post-merge argv) ---"
R="$TMP/b"; C=$(scoped_repo "$R" 10)
ledger_json 2 > "$C/brana/tasks.json"
OUT=$( cd "$R" && bash "$HOOK" 0 2>&1 ); RC=$?
check "exit non-zero" "$([ "$RC" -ne 0 ] && echo 0 || echo 1)" "rc=$RC"
check "ledger restored to the backup's 10 tasks" "$([ "$(count "$C/brana/tasks.json")" = "10" ] && echo 0 || echo 1)"
check "the collapsed file was kept aside, not lost (a pre-restore copy exists)" \
    "$(ls "$C/brana"/*pre-restore* "$C/brana/backups"/*pre-restore* 2>/dev/null | grep -q . && echo 0 || echo 1)"

echo ""
echo "--- C. intact ledger → silent exit 0 ---"
R="$TMP/c"; C=$(scoped_repo "$R" 10)
OUT=$( cd "$R" && bash "$HOOK" "$OLD" "$NEW" 1 2>&1 ); RC=$?
check "exit 0" "$([ "$RC" -eq 0 ] && echo 0 || echo 1)" "rc=$RC"
check "no output" "$([ -z "$OUT" ] && echo 0 || echo 1)" "$OUT"
check "ledger untouched" "$([ "$(count "$C/brana/tasks.json")" = "10" ] && echo 0 || echo 1)"

echo ""
echo "--- D. out of scope: repo tracks its ledger, no .git/brana → silent no-op ---"
R="$TMP/d"; mkdir -p "$R/.claude"
git -C "$R" init -q -b main; git -C "$R" config user.email t@t; git -C "$R" config user.name t; git -C "$R" config core.hooksPath /dev/null
ledger_json 3 > "$R/.claude/tasks.json"; git -C "$R" add -A && git -C "$R" commit -qm tracked
C=$(git -C "$R" rev-parse --path-format=absolute --git-common-dir)
OUT=$( cd "$R" && bash "$HOOK" "$OLD" "$NEW" 1 2>&1 ); RC=$?
check "exit 0" "$([ "$RC" -eq 0 ] && echo 0 || echo 1)" "rc=$RC"
check "no output" "$([ -z "$OUT" ] && echo 0 || echo 1)" "$OUT"
check "nothing created under .git/brana" "$([ ! -e "$C/brana" ] && echo 0 || echo 1)"

echo ""
echo "--- E. fast: under 100 ms on a 3000-task ledger ---"
R="$TMP/e"; C=$(scoped_repo "$R" 3000)
T0=$(date +%s%N); ( cd "$R" && bash "$HOOK" "$OLD" "$NEW" 1 >/dev/null 2>&1 ); T1=$(date +%s%N)
MS=$(( (T1 - T0) / 1000000 ))
check "hook completed in ${MS} ms (< 100)" "$([ "$MS" -lt 100 ] && echo 0 || echo 1)"

echo ""
echo "Results: $PASS passed, $FAIL failed, $TOTAL total"
tdd_red_exit "$FAIL"
