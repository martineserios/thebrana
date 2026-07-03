---
title: Knowledge Pipeline — Compute Routing
status: active
created: 2026-05-24
depends_on: ADR-042, ADR-040, ADR-041
see_also: knowledge-architecture-v2.md
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
