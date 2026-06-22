# the Orbit — Autonomous-Agent Operation (End-State Design)

**Status:** Design capstone (2026-06-20) · **Owner:** Martín Rios
> **This is the Orbit capstone** — the autonomous *operation* that runs on the Substrate. The filename (`substrate-end-state`) predates the Substrate/Orbit vocabulary and is kept to preserve inbound links. Start at the index: [the-orbit.md](the-orbit.md).

**Ties together:** [ADR-059](decisions/ADR-059-multi-agent-substrate-selection.md) (substrate selection) · [ADR-060](decisions/ADR-060-branch-strategy-autonomous-agents.md) (branch strategy) · [ADR-050](decisions/ADR-050-loop-request-protocol.md) (autonomy caps) · [autonomous-runner](features/autonomous-runner.md) · [learned-eligibility](features/learned-eligibility.md) · [consensus-primitive](features/consensus-primitive.md) · [substrate-leverage-audit](../research/substrate-leverage-audit.md)

## One system, for all work

brana's multi-agent substrate is **one development system** run across every repo (thebrana, clients/*, ventures/*, personal/*). The goal is **quality work at speed and scale**: invariants buy quality + scale; worktree parallelism + a fast integration line buy speed. **brana is the first adopter of its own system** — it dogfoods, which is why turning the substrate on its own code (sweep/hive-mind/challenger) found and fixed real bugs during this very build.

## The tiers (ADR-059)

| Tier | Substrate | Use |
|------|-----------|-----|
| In-session, quick parallel | **native Task** (Agent tool) | fan-out investigation, scouts |
| In-session, structured | **native Workflow** (`.claude/workflows/`) | deterministic find→verify→synthesize: `hive-mind`, `verify-findings`, `sweep` |
| Autonomous / overnight | **native loop** (`autonomous-runner.sh` + `claude -p`) | "work the backlog until done" |
| Shared memory | **ruflo memory / recall** | cross-session/agent recall (the only load-bearing ruflo piece) |
| Cross-model second opinion | **agy (Gemini)** | challenger diversity only |

ruflo MCP execution (`agent_execute`/`hive-mind_*`/`coordination_*`) is **never** used — hollow under subscription.

## The autonomous runner — staged trust

```
Stage 1 OBSERVE      ✅ built — judge eligibility, zero writes
Stage 2 RUN-ONE      ✅ built — one task, worktree-isolated, PR, human merges
Stage 3 RUN-BATCH    ✅ built — bounded batch, lock, kill-switch
Stage 4 LEARNED      ◻ designed (learned-eligibility.md) — built after soak
```

## The safety net (composed, in dependency order)

Every layer landed this build except where noted:
1. **Worktree-per-actor isolation** (t-2146) — agent works in an ephemeral worktree off the integration branch; live tree + base never touched; resolves detached-HEAD by construction.
2. **`--run-batch` lock** (t-2144) — no concurrent double-run.
3. **Secret-scan gate** (t-2138) — pre-commit + PreToolUse; an autonomous commit can't leak a token (the `xoxb-` incident is what proved this non-optional).
4. **Consecutive-failure kill + cost/iteration caps** (t-2140, ADR-050).
5. **Invariant test suite** (t-2150) — one test per safety property, incl. adversarial edges.
6. **Human merge gate** (ADR-060) — **ground control**: agents PR into `dev`, never touch production; nothing leaves the Orbit until the human promotes `dev → main` = ship.
7. **bootstrap from-main guard** (t-2151) — production deploy only from `main`.
8. **Session-unit alignment** (t-2152/t-2154) — handoffs route by the same unit key (task→branch→session), so session state obeys ADR-060 invariant #4 too.

## Branch strategy (ADR-060) — universal invariants + per-project policy

- **Universal (all repos):** agent never pushes production; works in an isolated worktree off the integration branch; human-gated promotion; never auto-merge/complete.
- **Per-project:** integration vs production branch declared per repo (`RUNNER_BASE_BRANCH` / `.claude/CLAUDE.md` `integration=`, default `dev`). brana's instance = two-tier `dev`→`main` (main = bootstrap-deployed production).

## Resolved open questions (ADR-060)

1. **validate as the merge gate** → **local pre-merge for now** (validate.sh already runs); GitHub Actions required-status-check deferred until CI exists / a collaborator joins.
2. **`dev` as GitHub default** → **no** — `main` stays default; `dev` is the integration branch (avoids retargeting PRs / breaking push automation).
3. **Per-project policy schema** → an `integration=<branch>` marker in the repo's `.claude/CLAUDE.md` (human-authored Layer 1); the runner falls back to `dev` when absent. (Brana needs no marker — default suffices.)

## Operating the Orbit

