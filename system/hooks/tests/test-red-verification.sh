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

# ── Test 10: leaked GIT_DIR/GIT_INDEX_FILE must not let a staged test's own git-fixture
# ops (git init/commit in a mktemp dir) redirect onto the real repo (t-2602). Git hooks
# export GIT_DIR/GIT_INDEX_FILE for their own process; those env vars win over `-C`/cwd,
# so a staged test that builds a throwaway git fixture silently commits onto the repo
# invoking the hook instead — see pattern_git-hook-env-leaks-into-executed-tests. ─────────
echo "Test 10: staged test's fixture git ops isolated from leaked GIT_DIR"
reset_repo
REPO_HEAD_BEFORE=$(git -C "$REPO" rev-parse HEAD)

cat > "$REPO/tests/test-fixture-hijack.sh" <<'EOS'
#!/usr/bin/env bash
set -e
FIX=$(mktemp -d)
git init -q "$FIX"
git -C "$FIX" config user.email f@f.local
git -C "$FIX" config user.name fixture
git -C "$FIX" commit -q --allow-empty -m "fixture: should stay in FIX, not REPO"
exit 1
EOS
git -C "$REPO" add tests/test-fixture-hijack.sh
write_goal

# Simulate a real pre-commit invocation: GIT_DIR/GIT_INDEX_FILE exported for the hook's
# own process, exactly as git sets them for every hook it runs.
(
  cd "$REPO" &&
  export GIT_DIR="$REPO/.git" GIT_INDEX_FILE="$REPO/.git/index" &&
  BRANA_GOAL_FILE="$GOAL" bash "$HOOK"
) >/dev/null 2>&1

REPO_HEAD_AFTER=$(git -C "$REPO" rev-parse HEAD)
if [ "$REPO_HEAD_AFTER" = "$REPO_HEAD_BEFORE" ]; then
    ok "repo HEAD unchanged — staged test's fixture git ops stayed in its own mktemp dir"
else
    bad "repo HEAD changed ($REPO_HEAD_BEFORE -> $REPO_HEAD_AFTER) — GIT_DIR leaked into the staged test and hijacked the real repo"
fi

# ── Test 11: registration pins a content hash (tests_hashes parallel map, ADR-082 §5) ─
# tests_required[] stays a plain string array (all existing consumers untouched);
# the hash lands in the SIBLING key tests_hashes{path: sha256-of-staged-blob}.
echo "Test 11: red registration writes tests_hashes[path] = staged-blob sha256"
reset_repo
printf '#!/usr/bin/env bash\nexit 1\n' > "$REPO/tests/test-red.sh"
git -C "$REPO" add tests/test-red.sh
EXPECTED_HASH=$(git -C "$REPO" show ":tests/test-red.sh" | sha256sum | cut -d' ' -f1)
write_goal
run_hook
GOT_HASH=$(jq -r '.tests_hashes["tests/test-red.sh"] // ""' "$GOAL" 2>/dev/null)
if [ -n "$GOT_HASH" ] && [ "$GOT_HASH" = "$EXPECTED_HASH" ]; then
    ok "tests_hashes carries the staged-blob sha256"
else
    bad "tests_hashes missing/wrong — expected $EXPECTED_HASH, got [${GOT_HASH:-<empty>}]"
fi
# tests_required must remain a plain string array (schema untouched)
T=$(jq -r '.tests_required[0] | type' "$GOAL" 2>/dev/null)
if [ "$T" = "string" ]; then ok "tests_required[] still a string array"; else bad "tests_required[] type drifted to [$T]"; fi

# ── Test 12: green (unregistered) test gets no hash entry ─────────────────────
echo "Test 12: unregistered test → no tests_hashes entry"
reset_repo
printf '#!/usr/bin/env bash\nexit 0\n' > "$REPO/tests/test-green.sh"
git -C "$REPO" add tests/test-green.sh
write_goal
run_hook
H=$(jq -r '.tests_hashes["tests/test-green.sh"] // ""' "$GOAL" 2>/dev/null)
if [ -z "$H" ]; then ok "no hash pinned for unregistered test"; else bad "hash pinned for green test"; fi

# ── Test 13 (panel repair): red re-commit of a registered path RE-PINS the hash ─
# Without re-pinning, an edit after registration gates forever with no recovery
# path (registration skipped registered paths entirely). Redness re-earns the pin.
echo "Test 13: registered path, new staged content, still red → hash re-pinned"
reset_repo
printf '#!/usr/bin/env bash\nexit 1\n' > "$REPO/tests/test-red.sh"
git -C "$REPO" add tests/test-red.sh
write_goal
run_hook
H1=$(jq -r '.tests_hashes["tests/test-red.sh"]' "$GOAL")
printf '#!/usr/bin/env bash\n# stronger assertion\nexit 1\n' > "$REPO/tests/test-red.sh"
git -C "$REPO" add tests/test-red.sh
EXPECT2=$(git -C "$REPO" show ":tests/test-red.sh" | sha256sum | cut -d' ' -f1)
run_hook
H2=$(jq -r '.tests_hashes["tests/test-red.sh"]' "$GOAL")
if [ "$H2" = "$EXPECT2" ] && [ "$H2" != "$H1" ]; then
    ok "hash re-pinned to the new red blob"
else
    bad "hash not re-pinned — H1=$H1 H2=$H2 expected=$EXPECT2"
fi
L=$(req_len)
if [ "$L" = "1" ]; then ok "tests_required still has exactly one entry (no dup)"; else bad "expected 1 entry, got $L"; fi
# and a GREEN re-stage of a registered path must NOT re-pin (redness not re-earned)
printf '#!/usr/bin/env bash\nexit 0\n' > "$REPO/tests/test-red.sh"
git -C "$REPO" add tests/test-red.sh
run_hook
H3=$(jq -r '.tests_hashes["tests/test-red.sh"]' "$GOAL")
if [ "$H3" = "$H2" ]; then ok "green re-stage does not re-pin"; else bad "green re-stage re-pinned ($H2 -> $H3)"; fi

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo "Results: $PASS/$TOTAL passed, $FAIL failed."
[ "$FAIL" -eq 0 ]
