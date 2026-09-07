---
title: Knowledge Pipeline — Compute Routing
status: active
created: 2026-05-24
depends_on: ADR-042, ADR-040, ADR-041, ADR-093
see_also: knowledge-architecture-v2.md, project-descriptor-vectors.md
---

# Knowledge Pipeline — Compute Routing

> ADR-042's decisions operationalized. Scoped strictly to: canonical URL entry point,
> tier-to-model routing, and Telegram wiring. Pipeline architecture lives in
> `knowledge-architecture-v2.md`.

## Canonical Entry Point

`brana knowledge ingest` is the only code path that writes URLs to `pipeline-state.json`.
No other surface queues URLs directly.

Accepts:
- Positional URLs: `brana knowledge ingest https://... https://...`
- File input (WA exports, plain lists, any text): `brana knowledge ingest inbox/dump.txt`
- Stdin: `cat urls.txt | brana knowledge ingest`
- Source-tagged (Phase 2): `brana knowledge ingest --source telegram <url>`

URL extraction: regex `https?://[^\s<>]+` applied to any input text. Platform tag
(`linkedin | github | substack | arxiv | other`) assigned at ingest. Dedup against
existing pipeline state runs before queueing — already-seen URLs skipped, count reported.

**Status:** shipped (t-1665 completed)

The existing `event-log.md` path (via `/brana:log`) remains supported. `parse_event_log()`
feeds those URLs into the same pipeline state on the next `ingest` or `run` invocation.

---

## Tier-to-Model Routing

| Tier | Operation | Model | Status |
|------|-----------|-------|--------|
| Tier 1 | Relevance scoring (per-URL) | Gemini Flash (`call_gemini_json()`) | shipped (t-1667) |
| Tier 2 | Topic clustering (across URLs) | Gemini Flash (`call_gemini_json()`) | shipped (t-1667) |
| Tier 3 | Dimension draft synthesis | Claude Sonnet (`call_claude_json()`) | shipped |

Gemini output from Tier 1/2 is input to Claude's judgment — Claude decides which clusters
to promote, Gemini does not. ADR-040 `/tmp/` invariant applies to all Tier 1/2 calls.

Cost impact at 50-URL batch:
- Before (Claude Sonnet Tier 1): ~$0.50–1.50
- After (Gemini Flash Tier 1): ~$0.01–0.05

### Ruflo Semantic Dedup (Tier 1 pre-check)

Before Tier 1 scoring, check if the URL's topic already exists in `brana-knowledge`
(threshold: 0.85, namespace: `knowledge`). Skip if already represented.

**Status:** pending (t-1668)

---

## Pipeline Flow

```
SOURCES
  ├── brana knowledge ingest <file|urls|stdin>     ← Phase 1 entry (shipped)
  ├── brana knowledge ingest --source telegram     ← Phase 2 entry (stable API, bot unbuilt)
  └── event-log.md (existing — feeds pipeline state on next ingest/run)
          ↓
  pipeline-state.json (URL queue, platform-tagged, deduplicated)
          ↓
  brana knowledge run                              ← shipped (t-1669)
    ├── ruflo semantic dedup (0.85, namespace: knowledge)   ← pending (t-1668)
    ├── Tier 1: Gemini Flash — relevance scoring
    ├── Tier 2: Gemini Flash — topic clustering
    ├── GATE → brana knowledge process --report + --draft   ← human judgment
    ├── Tier 3: Claude Sonnet — dimension draft synthesis
    └── GATE → brana knowledge promote                      ← human judgment

  brana knowledge next  ← zero LLM calls, state→directive mapping (shipped, t-1666)
```

---

## Telegram Integration (Phase 2)

The Telegram bot calls `brana knowledge ingest --source telegram <url>` per message.
`--source` is metadata only — tags the URL for provenance, does not change pipeline
behavior. The pipeline is source-agnostic at Tier 1+.

