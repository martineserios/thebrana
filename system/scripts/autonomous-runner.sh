#!/usr/bin/env bash
# autonomous-runner.sh — native /loop-over-backlog autonomous runner (t-2140).
#
# Staged rollout (docs/architecture/features/autonomous-runner.md):
#   --observe   STAGE 1: select eligible tasks, plan each, emit a would-run/would-park/
#               excluded ledger. ZERO mutations. (proves judgment before write access)
#   --run-one   STAGE 2: run the FIRST eligible would-run task on an isolated branch,
#               verify, commit, STOP. Never merges, never marks the task completed.
#               On ANY failure: revert working tree, return to base branch, delete branch.
#   --run-batch STAGE 3: loop run-one over eligible tasks (a snapshot, each on its own
#               branch) until the batch cap or bounds trip. Bounded: RUNNER_MAX_TASKS cap,
#               consecutive-failure KILL at RUNNER_MAX_FAILS (ADR-050), and a kill-switch
#               file (RUNNER_KILL_SWITCH). Reports ALLDONE when nothing is eligible.
#               PR-per-task; never merges, never marks tasks completed.
#
# Native only — no ruflo. Modelled on system/scripts/feed-summarize.sh.
#
# Env (shared):
#   RUNNER_TASKS_JSON  task-source override (file path; for tests). Default: live backlog.
#                      When set, brana mutations (remind/set) are skipped (hermetic tests).
#   RUNNER_MAX_TASKS   batch cap for --observe (default 5)
#   RUNNER_PLAN        1=claude judges would-run vs would-park (default 1); 0=skip
#   RUNNER_LEDGER      ledger path (default ~/.claude/scheduler/runner-ledger-<date>.jsonl)
#   CLAUDE_BIN         claude binary (default ~/.local/bin/claude)
# Env (--run-one adds):
#   RUNNER_VALIDATE_CMD  verification command (default ./validate.sh); non-zero = task failed
#   RUNNER_BRANCH_PREFIX per-task branch namespace (default runner/auto)
#   RUNNER_PUSH          1=open a PR via gh after commit (default 0 = local branch only)
#   RUNNER_BASE_BRANCH   integration branch to cut from (ADR-060). Default resolution:
#                        env → .claude/CLAUDE.md "integration=<b>" → "dev" → current HEAD (warn).
#                        The agent NEVER targets production directly; PRs open against this branch.
#   RUNNER_WORKTREE_DIR  parent dir for ephemeral per-task worktrees (default /tmp/brana-runner)
# Env (--run-batch adds):
#   RUNNER_MAX_FAILS     consecutive-failure kill threshold (default 3, ADR-050 cap)
#   RUNNER_KILL_SWITCH   abort if this file exists (default ~/.claude/scheduler/runner.stop)
#   RUNNER_LOCK_FILE     flock path serializing batch runs (default ~/.claude/scheduler/locks/autonomous-runner.lock)
#
# Eligibility: status==pending ∧ execution==autonomous ∧ priority!=P0 ∧ blocked_by empty.
set -u

MODE="observe"
for a in "$@"; do case "$a" in --observe) MODE="observe" ;; --run-one) MODE="run-one" ;; --run-batch) MODE="run-batch" ;; esac; done

MAX_TASKS="${RUNNER_MAX_TASKS:-5}"
PLAN="${RUNNER_PLAN:-1}"
CLAUDE_BIN="${CLAUDE_BIN:-$HOME/.local/bin/claude}"
LEDGER="${RUNNER_LEDGER:-$HOME/.claude/scheduler/runner-ledger-$(date -u +%Y%m%d).jsonl}"
VALIDATE_CMD="${RUNNER_VALIDATE_CMD:-./validate.sh}"
BRANCH_PREFIX="${RUNNER_BRANCH_PREFIX:-runner/auto}"
PUSH="${RUNNER_PUSH:-0}"
MAX_FAILS="${RUNNER_MAX_FAILS:-3}"
KILL_SWITCH="${RUNNER_KILL_SWITCH:-$HOME/.claude/scheduler/runner.stop}"
RUN_LOCK="${RUNNER_LOCK_FILE:-$HOME/.claude/scheduler/locks/autonomous-runner.lock}"
FIXTURE_MODE=0; [ -n "${RUNNER_TASKS_JSON:-}" ] && FIXTURE_MODE=1
TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

