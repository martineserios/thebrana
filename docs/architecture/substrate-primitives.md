# Agent Substrate — Primitives & Composition

**Status:** Design (2026-06-21, t-2184) · **Owner:** Martín Rios
**Index:** [the-orbit.md](the-orbit.md) (start here — the Orbit/Substrate map)
**Companion to:** [substrate-end-state](substrate-end-state.md) (the Orbit — autonomy tiers + safety net) · [ADR-059](decisions/ADR-059-multi-agent-substrate-selection.md) (substrate selection) · [substrate-leverage-audit](../research/substrate-leverage-audit.md) (empirical calibration) · [workflow-primitive](workflow-primitive.md) (Workflow API surface)

## Why this doc exists

ADR-059 picked *which* substrate to use for *which* job. [substrate-end-state](substrate-end-state.md) describes how autonomous agents *ship safely* (tiers, safety net, branch strategy). Neither describes the **building blocks others stack on**: what reusable primitives exist, what's missing, and the grammar by which they compose. This is that view — the foundation, from the bottom up.

The thesis: brana's multi-agent capability is **three substrate primitives + a small library of composed blocks + one trust mechanism**. Everything else is composition.

---

## 1. The primitive set

Three layers. Lower layers are runtime-provided; upper layers are brana-authored and stack on the lower.

### Layer 0 — Runtime substrate primitives (provided by CC / ruflo)

| Primitive | What it is | Unique power | Dies with session? |
|-----------|-----------|--------------|--------------------|
| **native Task** (Agent tool) | one subagent, in-session | quick parallel fan-out, inherits parent setup | yes |
| **native Workflow** | JS orchestration script spawning subagents deterministically | `pipeline`/`parallel` + schema-validated output + budget + resume | yes |
| **/loop + `claude -p`** | detached iteration over a queue (the [autonomous-runner](features/autonomous-runner.md)) | survives session end; backlog-native; fresh boot per iter | no — persistent |
| **ruflo memory / recall** | SQLite shared store (embeddings), no daemon | cross-session / cross-process shared state | no — persistent |

These four are the *only* execution substrates (ADR-059). ruflo MCP execution (`agent_execute`/`hive-mind_*`/`coordination_*`) is **never** used — hollow under subscription. agy (Gemini) appears in exactly one slot: the challenger's cross-model second opinion.

Workflow's exact contract (hooks, caps, failure semantics, resume) is documented once in [workflow-primitive](workflow-primitive.md) — not repeated here.

### Layer 1 — Composed blocks (brana-authored, in `.claude/workflows/`)

The reusable library. Each is a Workflow script; each composes Layer-0 primitives into a named, testable building block.

| Block | Shape | Calibration (t-2167, real tokens) |
|-------|-------|-----------------------------------|
| **hive-mind** | diverse-lens workers answer one question independently → each answer adversarially verified → synthesizer merges survivors | 7 agents, ~0.42M tok, ~4 min, 3/3 survived |
| **sweep** | read-only `Explore` finders each search a distinct angle → cluster near-duplicates (agreement = corroboration) → `verify-findings` judges each cluster | 41 agents, ~2.13M tok, ~11 min, 17 raw → 3 confirmed, 9 FPs killed |
| **verify-findings** | N diverse-lens skeptics per finding → strict-majority confirm or it drops to FALSE_POSITIVE → calibrated severity | the **canonical finding-verifier**; called by sweep + challenge --deep via `workflow()` |

Deterministic glue (clustering, coverage guard, confidence math, return shape) is covered by `.claude/workflows/tests/smoke.mjs` (mocks the runtime).

### Layer 2 — Skills that invoke blocks

Skills are the user-facing opt-in (`/brana:challenge --deep`, `/code-review ultra`, brainstorm evaluate). They satisfy the Workflow opt-in rule path 3 (user invoked a skill whose instructions call Workflow — see [workflow-primitive](workflow-primitive.md) §Opt-in). An agent deciding on its own that a task "would benefit" does **not** count.

### What's in the library vs what's missing

