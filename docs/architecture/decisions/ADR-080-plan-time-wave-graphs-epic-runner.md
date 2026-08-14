---
status: draft
---
# ADR-080: Plan-Time Wave Graphs, the Epic Runner, and Leases (extends ADR-079)

**Status:** Draft (2026-08-13, t-2828 — investigation deliverable, pre-challenge)
**Date:** 2026-08-13
**Deciders:** Martín Rios
**Tags:** backlog, waves, loop, planning, epic-entry
**Tasks:** t-2828 (design), t-2811 (epic backlog-drain), t-2820 (epic loop-first — reconciled here)
**Relates:** [ADR-079](ADR-079-backlog-drain-loop-handoff.md) (the substrate this extends: `ac approve`, drain→loop handoff, WIP-at-pull) · [ADR-065](ADR-065-epic-as-hierarchy-top.md) (waves as thin process objects — D1's selector addition and D4's lease stay within its computed-not-stored stance) · [ADR-062](ADR-062-runner-executor-sandbox.md) (unattended gate — unchanged) · [ADR-078](ADR-078-stale-task-park-via-tag.md) (`parked` — reused by the dead-letter path) · [wave-pipeline.md](../../ideas/wave-pipeline.md) (concept doc: four rings, four primitives, seven laws) · [loops-library.md](../../ideas/loops-library.md) (entry schema, pull interface, the lease gap this ADR closes) · [drain-loop.md](../../guide/workflows/drain-loop.md) (the single-wave runner the epic runner generalizes)

---

## Context

The first live drain (t-2813, 8 supervised beats) proved the pipeline end to end — and
showed the friction: every wave was born by hand (tag tasks, create wave, chain gates,
approve one task at a time, point a loop at one wave). t-2828's brief: waves should be
**born at planning time**, and the loop should **follow the wave graph over an epic**,
not be pointed at one wave. Two epics were independently designing adjacent machinery
(t-2811 backlog-drain: the task-queue substrate; t-2820 loop-first: the loop machinery);
both sessions flagged the scope overlap for reconciliation here (§6).

Design constraint carried throughout: **the vocabulary is closed** — queue, pump, valve,
gauge ([wave-pipeline.md](../../ideas/wave-pipeline.md)). Every capability below is an
arrangement of those four; none adds a fifth primitive. The seven operating laws are the
acceptance lens (§7).

## Decisions

### 1. `parent:` selector — waves derived from plan structure, no tagging

`resolve_wave_selector` gains a second selector form (today: `tag:<name>` only):

- **`parent:<id>`** — matches every task whose parent chain contains `<id>`
  (descendants of a milestone/phase/task node). Same eligibility filter and atomic
  pull as `tag:` (ADR-079 §2/§3) — the selector form changes *membership*, nothing
  downstream.
- Membership is **computed at resolution time** from the parent chain (ADR-065 D3:
  waves select, they don't own). Re-parenting a task moves it between waves with no
  wave edit — same accepted-limitation class as ADR-079 §3's re-tag note.
- `tag:` remains the hand-rolled form (ad-hoc waves spanning plan structure).

### 2. Plan emits the wave graph

`/brana:backlog plan` (and `/brana:build` DECOMPOSE when decomposing under an epic)
gains a **WAVES step** between DEPS and PROPOSE:

1. **Default grouping: one wave per milestone**, selector `parent:<ms-id>` — the plan's
   own structure is the wave graph; no tags are written.
2. **Gate chain from the computed dependency structure:** if milestone B's tasks depend
   on A's (any `blocked_by` edge crossing A→B, or explicit sequencing), wave-B gets
   `gate: wave-A`. Independent milestones share a gate or have none (parallel waves).
3. **Contract seeded from the milestone's definition of done** (prose; §5 keeps
   contracts human-graded).
4. The proposed wave graph is shown in PROPOSE alongside the task tree — **the human
   approves the graph in the same gesture as the plan** (studio output). WRITE creates
   the wave objects with `status: queued`.
5. Wave naming: `<epic-slug>-<milestone-slug>`.

Nothing requires plan-born waves: `wave add` stays for hand-rolled ones.

### 3. The epic runner — a graph-walking generalization of drain-loop.md

A second committed loop entry, **`epic-drain`** (loops library). Beat procedure:

