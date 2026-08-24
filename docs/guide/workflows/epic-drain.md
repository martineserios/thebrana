---
title: Epic drain loop — the graph-walking runner procedure
status: active
created: 2026-08-14
task: t-2845
adr: ADR-080
produced_by: [docs/architecture/decisions/ADR-080-plan-time-wave-graphs-epic-runner.md]
related: [docs/guide/workflows/drain-loop.md, docs/architecture/features/loops-library.md]
---
# Epic Drain Loop

> Second entry of the loops library ([loops-library.md](../../architecture/features/loops-library.md)
> — the beat-record schema this entry emits, single-sourced there, never
> duplicated here) — the first proof the library holds more than one entry.
> Catalog entry: [system/loops/epic-drain.md](../../../system/loops/epic-drain.md)
> (frontmatter + pointer back here — this file stays the single source for
> the procedure). Generalizes [drain-loop.md](drain-loop.md) (t-2813,
> ADR-079) from "one wave, hand-armed" to "walk an epic's wave graph, arm
> each wave as its gate clears." Everything drain-loop.md does once
> epic-drain has pulled a task — full build framework, human merge valve,
> denied verbs — is unchanged and inherited, not reimplemented here.

## Prerequisites

```
plan WAVES step emits parent:<ms-id> waves under an epic ──▶ YOU: /loop epic-drain <epic-slug> ──▶ the loop walks the graph
   (or hand-rolled waves, ADR-080 §1)         (queue graph)      (the human arming act)              (this file)
```

1. The epic's waves exist — either plan-born (`parent:<ms-id>` selector, one
   per milestone, ADR-080 §2) or hand-rolled (`tag:` waves — see **Scope**
   below).
2. Each wave's tasks have approved AC (`brana backlog ac t-N approve`, or
   the batch valve `brana backlog wave approve <wave-id>` — both human-only,
   both denied to this loop).
3. **Rehearse (recommended, law 6):** before ever launching this loop
   against a real epic, walk a fixture epic end-to-end with
   `brana backlog wave pull <fixture-wave-id> --dry-run` at the point the
   procedure below would arm — confirms the topo order and, if you built a
   deliberately cyclic gate chain into the fixture, confirms PREFLIGHT stops
   loud instead of stalling silently.
4. Launch: `/loop epic-drain <epic-slug>`. **This is the arming act** — see
   PREFLIGHT step 3 below for why launching the loop, not plan-approval, is
   the human authorization boundary (ADR-080 §3.3).

## Scope

**This loop walks `parent:` waves only.** A `parent:<id>` selector has a
single root node, so its epic-ancestor is well-defined and the loop can
resolve "which waves belong to this epic" by walking each wave's selector
root up the `parent` chain (`resolve_epic_ancestor`, shared helper). A
`tag:` selector has no single root — its matches can span epics or none —
so hand-rolled `tag:` waves are structurally outside any epic graph. They
drain via the single-wave [drain-loop.md](drain-loop.md), unchanged. A
`tag:` wave may still appear as another wave's `gate` (the gate check is
per-wave and selector-blind) — accepted scope, not an oversight (ADR-080 §3
finding 6).

A single `epic-drain` instance drains **one wave at a time, in topo order,
within one epic.** Ungated waves are order-free, not concurrent — two
gate-satisfied waves still drain sequentially, first-ready wins.
Multi-instance concurrent draining of one epic has no wave-level claim
mechanism and is out of scope (ADR-080 §2.2, finding 7); running two
`epic-drain` instances against the *same* epic is not a supported
configuration. Running `epic-drain` against **different** epics
concurrently is fine — see ADR-080 §8 for the shared cockpit-digest review
budget across epics.

## The loop prompt (supervised)

