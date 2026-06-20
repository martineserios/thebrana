#!/usr/bin/env bash
# test-autonomous-runner-invariants.sh — ADR-060 safety invariants for the autonomous runner (t-2150).
# One test per load-bearing property of the worktree model (t-2146) + the run-batch lock (t-2144).
# Hermetic: temp git repo + stub claude. These guard the properties that make autonomy safe to
# point at a real repo — they must hold even under adversarial conditions (detached HEAD, dirty
# live tree, a concurrent batch).
set -u

RUNNER_SRC="$(git rev-parse --show-toplevel 2>/dev/null)/system/scripts/autonomous-runner.sh"
[ -f "$RUNNER_SRC" ] || { echo "FAIL: runner not found"; exit 1; }

PASS=0; FAIL=0
ok(){ if eval "$2"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "  ✗ $1"; fi; }
led_count(){ jq -r "select(.decision==\"$2\")|.id" "$1" 2>/dev/null | wc -l | tr -d ' '; }

# Stub claude: plan AUTODOABLE; dispatch writes a RELATIVE target.txt (inside the worktree cwd).
STUBDIR="$(mktemp -d /tmp/runner-inv-stub-XXXXXX)"; STUB="$STUBDIR/claude"
cat > "$STUB" <<'STUBEOF'
#!/usr/bin/env bash
prompt="$(cat)"
if printf '%s' "$prompt" | grep -q "PLANNING step"; then echo "AUTODOABLE: ok"; exit 0; fi
printf 'the\n' > target.txt; echo "DONE: fixed the typo"
exit 0
STUBEOF
chmod +x "$STUB"

make_repo(){
  local d; d="$(mktemp -d /tmp/runner-inv-repo-XXXXXX)"
  ( cd "$d"
    git init -q; git config user.email t@t; git config user.name t; git config commit.gpgsign false
    printf 'teh\n' > target.txt
    printf '#!/usr/bin/env bash\nexit 0\n' > validate.sh; chmod +x validate.sh
    git add -A; git commit -q -m init
  ); echo "$d"
}
FIX1(){ cat > "$1" <<EOF
[{"id":"t-9001","subject":"Fix typo","status":"pending","execution":"autonomous","priority":"P3","blocked_by":[]}]
EOF
}
FIXN(){ local f="$1" n="$2" i; { printf '['; for i in $(seq 1 "$n"); do [ "$i" -gt 1 ] && printf ','
  printf '{"id":"t-90%02d","subject":"Fix %s","status":"pending","execution":"autonomous","priority":"P3","blocked_by":[]}' "$i" "$i"; done; printf ']'; } > "$f"
}
# run-one with explicit base branch + isolated worktree/lock/ledger dirs
run_one(){ local repo="$1"; shift; local base="$1"; shift
  FIX1 "${repo}.fix.json"
  ( cd "$repo"; env CLAUDE_BIN="$STUB" RUNNER_TASKS_JSON="${repo}.fix.json" RUNNER_PLAN=1 \
      RUNNER_LEDGER="${repo}.ledger.jsonl" RUNNER_BASE_BRANCH="$base" \
      RUNNER_WORKTREE_DIR="${repo}.wt" RUNNER_LOCK_FILE="${repo}.lock" "$@" \
      bash "$RUNNER_SRC" --run-one >/dev/null 2>&1 )
}
BR="runner/auto/t-9001"

echo "autonomous-runner invariant tests (ADR-060 / t-2150)"

# 1. Detached HEAD must NOT break isolation (the bug worktree-isolation fixes).
R="$(make_repo)"; ( cd "$R"; git checkout -q --detach HEAD )
run_one "$R" ""   # empty base → resolve falls back to current commit, never errors
ok "detached-HEAD: task branch still created" '( cd "$R"; git rev-parse --verify "$BR" >/dev/null 2>&1 )'
ok "detached-HEAD: commit landed on the branch" '[ "$( cd "$R"; git rev-list --count "$BR" 2>/dev/null )" = "2" ]'
ok "detached-HEAD: live tree clean" '[ -z "$( cd "$R"; git status --porcelain )" ]'
rm -rf "$R" "${R}".*

