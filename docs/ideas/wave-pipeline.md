---
title: The Wave Pipeline — loops all the way down
status: active
created: 2026-08-14
task: t-2828
adr: ADR-079
produced_by: [docs/ideas/loop-first-redesign.md]
related: [docs/ideas/loops-library.md, docs/guide/workflows/drain-loop.md, docs/ideas/wave-pipeline-design.html]
---
# The Wave Pipeline

> The concept doc for how thebrana builds itself. Visual companion (diagrams, 4-D depth
> view, cast mapping): [wave-pipeline-design.html](wave-pipeline-design.html). Lineage:
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

## The spectrum — rings are sample points (studio dialogue, 2026-08-14)

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

**Where the metaphor stops.** Queues and valves are deliberately *not* wave-like: a queue
decouples frequencies so they need not stay in phase (law 1 — loops never talk), and a
valve is a discontinuity where flow may stop dead. Continuous wave as the medium;
discrete instruments mounted in it. The frequency lens covers the timescale structure,
never the parts catalog — the four primitives remain the vocabulary for the machinery.

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

## Status (2026-08-14)

**Shipped and deployed** (dev→main, bootstrap + release binaries): `wave drain` (t-2775) ·
`ac approve` (t-2812) · `wip_limit` + draining freeze (t-2782) · atomic `wave pull` +
[drain-loop.md](../guide/workflows/drain-loop.md) runbook (t-2813, built by the pipeline
itself over 8 supervised `/loop` beats). Wave-1 completed the first full lifecycle:
queued → draining → **shipped**.

**Open:** t-2828 (plan-time wave graphs + epic runner — owns the corpus and the
two-epic reconciliation with t-2820 loop-first) · t-2827 (approve-denial as technical
control) · **leases** (a crashed pump strands its pulled task — known gap, design owned
by t-2828) · unattended mode (hard-gated on the ADR-062 sandbox).
