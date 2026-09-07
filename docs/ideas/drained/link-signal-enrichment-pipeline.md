---
title: Link Signal Enrichment Pipeline
status: drained
created: 2026-09-06
drained: 2026-09-06
tasks: t-3306..t-3314 (epic knowledge-pipeline, t-2348)
---
# Link Signal Enrichment Pipeline

> Brainstormed 2026-09-06, following the three-week Telegram captures digest. **Drained 2026-09-06** into t-3306..t-3314 under epic `knowledge-pipeline` (t-2348). Layer 2 remains open and gets its own idea doc when Layer 1 has produced tagged data.

## Scope of this plan

**This plan covers Layer 1 only** (cheap, post-sync, zero new LLM calls) —
the embedding-based tagging plus richer extraction fields, and the one-time
backfill over existing entries. **Layer 2** (the on-demand `brana knowledge
relevant` command and the scheduled L0 digest/proposal loop) is real and
worth building, but is deferred to its own idea doc once Layer 1 has run long
enough to produce backfilled, tagged data worth querying and proposing from.
Building Layer 2 against untagged data would be building on nothing.

## Problem

The Telegram → knowledge pipeline (`knowledge_pipeline.rs::extract_insight`) stores exactly
two fields per link — `summary` and `topic` (a 1-3 word label). Everything past that —
"what does this mean for thebrana," "which working project should see this" — has to be
hand-derived after the fact by rereading every stored entry. That is what the 2026-09-06
captures digest did manually for 240 links. It does not scale to a weekly cadence and it
means good findings (a Taskfile suggestion, a legal-template repo relevant to lexia) only
surface when someone happens to do a deep pass.