Phase 2 is a bot integration task, not a pipeline task. The pipeline API is stable and
will not change when the bot is wired.

**Status:** untracked (Phase 2, future)

---

## Concurrency & Locking (t-2247)

**Problem.** `knowledge-pipeline-state.json` is load→modify→save. `save_state()` is
atomic (tmp+rename) but nothing serializes concurrent invocations: two simultaneous
`process --tier1` runs read the same unprocessed set, double-score it, and the
last writer's save silently discards the other's results. The lock path
`~/.swarm/knowledge-pipeline.lock` has been reserved in `is_allowed_write_path()`
since the allow-list landed, but no code acquires it.

**Decision (2026-07-02, rev. after challenger review).** Blocking exclusive
advisory lock on the reserved `~/.swarm/knowledge-pipeline.lock`, mirroring
`util::lock_sidecar()` (std `File::lock()`, RAII — released on drop or process
death; no stale-lock handling needed). Dedicated `lock_pipeline()` in
`knowledge_pipeline.rs` because the reserved path does not follow the
`.json.lock` sidecar naming.

- **Acquired exactly once per CLI entry point — never inside composed calls.**
  `cmd_run` calls `cmd_process` in-process (knowledge.rs:1156/1164/1186), and
  `File::lock()` is not reentrant — lock-at-every-handler self-deadlocks on
  `run`'s first auto-advance. Structure: `cmd_process` becomes a locking
  wrapper around an unlocked `process_core(&mut state, …)`; `cmd_run` and
  `cmd_ingest` lock once at entry and call the core. `process_core` has no
  lock-acquisition path, making re-acquisition unrepresentable.
- **Long lock covers only the mutating pipeline ops** (tier1/tier2/draft,
  ingest, run) — whole invocation, because batch selection reads state and a
  write-only lock would double-score. **Display paths don't lock**: `--report`
  reads a separate report file; `--status` display reads state (consistent
  snapshot via atomic rename). The two short writes (`--status` cap-ack,
  `--reset-url`) take the lock only around their own load→set→save, so
  interactive status never blocks behind a ~20-min Gemini batch (nightly
  `knowledge-pipeline-tier1` cron makes that contention routine, not rare).
- **Blocking, not fail-fast.** N concurrent invocations serialize and all make
  progress — this is what makes fan-out (multiple agents/sessions driving the
  pipeline) safe. `try_lock` first; on `WouldBlock` print
  `waiting for knowledge-pipeline lock (another run active)…` then block; any
  other error is a real failure, not contention.
- **Tier-1 candidate sourcing fix (folded in, same file).**
  `extract_unprocessed_urls()` only parses event-logs and excludes URLs already
  in state — so `ingest`-queued entries (status `Unprocessed`) are permanently
  invisible to Tier 1. Fix: union of event-log parse and `state.urls` entries
  with `UrlStatus::Unprocessed`, deduplicated. Without this, `ingest` is a
  write-only queue.
- **Non-actions:** no lock timeout (agy batches legitimately run minutes); no
  PID-in-lockfile diagnostics (flock dies with the process); no re-scope of
  `lock_sidecar` (different naming contract); no failed-scoring attempt cap
  (URLs that repeatedly time out at agy keep re-entering batches — known,
  separate concern); no new ADR (mechanism precedent: tasks.json sidecar lock,
  ADR-051; this section is the decision record).

**Testing.** Hermetic — never touch the real `~/.swarm` (a live pipeline run
may hold the lock).
1. Primitive contention: N threads acquire `lock_pipeline()` against a tempdir
   lock, each read→modify→save on a tempdir state file; final state contains
   all N updates (mirrors `lock_tasks_serializes_concurrent_appends`).
2. Composition guard: calling `process_core` while the caller already holds
   the lock completes within a bounded time (no nested acquisition — the
   deadlock the challenger flagged).
3. Sourcing: seeded state with `Unprocessed` entries and no event-log →
   Tier-1 candidate selection returns them; event-log-only sourcing still
   works (regression).

