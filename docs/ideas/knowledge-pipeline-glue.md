---
title: Knowledge Pipeline Glue
status: promoted
promoted_to: docs/architecture/decisions/ADR-042-knowledge-ingest-canonical-entry-point-gemini-routing.md
created: 2026-05-24
---

# Knowledge Pipeline Glue

> Brainstormed 2026-05-24. Promoted to ADR-042 on 2026-05-24.
> Builds on: [`layered-input-processing.md`](./layered-input-processing.md) (closes the unimplemented gap).
> Related: ADR-040 (compute routing — Gemini for bulk classification).

## Problem

The knowledge pipeline has 6 manual steps and no orchestration. To process a batch of URLs today:

```
/brana:log bulk          ← skill, writes to event-log.md (LinkedIn only)
brana knowledge process --tier1
brana knowledge process --tier2
brana knowledge process --report
brana knowledge process --draft <topic>
brana knowledge promote <path>
```

No command tells you where you are. No command chains the steps. Non-LinkedIn URLs silently drop.
Gemini (cheap bulk classification) and ruflo (semantic dedup) are unused despite ADR-040 deciding they should handle Tier 1/2.

The pipeline was designed correctly in `layered-input-processing.md` — it just wasn't implemented.

## Use cases

**Phase 1 — Bulk paste (now):**
User has a WA dump, a URL list, or a batch of links. Wants to feed them all in and have the pipeline run.

**Phase 2 — Telegram bot (later):**
URLs arrive one-by-one via Telegram. Bot calls the same ingestion API per message.
The single-URL case is just a degenerate batch of 1.

## Solution

Six additions to `brana knowledge`:

### 1. `brana knowledge ingest` — source-agnostic URL entry point

```
brana knowledge ingest inbox/whatsapp-chat.txt     # file (WA dump, any text format)
brana knowledge ingest https://... https://...     # positional URLs
cat urls.txt | brana knowledge ingest              # stdin
brana knowledge ingest --source telegram <url>     # Phase 2 hook
```

**Implementation:**
- Regex `https?://[^\s<>]+` applied to any input text — works on WA exports, plain lists, Telegram message bodies
- Deduplicate against existing `pipeline-state.json` (URL already queued or processed)
- Platform-tag each URL: `linkedin | github | substack | arxiv | other`
- Report: `N new URLs queued, M duplicates skipped, K already processed`
- Writes directly to `pipeline-state.json` (same state the existing `--tier1` reads)

**Telegram wiring (Phase 2):** `brana knowledge ingest --source telegram <url>` is the stable API.
The Telegram bot just shells out to this command per message. No pipeline changes needed.

### 2. Remove LinkedIn-only filter

`knowledge_pipeline.rs:225` has `if !line.contains("linkedin.com/posts/") { continue; }`.
Remove this line. Accept any `https://` URL from the event log.

Tier 1 scoring already adapts to content quality (full | meta-only | unfetched) — non-LinkedIn
URLs degrade gracefully (scored on title/domain signal only until fetched).

### 3. `brana knowledge next` — state-aware directive

Reads pipeline state, emits exactly one command to run. Zero LLM calls.

```
$ brana knowledge next

  Pipeline status: 847 URLs queued
  → Run: brana knowledge run

$ brana knowledge next   (mid-run)

  Tier 1 complete: 47 passed, 800 irrelevant
  Tier 2 complete: 3 clusters
  → Review: brana knowledge process --report
  → Then:   brana knowledge process --draft <topic>

$ brana knowledge next   (draft on disk)

  Draft ready: brana-knowledge/drafts/2026-05-24-agent-tooling.md
  → Accept: brana knowledge promote brana-knowledge/drafts/2026-05-24-agent-tooling.md
  → Reject: rm brana-knowledge/drafts/2026-05-24-agent-tooling.md

$ brana knowledge next   (pipeline current)

  Pipeline up to date. Queue 0 URLs.
  → Add more: brana knowledge ingest <source>
```

State → directive mapping (no ambiguity):

| State | Directive |
|-------|-----------|
| unprocessed > 0 | run (or tier1 if run unavailable) |
| tier1_passed > 0, no clusters | tier2 |
| clusters exist, no drafts | process --report |
| drafts on disk | promote or rm |
| all current | ingest more |

### 4. `brana knowledge run` — chained pipeline

Chains tier1→tier2 automatically. Gates at human judgment points.

