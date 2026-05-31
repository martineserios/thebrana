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