```
/loop Epic-drain pump for <epic-slug> (supervised, ADR-080 §3). Each beat:

(1) PREFLIGHT (cheap, no-op fast): fresh-read tasks.json + `brana backlog
    wave list`. For each wave, resolve its selector root's epic-ancestor via
    `resolve_epic_ancestor` (skip tag: waves — out of scope, see Scope
    above); keep the ones whose ancestor == <epic-slug>.
    - **Check the exit status, not just the returned string** (the helper's
      own documented contract, `system/skills/_shared/epic-ancestor-walk.md`
      — three recurrences of this exact gap already found in the ADR-080
      family, t-2843 and this entry's own first draft included). A non-zero
      exit means the lookup itself broke, not that the wave has no epic —
      **do not silently exclude that wave from the kept set.** Silently
      dropping a wave here corrupts both downstream checks: it can hide a
      wave that was actually part of a cycle (false negative on cycle-STOP,
      step below) or make an epic look fully shipped when it isn't (false
      "epic drained. STOP" at step 2). On lookup failure: STOP the loop this
      beat, emit a beat record with state:"stopped", route "epic-ancestor
      lookup failed for `<wave-id>`'s selector root — not safe to compute
      this epic's wave graph" to the **studio agenda**. Never guess.
    - **Cycle detection is mandatory and runs FIRST, structurally.** Build
      the directed graph wave → its `gate` target over the kept waves only
      (edges to a wave outside the kept set, e.g. a `tag:` gate, are not
      followed — they can't be part of an in-epic cycle) and run a DFS for
      back-edges — **status-independent**: a not-yet-shipped wave is not a
      cycle, only a mutual/transitive gate reference is. `wave set <id>
      gate` has no referential or cycle check, so a real cyclic gate chain
      is a real possible state. If DFS finds one — STOP the loop
      immediately, emit a beat record with state:"stopped", route the
      diagnostic (exactly which waves and gate edges form the cycle) to the
      **studio agenda**, and do not proceed to topo-sort at all this beat.
      Never treat this as "still waiting on a human ship" — that's a silent
      stall, not a stop. **Do not conflate this with step 2's "not ready
      yet"** — a wave gated on another wave that simply hasn't shipped is
      normal pending state, not a cycle; only run the DFS on the gate
      graph's edges, never on live status, or every ordinary multi-wave
      chain false-positives as cyclic the moment its first wave hasn't
      shipped yet (caught in this entry's own fixture-epic rehearsal,
      Prerequisites step 3 — an earlier draft of this PREFLIGHT conflated
      the two).
    - **If no structural cycle:** topo-sort the kept waves by `gate`
      (Kahn's algorithm, now safe since the graph is acyclic: a wave is
      "ready" once its gate is null or names a wave with status:shipped;
      process ready waves, removing each from the graph unlocks its
      dependents).
(2) Find the active wave: first in topo order with status != "shipped"
    whose gate is null or names a wave with status:"shipped".
    - None found + all kept waves shipped → epic drained. STOP (real
      signal) — emit the final beat record, state:"stopped".
    - None found + some wave not shipped and not ready → report which
      wave is next and what it's waiting on; back off 20-30 min
      (state:"waiting").
(3) Arm if queued: if the active wave's status is "queued", run
    `brana backlog wave drain <id>`. (Idempotent if already draining or
    just-shipped-and-rechecked — drain-loop.md's re-resolve model.) The
    human authorization for this autonomous arm is **launching this loop
    with this epic named** — a deliberate, temporally-proximate act, not
    stale plan-approval from weeks earlier (ADR-080 §3.3).
(4) Pump: `brana backlog wave pull <active-wave-id>`.
    - pulled:null + at_limit    → report "at limit (live/limit)", back off
      20+ min (state:"waiting").
    - pulled:null + none_eligible → report counts (matched/unapproved/
      parked/blocked — blocked = unmet blocked_by; a cancelled blocker never
      resolves, ADR-079 §2 amendment). If matched is 0, do NOT report "wave done" — see step 5's
      empty-matched-set rule. Back off 30+ min (state:"waiting" or
      state:"empty").
    - pulled:<id> → work it through the FULL build framework, identical to
      drain-loop.md from here: `/brana:backlog start <id>` (worktree cut
      from dev, TDD, gates, challenger). At build CLOSE: present the merge
      command and WAIT — never merge to dev inside a beat.
(5) Contract-met announcement: derived from a FRESH tasks.json read at
    announce time (never a stale in-beat view — closure is derived, not
    asserted). If the active wave's matched set is non-empty and every
    matched task is completed/cancelled → announce "contract likely met"
    to the **cockpit digest**, back off.
    - **An empty matched set is NOT contract-met.** It's vacuous truth
      (undecomposed milestone, deleted selector root, pure-planning
      milestone with no tasks) — route it to the **studio agenda** as
      "wave matched zero tasks — needs a look," never to the ship digest.
(6) Advance: this loop never ships a wave. A human `wave set <id> status
    shipped` unlocks the next wave; the next beat finds it at step 2.
(7) JUDGE (fresh-context, mandatory): any challenger/evaluator review this
    beat needs is a SEPARATELY SPAWNED worker, never inline in this loop's
    own context. A beat that reviews its own work is self-judging —
    Actor≠Evaluator is a process separation, not a formality.
(8) Escalation routing (two rooms): scope questions, conflicting AC,
    design doubts, and anything this beat cannot confidently classify go to
    the **studio agenda** — the default under uncertainty. Rubber-stamp
    items (ship valve, merge valve surfacing) go to the **cockpit digest**.
    Under-escalating a design question into a rubber-stamp is the worse
    failure — when unsure, agenda.
(9) ASSIMILATE: emit a structured beat record every beat, from beat 1 —
    schema in loops-library.md, referenced not duplicated.
(10) Pace (RESTART): short delays while actively building; 20-30 min
    waiting on a human valve, at-limit, or an empty-for-now queue.
```

