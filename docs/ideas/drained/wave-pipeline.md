---
title: The Wave Pipeline — loops all the way down
status: active
created: 2026-08-14
task: t-2828
adr: ADR-079
produced_by: [docs/ideas/loop-first-redesign.md]
related: [docs/ideas/loops-library.md, docs/guide/workflows/drain-loop.md, docs/ideas/wave-pipeline-design.html, docs/ideas/wave-pipeline-infographic-prompt.md, docs/architecture/decisions/ADR-080-plan-time-wave-graphs-epic-runner.md]
---
# The Wave Pipeline

> The concept doc for how thebrana builds itself. Visual companion (diagrams, 4-D depth
> view, cast mapping): [wave-pipeline-design.html](wave-pipeline-design.html). NotebookLM
> infographic prompt built from this doc:
> [wave-pipeline-infographic-prompt.md](wave-pipeline-infographic-prompt.md). Lineage:
> born from [loop-first-redesign.md](loop-first-redesign.md) (the approach), built as the
> ADR-079 substrate (delivered 2026-08-13, t-2811), cataloged in
> [loops-library.md](loops-library.md). All three converge in **t-2828**.

## The claim

Work flows through durable queues, loops pump it forward, and every irreversible step
passes a human valve. **Only the innermost loop is the `/loop` command** — the outer
loops are achieved by harness design, and the outermost has no command at all: it is
knowledge being processed and reused.

## The four rings

Nested loops, each closing at its own timescale. Zooming in changes timescale, never
subject: one epic is a region of the knowledge plane; one beat is a region of the epic
plane; one task is a region of the beat plane.

| Ring | Mechanism | Timescale | The human here |
|---|---|---|---|
| **Knowledge** | memory → recall → work → learnings → memory. No command — the harness itself | weeks | **Studio** — you bring the topic; we design side by side |
| **Epic** | plan emits wave graph → approve → drain → ship → next gate unlocks. Design: waves + gates + valves | days | Studio births the graph · **Cockpit** approves + ships |
| **Beat** | sleep → wake → preflight → pull → work → report. **The `/loop` command** | minutes | Cockpit — the merge valve; seconds per decision |
| **Micro** | red→green→refactor · challenger find→fix→re-verify. Inside one task | seconds | none — machines all the way down |

The deeper the ring, the less of you it needs.