**Status:** implemented (t-2247)

---

## Post-Sync Enrichment (t-3310–t-3313)

A fourth compute stage, added by the link-signal enrichment pipeline
([ADR-093](../decisions/ADR-093-link-signal-enrichment-queue-scoring-layer2.md),
design record: [ideas/drained/link-signal-enrichment-pipeline.md](../../ideas/drained/link-signal-enrichment-pipeline.md)).
Unlike the tiers above it makes **zero LLM calls** — it is vector math over
rows the pipeline has already stored — so it is not in the tier table and has
no per-URL cost.

### Four enrichment columns on `knowledge.db`

`KnowledgeStore` (`brana-core/src/vector.rs`) carries four nullable columns
beyond sync's own `content` / `tags` / `source` / `created_at` / `vec`:

| Column | Type | Written by | Contents |
|--------|------|-----------|----------|
| `relevant_projects` | TEXT | scoring pass (t-3311) | JSON `[{"project": "<slug>", "score": <f32>}]`, best score first, `[]` when nothing cleared |
| `for_thebrana` | REAL | scoring pass (t-3311) | thebrana's own score, present only when it clears its threshold |
| `entities` | TEXT | `vector-sync` lift (t-3312) | JSON `["<name>", …]` — up to 5 tools, products or people from the extraction call |
| `action_type` | TEXT | `vector-sync` lift (t-3312) | `tool-to-evaluate \| technique-to-adopt \| read-later \| competitor-intel \| none` |

Real columns, never JSON stuffed into `content` — recall prints `content`
verbatim and FTS5 indexes it (ADR-093 §Non-Actions). The migration is
ALTER-if-missing on every `KnowledgeStore::open` (`ENRICHMENT_COLUMNS`), so an
older store upgrades in place. `NULL` means "that pass has not run for this
row"; `relevant_projects` is written on every scored row including `[]`, which
is what makes the distinction readable.

`entities` / `action_type` reach the store indirectly: the ingest pump has no
`knowledge.db` row to write to yet, so `extract_insight` emits them as
`action:<value>` / `entity:<name>` tags and `vector-sync` lifts them into the
columns (`vector.rs::extraction_from_tags`). Not backfilled — historical rows
never persisted the fetched page text, and YouTube/LongForm rows bypass
`extract_insight` entirely (ADR-087). See
[knowledge-pipeline.md](../knowledge-pipeline.md) for the extraction side.

### The scoring pass rides inside `vector-sync`

Scoring runs **post-sync, over committed rows** — never at ingest, which is
structurally impossible: `ruflo_memory_store` shells out and returns
`Result<()>`, so the ingest path never sees an embedding (ADR-093 D2). The pass
is therefore a step inside the existing `knowledge-vector-sync` scheduler job
(every 4h, 20min offset from `link-research-extraction`), not a second job:

```
brana knowledge vector-sync
  ├── migrate_from_memory_entries()   ← ruflo memory.db → knowledge.db (content, tags, vec)
  │     └── extraction_from_tags()    ← lifts entities / action_type (t-3312)
  └── run_relevance_pass()            ← after the upsert, on committed rows (t-3311)
        ├── ProjectVectorStore::all() ← the descriptor table (t-3307)
        ├── score_relevance()         ← centroid-subtracted cosine, pure (t-3308/t-3309)
        ├── set_relevance()           ← relevant_projects + for_thebrana
        └── ProjectTagWriter          ← coarse `project:<slug>` on the ruflo side, capped
```

- **Full recompute every run.** The project set is rebuilt from the descriptor
  table each time and every eligible row re-scored — a few thousand 384-dim
  vectors, milliseconds — so a descriptor edit, a rename or an archived project
  needs no versioning, no partial re-score and no scrub step.
- **Lock-free.** The whole handler sits outside every `lock_pipeline()` call
  site and touches `knowledge.db` only, so it never contends with the 4h drain
  cron's whole-invocation lock (pinned by `test_lock_discipline_source_tripwires`).
