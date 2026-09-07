---
depends_on:
  - docs/architecture/decisions/ADR-079-backlog-drain-loop-handoff.md
  - docs/architecture/decisions/ADR-080-plan-time-wave-graphs-epic-runner.md
  - docs/architecture/decisions/ADR-087-knowledge-pipeline-platform-adapters.md
  - docs/architecture/decisions/ADR-092-graduated-loop-autonomy-ladder.md
informs:
  - docs/architecture/features/inbox-to-dimensions-pipeline.md
  - docs/architecture/the-brana.md
status: accepted
---

# ADR-093: Link-Signal Enrichment — Backlog Fill Is a Queue, Scoring Runs Post-Sync, Layer 2's Queue Shape Is Fixed Now

**Date:** 2026-09-06
**Status:** Accepted
**Tasks:** t-3306 (this ADR)
**Source:** 2026-09-06 brainstorm, recorded in `docs/ideas/drained/link-signal-enrichment-pipeline.md` (§Scope, §Layer 1, §Risks, §Challenge record). Build tasks: t-3307..t-3314 (waves wave-27..wave-29). Framework refs: [the-brana.md](../the-brana.md) §Cycle → Mechanics · [ADR-092](ADR-092-graduated-loop-autonomy-ladder.md) · [ADR-079](ADR-079-backlog-drain-loop-handoff.md)/[ADR-080](ADR-080-plan-time-wave-graphs-epic-runner.md).

## Context

The link-signal enrichment pipeline takes links captured through the Telegram bot — fetched and summarised by `brana knowledge process-url` / `drain-links` (`brana-core/src/knowledge_pipeline.rs::extract_insight`, one LLM call per link) — and turns the stored rows into something the working projects and thebrana can query. **Layer 1** (project-relevance scoring over the stored vectors, two richer extraction fields for new links, a read-only `brana knowledge relevant` listing) is in scope. **Layer 2** (a scheduled proposal pump that files candidates into the backlog queue, and its closer) is **deferred and stays deferred** — this ADR fixes its shape only.

Three questions surfaced in the 2026-09-06 brainstorm that are not implementation details — each one, left unwritten, is the kind of thing a later reader re-opens from scratch:

1. **Is an automated writer filling the backlog "arming a gate"?** brana's valve law is unambiguous — a gate is "never automated, never armed by the party it constrains" (the-brana.md §Cycle → Mechanics; §Gate "Gate armed by an actor external to the loop"). If writing pending tagged candidates into `tasks.json` counted as arming, the deferred Layer 2 proposal pump would be illegal by construction and the whole pipeline would need a human in front of every capture.
2. **Where does project-relevance scoring live?** The intuitive placement is inside the Rust ingest path — score the item as you write it. That turns out to be not just undesirable but *unimplementable* on the current store, and the reason is worth recording so nobody spends a second session rediscovering it.
3. **Layer 2 is deferred — so is its design also deferred?** Operating law 2 says every loop needs a dead-letter path with its own closer pump, because queueless rejects rot. The already-logged incident behind that law is **t-2587 — LinkedIn-miss starvation, the 160-day-stale root cause** — which is *this exact domain*. Deferring Layer 2's build while leaving its queue shape open is how you ship t-2587 a second time.

## Decisions

### 1. Filling the backlog with pending tagged candidates is a pump filling a QUEUE, not arming a valve

**Decision: the Layer 2 proposal pump, when built, may write link-signal candidates into `tasks.json` unattended, at `status: pending` with an identifying tag (`link-signal`, `needs-triage`), and may append rows to `portfolio.md`'s Cross-Client Knowledge table. This is a pump moving work one stage into a queue. It is not a gate, and it does not arm one. Layer 1 itself writes no tasks.**

The mechanics row settles it. In `backlog ──▶ ac-propose ──▶ ac approve ──▶ wave drain ──▶ …`, the backlog is a **QUEUE** and the valve is `ac approve` — two stages downstream. Depth on a queue is not permission; it is only depth.

The eligibility filter is what makes this safe rather than merely nominal. ADR-079 §2 (as amended): a task is pullable only when

```
status:pending ∧ ac_state:approved ∧ ¬tag:parked ∧ ∀ b ∈ blocked_by · status(b) = completed
```

A freshly written candidate carries `ac_state: none`. It therefore fails the filter at the second term, and `wave_pull_decision` (`brana-core/src/tasks/wave.rs`) will not select it — no matter how many of them accumulate, no matter which wave's selector matches them. Nothing moves until a human runs `backlog ac-approve` / `wave approve`, which ADR-079 §1 makes human-only with no bypass through the generic `set` verb.

**Boundary on the pump (its denied-verbs list, ADR-092 §L1):** the enrichment pump may write `ac_state: none` and it may write `ac_state: proposed` (the `ac-propose` stage is itself a pump, not a valve — `proposed` is still not `approved`). It may **never** write `ac_state: approved`, never set a wave's `status`, never clear a `parked` tag, and never touch a task it did not create. Those are the actions that would turn the pump into a self-arming gate; everything short of them is queue-filling.

