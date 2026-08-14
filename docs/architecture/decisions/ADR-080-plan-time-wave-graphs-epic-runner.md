---
status: accepted
---
# ADR-080: Plan-Time Wave Graphs, the Epic Runner, and Leases (extends ADR-079)

**Status:** Accepted (2026-08-14; challenged twice + studio-synced same session — see §Challenge record)
**Date:** 2026-08-13
**Deciders:** Martín Rios
**Tags:** backlog, waves, loop, planning, epic-entry
**Tasks:** t-2828 (design), t-2811 (epic backlog-drain), t-2820 (epic loop-first — reconciled here)
**Relates:** [ADR-079](ADR-079-backlog-drain-loop-handoff.md) (the substrate this extends: `ac approve`, drain→loop handoff, WIP-at-pull) · [ADR-065](ADR-065-epic-as-hierarchy-top.md) (waves as thin process objects — D1's selector addition and D4's lease stay within its computed-not-stored stance) · [ADR-062](ADR-062-runner-executor-sandbox.md) (unattended gate — unchanged) · [ADR-078](ADR-078-stale-task-park-via-tag.md) (`parked` — reused by the dead-letter path) · [wave-pipeline.md](../../ideas/drained/wave-pipeline.md) (concept doc: four rings, four primitives, seven laws) · [loops-library.md](../../ideas/drained/loops-library.md) (entry schema, pull interface, the lease gap this ADR closes) · [drain-loop.md](../../guide/workflows/drain-loop.md) (the single-wave runner the epic runner generalizes)

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
gauge ([wave-pipeline.md](../../ideas/drained/wave-pipeline.md)). Every capability below is an
arrangement of those four; none adds a fifth primitive. The seven operating laws are the
acceptance lens (§7).

## Decisions

### 1. `parent:` selector — waves derived from plan structure, no tagging

`resolve_wave_selector` gains a second selector form (today: `tag:<name>` only):

- **`parent:<id>`** — matches every task whose parent chain contains `<id>`
  (descendants of a milestone/phase/task node). Same eligibility filter and atomic
  pull as `tag:` (ADR-079 §2/§3).
- **Downstream is NOT selector-agnostic today — explicit impl requirement.** The
  membership resolver is not the only selector consumer: `wave_pull_decision`
  (wave.rs) computes the wip_limit `live` count by hand-stripping the `tag:` prefix
  instead of calling `resolve_wave_selector`. Against a `parent:` wave that strips to
  `""`, the live count is 0 forever and `wip_limit` is silently defeated — for
  exactly the waves the plan emits. The `parent:` task must route **every** selector
  consumer (membership, live count, and any future one) through the single resolver,
  with a test asserting `AtLimit` fires on a `parent:` wave. (Challenge finding 1 —
  code-verified.)
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
   `gate: wave-A`. Independent milestones share a gate or have none. **"Ungated"
   means order-free, not concurrent:** a single epic-drain instance drains one wave at
   a time in topo order; two gate-satisfied waves are drained sequentially, first
   wins. Multi-instance concurrent draining of one epic has no wave-level claim
   mechanism and is **out of scope** in this slice (two instances would converge on
   the same "first ready" wave — challenge finding 7); the per-task atomic pull merely
   makes it safe, not useful. Design a wave-claim story before ever recommending it.
   **The WAVES step validates its own output:** the emitted gate chain is checked for
   cycles at emission time (cheap DFS) — the runner's PREFLIGHT cycle STOP (§3.1) is
   the last line of defense, not the first (round-2 challenge).
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
   wave→epic link. Topo-sort by `gate`. **Cycle detection is mandatory:** a cyclic
   gate chain (possible — `set_wave_field`'s `gate` arm has no referential or cycle
   check) must STOP the loop with a loud diagnostic routed to the studio agenda, never
   stall silently as if waiting on a human ship (challenge finding 9).
   **Scope: the epic runner walks `parent:` waves only.** A `tag:` selector has no
   single root node — its matches can span epics or none — so hand-rolled `tag:`
   waves are structurally outside any epic graph. They drain via the single-wave
   [drain-loop.md](../../guide/workflows/drain-loop.md), unchanged; a `tag:` wave may
   still appear as another wave's `gate` (the gate check is per-wave and
   selector-blind). Accepted scope, not an oversight (challenge finding 6).
