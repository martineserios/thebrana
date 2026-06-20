#!/usr/bin/env bash
# test-autonomous-runner-stage2.sh — Stage 2 (--run-one) for the autonomous runner (t-2140).
# Hermetic: a throwaway git repo + a stub `claude` (STUB_* env controls its behaviour) +
# a stub validate. Asserts the run/verify/commit path AND the critical failure invariant:
# on any failure the base branch stays pristine and the task branch is gone.
set -u

RUNNER_SRC="$(git rev-parse --show-toplevel 2>/dev/null)/system/scripts/autonomous-runner.sh"
[ -f "$RUNNER_SRC" ] || { echo "FAIL: runner not found"; exit 1; }

PASS=0; FAIL=0
ok(){ if eval "$2"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "  ✗ $1"; fi; }

# ── Build a stub claude: reads prompt from stdin, branches on plan-vs-dispatch ──
STUBDIR="$(mktemp -d /tmp/runner-s2-stub-XXXXXX)"
STUB="$STUBDIR/claude"
cat > "$STUB" <<'STUBEOF'
#!/usr/bin/env bash
prompt="$(cat)"
if printf '%s' "$prompt" | grep -q "PLANNING step"; then
  case "${STUB_PLAN:-auto}" in park) echo "NEEDSHUMAN: stub plan parks";; *) echo "AUTODOABLE: stub plan ok";; esac
  exit 0
fi
# dispatch call
case "${STUB_DISPATCH:-change}" in
  needshuman) echo "NEEDSHUMAN: stub dispatch needs human" ;;
  nochange)   echo "DONE: claimed done, changed nothing" ;;
  *)          printf 'the\n' > "${STUB_TARGET:-target.txt}"; echo "DONE: fixed the typo" ;;
esac
exit 0
STUBEOF
chmod +x "$STUB"

# ── Helper: fresh temp git repo with a target file + stub validate ─────────────
make_repo(){
  local d; d="$(mktemp -d /tmp/runner-s2-repo-XXXXXX)"
  ( cd "$d"
    git init -q; git config user.email t@t; git config user.name t
    git config commit.gpgsign false
    printf 'teh\n' > target.txt
    printf '#!/usr/bin/env bash\nexit 0\n' > validate.sh; chmod +x validate.sh
    git add -A; git commit -q -m "init"
  )
  echo "$d"
}
FIX(){ cat > "$1" <<EOF
[{"id":"t-7001","subject":"Fix the typo in target.txt","status":"pending","execution":"autonomous","priority":"P3","blocked_by":[]}]
EOF
}
run_one(){ # repo  extra-env...
  local repo="$1"; shift
  FIX "${repo}.fix.json"   # OUTSIDE the repo, so the repo working tree stays clean
  ( cd "$repo"
    env CLAUDE_BIN="$STUB" RUNNER_TASKS_JSON="${repo}.fix.json" RUNNER_PLAN=1 \
        RUNNER_LEDGER="${repo}.ledger.jsonl" STUB_TARGET="${repo}/target.txt" "$@" \
        bash "$RUNNER_SRC" --run-one >/dev/null 2>&1
  )
}
BRANCH="runner/auto/t-7001"

echo "autonomous-runner Stage 2 (run-one) tests"

# 1. Happy path: change made + validate passes → commit on branch, base pristine, back on base.
R="$(make_repo)"; run_one "$R"
ok "happy: task branch created" '( cd "$R"; git rev-parse --verify "$BRANCH" >/dev/null 2>&1 )'
ok "happy: 1 commit on branch beyond base" '[ "$( cd "$R"; b=$(git branch --show-current); git rev-list --count "$b".."'"$BRANCH"'" 2>/dev/null )" = "1" ]'
ok "happy: base branch has no new commit" '[ "$( cd "$R"; git rev-list --count HEAD 2>/dev/null )" = "1" ]'
ok "happy: returned to base (not on task branch)" '[ "$( cd "$R"; git branch --show-current )" != "'"$BRANCH"'" ]'
ok "happy: working tree clean" '[ -z "$( cd "$R"; git status --porcelain )" ]'
ok "happy: ledger decision=ran" '[ "$(jq -r "select(.id==\"t-7001\")|.decision" "${R}.ledger.jsonl" 2>/dev/null)" = "ran" ]'
rm -rf "$R"

# 2. NEEDSHUMAN from dispatch → no commit, branch deleted, base pristine.
R="$(make_repo)"; run_one "$R" STUB_DISPATCH=needshuman
ok "needshuman: no task branch left" '! ( cd "$R"; git rev-parse --verify "$BRANCH" >/dev/null 2>&1 )'
ok "needshuman: base pristine (1 commit)" '[ "$( cd "$R"; git rev-list --count HEAD )" = "1" ]'
ok "needshuman: working tree clean" '[ -z "$( cd "$R"; git status --porcelain )" ]'
rm -rf "$R"

# 3. No change produced → clean abort, no commit, branch gone.
R="$(make_repo)"; run_one "$R" STUB_DISPATCH=nochange
ok "nochange: no task branch left" '! ( cd "$R"; git rev-parse --verify "$BRANCH" >/dev/null 2>&1 )'
ok "nochange: base pristine" '[ "$( cd "$R"; git rev-list --count HEAD )" = "1" ]'
ok "nochange: target.txt unchanged" '[ "$(cat "$R/target.txt")" = "teh" ]'
rm -rf "$R"

# 4. Validate fails → working tree reverted, no commit, back on base, branch gone.
R="$(make_repo)"; run_one "$R" RUNNER_VALIDATE_CMD="false"
ok "validatefail: no task branch left" '! ( cd "$R"; git rev-parse --verify "$BRANCH" >/dev/null 2>&1 )'
ok "validatefail: base pristine" '[ "$( cd "$R"; git rev-list --count HEAD )" = "1" ]'
ok "validatefail: target.txt reverted to teh" '[ "$(cat "$R/target.txt")" = "teh" ]'
ok "validatefail: working tree clean" '[ -z "$( cd "$R"; git status --porcelain )" ]'
rm -rf "$R"

# 5. Plan says park → task not executed at all (no branch, no change).
R="$(make_repo)"; run_one "$R" STUB_PLAN=park
ok "park: no task branch created" '! ( cd "$R"; git rev-parse --verify "$BRANCH" >/dev/null 2>&1 )'
ok "park: base pristine" '[ "$( cd "$R"; git rev-list --count HEAD )" = "1" ]'
ok "park: ledger decision=would-park" '[ "$(jq -r "select(.id==\"t-7001\")|.decision" "${R}.ledger.jsonl" 2>/dev/null)" = "would-park" ]'
rm -rf "$R"

rm -rf "$STUBDIR"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
