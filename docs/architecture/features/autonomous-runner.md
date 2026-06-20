# Feature Spec — Autonomous Task Runner

**Task:** t-2140 · **Status:** spec (Stage 1 in build) · **Date:** 2026-06-20
**Basis:** ADR-059 (substrate selection) · [substrate-leverage-audit](../../research/substrate-leverage-audit.md) · ADR-050 (autonomy caps)

## Problem

brana needs an autonomous tier — "keep working through the backlog until done / overnight." The substrate audit settled the *how*: **native `/loop + claude -p` over the backlog**, not ruflo (autopilot/`--claude`/MCP are redundant or hollow under subscription). This spec defines a *safe, staged* runner that integrates with existing brana machinery instead of reinventing it.

## Principles

1. **Native only.** Zero ruflo execution. (`backlog execute` is ruflo-FIRST and would silently under-execute on the subscription — so the runner is a thin native loop, not a wrapper around it.)
2. **Autonomy earns write access — it isn't granted.** Roll out in trust-earning stages; give write access last.
3. **Defer, don't guess or halt.** When a task needs a human-only decision, park a question and continue with other tasks.
4. **Reuse the system.** Lean on existing hooks, gates, and CLI; add only the thin delta.

## Decisions (locked)

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Eligibility | `execution: autonomous` **+ not P0** + unblocked + lint-clean | Default-deny, whitelist-in. Reach expands later via learning (t-2142). |
| Output | branch + PR per task; **human merges** | ADR-050 (merges human-gated); isolated, revertable, reviewable units. |
| Shared state | **native only** — backlog + ledger files | Minimal dependencies; no ruflo coupling. |
| Verification | `validate.sh` **+ AC check** (build-evaluator vs task `AC:` lines) | Catches "ran but did the wrong thing", not just structural breakage. |
| Failure policy | consecutive-failure **kill at 3** (ADR-050 cap), per-task timeout, batch cap, cost ceiling | Bounded blast radius. |

## Staged rollout (the safety backbone)

```
Stage 0  DESIGN (this spec)
Stage 1  OBSERVE-ONLY   ← picks eligible tasks, PLANS per task, reports would-run /
                          would-park / excluded. ZERO mutations. You watch its judgment.   ← THIS BUILD
Stage 2  SINGLE-TASK    ← runs ONE eligible task → PR → stops. Human reviews. (t-TBD)
Stage 3  BOUNDED BATCH  ← many tasks/run, all bounds + kill-switch, PR-per-task. (t-TBD)
Stage 4  LEARNED        ← graduates task shapes to auto-eligible from track record. (t-2142)
```

Each stage is gated by the prior earning trust. Stage 1 proves *judgment* (right task pick, right done-vs-park call) **before** the runner can touch a file.

## Reuse map (free, already in brana)

| Need | Reuse |
|------|-------|
| Loop template | `system/scripts/feed-summarize.sh` pattern (cap, `timeout claude -p`, per-item skip) |
| Eligibility gate | `brana backlog lint` + `execution: autonomous` marker |
| Quality gate | `validate.sh` (non-zero = task failed) — Stage 2+ |
| Question queue | `brana remind write --tags "runner-question,needs-human" --task-id t-NNN` — Stage 2+ |
| Commit safety | existing hooks (attribution, secrets, budget, doc-gate, branch-guard) — automatic |
| Scheduling | `brana ops` job — Stage 3+ |
| Governance | ADR-050 caps |

## Stage 1 — Observe-only (this build)

`system/scripts/autonomous-runner.sh --observe`

**Does:** load pending tasks → filter to eligible (`execution:autonomous` ∧ `priority≠P0` ∧ unblocked) → cap to `RUNNER_MAX_TASKS` → per task, emit a planned **decision** (`would-run` / `would-park` / `excluded:<reason>`) to a JSONL **ledger** → print a summary.

**Must NOT (observe invariant):** no `brana backlog set`, no `git` writes, no `brana remind write`, no edits to the repo or tasks.json. Read + ledger-write only.

**Interfaces / env (for testability + ops):**
- `RUNNER_TASKS_JSON` — task source override (test fixture); default `brana backlog query --status pending --output json`
- `RUNNER_MAX_TASKS` — batch cap (default 5)
- `RUNNER_LEDGER` — ledger output path (default under `~/.claude/scheduler/`)
- `RUNNER_PLAN` (0/1) — whether to call `claude -p` for per-task planning (default 1); `CLAUDE_BIN` overridable for tests
- exit 0 always on a clean observe pass (it's read-only)

**Eligibility (exact):** `status == "pending"` ∧ `execution == "autonomous"` ∧ `priority != "P0"` ∧ (`blocked_by` empty/null). Everything else → `excluded:<reason>`.

## Testing

`system/scripts/tests/test-autonomous-runner.sh` (TDD — written first):
- eligible task → `would-run`
- P0-autonomous → `excluded:p0`
- blocked-autonomous → `excluded:blocked`
- non-autonomous → `excluded:not-autonomous`
- `RUNNER_MAX_TASKS` cap respected
- **observe invariant:** task source unchanged, no reminder file written, no git mutation

Runs with `RUNNER_PLAN=0` (no `claude` call) for a hermetic, fast test.

## Stage 2 — Single-task supervised (this build)

`system/scripts/autonomous-runner.sh --run-one`

**Does:** select the **first** eligible `would-run` task (cap 1) → isolate on a per-task branch → dispatch `claude -p` (scoped `Read,Write,Edit,Bash`, build-discipline prompt) to do the work → **verify** → commit on the branch → **stop**. Never merges (ADR-050: human-gated). Never marks the task `completed` (human gates that too — runner leaves it for review).

**Verification gate (all must hold to commit):**
1. dispatch did not return `NEEDSHUMAN:` (else park + abort, no commit),
2. the working tree actually changed (empty diff = nothing done → abort),
3. `RUNNER_VALIDATE_CMD` (default `./validate.sh`) passes,
4. (best-effort) AC check if the task has `AC:` lines.

**Failure invariant (the critical safety property):** on *any* failure — `NEEDSHUMAN`, empty diff, validate fail, dispatch error — the runner **reverts the working tree, returns to the base branch, and deletes the task branch.** No partial commits, base branch always pristine.

**Output:** a commit on `RUNNER_BRANCH_PREFIX/<id>` (default `runner/auto/<id>`). With `RUNNER_PUSH=1` it also opens a PR via `gh`. Default is local-branch-only (no remote needed).

**Env (adds to Stage 1):** `RUNNER_VALIDATE_CMD` · `RUNNER_PUSH` (0/1) · `RUNNER_BRANCH_PREFIX`. brana mutations (remind/set) are skipped when `RUNNER_TASKS_JSON` is set (fixture/test mode) — keeps tests hermetic.

**Tests** (`test-autonomous-runner-stage2.sh`, hermetic temp git repo, stub claude + stub validate):
- would-run task → change made, validate passes → commit exists on task branch, base branch has no new commit, task not `completed`
- stub returns `NEEDSHUMAN` → no commit, base branch pristine, branch deleted
- stub makes no change → no commit, clean abort
- validate fails → working tree reverted, no commit, back on base branch
- would-park task → not executed at all

## Follow-ups

- Stage 3 (bounded batch + `brana ops` hosting) — file when Stage 2 trusted.
- Stage 3 (bounded batch + `brana ops` hosting).
- t-2142 (learned eligibility).
- Wire the leverage doctrine into `delegation-routing.md` once the runner exists.