| Block | Status | Notes |
|-------|--------|-------|
| hive-mind | ✅ built | answer-one-question; keeps its *own* answer-verifier (verifies a free answer vs its claims — a different primitive from finding-severity; do not merge) |
| sweep | ✅ built | `exhaustive` loop-until-dry mode deliberately deferred (needs prior-round feedback to be real) |
| verify-findings | ✅ built | single source of truth for finding verification |
| **consensus** (cross-model) | ◻ designed, not built | [consensus-primitive](features/consensus-primitive.md) (t-2143) — build when a real decision-gate needs it |
| **judge-panel** | ✅ *is* verify-findings | not a separate block — verify-findings already is the judge panel |
| **tournament / bracket** | ✗ not designed | N attempts from different angles, scored pairwise, winner synthesized. Genuinely missing; file only when a wide solution-space task needs it |
| **self-repair loop** | ✗ not designed | generate → test → feed failures back → regenerate, until green. Missing; natural fit for the build loop's TDD inner cycle |
| **completeness critic** | ✗ not designed | a final agent asking "what's missing — modality not run, claim unverified?" Missing; cheap, high-leverage tail-catcher |

**Discipline:** missing blocks are filed on *first real need*, not pre-built. The library grew exactly this way (sweep built at need, exhaustive mode deferred). Pre-building primitives nobody calls is the anti-pattern.

---

## 2. The composition model

### The grammar

```
Layer 0 primitives  →  compose into  →  Layer 1 blocks  →  invoked by  →  Layer 2 skills
   (Task, Workflow,                    (hive-mind,                        (challenge --deep,
    /loop, memory)                      sweep,                             code-review ultra,
                                        verify-findings)                   brainstorm)
```

Two composition operators:
- **Within a Workflow** — `pipeline` (no barrier, default) and `parallel` (barrier). Default to `pipeline`; reach for a barrier only when a stage genuinely needs *all* prior-stage results (dedup across the full set, early-exit on zero, cross-item comparison).
- **Across blocks** — `workflow(nameOrRef, args)`, **one level of nesting only** (2 levels throws, by design). sweep → verify-findings is the validated example. This is a hard ceiling: a block that needs to call a block that calls a block must be flattened.

### The headline triad (the leverage move)

```
outer /loop  →  inner native Workflow  →  ruflo-memory blackboard
("until done")   ("parallel structured")    ("cross-iteration shared state")
```

Each autonomous iteration boots `claude -p`, which runs a native Workflow for parallel structured work, with a fixed ruflo-memory namespace as the cross-iteration blackboard (accumulation, dedup-vs-seen, hand-off). This composes **persistence × parallelism × shared-state** — no single substrate does it alone. Source: [substrate-leverage-audit](../research/substrate-leverage-audit.md) §Compose.

### When to fan out vs go sequential

| Use | When |
|-----|------|
| `parallel` / Task fan-out | independent sub-tasks, results needed together, in-session — cap is min(16, cores−2) |
| `pipeline` | multi-stage per-item work with no cross-item dependency (the default) |
| `/loop` (sequential, detached) | "until all done" over the backlog — never for parallel fan-out (serial boot tax makes it slow + pricey) |
| single reviewer (no block) | hardened, well-tested targets — see cost gate below |

### The cost gate (suppression, not amplification)

The blocks' real job is **suppression** — sweep killed 75% of raw findings (9/12 clusters were FPs). Their value is "don't waste attention on false alarms," not "surface more." Yield is **low on mature/tested code** (2.13M tokens → 3 OBSERVATION nits on a 40-test-covered script). Routing heuristic:

- **Reach for blocks on fresh / unreviewed targets** — new code, undecided designs.
- **On hardened code, a single reviewer is the better spend.**
- **Cost is real** (~0.4M tok/hive-mind question, ~2M/sweep of one file) — high-stakes only, never a default pass.

Persisted as `pattern_native-workflow-substrate-calibration` (auto-recall).

---

## 2b. Autonomy: two architectures, one definition of done

"Pick a backlog task → work it till done → next → until the list is empty" has **two valid implementations**, and they are not interchangeable. The axis that separates them is **whether a human is present**, not the word "autonomous."

