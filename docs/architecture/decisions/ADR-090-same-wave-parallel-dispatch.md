---
depends_on:
  - docs/architecture/decisions/ADR-079-backlog-drain-loop-handoff.md
  - docs/architecture/decisions/ADR-080-plan-time-wave-graphs-epic-runner.md
  - docs/architecture/decisions/ADR-060-branch-strategy-autonomous-agents.md
status: accepted
---

# ADR-090: Same-Wave Parallel Dispatch (extends ADR-079 §3, ADR-080 §2/§3/§8)

**Date:** 2026-09-02
**Status:** Accepted (2026-09-02; challenged same session — 2 MAJOR + 4 MINOR found and
incorporated, no BLOCKER — see Challenger findings)
**Deciders:** Martín Rios
**Tags:** backlog, waves, loop, wip, parallelism, epic-runner
**Tasks:** t-3264 (this ADR), t-2889 (spike that produced it), t-2811 (epic backlog-drain)
**Relates:** [ADR-079](ADR-079-backlog-drain-loop-handoff.md) (WIP-at-pull, leases design)
· [ADR-080](ADR-080-plan-time-wave-graphs-epic-runner.md) (leases shipped, epic runner,
§2.2 within-epic single-instance rule, §8 review-budget model — all extended, none
reopened, by this ADR) · [ADR-060](ADR-060-branch-strategy-autonomous-agents.md)
(worktree-per-task execution contract, unchanged, now parallelized) ·
[docs/research/2026-08-22-pocock-alignment-decision-matrix.md](../../research/2026-08-22-pocock-alignment-decision-matrix.md)
(row #2, ADOPT — the decision this ADR fulfills) ·
[docs/research/2026-09-02-pocock-sandcastle-video-findings.md](../../research/2026-09-02-pocock-sandcastle-video-findings.md)
(§3 — Sandcastle reference implementation, ring-scoped comparison)

---

## Context

The 2026-08-22 decision matrix locked **ADOPT** for wave-level parallelism (row #2):
independent, unblocked tasks in a wave should be pullable and buildable concurrently, not
strictly one-at-a-time. `the-brana-guide.md` §L3 recorded this as DECIDED, with leases named
as the hard prerequisite. That prerequisite is done: ADR-080 §5 shipped per-task leases
(t-2841) inside the same atomic `lock_tasks` critical section as `wave pull`, and §1 fixed
the `wip_limit` live-count bug (a hand-stripped `tag:` prefix that silently defeated the
limit on `parent:` waves). Both are implemented and correct in `wave.rs` today.

t-2889 (spike, 2026-09-02, full pass) found the actual remaining gap is not safety — it's
that **nothing consumes `wip_limit` above 1**. `docs/guide/workflows/epic-drain.md` and its
implementing loop call `wave pull` exactly once per beat; the epic runner works one task
through the full build framework, then moves to the next beat. Raising `wip_limit` today
changes zero runtime behavior. Separately, ADR-080 §2.2 (finding 7) already declared
**cross-wave, multi-instance draining of one epic** "not a supported configuration," pending
a wave-claim design that has never been scoped. The spike's key move was recognizing these
are two independent axes — within-wave task fan-out (this ADR) vs. cross-wave/multi-instance
(still out of scope, unchanged) — that t-2889's original framing had conflated into one
question. See `pattern_concurrency-axis-must-match-safety-substrate-scope` for the reusable
form of that distinction.

A concrete reference point exists now that didn't when the matrix scored row #2: Matt
Pocock's `sandcastle` (a working AFK-orchestration library, not just a stated principle) —
Docker container + worktree per task, planner/implementer/reviewer/merger agent roles. Read
against brana's own frequency-ring model (`the-brana-guide.md` §L3.1), Sandcastle's entire
four-role machine collapses into a single **Beat-ring** cycle; brana's `WAVE` is an
**Epic-ring** queue object one level up, untouched by anything Sandcastle does. This ADR is
scoped to the Beat ring only — it does not touch the wave object, its selector, its gate, or
its `wave ship` valve.

## Decision

### 1. Parallel-pull-per-beat contract

The epic runner (and single-wave `drain-loop.md`, same underlying `wave_pull_decision`) may
pull up to `min(wip_limit − live, N)` tasks within one beat, instead of exactly one. If
`wip_limit` is null (unbounded — the ADR-079 §3 default), the bound is just `N` directly; this
ADR holds itself to the same no-guessed-default standard the field already follows, so the
unbounded case is named explicitly rather than left implicit.
`N` is an operator-set fan-out cap (config, not schema — same no-guessed-default posture as
`wip_limit` itself; a sane starting default is left to the implementation task, not fixed
here). Each individual pull remains inside the existing atomic `lock_tasks` critical section
unchanged from ADR-080 §5 — pulls happen in sequence within the beat (not literally
simultaneous), each still taking its own lease before the next is attempted. No new locking
primitive is introduced; this is the existing per-task safety mechanism exercised more than
once per beat, not a new one. **Verified against `wave.rs`, not just asserted:**
`pull_wave_task` takes its own `lock_tasks` → fresh `load_raw` → decide → write → `save_tasks`
per call, releasing the lock at return — so a second pull within the same beat sees the first
pull's `in_progress` write and recomputes `live` correctly. The live-count-freshness this
contract depends on is structural, not a new invariant this ADR has to introduce.

### 2. Dispatch mechanism — parallelizes the existing per-task pattern, adds no new isolation primitive

- **Supervised (interactive `/loop epic-drain`):** dispatch each pulled task to its own
  worktree via native Agent/Task fan-out, one build-loop instance per task, run in parallel
  within the beat.
- **Headless (Orbit/autonomous runner, t-3019, `presence: none`):** dispatch as N separate
  `claude -p` processes, each in its own ephemeral worktree — the same ADR-060 isolation
  contract already used for the single-task case, invoked N times instead of once.
- **Docker-per-task isolation** (the layer Sandcastle adds on top of its own worktree): named
  here as an **open, undecided question** — worth its own follow-up spike once this ADR's
  worktree-only version has run, not decided or scoped by this ADR.

### 3. Beat-record schema — a net-new structured field, not a pluralized existing one

**Corrected from an earlier draft's claim** (challenger finding, verified against the live
schema): the canonical beat-record schema is
[`docs/architecture/features/loops-library.md`](../features/loops-library.md) §Beat record
schema — `docs/ideas/drained/loops-library.md` is explicitly superseded ("do not add new
content here") and must not be edited; an implementer following this ADR should touch only
the `features/` copy. Today there is **no structured task-ID field at all** — the pulled
task id lives only inside the free-text `what_happened` prose string. So this ADR is not
pluralizing an existing array field into a longer one; it is **adding a net-new structured
field** (e.g. `pulled_task_ids: [...]`) to the beat record. "No migration needed" is true only
in the trivial sense that nothing existed to migrate — the real design work is naming/shaping
that new field and deciding whether prose-only historical records need any backfill for
consumers that want to query pulled-task-ids structurally. Left to the implementation task,
named here so it isn't discovered mid-build.

### 4. Human valve — batched digest, existing capacity model, no new mechanism

N concurrent build-CLOSEs from one parallel beat land in the **same cockpit digest queue**
ADR-080 §8 already uses for cross-epic arbitration — no new review-budget model is needed.
§8's measured throughput (7-8 well-contracted approvals per sitting, backpressure at ~15
unreviewed / drains to ~8) already covers batches of this size; this ADR's batches are simply
another source feeding the same queue, ordered the same priority-then-FIFO way. This directly
answers the question t-2889's original context raised ("can the human merge valve absorb N
concurrent build-CLOSE reviews without conflating them?") — yes, by the queue's existing
design, without inventing new capacity. §8's own cited evidence (the wave-2 drain measurement,
7 approvals in 33 minutes) is itself same-wave data, so this generalization is better-grounded
than a naive read of "cross-epic throughput" would suggest — but same-wave parallel tasks are,
by construction, more likely to share file or logic surface than an arbitrary cross-epic batch
(they came from one milestone). The human may face rebase/merge-order dependencies *between*
the N branches, not just N independent approvals to work through. This ADR names that risk;
it does not solve it — resolving merge order among N same-wave branches is implementation
scope, not a design decision this ADR needs to make in advance.