**Consequence — the real risk is depth, not authority.** Because this is a queue, the failure mode is not unauthorized automation but unbounded accumulation: candidates piling up faster than the valve is worked. Queue depth is a **gauge** — it is surfaced, it never acts. The tag makes candidates filterable and greppable in bulk; the cap and dead-letter in Decision 3 bound the depth.

### 2. Project-relevance scoring runs post-sync over the brana-owned `knowledge.db`, never at ingest

**Decision: relevance scoring is a second, separate pump that runs after `brana knowledge vector-sync` has committed its rows, reading each row's stored `vec` from `~/.claude/memory/knowledge.db` and scoring it against a small table of project-descriptor vectors. It never rides inside the ingest write.**

The Rust ingest path *cannot* do this, and the reason is structural rather than a missing convenience. The ingest store call (`ruflo.rs::ruflo_memory_store`) shells out to ruflo and returns `Result<()>` — no vector comes back to the caller — and the one similarity precedent in the pipeline, `cluster_long_form_entries` (`knowledge_pipeline.rs:758-804`), re-embeds via a `RufloEmbedder::embed()` subprocess per call rather than reading a stored vector. The vectors *are* readable, but downstream: `vector-sync` copies each row's stored embedding out of `memory_entries` into `knowledge.db`'s `vec` column (`vector.rs:296-319`, verified 2026-09-06) without re-embedding, and its handler (`commands/knowledge.rs:4269`) sits outside every `lock_pipeline()` call site. So the only place a scorer can hold both sides of the comparison — the item's vector and the project vectors — cheaply and lock-free is after sync, over `knowledge.db`.

So scoring runs as its own pass:

- **Input:** the committed `knowledge.db` at `knowledge_db_path()` (`~/.claude/memory/knowledge.db` — brana-owned, deliberately outside `~/.swarm/` and its rotation machinery, t-2615/t-2619).
- **Read path:** a new `KnowledgeStore` read of `(key, tags, source, vec)` restricted to link-capture and intelligence-feed rows (never thebrana's own indexed doc chunks), added by t-3310. Scoring is `score_relevance` (t-3308/t-3309): cosine after subtracting the centroid of all project vectors, so shared stack boilerplate cancels; nothing below threshold is emitted, and a missing or unreadable store yields no scores rather than wrong ones.
- **Write path:** two new columns on the same store, `relevant_projects` (JSON `[{project, score}]`) and `for_thebrana` (score), plus coarse `project:<slug>` tags on the ruflo side for rows over threshold (t-3311). Never JSON inside `content` — recall prints it verbatim and FTS5 would index it.
- **Full recompute every run.** The pass rebuilds its project set from the current portfolio and re-scores every eligible row (a few thousand 384-dim vectors, milliseconds), so descriptor edits, renames and archived projects need no versioning and no scrub step.
- **Timing:** after sync, on committed rows. Not in the same transaction, not in the same pump.

**This holds on mechanics grounds, not only API grounds.** Ingest is a pump (capture → knowledge row). Scoring is a pump (knowledge row → ranked candidate). Law 1: the two never call each other — the DB is the queue between them. Law 4: the scoring pass is idempotent, because it is a full recompute — the stored score is a cache of a derivation from the current corpus and descriptor table, never authoritative state. The vector read added by t-3310 does not reopen this decision: the placement argument (both sides of the comparison live post-sync) survives the API change.

**Calibration amendment (2026-09-07, first live pass, t-3311 review).** Measured on
2,705 link + feed rows against 12 curated client descriptors: centroid-subtracted
best-score-per-row p50 0.12 · p99 0.29 · max 0.39, so the provisional 0.5 threshold
admitted nothing and `PROJECT_RELEVANCE_THRESHOLD` is now 0.25 (top ~3%; the
known-relevant probes clear it). Two structural corrections: (a) **thebrana is scored
apart**, by plain cosine against its own vector with its own threshold
(`THEBRANA_RELEVANCE_THRESHOLD` 0.30) — inside the client centroid set its residual
dominated every row (p50 0.48) because its descriptor and the corpus are both about
agents; (b) **the project-vector sync prunes slugs absent from the current descriptor
set**, so a project that leaves the portfolio leaves the table — without that the
"full recompute drops archived projects" claim above was false. Archived or retired
projects are excluded by blanking their descriptor line, which the parser already
treats as "no vector".

**Scores are a gauge.** They rank candidates so the human valve is cheap to work. They never approve, never select, never flip `ac_state` — that would collapse Decision 2 into a violation of Decision 1.

### 3. Layer 2 stays deferred, but its queue shape is fixed now: `wip_limit` cap + untouched-N-days dead-letter

**Decision: Layer 2 is not built by this ADR. Its queue shape is nevertheless settled here, so that whoever builds it inherits a cap and a dead-letter path instead of designing them under delivery pressure.**

Operating law 2 — *every loop needs a dead-letter path with its own closer pump; queueless rejects rot* — was derived from **t-2587**, LinkedIn-miss starvation, the 160-day-stale root cause. That is the same content domain this pipeline operates in. The law is not being applied to Layer 2 by analogy; Layer 2 *is* the case the law was written for.

**Cap — `wip_limit` on the wave selector.** The Layer 2 queue is a wave over the candidate tag (`selector: tag:<link-signal-tag>`), and the bound is that wave's `wip_limit` — ADR-079 §3's existing WIP field, enforced by the existing `wave_pull_decision` / `min(wip_limit - live, N)` path (ADR-090). No new mechanism, no new field. Two constraints on it:

- WIP control lives on the **wave**, never on a task. `wip_limit` is a retired task field (ADR-065 D4, enforced by `RETIRED_FIELDS` in `brana-core/src/tasks/validation.rs`); the wave-level `wip_limit` is deliberate name reuse.
- `wip_limit: null` (unbounded) is **not permitted** for this wave. An unbounded auto-fed queue is the shape t-2587 died of; the cap is the point.

**Dead-letter — untouched-for-N-days → `link-signal-expired` + `cancelled`.** A closer pump sweeps candidates that have sat in the queue N days without being pulled and performs one terminal transition: add the tag `link-signal-expired`, set `status: cancelled`.

- `cancelled` is a valid terminal status (`validation.rs`), and a `cancelled` task **never resolves as a `blocked_by` dependency** (same resolver as classify / `wave pull`, t-3166). Expiring a stale candidate therefore cannot silently unblock anything downstream.
- The `link-signal-expired` tag is what makes this a dead-letter *queue* rather than a silent drop: the bucket is greppable, so a human can peek at what the pipeline gave up on and re-file anything that mattered. A drop you cannot inspect is exactly the "queueless reject" law 2 forbids.
- **N is a build-time parameter, not fixed by this ADR.** What is fixed: N exists, N is finite, and expiry is this specific terminal transition. A Layer 2 implementation that ships with no N, or with expiry as a delete, contradicts this ADR.

**The closer pump is L1 under [ADR-092](ADR-092-graduated-loop-autonomy-ladder.md)** — it mutates durable state, so it runs `supervised: true` until it accrues its own 5 clean runs. Its denied-verbs boundary, written here rather than discovered live: it may set `status: cancelled` and add `link-signal-expired`, on tasks matching the wave selector **and** the age predicate, and nothing else. It may not touch `ac_state`, may not delete a task, may not modify a task outside the selector, and may not widen its own age predicate.

## Seven-laws check

- **1 (loops talk via queues).** Ingest, scoring, and the Layer 2 closer are three pumps sharing two queues (`knowledge.db`, the tagged wave). None calls another.
- **2 (dead-letter + closer pump).** Decision 3, explicitly — the law's originating incident is in this domain.
- **3 (external watchdog).** Unchanged; the Layer 2 pumps record beats like any other and are watched from outside.
- **4 (idempotent beats).** Scoring is a full recompute (D2) — running it twice yields the same columns. The closer's transition is idempotent — a second sweep over an already-`cancelled` candidate is a no-op.
- **5 (cost ≈ context).** Scoring is a batch pass over committed rows, not a per-item LLM call at ingest.
- **6 (testable).** The Layer 2 wave rehearses via `wave pull --dry-run` (shadow drain) before arming, and the closer pump's age predicate is machine-checkable against a fixture `tasks.json`.
- **7 (lifecycle stance).** The N-day expiry *is* Layer 2's retirement stance, taken up front rather than bolted on.

## Consequences

- Layer 1 ships as a scheduler step inside the existing `knowledge-vector-sync` job plus a read-only listing; it touches no task state. When Layer 2 is built, its proposal pump can run unattended: the valve law is satisfied by the eligibility filter (`ac_state: none` is never pullable), not by throttling the pump.
- The "score at ingest" design is closed. Any future proposal to score inside `KnowledgeStore::upsert` must first answer the mechanics objection in D2, not just add a read-back method.
- Layer 2's builder inherits a spec for the two things that are hardest to add later: the cap and the dead-letter path. The remaining Layer 2 design surface (selector name, N, who runs the closer, how candidates enter the wave) is untouched and still open.
- `docs/architecture/the-brana.md` §Cycle needs no change — D1 is an application of its existing mechanics table, not an amendment to it.

## Non-Actions

- **Layer 2 is not built.** No wave is created, no closer pump is written, no selector name is minted. This ADR fixes shape only.
- **No fifth primitive.** Everything above is an arrangement of queue / pump / valve / gauge, per the closed vocabulary in the-brana.md §Cycle → Mechanics.
- **No new store.** Scores live as columns on the existing brana-owned `knowledge.db` (t-3310); the ruflo-side `memory.db` gets tags only, no schema change.
- **No ingest-time scoring, ever.** The vector read added to `KnowledgeStore` by t-3310 serves the post-sync pass; it is not a licence to move scoring into `upsert`.
- **No backfill of LLM-derived fields.** `entities` and `action_type` are extracted for new short-signal links only (t-3312); historical rows never persisted the fetched text, so backfilling would cost one LLM call per row. YouTube/LongForm rows bypass `extract_insight` (ADR-087) and are out of scope for those two fields.
- **No change to ADR-079's eligibility filter or the `ac approve` valve.** D1 relies on both exactly as they stand.
