---
status: accepted
---
# ADR-079: ac_state Approval, Wave-Drain→Loop Handoff, and WIP Location (amends ADR-065)

**Status:** Accepted (2026-08-13; challenged and amended same day — see §Challenge record)
**Date:** 2026-08-13
**Deciders:** Martín Rios
**Tags:** backlog, waves, ac, wip, loop, epic-entry, adr-065-followup
**Tasks:** t-2811 (epic), t-2775, t-2812, t-2813, t-2782
**Relates:** [ADR-065](ADR-065-epic-as-hierarchy-top.md) (waves as thin process objects, D3;
epic WIP cap retirement amendment) · [ADR-060](ADR-060-branch-strategy-autonomous-agents.md)
(execution contract for the loop's workers — §2b) ·
[ADR-062](ADR-062-runner-executor-sandbox.md) (sandbox precondition for unattended drain) ·
[ADR-067](ADR-067-retired-fields-write-guard.md) (`wip_limit` name reuse — §3) ·
[ADR-078](ADR-078-stale-task-park-via-tag.md) (`parked` exclusion in the eligibility filter) ·
ADR-047 + t-2288 (`ac-propose`, the existing proposer this ADR's approve verb completes) ·
[backlog-v3-schema.md](../features/backlog-v3-schema.md) (§ac_state, §Wave = Queue) ·
[wave-gate-enforcement.md](../features/wave-gate-enforcement.md) (t-2775's spec — unchanged,
referenced not superseded) · ADR-074/t-1994 (foreman loop protocol — t-2813 is a pre-foreman
interim and converges with that contract when ADR-074 lands)

---

## Context

t-2811 (epic: backlog-drain) diagnosed 2026-08-13 that three backlog-v3 features shipped
without the connective tissue that makes them mean anything:

1. **Waves** (ADR-065 D3) — CRUD exists, `drain` does not yet (t-2775, already spec'd,
   unblocked, S effort — this ADR does not change that spec).
2. **`ac_state`** — the field, validation (`none`/`proposed`/`approved`), and query filtering
   exist. The **proposer half is also already built**: `brana backlog ac-propose` (t-2288,
   CLI-only) emits the drain queue (`ac_state:none` minus research/review) and with `--apply`
   writes `ac_state:proposed` plus `proposed_acceptance_criteria` — a field **deliberately
   separate** from `acceptance_criteria` so a proposed contract gates nothing until promoted
   (rollup.rs's own design comment: "promotion moves this array into `acceptance_criteria`
   and flips `ac_state` to `approved`"). What is missing is exactly that promotion: **no
   approve/promote verb exists, and nothing anywhere consumes `ac_state:approved`.** (An
   earlier draft of this ADR claimed ac_state had zero writers/readers outright — corrected
   after fact-check: `ac-propose` writes it and branches on `none`; the accurate claim is
   the narrower one just stated.)
3. **WIP capping** — `check_epic_wip_cap()` retired 2026-08-12 (t-2727, ADR-065's amendment)
   because epics are unbounded groupings. Its replacement was redirected to waves (t-2782)
   but never designed.

Per `m-plus-discipline-enforcement.md`, the epic's implementation children are gated on an
ADR settling the cross-cutting contract before code starts. This is that ADR. It covers only
what `wave-gate-enforcement.md` explicitly deferred: what consumes `drain`'s output, what
"approved" means and how a task gets there, and where a WIP bound lives.

## Decision

### 1. `ac_state` approval verb: approve = promote + flip, human-only

**New verb:** `brana backlog ac <id> approve` (CLI) and `backlog_ac_approve(task_id)` (MCP).
It is the sanctioned transition to `ac_state:approved` and does two things atomically:

1. **Promote:** if `proposed_acceptance_criteria` is non-empty, move its contents into
   `acceptance_criteria` (the live gating field) and clear `proposed_acceptance_criteria`.
   This completes the promotion path t-2288's proposer was built against and never got.
2. **Flip:** set `ac_state: approved`.

- **Precondition:** at least one of `acceptance_criteria` / `proposed_acceptance_criteria`
  non-empty. Approving with both empty is an error ("no acceptance criteria to approve"),
  not a silent flip. (An earlier draft required `acceptance_criteria` non-empty — that would
  have rejected exactly the tasks `ac-propose` prepared, since the proposer populates the
  *other* field.)
- **Source state:** accepts from `none` or `proposed` (human may author+approve directly;
  the loop-backfill path via `proposed` is the common case, not the only legal one).
- **Idempotent on `approved`** — but see content-binding below.
- **Approval binds to content, not just state.** Any write to `acceptance_criteria` on a
  task whose `ac_state` is `approved` resets `ac_state` to `proposed` (enforced in
  `set_field`'s `acceptance_criteria` arm — shared layer, all write paths). An approval of
  criteria that were then edited is an approval of nothing; without this, a loop could
  propose, obtain approval, then reshape the contract while staying drainable (the
  ADR-076-D2 moving-target class).
- **No bypass via generic `set`.** `backlog set <id> ac_state approved` (and the MCP
  `backlog_set` twin) is **rejected** at the shared validation layer with a pointer to the
  verb ("use `backlog ac <id> approve`"). Without this the verb's precondition is
  decorative — today `set_field` accepts `approved` with empty AC. The other transitions
  (`none`/`proposed`/`null`) remain settable generically.
- **Human-only gate, structurally.** The loop runner's tool manifest (allowedTools/deny
  list, t-2813) **denies** `backlog ac approve` and `backlog_ac_approve`. The whole point of
  `approved` is a human trust boundary between selector-match and autonomous execution; a
  gate armed by the party it constrains is no gate
  (`pattern_gate-armed-by-the-party-it-constrains`, ADR-076 D4). Approval happens in an
  interactive human session, never inside the drain loop.
- **Which representation the grader trusts:** `acceptance_criteria` (the ADR-047 field) is
  the contract of record for loop grading. `AC:` context lines remain the human-authoring
  shorthand that lints into the field; the loop never reads `AC:` lines directly.
- **`ac <id> add`** — explicitly out of scope (authoring paths already exist); own task if
  ever wanted.

### 2. Wave-drain → loop handoff contract

`wave drain <id>` (t-2775, unchanged) is a **point-in-time report**: resolve selector once,
print matches, set `wave.status: "draining"`. It executes nothing and freezes nothing.

The loop runner (t-2813) is the consumer and owns re-resolution:

- **Eligibility to run:** pull only from waves with `status == "draining"`.
- **Re-resolve each cycle** via the **same brana-core selector resolver `wave drain` uses**
  (single owner, e.g. `resolve_wave_selector(wave) -> Vec<Task>`; t-2775 must land it as an
  importable function, not CLI-command-local — mirroring the `shape(task)` single-owner
  principle; replicated-logic drift is the named failure mode). Note for t-2775: the
  resolver now has two structurally different callers (one-shot CLI report vs. repeated
  per-cycle polling) — design the signature for both; likely still small, but it is a real
  second consumer, not a free refactor.
- **Eligibility filter** on the resolver's raw match:
  `status:pending ∧ ac_state:approved ∧ ¬tag:parked`, then the WIP bound (§3).
  The `parked` exclusion is load-bearing: ADR-078 parks tasks by tag while `status` stays
  `pending`, so without it the loop would autonomously work deliberately shelved tasks.
  `drain`'s report and the loop's pull set are allowed to differ; matched-but-not-approved
  (or parked) is visible and expected, not a bug.
- **No auto-ship** (unchanged from `wave-gate-enforcement.md` §1.4): the loop never sets
  `shipped`; "no eligible tasks this cycle" is not "the wave is done."

#### 2b. Execution contract — what "works them" means

An earlier draft specified the pull precisely and left the work implicit. That silence
recreated the exact shape ADR-059's OQ3 closure rejected in ruflo's `--claude` spawn (workers
without worktree isolation). Made explicit:

- **Routing class:** this is the *autonomous* row of `delegation-routing.md` ("native
  `/loop` + `claude -p` over tasks.json"), not in-session orchestration. The loop is the
  foreman-shaped puller; each pulled task is dispatched to an **executor** (`claude -p`, or
  an interactive build session when supervised).
- **ADR-060 invariants apply to every executor, non-negotiable:** work happens in an
  isolated ephemeral worktree cut from `dev`; result returns as a branch/PR into `dev`;
  the loop/executor never merges to `dev` or `main`, never pushes production, and **never
  sets `status:completed`** — a human gates promotion and completion.
- **The work goes through the build framework:** the executor runs the pulled task through
  `/brana:build` (or the runner's equivalent with the same gates — spec gate, TDD,
  challenger, build_step tracking) per `always-use-build-framework.md`. The approved AC is
  the machine-verifiable done-signal that framework grades; a bespoke execution path would
  bypass exactly the machinery that makes `approved` meaningful.
- **Sandbox precondition for unattended operation (ADR-062):** task `subject`/
  `description`/AC content is untrusted input flowing into executor prompts. Supervised
  interactive drain (human at the gates) may run without it; **unattended** drain
  (ScheduleWakeup-paced overnight operation) inherits ADR-062's sandbox as a hard
  precondition — t-2813 must not enable unattended mode before that gate is satisfiable.

### 3. WIP enforcement: on waves, at pull time, atomically, no default

Confirms t-2782's direction (WIP moves from epics to waves) and resolves its open questions,
deferring only the numeric default to real usage data:

- **New field:** `wip_limit` on the wave object — nullable **integer**, `null` = unbounded
  (the default until an operator opts in). Implementation notes for t-2782: `set_wave_field`
  is a hard allowlist that currently stores only strings — `wip_limit` needs a new
  integer-parsing arm (the first non-string wave field), plus the MCP `backlog_wave_set`
  mirror. **Name reuse is deliberate and scoped** (ADR-067): task-level `wip_limit` sits in
  `RETIRED_FIELDS` and its guard (`reject_retired_fields`) is task-object-scoped; wave
  writes must never route through it, retired-field validate checks stay `.tasks[]`-scoped,
  and `RETIRED_FIELDS` gets a comment noting the scope so a future grep-shaped guard
  extension doesn't wrongly reject the wave field.
- **What counts as "live":** tasks matching the wave's selector with `status:in_progress`.
  Computed, never a stored link (ADR-065 D3: waves select, don't own). **Accepted
  limitation of the no-stored-link design:** re-tagging a task mid-execution so it stops
  matching the selector silently frees a WIP slot while the work is still running — real
  concurrency can then exceed `wip_limit`. Named and accepted (consistent with D3's
  rationale) rather than fixed with a claim/lease mechanism this MVP doesn't need.
- **Enforcement point:** the **loop's pull step only** (t-2813). Not at `drain` (a snapshot
  report), not at task `start` (humans can still manually start wave-matched tasks outside
  the loop, same as today).
- **The pull is one atomic critical section.** Count-then-pull as two independent calls is a
  TOCTOU: two loop cycles (or loop + human start) both read `count < limit` and both
  proceed, overshooting the limit. The pull step must run inside a single
  `lock_tasks` RMW: lock → re-read fresh → count live → re-verify the target task is still
  `status:pending` (and still approved/unparked) → write `in_progress` → save → unlock.
  The existing unlocked read paths (e.g. `backlog_get`) are fine for reporting but must not
  feed the pull decision.
- **Overlapping selectors don't compose.** Two concurrently-draining waves whose selectors
  overlap each count a shared task against their own cap independently; per-wave budgets are
  not additive and a task pulled under one wave counts as live in every wave that matches
  it. The atomic pull (above) is what prevents two waves' loops double-pulling the same
  task. Supported, with these semantics — not an error.
- **Selector edits while draining are rejected.** `set_wave_field` refuses `selector`/`gate`
  writes while `status == "draining"` (error: requeue the wave first). Waves have no `log`
  field, so a mid-drain selector edit would silently redirect what the next cycle pulls
  with zero audit trail. Cheap validation arm, rides with t-2782's `wip_limit` arm.
- **t-2782 still owns:** the numeric default/derivation once real drain usage exists, any
  cockpit surface for "N/limit in flight," and retroactive-lowering semantics (decide when
  observed).

## Consequences

- **t-2775** (wave drain CLI): land the gate-check + `tag:` selector resolution as an
  importable brana-core function serving both callers (one-shot CLI, per-cycle loop
  polling). Behavior and test list per `wave-gate-enforcement.md`, unchanged.
- **t-2812** (approve verb): scope is §1 — promote+flip verb (CLI + MCP), the
  approved-write rejection in the generic `set` path, the AC-edit→`proposed` reset in
  `set_field`'s `acceptance_criteria` arm, and wiring t-2813's approved-filter. `ac add`
  stays out.
- **t-2813** (loop runner, capstone): §2 + §2b + §3's atomic pull. Stays `blocked_by`
  t-2775/t-2782/t-2812. Its tool manifest denies the approve verb (§1). Unattended mode is
  additionally gated on ADR-062's sandbox. Converges with the ADR-074/t-1994 foreman
  contract when that lands — this is the interim, not a competing loop architecture.
- **t-2782** (WIP-on-waves): design questions resolved by §3; remaining scope: `wip_limit`
  integer arm + MCP mirror + draining-edit rejection in `set_wave_field`, the loop's
  atomic count-and-pull, ADR-067 scope comment, numeric default from usage data.
- **`wave-gate-enforcement.md`**: not amended — this ADR covers what it deferred.
- **Review checkpoint (pre-registered, per ADR-076's precedent):** after the first ~10 real
  wave drains, review: has any wave set `wip_limit`? has `ac approve` been used outside this
  epic's own tasks? If both answers are no, the unused halves get the ADR-076 treatment —
  revisit and shrink rather than let dead mechanism accrete.

## Alternatives considered

- **Enforce WIP at `wave drain` time.** Rejected: `drain` is a snapshot report; a cap there
  is stale immediately and violates its "report, don't execute" contract.
- **Stored wave-membership link instead of re-resolving.** Rejected: contradicts ADR-065 D3
  and doubles bookkeeping (selector + a link that drifts from it).
- **Auto-ship on empty matched set.** Rejected: already out of scope in
  `wave-gate-enforcement.md` §1.4; not reopened.
- **Guess a default `wip_limit` now.** Rejected: the epic-cap retirement is the cautionary
  tale (9/55 epics 4-7x over an unvalidated default). `null` is the only honest default
  until usage exists.
- **Approve verb without promotion (state-flip only).** Rejected after fact-check: the
  existing proposer writes `proposed_acceptance_criteria`, so a flip-only verb with an
  `acceptance_criteria` precondition rejects every loop-prepared task; promotion is the
  missing half of t-2288's own documented design.
- **Content-hash snapshot at approval, verified at drain time** (instead of edit-resets-
  state). Considered for binding approval to content; rejected as heavier — the reset rule
  achieves the same trust boundary with one line in an existing match arm and no new stored
  state.

## Challenge record (2026-08-13)

Reviewed same-day by three independent passes (adversarial challenger, code fact-check,
cross-ADR alignment audit). Material findings, all amended into the text above: the original
§1 precondition was broken against the existing `ac-propose` proposer (fact-check — approve
now promotes); the Context's "zero writers/readers" audit claim was wrong (corrected);
execution contract was entirely implicit (alignment BLOCKER — now §2b); the WIP check was a
TOCTOU as described (challenger MAJOR — now an atomic critical section); approval didn't
bind to content (challenger MAJOR — now the edit-reset rule); parked tasks were
loop-eligible (now excluded); the generic-`set` bypass made the precondition decorative (now
rejected at the shared layer); self-approval was structurally possible (now denied in the
runner manifest); plus minor items: overlapping-selector semantics, mid-drain selector-edit
rejection, the re-tag WIP-slot leak named as accepted limitation, ADR-067 name-scoping, and
the pre-registered review checkpoint.
