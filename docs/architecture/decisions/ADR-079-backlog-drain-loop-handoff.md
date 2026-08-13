---
status: accepted
---
# ADR-079: ac_state Approval, Wave-Drain→Loop Handoff, and WIP Location (amends ADR-065)

**Status:** Accepted (2026-08-13)
**Date:** 2026-08-13
**Deciders:** Martín Rios
**Tags:** backlog, waves, ac, wip, loop, epic-entry, adr-065-followup
**Tasks:** t-2811 (epic), t-2775, t-2812, t-2813, t-2782
**Relates:** [ADR-065](ADR-065-epic-as-hierarchy-top.md) (waves as thin process objects, D3;
epic WIP cap retirement amendment) · [backlog-v3-schema.md](../features/backlog-v3-schema.md)
(§ac_state, §Wave = Queue — the design intent this ADR makes concrete) ·
[wave-gate-enforcement.md](../features/wave-gate-enforcement.md) (t-2775's spec — unchanged by
this ADR, referenced not superseded)

---

## Context

t-2811 (epic: backlog-drain) diagnosed 2026-08-13 that three backlog-v3 features shipped at
the schema/storage layer only, with zero live consumers and no wiring to a loop:

1. **Waves** (ADR-065 D3) — CRUD exists, `drain` does not yet (t-2775, already spec'd,
   unblocked, S effort — this ADR does not change that spec).
2. **`ac_state`** — the field, its validation (`none`/`proposed`/`approved`), and query
   filtering all exist. Zero write paths besides the untyped `backlog set <id> ac_state
   <value>` escape hatch; zero read paths gate or branch on it anywhere in the codebase
   (confirmed by exhaustive grep, 2026-08-13 audit — the only two hits are a one-time
   migration default-write).
3. **WIP capping** — `check_epic_wip_cap()` was retired 2026-08-12 (t-2727, ADR-065's own
   amendment) because epics are unbounded groupings. Its replacement was redirected to
   waves (t-2782) but never designed.

Per `m-plus-discipline-enforcement.md`, the epic's three implementation children (t-2812,
t-2813, and t-2782's downstream consumer) are gated on an ADR settling the cross-cutting
contract between these three pieces before code starts. This is that ADR.

**What this ADR does NOT redo:** t-2775's spec (`wave-gate-enforcement.md`) already fully
specifies `wave drain`'s gate-check and `tag:<name>` selector resolution — that stands as
written. This ADR covers only the three things `wave-gate-enforcement.md` explicitly declined
to specify: what consumes `drain`'s output, what "approved" means and how a task gets there,
and where a WIP bound is enforced.

## Decision

### 1. `ac_state` approval verb + consumer

**New verb**, not a new representation: `brana backlog ac <id> approve` (CLI) and
`backlog_ac_approve(task_id)` (MCP). It is the sanctioned way to move a task to
`ac_state:approved`, replacing the untyped `backlog set <id> ac_state approved` escape hatch
for this transition (the generic `set` path remains available for the other transitions —
`none`→`proposed`, clearing to `null` — which are not human-approval events).

