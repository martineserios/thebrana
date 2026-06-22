#!/usr/bin/env bash
# Tests for red-verification.sh — the pre-commit registration gate (t-2216, ADR-061 §4).
#
# The hook registers a newly-added staged test into active-goal.json.tests_required[]
# ONLY when the staged blob runs RED (exit != 0). Everything else (green stub,
# un-runnable fixture, wrong repo, no goal) is fail-closed: NOT registered.
#
# Each case builds a throwaway git repo + a temp active-goal.json (pointed at via
# BRANA_GOAL_FILE) and asserts the resulting tests_required[] membership.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/../red-verification.sh"
PASS=0
FAIL=0
TOTAL=0

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

REPO="$WORK/repo"
GOAL="$WORK/active-goal.json"

git init -q "$REPO"
git -C "$REPO" config user.email t@t.local
git -C "$REPO" config user.name tester
mkdir -p "$REPO/tests" "$REPO/tests/fixtures"
echo seed > "$REPO/seed.txt"
git -C "$REPO" add seed.txt
git -C "$REPO" commit -qm seed

# Reset the index to a clean post-seed state between cases.
reset_repo() {
    git -C "$REPO" reset -q --hard HEAD
    git -C "$REPO" clean -qfdx
    mkdir -p "$REPO/tests" "$REPO/tests/fixtures"
}

write_goal() { # $1 = cwd (default $REPO), $2 = tests_required JSON (default [])
    printf '{"task_id":"t-test","cwd":"%s","session_id":"sid","base_ref":"HEAD","criteria":["AC: x"],"tests_required":%s}\n' \
        "${1:-$REPO}" "${2:-[]}" > "$GOAL"
}

run_hook() { ( cd "$REPO" && BRANA_GOAL_FILE="$GOAL" bash "$HOOK" ) >/dev/null 2>&1; }

is_registered() { jq -e --arg p "$1" '(.tests_required // []) | index($p) != null' "$GOAL" >/dev/null 2>&1; }

req_len() { jq '(.tests_required // []) | length' "$GOAL" 2>/dev/null; }

ok()   { TOTAL=$((TOTAL+1)); echo "  PASS: $1"; PASS=$((PASS+1)); }
bad()  { TOTAL=$((TOTAL+1)); echo "  FAIL: $1"; FAIL=$((FAIL+1)); }
check(){ if [ "$1" -eq 0 ]; then ok "$2"; else bad "$2"; fi; }   # $1 = a command's exit status

# ── Test 1: RED staged test → registered (exempt) ────────────────────────────
echo "Test 1: red staged test → registered"
reset_repo
printf '#!/usr/bin/env bash\nexit 1\n' > "$REPO/tests/test-red.sh"
git -C "$REPO" add tests/test-red.sh
write_goal
run_hook
is_registered "tests/test-red.sh"; check $? "red test registered into tests_required[]"

# ── Test 2: GREEN staged test → NOT registered (blocked) ─────────────────────
echo "Test 2: green staged test → NOT registered"
reset_repo
printf '#!/usr/bin/env bash\nexit 0\n' > "$REPO/tests/test-green.sh"
git -C "$REPO" add tests/test-green.sh
write_goal
run_hook
if is_registered "tests/test-green.sh"; then bad "green test wrongly registered"; else ok "green test left unregistered (grader blocks)"; fi

# ── Test 3: no active-goal.json → silent no-op, never errors ──────────────────
echo "Test 3: no goal file → no-op"
reset_repo
rm -f "$GOAL"
printf '#!/usr/bin/env bash\nexit 1\n' > "$REPO/tests/test-red.sh"
git -C "$REPO" add tests/test-red.sh
if ( cd "$REPO" && BRANA_GOAL_FILE="$GOAL" bash "$HOOK" ) >/dev/null 2>&1; then ok "exit 0 with no goal file"; else bad "errored with no goal file"; fi

# ── Test 4: goal owned by a different repo → no-op ───────────────────────────
echo "Test 4: cwd mismatch → no-op"
reset_repo
printf '#!/usr/bin/env bash\nexit 1\n' > "$REPO/tests/test-red.sh"
git -C "$REPO" add tests/test-red.sh
write_goal "/some/other/repo"
run_hook
if is_registered "tests/test-red.sh"; then bad "registered despite cwd mismatch"; else ok "cwd mismatch → not registered"; fi

# ── Test 5: idempotent — running twice does not duplicate ────────────────────
echo "Test 5: idempotent registration"
reset_repo
printf '#!/usr/bin/env bash\nexit 1\n' > "$REPO/tests/test-red.sh"
git -C "$REPO" add tests/test-red.sh
write_goal
run_hook
run_hook
L=$(req_len)
if [ "$L" = "1" ]; then ok "tests_required has exactly one entry after two runs"; else bad "expected 1 entry, got $L"; fi

# ── Test 6: non-test path (no grader-regex match) → ignored even if red ───────
echo "Test 6: non-test path red → ignored"
reset_repo
printf '#!/usr/bin/env bash\nexit 1\n' > "$REPO/build.sh"
git -C "$REPO" add build.sh
write_goal
run_hook
if is_registered "build.sh"; then bad "non-test path wrongly registered"; else ok "non-test path ignored"; fi

# ── Test 7: staged-blob semantics — stage GREEN, worktree RED → NOT registered ─
# Proves the hook grades the STAGED blob, not the working tree (closes the
# stage-green / worktree-red gaming hole).
echo "Test 7: staged blob graded, not working tree"
reset_repo
printf '#!/usr/bin/env bash\nexit 0\n' > "$REPO/tests/test-swap.sh"
git -C "$REPO" add tests/test-swap.sh
printf '#!/usr/bin/env bash\nexit 1\n' > "$REPO/tests/test-swap.sh"   # worktree now RED, unstaged
write_goal
run_hook
if is_registered "tests/test-swap.sh"; then bad "graded working tree (red) instead of staged blob (green)"; else ok "graded staged blob (green) → not registered"; fi

# ── Test 8: un-runnable fixture matching tests/ → fail-closed, not registered ─
echo "Test 8: injected fixture → fail-closed"
reset_repo
printf '{"data": 1}\n' > "$REPO/tests/fixtures/data.json"
git -C "$REPO" add tests/fixtures/data.json
write_goal
run_hook
if is_registered "tests/fixtures/data.json"; then bad "un-runnable fixture wrongly registered"; else ok "un-runnable fixture left blocked"; fi

# ── Test 9: modified (not added) pre-existing test → not registered ──────────
# Only newly-Added tests are registration candidates; Modified grader paths are
# always blocked by goal-completion.sh, so the hook must not touch them.
echo "Test 9: modified pre-existing test → not registered"
reset_repo
printf '#!/usr/bin/env bash\nexit 0\n' > "$REPO/tests/test-existing.sh"
git -C "$REPO" add tests/test-existing.sh
git -C "$REPO" commit -qm "add existing test"
printf '#!/usr/bin/env bash\nexit 1\n' > "$REPO/tests/test-existing.sh"   # now red, staged-modified
git -C "$REPO" add tests/test-existing.sh
write_goal
run_hook
if is_registered "tests/test-existing.sh"; then bad "modified pre-existing test wrongly registered"; else ok "modified test not registered (Added-only)"; fi

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo "Results: $PASS/$TOTAL passed, $FAIL failed."
[ "$FAIL" -eq 0 ]