- **Row selection is by marker, not by guessing.** `RowFilter::LinkAndFeed`
  keeps rows carrying a platform tag (`linkedin`, `github`, `youtube`,
  `substack`, `arxiv`, `twitter`) or an explicit `source:link-capture` /
  `source:intelligence-feed` marker. thebrana's own indexed doc chunks are
  never scored. Tags decide it rather than `source`, because sync stamps every
  migrated row's `source` as `memory_entries`.
- **Clients are scored by centroid-subtracted cosine**, so the stack
  boilerplate sibling repos share cancels; **thebrana is scored apart** by
  plain cosine against its own vector, because inside the client centroid set
  its residual dominated every row. Thresholds, calibrated 2026-09-07 against
  2,705 live rows: `PROJECT_RELEVANCE_THRESHOLD` 0.25,
  `THEBRANA_RELEVANCE_THRESHOLD` 0.30 (top ~3% each).
- **Empty project table ⇒ pass skipped**, not every score wiped: an empty table
  means `project-vectors` has not run, not that every project was archived.
- **Ruflo side gets tags only**, no schema change: rows over threshold gain a
  coarse `project:<slug>` in the existing tags CSV, capped per run
  (`--tag-cap`, default 25) because ruflo has no tag-only update. Additive —
  a slug that leaves the portfolio drops out of `relevant_projects` but keeps
  its old tag.

### The `source:link-capture` marker

Every `process-url` write — YouTube included — carries the tag
`source:link-capture` (t-3312), so the link population is selectable by an
explicit marker instead of by inferring it from platform tags. It is matched
with or without the `source:` prefix (`LINK_SOURCE_MARKERS`), alongside
`intelligence-feed`, which `feed-ruflo-index.sh` already wrote.

### Descriptor table and how to edit it

Scoring compares each row against `project_vectors(slug PK, descriptor,
descriptor_hash, source, updated_at, vec)` — one **curated** line per portfolio
project, in the same `knowledge.db`. Curated because cosine over each repo's
raw `CLAUDE.md` cross-tags siblings on shared stack vocabulary.

To change what a project matches:

1. Edit `clients[].projects[].descriptor` on the portfolio record — domain, customer,
   problem, **no stack words**. The repo copy is
   `system/state/tasks-portfolio.json`; it reaches
   `~/.claude/tasks-portfolio.json` via `sync-state.sh pull` (do not edit both
   copies in one session — one direction overwrites the other).
2. Run `brana knowledge project-vectors`. Nothing watches the file; a project
   is re-embedded only when its descriptor text changes (SHA-256 of the exact
   embedded text), and `--force` covers a changed embedding model, which the
   hash cannot see. `--list` prints the stored table.
3. The next `vector-sync` absorbs it — full recompute, no scrub step.

Blanking a descriptor is how a project is retired: no descriptor ⇒ no vector,
and `project-vectors` prunes any slug absent from the current descriptor set
(`prune_except`), so the project leaves the table rather than lingering with a
stale vector. thebrana is
not a portfolio record — its vector is composed from `the-brana.md` plus the
accepted ADR titles. Full spec:
[project-descriptor-vectors.md](project-descriptor-vectors.md).

### Query surface

`brana knowledge relevant <project|thebrana> [--min-score <f>] [--dest <path>]
[--json]` lists the scored rows, best first — read-only, no embedding, no LLM
call, no synthesis. It exists so the pass's output is judgeable on evidence
rather than invisible; `--min-score` defaults to 0.0 because the pass already
applied its own threshold on the way in. Layer 2 (a synthesis pass and a
scheduled proposal loop) is deliberately **not** here — deferred by ADR-093 D3,
which fixes only its queue shape. Flags:
[reference/brana-cli.md](../../reference/brana-cli.md#brana-knowledge-relevant).

**Status:** implemented (t-3307–t-3313)