```
$ brana knowledge run

  Tier 1: scoring 847 URLs (Gemini Flash)...
  ✓ 47 passed, 800 irrelevant

  Tier 2: clustering 47 URLs...
  ✓ 3 clusters ready

  ──────────────────────────────────────────
  Gate: cluster review required.
  Run: brana knowledge process --report
  Then pick a topic: brana knowledge process --draft <topic>
  ──────────────────────────────────────────

$ brana knowledge run   (after draft is approved)

  Draft ready: brana-knowledge/drafts/2026-05-24-agent-tooling.md
  ──────────────────────────────────────────
  Gate: draft review required.
  Run: brana knowledge promote <path>
  ──────────────────────────────────────────
```

No looping past human gates. `run` always stops at a decision point and tells you what to do.

### 5. Gemini for Tier 1 + Tier 2 (ADR-040 compute routing)

Currently `call_claude_json()` is used for Tier 1 scoring — Claude called 50× per batch.
ADR-040 decided: Gemini for bulk classification, Claude for synthesis.

Tier 1 = relevance classification → Gemini Flash
Tier 2 = clustering = topic classification → Gemini Flash
Tier 3 = dimension draft synthesis → Claude Sonnet (unchanged)

Implementation: add `call_gemini_json()` in `brana-core` alongside existing `call_claude_json()`.
Tier 1/2 handlers switch to Gemini. Tier 3 stays Claude.

Cost impact: Tier 1 batch of 50 URLs:
- Today (Claude Sonnet): ~$0.50–1.50
- After (Gemini Flash): ~$0.01–0.05

### 6. Ruflo semantic dedup before Tier 1

Before scoring a URL in Tier 1, check if its topic is already covered in brana-knowledge:

```rust
let existing = ruflo_search(url.title_signal, namespace: "knowledge", limit: 2, threshold: 0.85);
if existing.len() > 0 && existing[0].similarity > 0.85 {
    mark_url(state, &url.url, UrlStatus::Irrelevant);  // already covered
    continue;
}
```

This catches "yet another MCP tutorial" even if the specific URL was never seen before.
Threshold 0.85 — tight enough to only skip near-duplicates (calibrated from t-1589).

## Architecture summary

```
SOURCES
  ├── brana knowledge ingest <file|urls|stdin>   (Phase 1)
  ├── brana knowledge ingest --source telegram   (Phase 2)
  └── event-log.md (existing, now URL-agnostic)
          ↓
  pipeline-state.json (URL queue)
          ↓
  brana knowledge run
    ├── ruflo dedup check (semantic, threshold 0.85)
    ├── Tier 1: Gemini Flash scoring (relevance)
    ├── Tier 2: Gemini Flash clustering
    ├── GATE → brana knowledge process --report + --draft
    ├── Tier 3: Claude Sonnet drafting
    └── GATE → brana knowledge promote

  brana knowledge next  (read state → emit one directive, anytime)
```

## Engineering disciplines

- **DDD:** ADR — formalizes `ingest` as canonical URL entry point; documents Gemini routing for Tier 1/2; Telegram as Phase 2 client of `ingest`. Extends or amends ADR-040.
- **TDD:** Unit tests for: `ingest` dedup logic; `next` state→directive mapping (6 states); LinkedIn filter removal (non-LinkedIn URL enters state); Gemini routing (mock Gemini call, verify JSON output shape); ruflo dedup skip (mock search result, verify `Irrelevant` status set).
- **SDD:** Update `layered-input-processing.md` — close unimplemented gap, mark `next` and `run` as shipped. Update CLAUDE.md command table. Update `docs/reference/` for new subcommands.

## Possible next steps

1. ADR — ingest as canonical entry point + Gemini routing (extends ADR-040)
2. Remove LinkedIn filter in `knowledge_pipeline.rs:225`
3. `brana knowledge ingest` — CLI subcommand + URL extractor + dedup against pipeline state
4. `brana knowledge next` — state→directive mapping, ~50 lines Rust
5. `call_gemini_json()` in brana-core + wire into Tier 1 + Tier 2
6. Ruflo dedup check in Tier 1 loop
7. `brana knowledge run` — chain tier1→tier2, gate at clusters + drafts
8. Update `layered-input-processing.md` + CLAUDE.md + reference docs
9. Telegram bot Phase 2 — wire webhook → `brana knowledge ingest --source telegram`