2. **Find the active wave:** first in topo order with `status != shipped` whose gate is
   `null` or names a `shipped` wave.
3. **Arm if queued:** the runner MAY run `wave drain <id>` on that wave. The human
   authorization for autonomous arming is **launching the runner itself**: `/loop
   epic-drain <epic>` is a deliberate, named human action, temporally proximate to
   execution — the human who starts an epic runner is authorizing it to open that
   epic's gate-satisfied queues as the graph unlocks. (Plan-approval alone is NOT the
   arming valve — a plan can be approved weeks before anyone chooses to drain it;
   challenge finding 3.) For waves after the first, the upstream human ship is a
   second, per-wave human signal on top of that. Drain remains a report + status
   flip; re-draining a draining wave is a no-op report (idempotent — law 4).
4. **Pump:** `wave pull` → work the pulled task through the full build framework —
   identical to [drain-loop.md](../../guide/workflows/drain-loop.md) from here,
   including every denied verb.
5. **Contract-met announcement:** when the wave's matched set is **non-empty** and has
   no pending work left (matched tasks all completed/cancelled), announce **"contract
   likely met"** to the cockpit digest and back off. **The check is derived at
   announce time from a fresh read of tasks.json** — same fresh-read discipline as
   the pull; a stale in-memory view must not be able to announce a closed wave
   (closure is derived, never asserted — studio sync 2026-08-14). An **empty matched
   set is not contract-met** — it is vacuous truth (undecomposed milestone, deleted
   selector root, pure-planning milestone) and routes to the **studio agenda** as
   "wave matched zero tasks — needs a look," never to the ship digest (challenge
   finding 5). The runner **never ships** — one human ship decision per wave is what
   makes epic-looping safe (unchanged from ADR-079 / §1.4).
6. **Advance:** a human `wave set <id> status shipped` unlocks the next wave; the next
   beat finds it via step 2. All waves shipped → epic drained → STOP (real signal).
7. **Escalation routing (two rooms):** anything the runner is unsure about — scope
   questions, conflicting AC, design doubts, **and any item it cannot confidently
   classify** — goes to the **studio agenda queue**, never the cockpit digest.
   Rubber-stamp items (ship valve, merge valve) go to the digest. The agenda is the
   default under uncertainty (under-escalating a design question into a rubber-stamp
   is the worse failure).

**The beat is the seven-step skeleton, deliberately** (wave-pipeline.md §The skeleton
match — the runner is designed against the merged model): preflight re-read = ORIENT ·
atomic pull = SELECT (externalized queue-side, unbypassable) · build framework = ACT ·
gates/tests = MEASURE · JUDGE split by reversibility — machine judges for reversible
outcomes, human valves for irreversible ones · structured beat record + task-context
write = ASSIMILATE · pacing `{active, waiting, empty}` = RESTART. Two mechanical
consequences, not just description: **(a) the machine half of JUDGE is structurally
fresh-context** — challenger/evaluator run as separately-spawned workers per beat,
never inline in the runner's own context (Actor≠Evaluator is a process separation;
a beat that self-reviews is self-judging); **(b) the beat record is emitted from beat
1** with its schema single-sourced in the loops-library contract — referenced, never
duplicated here.

Runner denied verbs = drain-loop.md's table **plus**: `wave set * status shipped`,
`wave set * gate/selector`, the batch approve verb (§4), and **inline self-review in
place of a spawned challenger/evaluator**. t-2827 (technical enforcement of denials)
covers this list too. The runner prompt must not hardcode assumptions about which
skills are model-invocable (t-2832 will re-taxonomize skill frontmatter; the runner
stays order-independent of that change).

### 4. Coarser valve: wave-level batch approve

**New verb:** `brana backlog wave approve <wave-id>` (CLI) + `backlog_wave_approve`
(MCP). Human-only, cockpit-shaped:

- Resolves the wave's selector, lists matched tasks with `ac_state: proposed`, shows
  each task's proposed criteria, takes **one confirmation per batch of at most 10**,
  then applies the existing per-task promote+flip (ADR-079 §1) to each. No new state
  semantics — a batch loop over the sanctioned verb, all its bindings intact
  (content-binding reset, no-bypass). **The batch cap is the rubber-stamp guard**
  (challenge finding 8): ADR-079 §1's trust boundary is a human actually reading
  criteria before arming autonomous work; past ~10 items a single confirmation stops
  being review. Larger waves approve in successive capped batches, each explicitly
  confirmed.
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
- **Reclaim is a pump, not the watchdog.** The four-primitive vocabulary says gauges
  never act; resetting `in_progress → pending` is moving work a stage, i.e. pump
  behavior (challenge finding 4). Split: the **watchdog stays a pure gauge** — it
  reads lease state and *surfaces* expired leases in its digest; a separate tiny
  **`lease-reclaimer` pump** (its own loops-library entry, external to every drain
  loop per law 3) performs the reset. Both live in the loop-first epic.
- **Reclaim is evidence-gated, not timer-only — the double-execution fence**
  (challenge finding 2). An expired lease alone does not prove the pump is dead; a
  slow build past TTL is alive. The reclaimer resets a task only when the lease is
  expired **and** the task's branch shows no executor liveness (no new commits within
  the TTL window) — gate the destructive act on proof, not assertion. Two designed
  backstops if a presumed-dead executor returns anyway: (a) the task's branch name is
  deterministic (`…/t-NNN-…`), so a second executor's `worktree add` on the same
  branch fails loudly at dispatch; (b) the reclaim note travels to the merge valve,
  where the human sees the task was reclaimed before accepting either result. These
  are named contracts of the design, not accidents.
- **Reclaims are counted in schema, not inferred:** new nullable task field
  `reclaim_count` (int), incremented by the reclaimer in the same write as the reset,
  removed on task completion. It must survive lease clearing — which is why it is not
  inside `lease` (round-2 challenge BLOCKER: an uncounted "second reclaim" rule would
  force schema invention mid-implementation).
- **Second reclaim of the same task (`reclaim_count ≥ 2`) → dead-letter:** tag
  `parked` (ADR-078) + `dead-letter` — which lands it in the standing triage wave
  (§6) and out of every eligibility filter (ADR-079 already excludes parked).
- **Open question, named (not silently deferred): who reclaims the reclaimer?** The
  reclaimer/watchdog pair is currently a SPOF with no meta-answer beyond "the human
  notices the digest went quiet." Same deferred-item status as §7's auto-advance
  question (challenge finding 12).
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
| Watchdog (gauge) + `lease-reclaimer` (pump) | **loop-first** — watchdog reads and surfaces lease state (pure gauge, law 3); the reclaimer is a separate tiny pump acting on what the watchdog surfaces (§5), consuming backlog-drain's lease data | extend t-2823's follow-on scope; two catalog entries, not one |
| Loops library catalog + entry schema + `records:` beat schema | **loop-first** (t-2826 — its feature spec is where the entry format lives) | unchanged |
| TUI dashboard | **loop-first** (t-2825) | unchanged |
| Autonomy ladder / per-wave autonomy promotion | **loop-first** (t-2824's ADR) — a wave has no autonomy field; autonomy is a property of the loop you arm, not the queue | defer to t-2824 |
| Foreman (t-1994) | graduation target, re-scoped under backlog-drain once epic-drain has promotion evidence | unchanged from loop-first doc |

Brainstorm items (a)–(h) resolved as arrangements, no new mechanism:
- **(b) standing waves** — a wave with `gate: null` that is never shipped (e.g.
  selector `tag:dead-letter`, the triage wave). A usage pattern; zero code.
- **(c) shadow drain** — `wave pull --dry-run`: report what would be pulled, write
  nothing. Small CLI arm; the rehearsal-beat primitive (law 6).
- **(g) dead-letter wave** — standing triage wave, selector `tag:dead-letter` (the
  selector grammar has no AND; this is subset-equivalent because the reclaimer always
  applies `parked` + `dead-letter` together — do not go looking for compound-selector
  support, it was never built). Fed by the second-reclaim path (§5); its closer pump
  is a human triage session (cockpit), honoring law 2.
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
   (digest/agenda). 2. Dead-letter path exists with a named closer (§5/§6g). 3. Lease
observation lives in the external watchdog (gauge) and reclaim in a separate external
reclaimer pump — neither inside the loops they guard. 4. Every beat step is
replay-safe (atomic pull; drain re-run is a no-op report). 5. Preflight is one
tasks.json read + topo-sort. 6. `--dry-run` rehearses without arming. 7. Loop entries
inherit /loop lifecycle (7-day expiry, Esc-kill); the epic runner terminates on a real
signal (all waves shipped).

## Consequences

- ADR-065's wave object grows nothing; ADR-079's contracts are unchanged — this ADR
  only adds a selector form, a batch wrapper over an existing verb, a lease field, and
  two committed procedures (plan WAVES step, epic-drain entry).
- MODEL-001 updates (DDD): **two** stale Wave statements, not one — "selector
  resolution is not yet implemented" (line ~409; shipped in t-2775/t-2813) and "gate
  (nullable wave id, **unenforced**)" (line ~25; `check_wave_gate` is implemented and
  tested since t-2775) — fix both in the same pass (challenge finding 10); add
  **Lease**, **Wave graph**, **Epic runner**, **Standing wave**, **Dead-letter wave**
  to the ubiquitous language.