```
  SAME GOAL: work the backlog until empty

  A — PERSISTENT SESSION LOOP            B — DETACHED RUNNER
  /loop (self-paced) + /goal + build     autonomous-runner.sh = bash loop
  + Workflow, in ONE live session        + a fresh `claude -p` PER task
  → /goal anchors AC: → build →          → isolated process + ephemeral
    Stop hook AUTO-COMPLETES → next         worktree → verify → commit →
                                            LEAVE PENDING → next
  the SUPERVISED tier (human nearby)      the UNATTENDED tier (human absent)
```

| | A — session loop | B — detached runner |
|---|---|---|
| Isolation per task | ❌ shared session | ✅ fresh process + worktree |
| Survives session end | ❌ | ✅ cron-able, overnight |
| Context | accumulates → rot/compaction | clean per task (boot-tax cost) |
| Completion | **auto-completes** (`/goal`) | **leaves pending** (human merge) |
| Containment story | weak (your live session) | the t-2173/t-2193 sandbox story |
| Right when… | **you're nearby** (grind this afternoon) | **you're asleep** (trustless, overnight) |

Both are worth having; they share **one backlog** and **one definition of done**.

### Definition of Done — a primitive with tier-specific bindings

"Explicit done-when criteria" is itself a substrate primitive. There is **one definition** — the task's `AC:` lines (machine-readable, author-set in the backlog) — and **two bindings** of it, chosen by human-presence:

```
  ONE definition (AC: lines)
    ├─ binding A (supervised loop):  /goal → Stop hook AUTO-COMPLETES   ← human present
    └─ binding B (detached runner):  AC → validate + build-evaluator → LEAVE PENDING ← human absent
```

