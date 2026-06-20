#!/usr/bin/env bash
# test-autonomous-runner-stage3.sh — Stage 3 (--run-batch) for the autonomous runner (t-2140).
# Hermetic: throwaway git repo + stub `claude` + stub validate. Asserts the bounded-batch
# loop: runs many eligible tasks/run, respects the batch cap, KILLS on 3 consecutive
# failures (ADR-050), honours the kill-switch file, and reports ALLDONE when nothing is
# eligible. Each task still isolates on its own branch with base left pristine (Stage 2
# invariant must survive the loop).
set -u

RUNNER_SRC="$(git rev-parse --show-toplevel 2>/dev/null)/system/scripts/autonomous-runner.sh"
[ -f "$RUNNER_SRC" ] || { echo "FAIL: runner not found"; exit 1; }

PASS=0; FAIL=0
ok(){ if eval "$2"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "  ✗ $1"; fi; }
led_count(){ jq -r "select(.decision==\"$2\")|.id" "$1" 2>/dev/null | wc -l | tr -d ' '; }   # ledger decision count

# ── Stub claude: plan always AUTODOABLE; dispatch writes the fix unless STUB_DISPATCH set ──
STUBDIR="$(mktemp -d /tmp/runner-s3-stub-XXXXXX)"
STUB="$STUBDIR/claude"
cat > "$STUB" <<'STUBEOF'
#!/usr/bin/env bash
prompt="$(cat)"
if printf '%s' "$prompt" | grep -q "PLANNING step"; then echo "AUTODOABLE: stub plan ok"; exit 0; fi
case "${STUB_DISPATCH:-change}" in
  needshuman) echo "NEEDSHUMAN: stub dispatch needs human" ;;
  nochange)   echo "DONE: claimed done, changed nothing" ;;
  *)          printf 'the\n' > "${STUB_TARGET:-target.txt}"; echo "DONE: fixed the typo" ;;
esac
exit 0
STUBEOF
chmod +x "$STUB"

make_repo(){
  local d; d="$(mktemp -d /tmp/runner-s3-repo-XXXXXX)"
  ( cd "$d"
    git init -q; git config user.email t@t; git config user.name t; git config commit.gpgsign false
    printf 'teh\n' > target.txt
    printf '#!/usr/bin/env bash\nexit 0\n' > validate.sh; chmod +x validate.sh
    git add -A; git commit -q -m "init"
  )
  echo "$d"
}
# Write a fixture with N eligible autonomous tasks (t-7001..t-700N).
FIXN(){ # file N
  local f="$1" n="$2" i; { printf '['; for i in $(seq 1 "$n"); do
    [ "$i" -gt 1 ] && printf ','
    printf '{"id":"t-700%s","subject":"Fix typo %s","status":"pending","execution":"autonomous","priority":"P3","blocked_by":[]}' "$i" "$i"
  done; printf ']'; } > "$f"
}
run_batch(){ # repo  extra-env...
  local repo="$1"; shift
  ( cd "$repo"
    env CLAUDE_BIN="$STUB" RUNNER_TASKS_JSON="${repo}.fix.json" RUNNER_PLAN=1 \
        RUNNER_LEDGER="${repo}.ledger.jsonl" STUB_TARGET="${repo}/target.txt" \
        RUNNER_KILL_SWITCH="${repo}.stop" "$@" \
        bash "$RUNNER_SRC" --run-batch >/dev/null 2>&1
  )
}

echo "autonomous-runner Stage 3 (run-batch) tests"

# 1. Batch happy path: 2 eligible → both run on their own branches, base pristine.
R="$(make_repo)"; FIXN "${R}.fix.json" 2; run_batch "$R"
ok "batch: branch t-7001 created" '( cd "$R"; git rev-parse --verify runner/auto/t-7001 >/dev/null 2>&1 )'
ok "batch: branch t-7002 created" '( cd "$R"; git rev-parse --verify runner/auto/t-7002 >/dev/null 2>&1 )'
ok "batch: base still 1 commit (no merges)" '[ "$( cd "$R"; git rev-list --count HEAD )" = "1" ]'
ok "batch: returned to base, tree clean" '[ -z "$( cd "$R"; git status --porcelain )" ]'
ok "batch: ledger has 2 ran" '[ "$(led_count "${R}.ledger.jsonl" ran)" = "2" ]'
rm -rf "$R" "${R}".*

# 2. Batch cap: RUNNER_MAX_TASKS=1 with 2 eligible → only the first attempted.
R="$(make_repo)"; FIXN "${R}.fix.json" 2; run_batch "$R" RUNNER_MAX_TASKS=1
ok "cap: only t-7001 ran" '[ "$(led_count "${R}.ledger.jsonl" ran)" = "1" ]'
ok "cap: t-7002 branch NOT created" '! ( cd "$R"; git rev-parse --verify runner/auto/t-7002 >/dev/null 2>&1 )'
rm -rf "$R" "${R}".*

# 3. Consecutive-failure kill: 4 failing tasks (validate=false), cap high → stops at 3.
R="$(make_repo)"; FIXN "${R}.fix.json" 4; run_batch "$R" RUNNER_MAX_TASKS=10 RUNNER_VALIDATE_CMD="false"
ok "kill: exactly 3 failures recorded (killed at 3)" '[ "$(led_count "${R}.ledger.jsonl" failed)" = "3" ]'
ok "kill: 4th task never attempted (no ledger entry)" '[ "$(wc -l < "${R}.ledger.jsonl" | tr -d " ")" = "3" ]'
ok "kill: base pristine after failures" '[ "$( cd "$R"; git rev-list --count HEAD )" = "1" ]'
ok "kill: no task branches survive" '! ( cd "$R"; git branch | grep -q runner/auto )'
rm -rf "$R" "${R}".*

# 4. Kill-switch file present → batch aborts before doing anything.
R="$(make_repo)"; FIXN "${R}.fix.json" 2; : > "${R}.stop"; run_batch "$R"
ok "killswitch: nothing ran (empty/absent ledger)" '[ ! -s "${R}.ledger.jsonl" ] || [ "$(led_count "${R}.ledger.jsonl" ran)" = "0" ]'
ok "killswitch: no branches created" '! ( cd "$R"; git branch | grep -q runner/auto )'
rm -rf "$R" "${R}".*

# 5. ALLDONE: zero eligible tasks → clean exit, no branches.
R="$(make_repo)"; printf '[]' > "${R}.fix.json"; run_batch "$R"
ok "alldone: exit 0 on empty backlog" 'run_batch "$R"; [ $? -eq 0 ]'
ok "alldone: no branches" '! ( cd "$R"; git branch | grep -q runner/auto )'
rm -rf "$R" "${R}".*

# 6. NEEDSHUMAN mid-batch parks, does NOT count as a failure (kill counter resets).
R="$(make_repo)"; FIXN "${R}.fix.json" 2; run_batch "$R" STUB_DISPATCH=needshuman
ok "park: both parked (would-park x2)" '[ "$(led_count "${R}.ledger.jsonl" would-park)" = "2" ]'
ok "park: base pristine, no branches" '! ( cd "$R"; git branch | grep -q runner/auto ) && [ "$( cd "$R"; git rev-list --count HEAD )" = "1" ]'
rm -rf "$R" "${R}".*

rm -rf "$STUBDIR"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