- Implementation tree (emitted by t-2828's REPORT, waves included — the plan that
  plans itself): selector + dry-run · plan WAVES step · wave approve · lease + reclaim
  handoff spec to watchdog · wave board · epic-drain entry. **The epic-drain entry's
  acceptance bar is proof-of-life** (materialization rule: a band exists only once
  something has cycled in it): N real supervised beats completed with structured
  records emitted — completion graded, not asserted. Wave sequencing across lanes:
  gate the staged `drain-3` wave (t-2831–t-2836) on `adr080-consumers` — the binding
  system constraint is human review rate (~1/day, probe-derived), so waves serialize
  by gates rather than trusting per-wave wip; drain-3 then exercises leases + batch
  approve as the third dogfood.
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
- **Timer-only lease reclaim (no liveness evidence).** Rejected: an expired lease on a
  slow-but-alive pump would trigger double execution; reclaim gates on proof (§5).
- **Lease-renewal heartbeat from the executor.** Rejected for this slice: `claude -p`
  executors have no natural mid-build hook to renew from, and evidence-gated reclaim
  (branch commits ARE the heartbeat) gets the same protection without new machinery.

## Challenge record

**Round 1 (2026-08-13, context-isolated challenger, code-verified):** verdict
RECONSIDER on the pre-challenge draft; all findings amended into the text above.
BLOCKER-class: the §1 "nothing downstream changes" claim was false against
`wave_pull_decision`'s hardcoded `tag:` strip (wip_limit silently defeated for
`parent:` waves — now an explicit impl requirement with a named test); lease reclaim
had no fencing (now evidence-gated with two named backstops); first-wave arming was
justified by stale plan-approval (now justified by the temporally-proximate human act
of launching the runner). MAJOR: watchdog-as-reclaimer violated the gauge primitive
(split into gauge + reclaimer pump); vacuous contract-met on empty matched sets (now
routed to the studio agenda); `tag:` waves structurally invisible to the runner (now
named accepted scope); "parallel waves" overpromised under a single runner instance
(scoped to order-free, multi-instance deferred); unbounded batch approve (capped at
10 per confirmation). MINOR: gate-cycle detection made mandatory in PREFLIGHT; both
MODEL-001 stale lines flagged, not one; reclaimer SPOF named as an open question.
**Round 2 (2026-08-13, second isolated challenger, against the implementation tree):**
verdict PROCEED WITH CHANGES; amendments applied. BLOCKER: "second reclaim →
dead-letter" had no counting mechanism in schema — `reclaim_count` named (§5).
MAJOR: doc-sync task wired behind the watchdog/reclaimer task so MODEL-001 never
describes unbuilt machinery; `wave board` reclassified as real Rust needing
tests-first; explicit "zero direct selector string parsing — resolve_wave_selector
exclusively" AC added to every new selector consumer (the finding-1 bug class,
prevented by AC rather than rediscovered). MINOR: lease task sequenced after the
selector task (same critical-section functions); plan-time gate-cycle DFS added to
§2; fixture-epic dry-run made an explicit deliverable of the epic-drain entry;
standing dead-letter wave creation tracked as an operational AC, not left to memory.
Notes: wave-4's `parent:` overlap with shipped wave-3 tasks verified harmless in code
(completed tasks match neither eligibility nor live-count) — overlap accepted, no
sub-milestone; §6(g) selector prose corrected (no AND grammar exists).