mkdir -p "$(dirname "$LEDGER")"
: > "$LEDGER"

if [ -n "${RUNNER_TASKS_JSON:-}" ]; then
  TASKS_JSON="$(cat "$RUNNER_TASKS_JSON" 2>/dev/null || echo '[]')"
else
  TASKS_JSON="$(brana backlog query --status pending --output json 2>/dev/null || echo '[]')"
fi

resolve_claude() { local cb="$CLAUDE_BIN"; [ -x "$cb" ] || cb="$(command -v claude 2>/dev/null || true)"; echo "$cb"; }

# sandbox_claude <workdir> -- <claude args...> : run `claude -p` inside a bubblewrap
# capability jail (ADR-062). The prompt is read from this function's STDIN and forwarded
# into the jail. Containment (spike-validated 2026-06-21):
#   - minimal --ro-bind list (NOT /) → ~/.config/brana/*.env, ~/.ssh, ~/.aws are ABSENT
#   - env -i → inherited env secrets (LINEAR_API_KEY, …) cleared
#   - writable tmpfs HOME with claude's creds ro-bound inside → auth works, no host writes
#   - <workdir> bound to /workspace = the ONLY writable host path
#   - rlimits via inner ulimit (bwrap 0.11.1 has no --rlimit-* flags)
# Egress is NOT yet restricted (shared netns) — ADR-062 open item. Graceful fallback to an
# UNSANDBOXED run (loud warning) when bwrap is missing or RUNNER_SANDBOX=0 (e.g. CI without
# user namespaces, or the orchestration tests that stub `claude`).
SANDBOX="${RUNNER_SANDBOX:-1}"
sandbox_claude() {
  local wd="$1"; shift
  local cb; cb="$(resolve_claude)"
  if [ "$SANDBOX" = "0" ] || ! command -v bwrap >/dev/null 2>&1; then
    [ "$SANDBOX" != "0" ] && echo "[autonomous-runner] WARN: bwrap unavailable — executor running UNSANDBOXED (ADR-062)" >&2
    ( cd "$wd" && timeout "${RUNNER_DISPATCH_TIMEOUT:-600}" "$cb" "$@" )
    return $?
  fi
  local cbr resolv
  cbr="$(readlink -f "$cb")"
  resolv="$(readlink -f /etc/resolv.conf 2>/dev/null)"
  local -a B=(--unshare-ipc --unshare-pid
    --ro-bind /usr /usr --ro-bind /bin /bin --ro-bind /lib /lib)
  [ -e /lib64 ] && B+=(--ro-bind /lib64 /lib64)
  B+=(--ro-bind /etc /etc)
  [ -n "$resolv" ] && [ -e "$resolv" ] && B+=(--ro-bind "$resolv" /run/systemd/resolve/stub-resolv.conf)
  B+=(--ro-bind "$cbr" /opt/claude)
  [ -e "$HOME/.cargo" ]    && B+=(--ro-bind "$HOME/.cargo" /home/sb/.cargo)
  [ -e "$HOME/.gitconfig" ] && B+=(--ro-bind "$HOME/.gitconfig" /home/sb/.gitconfig)
  [ -e "$HOME/.claude/.credentials.json" ] && B+=(--ro-bind "$HOME/.claude/.credentials.json" /home/sb/.claude/.credentials.json)
  B+=(--bind "$wd" /workspace --tmpfs /home --tmpfs /tmp --proc /proc --dev /dev --chdir /workspace)
  timeout "${RUNNER_DISPATCH_TIMEOUT:-600}" bwrap "${B[@]}" \
    env -i HOME=/home/sb PATH=/usr/bin:/bin TERM="${TERM:-dumb}" \
    bash -c 'ulimit -u 200 2>/dev/null; ulimit -f 1024000 2>/dev/null; exec /opt/claude "$@"' _ "$@"
}

emit() { # id subject decision reason
  jq -cn --arg id "$1" --arg s "$2" --arg d "$3" --arg r "$4" --arg ts "$TS" \
    '{id:$id,subject:$s,decision:$d,reason:$r,ts:$ts}' >> "$LEDGER"
}

