# Feature: PlatformAdapter for the knowledge pipeline

**Date:** 2026-08-24
**Status:** built
**Task:** t-3151

## Problem

`brana knowledge process` can't synthesize YouTube transcripts (or any long-form
content) into dimension docs, and mislabels non-LinkedIn URLs (GitHub, Substack,
arxiv) as LinkedIn posts when scoring relevance — see
[ADR-087](../decisions/ADR-087-knowledge-pipeline-platform-adapters.md) for the full
context.

## Decision Record

See [ADR-087](../decisions/ADR-087-knowledge-pipeline-platform-adapters.md) — the
architectural decision (enum-dispatched `PlatformAdapter`, shared pipeline skeleton,
per-step overrides) is frozen there. ADR-087 depends on
[ADR-042](../decisions/ADR-042-knowledge-ingest-canonical-entry-point-gemini-routing.md)
(Accepted) — `ingest` is the canonical, sole writer into `PipelineState`; this
feature's wiring must extend `ingest`, not add a second writer. This spec covers
implementation scope only.

## Constraints

- LinkedIn's actual scoring/clustering logic must not change (only prompt wording
  generalizes for non-LinkedIn `ShortSignalAdapter` platforms).
- No podcast/audio-transcription fetch mechanism — out of scope.
- Does not touch or unblock t-1144.
- Per ADR-042 §1: no code path other than `brana knowledge ingest` may write
  directly into `PipelineState`. Caught during this task's own DECOMPOSE impact
  analysis — an earlier SPECIFY-stage draft of ADR-087 left "`drain-links` writing
  into both stores" as a candidate, which would have violated this.

## Scope (v1)

- `PlatformAdapter` enum with two variants: `ShortSignal`, `LongForm`.
- Dispatch by `UrlEntry.platform` (already populated by `classify_platform`).
- `ShortSignalAdapter`: generalize `build_tier1_prompt`/`build_tier2_prompt` wording
  per platform (linkedin/github/substack/arxiv) — no logic change.
- `LongFormAdapter`:
  - Tier1: semantic-dedup pre-filter still runs (unchanged, no LLM cost); only the
    LLM relevance-scoring call is skipped — auto-pass with a fixed score and
    reason "pre-curated at ingestion".
  - Tier2: embedding-similarity clustering via ruflo semantic search, replacing the
    LLM call for this adapter only.
  - Tier3: draft prompt includes real excerpts from `fetched_content`, not just
    metadata.
- Wiring (resolved, not TBD — ADR-042 compliance forced the choice): extend
  `brana knowledge ingest` to accept an already-processed ruflo `knowledge:url:*`
  key or a long-form URL directly, and populate `UrlEntry.fetched_content` from
  ruflo when available at ingest time. `ingest` stays the sole writer into
  `PipelineState` (ADR-042 §1) — no new writer, no `drain-links`-writes-both-stores
  path.