The Orbit has **two tiers, split by one question — are you present?** Both work the
same backlog to the same definition of done (the task's `AC:` lines); they differ only
in *binding*. The two architectures are formalized in
[substrate-primitives §2b](substrate-primitives.md#2b-autonomy-two-architectures-one-definition-of-done) —
this is how you *operate* each.

### Supervised — you're nearby (the session loop)

An in-session grind: native `/loop` (self-paced) + `/goal` + `/brana:build` + `Workflow`,
all in **one live session**. `/goal` anchors the task's `AC:` and iterates
build-until-condition; the Stop hook **auto-completes** the task; on to the next. You
watch it happen and can interrupt on any turn.

- **Front door:** existing surfaces — `/brana:build` under a self-paced `/loop`, with
  `/goal` holding the stop condition. No new command; it's composed native primitives.
- **Completion:** auto-completes (`/goal` + Stop hook) — safe *because you're watching*.
- **Status:** the three-primitive composition (`/loop` POLL · `/goal` ITERATE ·
  `Workflow` FAN-OUT) is **designed** — see [ADR-061](decisions/ADR-061-goal-integration-three-primitive.md) (accepted 2026-06-21, t-2194). Build tasks: t-2204 → t-2205 → t-2206 → t-2207.

### Unattended — you're away (the detached runner)

A headless bash loop (`system/scripts/autonomous-runner.sh`) spawning a fresh `claude -p`
per task in an ephemeral worktree. Three modes of escalating trust:

| Mode | Command | Does | Writes? |
|------|---------|------|---------|
| Observe | `autonomous-runner.sh --observe` | pick eligible tasks, plan each, emit `would-run`/`would-park`/`excluded` to a ledger | none — read-only |
| Run-one | `autonomous-runner.sh --run-one` | run the first eligible task in a worktree → verify → commit on `runner/auto/<id>` → stop | one branch |
| Run-batch | `autonomous-runner.sh --run-batch` | loop run-one over the eligible snapshot, all bounds + kill-switch active | branch-per-task |

**Eligible** = `execution: autonomous` ∧ not P0 ∧ unblocked ∧ lint-clean. Everything
else is excluded with a reason.

**Arm it** via the scheduler: a disabled `autonomous-runner` job ships in `brana ops`
(default-deny). `brana orbit enable` flips `enabled=true` and swaps its arg
`--observe`→`--run-batch` (or do it by hand); `brana orbit disable` reverses both. The
bounds below apply automatically.

**Bounds & stop (always on for a batch):**
- batch cap — `RUNNER_MAX_TASKS` (default 5)
- consecutive-failure kill — stops after `RUNNER_MAX_FAILS` (default 3) in a row (ADR-050)
- per-task timeout — 600s
- **kill-switch** — `brana orbit stop` (or `touch ~/.claude/scheduler/runner.stop`) halts a
  running batch cleanly and blocks a new one from starting; `brana orbit stop --clear`
  re-arms

**Completion:** never self-completes — commits land on `runner/auto/<id>`, tasks stay
`pending`, and **you merge** (ground control). With `RUNNER_PUSH=1` each task opens a PR
to `dev` via `gh`. A task hitting a human-only decision is **parked**: a high-priority
`needs-human` reminder + a `PARKED` note, and the batch moves on.

> **Front-door:** `brana orbit observe | run [--one] [--push] [--max-tasks N] | enable |
> disable | stop [--clear] | status` fronts the unattended tier (t-2197) — a thin control
> surface, not a reinvention: the script stays the engine, the `brana ops` scheduler stays
> the host. `observe`/`run` invoke the runner; `enable`/`disable` arm/disarm the scheduler
> job; `stop [--clear]` toggles the kill-switch; `status` reports job state + kill-switch +
> the latest ledger summary. The raw script and the `RUNNER_*` env-vars remain available and
> unchanged underneath — a flag only sets a var when given, so script defaults are never
> duplicated.

> **Don't cross the tiers:** `/goal`'s auto-complete is correct when you're watching and a
> footgun when you're not — auto-merging unreviewed work overnight is exactly what the
> human gate prevents. Same backlog, same `AC:`, different binding — picked by presence.

## What remains (designed, not built)

- **Stage 4 learned eligibility** (t-2142) — gated on the Stage 1-3 soak producing a track record.
- **Consensus primitive** (t-2143) — built when a real decision-gate needs it.
- **Team mode** (ADR-060) — required-PR / CODEOWNERS / merge-queue, flipped on when a collaborator joins; topology unchanged.

## The engine

The durable pattern this substrate encodes: **build → turn the substrate's own adversarial tools on the new work → fix what they find → ship.** The system that finds the bugs and the system being fixed are the same system. That recursive loop is how brana makes itself better — and, run in any repo, how it delivers quality work at speed and scale.
