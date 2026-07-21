---
title: Skills as Loops — recipes re-derived under the v3 loop model
status: seed
created: 2026-07-20
feeds: "[brana-v3 redesign](brana-v3-redesign.md) — extends wave 4 (router) and wave 5 (core/packs cut)"
relates-to:
  - "[backlog-v3 schema](../architecture/features/backlog-v3-schema.md) (waves = drainable queues)"
  - "[32-lifecycle Discovery/Shaping](../reflections/32-lifecycle.md)"
  - "[loop-engineering + Pi research](../research/loop-engineering-and-pi.md) (github.com/cobusgreyling/loop-engineering)"
---

# Skills as Loops

> Seed from the 2026-07-20 session (post schema-challenge discussion). Not yet brainstormed — park here, shape via `/brana:brainstorm skills-as-loops`, graduate into the v3 epic plan.

## The reframe

**A recipe is a loop unrolled once.** What separates a skill-as-recipe from a skill-as-loop is not shape but three explicit properties (all v3 principles):

1. an **encoded stop condition** (not "the human notices we're done")
2. an **independent verifier** (not the worker grading itself)
3. a **queue to drain** (a wave selector, per the v3 schema)

Any skill with all three can run as a loop at whatever autonomy rung its shape has earned (L1/L2/L3). Any skill missing one is a recipe whose stop condition is a human — which is fine, *when chosen deliberately*.

## The latent loop hierarchy (already in the system)

| Size | Loop | Body | Stop condition |
|---|---|---|---|
| micro | red-green-refactor | one assertion | test green |
| task | `/brana:build` | one task | AC met + validate.sh |
| drain | wave: `while wave.next(): work()` | one task | wave empty |
| epic | epic lifecycle | one wave | contract met (empty + `AC:`) |
| meta | LEARN / graduation / process loop | one outcome row | queue drained / rule table |

Existing skills map onto this: `fix` = task loop with repro-test verifier · `challenge` = find→verify loop · `close` extraction = the LEARN meta-loop's producer · `brainstorm` = a deliberately human-stop-condition loop (rounds + exit gate) and should stay one.

## Loops calling loops — three shapes, five safety rules

