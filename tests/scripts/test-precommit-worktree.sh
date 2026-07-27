#!/usr/bin/env bash
# Regression tests for the pre-commit hook in linked worktrees (t-2468).
#
# In a linked worktree `.git` is a FILE (a gitdir pointer), not a directory.
# The hook resolved its commit-message source as the literal `.git/COMMIT_EDITMSG`
# and did `exit 0` when that was missing — so in EVERY worktree it abandoned the
# whole hook before reaching the secret scan, the context-budget gate and the
# red-verification registration (t-2216, ADR-061 Stage 2).
#
# git-discipline.md mandates worktrees for all branch work, so this silently
# disabled all four gates for every feature commit. ADR-061 and build-loop.md
# meanwhile both documented the registration gate as active.
#
# Coverage:
#   - the hook resolves COMMIT_EDITMSG via git rev-parse --git-path
#   - the hook does not `exit 0` merely because .git is not a directory
#   - red-verification is reached and registers a red test from a worktree commit
#   - attribution blocking still works (no regression in the original purpose)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HOOK="$REPO_ROOT/system/scripts/git-hooks/pre-commit"

PASS=0; FAIL=0; TOTAL=0
ok()  { PASS=$((PASS+1)); TOTAL=$((TOTAL+1)); echo "  PASS: $1"; }
bad() { FAIL=$((FAIL+1)); TOTAL=$((TOTAL+1)); echo "  FAIL: $1"; }

echo "=== pre-commit hook in linked worktrees (t-2468) ==="

# 1. Static: must not hard-code the non-worktree-safe path.
if grep -q 'git rev-parse --git-path COMMIT_EDITMSG' "$HOOK"; then
    ok "hook resolves COMMIT_EDITMSG via git rev-parse --git-path"
else
    bad "hook does not use git rev-parse --git-path — breaks in worktrees"
fi

if grep -qE '^\s*elif \[ -f "\.git/COMMIT_EDITMSG" \]' "$HOOK"; then
    bad "hook still hard-codes .git/COMMIT_EDITMSG (a FILE in worktrees)"
else
    ok "hook no longer hard-codes .git/COMMIT_EDITMSG"
fi

# 2. Behavioural: real repo + real linked worktree.
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
MAIN="$TMP/main"
git init -q "$MAIN"
git -C "$MAIN" config user.email t@t; git -C "$MAIN" config user.name t
git -C "$MAIN" config commit.gpgsign false
mkdir -p "$MAIN/tests/scripts"
echo seed > "$MAIN/seed.txt"
git -C "$MAIN" add seed.txt
git -C "$MAIN" -c core.hooksPath=/dev/null commit -q -m "seed"

# Install the hook under test as BOTH pre-commit and commit-msg. commit-msg is
# required for the attribution check: at pre-commit time git has not yet written
# the new COMMIT_EDITMSG (it still holds the PREVIOUS commit's message), so only
# commit-msg — which receives the real message file as $1 — can see it.
HOOKDIR="$TMP/hooks"; mkdir -p "$HOOKDIR"
cp "$HOOK" "$HOOKDIR/pre-commit";  chmod +x "$HOOKDIR/pre-commit"
cp "$HOOK" "$HOOKDIR/commit-msg";  chmod +x "$HOOKDIR/commit-msg"
git -C "$MAIN" config core.hooksPath "$HOOKDIR"

# The hook prefers $HOME/.claude/hooks/red-verification.sh and falls back to the
# repo's own system/hooks/. The fixture repo has no system/ tree, so provide the
# deployed-copy path explicitly.
FAKEHOME="$TMP/home"; mkdir -p "$FAKEHOME/.claude/hooks"
cp "$REPO_ROOT/system/hooks/red-verification.sh" "$FAKEHOME/.claude/hooks/"
chmod +x "$FAKEHOME/.claude/hooks/red-verification.sh"

WT="$TMP/wt"
git -C "$MAIN" worktree add -q "$WT" -b feat/probe 2>/dev/null

TOTAL=$((TOTAL+1))
if [ -f "$WT/.git" ]; then
    PASS=$((PASS+1)); echo "  PASS: linked worktree has .git as a FILE (precondition)"
else
    FAIL=$((FAIL+1)); echo "  FAIL: worktree precondition not met — .git is not a file"
fi

# 3. Red test committed FROM THE WORKTREE must register.
GOAL="$TMP/goal.json"
printf '{"cwd":"%s","tests_required":[]}\n' "$WT" > "$GOAL"
mkdir -p "$WT/tests/scripts"
printf '#!/usr/bin/env bash\nexit 1\n' > "$WT/tests/scripts/red-probe.sh"
chmod +x "$WT/tests/scripts/red-probe.sh"
git -C "$WT" add tests/scripts/red-probe.sh
HOME="$FAKEHOME" BRANA_GOAL_FILE="$GOAL" \
    git -C "$WT" commit -q -m "test: red probe" >/dev/null 2>&1

if grep -q 'red-probe.sh' "$GOAL" 2>/dev/null; then
    ok "red test committed from a worktree registers into tests_required[]"
else
    bad "red test from a worktree did NOT register — hook exited early"
    echo "        goal: $(cat "$GOAL")"
fi

# 3b. The REAL thebrana configuration: pre-commit installed, commit-msg NOT.
#     Without commit-msg there is no $1, so the hook falls back to resolving
#     COMMIT_EDITMSG itself — which is exactly where the worktree bug bites.
#     With commit-msg present (case 3) the $1 path masks the defect entirely,
#     so this case is the one that actually pins the regression.
HOOKDIR2="$TMP/hooks-precommit-only"; mkdir -p "$HOOKDIR2"
cp "$HOOK" "$HOOKDIR2/pre-commit"; chmod +x "$HOOKDIR2/pre-commit"
git -C "$MAIN" config core.hooksPath "$HOOKDIR2"

GOAL2="$TMP/goal2.json"
printf '{"cwd":"%s","tests_required":[]}\n' "$WT" > "$GOAL2"
printf '#!/usr/bin/env bash\nexit 1\n' > "$WT/tests/scripts/red-probe-b.sh"
chmod +x "$WT/tests/scripts/red-probe-b.sh"
git -C "$WT" add tests/scripts/red-probe-b.sh
HOME="$FAKEHOME" BRANA_GOAL_FILE="$GOAL2" \
    git -C "$WT" commit -q -m "test: red probe b" >/dev/null 2>&1

if grep -q 'red-probe-b.sh' "$GOAL2" 2>/dev/null; then
    ok "red test registers with pre-commit ONLY (no commit-msg) in a worktree"
else
    bad "pre-commit-only worktree commit did NOT register — hook exited early"
    echo "        goal: $(cat "$GOAL2")"
fi

# Restore the both-hooks config for the remaining case.
git -C "$MAIN" config core.hooksPath "$HOOKDIR"

# 4. No regression: attribution trailer still blocks, from a worktree.
echo change >> "$WT/seed.txt"
git -C "$WT" add seed.txt
if HOME="$FAKEHOME" git -C "$WT" commit -q -m "feat: x

Co-Authored-By: someone <a@b.c>" >/dev/null 2>&1; then
    bad "attribution trailer was NOT blocked from a worktree"
else
    ok "attribution trailer still blocked from a worktree"
fi

echo ""
echo "Total: $TOTAL  Passed: $PASS  Failed: $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
