---
status: accepted
produced_by: docs/ideas/drained/knowledge-pipeline-glue.md
depends_on: [ADR-040]
operationalized_by: docs/architecture/features/knowledge-pipeline-compute.md
---
# ADR-042: Knowledge Pipeline — `ingest` as Canonical URL Entry Point + Gemini Routing for Tier 1/2

**Status:** Accepted  
**Date:** 2026-05-24  
**Task:** t-1663 (knowledge-pipeline initiative)

---

## Context

The brana knowledge pipeline has no single entry point for URLs. Today, URLs enter via
`/brana:log` (LinkedIn only) and are processed through six manually-invoked steps with
no orchestration. Non-LinkedIn URLs silently drop. Tier 1 and Tier 2 classification call
Claude Sonnet 50+ times per batch despite ADR-040 §3 deciding Gemini is the right model
for atomic, system-isolated classification tasks.

Three decisions need to be locked before implementation work begins:

1. Where URLs enter the pipeline (source authority)
2. Which model handles which tier (compute routing)
3. How Telegram (Phase 2) wires into the pipeline without requiring pipeline changes

---

## Decision

### 1. `brana knowledge ingest` is the canonical URL entry point

All URLs enter `pipeline-state.json` through `brana knowledge ingest`. No other code path
writes URLs directly to pipeline state.

`ingest` accepts:
- Positional URLs: `brana knowledge ingest https://... https://...`
- File input (WA exports, plain URL lists, any text): `brana knowledge ingest inbox/dump.txt`
- Stdin: `cat urls.txt | brana knowledge ingest`
- Source-tagged input (Phase 2): `brana knowledge ingest --source telegram <url>`
- Ruflo-content attach (t-3177): `brana knowledge ingest <url> --from-ruflo <knowledge:url:key>`
  populates the entry's `fetched_content` from an already-drained ruflo store entry
  (exactly one URL — key slugs are lossy). Without the flag, LongForm URLs
  best-effort probe `url_storage_key(url)` automatically at ingest.

URL extraction is regex-based (`https?://[^\s<>]+`) applied to any input text. Platform
tagging (`linkedin | github | substack | arxiv | other`) is assigned at ingest time.
Deduplication against existing pipeline state runs before any URL is queued — already
queued or processed URLs are skipped with a count reported to the user.

The existing `event-log.md` path (via `/brana:log`) remains supported for backward
compatibility but is now a client of `ingest` semantically — it writes URLs to event-log,
and `parse_event_log()` feeds them into the same pipeline state on the next `ingest` or
`run` invocation.

### 2. Gemini Flash for Tier 1 and Tier 2; Claude Sonnet for Tier 3

| Tier | Operation | Model | Rationale |
|------|-----------|-------|-----------|
| Tier 1 | Relevance scoring (per-URL classification) | Gemini Flash | Atomic, system-isolated, brana-agnostic — matches ADR-040 §3 |
| Tier 2 | Topic clustering (classification across URLs) | Gemini Flash | Bulk, parallel, no in-session brana state required |
| Tier 3 | Dimension draft synthesis | Claude Sonnet | Requires brana ADR context, system conventions, in-session judgment |

This extends ADR-040 §3 ("Gemini is dispatched, never coordinated") to the knowledge
pipeline specifically. Gemini output from Tier 1/2 is input to Claude's judgment — Claude
decides which clusters to promote, not Gemini.

ADR-040 /tmp/ invariant (§5) applies: Gemini output lands in `/tmp/` only. Claude reads
and applies changes via `Write`/`Edit`.

Implementation: `call_gemini_json()` is added to `brana-core` alongside `call_claude_json()`.
Tier 1/2 handlers switch to `call_gemini_json()`. Tier 3 stays `call_claude_json()`.

Cost impact at 50-URL batch:
- Before (Claude Sonnet Tier 1): ~$0.50–1.50 per batch
- After (Gemini Flash Tier 1): ~$0.01–0.05 per batch

### 3. Telegram is a Phase-2 client of `ingest`; no pipeline changes required

The Telegram bot (Phase 2) calls `brana knowledge ingest --source telegram <url>` per
message. The `--source` flag is metadata only — it tags the URL for provenance tracking
but does not change pipeline behavior. The pipeline is source-agnostic at Tier 1+.