**Shapes:** (1) **nesting** — a loop's body *is* a smaller loop (wave-drain calls build calls red-green); (2) **chaining** — a wave selector references another wave's output (triage → fix → verify; Green-hat alt #11 from the schema challenge — requires cycle detection); (3) **spawning** — a loop enqueues for another loop (cockpit parks NEEDSHUMAN; close enqueues for LEARN). Prefer spawning > nesting > chaining.

**Safety rules:**
1. **Budgets flow down, never multiply** — parent owns the ceiling, children draw from it (the native Workflow budget-pool model).
2. **Autonomy of a composition = min of its parts** — an L3 outer calling an L2-capped inner makes the chain L2; nesting must never launder autonomy past the ladder.
3. **Depth cap encoded** — copy native Workflow's one-level nesting rule; two levels deep is better expressed as spawning through a queue.
4. **One ledger, attributed chain** — the `log`'s `by:` carries the loop chain (`loop:wave-drain>build`) so verdict rows attribute graduation evidence unambiguously.
5. **Stop conditions compose, parent wins** — wave-empty halts the inner loop cleanly (finish current item, start no next); consecutive-failure kill at any level kills the whole chain.

## The exit-router pattern (first concrete instance: brainstorm)

Skills stop ending in prose ("consider running X next") and end in a **ROUTE step**: an AskUserQuestion whose options are computed from state, whose recommended option is the pipeline's next stage, and whose selection *invokes* the next skill. First instance — brainstorm Phase 5d:

```
"The idea is saved. Next move?"
  ▸ Challenge it first        → challenge (M+ → --deep)     [when: shape locked, never challenged]
  ▸ Graduate: spec + ADR(s)   → the lifecycle front door    [when: challenged or S-effort]
  ▸ Plan into backlog         → backlog plan                [when: spec exists or < M]
  ▸ Park it                   → stays in docs/ideas, resumable
```

This closes a live drift: 32-lifecycle now specifies idea → spec+ADR → plan, but brainstorm's current exit (5b) jumps idea → plan, and challenge is never offered (v3 itself needed it invoked by hand, twice). The existing 5b backlog question folds into the router; the M+ governance gate moves to fire at "Plan into backlog."

## Loop-engineering grounding (Cobus Greyling — the examples menu)

Already swept in [loop-engineering-and-pi.md](../research/loop-engineering-and-pi.md); what this idea borrows directly:

- **Loop anatomy checklist** — the six components (scheduling · worktrees · skills · connectors · sub-agent verifiers · durable state) become the audit rubric when re-deriving a skill as a loop: which components does the skill already have, which is it missing? Brana converged on ~5 of 6; the recurring gap is the **maker/checker split** (worker self-grades).
- **Encoded stop conditions, none optional:** goal-achieved (human-verified) · iteration cap · non-recoverable error → escalate · cost threshold · state drift. This is the concrete checklist behind property (1) above — a skill's ROUTE/CLOSE step should declare all five or name why one doesn't apply.
- **The 7 production patterns as brana loop candidates**, mapped to surfaces that already exist:

  | loop-engineering pattern | brana loop | queue | rung today |
  |---|---|---|---|
  | Daily Triage | inbox/feed processing (`brana feed`/`inbox`) | research-inbox triage wave | L1 |
  | Issue Triage | backlog AC-backfill (`ac_state: none → proposed`) | AC-backfill wave | L2 (cockpit approves) |
  | PR Babysitter | pr-reviewer agent + post-PR hooks | open PRs | L1→L2 |
  | CI Sweeper | validate.sh / test-failure drain | `kind:fix ∧ shape:mechanical` (bug-drain wave) | L2 |
  | Dependency Sweeper | cargo-machete / dep upgrades | standing chore wave | L2 |
  | Changelog Drafter | `/brana:docs` living-doc updates | docs tasks blocked_by impl | L2 |
  | Post-Merge Cleanup | worktree remove + branch -d + task close (build CLOSE) | merged branches | L2, near-L3 |

- **Comprehension debt** stays a first-class risk (already in v3's risk table): every skill-turned-loop keeps its ledger human-readable — the `log` verdict rows are the antidote, not dashboards.

## Example catalogs (2026-07-20 two-scout sweep)

Deep catalogs persisted as research docs — the raw material for the brainstorm:

- **[loop-engineering examples catalog](../research/loop-engineering-examples-catalog.md)** — the repo mined fully: per-pattern stop conditions/verifiers/state/cost profiles, the **4-file loop anatomy** (`LOOP.md` contract · `STATE.md` memory · `loop-budget.md` caps+kill-switch · `loop-run-log.md` audit), the **circuit breaker as reusable machinery** (`loop-guard` + `loop-ledger.json` + pre-retry check), the `loop-audit` readiness rubric (0–100, CI-gateable — a shipped lint for this doc's three loop properties), 10 anti-patterns (several = brana findings independently rediscovered: verifier theater, state rot, shared-state-without-schema, auto-merge-without-allowlist), and **multi-loop coordination by priority ordering + shared state, not mutual invocation**.
- **[wild production loops catalog](../research/loop-examples-wild-2026-07.md)** — 12 examples beyond the repo. Standouts:
  - **FlakyGuard (Uber)** — production proof of *nested* loops: 3-level (contexts ×3 → reasoning ×2 → fix ×3 = 18 bounded attempts), 2h wall cap, fix accepted only after 1,000 test reruns. Nesting works when every level has its own cap and feedback flows between levels.
  - **Ralph loop (Vercel)** — outer verify/retry wrapping inner LLM iteration; ANY-trips stop semantics (iteration ∨ tokens ∨ cost); the rare true L3, made safe purely by resource bounds.
  - **Triage-before-action** (PR babysitter) — categorize Fix / Dismiss / Escalate with documented reasoning before touching anything; the wild version of defer-don't-halt.
  - **Confidence + escalation gate** (nightly error sweep) — high-confidence → auto-PR, medium/flagged → issue for human; graduated autonomy per decision, not per loop.
  - **Plan-as-comment** (Sweep) — post the plan publicly before writing code; transparency as the trust mechanism.
  - **Reality check: almost no true L3 exists in production** — nearly everything stops at L2 (human approves before merge). Independently validates v3's "L2 cockpit is the center of gravity, permanently."
  - **What the wild lacks** — cross-loop coordination, crash recovery, queue-overflow handling — is exactly what the v3 wave/log/ledger design already specifies. Brana is ahead precisely where the ecosystem is blank.

## Graduated migration — NOT a big-bang rewrite

Rewriting 35 skills would vaporize the wave contract (≤10 tasks, deletes ≥ adds). Instead, a skill becomes a loop **when its queue appears**:

1. **Bug-drain + AC-backfill** — queues exist the moment the v3 schema lands (standing waves).
2. **LEARN** — already designed as a loop (v3 wave 2).
3. **Exit routers** — cheap per-skill recipe improvements that need no autonomy: brainstorm first, then challenge (verdict → "apply findings? / log decision"), then build CLOSE (→ "ship? / next task?").
4. **Chaining** — only when two loops actually need to feed each other; brings the cycle-detection cost.

Candidate mechanism (to shape at brainstorm): skill frontmatter gains optional `stop_condition:` / `verifier:` / `queue:` fields — a skill declaring all three is loop-eligible; the fields are the machine-readable version of this doc's three properties, and the wave-5 core/packs cut (t-2090) can key on them.

## Non-goals

- Rewriting human-led judgment skills (brainstorm, decide, review) into unattended loops — their human stop condition is the design, not a gap.
- A new orchestration framework — composition uses what exists (waves, queues, remind, Workflow).
- Doing any of this before the backlog-v3 schema lands (waves are the queue primitive everything above drains).
