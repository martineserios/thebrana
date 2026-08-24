# ADR-087: PlatformAdapter for the knowledge pipeline

**Status:** Proposed
**Date:** 2026-08-24
**Task:** t-3151

## Context

`brana knowledge process` (Tier1 relevance score → Tier2 cluster → Tier3
LLM-drafted dimension doc) is hardcoded to a single content shape. `build_tier1_prompt`
and `build_tier2_prompt` take only `author`, `title_signal`, `tags` — no platform
parameter exists anywhere in the tier functions — and the Tier1 prompt is literally
worded *"You are classifying a LinkedIn post..."* unconditionally.

Two problems follow from this:

1. **No path for long-form content.** YouTube transcripts fetched via
   `process-url`/`drain-links` land in ruflo memory (`knowledge:url:*` keys) and never
   touch `PipelineState` — there's no code path into dimension-doc synthesis at all.
   Even if there were, the three tier prompts have no slot for full content: they're
   built for short-signal triage at batch volume (`TIER1_BATCH = 50`,
   `TIER1_CONCURRENCY = 5`), not long-form synthesis.
2. **Live mislabeling bug.** `cmd_ingest` accepts and queues arbitrary URLs into
   `PipelineState` with no platform filter. `UrlEntry.platform` is populated
   (`classify_platform` distinguishes linkedin/github/substack/arxiv/youtube/other),
   but nothing in Tier1/2/3 reads it. A GitHub repo or arxiv paper entering the
   pipeline today is scored against a prompt that assumes it's a LinkedIn post.

`UrlEntry.fetched_content` already exists generically on the struct but is populated
by nothing. Its doc comment points at t-1144 — a separate, LinkedIn-only task gated on
the LinkedIn pipeline completing one full validated cycle first. This ADR's scope is
independent of t-1144 and does not reopen that gate.

## Decision

Introduce a `PlatformAdapter` dispatched by **content shape**, via a plain Rust enum
match — not a `dyn Trait` object. `brana-core` has 22 `pub enum`s and, separately,
one live `dyn Trait` adapter precedent (`search.rs`'s `SearchProvider`, with three
implementations composed via `Arc<dyn SearchProvider>`) — so trait objects aren't
foreign to this codebase. Enum dispatch is still preferred here specifically because
the adapter set is small (two variants) and closed for the foreseeable future,
unlike `SearchProvider`'s genuinely open-ended provider set; a closed 2-variant
match needs none of `dyn Trait`'s indirection or extensibility. This is a judgment
call about *this* adapter set, not a codebase-wide style rule (challenger review,
2026-08-24 — corrected from an earlier draft that mischaracterized the codebase as
having zero trait-object precedent).

**The pipeline skeleton is shared** — queue → Tier1 → Tier2 → Tier3 → draft/promote —
across every adapter. An adapter overrides only the *steps* it needs to diverge on;
the orchestration loop (`cmd_process`, batch handling, draft cap, state persistence)
never forks per content type. A future adapter may override a single tier, or none,
without duplicating the loop.

Two adapters cover the three concrete cases known today:

| | `ShortSignalAdapter` | `LongFormAdapter` |
|---|---|---|
| Platforms | linkedin, github, substack, arxiv | youtube, long-form articles |
| Tier1 | LLM scores relevance from author/title/tags — **prompt wording becomes platform-aware** (fixes the mislabeling bug: GitHub/Substack/arxiv get their own wording, not "LinkedIn post") | Auto-pass — content is already curated at ingestion (channel-backfill + manual filtering); re-scoring relevance from a title string is wasted LLM cost on content already decided to matter |
| Tier2 | LLM clusters from title/tags (unchanged) | Embedding similarity via ruflo's existing semantic search — no LLM round-trip |
| Tier3 | Drafts from metadata only (unchanged) | Drafts grounded in real excerpts from `fetched_content` |

Podcasts are explicitly excluded from `LongFormAdapter`'s scope — no fetch mechanism
exists for audio transcription, and this ADR does not build one.