t-1706 already identified half of this gap in 2026-07 ("Extend /brana:reconcile to scan
dim Could Adopt sections → push actionable ideas to backlog") and has sat pending since.
This idea generalizes that mechanism to links too, rather than shipping a second,
disconnected version of the same pump.

## Proposed solution

Two layers, kept deliberately separate by cost and by valve discipline (the-brana.md
§Cycle mechanics — backlog is a QUEUE, not a valve; filling it is a pump's job, never
auto-approving or auto-starting is the valve's).

### Layer 1 — cheap, post-sync scoring plus richer extraction (revised after challenge)

**Where the vectors actually are.** The Rust ingest path cannot see an embedding: the
store call (`ruflo.rs::ruflo_memory_store`) shells out and returns `Result<()>`, and the
real similarity precedent — `cluster_long_form_entries` (`knowledge_pipeline.rs:758-804`,
production-wired at `commands/knowledge.rs:1604`) — re-embeds via a `RufloEmbedder::embed()`
subprocess each call. The vectors *are* readable, but downstream: the brana-owned
`~/.claude/memory/knowledge.db` (`vector.rs::KnowledgeStore`, `vec` column) is filled by
`brana knowledge vector-sync`, which already runs 20 minutes after every drain. **Verified
2026-09-06:** the sync reads the stored `embedding` JSON out of `memory_entries` and converts
it to `f32` (`vector.rs:296-319`, `migrate_from_memory_entries`) — it never re-embeds — and
its handler (`commands/knowledge.rs:4269`, `cmd_vector_sync`) is outside every
`lock_pipeline()` call site, so it never contends with the 4h drain cron. So scoring is a
**post-sync pass over `knowledge.db`**, not an ingest-time hook, and it is lock-free.

1. **Project descriptors, not raw CLAUDE.md.** One curated line per project (domain,
   customer, the problem — no stack words) kept in `tasks-portfolio.json` or
   `portfolio.md`. Embed each once via the existing `RufloEmbedder` seam (a handful of
   subprocess spawns, only when a descriptor changes). Score **differentially**: subtract
   the centroid of all project vectors before cosine, so shared boilerplate cancels and
   only what distinguishes a project registers. thebrana's own vector comes from
   `the-brana.md` + accepted ADRs, embedded the same way.
2. **Scoring pass = full recompute, every time.** Read every `knowledge.db` row whose
   `source` is a link capture or an intelligence-feed item (never thebrana's own doc
   chunks), compute cosine against the current project set, write the result. ~300 link
   rows plus feed items × 384 dims is milliseconds of vector math, so there is no
   versioning, no partial re-score, no stale-vector problem: any change to a descriptor
   or to the portfolio (add, rename, archive) is handled by re-running the whole pass.
   Runs as a step inside the existing `knowledge-vector-sync` scheduler job.
3. **Real columns, not JSON in `content`.** Add `relevant_projects` (JSON `[{project,
   score}]`) and `for_thebrana` (score) to `KnowledgeStore` — a small, explicit schema
   migration on the brana-owned db, threaded through `vector-sync`. In the ruflo-side
   `memory.db`, the only addition is coarse `project:<slug>` entries in the existing CSV
   `--tags` for scores over threshold, which recall already displays and which pollute
   nothing. Store the score; never force a tag below threshold.
4. **Richer extraction for new short-signal links only.** Extend the one
   `extraction_prompt()` call (`knowledge_pipeline.rs:3023`, reused across the agy →
   `claude -p` tiers) to also return `entities: []` and `action_type` (`tool-to-evaluate |
   technique-to-adopt | read-later | competitor-intel | none`). Requires adding the fields
   to `ExtractedInsight` (`:3003`) and `parse_extraction_response` (`:3060`), and two more
   `KnowledgeStore` columns. **Not backfilled**: historical entries never persisted the
   fetched page text, so backfilling would mean ~300 new LLM calls; they get scoring only.
   **YouTube / LongForm entries bypass `extract_insight`** (`commands/knowledge.rs:624`,
   ADR-087) and are out of scope for these two fields.
5. **A query surface ships with Layer 1, or Layer 1 is invisible.** `brana knowledge
   relevant <project|thebrana> [--min-score 0.5]` — a read-only listing over the new
   columns, no synthesis, no LLM call. This is what lets the "worth building Layer 2"
   gate actually be judged on evidence.
6. **Tag every process-url write `source:link-capture`** going forward, so the link
   population is selectable by a marker rather than by guessing platform tags.

### Layer 2 — deferred, not part of this plan (see Scope above)

> The steps below are kept for context and to seed the follow-up idea doc. Not planned in this pass.

5. `brana knowledge relevant <project|topic>` — a real synthesis pass, one call per
   invocation, answering "what have we learned relevant to X" by combining Layer 1's
   tags with semantic search, not just returning a link dump.
6. A scheduled digest pass, shaped exactly like the shipped `pipeline-digest` L0
   Reporter loop (`system/loops/pipeline-digest.md` — read-only, `autonomy: L0`,
   proven precedent, 30-60m cadence pattern generalizes to weekly here): read entries
   stored since the last run, and for any whose `action_type` is `tool-to-evaluate` or
   `technique-to-adopt` with a high-confidence project or thebrana tag, propose (not
   file) a candidate.
7. Candidates land in the backlog QUEUE, not past a valve: `status: pending`,
   `tags: link-signal, needs-triage`, optionally under one shared epic so
   `role:needs-triage` + `tag:link-signal` becomes a real wave selector — the
   ac-propose/ac-approve/wave-drain machinery (ADR-079/080) already does exactly this
   for every other kind of task. High-relevance project findings append a row to
   `portfolio.md`'s existing Cross-Client Knowledge table (additive, same shape as the
   rows already there) rather than a new file.
8. Merge with t-1706 rather than running two parallel mechanisms: the same
   "scan stored knowledge → propose backlog candidates" pump serves both dimension docs
   and links.

## Research findings

- Every stored knowledge entry has an ONNX 384-dim embedding in `~/.swarm/memory.db`
  (5099/5099), mirrored as `vec` in the brana-owned `knowledge.db` by `vector-sync`.
  Only ~300 of those rows are link captures; ~1800 are intelligence-feed items and
  ~2800 are thebrana's own indexed docs. The Rust ingest path cannot read the vector
  back in-process (the store call returns nothing), so scoring must happen where the
  vectors live: post-sync, over `knowledge.db`.
- The zero-LLM-call similarity precedent is `cluster_long_form_entries`
  (`knowledge_pipeline.rs:758-804`); it re-embeds per call via a subprocess. The earlier
  "~line 6575" citation was a unit test with a bag-of-words fake.
- No `dataviz` consumer of `memory.db`/`knowledge.db` exists in this repo (systems lens
  checked; the brief had assumed one). Readers of the store: `vector-sync`, `recall` CLI
  and MCP, and the new `relevant` listing.
- `pipeline-digest.md` is a shipped, production L0 Reporter loop — the read-only shape
  this idea's Layer 2 batch pass should copy, not invent.
- t-1706 (2026-07) proposed the same "scan → push to backlog" pump for dimension docs
  and has never been built — evidence this class of idea stalls without a small first
  slice tied to something already running.
- backlog's own mechanics table (the-brana.md §Cycle) already settles the
  queue-vs-valve question this idea initially got wrong in discussion: creating a
  pending, tagged task is a pump filling a queue, not arming a valve.

## Risks

- **Mistagging erodes trust** (pre-mortem risk A). Project embeddings built from a
  thin `CLAUDE.md` paragraph may produce noisy matches. Mitigation: always show the
  score, never force a tag below threshold, and treat the scheduled digest's output as
  proposals a human skims in seconds, not authoritative labels.
- **Never gets built** (pre-mortem risk B, same fate as t-1706). Mitigation: land the
  smallest slice first — extend the existing extraction call and the existing
  drain-links storage path, don't stand up a new service; and explicitly close or merge
  t-1706 into this idea's backlog plan so there is one pump, not two abandoned ones.
- **Portfolio staleness**: adding/archiving a client or venture changes the project
  vector table. Mitigation: re-embedding is cheap (one call per project doc change,
  event-driven off the same doc-drift detection `/brana:reconcile` already runs), not a
  new maintenance burden.

- **Cross-tagging siblings on stack boilerplate.** Client repos share "Next.js,
  Supabase, Vercel" verbatim; cosine over that text tags the wrong project. Mitigation:
  curated one-line descriptors with no stack words, plus centroid-subtracted
  differential scoring (Layer 1 step 1).
- **Layer 2's queue has no cap or dead-letter.** Operating law 2 and the t-2587
  incident. Mitigation: the ADR note written in this plan fixes the queue design now —
  `wip_limit` on the `link-signal` wave selector, untouched-N-days → `link-signal-expired`
  + cancelled — even though the pump that fills it is deferred.
- **Long pass under the pipeline lock.** `lock_pipeline()` is whole-invocation and the
  4h drain cron holds it. Resolved: the scoring pass lives in the `vector-sync` job, which
  is verified lock-free and touches `knowledge.db` only; the one ruflo-side write
  (`project:<slug>` tags) runs with a `--cap` in slices, like `drain-links`.
- **Retired or renamed projects.** Handled by the full recompute: the pass builds its
  project set from the current portfolio each run, so a removed project drops out of every
  `relevant_projects` entry on the next run with no scrub step (AC on the pass task).
- **Descriptors still too thin.** Fallback kept from the challenge: enrich each project
  vector with its own backlog task subjects and tags before anything heavier; decide on
  evidence from `brana knowledge relevant`, not up front.

## Second-order effects

- Scoring as a full recompute over `knowledge.db` → covers the ~300 historical link
  captures and ~1800 intelligence-feed items on the first run, free → the feed, which
  today is ingested and never looked at per project, becomes project-queryable as a
  side effect. Smaller than the "5000 entries" claim in the first draft, but real, and
  it also means portfolio changes cost nothing to absorb.
- Filling the backlog queue under one shared tag/epic → `role:needs-triage` +
  `tag:link-signal` becomes a real, continuously-fed wave selector → this exercises the
  ac-propose/ac-approve/wave-drain machinery (ADR-079/080) on a genuinely new, steady
  source of pending work, which today mostly only proves itself against internally
  authored dev tasks — a live stress test of infrastructure that needs more real load.

## Engineering disciplines

- **DDD (Decision):** No new primitive — this composes existing ones (queue, pump,
  L0 loop, embedding similarity). A short ADR note may still be worth it to record the
  queue-vs-valve resolution reached in discussion, so a future reader doesn't re-litigate it.
- **TDD (Tests):** `resolve_extraction`-style pure-function tests for the new
  similarity-scoring function (given a link embedding + project vectors, assert
  threshold behavior) before wiring it into `extract_insight`.
- **SDD (Spec/Docs):** `docs/architecture/features/knowledge-pipeline-compute.md` and
  `docs/architecture/knowledge-pipeline.md` need the new fields documented; a new
  `system/loops/link-signal-digest.md` loop entry if Layer 2's batch pass ships as a
  loop.
- **Docs:** tech doc update (existing knowledge-pipeline feature doc), no new user
  guide needed (extends `brana knowledge` command family already documented).

## Next steps (this plan — Layer 1 only)

1. ADR note: record the queue-vs-valve resolution, the post-sync scoring placement,
   and the Layer 2 queue design (cap + dead-letter) so it is decided before anything
   fills it.
2. Curated one-line descriptors for every portfolio project; embed them and thebrana's
   framework corpus via the existing `RufloEmbedder` seam.
3. Pure, unit-tested scoring function: centroid-subtracted cosine over a set of project
   vectors, threshold behaviour, empty result when nothing clears.
4. `KnowledgeStore` migration: `relevant_projects`, `for_thebrana`, `entities`,
   `action_type` columns; `vector-sync` threads them.
5. Scoring pass wired into the `knowledge-vector-sync` scheduler job (full recompute,
   link + feed sources only), plus `project:<slug>` tags on the ruflo side.
6. Extend `extraction_prompt()` / `ExtractedInsight` / `parse_extraction_response` with
   `entities` + `action_type` for new short-signal links; tag writes `source:link-capture`.
7. `brana knowledge relevant <project|thebrana> [--min-score]` read-only listing.
8. Update the two knowledge-pipeline feature docs and the `brana knowledge` reference.

## Deferred next steps (Layer 2 — separate future idea doc)

5. Close or merge t-1706 into that follow-up plan; ship the shared "propose
   backlog candidate" pump once, serving both dimension docs and links.
6. Ship `brana knowledge relevant <project|topic>` as the on-demand query-time layer.
7. Ship the scheduled digest pass as an L0 Reporter loop, proposing only.

## Challenge record (2026-09-06, three-lens native quorum)

HIGH (two or more lenses): the "zero-cost backfill over ~5000 entries" claim was wrong
on population (~300 links) and on mechanism (no in-process vector; entities need LLM
calls); there was no storage slot for the new fields; stale project vectors had no
re-scoring plan. Single-lens, accepted: Layer 1 without a query surface is invisible
work; boilerplate cross-tagging; Layer 2 queue needs cap + dead-letter; wrong line
citation; YouTube bypasses extraction. All applied above — the design moved from
"score at ingest, backfill everything" to "score post-sync as a full recompute, extract
richer fields for new links only, ship a read-only query with Layer 1."