This means Phase 2 is a bot integration task, not a pipeline task. The pipeline ships
complete in Phase 1. The Telegram bot wires to a stable, unchanging CLI interface.

---

## Architecture (post-ADR state)

```
SOURCES
  ├── brana knowledge ingest <file|urls|stdin>     ← Phase 1 entry point
  ├── brana knowledge ingest --source telegram     ← Phase 2 entry point (stable API)
  └── event-log.md (existing — feeds pipeline state on next ingest/run)
          ↓
  pipeline-state.json (URL queue, platform-tagged, deduplicated)
          ↓
  brana knowledge run
    ├── ruflo semantic dedup (threshold 0.85, namespace: knowledge)
    ├── Tier 1: Gemini Flash — relevance scoring
    ├── Tier 2: Gemini Flash — topic clustering
    ├── GATE → brana knowledge process --report + --draft   ← human judgment
    ├── Tier 3: Claude Sonnet — dimension draft synthesis
    └── GATE → brana knowledge promote                      ← human judgment

  brana knowledge next  ← read-only state→directive mapping (zero LLM calls)
```

---

## Consequences

- `call_gemini_json()` must be implemented in `brana-core` before Tier 1/2 can route to Gemini (tracked: t-1667).
- `brana knowledge ingest` CLI subcommand must be implemented before `ingest` becomes the entry point (tracked: t-1665).
- `brana knowledge next` (state→directive) must be implemented for pipeline observability (tracked: t-1666).
- `brana knowledge run` (chained Tier 1→2 with gates) must be implemented (tracked: t-1668).
- Ruflo semantic dedup (Tier 1 pre-check) must be wired (tracked: t-1669).
- `layered-input-processing.md` must be updated to close the unimplemented gap and mark `next` and `run` as shipped (tracked: t-1670).

## Non-Actions

- This ADR does not define the internal `call_gemini_json()` API contract (covered in t-1667).
- This ADR does not specify the Telegram bot implementation (Phase 2, untracked).
- This ADR does not change Tier 3 (Claude Sonnet synthesis) — that decision was already stable in ADR-040.
- This ADR does not define ruflo dedup threshold calibration (0.85 is from t-1589; re-calibration is out of scope here).

## Amendment (t-2028, 2026-07-24): `type:` frontmatter requirement on ingest output

The knowledge-base redesign (`docs/ideas/drained/knowledge-base-redesign.md`, promoted via t-2021/t-2022)
establishes one frontmatter schema where every knowledge file declares its ontology `type:`
(atom: `claim`/`pattern`/`event`/`source`; synthesis: `hub`/`decision`) so graph, ruflo, and
Obsidian read the same source of truth with zero translation.

**Amendment:** per ADR-057 (Unit of Knowledge, accepted 2026-06-12, authored under t-2027), which
already defines the concrete ontology enum `type: claim | pattern | event | source | hub |
decision` and explicitly names this amendment (ADR-057 §"ADR-038 disposition": *"ADR-042 is
amended (t-2028, separate task) only to require `type:` frontmatter on ingest output; its Tier
1/2 Gemini routing is untouched"*) — this pipeline's Tier 3 draft output (`brana knowledge
process --draft`, `system/cli/rust/crates/brana-cli/src/commands/knowledge.rs`, `draft_content`
frontmatter block — currently `status`/`created`/`sources`/`cluster_topic`/`draft_author`/
`review_due`/`promotion_target`, no `type:` key) must add `type: claim` to that frontmatter block.
A drafted addition to a dimension is a sourced, falsifiable synthesis awaiting human review before
promotion — ADR-057 §2 defines `claim` as exactly this: *"falsifiable statement; carries
confidence and review_due"* (the draft already carries `review_due`). Implemented as a follow-on
(t-2437).

*(Corrects an earlier version of this amendment, 2026-07-24, which incorrectly described the
ontology enum as still pending on t-2022 — t-2022's child task t-2027 had already produced and
merged ADR-057 a month prior; t-2022 itself simply hadn't been marked complete. Fixed as t-2438.)*

**Non-Action (amendment-scoped):** this amendment does not touch Tier 1/2 Gemini routing (§2
above, unchanged) and does not absorb or supersede any of the 6 overlapping kb-redesign idea
docs — that's the separate idea-doc absorption task (t-2029).
