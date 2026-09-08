#!/usr/bin/env bash
# Tests: ADR-094 decision 2 — explicit, idempotent migration that refuses ambiguity
# (t-3323, RED until t-3324 lands).
#
#   A. populated <common-root>/.claude/tasks.json (+ .lock sidecar), no .git/brana ledger:
#      the first brana call MOVES both (rename — same inode) into <git-common-dir>/brana/,
#      reports the same count, and leaves a non-JSON MOVED marker at the old path.
#      A second call is a no-op (same inode, marker unchanged).
#   B. both present and different: brana refuses, prints both paths and both counts,
#      moves nothing, exits non-zero.
#   C. a repo that still git-tracks .claude/tasks.json is left exactly as-is
#      (portfolio scope: no .git/brana, no marker).
#
# Expected to FAIL today: no migration exists; the resolver reads .claude/tasks.json.

set -uo pipefail

TDD_RED_UNTIL=t-3324
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_tdd-red.sh
source "$SCRIPT_DIR/_tdd-red.sh"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

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
export HOME="$TMP/home"; mkdir -p "$HOME"
unset CLAUDE_PROJECT_DIR GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR

ledger_json() {   # $1 = task count
    local n="$1" i items=""
    for ((i = 1; i <= n; i++)); do items="$items${items:+,}{\"id\":\"t-$i\",\"subject\":\"s$i\"}"; done
    printf '{"version":3,"tasks":[%s]}\n' "$items"
}
untracked_repo() {   # ledger path ignored on main, no ledger file present
    local r="$1"
    mkdir -p "$r/.claude"
    git -C "$r" init -q -b main
    git -C "$r" config user.email t@t; git -C "$r" config user.name t
    git -C "$r" config core.hooksPath /dev/null
    echo '.claude/tasks.json' > "$r/.gitignore"
    git -C "$r" add -A && git -C "$r" commit -qm init
}
count() { ( cd "$1" && "$BRANA" backlog stats 2>/dev/null | jq -r '.total // empty' ); }
common_dir() { git -C "$1" rev-parse --path-format=absolute --git-common-dir; }
inode() { stat -c %i "$1" 2>/dev/null; }

echo "ADR-094 — migration of the ledger into <git-common-dir>/brana/"
echo "==============================================================="

echo ""
echo "--- A. move once, with the .lock sidecar, leaving a MOVED marker (d2) ---"
R="$TMP/a"; untracked_repo "$R"
ledger_json 5 > "$R/.claude/tasks.json"; : > "$R/.claude/tasks.json.lock"
OLD_INODE=$(inode "$R/.claude/tasks.json")
COMMON="$(common_dir "$R")"
check "first brana call reports the 5 migrated tasks" "$([ "$(count "$R")" = "5" ] && echo 0 || echo 1)" "count=$(count "$R")"
check "ledger now lives at <git-common-dir>/brana/tasks.json" "$([ -f "$COMMON/brana/tasks.json" ] && echo 0 || echo 1)"
check "it was MOVED (rename), not copied — same inode" "$([ "$(inode "$COMMON/brana/tasks.json")" = "$OLD_INODE" ] && echo 0 || echo 1)" \
    "old=$OLD_INODE new=$(inode "$COMMON/brana/tasks.json")"
check "the .lock sidecar moved with it" "$([ -e "$COMMON/brana/tasks.json.lock" ] && [ ! -e "$R/.claude/tasks.json.lock" ] && echo 0 || echo 1)"
check "a MOVED marker (not JSON) sits at the old path" \
    "$([ -f "$R/.claude/tasks.json" ] && head -c 5 "$R/.claude/tasks.json" | grep -q '^MOVED' && ! jq -e . "$R/.claude/tasks.json" >/dev/null 2>&1 && echo 0 || echo 1)"
MARKER_BEFORE=$(cat "$R/.claude/tasks.json" 2>/dev/null)
NEW_INODE=$(inode "$COMMON/brana/tasks.json")
check "second call is a no-op: same count, same inode, marker unchanged" \
    "$([ "$(count "$R")" = "5" ] && [ "$(inode "$COMMON/brana/tasks.json")" = "$NEW_INODE" ] && [ "$(cat "$R/.claude/tasks.json" 2>/dev/null)" = "$MARKER_BEFORE" ] && echo 0 || echo 1)"

echo ""
echo "--- B. both present and different: refuse, print both, move nothing (d2) ---"
R="$TMP/b"; untracked_repo "$R"
COMMON="$(common_dir "$R")"; mkdir -p "$COMMON/brana"
ledger_json 5 > "$R/.claude/tasks.json"
ledger_json 7 > "$COMMON/brana/tasks.json"
OUT=$( cd "$R" && "$BRANA" backlog stats 2>&1 ); RC=$?
check "brana exits non-zero instead of choosing silently" "$([ "$RC" -ne 0 ] && echo 0 || echo 1)" "rc=$RC out=$OUT"
check "message names both paths" "$(echo "$OUT" | grep -q '\.claude/tasks\.json' && echo "$OUT" | grep -q 'brana/tasks\.json' && echo 0 || echo 1)" "$OUT"
check "message carries both counts (5 and 7)" "$(echo "$OUT" | grep -qw 5 && echo "$OUT" | grep -qw 7 && echo 0 || echo 1)" "$OUT"
check "legacy file untouched (still 5 tasks, still JSON)" "$([ "$(jq '.tasks|length' "$R/.claude/tasks.json" 2>/dev/null)" = "5" ] && echo 0 || echo 1)"
check "canonical file untouched (still 7 tasks)" "$([ "$(jq '.tasks|length' "$COMMON/brana/tasks.json" 2>/dev/null)" = "7" ] && echo 0 || echo 1)"

echo ""
echo "--- C. a repo that still tracks its ledger is left exactly as-is (d1 portfolio scope) ---"
R="$TMP/c"; mkdir -p "$R/.claude"
git -C "$R" init -q -b main; git -C "$R" config user.email t@t; git -C "$R" config user.name t; git -C "$R" config core.hooksPath /dev/null
ledger_json 3 > "$R/.claude/tasks.json"
git -C "$R" add -A && git -C "$R" commit -qm "tracked ledger"
COMMON="$(common_dir "$R")"
check "brana reads the tracked ledger (3)" "$([ "$(count "$R")" = "3" ] && echo 0 || echo 1)" "count=$(count "$R")"
check "no .git/brana/ was created" "$([ ! -e "$COMMON/brana" ] && echo 0 || echo 1)"
check "tracked file still clean in git (no marker, no rewrite)" "$([ -z "$(git -C "$R" status --porcelain)" ] && echo 0 || echo 1)" "$(git -C "$R" status --porcelain)"

echo ""
echo "Results: $PASS passed, $FAIL failed, $TOTAL total"
tdd_red_exit "$FAIL"