The `ShortSignalAdapter` generalization (platform-aware prompt wording, fixing the
mislabeling bug) is included in this decision's scope rather than filed separately:
the adapter abstraction is being built regardless, and the fix is prompt-wording
only — no new adapter kind, no behavior change to LinkedIn's actual scoring/clustering
logic.

**Required: shared URL identity across both stores (challenger finding, 2026-08-24,
score 4).** `ingest_urls` keys `PipelineState.urls` by the raw literal URL string.
Ruflo's side (`process_one_url`/`url_storage_key`) canonicalizes first —
`canonicalize_url()` strips tracking params, unwraps `/safety/go`-style redirects,
drops fragments — before deriving the storage key. Whatever wiring mechanism
DECOMPOSE picks (a new `queue-for-dimensions` step, or `drain-links` writing into
both stores) **must key `PipelineState` entries by the same canonicalized identity
ruflo uses**, not the raw URL. Without this, a tracking-param variant of a URL merges
into one ruflo entry but splits into two `PipelineState` entries, silently
misattaching or duplicating `fetched_content` — defeating the entire point of
`LongFormAdapter`'s grounded Tier3. This is a decision requirement, not an open
risk: the wiring mechanism is not acceptable without it.

## Consequences

- YouTube transcripts (and future long-form articles) become synthesizable into
  dimension docs, addressing poor semantic-search ranking of raw transcript storage.
- GitHub/Substack/arxiv URLs stop being scored under a LinkedIn-shaped prompt.
- LinkedIn's existing Tier1/2/3 behavior is provably unchanged in substance (only
  prompt wording generalizes) — t-1144 remains valid and unaffected.
- Tier2 for long-form content stops producing an LLM `"reason"` string. Corrected
  from an earlier draft that overstated this as a "UI/report code" concern: `reason`
  from `parse_tier2_json` is never persisted on `UrlEntry` today (no `tier2_reason`
  field exists) — it's only printed once via `println!` in `run_tier2`'s loop. The
  actual touch point is that one printline needing an embedding-clustering-aware
  message, nothing more.
- **Open question for DECOMPOSE (challenger finding, 2026-08-24):** `run_tier1`'s
  semantic-dedup pre-filter (`check_semantic_dedup`, t-1668) currently runs before
  any LLM scoring, for every platform. This ADR does not decide whether
  `LongFormAdapter`'s Tier1 auto-pass still goes through that dedup check or skips
  straight to Tier2. Skipping it means duplicate long-form topics reach the
  expensive Tier3 drafting step instead of being cheaply filtered at Tier1 — the
  opposite of what auto-pass exists to save.
- **Open risk, deliberately not resolved by this ADR:** Tier1 auto-pass assumes
  ingestion-time curation always holds. It's true for this session's manual
  channel-backfill filtering; it isn't guaranteed for a future bulk-queued long-form
  source. DECOMPOSE must decide whether auto-pass stays unconditional or gets a
  lightweight per-adapter Tier1 heuristic.
- **Open risk, deliberately not resolved by this ADR:** embedding-based clustering
  quality for long-form content is asserted, not measured. Cheap to fall back to LLM
  clustering if it underperforms; a small spike may precede full commitment.
- **Named tension for later, not addressed now:** once embedding-based Tier2 exists
  and works well for long-form content, it creates pressure to ask why LinkedIn
  doesn't get the same treatment — a future scoping question, not this ADR's to
  answer.

## Non-Actions

- Does not build a podcast/audio-transcription fetch mechanism.
- Does not touch t-1144 (LinkedIn full-content fetch) — that gate is unaffected.
- Does not change `ShortSignalAdapter`'s scoring/clustering *logic* for LinkedIn,
  only its prompt wording for non-LinkedIn platforms already reaching the pipeline
  via `ingest`.
- Does not resolve the Tier1-auto-pass-curation risk or the embedding-clustering
  quality risk — both are named as open questions for DECOMPOSE.