`/goal` is the *interactive* binding — correct for A, an anti-pattern for B (headless `claude -p` runs no interactive Stop hook, and auto-completing unreviewed work on real code while no one watches is exactly the danger B's human-merge gate exists to prevent). Binding B is currently **unbuilt** — the runner's spec promises an AC check but `grep autonomous-runner.sh` for `AC:|evaluator|/goal` returns nothing (tracked as t-2193 C4).

**Security invariant shared by binding B and the sandbox work:** *the thing that checks the agent must live outside the agent's control.* The AC grader (validate + build-evaluator) must run from a **pinned base-ref copy**, never the agent-writable worktree — the same principle as t-2193 C3 (validate from base-ref) and t-2173 (sandbox the executor). One rule, enforced in three places. Default-deny: no `AC:` lines → not autonomous-eligible → routes to a human.

> Don't conflate the tiers: using A's auto-complete in B's unwatched context, or paying for B's per-task isolation when you're really just doing A's supervised grind, are both mistakes. Same backlog, same `AC:`, different binding — picked by presence.

---

## 3. Durability, reliability & trust

### Durability (built into Workflow)

- **Resume** — `{scriptPath, resumeFromRunId}`; the unchanged agent-call prefix returns cached results, only edited/new calls re-run. Same script + same args = 100% cache hit. (This is why `Date.now()`/`Math.random()` throw in scripts — they'd break resume.)
- **Budget governance** — `budget.total / spent() / remaining()` against a "+500k"-style directive; a hard ceiling, not advisory. Use for dynamic loops (`while budget.remaining() > 50_000`) or static fleet scaling. The pool is shared across the main loop and all workflows.
- **Failure semantics** — erroring/skipped agents resolve to `null` (filter with `.filter(Boolean)`); a throwing pipeline stage drops that one item and skips its remaining stages. The call never rejects — partial results are the norm, design for them.

### The trust mechanism (load-bearing)

**Adversarial-verify is what makes the substrate real.** The verify phase is *evidence-anchored, not self-voting* — this is the single property that separates it from the hollow ruflo MCP layer (which records + self-votes with `totalNodes:1`). Live evidence (t-2167): verify-findings **refuted a factually-false worker claim** ("validate.sh never executes changed code" — wrong, Check 46 runs `cargo test --no-run`) and **downgraded a finder's CRITICAL to OBSERVATION** grounded in "0/2057 tasks lack an id."

Design implications:
- Every finding-producing block must end in a verify pass. Trust the survivors; distrust raw finder output.
- Verifiers get **distinct lenses** when a finding can fail multiple ways (correctness, security, repro), not N identical skeptics — diversity catches failure modes redundancy can't.
- A finding holds only on **strict majority**; ties and majority-refute both drop to FALSE_POSITIVE.

### The worktree-persistence gotcha

A Workflow worktree where an agent *committed* survives the run under `.claude/worktrees/wf_*`, holding its branch checked out — blocking later `git checkout`/worktree of that branch. Crews must end with an explicit release, or the dispatcher sweeps before re-dispatching. (Auto-removal is literal: only *unchanged* worktrees auto-clean.) Source: [workflow-primitive](workflow-primitive.md) §Field Notes.

### Security / capability isolation (a HARD precondition for unattended autonomy)

The substrate's own hive-mind surfaced the riskiest assumption: **git-worktree isolation ≠ process/capability isolation** ([t-2173], filed by the substrate about itself). The runner dispatches `claude -p --allowedTools "...,Bash"` with Bash **unscoped**; non-git side effects — network egress, `$HOME` writes, secret reads, `rm`, `git push` — escape every gate (all gates only inspect the worktree's *tracked* diff). The higher-probability threat is **prompt injection via task fields** (subject/description/AC are backlog-author-controlled and flow into the executor prompt).

Primitive-level mitigations:
- **Read-only by construction** — sweep finders run as `Explore` agents (no Write/Edit), so a discovery sweep *cannot* mutate its target. Prefer read-only blocks wherever the job is discovery/judgment.
- **Write-capable blocks need the capability boundary** — an OS sandbox/container with no host-credential mount + egress block, or a Bash command allowlist. This is t-2173, a HARD precondition before any unattended `--run-batch`. Today's runner is human-supervised (`--run-one` leaves the branch for review), so it is gated, not blocked.

---

## 4. Plug-points into the rest of the system

| System | How the substrate plugs in |
|--------|----------------------------|
| **Autonomous runner** ([t-2140], built) | the outer-loop tier — `/loop`-over-backlog; each iteration *may* run an inner Workflow for heavy per-task work (the triad). Runner owns the staged-trust pipeline ([substrate-end-state](substrate-end-state.md)). |
| **Backlog** | the queue source for the outer loop, *and* the blackboard's durable counterpart — blocks read tasks as work-lists and write findings back as child tasks. Reached only via brana-core (flock-guarded, t-2168). |
| **Skills** | Layer 2 — the user-facing opt-in. `challenge --deep` → sweep + verify-findings; `code-review ultra`; brainstorm evaluate. Skills are the *only* legitimate in-session trigger (opt-in path 3). |
| **Memory** | ruflo-memory as the cross-iteration / cross-session blackboard (fixed namespace + path; CWD-scoped by default). The one irreplaceable ruflo piece. |
| **Context governance** ([t-2176]) | the substrate's context envelope (MCP tool defs 30–70K, compaction buffer) is governed there, not here. Tool Search ([t-2181]) is the real 10× lever; on-demand tool schemas keep Workflow agents' context lean. |

---

## 5. Open questions & disposition

ADR-059's open questions:
1. **Autonomous tier: autopilot vs native /loop?** → **RESOLVED** — native `/loop + claude -p` over the backlog (t-2140, built). Evidence in the audit.
2. **Expose sweep now or on first need?** → **RESOLVED** — built now; exhaustive mode deferred.

New questions this design surfaces (each routed):
| Question | Disposition |
|----------|-------------|
| Which missing blocks (tournament, self-repair, completeness critic) to build, and when? | **child task** — file as a tracked "primitive library gaps" backlog item; build on first real need, not speculatively |
| Capability isolation before unattended `--run-batch` | **owned by [t-2173]** (pending) — HARD precondition; referenced, not re-opened here |
| Context envelope governance for Workflow fleets | **owned by [t-2176]/[t-2181]** (pending) — referenced |
| Consensus primitive: build trigger | **owned by [t-2143]** (designed) — build when a decision-gate needs it |

---

> The durable engine ([substrate-end-state](substrate-end-state.md) §The engine): **build → turn the substrate's own adversarial blocks on the new work → fix what they find → ship.** This doc is the parts list for the blocks that do the finding. The library stays small on purpose — three primitives, three blocks, one trust mechanism — and grows only when a real task proves a gap.
