#!/usr/bin/env bash
# Tests for system/scripts/check-private-state-untracked.sh (validate.sh Check 75, t-3352).
#
# Must-fire discipline (pattern_detector-needs-a-must-fire-test): a detector with no
# test proving it fires rots silently. thebrana is PUBLIC; system/state/portfolio.md and
# tasks-portfolio.json hold private client data and must stay untracked AND gitignored
# (ignored, so a blanket `git add system/state/` can never re-publish them).
#   1. a fixture that TRACKS portfolio.md                 -> FAIL
#   2. a fixture that tracks tasks-portfolio.json         -> FAIL
#   3. both untracked but NOT gitignored                  -> FAIL (auto-commit could re-add)
#   4. both untracked and gitignored                      -> OK
#   5. tracked AND gitignored (ignore does not untrack)   -> FAIL
#   6. the live repo                                      -> OK (regression guard)
set -uo pipefail

PASS=0; FAIL=0
assert_true() {
    local desc="$1" cond="$2"
    if [ "$cond" = "true" ]; then echo "  PASS: $desc"; PASS=$((PASS + 1)); else echo "  FAIL: $desc"; FAIL=$((FAIL + 1)); fi
}

REPO_ROOT=$(git rev-parse --show-toplevel)
CHECK="$REPO_ROOT/system/scripts/check-private-state-untracked.sh"
[ -f "$CHECK" ] || { echo "ERROR: $CHECK missing"; exit 1; }

echo "=== check-private-state-untracked.sh ==="

mk_fixture() {   # $1 = root; $2 = space-separated files to track; $3 = "ignore" to add .gitignore
    git init -q "$1"
    mkdir -p "$1/system/state"
    echo "x" > "$1/system/state/portfolio.md"
    echo "{}" > "$1/system/state/tasks-portfolio.json"
    if [ "${3:-}" = "ignore" ]; then
        printf '%s\n' 'system/state/portfolio.md' 'system/state/tasks-portfolio.json' > "$1/.gitignore"
    fi
    for f in $2; do git -C "$1" add -f "system/state/$f"; done
}
run() { bash "$CHECK" "$1" >/dev/null 2>&1; }

F1=$(mktemp -d); mk_fixture "$F1" "portfolio.md" ignore
run "$F1"; rc=$?
assert_true "fires when portfolio.md is tracked" "$([ $rc -ne 0 ] && echo true || echo false)"
OUT=$(bash "$CHECK" "$F1" 2>&1)
assert_true "names the tracked file" "$(echo "$OUT" | grep -q 'portfolio.md' && echo true || echo false)"
rm -rf "$F1"

F2=$(mktemp -d); mk_fixture "$F2" "tasks-portfolio.json" ignore
run "$F2"; rc=$?
assert_true "fires when tasks-portfolio.json is tracked" "$([ $rc -ne 0 ] && echo true || echo false)"
rm -rf "$F2"

F3=$(mktemp -d); mk_fixture "$F3" "" ""
run "$F3"; rc=$?
assert_true "fires when untracked but not gitignored" "$([ $rc -ne 0 ] && echo true || echo false)"
rm -rf "$F3"

F4=$(mktemp -d); mk_fixture "$F4" "" ignore
run "$F4"; rc=$?
assert_true "passes when untracked and gitignored" "$([ $rc -eq 0 ] && echo true || echo false)"
rm -rf "$F4"

F5=$(mktemp -d); mk_fixture "$F5" "portfolio.md tasks-portfolio.json" ignore
run "$F5"; rc=$?
assert_true "fires when tracked even though gitignored" "$([ $rc -ne 0 ] && echo true || echo false)"
rm -rf "$F5"

# 6. ignored only via .git/info/exclude protects THIS clone only — another clone (or the
#    CI checkout) has no such rule, so it must not count as "gitignored" (t-3352 review).
F6=$(mktemp -d); mk_fixture "$F6" "" ""
printf '%s\n' 'system/state/portfolio.md' 'system/state/tasks-portfolio.json' >> "$F6/.git/info/exclude"
run "$F6"; rc=$?
assert_true "fires when ignored only via .git/info/exclude (not in .gitignore)" "$([ $rc -ne 0 ] && echo true || echo false)"
rm -rf "$F6"

# 7. a later negation ('!path') re-includes the file: git then does NOT ignore it, but
#    `check-ignore -v` still prints the matching rule. Must fire (Gate 3 security review).
F7=$(mktemp -d); mk_fixture "$F7" "" ignore
printf '%s\n' '!system/state/portfolio.md' >> "$F7/.gitignore"
run "$F7"; rc=$?
assert_true "fires when a negation re-includes portfolio.md" "$([ $rc -ne 0 ] && echo true || echo false)"
rm -rf "$F7"

run "$REPO_ROOT"; rc=$?
assert_true "live repo passes" "$([ $rc -eq 0 ] && echo true || echo false)"

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
