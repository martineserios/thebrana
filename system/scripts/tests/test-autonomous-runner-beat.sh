#!/usr/bin/env bash
# test-autonomous-runner-beat.sh — Stage 4 (--run-beat) headless N-process fan-out (t-3271,
# ADR-090 §1/§2). Hermetic: a throwaway git repo, a stub `brana` standing in for the wave
# pull, and a stub `claude` that records its own start/end so the test can prove the N
# dispatches genuinely OVERLAP rather than merely happening N times in a row.
#
# The property under test is ADR-090 §2's headless clause: N separate `claude -p` processes,
# each in its OWN ephemeral worktree under the same ADR-060 isolation contract used once
# today. So the assertions are: N executor invocations, N distinct task branches, the base
# branch untouched, and fan-out 1 behaving exactly like a single dispatch.
set -u

RUNNER_SRC="$(git rev-parse --show-toplevel 2>/dev/null)/system/scripts/autonomous-runner.sh"
[ -f "$RUNNER_SRC" ] || { echo "FAIL: runner not found"; exit 1; }

PASS=0; FAIL=0
ok(){ if eval "$2"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "  ✗ $1"; fi; }

STUBDIR="$(mktemp -d /tmp/runner-beat-stub-XXXXXX)"

# ── Stub claude: one dispatch = one line pair in $STUB_TRACE (S then E, around a short
#    sleep). Concurrent dispatches interleave as S,S,…,E,E; serial ones as S,E,S,E.
STUB="$STUBDIR/claude"
cat > "$STUB" <<'STUBEOF'
#!/usr/bin/env bash
prompt="$(cat)"
if printf '%s' "$prompt" | grep -q "PLANNING step"; then echo "AUTODOABLE: ok"; exit 0; fi
id="$(printf '%s' "$prompt" | sed -n 's/^Task \(t-[0-9]*\):.*/\1/p' | head -1)"
[ -n "${STUB_TRACE:-}" ] && echo "S $id" >> "$STUB_TRACE"
sleep "${STUB_SLEEP:-0.5}"
printf 'the\n' > target.txt
[ -n "${STUB_TRACE:-}" ] && echo "E $id" >> "$STUB_TRACE"
echo "DONE: fixed the typo in $id"
exit 0
STUBEOF
chmod +x "$STUB"

# ── Stub brana: only `backlog wave pull` is exercised by --run-beat. Emits the real CLI's
#    n>1 shape (pulled_task_ids + stopped); STUB_PULL_IDS controls what the beat claims.
BSTUB="$STUBDIR/brana"
cat > "$BSTUB" <<'BSTUBEOF'
#!/usr/bin/env bash
if [ "${1:-}" = "backlog" ] && [ "${2:-}" = "wave" ] && [ "${3:-}" = "pull" ]; then
  arr="$(printf '%s\n' ${STUB_PULL_IDS:-} | grep -v '^$' | jq -R . | jq -sc .)"
  jq -cn --arg w "${4:-wave-1}" --argjson ids "$arr" --arg st "${STUB_STOP:-reached_n}" \
    '{ok:true,id:$w,n:($ids|length),pulled_task_ids:$ids,stopped:$st}'
  exit 0
fi
exit 0
BSTUBEOF
chmod +x "$BSTUB"

make_repo(){
  local d; d="$(mktemp -d /tmp/runner-beat-repo-XXXXXX)"
  ( cd "$d"
    git init -q; git config user.email t@t; git config user.name t; git config commit.gpgsign false
    printf 'teh\n' > target.txt
    git add -A; git commit -q -m init
  ); echo "$d"
}
# FIXN <file> <n> — the task objects --run-beat resolves each pulled id against.
FIXN(){ local f="$1" n="$2" i
  { printf '['; for i in $(seq 1 "$n"); do [ "$i" -gt 1 ] && printf ','
      printf '{"id":"t-80%02d","subject":"Fix typo %s","status":"in_progress","execution":"autonomous","priority":"P3","blocked_by":[]}' "$i" "$i"
    done; printf ']'; } > "$f"
}
run_beat(){ # repo fanout ids... ; extra env via BEAT_ENV
  local repo="$1" fanout="$2"; shift 2
  local base; base="$(cd "$repo" && git branch --show-current)"
  ( cd "$repo"
    env RUNNER_SANDBOX=0 CLAUDE_BIN="$STUB" BRANA_BIN="$BSTUB" \
        RUNNER_TASKS_JSON="${repo}.fix.json" RUNNER_PLAN=0 \
        RUNNER_LEDGER="${repo}.ledger.jsonl" RUNNER_BASE_BRANCH="$base" \
        RUNNER_WORKTREE_DIR="${repo}.wt" RUNNER_LOCK_FILE="${repo}.lock" \
        RUNNER_KILL_SWITCH="${repo}.nostop" RUNNER_FANOUT="$fanout" \
        STUB_TRACE="${repo}.trace" STUB_PULL_IDS="$*" \
        bash "$RUNNER_SRC" --run-beat --wave wave-1 >"${repo}.out" 2>&1 )
}

echo "autonomous-runner Stage 4 (run-beat, ADR-090 fan-out) tests"