plan_task() { # id subject -> "would-run <reason>" | "would-park <reason>"
  local id="$1" subj="$2"
  if [ "$PLAN" != "1" ]; then echo "would-run eligible"; return; fi
  local cb; cb="$(resolve_claude)"
  if [ -z "$cb" ]; then echo "would-run eligible (no claude; plan skipped)"; return; fi
  local prompt verdict
  prompt="You are the PLANNING step of an autonomous task runner in OBSERVE mode — make NO changes, only assess. Task ${id}: \"${subj}\". Can an agent complete this with NO human input, or does it need a human decision first (ambiguous scope, irreversible/risky action, a choice only the owner can make)? Reply with exactly one line: AUTODOABLE: <why> or NEEDSHUMAN: <what decision is needed>."
  verdict="$(printf '%s' "$prompt" | timeout 60 "$cb" -p --model haiku --allowedTools "Read,Grep,Glob" --output-format text 2>/dev/null)"
  case "$verdict" in
    NEEDSHUMAN:*) echo "would-park ${verdict#NEEDSHUMAN: }" ;;
    AUTODOABLE:*) echo "would-run ${verdict#AUTODOABLE: }" ;;
    *)            echo "would-run eligible (plan inconclusive)" ;;
  esac
}

# ════════════════════════════════ STAGE 1: OBSERVE ════════════════════════════
if [ "$MODE" = "observe" ]; then
  ELIG=0; RUN=0; PARK=0; EXCL=0; TAKEN=0
  while IFS= read -r t; do
    [ -z "$t" ] && continue
    id="$(echo "$t" | jq -r '.id // "?"')"; subj="$(echo "$t" | jq -r '.subject // ""')"
    status="$(echo "$t" | jq -r '.status // ""')"; execm="$(echo "$t" | jq -r '.execution // ""')"
    prio="$(echo "$t" | jq -r '.priority // ""')"; nblock="$(echo "$t" | jq -r '(.blocked_by // []) | length')"
    if [ "$status" != "pending" ];   then emit "$id" "$subj" excluded "not-pending ($status)"; EXCL=$((EXCL+1)); continue; fi
    if [ "$execm" != "autonomous" ]; then emit "$id" "$subj" excluded "not-autonomous (execution=$execm)"; EXCL=$((EXCL+1)); continue; fi
    if [ "$prio" = "P0" ];           then emit "$id" "$subj" excluded "p0 (never auto)"; EXCL=$((EXCL+1)); continue; fi
    if [ "$nblock" -gt 0 ];          then emit "$id" "$subj" excluded "blocked ($nblock blocker(s))"; EXCL=$((EXCL+1)); continue; fi
    ELIG=$((ELIG+1))
    if [ "$TAKEN" -ge "$MAX_TASKS" ]; then emit "$id" "$subj" excluded "cap (RUNNER_MAX_TASKS=$MAX_TASKS)"; EXCL=$((EXCL+1)); continue; fi
    read -r decision reason < <(plan_task "$id" "$subj")
    emit "$id" "$subj" "$decision" "$reason"; TAKEN=$((TAKEN+1))
    if [ "$decision" = "would-park" ]; then PARK=$((PARK+1)); else RUN=$((RUN+1)); fi
  done < <(echo "$TASKS_JSON" | jq -c '.[]' 2>/dev/null)
  echo "[autonomous-runner] mode=observe (OBSERVE — no changes made)"
  echo "[autonomous-runner] eligible=$ELIG  would-run=$RUN  would-park=$PARK  excluded=$EXCL  (cap=$MAX_TASKS)"
  echo "[autonomous-runner] ledger: $LEDGER"
  exit 0
fi

# ═══════════════════════ STAGE 2/3: per-task executor (run_task) ═══════════════
# Auto-generated files churn as a side effect of brana reads/writes (e.g. brana regenerates
# docs/spec-graph.json on any backlog query). They are never hand-edited, so their uncommitted
# churn is always safe to discard — do so before the clean check and before committing.
GENERATED="${RUNNER_GENERATED_FILES:-docs/spec-graph.json}"
drop_generated() { local gf; for gf in $GENERATED; do git checkout -- "$gf" 2>/dev/null || true; done; }