**The fourth dimension is memory.** It stands orthogonal to depth, touching every ring:
each recalls from it on entry (LOAD, wave state, task context) and writes back on exit
(learnings, ADRs, beat records). The three spatial dimensions cycle and forget; the
fourth accumulates. (Proven in the first live drain: beat 2 read its build map from the
task's `context` field, not from the conversation.)

## The spectrum — rings are sample points

The four rings are not an ontology. They are **different frequencies of the same wave** —
one subject oscillating at four rates, superimposed harmonics of one continuous signal —
and the rings table above marks the frequencies where instruments happen to be installed
(`/loop` at minutes, waves at days, the harness at weeks). The spectrum underneath is
continuous. Consequences:

- **Layers are discoverable, not fixed.** Bands already cycling uninstrumented: *session*
  (~hours — the close/handoff rhythm), *season* (~months — ADR-002's monthly reviews,
  portfolio direction, heavily studio), *sub-second* (lint, type-check — below micro,
  already fully machine). New layers are found by asking: where does work naturally cycle
  without a queue, pump, valve, or gauge installed yet?
- **The layer test — closed vocabulary at a new altitude.** A proposed band is real iff
  you can name its queue, its pump, its valve placement, its gauge, and its memory
  read-on-entry / write-on-exit. Can't name the queue → it's not a layer. Admission stays
  graded: a band exists once something has actually cycled in it with records emitted —
  the [loops-library.md](loops-library.md) proof-of-life bar, applied to layers.
- **The human is a low-pass filter.** Sustained coupling to the slow frequencies
  (studio), discrete sampling of the fast ones (cockpit valves), absent from the fastest.
  Tuning the system = sliding your coupling toward lower frequencies as evidence
  accumulates — the graduated-autonomy ladder
  ([loop-first-redesign.md](loop-first-redesign.md): L0→L3, promotion by clean runs,
  never assumption) is exactly this, generalized. The target is **dynamic equilibrium**:
  most learning and enjoyment per unit of effort. Gauges are the sensors, the watchdog
  the homeostat, the human the setpoint.
- **Ascent is phase, not a return trip.** Nothing travels back up the rings; the slow
  wave advances *because* the fast one oscillated. A wave is not closed by a separate
  closing activity — it closes as a side effect of its beats completing.
- **The fundamental.** Every band runs the same loop at its own rate:
  **try → feedback → improve**. red→green→refactor (seconds) · pull→work→report
  (minutes) · drain→ship→learnings (days) · memory→recall→work→learnings (weeks) ·
  observe-loop-failures→redesign — the band this doc itself cycles in
  ([loop-first-redesign.md](loop-first-redesign.md): "redesign follows observed loop
  failures, not upfront design"). Memory write-back is what turns each circle into a
  **spiral**: a loop without write-back returns to exactly where it started; with it,
  every cycle comes back to a different place. The wave cycles; the spiral is what the
  cycling leaves behind.

### Materialization — a discretized frequency is a new brana

The continuum holds infinite layers — all possibilities. A layer exists as a *thing* only
when a frequency of interest is identified and discretized: installing the instruments
(queue, pump, valve, gauge, memory contract) on a chosen band **materializes** it. That
materialized layer is a brane in the name's original sense — a self-contained unit with
its own fields, living in the higher-dimensional bulk (the memory reservoir), leaking
learnings to the others through it. The layer test above is therefore not just an
admission check — it is the **materialization procedure**. brana, the system, is the
practice of materializing branas out of the continuum, one proven band at a time. (In
string theory the objects living on branes are strings, whose modes are frequencies of
one vibrating string — the name predicted this section.)

### The skeleton match — an independent derivation

The fundamental has an engineering-grade anatomy, and thebrana already researched it:
[doc 60](../../../brana-knowledge/dimensions/60-agent-loop-architecture.md) (t-1851,
2026-06-07, 18 sources) found every loop lineage — ReAct, Reflexion, RALPH, OODA —
converging on one seven-step skeleton: **ORIENT → SELECT → ACT → MEASURE → JUDGE →
ASSIMILATE → RESTART**. Lined up against this doc's vocabulary, derived independently
two months later, the match is 1:1:

| Canonical step (doc 60) | This doc's structure | The shared rule |
|---|---|---|
| ORIENT — load external state | memory read-on-entry | the repo is the memory; the agent forgets |
| SELECT — next incomplete item | **queue** (atomic pull) | durable state, not conversation |
| ACT — execute | **pump** | moves work exactly one stage |
| MEASURE — external validators | **gauge** | objective readout; never self-assessment, never acts |
| JUDGE — *separate* evaluator | **valve** | Actor≠Evaluator ↔ never armed by the party it constrains |
| ASSIMILATE — write reflection back | memory write-on-exit | the circle-into-spiral step |
| RESTART — exit or re-enter | pacing (`{active, waiting, empty}`) | termination the agent can't game |

So the layer test is an **anatomy exam** — the four primitives plus the memory contract
*are* the skeleton's structural roles — and the diagnostic runs both ways: for any
existing band, ask which of the seven steps is missing (the knowledge band has strong
ORIENT/ACT/ASSIMILATE but weak MEASURE/JUDGE — nothing yet measures whether accumulated
knowledge is any good; that is why eval-rerunner and memory-hygiene surfaced on the
loops-library candidate list before anyone could name why).

Two refinements this system made over the June theory, worth stating as deliberate:

1. **JUDGE splits by reversibility.** Doc 60 allows an automated separate evaluator;
   here, machine judges (challenger, evaluator, verification gates) own *reversible*
   outcomes, while the human valve is mandatory for *irreversible* ones (approve, merge,
   ship). Judgment routed by blast radius, not one JUDGE box.
2. **SELECT is externalized.** Doc 60's loop picks its own next task; here selection
   lives in the queue with eligibility enforced queue-side in the atomic pull —
   structurally unbypassable by the pump. A loop that picks its own work can game its
   priorities; a loop that can only `pull` cannot.

This section stays conceptual; the mechanics — the epic runner's seven-step beat,
leases with evidence-gated reclaim, the watchdog gauge/reclaimer-pump split — are
specified in
[ADR-080 §3](../architecture/decisions/ADR-080-plan-time-wave-graphs-epic-runner.md),
which cross-references this section rather than duplicating it.

**Where the metaphor stops.** Queues and valves are deliberately *not* wave-like: a queue
decouples frequencies so they need not stay in phase (law 1 — loops never talk), and a
valve is a discontinuity where flow may stop dead. Continuous wave as the medium;
discrete instruments mounted in it. The frequency lens covers the timescale structure,
never the parts catalog — the four primitives remain the vocabulary for the machinery.

## The five pillars

Five independently built perspectives converge on this one object; the merge is the aim,
because each looks along a different axis and corrects the others:

| Pillar | Axis | Contributes | Corrects in the others |
|---|---|---|---|
| **Wave-pipeline** (this doc: primitives, laws, rooms) | composition — what parts exist | closed vocabulary, backpressure, dead-letter, studio/cockpit | forces the JUDGE-by-reversibility split |
| **Frequency spectrum** (§above) | time — where loops run | continuity, layer materialization, low-pass human, tuning to dynamic equilibrium | dissolves rings-as-fixed-ontology |
| **Canonical skeleton** ([doc 60](../../../brana-knowledge/dimensions/60-agent-loop-architecture.md)) | anatomy — what one loop is made of | the seven steps + hard rules (external state, Actor≠Evaluator, ungameable termination) | turns the layer test into an anatomy exam |
| **Pocock / AI Hero** ([study](../research/2026-08-13-matt-pocock-skill-system.md), t-2830) | ergonomics — how a human walks it | the ordered spine, artifact-chain handoffs, triage state machine, writing-for-agents craft, thin skills as armable beat bodies | exposes the legibility gap; third independent derivation (RALPH shared ancestor with doc 60) — convergence is evidence |
| **Lived practice** (brainstorm, build, challenge, close, sitrep, reconcile, …) | evidence — what a real team actually needed | months of daily usage; every skill already *occupies* a skeleton position (build's steps are literally the seven: LOAD=ORIENT, CLASSIFY/DECOMPOSE=SELECT, BUILD=ACT, gates=MEASURE, evaluator+challenger=JUDGE, learning=ASSIMILATE, CLOSE=RESTART; close=ASSIMILATE at session band; sitrep=ORIENT gauge; reconcile=slow-band drift gauge+pump) | grounds the theory: positions grew empirically into the right places |

Orthogonality note: Pocock's 7 *phases* (Idea→Research→Prototype→PRD→Kanban→Execution→QA)
traverse the flow line once — a spatial pass; doc 60's 7 *steps* are the loop anatomy
each station repeats — temporal. Flow × anatomy, not two versions of one list. (His
`wayfinder` and our waves are structural cousins — claim-before-work frontiers over
blocking-edge graphs — but wayfinder drains *decision* tickets, waves drain *execution*
tasks; don't conflate.)

**The lived-practice diagnosis.** The skills deliver because their positions are right,
but they factor by *occasion* ("session ending" → close does six jobs), not by
*anatomy* — monoliths spanning multiple skeleton steps and bands, with shared organs
(interviewing, learning-extraction, verification, handoff-writing) duplicated inside
several skills instead of extracted once (Pocock's `grilling`/`tdd` show the thin-organ
alternative; his `implement` is 12 lines because the organs live outside it). Refactor
direction: **skill boundaries follow skeleton-step × band; shared organs extracted;
enforcement layer untouched.** Discipline for the rethink: loop first, redesign after —
refactors are pulled incrementally by observed friction, never big-bang (the t-1994
lesson; first six moves already queued as t-2831–t-2836, tagged `wave:drain-3`).

## The flow

```
backlog ──▶ ac-propose ──▶ ac approve ──▶ wave drain ──▶ wave pull ──▶ build ──▶ merge · ship
 QUEUE        PUMP          VALVE·you      VALVE·you       PUMP         PUMP       VALVE·you
```

Ascent happens on the way back: green tests close a beat, beats close a wave, shipped
waves close an epic, the epic's learnings close the knowledge loop.

## Four primitives, nothing else

| Primitive | Definition | Instances |
|---|---|---|
| **Queue** | Durable state holding work between pumps — the loop's only memory | waves, `inbox/`, branches (`ready/*`), URL jsonl |
| **Pump** | A loop moving work exactly one stage forward | `wave pull`, drain loop, cleanup |
| **Valve** | A human gate between stages — never automated, never armed by the party it constrains | `ac approve`, merge, `wave … shipped` |
| **Gauge** | A readout on a queue or the pumps — never acts, makes the next decision cheap | wave board, watchdog, beat telemetry |

**The vocabulary is closed.** Every capability — standing waves, shadow drains,
dead-letter triage, graduated autonomy, the epic runner — is an *arrangement* of these
four. The day an idea needs a fifth primitive is the day to be suspicious of it.

Every queue answers five verbs — `peek / pull / ack / dead-letter / depth` — with its
store's native atomic primitive doing `pull` (lock+write for waves, `mv` for dirs,
`update-ref` for git). Native stores stay authoritative; the abstraction lives only at
the verb interface ([loops-library.md](loops-library.md) has the full contract).

## The two rooms

The human appears in two postures, and the architecture keeps them distinct — loops
**protect** the first and **speed** the second:

- **Studio (creative):** you bring the topic or project; solutions are built together in
  dialogue; you decide side by side with the assistant's knowledge. Births epics, wave
  graphs, ADRs, specs. Unhurried, protected, never interrupted.
- **Cockpit (operative):** the system brings items to you for fast decisions on the fly —
  "go", approve AC, merge, ship, triage. Seconds each, batched, evidence attached.

**"Needs human" is not one queue.** Valve-feeders classify every item: *rubber-stamp* →
cockpit digest; *needs thinking* → a **studio agenda** queue for the next design
conversation, never the interrupt stream. When unsure, route to the agenda —
under-escalating a design question into a rubber-stamp is the worse failure.

## Session lifecycle in the loop world

Sessions are **disposable read/write heads over durable state**, not where state lives.
Consequences for the session-band apparatus:

- **Close decomposes into distributed ASSIMILATE.** Learning extraction, handoff, and
  pattern storage stop being an end-of-session ceremony: every beat writes its record,
  task context, and staging entries at exit. What remains of `/close` is a thin
  session-band valve — the human confirming what enters `next[]` and what counts. Loop
  sessions never call close; their beat record *is* their close.
- **Sitrep becomes ORIENT.** Loops re-orient every beat from durable stores and need no
  reconstruction; sitrep survives as the *human's* gauge — rendering wave board, beat
  records, and `next[]` after time away, instead of excavating a dying context.
- **Cross-session learning is a pipeline, not a feature:** capture (every beat, free) →
  `knowledge-staging` queue (cap = WIP bound) → distiller pump → curation valve
  (cockpit digest) → reservoir, with hygiene gauges measuring staleness and a
  retirement path (law 7 for knowledge). This materializes the knowledge band's missing
  MEASURE/JUDGE (t-2851 pump · t-2852 valve-feeder · t-2853 gauge).
- **Context economy is law 5 applied to sessions:** lean dedicated loop sessions
  (~100× cheaper than piggybacking, probe-measured), cheap no-op preflight, a named
  session-recreation cadence (sessions regrow fat from turn count alone), and a slim
  resident harness (on-demand skill shelf, `disable-model-invocation` taxonomy).
  Killing a session must always be a non-event.

## The seven operating laws

1. **Loops never talk to each other — queues do.** Coordination is backpressure; the
   foreman fills a queue, it never calls workers.
2. **Every loop needs a dead-letter path** with its own closer pump — queueless rejects
   rot (the 160-day-stale root cause).
3. **One external watchdog watches all loops** via last-beat records, outside the loops
   it guards. Session death is loop death; only the watchdog notices.
4. **Beats are idempotent.** A beat replayed twice must be safe (the atomic wave pull is
   the reference implementation).
5. **Cost per beat ≈ context size.** Lean dedicated sessions, cheap preflight first; a
   loop whose beats cost more than the work they move is net negative.
6. **Loops are testable.** Rehearse beats against fixture queues before arming (shadow
   drains are the wave-native form).
7. **Lifecycle needs a stance** — 7-day expiry, Esc-kill, no pause/resume: retirement and
   re-arming, not just birth.

## Status (2026-08-14, post-ADR-080)

**Shipped and deployed** (dev→main, bootstrap + release binaries): `wave drain` (t-2775) ·
`ac approve` (t-2812) · `wip_limit` + draining freeze (t-2782) · atomic `wave pull` +
[drain-loop.md](../guide/workflows/drain-loop.md) runbook (t-2813, built by the pipeline
itself over 8 supervised `/loop` beats). Wave-1 completed the first full lifecycle:
queued → draining → **shipped**.

**Designed, implementation queued:**
[ADR-080](../architecture/decisions/ADR-080-plan-time-wave-graphs-epic-runner.md)
**accepted** (t-2828 completed) — plan-time wave graphs, epic-drain runner, leases with
evidence-gated reclaim, watchdog gauge/reclaimer-pump split. Implementation tree:
milestone t-2839 (t-2840–t-2846) + t-2847, draining via wave-3 `adr080-core` → wave-4
`adr080-consumers` (first live `parent:` selector). Behind them: the Pocock-mining
batch (t-2831–t-2836, `wave:drain-3`, gated on adr080-consumers), the knowledge-band
trio (t-2851–t-2853), and the skill-system rethink map (t-2838).

**Open:** t-2827 (approve-denial as technical control) · unattended mode (hard-gated on
the ADR-062 sandbox).

## Changelog

One line per substantive revision — the temporal ledger. Reasoning history lives in git,
task contexts, and ADRs; this doc keeps only current state.

- 2026-08-14 · born from [loop-first-redesign.md](loop-first-redesign.md); four rings,
  four primitives, seven laws, two rooms (t-2828 corpus).
- 2026-08-14 · spectrum lens: rings as sample points, layer test, low-pass human,
  try→feedback→improve fundamental (studio dialogue).
- 2026-08-14 · skeleton match (doc 60 isomorphism), materialization (= a new brana),
  five pillars incl. Pocock convergence ([study](../research/2026-08-13-matt-pocock-skill-system.md))
  and lived-practice factoring diagnosis.
- 2026-08-14 · ADR-080 accepted (mechanics cross-ref); session-lifecycle section;
  status refreshed to post-ADR-080.
