---
title: Skills as Loops — recipes re-derived under the v3 loop model
status: draft
created: 2026-07-20
brainstormed: 2026-07-20
grounded-by:
  - "[primitive-taxonomy prior art](../research/primitive-taxonomy-prior-art.md)"
  - "[loop-framework landscape](../research/loop-framework-landscape-2026-07.md)"
  - "[skills primitive-audit preview](../research/skills-primitive-audit-preview-2026-07.md)"
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

## The deeper reframe — re-derive behaviors against the full primitive palette

The narrow reading above ("some skills are loops") is a special case of the real point (operator, 2026-07-20):

> Brana's skills were authored when **skill was the only primitive for enforcing or guiding a behavior**. That constraint is gone. We now have a palette — **skill · agent · workflow · loop · goal** — *plus* the supporting structure v3 is building (**contracts, AC, waves, ledger, verifiers**) that makes loops and goals usable where they weren't before. So the work is to **re-examine every behavior brana encodes and re-derive it against the whole palette**: designed today, is this still a skill? a loop? a workflow? a goal? a combination? Some stay skills; some become loops; some become workflows; and the gaps surface new ideas.

This is **Pi's "primitives over features" lesson pointed inward** — many current skills are the *right behavior expressed in the only primitive that existed at authoring time*, not the primitive whose shape the behavior actually has.

**Draft routing heuristic (the core deliverable — it makes the audit repeatable and guides every future "skill or loop?" call):**

| Primitive | Shape it fits | Signal in an existing skill |
|---|---|---|
| **Skill** | persistent procedure/knowledge, human-invoked, judgment-led | run once per human intent; irreducible judgment; no drain (brainstorm, decide, review) |
| **Workflow** | deterministic multi-agent fan-out → verify → synthesize | already spawns parallel agents + merges internally (challenge, deep review, research sweep) |
| **Loop** | autonomous drain-until-done: body + stop + verifier + queue | run repeatedly over a queue; objective done-signal (reconcile drift, close extraction, bug-drain) |
| **Goal** | a single verifiable end-state the system converges on | "keep going until X true" (goal-completion.sh already exists) |
| **Agent** | one context-isolated delegated worker | a step inside any of the above |

A behavior can be a **composition** (a skill that hands off to a loop; a workflow that a loop invokes per item) — which is exactly the loops-calling-loops section below, generalized to all primitives.

**The audit is the work.** The deliverable is (1) this routing heuristic, hardened; (2) a pass over brana's current skills/behaviors classifying each (stays-skill / →loop / →workflow / →goal / compose / retire); (3) the concrete reclassification tasks that fall out; (4) the new ideas the gaps reveal. Scope discipline (below, and the migration section) is what keeps this from becoming a 35-skill boil-the-ocean rewrite.

## The pipeline reading — task as workpiece, steps as stations, loop as conveyor (operator, 2026-07-20)

> **Scope decision (2026-07-20): this is the NORTH STAR / final wave — explicitly OUT of initial scope.** It depends on the schema (carrier), the wave/drain machinery, and *proven single loops* all existing first; per Anthropic's start-simple rule it must be *earned* by evidence that simpler single-station loops hand off cleanly, not assumed. Captured here so it isn't lost — it is the target the earlier waves build toward, not work to start now. Sequence: schema → audit (find the stations) → convert painful behaviors to single loops one at a time → *then*, only if handoffs prove lossless, compose into this pipeline.

The sharpest concrete form of the whole idea: **stop treating brainstorm and build as monolithic human-driven skills; decompose them into a stage graph of specialized agents, and let a loop advance tasks through the graph.**

- **Stations** = the SDLC steps, each staffed by a *specialized* agent: shape → spec → ADR → test → implement → verify → docs → close. (Brainstorm already has SEED/EXPAND/DISCUSS/SHAPE/OUTPUT; build already has SPECIFY/TEST/IMPLEMENT/VERIFY/CLOSE — the stations already exist as phases inside monolithic skills.)
- **Workpiece** = the task. The **[v3 schema built the carrier](../architecture/features/backlog-v3-schema.md)**: the self-contained handoff packet (spec + AC + log + refs) is precisely what a workpiece needs to carry context between stations. **This idea and the v3 schema are the same idea from two ends** — the schema made the packet; this builds the line that consumes it.
- **Conveyor** = a loop / wave: pick a task, advance one station, inject that station's context, assign the station's specialized agent, verify, advance-or-bounce.

**Prior art:** Factory.ai, Cognition (Devin), MetaGPT, ChatDev — role-specialized agents passing artifacts down a line. Their documented failure mode: **quality degrades across handoffs** (the telephone game) — which is exactly what the rich task-packet exists to prevent.