1. **PREFLIGHT (cheap):** resolve the epic's waves — waves whose selector root
   (`parent:<id>`'s node) has this epic as its epic-ancestor. Computed live, no stored
   wave→epic link. Topo-sort by `gate`.
2. **Find the active wave:** first in topo order with `status != shipped` whose gate is
   `null` or names a `shipped` wave.
3. **Arm if queued:** the runner MAY run `wave drain <id>` on that wave. Arming is not
   a human valve *here* because the human valve already fired upstream: the gate wave
   was human-shipped (or the human approved the graph at plan time for the first wave).
   Drain remains a report + status flip; re-draining a draining wave is a no-op report
   (idempotent — law 4).
4. **Pump:** `wave pull` → work the pulled task through the full build framework —
   identical to [drain-loop.md](../../guide/workflows/drain-loop.md) from here,
   including every denied verb.
5. **Contract-met announcement:** when the wave's matched set has no pending work left
   (matched tasks all completed/cancelled), announce **"contract likely met"** to the
   cockpit digest and back off. The runner **never ships** — one human ship decision
   per wave is what makes epic-looping safe (unchanged from ADR-079 / §1.4).
6. **Advance:** a human `wave set <id> status shipped` unlocks the next wave; the next
   beat finds it via step 2. All waves shipped → epic drained → STOP (real signal).
7. **Escalation routing (two rooms):** anything the runner is unsure about — scope
   questions, conflicting AC, design doubts — goes to the **studio agenda queue**,
   never the cockpit digest. Rubber-stamp items (ship valve, merge valve) go to the
   digest. When unsure which, the agenda (under-escalating a design question into a
   rubber-stamp is the worse failure).

Runner denied verbs = drain-loop.md's table **plus**: `wave set * status shipped`,
`wave set * gate/selector`, and the batch approve verb (§4). t-2827 (technical
enforcement of denials) covers this list too.

### 4. Coarser valve: wave-level batch approve

**New verb:** `brana backlog wave approve <wave-id>` (CLI) + `backlog_wave_approve`
(MCP). Human-only, cockpit-shaped:

- Resolves the wave's selector, lists matched tasks with `ac_state: proposed`, shows
  each task's proposed criteria, takes **one confirmation**, then applies the existing
  per-task promote+flip (ADR-079 §1) to each. No new state semantics — a batch loop
  over the sanctioned verb, all its bindings intact (content-binding reset, no-bypass).
- Tasks with `ac_state: none` in the matched set are listed but skipped (nothing to
  approve) — the gap is visible, not silently absorbed.
- Denied in the runner manifest, same trust boundary as `ac approve`.
- Ship is **not** batched: one wave, one ship decision, always.

### 5. Leases — closing t-2813's crashed-pump gap

Confirmed gap: `wave pull` writes `in_progress` with no claimant; a pump that dies
between pull and ack strands the task forever (loops-library §Pull interface, hard
edge 3).

- **Pull takes a lease.** Inside the same `lock_tasks` critical section, `wave pull`
  writes `lease: {claimant, expires}` on the task — `claimant` = loop name + session
  id, `expires` = now + TTL. TTL default **24h** (a build beat spans hours; tune from
  beat telemetry later — same no-guessed-default stance as `wip_limit`, but a lease
  needs *some* expiry to exist at all, and 24h only delays reclaim, never loses work).
- **Ack clears it.** Build CLOSE (task → completed) and any human `status` write clear
  `lease`. Manual `backlog start` does **not** take a lease — leases mark *pump-pulled*
  work; human work is not watchdog-reclaimable.
- **Reclaim is the watchdog's job** (external, law 3 — never the pump's own): task
  `in_progress` ∧ lease expired → reset to `pending`, clear lease, append a reclaim
  note. **Second reclaim of the same task → dead-letter:** tag `parked` (ADR-078) +
  `dead-letter` — which lands it in the standing triage wave (§6) and out of every
  eligibility filter (ADR-079 already excludes parked).
- Schema: new nullable task field `lease` (object). Not a retired-field name (ADR-067
  clean). Absent = no lease — assert key absence, not null.

### 6. Scope reconciliation: backlog-drain × loop-first

The boundary rule: **backlog-drain (t-2811) owns the task-queue substrate; loop-first
(t-2820) owns the loop machinery that runs against any queue.**

