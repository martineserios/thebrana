---
title: NotebookLM infographic prompt — The Wave Pipeline
status: active
created: 2026-08-14
task: t-2867
related: [docs/ideas/drained/wave-pipeline.md, docs/ideas/drained/wave-pipeline-design.html]
---
# NotebookLM infographic prompt — The Wave Pipeline

> Customization prompt for NotebookLM's Infographic feature. Load
> [wave-pipeline.md](wave-pipeline.md) (and its related ADRs) as sources, then paste the
> block below into the infographic customization box. Kept here because the v1 prompt
> (2026-08-13) was delivered in-chat and never persisted — only a one-line memory summary
> survived it. This is v2, rewritten 2026-08-14 for the post-ADR-080 corpus (frequency
> spectrum lens, epic-runner mechanics, five-pillar convergence).

## Prompt (v2, post-ADR-080)

```
Generate an infographic titled "The Wave Pipeline — loops all the way down" from the
sources on brana's self-build architecture (wave-pipeline.md, ADR-079, ADR-080,
loop-first-redesign.md, loops-library.md).

CORE CLAIM (header strip): Work flows through durable queues, loops pump it forward,
and every irreversible step passes a human valve. Only the innermost loop is the
`/loop` command — the outer loops are harness design; the outermost has no command at
all, it's knowledge being processed and reused.

FOUR PRIMITIVES (closed vocabulary — anchor everything else to these four, nothing
else exists):
- QUEUE — durable state between pumps, the loop's only memory (waves, inbox/,
  ready/* branches, URL jsonl)
- PUMP — a loop moving work exactly one stage forward (wave pull, drain loop, cleanup)
- VALVE — a human gate, never automated, never armed by the party it constrains
  (ac approve, merge, wave shipped)
- GAUGE — a readout that never acts, makes the next decision cheap (wave board,
  watchdog, beat telemetry)

THE FLOW (single horizontal pipeline diagram):
backlog → ac-propose → ac approve → wave drain → wave pull → build → merge/ship
 QUEUE      PUMP        VALVE·you    VALVE·you    PUMP        PUMP     VALVE·you

FOUR RINGS AS FREQUENCIES, NOT LAYERS — this is the change from the old version:
don't draw these as nested fixed rings/onion layers. Draw them as four sample points
on one continuous spectrum/waveform, each a different frequency of the same signal
(try → feedback → improve), with the instrument (queue/pump/valve/gauge) mounted at
that frequency:
- Knowledge — weeks — memory→recall→work→learnings→memory — no command, the harness
  itself — human: Studio (co-design)
- Epic — days — plan emits wave graph→approve→drain→ship→next gate unlocks — human:
  Studio births the graph, Cockpit approves+ships
- Beat — minutes — sleep→wake→preflight→pull→work→report — THE /loop command — human:
  Cockpit, seconds per decision
- Micro — seconds — red→green→refactor, challenger find→fix→re-verify — human: none,
  machines all the way down
Show the spectrum extending past these four with unlabeled/dotted bands (session ~hours,
season ~months, sub-second lint/typecheck) to signal the lens is open-ended, not a
fixed ontology. Label the human's role across the spectrum as a "low-pass filter" —
sustained coupling to slow bands, discrete sampling of fast ones, absent from the
fastest.

THE FOURTH DIMENSION — MEMORY: draw as an axis orthogonal to the spectrum, touching
every band — read-on-entry, write-on-exit. Caption: "the three spatial dimensions cycle
and forget; the fourth accumulates." Note that write-back is what turns a circle into a
spiral.

NEW SECTION — MECHANICS LAYER (ADR-080, the epic runner): add a panel showing what
actually drains a wave now — plan-time wave graphs (planned before drain starts) feeding
an epic-drain runner, leases with evidence-gated reclaim (a stalled/crashed pump's claim
is reclaimed only once there's proof it's dead, not just a timeout), and a
watchdog-gauge / reclaimer-pump split (the watchdog only observes and reports; a
separate pump does the reclaiming — gauges never act). Show wave-3 (adr080-core) gating
wave-4 (adr080-consumers) as a concrete worked example of a gate.

FIVE PILLARS CONVERGENCE (small multi-panel or Venn-like device): five independently
built perspectives on the same object — Wave-pipeline (composition), Frequency spectrum
(time), Canonical seven-step skeleton ORIENT→SELECT→ACT→MEASURE→JUDGE→ASSIMILATE→RESTART
(anatomy), Pocock/AI Hero skill ergonomics (how a human walks it), Lived practice
(brainstorm/build/challenge/close/sitrep/reconcile — evidence). Caption: each corrects
the others; convergence from independent derivation is itself evidence.

TWO ROOMS (two clearly distinct visual zones, not a spectrum — a hard split):
- Studio (creative) — unhurried, protected, dialogue, births epics/wave
  graphs/ADRs/specs
- Cockpit (operative) — fast decisions on the fly, seconds each, batched, evidence
  attached
Caption the routing rule: "needs human" is not one queue — rubber-stamp items go to the
cockpit digest, needs-thinking items go to a studio agenda, never the interrupt stream.

SEVEN OPERATING LAWS (compact numbered list/footer band):
1. Loops never talk to each other — queues do.
2. Every loop needs a dead-letter path with its own closer pump.
3. One external watchdog watches all loops, outside the loops it guards.
4. Beats are idempotent.
5. Cost per beat ≈ context size — lean sessions, cheap preflight.
6. Loops are testable — rehearse against fixture queues before arming.
7. Lifecycle needs a stance — expiry, kill switch, no pause/resume.

STATUS STRIP (small, bottom, dated 2026-08-14): shipped — wave drain, ac approve,
wip_limit, atomic wave pull (wave-1 completed queued→draining→shipped). Designed,
queued — ADR-080 accepted, implementation tree t-2839–t-2847 draining via wave-3→wave-4.

VISUAL IDENTITY — reuse the existing six-color language, don't invent a new palette:
teal/cyan for pumps & motion (flow), amber for human valves, slate/blue-grey for
durable queue state, purple for studio/human creativity, green for the memory
dimension, and a warm red reserved only for named gaps/known holes — do not use red
decoratively. Keep it a clean technical one-pager, not cute icons — this describes how
the system that builds itself actually runs.
```

## Changelog

- 2026-08-14 · v2 written for the post-ADR-080 corpus (t-2867). v1 (2026-08-13, delivered
  in-chat during t-2828) is not recoverable verbatim — only the memory summary
  "wave not tubes, frequencies of one continuous signal" survived.