- `ingest`'s key derivation switches to `canonicalize_url()` (the same function
  ruflo's `url_storage_key()` uses) instead of the raw literal URL. This is a hard
  requirement (ADR-087's "Required: shared URL identity" section), and improves
  LinkedIn's own dedup accuracy in `ingest_urls`'s `contains_key` check as a
  byproduct — not scope creep, a direct consequence of fixing the identity bug at
  its actual source.
- **Sibling touch point, not itself in scope:** `backfill_linkedin_fields`
  unconditionally calls `parse_linkedin_url` on any `UrlEntry` missing `author`/
  `title_signal`, regardless of platform. Harmless no-op for non-LinkedIn URLs
  today, but DECOMPOSE should confirm `LongFormAdapter` entries either don't need
  `author`/`title_signal` populated at all, or get them from a YouTube-appropriate
  source instead of silently falling through this LinkedIn-shaped backfill.

## Research

See [the idea doc](../../ideas/knowledge-pipeline-platform-adapters.md) for the full
brainstorm trail — research findings, risks, and the second-order tension this
surfaces (embedding-clustering success pressuring the "LinkedIn stays untouched"
boundary later).

## Assumptions

- `fetched_content` on `UrlEntry` is the right field to reuse for long-form content.
  **Resolved:** it's a plain generic `Option<String>` on the struct with no
  exclusivity annotation; its doc comment names t-1144 only as the currently
  *planned* consumer, not the sole owner. Safe to populate for `LongFormAdapter`
  entries without conflicting with t-1144's LinkedIn scope.
- Tier1 auto-pass for `LongFormAdapter` is safe because all long-form content reaching
  the pipeline is manually curated at ingestion today. **Not guaranteed to hold for
  future bulk-queued sources — flagged as an open risk in ADR-087, not resolved here.**
- Embedding-similarity clustering will produce comparable-or-better cluster quality
  than the existing LLM-based Tier2 for long-form content. **Unverified — candidate
  for a small spike before full implementation.**
- `LongFormAdapter`'s Tier1 auto-pass still runs through the existing semantic-dedup
  pre-filter (`check_semantic_dedup`, t-1668) — only the LLM relevance-scoring call
  is skipped, not the dedup check, since dedup costs no LLM call and skipping it
  would let duplicate topics reach the expensive Tier3 step. **Resolved — see
  ADR-087.**

## Behavior

- Running `brana knowledge process --tier1` on a queue containing YouTube URLs:
  they auto-pass with no LLM call, logged distinctly from a real score.
- Running `--tier2`: YouTube entries cluster via embedding similarity against
  existing dimension topics; LinkedIn entries cluster exactly as before.
- Running `--tier3 <topic>` on a YouTube-sourced cluster: the drafted section quotes
  or closely paraphrases real transcript content, not just author/title synthesis.
- A GitHub URL ingested via `brana knowledge ingest` and scored via `--tier1` is
  judged with GitHub-appropriate prompt wording, not LinkedIn's.

## Edge Cases

- A `LongFormAdapter` URL with empty/missing `fetched_content` (fetch failed
  upstream): Tier3 must not draft from nothing — skip with a clear log line, don't
  silently produce an empty-graded draft.
- A cluster with only one long-form source: embedding clustering degenerates to a
  single-item "cluster" — decide whether Tier3 still drafts from n=1 or requires a
  minimum cluster size (LinkedIn's existing behavior for this case should inform the
  answer).

## Design

Technical approach to be filled in during DECOMPOSE, once the wiring mechanism
(new command vs. `drain-links` writing to both stores) and the Tier1-curation /
Tier2-quality open risks from ADR-087 have owners.

## Boundaries

| Always | Ask First | Never |
|--------|-----------|-------|
| Preserve LinkedIn's exact scoring/clustering output for `ShortSignalAdapter` | Whether Tier1 auto-pass stays unconditional or gets a curation heuristic | Touch t-1144's scope or its gating condition |
| Dispatch via enum match, not `dyn Trait` | Whether a spike precedes full Tier2 embedding-clustering implementation | Build a podcast/audio fetch mechanism |

## Testing Strategy

- **Unit:** adapter dispatch (platform → adapter kind), per-adapter prompt
  construction (all platforms), Tier1 auto-pass logic, embedding-clustering
  assignment logic with fixture embeddings — target 70%+ of budget.
- **Integration:** full `--tier1`/`--tier2`/`--tier3` runs against a fixture
  `PipelineState` mixing LinkedIn and YouTube entries, verifying no cross-adapter
  leakage.
- **E2E:** none planned — `cmd_process`'s existing CLI smoke coverage should extend
  naturally once fixtures include long-form entries.
- **Mock policy:** real ruflo memory search for embedding clustering where feasible;
  mock only the LLM call boundary (Gemini/`claude -p`).

## Documentation Plan

- [ ] **Tech doc** — this file: design section to be completed in DECOMPOSE.
- [ ] **Domain glossary** — `docs/domain/MODEL-001-brana-core.md` doesn't document
      `UrlEntry`/`PipelineState` at all today; add a small glossary entry for the
      content-shape/adapter concept introduced here. (Named in the idea doc's
      Engineering Disciplines section; restored here after the challenger caught it
      dropped from this Plan — see Challenger findings below.)
- [ ] **Existing docs to update (impact-analysis-confirmed via spec-graph `impl_files`,
      supersedes an earlier unconfirmed guess)** —
      `docs/architecture/features/inbox-to-dimensions-pipeline.md` (the actual tech
      doc for Tier1/2/3 — directly describes the pipeline this feature modifies,
      including the ADR-042 architecture diagram that needs a `LongFormAdapter`
      branch added) and `docs/architecture/features/youtube-channel-backfill.md`
      (impl_files match on both `knowledge.rs` and `knowledge_pipeline.rs`).
      `youtube-channel-ingestion.md` and `knowledge-architecture-v2.md` were an
      earlier guess before impact analysis ran — worth a quick check in DECOMPOSE
      for whether they also need touching, but not confirmed the way the two above
      are.
- [ ] **User guide** — resolved (was TBD, challenger caught it unresolved on the
      sprint-contract pass): `ingest` gains a user-visible `--from-ruflo <key>` flag
      (ADR-087, matching ADR-042 §3's `--source telegram` precedent) — document it
      wherever `ingest`'s existing flags are documented. `process` itself gains no
      new flags.

## Challenger findings

Reviewed 2026-08-24 (context-isolated agent, full repo read access). Verdict:
**RECONSIDER** on the first pass — one score-4 finding, addressed below before this
spec was presented for approval.

**Critical (score 4, addressed):** the proposed wiring never reconciled two
different URL identity functions — `ingest_urls` keys by raw URL,
`process_one_url`/`url_storage_key` canonicalizes first. Fixed by adding an explicit
hard requirement (ADR-087 "Required: shared URL identity", and the matching line in
this spec's Scope) that DECOMPOSE's wiring mechanism must key by the same
canonicalized identity ruflo uses.

**Warnings (addressed):**
- My own ADR claimed "zero trait-object adapters" in the codebase — false;
  `search.rs`'s `SearchProvider` is a live `dyn Trait` precedent. Corrected in
  ADR-087's Decision section; the enum-dispatch choice itself stands (closed
  2-variant set), the stated rationale was wrong and is now accurate.
- Semantic-dedup (t-1668) interaction with `LongFormAdapter`'s Tier1 auto-pass was
  unaddressed — now an explicit open question in both ADR-087's Consequences and
  this spec's Assumptions.

**Observations (addressed):**
- "Tier2 stops producing a reason string; UI/report code needs a fallback"
  overstated the surface — `reason` isn't persisted anywhere, only printed once.
  Corrected in ADR-087.

---

**Sprint-contract review, second pass, 2026-08-24 (context-isolated agent).**
Verdict: **RECONSIDER** — two critical gaps in the 12-subtask decomposition itself,
both fixed before presenting the plan for approval:

1. **The mixed LinkedIn+YouTube integration test named in the Testing Strategy and
   the sprint contract's own success criteria had no owning subtask** — all 12
   original subtasks could complete green without it ever running. Fixed: added
   t-3183, blocked_by both adapter implementations, blocking the docs task.
2. **No migration for `~/.swarm/knowledge-pipeline-state.json`'s existing production
   data** once the canonicalization key fix ships — a differently-decorated re-ingest
   of an already-seen URL would silently duplicate it. Fixed: added t-3182
   (one-time re-key migration with collision handling), blocked_by the key fix,
   blocking the ingest-wiring implementation task.

Warnings from this pass, also addressed: ADR-087 flipped from Proposed to Accepted
(stabilized after two full challenger passes); the `--from-ruflo <key>` CLI surface
for ingest was left ambiguous — resolved via an explicit user decision rather than
picked silently (see ADR-087); `backfill_linkedin_fields` was confirmed low-risk by
reading `ingest_urls`'s actual fallback-signal logic rather than asserted; the user
guide's "TBD" item resolved to documenting the new flag.
- `backfill_linkedin_fields` touches every platform unconditionally, unnamed in the
  original scope — now a named sibling touch point in this spec's Scope section.

**Discipline gap (addressed):** the idea doc's DDD glossary action item was dropped
when promoted into this spec's Documentation Plan — restored above.

SIBLINGS confirmed by the challenger: `knowledge.rs` (`backfill_linkedin_fields`,
`check_semantic_dedup` call site, `url_storage_key`/`canonicalize_url`),
`knowledge_pipeline.rs` (`ingest_urls`), `docs/domain/MODEL-001-brana-core.md`
(missing glossary entries) — all now named explicitly in this spec or ADR-087
rather than left implicit.