**This is likely the *target architecture* the loops-refactor builds toward** — reframing the palette-audit's job as *find the stations* (which steps deserve a specialized agent + a station boundary).

**The hard tension (must be designed around, not wished away):**
1. **The SDLC is a graph with feedback cycles, not a clean line.** Test reveals spec wrong; impl reveals design wrong. Forward-only pipelines fight this — you need bounce-back edges (impl → spec), which reintroduces routing + cycle-detection.
2. **Specialization tax.** For a solo operator, N specialized agents + N handoffs may cost more than one strong agent holding the whole task in context. Anthropic's rule (taxonomy research, 2026-07-20): *start simple; add agent-complexity only when demonstrably necessary.*

**Design resolution:** a station boundary is justified **only where (a) the handoff is lossless** (the packet carries everything the next station needs) **and (b) the specialization pays** (the step is genuinely better done by a dedicated expert agent than a generalist with full context). Human gates sit at the irreducible-judgment stations (spec approval, merge). Don't split a step just because it has a name.

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

## Scope & shape (decided 2026-07-20)

**This is a full loops-refactor epic** — audit *and* rebuild, not a docs-only map. Chosen deliberately over the lighter "cheap map feeds waves" and "fold heuristic + do top 2–3" options. **The audit preview right-sized it:** "full" turns out to mean a *focused* reclassification — the routing heuristic + ADR, ~2 standalone loops built (reconcile, cargo/dep-sweep), 2 workflows formalized (challenge, research), ~4 loop-bodies wired into drain waves (fix→bug-drain, close→LEARN, docs→changelog, backlog→AC-backfill), 2 retires (do, verify-docs) — the 22 stay-skills untouched. Effort **L, not XL** (the XL pipeline/north-star is deferred). What makes it survivable (both are the operator's own constraints, not add-ons):

1. **The epic obeys the v3 wave contract, recursively.** Not one giant push: **audit = wave 0** (routing heuristic + classification pass = the cheap map), then **one behavior re-derived and rebuilt end-to-end per wave**, shipped to daily use and graduated (L1→L2→L3) before the next. Deletes ≥ adds enforced per wave. This *is* the graduated migration below — "full epic" and "not a big-bang rewrite" are consistent because the epic drains as waves.
2. **The refactor dogfoods the machinery it builds.** The audit emits a prioritized candidate queue; a wave *drains* it one loop-build at a time. If the wave/drain machinery can't drain its own "convert skills to loops" queue, that is the early signal it isn't ready — the refactor is the loop machinery's first real customer.

## Risks

| Risk | Failure scenario | Mitigation (operator-confirmed) |
|---|---|---|
| **Churn — breaking what works** | Rebuilding working daily-driver skills (build/close/backlog/fix) as loops introduces regressions for architectural purity, no user-visible gain — the live-refactor-entangled-with-feature pattern. | Convert only **painful** behaviors first (manual, repeated, unverified); a working daily-driver is never touched for tidiness. Pain-driven, not completeness-driven, ordering. |
| **Obsolescence — CC ships it native** | Hand-built loop infra is replaced by native Claude Code primitives mid-refactor (already a v3 risk). | Build **thin deltas** over native primitives; the audit + routing heuristic survive even if the underlying machinery is swapped — the classification is portable, the implementation is not. |
| **Boil-the-ocean** | 35 skills × (build loop + graduate) = never finishes; v3's "waves never finish" realized. | Wave-0 audit produces a *capped, prioritized* queue; one loop per wave; next wave gated on previous shipping. |
| **Frankenstein compositions** | Skills turn out to be hybrids; forced reclassification produces compositions worse than the original skill. | The routing heuristic explicitly allows "stays a skill" and "compose" as first-class outcomes — reclassification is not mandatory; a behavior keeps its primitive if that's the right shape. |

## Graduated migration — NOT a big-bang rewrite

Rewriting 35 skills would vaporize the wave contract (≤10 tasks, deletes ≥ adds). Instead, a skill becomes a loop **when its queue appears**:

1. **Bug-drain + AC-backfill** — queues exist the moment the v3 schema lands (standing waves).
2. **LEARN** — already designed as a loop (v3 wave 2).
3. **Exit routers** — cheap per-skill recipe improvements that need no autonomy: brainstorm first, then challenge (verdict → "apply findings? / log decision"), then build CLOSE (→ "ship? / next task?").
4. **Chaining** — only when two loops actually need to feed each other; brings the cycle-detection cost.

Candidate mechanism (to shape at brainstorm): skill frontmatter gains optional `stop_condition:` / `verifier:` / `queue:` fields — a skill declaring all three is loop-eligible; the fields are the machine-readable version of this doc's three properties, and the wave-5 core/packs cut (t-2090) can key on them.

## Audit preview — the reality check (2026-07-20, real classification of 34 first-party skills)

A first-pass classification of brana's actual skills against the palette **right-sized this idea and corrected two of its own hypotheses.** Do not skip this — the honest numbers matter more than the ambitious framing.

**Counts (34 first-party skills; ~25 acquired reference packs all correctly stay skills):**
- **stay skill: 22** (reference packs, utilities, human-judgment skills — most of the system)
- **→ workflow: 2** — `challenge` (already fans out→verify→synthesize), `research`
- **→ standalone loop: 2** — `reconcile` (the prime drain-until-done), `cargo-machete` (dep-sweep)
- **compose (loop-body / loop-shaped skill / agent-wrapper): 7** — `build`, `fix`, `close`, `docs`, `memory`, `retrospective`, `gemini`
- **retire / merge: 2** — `do`→`backlog start` (self-declared alias), `verify-docs`→`reconcile` (it's reconcile's no-LLM sensor)

**Hypotheses tested against real skills (not vocabulary):**
- *reconcile / verify-docs / repo-cleanup → one loop* — **PARTIAL.** Only `verify-docs` merges in (as reconcile's sensor). `repo-cleanup` stays a *sibling* loop — it drains the git working tree, a different queue than reconcile's spec-vs-impl drift.
- *challenge / review / decide → shared workflow core* — **REFUTED.** `challenge` is the workflow; `decide` is a human-judgment router (no fan-out); `review` is a cadence business skill. Name collision, not primitive overlap.
- **Lesson (load-bearing): test primitive hypotheses against a behavior's *shape*, not its shared vocabulary.**

**Honest verdict — the "smaller system" claim was too rosy:** the refactor reclassifies **~10 behaviors and retires ~2** (34 → ~32 top-level surface). It is **not** a surface-halving. The genuine payoff is **conceptual** (fewer primitive-*types* to reason about; drain-machinery reused across reconcile/cargo/bug-drain) and **capability** (behaviors that were manual become autonomous), **not** a shorter menu. Only **2 skills genuinely want to *be* standalone loops** (reconcile, cargo-machete); ~4 more are loop-*bodies* feeding new drain waves (fix→bug-drain, close→LEARN, docs→changelog, backlog→AC-backfill). **This right-sizes the epic from "rewrite 35 skills" to a focused reclassification — and de-risks the churn concern, since the 22 stay-skills are never touched.**

## Landscape — adopt vs. build (2026-07-20 similar-frameworks sweep)

The loop-framework landscape tells brana **what NOT to build**:
- **Durable-execution layer** (Temporal, LangGraph, Inngest, Restate) — exists; brana's worktree+task-store is its equivalent. Don't build.
- **Multi-agent orchestrators** (CrewAI's Crews+Flows = the loop-vs-workflow split, validated; AutoGen; Marvin's *task-centric* abstraction — same instinct as brana's task-as-workpiece). Don't build.
- **Domain bots** (Sweep, Aider architect-mode = maker/checker, Nx/Dagger self-healing CI) — reference implementations of individual loops, not frameworks to adopt wholesale.
- **The niche brana actually occupies** = loop-engineering's own niche: *design + deploy a single autonomous loop safely* (governance: packet + verifier + budget + graduated autonomy + human cockpit). Near-peer: **ralph-loop-agent** (Vercel, 822⭐) — more LLM-procedural; brana/loop-engineering more systems-oriented. **Takeaway: build thin deltas over native CC primitives + adopt loop-engineering's anatomy; never rebuild the durable-execution or orchestration layers others already ship.**

## Second-order effects

- **Rebuild painful behaviors as loops, one per wave → each runs autonomously → the operator's role shifts from *invoking* to *supervising*.** You stop typing `/brana:reconcile` and start reviewing what the reconcile-loop drained in the cockpit. Opportunity: this is the v3 north star arriving concretely. Risk flavor: convert too fast and tacit knowledge of how each behavior works erodes (comprehension debt) — the ledger + L2 cockpit is the designed antidote, which is why pain-first + one-per-wave pacing matters.
- **Net-reduction was the wrong success metric** (audit above): measure the refactor by *behaviors made autonomous* and *primitive-types reduced*, not menu entries removed.

## Dependency

Hard-depends on the [backlog-v3 schema](../architecture/features/backlog-v3-schema.md) landing first — **waves are the queue primitive** every loop in this epic drains. Schema ships → this epic drains on top. Sequencing: schema epic → (this) audit wave 0 → per-behavior loop waves.

## Non-goals

- Rewriting human-led judgment skills (brainstorm, decide, review) into unattended loops — their human stop condition is the design, not a gap.
- A new orchestration framework — composition uses what exists (waves, queues, remind, Workflow).
- Doing any of this before the backlog-v3 schema lands (waves are the queue primitive everything above drains).
