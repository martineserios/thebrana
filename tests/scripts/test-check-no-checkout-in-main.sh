#!/usr/bin/env bash
# Tests for system/scripts/check-no-checkout-in-main.sh (validate.sh Check 74, ADR-094 d5, t-3327).
#
# Must-fire discipline: a detector without a test that proves it fires is a detector that
# rots silently (pattern_detector-needs-a-must-fire-test). Cases:
#   1. a shell command line `git checkout main` in a skill  → FAIL
#   2. a printed hint `println!("  git checkout dev")`       → FAIL
#   3. prose mentioning `git checkout main` in backticks     → OK (not a command line)
#   4. `git worktree add ../x main` and lines naming worktree → OK (sanctioned alternative)
#   5. the live repo                                        → OK (regression guard for the real surface)
set -uo pipefail

PASS=0; FAIL=0
assert_true() {
    local desc="$1" cond="$2"
    if [ "$cond" = "true" ]; then echo "  PASS: $desc"; PASS=$((PASS + 1)); else echo "  FAIL: $desc"; FAIL=$((FAIL + 1)); fi
}

REPO_ROOT=$(git rev-parse --show-toplevel)
CHECK="$REPO_ROOT/system/scripts/check-no-checkout-in-main.sh"
[ -f "$CHECK" ] || { echo "ERROR: $CHECK missing"; exit 1; }

echo "=== check-no-checkout-in-main.sh ==="

mk_fixture() {   # $1 = fixture root
    mkdir -p "$1/system/skills/x" "$1/system/rules" "$1/system/cli/rust/crates/brana-cli/src"
}

# 1. shell command line in a skill must fire
F1=$(mktemp -d); mk_fixture "$F1"
printf '%s\n' '```bash' 'git fetch origin' 'git checkout main' '```' > "$F1/system/skills/x/SKILL.md"
bash "$CHECK" "$F1" >/dev/null 2>&1; rc=$?
assert_true "fires on a 'git checkout main' command line in a skill" "$([ $rc -ne 0 ] && echo true || echo false)"
OUT=$(bash "$CHECK" "$F1" 2>&1)
assert_true "names the offending file:line" "$(echo "$OUT" | grep -q 'system/skills/x/SKILL.md:3:' && echo true || echo false)"
rm -rf "$F1"

# 2. printed hint (string literal) must fire
F2=$(mktemp -d); mk_fixture "$F2"
printf '%s\n' 'fn main() {' '    println!("  git checkout dev             # back");' '}' > "$F2/system/cli/rust/crates/brana-cli/src/main.rs"
bash "$CHECK" "$F2" >/dev/null 2>&1; rc=$?
assert_true "fires on a printed 'git checkout dev' hint in main.rs" "$([ $rc -ne 0 ] && echo true || echo false)"
rm -rf "$F2"

# 3. prose in backticks must NOT fire
F3=$(mktemp -d); mk_fixture "$F3"
printf '%s\n' 'Never run `git checkout main` in the shared checkout (ADR-094).' > "$F3/system/rules/git-discipline.md"
bash "$CHECK" "$F3" >/dev/null 2>&1; rc=$?
assert_true "does not fire on prose that mentions the command in backticks" "$([ $rc -eq 0 ] && echo true || echo false)"
rm -rf "$F3"

# 4. worktree lines must NOT fire
F4=$(mktemp -d); mk_fixture "$F4"
printf '%s\n' '```bash' 'git worktree add ../thebrana-main main' 'git checkout dev   # inside the worktree, not the main checkout' '```' > "$F4/system/skills/x/SKILL.md"
bash "$CHECK" "$F4" >/dev/null 2>&1; rc=$?
assert_true "exempts lines that name the worktree alternative" "$([ $rc -eq 0 ] && echo true || echo false)"
rm -rf "$F4"

# 5. the live repo must be clean
bash "$CHECK" "$REPO_ROOT" >/tmp/check74-live.log 2>&1; rc=$?
assert_true "live repo surface is clean (see /tmp/check74-live.log on failure)" "$([ $rc -eq 0 ] && echo true || echo false)"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