## Denied verbs — the runner must never run these

Same trust boundary as [drain-loop.md](drain-loop.md), plus the epic-level
verbs this loop's wider blast radius makes newly reachable:

| Verb | Why |
|---|---|
| `brana backlog ac <id> approve` / MCP `backlog_ac_approve` | Inherited from drain-loop.md — approval is the human trust boundary between selector-match and autonomous execution (ADR-079 §1; ADR-076 D4). |
| `brana backlog wave approve <wave-id>` / MCP `backlog_wave_approve` (with `confirm_ids`) | Same trust boundary, batched (ADR-080 §4). The loop may surface that a wave has `ac_state:proposed` tasks; it must never supply `confirm_ids` itself. |
| `git merge` into `dev`/`main`, any push to production | ADR-060: executors return branches; a human integrates and ships. |
| `brana backlog set <id> status completed` (outside build CLOSE) | Completion is graded, not asserted. |
| `brana backlog wave set <id> status shipped` | **New at epic scope.** No auto-ship — one human ship decision per wave is what makes epic-looping safe (ADR-080 §3.6, unchanged from ADR-079 §1.4). Empty pull ≠ done; contract-met is an announcement, never a self-executed advance. |
| `brana backlog wave set <id> gate` / `brana backlog wave set <id> selector` | **New at epic scope.** The loop reads the gate chain to topo-sort; it must never rewrite it — a runner that can edit its own dependency graph could route around a human-authored gate. |
| Inline self-review in place of a spawned challenger/evaluator | **New at epic scope.** Step 7 (JUDGE) above — the machine half of judgment must be a fresh-context worker per beat, never this loop reviewing its own pull. |

Shipped (t-2827): `runner-verb-guard.sh` (PreToolUse) mechanically denies
this list in sessions launched with `BRANA_RUNNER=1` — arm it when starting
the runner session (`BRANA_RUNNER=1 claude`). Two rows stay procedural (a
hook cannot distinguish them): `status completed` outside build CLOSE, and
inline self-review in place of a spawned challenger. This
prompt must not hardcode assumptions about which skills are
model-invocable — `t-2832` will re-taxonomize skill frontmatter; this loop
stays order-independent of that change.

## Unattended mode — NOT enabled

Same as [drain-loop.md](drain-loop.md): supervised-only. A human is
present, watching beats, operating the merge valve, and reading studio
agenda escalations. Unattended operation is hard-gated on the **ADR-062
executor sandbox** — do not remove this section without amending ADR-080.

## Mechanics reminders (shipped `/loop` semantics)

Session-scoped; hard 7-day expiry; no catch-up for missed fires; Esc stops
a waiting loop. Run epic-drain in a dedicated lean session, not your fat
interactive one — cost per beat ≈ context size (law 5). Cheap preflight
first, always — the topo-sort in PREFLIGHT reads tasks.json once and sorts
in memory; it does not call `wave drain` or `wave pull` until step 3/4.

## Proof-of-life

Per the loops-library shape doc's acceptance bar: this entry is not `done`
until it has run **≥3 real supervised beats with emitted records**
(completion graded, not asserted). The fixture-epic dry-run rehearsal
(Prerequisites step 3) may count toward this bar, capped at 1 of 3 — a
fixture beat doesn't exercise live-drift failure modes (contract-met on a
real wave, a real gate ship unlocking a real dependent, a real escalation),
so real production beats must dominate (ADR-080 valve-order amendment,
2026-08-14).

**Provenance (this entry's own bar, t-2845):** fixture epic t-2881
(`epic-drain-fixture`, milestones t-2882/t-2883 for the happy-path chain,
t-2885/t-2886 for the deliberate 2-cycle; waves wave-7..wave-10; archived
after use — waves have no delete verb, left inert with `contract` marked
FIXTURE). Beat records for the rehearsal and the two subsequent real beats
against the live `backlog-drain` epic's `wave-4` are logged on t-2845's
`notes` field (session-state, committed on `dev` per this project's
convention — not on this doc's own branch, so they won't appear in a diff
of this file).
