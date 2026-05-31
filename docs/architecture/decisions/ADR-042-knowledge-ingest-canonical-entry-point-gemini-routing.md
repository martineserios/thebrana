---
status: accepted
produced_by: docs/ideas/knowledge-pipeline-glue.md
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