# 1. N=3: three dispatches, three branches, base pristine — the headless fan-out contract.
R="$(make_repo)"; FIXN "${R}.fix.json" 3
run_beat "$R" 3 t-8001 t-8002 t-8003
STARTS="$(grep -c '^S ' "${R}.trace" 2>/dev/null || echo 0)"
ok "N=3: three executor processes dispatched" '[ "$STARTS" = "3" ]'
ok "N=3: branch for t-8001" '( cd "$R"; git rev-parse --verify runner/auto/t-8001 >/dev/null 2>&1 )'
ok "N=3: branch for t-8002" '( cd "$R"; git rev-parse --verify runner/auto/t-8002 >/dev/null 2>&1 )'
ok "N=3: branch for t-8003" '( cd "$R"; git rev-parse --verify runner/auto/t-8003 >/dev/null 2>&1 )'
ok "N=3: each branch carries exactly one commit beyond base" \
  '[ "$( cd "$R"; for b in t-8001 t-8002 t-8003; do git rev-list --count HEAD..runner/auto/$b; done | sort -u | tr -d "\n" )" = "1" ]'
ok "N=3: base branch has no new commit" '[ "$( cd "$R"; git rev-list --count HEAD )" = "1" ]'
ok "N=3: live working tree clean" '[ -z "$( cd "$R"; git status --porcelain )" ]'
ok "N=3: three ledger 'ran' entries" '[ "$(jq -r "select(.decision==\"ran\")|.id" "${R}.ledger.jsonl" 2>/dev/null | wc -l | tr -d " ")" = "3" ]'
# The dispatches must genuinely overlap — N sequential run_task calls would trace S,E,S,E.
ok "N=3: dispatches overlap (parallel, not a serial loop)" \
  '[ "$(head -2 "${R}.trace" | grep -c "^S ")" = "2" ]'
ok "N=3: no ephemeral worktree left behind" '[ -z "$(ls -A "${R}.wt" 2>/dev/null | grep -v "^\." || true)" ]'
rm -rf "$R" "${R}.wt"

# 2. N=1 stays a single dispatch — the fan-out is opt-in, not a behaviour change.
R="$(make_repo)"; FIXN "${R}.fix.json" 3
run_beat "$R" 1 t-8001
ok "N=1: exactly one executor process" '[ "$(grep -c "^S " "${R}.trace" 2>/dev/null || echo 0)" = "1" ]'
ok "N=1: only the pulled task got a branch" \
  '( cd "$R"; git rev-parse --verify runner/auto/t-8001 >/dev/null 2>&1 ) && ! ( cd "$R"; git rev-parse --verify runner/auto/t-8002 >/dev/null 2>&1 )'
ok "N=1: base pristine" '[ "$( cd "$R"; git rev-list --count HEAD )" = "1" ]'
rm -rf "$R" "${R}.wt"

# 3. Empty beat (nothing eligible) is a clean ALLDONE, not a failure or a dispatch.
R="$(make_repo)"; FIXN "${R}.fix.json" 3
run_beat "$R" 3
ok "empty beat: exit 0" '[ "$?" = "0" ]'
ok "empty beat: no executor dispatched" '[ ! -s "${R}.trace" ]'
ok "empty beat: reports ALLDONE" 'grep -q "ALLDONE" "${R}.out"'
rm -rf "$R" "${R}.wt"

# 4. A beat with no wave is a caller error — never a silent fall-through to another mode.
R="$(make_repo)"; FIXN "${R}.fix.json" 1
( cd "$R"; env RUNNER_SANDBOX=0 CLAUDE_BIN="$STUB" BRANA_BIN="$BSTUB" \
    RUNNER_TASKS_JSON="${R}.fix.json" RUNNER_PLAN=0 RUNNER_LEDGER="${R}.l2.jsonl" \
    RUNNER_WORKTREE_DIR="${R}.wt" RUNNER_LOCK_FILE="${R}.lock" RUNNER_KILL_SWITCH="${R}.nostop" \
    bash "$RUNNER_SRC" --run-beat >"${R}.out2" 2>&1 )
ok "no wave: non-zero exit" '[ "$?" != "0" ]'
ok "no wave: says which flag is missing" 'grep -q -- "--wave" "${R}.out2"'
ok "no wave: nothing dispatched" '[ ! -s "${R}.trace" ]'
rm -rf "$R" "${R}.wt"

# 5. Kill-switch stops the beat BEFORE the pull — no task may be claimed and abandoned.
R="$(make_repo)"; FIXN "${R}.fix.json" 3; touch "${R}.stop"
( cd "$R"; env RUNNER_SANDBOX=0 CLAUDE_BIN="$STUB" BRANA_BIN="$BSTUB" \
    RUNNER_TASKS_JSON="${R}.fix.json" RUNNER_PLAN=0 RUNNER_LEDGER="${R}.l3.jsonl" \
    RUNNER_WORKTREE_DIR="${R}.wt" RUNNER_LOCK_FILE="${R}.lock" RUNNER_KILL_SWITCH="${R}.stop" \
    RUNNER_FANOUT=3 STUB_TRACE="${R}.trace" STUB_PULL_IDS="t-8001 t-8002 t-8003" \
    bash "$RUNNER_SRC" --run-beat --wave wave-1 >"${R}.out3" 2>&1 )
ok "kill-switch: exit 0 (clean abort)" '[ "$?" = "0" ]'
ok "kill-switch: nothing dispatched" '[ ! -s "${R}.trace" ]'
ok "kill-switch: no task branch created" '! ( cd "$R"; git branch --list "runner/auto/*" | grep -q . )'
rm -rf "$R" "${R}.wt"

rm -rf "$STUBDIR"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