### 5. Named risk: the approval valve, not just the merge valve, now has a throughput question

Parallel dispatch drains the `ac_state:approved` backlog up to N× faster per beat than today —
but the *approval* step (`wave approve`, ADR-080 §4, batch-capped at 10 confirmations per
call, same ~1-sitting/day cadence as merge review) gets no corresponding speed-up from this
ADR. This is the mirror-image risk to §4's merge-valve question, and unlike that one, it isn't
already answered by an existing measured model: an epic-runner exercising N-fan-out could burn
through its `ac_state:approved` queue faster than a human refills it, landing on
`NoneEligible{unapproved: N}` more often than today's single-pull runner does. This ADR does
not resolve it — the existing `wave approve --confirm_ids` batch path (cap 10) is the
mitigation mechanism already available; whether it needs to run more frequently once
parallel dispatch ships is an operational question to watch via the cockpit digest, not a new
mechanism to build here. Named so it isn't discovered as a surprise stall after ship.

## Non-Actions (explicit — do not silently expand into these)

- **Does NOT enable or design cross-wave, multi-instance draining of one epic.** ADR-080
  §2.2's "not a supported configuration" stance for two `epic-drain` instances against the
  *same* epic is unchanged. A wave-claim mechanism remains undesigned. If this resurfaces, it
  needs its own ADR, gated on actual evidence of a cross-wave bottleneck — none exists today.
