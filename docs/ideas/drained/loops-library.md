---
title: Loops Library — catalog of committed loop definitions
status: idea
created: 2026-08-13
task: t-2826
related: [t-2820, t-2825, t-2813, ADR-079, t-2828]
produced_by: [docs/ideas/loop-first-redesign.md]
---
# Loops Library

> Brainstormed 2026-08-13, shaped 2026-08-14. **Division of labor:**
> [wave-pipeline.md](wave-pipeline.md) owns the philosophy (four rings, four primitives,
> seven laws, two rooms); **this doc owns the contract** — entry schema, queue types,
> pull-interface verbs, per-beat records, and the proof-of-life acceptance bar; **t-2828**
> owns the convergence design (ADR extending [ADR-079](../architecture/decisions/ADR-079-backlog-drain-loop-handoff.md),
> epic runner, leases); **t-2826** builds the catalog itself. Lineage:
> [loop-first-redesign.md](loop-first-redesign.md) → this.

## Problem

Loop definitions are scattered: ephemeral `/loop` prompts die with their session; the one committed example (`docs/guide/workflows/drain-loop.md`, t-2813) proves the committed-prompt pattern works. Like skills, loops need a library: versioned, discoverable, reusable, reviewable.

## Entry schema (draft)

Frontmatter per loop:
- `name`, `cadence` (default), `pacing`: time | work | event. **Work-paced loops express pacing as `{active_delay, waiting_delay, empty_delay}`, not one cadence number** — the loop knows its state from the pull outcome (Pulled / AtLimit / NoneEligible map 1:1). Field-tested by the first live drain loop (2026-08-13, 8 beats): ~90s while building, 1200s backed off waiting on a challenger.
- `autonomy`: L0–L3 + `supervised` flag (unattended hard-gated on ADR-062 sandbox)
- `drains:` / `fills:` — queue references (see Queue types)
- `spawns:` — which other loops/runners a beat may launch + max concurrency (recursion bound)
- `records:` — the structured per-beat record schema (Pavlyshyn: memory is the loop's product). Always emitted; verbosity is a render toggle, never an emit toggle. Declares progress kind: bounded (queue n/total → progress bar) vs unbounded (heartbeat).
- Body: beat procedure + cheap preflight (no-op fast) + STOP conditions (real signals only) + denied verbs (human valves).

## Queue types — the second half of the catalog

Queue contract (invariant): item + durable store; states pending→pulled→done|dead; eligibility gate (valve); atomic pull; dead-letter path; WIP bound.

Materialization varies by input type; drain semantics identical:

| Input type | Materialization | Item | Atomic pull |
|---|---|---|---|
| Tasks | tasks.json waves (selector + ac gate + wip_limit) | task | lock + status write (t-2813) |
| Files | `inbox/` directory | file | `mv` to processing/ (atomic same-fs) |
| URLs | append-only `queue/urls.jsonl` | `{url, source, status}` line | cursor/status rewrite |
| Content | `brana feed` / `inbox` CLI | entry | CLI verb |
| Branches | git refs (`ready/*`) | branch | ref move/delete |
| External | GitHub issues, Meta templates | API object | label/state via API |

Already-live queues discovered by this lens: inbox/ dir, unmerged branches (merge valve), session-state `next[]`, knowledge-staging.md (cap 30 = WIP bound).

Example pipeline (URLs): `/brana:log` enqueues → feed-digester pump drains N/beat → fills knowledge-staging → human curation valve. Backpressure free: staging full → digester no-ops.

## Candidate loops (seed spread, 2026-08-13)

- **Gauges (L0)**: session-status (proven), merge-radar (proven t-2823), backlog-health, doc-drift, cost-gauge, loop-watchdog (meta — must live outside the loops it watches)
- **Pumps**: wave-drain (building, t-2813), inbox-processor, pr-shepherd, worktree-reaper, stale-closer (dead-letter pump — 160-day-stale root cause), knowledge-distiller
- **Valve-feeders**: ac-proposer, triage-preparer, close-sweeper, needs-you-digest
- **Beyond-repo**: pipeline-follower, metrics-snapshot, feed-digester, template-auditor (ADR-002 already lists ~15 recurring tasks: weekly staleness/link/dependency/frontmatter checks; monthly knowledge review, growth, financial close)
- **Self-maintaining**: memory-hygiene, phantom-ref-check, eval-rerunner

Dimension axes for generating more: primitive (gauge/pump/valve-feeder) × pacing (time/work/event) × boundedness × scope (repo/portfolio/business/personal) × autonomy (L0–L3) × **frequency band** (sub-second … session … season — see [wave-pipeline.md](wave-pipeline.md) §The spectrum: bands already cycling uninstrumented are loop candidates). Sparse grid corners generate ideas mechanically.

## Philosophy — defer to wave-pipeline.md

The seven operating laws, the studio/cockpit two-rooms split (and its "needs human is not one queue" consequence), the four primitives, the four rings, and the continuous-spectrum frequency lens that generalizes the rings (§The spectrum — rings as sample points, the layer test, the try→feedback→improve fundamental) are canonical in [wave-pipeline.md](wave-pipeline.md) — not duplicated here. This doc adds exactly one library-specific principle on top: **records are always emitted; verbosity is a render toggle** — records feed the TUI (t-2825): bounded → progress bar, unbounded → heartbeat.

## Pull interface (explored 2026-08-13)

Five verbs every queue answers: `peek / pull / ack / dead-letter / depth`. Per-store mechanics:

| Verb | Waves | inbox/ dir | URLs jsonl | git refs | External API |
|---|---|---|---|---|---|
| pull atomicity | lock+fresh-read+write (t-2813) | `mv` rename | flock+rewrite | `update-ref` | conditional update (race-prone) |
| ack | graded (build CLOSE) | mv processed/ | status done | merge+delete | close |
| dead-letter | park+reason | `.dead/`+sidecar | status dead | `rejected/*` | wontfix label |

Hard edges:
1. **Adapter's only real job is atomic pull** — every store has a native atomic primitive; hybrid keeps them.
2. **Two ack grades**: mechanical (self-ack) vs judged (gated by CLOSE/tests, evidence field required). Queue spec declares which.
3. **Leases (NEW — nothing has this today):** pull takes a lease (claimant + expiry in the beat record); crashed pump between pull and ack strands the item. Watchdog's second job: requeue stale leases. Without this every crashed loop leaks work invisibly. **Confirmed by the t-2813 builder session:** `pull_wave_task` writes `in_progress` with no claimant/expiry — the gap is real in shipped code. Lease design is owned by **t-2828** (plan-time wave graphs + epic runner), not duplicated here.
3b. **Concurrency evidence (t-2813 challenger stress test):** 20 concurrent OS processes against `wip_limit=5` → exactly 5 pulls, 0 duplicates — one `lock_tasks` flock sidecar around fresh-read→decide→write carries the whole guarantee. Load-bearing bonus: manual `backlog set/start` takes the SAME sidecar, so **human actions serialize against pumps for free** — a property a generic mirror store would have destroyed (final nail for the hybrid decision).
4. **Valve lives queue-side in pull** — eligibility enforced by the adapter, structurally unbypassable by pumps; approve verbs human-only (ADR-079).

## Decisions (brainstorm, 2026-08-13)

- **Hybrid queue architecture (user, after challenge):** native stores stay authoritative where they exist (waves in tasks.json, inbox/ dir, git refs) — no generic mirror store (avoids second-source-of-truth sync drift). Shared abstraction lives at the **pull interface**: every queue answers `peek / pull / ack / dead-letter / depth` however it's stored. Generic jsonl store only for input types with no natural home (URLs first). TUI renders anything with `depth`; watchdog reads anything emitting beat records.
- **URL queue is the second materialization** (after waves): fillers already exist (`brana feed poll`, `brana inbox poll`); the missing piece is the drainer. Diagnosed disease: thebrana queues have fillers but no pumps ("schema shipped, zero consumers" — same as t-2811's finding).

## Risks (pre-mortem, 2026-08-13)

Top two failure modes, both with in-repo precedent, one shared mitigation (user decision):

- **A — Shelf-ware:** entries written, never armed (the t-1994 pattern: 2 months of runway, no loop ever ran; "schema shipped, zero consumers").
- **B — Catalog of one:** only the waves adapter ever exists; every other entry references phantom queue verbs.
- **Mitigation — proof-of-life acceptance bar:** an entry is not `done` until its loop has run **N real beats with emitted records** (N by autonomy level; L0 gauges cheap to prove, pumps need more). Completion graded, not asserted. Side effect: forces adapters to exist before entries that need them can ship, and feeds the TUI (t-2825) real record data from day one.

## Shape (approved 2026-08-14)

- **Success metric:** 3 catalog loops each ≥10 real beats within a month of shipping, records visible in one place.
- **Next steps:** (1) this doc committed — done; (2) ADR folds into t-2828's design (not a separate step); (3) t-2826 builds: `system/loops/` structure + records-schema lint + first two entries to proof-of-life (session-status gauge — nearly free; drain-loop pump — already beating).
- **Second-order effects:** proof-of-life makes writing an entry deliberately expensive → fewer, better loops (anti-sprawl brake); every proven entry emits records → t-2825's TUI gets real test data before it's built. Watch-out: the bar could chill L0 experimentation — N scales with autonomy (a gauge proves in an afternoon).
- **Disciplines (M+):** DDD → ADR via t-2828 (blocks t-2826 impl). TDD → schema-lint + adapter tests before impl. SDD → feature spec `docs/architecture/features/loops-library.md` distilled from this doc at build start. Docs → user guide "write + arm a loop" after impl.

## Open questions

- system/loops/ dir vs skills-with-loop-frontmatter (Cherny: `/loop 5m /skill` — skill = beat body, /loop = cadence)?
- ~~Scope reconciliation loop-first ↔ backlog-drain~~ **Resolved 2026-08-14:** wave-pipeline.md unified the philosophy; t-2828 holds convergence design; division of labor in this doc's header.