# resolve_base_branch — the per-project integration branch (ADR-060 Layer-2 policy).
# Precedence: RUNNER_BASE_BRANCH env → repo .claude/CLAUDE.md "integration=<b>" declaration → "dev".
# The concrete ref is resolved later (origin/<b> → local <b> → current HEAD with a loud warning),
# so the runner NEVER silently targets production.
resolve_base_branch() {
  if [ -n "${RUNNER_BASE_BRANCH:-}" ]; then echo "$RUNNER_BASE_BRANCH"; return; fi
  local decl
  decl="$(grep -oiE 'integration=[A-Za-z0-9._/-]+' .claude/CLAUDE.md 2>/dev/null | head -1 | cut -d= -f2)"
  if [ -n "$decl" ]; then echo "$decl"; return; fi
  echo "dev"
}

# cleanup_worktree <path> <branch> — remove an ephemeral worktree and its branch. The live
# working tree and the base branch are NEVER touched (that is the isolation boundary, ADR-060).
cleanup_worktree() {
  git worktree remove --force "$1" 2>/dev/null || rm -rf "$1" 2>/dev/null || true
  git worktree prune 2>/dev/null || true
  [ -n "$2" ] && git branch -D "$2" -q 2>/dev/null || true
}

park() { # id subj reason — record a needs-human question and leave the task pending
  emit "$1" "$2" would-park "$3"
  if [ "$FIXTURE_MODE" = "0" ] && command -v brana >/dev/null 2>&1; then
    # High priority + actionable: parked questions must surface above the medium-priority noise.
    brana remind write --text "Runner parked $1: $3" --action "brana backlog get $1" \
      --priority high --tags "runner-question,needs-human" --task-id "$1" --dedup-key "runner-$1" >/dev/null 2>&1 || true
    brana backlog set "$1" context "PARKED $(date -u +%F): $3" --append >/dev/null 2>&1 || true
  fi
  echo "[autonomous-runner] run-task: PARKED $1 — $3"
}