| Capability | Epic | Landing |
|---|---|---|
| `parent:` selector (§1), plan WAVES step (§2) | backlog-drain | new impl tasks (this ADR's tree) |
| `wave approve` batch (§4), lease field + pull change (§5) | backlog-drain | new impl tasks |
| `epic-drain` committed loop entry (§3) | backlog-drain authors the procedure | **filed as a loops-library entry** (t-2826 format) — first proof the library holds >1 entry |
| `wave board` gauge (gate-chain graph + counts, the L0 cockpit digest) | backlog-drain (CLI) | new impl task; TUI (t-2825) renders it later |
| Watchdog + lease reclaim | **loop-first** — the watchdog is the external meta-gauge (law 3); reclaim (§5) is its second job, consuming backlog-drain's lease data | extend t-2823's follow-on scope |
| Loops library catalog + entry schema + `records:` beat schema | **loop-first** (t-2826 — its feature spec is where the entry format lives) | unchanged |
| TUI dashboard | **loop-first** (t-2825) | unchanged |
| Autonomy ladder / per-wave autonomy promotion | **loop-first** (t-2824's ADR) — a wave has no autonomy field; autonomy is a property of the loop you arm, not the queue | defer to t-2824 |
| Foreman (t-1994) | graduation target, re-scoped under backlog-drain once epic-drain has promotion evidence | unchanged from loop-first doc |

Brainstorm items (a)–(h) resolved as arrangements, no new mechanism:
- **(b) standing waves** — a wave with `gate: null` that is never shipped (e.g.
  selector `tag:dead-letter`, the triage wave). A usage pattern; zero code.
- **(c) shadow drain** — `wave pull --dry-run`: report what would be pulled, write
  nothing. Small CLI arm; the rehearsal-beat primitive (law 6).
- **(g) dead-letter wave** — standing triage wave over `tag:dead-letter ∧ parked`,
  fed by the watchdog's second-reclaim path (§5); its closer pump is a human triage
  session (cockpit), honoring law 2.
- **(h) telemetry** — per-beat records are the loops-library `records:` schema
  (loop-first's scope); wave-level counts are computed from tasks.json by `wave
  board`, no new store. t-2782 keeps the wip-default question.

### 7. Machine-checkable contracts: deferred, no auto-advance

Whether a structured, machine-verifiable wave contract may ever auto-advance a gate is
**its own ADR** (the trust-boundary analysis deserves the full treatment ADR-079 §1
got). Until then: contracts stay prose, the runner announces contract-likely-met (§3.5)
as a cockpit item, and **no gate advances without a human ship** — the conservative
default is the current behavior, so deferral costs nothing.

## Seven-laws check (acceptance lens)

1. Runner coordinates with nothing — it pulls from waves, escalates into queues
   (digest/agenda). 2. Dead-letter path exists with a named closer (§5/§6g). 3. Reclaim
lives in the external watchdog, never the pump. 4. Every beat step is
replay-safe (atomic pull; drain re-run is a no-op report). 5. Preflight is one
tasks.json read + topo-sort. 6. `--dry-run` rehearses without arming. 7. Loop entries
inherit /loop lifecycle (7-day expiry, Esc-kill); the epic runner terminates on a real
signal (all waves shipped).

## Consequences

- ADR-065's wave object grows nothing; ADR-079's contracts are unchanged — this ADR
  only adds a selector form, a batch wrapper over an existing verb, a lease field, and
  two committed procedures (plan WAVES step, epic-drain entry).
- MODEL-001 updates (DDD): Wave entry is stale ("selector resolution is not yet
  implemented" — it shipped in t-2775/t-2813); add **Lease**, **Wave graph**,
  **Epic runner**, **Standing wave**, **Dead-letter wave** to the ubiquitous language.
- Implementation tree (emitted by t-2828's REPORT, waves included — the plan that
  plans itself): selector + dry-run · plan WAVES step · wave approve · lease + reclaim
  handoff spec to watchdog · wave board · epic-drain entry.
- Review checkpoint (ADR-076 pattern): after the first epic drained end-to-end via
  epic-drain, review whether `parent:` waves, batch approve, and leases were each
  actually exercised; unexercised halves get the shrink treatment.

## Alternatives considered

- **Stored wave→epic link** (field on wave). Rejected: computable from the selector
  root's epic-ancestor; ADR-065 D3 again.
- **Runner arms nothing (human drains every wave).** Rejected: the human decision
  already lives at ship; requiring a second manual arm per wave re-creates the manual
  friction t-2828 exists to remove, and adds no trust boundary (drain executes
  nothing).
- **Lease TTL as wave field now.** Rejected: one global default until beat telemetry
  says otherwise (wip_limit precedent).
- **Batch approve as a new state transition.** Rejected: a loop over the existing verb
  keeps every ADR-079 §1 binding for free.
- **Auto-advance gates on machine-verified contracts now.** Deferred (§7).
