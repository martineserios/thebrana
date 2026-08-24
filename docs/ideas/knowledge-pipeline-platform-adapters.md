---
title: PlatformAdapter for the knowledge pipeline
status: draft
created: 2026-08-24
---

# PlatformAdapter for the knowledge pipeline

> Brainstormed 2026-08-24, following t-3097 (MemPoison exemption) and a Matt Pocock
> YouTube backfill session. Feeds t-3151.

## Problem

`brana knowledge process` (Tier1 relevance score → Tier2 cluster → Tier3 LLM-drafted
dimension doc) is hardcoded to a single LinkedIn-shaped prompt with **no platform
branching at all**. Two consequences:

1. YouTube transcripts (and any other long-form content) can't be synthesized into
   dimension docs — there's no code path from `process-url`/`drain-links`'s ruflo
   `knowledge:url:*` entries into `PipelineState`, and even if there were, the three
   tier prompts have no slot for full content — they work from `author`/`title_signal`/
   `tags` only (three short strings), consistent with a design built for LinkedIn-post
   triage at batch volume.
2. **Live bug, not hypothetical:** `brana knowledge ingest` accepts and queues *any*
   URL with no platform filter, but `build_tier1_prompt` is unconditionally worded
   *"You are classifying a LinkedIn post..."* A GitHub repo, Substack article, or
   arxiv paper entering the pipeline today gets judged as if it were a LinkedIn post.

## Proposed solution

A `PlatformAdapter`, dispatched by **content shape**, not by platform — a plain enum
match (the codebase already has 20 `pub enum`s in `brana-core` and zero trait-object
adapters; enum dispatch fits house style, no `dyn Trait` needed).

**Core principle:** there is **one pipeline skeleton** —
queue → Tier1 → Tier2 → Tier3 → draft/promote — shared by every adapter. An adapter
only overrides the *steps* it needs to behave differently on; the pipeline never forks
per input type, only individual steps do. A future adapter might override just one
tier, or add a step none of the others need, without duplicating the orchestration
loop.

Two adapters cover the three concrete cases known today (LinkedIn as-is; YouTube +
long-form articles are the *third* case — podcasts explicitly excluded, no fetch
mechanism exists for them):

| | `ShortSignalAdapter` | `LongFormAdapter` |
|---|---|---|
| Platforms | linkedin, github, substack, arxiv (generalized — see below) | youtube, long-form articles |
| Tier1 | LLM scores relevance from author/title/tags, **prompt wording now platform-aware** (fixes the mislabeling bug as a byproduct — GitHub/Substack/arxiv get their own wording, not "LinkedIn post") | Auto-pass — content is already curated at ingestion (channel-backfill + manual filtering), so re-scoring relevance from a title string is wasted LLM cost |
| Tier2 | LLM clusters from title/tags (unchanged) | Embedding similarity via ruflo's existing semantic search — no LLM round-trip, likely more accurate on real transcript/article text than an LLM guessing from a title |
| Tier3 | Drafts from metadata only (unchanged — LLM's general knowledge of the topic, not the actual post) | Drafts grounded in real excerpts from `fetched_content` — a genuine quality improvement over what LinkedIn gets today |

**Scoping decision (made during discussion, not deferred):** the ShortSignalAdapter
generalization (platform-aware prompt wording) is folded into this work rather than
filed separately, since the adapter abstraction is being built anyway and the fix is
prompt-wording only — no new adapter kind, no behavior change for LinkedIn itself.

## Research findings

- Tier1/2/3 currently take no `platform` parameter at all — `build_tier1_prompt` and
  `build_tier2_prompt` only see `author`, `title_signal`, `tags`.
- `UrlEntry.fetched_content` already exists generically on the struct but nothing
  populates it. Its doc comment points at **t-1144** (LinkedIn-only, gated on the
  LinkedIn pipeline's own first full validated cycle — confirmed unrelated to this
  work, not accidentally reopening that gate).
- `cmd_ingest` queues arbitrary URLs into `PipelineState` with no platform filter —
  the LinkedIn-prompt mislabeling of GitHub/Substack/arxiv URLs is live today.
- No existing adapter-pattern precedent anywhere in the codebase; 20 existing
  `pub enum`s in `brana-core` confirm enum dispatch is the established idiom over
  trait objects.
- Raw YouTube transcripts rank poorly in `brana knowledge search` against short,
  topically-tight feed content — live-tested 2026-08-23, a video's own title phrase
  surfaced Reddit/HN feed items above the video itself. Synthesized dimension docs
  would be far more findable than raw transcript storage.

## Risks

- **Tier1 auto-pass for long-form assumes ingestion-time curation always holds** —
  true for this session's manual channel-backfill filtering, not guaranteed for a
  future bulk-queued long-form source. Mitigation: design a lightweight per-adapter
  Tier1 (even a cheap heuristic) rather than an unconditional skip — open question
  for DECOMPOSE, not resolved here.
- **Embedding-based Tier2 clustering quality is an unverified claim** — asserted as
  "probably more accurate," not measured. Mitigation: cheap to fall back to LLM
  clustering if it underperforms in practice; consider a small spike before full
  commitment if the team wants evidence before building on top of it.
- **Scope creep from folding in the ShortSignalAdapter fix** — accepted deliberately
  this round (prompt wording only, no adapter-kind proliferation), not a rabbit hole,
  but worth remembering as the reason this diff touches LinkedIn's prompt at all.

## Second-order effects

- Build embedding-based Tier2 for long-form → it's cheaper and content-grounded and
  works well → **opportunity/tension**: this creates pressure to eventually ask why
  LinkedIn doesn't get the same treatment, which pushes on the "LinkedIn stays
  untouched" boundary deliberately drawn in this same discussion. Not a problem now —
  named so it isn't rediscovered awkwardly later.

## Engineering disciplines

- **DDD:** small glossary addition to `docs/domain/` for the content-shape/adapter
  concept on `UrlEntry` — not a big lift, `docs/domain/MODEL-001-brana-core.md`
  currently doesn't document `UrlEntry`/`PipelineState` at all.
- **ADR needed:** yes — load-bearing interface contract (adapter dispatch shape,
  platform→adapter mapping, per-tier behavior divergence).
- **TDD:** adapter dispatch and prompt-generation logic are pure functions, testable
  without I/O before implementation. Embedding-clustering *quality* is an eval
  question, not something a unit test proves.
- **Docs:** tech doc at `docs/architecture/features/{slug}.md`; no separate user
  guide unless `brana knowledge process` gains new user-visible flags. Existing docs
  to touch: `docs/architecture/features/youtube-channel-ingestion.md` (doesn't
  mention Tier1/2/3 today) and `docs/architecture/features/knowledge-architecture-v2.md`
  (doesn't mention YouTube today).

## Next steps

1. Write ADR: PlatformAdapter for the knowledge pipeline (enum dispatch; pipeline
   skeleton shared, steps overridden per adapter).
2. DECOMPOSE t-3151 into build tasks: adapter enum + dispatch; ShortSignalAdapter
   generalization (platform-aware prompt wording); LongFormAdapter (Tier1 auto-pass
   with the curation caveat addressed, Tier2 embedding clustering, Tier3
   content-grounded drafting); wiring from `drain-links`/`channel-backfill` output
   into `PipelineState`.
3. Optional small spike to sanity-check embedding-clustering quality before full
   commitment.