- **Precondition:** `acceptance_criteria` (ADR-047's field) must be non-empty. Approving an
  empty contract is a no-op error ("no acceptance criteria to approve — populate
  `acceptance_criteria` first"), not a silent state flip.
- **Source state:** accepts from `none` or `proposed` (a human may author+approve AC directly
  without a loop backfill step first; the loop-backfill path via `proposed` is the common
  case per `backlog-v3-schema.md`'s "loop backfills its own contracts" flow, not the only
  legal one).
- **Idempotent:** already-`approved` → no-op success, not an error (matches
  `validate_wave_status`'s "any-to-any" precedent — approval is a human action re-confirming
  state, not a strict state machine that forbids re-entry).
- **`ac <id> add <criterion>`** — explicitly **out of scope** for t-2812 and this ADR. AC
  authoring already has a working convention (`AC:` context lines lint into
  `acceptance_criteria`; the generic field can be set directly). Only the *approval* verb was
  missing a home. If a dedicated `add` verb is wanted later, it's its own task — not bundled
  here.
- **The consumer:** the loop runner (t-2813, §2 below) is the first and, for this epic, only
  real consumer. It filters candidate tasks to `ac_state:approved` before pulling — this is
  what closes the loop `backlog-v3-schema.md` describes ("you approve in the cockpit →
  approved → now it is loop-drainable") and what makes the approve verb more than a naming
  exercise.

### 2. Wave-drain → loop handoff contract

`wave drain <id>` (t-2775, unchanged) is a **point-in-time report**, not a queue handle: it
resolves the selector once, prints the matched list, and sets `wave.status: "draining"`. It
does not execute anything and does not freeze the matched list anywhere durable.

The loop runner (t-2813) is the actual consumer and owns re-resolution:

- **Eligibility to run:** the loop only pulls from waves whose `status == "draining"`. A wave
  in `queued` has not been drained (nothing to pull); a wave in `shipped` is done. This is the
  entire signal — no new wave field for "loop is watching this."
- **Re-resolve, don't trust the frozen snapshot.** On each pull cycle the loop calls the
  **same selector-resolution function `wave drain` uses** — not a re-implementation. This
  function must be a single `brana-core` export (e.g. `resolve_wave_selector(wave) ->
  Vec<Task>`) called identically by `cmd_wave_drain` and the loop driver, mirroring the
  `shape(task)` single-owner principle `backlog-v3-schema.md` already establishes for shape
  computation (replicated-logic drift is the named failure mode to avoid — see
  `pattern_replicated-logic-tests-rot_2026-06-11` and the `claude -p`-over-tasks.json
  divergence vector `backlog-v3-schema.md` calls out for `shape`). t-2775's implementation
  must land this resolver as an importable function, not inline it only in the CLI command
  body, so t-2813 has something to call.
- **Filter chain the loop applies** on top of the resolver's raw match: `status:pending ∧
  ac_state:approved`, then the WIP bound (§3). Selector match alone (what `drain` reports) is
  necessary but not sufficient for loop-eligibility — `drain`'s report and the loop's actual
  pull set are allowed to differ, and that difference (matched-but-not-yet-approved) is
  visible/expected, not a bug.
- **No auto-ship.** Per `wave-gate-enforcement.md` §1.4 (unchanged): the loop does not
  transition a wave to `shipped` when its matched set empties. An operator does that
  manually. The loop's job ends at "no eligible tasks this cycle" — it does not decide the
  wave is done, only that there's nothing to pull *right now*.
- **Runner shape:** native `/loop` (or `ScheduleWakeup`-paced dynamic loop) over the CLI/MCP
  surface — per `delegation-routing.md` compute routing, this is in-session orchestration
  work, not a `ruflo` `hive-mind`/`agent_execute` path (those are hollow under subscription,
  ADR-059). t-2813 implements the pull-and-work loop; it does not need a new daemon process.

### 3. WIP enforcement: on waves, at pull time, no default

Confirms t-2782's design direction (WIP moves from epics to waves) and resolves its three open
questions enough to unblock implementation, deferring only the *numeric default* to real usage
data (repeating the epic-cap mistake — guessing a number pre-data — is exactly what this ADR
must not do):

- **New field:** `wip_limit` on the wave object (nullable int, parallel to the retired
  `epic.wip_limit`). `null` = unbounded (the default for every wave until an operator opts in).
- **What counts as "live":** tasks matching the wave's selector with `status:in_progress`.
  Not "explicitly linked to the wave" — waves select, they don't own (ADR-065 D3's own
  framing: "It *selects* tasks; it does not *own* them"); membership is always computed via
  the selector, never a stored link, keeping this consistent with how `drain`'s match works.
- **Enforcement point:** at the **loop's pull step** (t-2813), not at `wave drain` and not at
  task `start`. `drain` only reports/gates on the *sibling* wave via `gate` (t-2775's
  existing scope) — it has no reason to also enforce WIP, since it doesn't execute anything.
  Task `start` stays ungated by waves entirely: a human can still manually start a
  wave-matched task outside the loop, same as today — waves don't gate creation/start the way
  epics used to, and this ADR doesn't change that. The loop is the only actor that "pulls
  jobs," so it's the only actor that needs to check the bound before pulling one more.
- **Mechanism:** before each pull, the loop counts current live tasks (as defined above) for
  the wave; if `count >= wip_limit`, skip pulling this cycle (poll again later — this is a
  natural fit for `ScheduleWakeup`'s dynamic-loop pacing, not a hard stop).
- **t-2782 still owns:** the exact default/derivation once real `drain` usage exists, any
  cockpit/reporting surface for "N/limit in flight," and whether a limit is ever enforced
  retroactively (e.g. a wave whose limit is lowered while over it — out of scope here, decide
  when it's observed).

## Consequences

- **t-2775** (wave drain CLI) needs one adjustment to its already-approved scope: land the
  gate-check + `tag:<name>` selector resolution as an importable `brana-core` function (not
  CLI-command-local), so §2's reuse requirement is satisfiable. This does not change
  `wave-gate-enforcement.md`'s behavior or test list — it's an internal-structure note for
  the implementer, not a spec rewrite.
- **t-2812** (ac_state approval verb) is unblocked by this ADR — scope is exactly §1: the
  `approve` verb, CLI + MCP, plus wiring the loop runner (t-2813) to filter on
  `ac_state:approved`. `ac <id> add` stays out of scope.
- **t-2813** (loop runner, capstone) is unblocked in design terms but stays practically
  blocked_by t-2775 and t-2812 landing first (existing `blocked_by` on the task is correct
  and unchanged) — this ADR defines the contract those two must expose, not a way to skip
  building them.
- **t-2782** (WIP-on-waves) gets its three open design questions resolved by §3 above; its
  remaining scope shrinks to: add the `wip_limit` field + validation, wire the loop's
  count-and-skip check, and decide the numeric default from real usage — no longer an open
  architecture question.
- **`wave-gate-enforcement.md`** is not amended in content — this ADR sits alongside it,
  covering what it explicitly deferred, not what it already specified.

## Alternatives considered

- **Enforce WIP at `wave drain` time** (cap the matched list drain reports). Rejected: `drain`
  is a snapshot report with no ongoing process attached to it; a cap there would be stale the
  moment a task elsewhere in the matched set finishes, and doesn't fit `drain`'s "report,
  don't execute" contract (`wave-gate-enforcement.md` §1.3).
- **Link tasks to waves explicitly (a stored membership field) instead of re-resolving the
  selector.** Rejected: contradicts ADR-065 D3's "waves select, don't own" framing and doubles
  the bookkeeping (selector *and* a link that can drift from it) for no benefit the selector
  doesn't already provide.
- **Auto-ship a wave when its matched set empties.** Rejected: already explicitly out of scope
  in `wave-gate-enforcement.md` §1.4 as a "reasonable fast-follow, not required" — this ADR
  doesn't reopen that call.
- **Guess a default `wip_limit` now** (e.g. port the retired epic default of 10). Rejected:
  this is the exact mistake ADR-065's own amendment names (9/55 epics sat 4-7x over an
  unvalidated default). No wave has drained yet in live data; `null`/unbounded is the only
  honest default until usage exists.