# run_task <task-json> — isolate in an EPHEMERAL WORKTREE off the integration branch, dispatch,
# verify, commit one task. STOPS (no merge, no completed-mark). The live working tree and the base
# branch are never touched. Returns: 0=ran, 2=parked (needs human), 1=failed (worktree removed).
run_task() {
  local TASK="$1" ID SUBJ DESC CTX DECISION REASON BASE_BRANCH BASE_REF FALLBACK WT BRANCH CB DPROMPT DOUT REASON_H gf
  ID="$(echo "$TASK" | jq -r '.id')"; SUBJ="$(echo "$TASK" | jq -r '.subject // ""')"
  DESC="$(echo "$TASK" | jq -r '.description // ""')"; CTX="$(echo "$TASK" | jq -r '.context // ""')"

  # Plan gate: only run a would-run; park a would-park (clean outcome, not a failure).
  read -r DECISION REASON < <(plan_task "$ID" "$SUBJ")
  if [ "$DECISION" = "would-park" ]; then park "$ID" "$SUBJ" "$REASON"; return 2; fi

  # Resolve the integration branch (ADR-060) and a concrete base ref. Prefer origin/<b>, then
  # local <b>; else fall back to current HEAD with a LOUD warning (never silently hit production).
  BASE_BRANCH="$(resolve_base_branch)"
  git fetch origin "$BASE_BRANCH" --quiet 2>/dev/null || true
  if git rev-parse --verify -q "refs/remotes/origin/$BASE_BRANCH" >/dev/null 2>&1; then
    BASE_REF="origin/$BASE_BRANCH"
  elif git rev-parse --verify -q "refs/heads/$BASE_BRANCH" >/dev/null 2>&1; then
    BASE_REF="$BASE_BRANCH"
  else
    FALLBACK="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)"
    echo "[autonomous-runner] WARN: integration branch '$BASE_BRANCH' not found — falling back to '$FALLBACK'. Set RUNNER_BASE_BRANCH or declare 'integration=<branch>' in .claude/CLAUDE.md." >&2
    BASE_REF="$FALLBACK"; BASE_BRANCH="$FALLBACK"
  fi

  BRANCH="${BRANCH_PREFIX}/${ID}"
  WT="${RUNNER_WORKTREE_DIR:-/tmp/brana-runner}/${ID}"
  # Stale-state hygiene: drop any leftover worktree/branch from a prior crashed run.
  cleanup_worktree "$WT" "$BRANCH"

  # Isolated worktree off the base ref — its own .git/index, parallel-safe, base untouched.
  if ! git worktree add -q "$WT" -b "$BRANCH" "$BASE_REF" 2>/dev/null; then
    emit "$ID" "$SUBJ" failed "could not create worktree off $BASE_REF"
    echo "[autonomous-runner] run-task: ABORT $ID — worktree add failed (base $BASE_REF)"; return 1
  fi

  CB="$(resolve_claude)"
  if [ -z "$CB" ]; then cleanup_worktree "$WT" "$BRANCH"; emit "$ID" "$SUBJ" failed "no claude binary"; return 1; fi
  DPROMPT="You are an autonomous worker completing ONE backlog task in a git repo. Follow the repo's conventions and make MINIMAL, focused changes for exactly this task — nothing else.

Task ${ID}: ${SUBJ}
${DESC:+Description: $DESC}
${CTX:+Context: $CTX}

If you can complete it, do the edits, then end with one line: DONE: <one-line summary>.
If it needs a human decision first (ambiguous, risky, owner's choice), make NO changes and end with: NEEDSHUMAN: <what decision is needed>."
  # Dispatch inside a bwrap capability jail (ADR-062): the worktree is the only writable
  # host path, inherited secrets are cleared (env -i), and ~/.config/brana et al. are absent.
  # The git worktree isolates tracked files; the jail isolates the OS process.
  DOUT="$(printf '%s' "$DPROMPT" | sandbox_claude "$WT" -p --allowedTools "Read,Write,Edit,Bash" --output-format text 2>/dev/null)"

  # Verify gate (all checks scoped to the worktree). NEEDSHUMAN → park; empty diff / validate fail → failed.
  if printf '%s' "$DOUT" | grep -q "NEEDSHUMAN:"; then
    REASON_H="$(printf '%s' "$DOUT" | sed -n 's/.*NEEDSHUMAN: *//p' | head -1)"
    cleanup_worktree "$WT" "$BRANCH"; park "$ID" "$SUBJ" "${REASON_H:-needs human decision}"; return 2
  fi
  if [ -z "$(git -C "$WT" status --porcelain 2>/dev/null)" ]; then
    cleanup_worktree "$WT" "$BRANCH"; emit "$ID" "$SUBJ" failed "no changes produced"
    echo "[autonomous-runner] run-task: FAILED $ID (no changes) — worktree removed, base '$BASE_BRANCH' pristine"; return 1
  fi
  if ! ( cd "$WT" && eval "$VALIDATE_CMD" ) >/dev/null 2>&1; then
    cleanup_worktree "$WT" "$BRANCH"; emit "$ID" "$SUBJ" failed "verification failed ($VALIDATE_CMD)"
    echo "[autonomous-runner] run-task: FAILED $ID (validate) — worktree removed, base '$BASE_BRANCH' pristine"; return 1
  fi

  # Commit on the task branch (inside the worktree) — hooks run. Never merge, never mark completed.
  for gf in $GENERATED; do git -C "$WT" checkout -- "$gf" 2>/dev/null || true; done  # drop brana side-effect churn
  git -C "$WT" add -A
  # --no-verify (ADR-062 C2): never run the worktree's own .git/hooks on the host — a
  # prompt-injected agent could otherwise plant a malicious pre-commit and get host RCE.
  if ! git -C "$WT" commit -q --no-verify -m "feat(auto): ${SUBJ} (${ID})"; then
    cleanup_worktree "$WT" "$BRANCH"; emit "$ID" "$SUBJ" failed "commit rejected (hooks?)"; return 1
  fi
  emit "$ID" "$SUBJ" ran "committed on $BRANCH (validate ✓), awaiting human review"

  if [ "$PUSH" = "1" ] && command -v gh >/dev/null 2>&1; then
    git -C "$WT" push -u origin "$BRANCH" -q 2>/dev/null && \
      gh pr create --title "auto: ${SUBJ} (${ID})" --body "Autonomous runner. Task ${ID}. Verified by ${VALIDATE_CMD}. Human review + merge required." --base "$BASE_BRANCH" >/dev/null 2>&1 \
      && echo "[autonomous-runner] run-task: PR opened for $ID (base $BASE_BRANCH)" \
      || echo "[autonomous-runner] run-task: committed but PR push failed — branch $BRANCH is local"
  fi
  if [ "$FIXTURE_MODE" = "0" ] && command -v brana >/dev/null 2>&1; then
    brana backlog set "$ID" context "RUNNER: committed on $BRANCH $(date -u +%F) off $BASE_BRANCH, awaiting human review+merge" --append >/dev/null 2>&1 || true
  fi
  # Remove the worktree; the branch is left (with its commit) for human review. Base never touched.
  cleanup_worktree "$WT" ""   # keep the branch, drop only the worktree
  echo "[autonomous-runner] run-task: DONE $ID — committed on '$BRANCH' (base '$BASE_BRANCH'), worktree removed, NOT merged. Human review required."
  return 0
}

# ════════════════════════════════ STAGE 2: RUN-ONE ════════════════════════════
if [ "$MODE" = "run-one" ]; then
  # Pick the first eligible task (jq preserves array order).
  TASK="$(echo "$TASKS_JSON" | jq -c '[.[] | select(.status=="pending" and .execution=="autonomous" and (.priority//"")!="P0" and ((.blocked_by//[])|length==0))] | .[0] // empty' 2>/dev/null)"
  if [ -z "$TASK" ]; then echo "[autonomous-runner] run-one: no eligible task — nothing to do"; exit 0; fi
  run_task "$TASK"; rc=$?
  [ "$rc" = "1" ] && exit 1 || exit 0   # ran/parked = clean (0); only true failure is non-zero
fi

# ════════════════════════════════ STAGE 3: RUN-BATCH ══════════════════════════
# Loop run_task over a snapshot of eligible tasks (run_task leaves each pending, so we
# iterate the snapshot rather than re-pick first — avoids re-running the same task forever).
if [ -f "$KILL_SWITCH" ]; then
  echo "[autonomous-runner] run-batch: kill-switch present ($KILL_SWITCH) — aborting before any work"; exit 0
fi
# Concurrency lock (t-2144): a non-blocking flock serializes batch runs — a second overlapping
# --run-batch exits cleanly rather than double-running a task (run_task leaves tasks pending, so
# two batches over the same snapshot would otherwise both pick it). Released on process exit.
mkdir -p "$(dirname "$RUN_LOCK")" 2>/dev/null || true
exec 9>"$RUN_LOCK" 2>/dev/null || true
if command -v flock >/dev/null 2>&1 && ! flock -n 9; then
  echo "[autonomous-runner] run-batch: another batch holds the lock ($RUN_LOCK) — exiting"; exit 0
fi
ATTEMPTED=0; RAN=0; PARKED=0; FAILED=0; CONSEC=0
while IFS= read -r TASK; do
  [ -z "$TASK" ] && continue
  [ "$ATTEMPTED" -ge "$MAX_TASKS" ] && break
  if [ -f "$KILL_SWITCH" ]; then echo "[autonomous-runner] run-batch: kill-switch tripped mid-batch — stopping"; break; fi
  run_task "$TASK"; rc=$?
  ATTEMPTED=$((ATTEMPTED+1))
  case "$rc" in
    0) RAN=$((RAN+1));    CONSEC=0 ;;
    2) PARKED=$((PARKED+1)); CONSEC=0 ;;
    *) FAILED=$((FAILED+1)); CONSEC=$((CONSEC+1)) ;;
  esac
  if [ "$CONSEC" -ge "$MAX_FAILS" ]; then
    echo "[autonomous-runner] run-batch: KILL — $CONSEC consecutive failures (ADR-050 cap=$MAX_FAILS)"; break
  fi
done < <(echo "$TASKS_JSON" | jq -c '[.[] | select(.status=="pending" and .execution=="autonomous" and (.priority//"")!="P0" and ((.blocked_by//[])|length==0))] | .[]' 2>/dev/null)

if [ "$ATTEMPTED" = "0" ]; then echo "[autonomous-runner] run-batch: ALLDONE — no eligible tasks"; fi
echo "[autonomous-runner] run-batch: attempted=$ATTEMPTED ran=$RAN parked=$PARKED failed=$FAILED (cap=$MAX_TASKS, kill-at=$MAX_FAILS)"
echo "[autonomous-runner] ledger: $LEDGER"
exit 0