# 2. Live working tree is NEVER modified (change lives only on the task branch).
R="$(make_repo)"; base="$( cd "$R"; git branch --show-current )"; run_one "$R" "$base"
ok "isolation: live target.txt unchanged (still 'teh')" '[ "$(cat "$R/target.txt")" = "teh" ]'
ok "isolation: base branch has no new commit" '[ "$( cd "$R"; git rev-list --count HEAD )" = "1" ]'
ok "isolation: still on base branch (live HEAD not moved)" '[ "$( cd "$R"; git branch --show-current )" = "'"$base"'" ]'
ok "isolation: change IS on the task branch" '[ "$( cd "$R"; git show "$BR":target.txt 2>/dev/null )" = "the" ]'
rm -rf "$R" "${R}".*

# 3. The ephemeral worktree is removed on success (no leftover worktrees).
R="$(make_repo)"; base="$( cd "$R"; git branch --show-current )"; run_one "$R" "$base"
ok "worktree removed after success: only main worktree remains" '[ "$( cd "$R"; git worktree list | wc -l | tr -d " " )" = "1" ]'
rm -rf "$R" "${R}".*

# 4. The worktree is removed on FAILURE too (validate fails) — and base stays pristine.
R="$(make_repo)"; base="$( cd "$R"; git branch --show-current )"; run_one "$R" "$base" RUNNER_VALIDATE_CMD="false"
ok "worktree removed after failure" '[ "$( cd "$R"; git worktree list | wc -l | tr -d " " )" = "1" ]'
ok "failure: no task branch left" '! ( cd "$R"; git rev-parse --verify "$BR" >/dev/null 2>&1 )'
ok "failure: base pristine" '[ "$( cd "$R"; git rev-list --count HEAD )" = "1" ]'
rm -rf "$R" "${R}".*

# 5. A DIRTY live tree does not block the run (worktree model ignores the live checkout).
R="$(make_repo)"; base="$( cd "$R"; git branch --show-current )"
( cd "$R"; printf 'dirty\n' >> target.txt )   # uncommitted live-tree change
run_one "$R" "$base"
ok "dirty-tree tolerated: run still produced the task branch" '( cd "$R"; git rev-parse --verify "$BR" >/dev/null 2>&1 )'
rm -rf "$R" "${R}".*

# 6. Concurrency: while the lock is held by another process, --run-batch bails (no double-run).
R="$(make_repo)"; base="$( cd "$R"; git branch --show-current )"; FIXN "${R}.fix.json" 2
mkfifo "${R}.fifo"
# Holder = ONE process (read is a builtin → no child to orphan) that takes the exclusive lock,
# signals via ${R}.held, then blocks on the FIFO. Killed cleanly at the end; stdout to /dev/null
# so it never holds the suite's pipe.
( exec 9>"${R}.lock"; flock -n 9 || exit 1; : > "${R}.held"; read -r _ <"${R}.fifo" ) >/dev/null 2>&1 &
HOLDER=$!
held=0; for _ in $(seq 1 500); do [ -f "${R}.held" ] && { held=1; break; }; done
( cd "$R"; env CLAUDE_BIN="$STUB" RUNNER_TASKS_JSON="${R}.fix.json" RUNNER_PLAN=1 \
    RUNNER_LEDGER="${R}.ledger.jsonl" RUNNER_BASE_BRANCH="$base" RUNNER_WORKTREE_DIR="${R}.wt" \
    RUNNER_LOCK_FILE="${R}.lock" RUNNER_KILL_SWITCH="${R}.stop" \
    bash "$RUNNER_SRC" --run-batch >/dev/null 2>&1 )
ok "concurrency: lock was actually held during the test" '[ "$held" = "1" ]'
ok "concurrency: locked-out batch ran nothing" '[ ! -s "${R}.ledger.jsonl" ] || [ "$(led_count "${R}.ledger.jsonl" ran)" = "0" ]'
ok "concurrency: locked-out batch created no branches" '! ( cd "$R"; git branch | grep -q runner/auto )'
kill "$HOLDER" 2>/dev/null; wait "$HOLDER" 2>/dev/null   # single process, no orphan
rm -rf "$R" "${R}".*

rm -rf "$STUBDIR"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
