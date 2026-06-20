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
# Env (--run-batch adds):
#   RUNNER_MAX_FAILS     consecutive-failure kill threshold (default 3, ADR-050 cap)
#   RUNNER_KILL_SWITCH   abort if this file exists (default ~/.claude/scheduler/runner.stop)
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

revert_to_base() { # branch base — revert work, return to base, drop the branch (no ledger emit)
  git reset --hard -q 2>/dev/null || true
  git clean -fdq 2>/dev/null || true
  [ -n "$2" ] && git checkout -q "$2" 2>/dev/null || true
  git branch -D "$1" -q 2>/dev/null || true
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

# run_task <task-json> — isolate, dispatch, verify, commit one task. STOPS (no merge, no
# completed-mark). Returns: 0=ran, 2=parked (needs human), 1=failed (reverted, base pristine).
run_task() {
  local TASK="$1" ID SUBJ DESC CTX DECISION REASON BASE BRANCH CB DPROMPT DOUT REASON_H
  ID="$(echo "$TASK" | jq -r '.id')"; SUBJ="$(echo "$TASK" | jq -r '.subject // ""')"
  DESC="$(echo "$TASK" | jq -r '.description // ""')"; CTX="$(echo "$TASK" | jq -r '.context // ""')"

  # Plan gate: only run a would-run; park a would-park (clean outcome, not a failure).
  read -r DECISION REASON < <(plan_task "$ID" "$SUBJ")
  if [ "$DECISION" = "would-park" ]; then park "$ID" "$SUBJ" "$REASON"; return 2; fi

  # Preflight: working tree clean (modulo generated churn) so we can isolate + revert cleanly.
  drop_generated
  if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
    emit "$ID" "$SUBJ" failed "working tree not clean"
    echo "[autonomous-runner] run-task: ABORT $ID — working tree not clean"; return 1
  fi
  BASE="$(git branch --show-current 2>/dev/null)"
  BRANCH="${BRANCH_PREFIX}/${ID}"

  git checkout -b "$BRANCH" -q 2>/dev/null || {
    emit "$ID" "$SUBJ" failed "could not create branch $BRANCH"
    echo "[autonomous-runner] run-task: ABORT $ID — could not create branch"; return 1; }

  CB="$(resolve_claude)"
  if [ -z "$CB" ]; then revert_to_base "$BRANCH" "$BASE"; emit "$ID" "$SUBJ" failed "no claude binary"; return 1; fi
  DPROMPT="You are an autonomous worker completing ONE backlog task in a git repo. Follow the repo's conventions and make MINIMAL, focused changes for exactly this task — nothing else.

Task ${ID}: ${SUBJ}
${DESC:+Description: $DESC}
${CTX:+Context: $CTX}

If you can complete it, do the edits, then end with one line: DONE: <one-line summary>.
If it needs a human decision first (ambiguous, risky, owner's choice), make NO changes and end with: NEEDSHUMAN: <what decision is needed>."
  DOUT="$(printf '%s' "$DPROMPT" | timeout 600 "$CB" -p --allowedTools "Read,Write,Edit,Bash" --output-format text 2>/dev/null)"

  # Verify gate. NEEDSHUMAN → park (not a failure); empty diff / validate fail → failed.
  if printf '%s' "$DOUT" | grep -q "NEEDSHUMAN:"; then
    REASON_H="$(printf '%s' "$DOUT" | sed -n 's/.*NEEDSHUMAN: *//p' | head -1)"
    revert_to_base "$BRANCH" "$BASE"; park "$ID" "$SUBJ" "${REASON_H:-needs human decision}"; return 2
  fi
  if git diff --quiet && git diff --cached --quiet; then
    revert_to_base "$BRANCH" "$BASE"; emit "$ID" "$SUBJ" failed "no changes produced"
    echo "[autonomous-runner] run-task: FAILED $ID (no changes) — reverted, base '$BASE' pristine"; return 1
  fi
  if ! ( eval "$VALIDATE_CMD" ) >/dev/null 2>&1; then
    revert_to_base "$BRANCH" "$BASE"; emit "$ID" "$SUBJ" failed "verification failed ($VALIDATE_CMD)"
    echo "[autonomous-runner] run-task: FAILED $ID (validate) — reverted, base '$BASE' pristine"; return 1
  fi

  # Commit on the task branch — hooks run. Never merge, never mark task completed.
  drop_generated   # don't fold brana side-effect churn into the task commit
  git add -A
  git commit -q -m "feat(auto): ${SUBJ} (${ID})" || {
    revert_to_base "$BRANCH" "$BASE"; emit "$ID" "$SUBJ" failed "commit rejected (hooks?)"; return 1; }
  emit "$ID" "$SUBJ" ran "committed on $BRANCH (validate ✓), awaiting human review"

  if [ "$PUSH" = "1" ] && command -v gh >/dev/null 2>&1; then
    git push -u origin "$BRANCH" -q 2>/dev/null && \
      gh pr create --title "auto: ${SUBJ} (${ID})" --body "Autonomous runner. Task ${ID}. Verified by ${VALIDATE_CMD}. Human review + merge required." --base "$BASE" >/dev/null 2>&1 \
      && echo "[autonomous-runner] run-task: PR opened for $ID" \
      || echo "[autonomous-runner] run-task: committed but PR push failed — branch $BRANCH is local"
  fi
  if [ "$FIXTURE_MODE" = "0" ] && command -v brana >/dev/null 2>&1; then
    brana backlog set "$ID" context "RUNNER: committed on $BRANCH $(date -u +%F), awaiting human review+merge" --append >/dev/null 2>&1 || true
  fi
  # Return to base so the loop/caller resumes cleanly; the task branch is left for review.
  [ -n "$BASE" ] && git checkout -q "$BASE" 2>/dev/null || true
  echo "[autonomous-runner] run-task: DONE $ID — committed on '$BRANCH', base '$BASE' untouched, NOT merged. Human review required."
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