- **Does NOT automate the Beat-ring merge valve.** The human merge valve stays mandatory
  (ADR-079 §1, `runner-verb-guard.sh` still denies `git merge`/`push` to runner sessions).
  Sandcastle's `merger` agent role has no brana equivalent under this ADR — the gauge shrinks
  what the human sees (via existing challenger/evaluator), the valve itself does not move.
  See `pattern_gate-armed-by-the-party-it-constrains`.
- **Does NOT change lease or `wip_limit` live-count semantics or code.** ADR-080 §1 and §5's
  mechanisms are exercised more than once per beat, never modified. Worth one honest caveat,
  not a reframing: `wip_limit` itself is an Epic-ring field (it lives on the wave object), and
  before this ADR it was behaviorally inert above 1 — after, it becomes the live concurrency
  cap. That's a real change in what the field *does*, even though its schema, selector, and
  gate logic are untouched. "Beat-ring scoped" describes the mechanism this ADR adds, not a
  claim that zero Epic-ring field suddenly matters more than it did.
- **Does NOT decide Docker-per-task isolation.** Named as future scope only (§2 above).

**Worth stating explicitly, not left for the reader to infer:** the same-epic multi-instance
guard (ADR-080 §2.2) remains a documented convention, not a code-enforced one — nothing in
`wave.rs` stops two `epic-drain` instances from targeting the same epic today; only the
per-task atomic pull makes that scenario *safe*, not *useful* (ADR-080's own words). By giving
an operator a supported, single-instance way to get real throughput via `N`-fan-out, this ADR
reduces the practical temptation to reach for a second instance against the same epic as a
workaround — it doesn't close the gap in code, but it removes the main reason someone would
try.

## Consequences

- t-2889's spike closes with this ADR as its concrete output.
- Implementation tasks may be filed once this ADR is Accepted (post-challenger, post-user
  review) — not before, per `m-plus-discipline-enforcement.md`'s M+ ADR gate.
- Beat-record consumers (cockpit digest, wave board) need updating to read a multi-task beat
  correctly — named here as implementation scope, not designed in full by this ADR.
- MODEL-001 (`docs/domain/MODEL-001-brana-core.md`) should gain a note on the beat record's
  multi-task-array extension once implemented (DDD, light touch — no new entity, an existing
  one's shape changes).

## Challenger findings

Context-isolated challenger review, 2026-09-02 — verified claims against `wave.rs`,
`epic-drain.md`, ADR-079/080, and both copies of `loops-library.md`. Verdict: proceed with
changes, no BLOCKER, 2 MAJOR + 4 MINOR, all incorporated above.

**Verified true, not just asserted** — the review checked these against source rather than
trusting the draft's prose, so they're now load-bearing claims, not assumptions: "`wip_limit`
above 1 is inert" and "exactly one pull per beat" (confirmed in `pull_wave_task` and
`epic-drain.md` step 4); the atomicity/lease claim in §1 (confirmed `pull_wave_task`'s
lock→read→decide→write→unlock shape gives every pull within a beat a fresh, correctly
recomputed `live` count — the ADR's strongest claim, and the one that actually gates whether
this is safe to build); Beat-ring scope discipline (Decision section doesn't touch wave
schema, selector, or gate logic).

**MAJOR, both fixed above:** (1) §3's "array extension" framing was wrong — the beat record
has no structured task-ID field today at all (lives in free-text `what_happened`), so this is
a net-new field, not a pluralization; the ADR also failed to disambiguate the two
`loops-library.md` files, risking an edit to the superseded one. (2) The merge-valve throughput
answer in §4 didn't address that the *approval* valve (`wave approve`) gets no matching
speed-up — now named as §5, an explicit risk with an already-available mitigation
(`--confirm_ids` batching) rather than a silent gap.

**MINOR, all folded in:** same-wave branches are more likely to share file/logic surface than
cross-epic batches, so merge-order dependencies between the N branches are a real risk beyond
"N independent approvals" (§4); `wip_limit`'s Non-Actions framing undersold that an Epic-ring
field becomes operationally meaningful for the first time (Non-Actions, bullet 3); the
`min(wip_limit − live, N)` formula didn't spell out the null/unbounded case (§1, now explicit);
the single-instance guard staying convention-only (not code-enforced) is true but was left
implicit — now stated as an explicit argument for why N-fan-out reduces the temptation to
violate it, in Non-Actions.
