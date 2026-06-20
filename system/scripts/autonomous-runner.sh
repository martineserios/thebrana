#!/usr/bin/env bash
# autonomous-runner.sh — native /loop-over-backlog autonomous runner (t-2140).
#
# STAGE 1: OBSERVE-ONLY. Selects eligible backlog tasks, plans each, and emits a JSONL
# ledger of decisions (would-run / would-park / excluded:<reason>). Makes ZERO mutations:
# no git writes, no `brana backlog set`, no `brana remind`. You watch its judgment before
# it ever earns write access (staged rollout — see docs/architecture/features/autonomous-runner.md).
#
# Native only — no ruflo. Modelled on system/scripts/feed-summarize.sh.
#
# Usage: ./system/scripts/autonomous-runner.sh --observe
# Env:
#   RUNNER_TASKS_JSON  task-source override (file path; for tests). Default: live backlog.
#   RUNNER_MAX_TASKS   batch cap (default 5)
#   RUNNER_PLAN        1=call claude -p per eligible task to plan would-run vs would-park
#                      (default 1); 0=skip (hermetic, no claude)
#   RUNNER_LEDGER      ledger output path (default ~/.claude/scheduler/runner-ledger-<date>.jsonl)
#   CLAUDE_BIN         claude binary (default ~/.local/bin/claude)
#
# Eligibility: status==pending ∧ execution==autonomous ∧ priority!=P0 ∧ blocked_by empty.
set -u

MODE="observe"
for a in "$@"; do case "$a" in --observe) MODE="observe" ;; esac; done

MAX_TASKS="${RUNNER_MAX_TASKS:-5}"
PLAN="${RUNNER_PLAN:-1}"
CLAUDE_BIN="${CLAUDE_BIN:-$HOME/.local/bin/claude}"
LEDGER="${RUNNER_LEDGER:-$HOME/.claude/scheduler/runner-ledger-$(date -u +%Y%m%d).jsonl}"
TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

mkdir -p "$(dirname "$LEDGER")"
: > "$LEDGER"   # fresh ledger per observe run

# ── Load tasks (fixture override for tests, else live backlog) ──────────────────
if [ -n "${RUNNER_TASKS_JSON:-}" ]; then
  TASKS_JSON="$(cat "$RUNNER_TASKS_JSON" 2>/dev/null || echo '[]')"
else
  TASKS_JSON="$(brana backlog query --status pending --output json 2>/dev/null || echo '[]')"
fi

emit() { # id subject decision reason
  jq -cn --arg id "$1" --arg s "$2" --arg d "$3" --arg r "$4" --arg ts "$TS" \
    '{id:$id,subject:$s,decision:$d,reason:$r,ts:$ts}' >> "$LEDGER"
}

# ── Per-task read-only plan: autonomously doable, or needs a human decision? ─────
plan_task() { # id subject  -> echoes "would-run <reason>" or "would-park <reason>"
  local id="$1" subj="$2"
  if [ "$PLAN" != "1" ]; then echo "would-run eligible"; return; fi
  local cb; cb="$CLAUDE_BIN"; [ -x "$cb" ] || cb="$(command -v claude 2>/dev/null || true)"
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

ELIG=0; RUN=0; PARK=0; EXCL=0; TAKEN=0

# Process substitution (not a pipe) so counters persist in this shell.
while IFS= read -r t; do
  [ -z "$t" ] && continue
  id="$(echo "$t"   | jq -r '.id // "?"')"
  subj="$(echo "$t" | jq -r '.subject // ""')"
  status="$(echo "$t" | jq -r '.status // ""')"
  execm="$(echo "$t" | jq -r '.execution // ""')"
  prio="$(echo "$t"  | jq -r '.priority // ""')"
  nblock="$(echo "$t" | jq -r '(.blocked_by // []) | length')"

  # Eligibility gate (default-deny).
  if [ "$status" != "pending" ];      then emit "$id" "$subj" excluded "not-pending ($status)"; EXCL=$((EXCL+1)); continue; fi
  if [ "$execm" != "autonomous" ];    then emit "$id" "$subj" excluded "not-autonomous (execution=$execm)"; EXCL=$((EXCL+1)); continue; fi
  if [ "$prio" = "P0" ];              then emit "$id" "$subj" excluded "p0 (never auto)"; EXCL=$((EXCL+1)); continue; fi
  if [ "$nblock" -gt 0 ];             then emit "$id" "$subj" excluded "blocked ($nblock blocker(s))"; EXCL=$((EXCL+1)); continue; fi

  ELIG=$((ELIG+1))
  # Batch cap (bounds).
  if [ "$TAKEN" -ge "$MAX_TASKS" ]; then emit "$id" "$subj" excluded "cap (RUNNER_MAX_TASKS=$MAX_TASKS)"; EXCL=$((EXCL+1)); continue; fi

  read -r decision reason < <(plan_task "$id" "$subj")
  emit "$id" "$subj" "$decision" "$reason"
  TAKEN=$((TAKEN+1))
  if [ "$decision" = "would-park" ]; then PARK=$((PARK+1)); else RUN=$((RUN+1)); fi
done < <(echo "$TASKS_JSON" | jq -c '.[]' 2>/dev/null)

echo "[autonomous-runner] mode=$MODE (OBSERVE — no changes made)"
echo "[autonomous-runner] eligible=$ELIG  would-run=$RUN  would-park=$PARK  excluded=$EXCL  (cap=$MAX_TASKS)"
echo "[autonomous-runner] ledger: $LEDGER"
exit 0
