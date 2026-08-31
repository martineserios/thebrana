# Knowledge pipeline — fetch tiers and the YouTube tier

> Tech doc for the URL-ingestion side of the knowledge pipeline: how `drain-links`
> turns captured URLs into stored knowledge, and the design decisions behind the
> YouTube fetch tier (t-2950, shipped 2026-08-21). Home of record for the full
> YouTube design: [features/youtube-knowledge-extraction.md](features/youtube-knowledge-extraction.md)
> (Phase 1, shipped). Operator guide: docs/guide/features/knowledge-drain-links.md.

## Pipeline shape

`brana knowledge drain-links` selects pending `link`-tagged tasks, routes each URL
through a platform-specific fetch tier (`classify_platform()`,
`brana-core/src/knowledge_pipeline.rs:626`), and stores the result under the
**flat key `knowledge:url:<slug>`** in the ruflo knowledge namespace. The stored
key doubles as the idempotency marker — a URL with a stored key is never
re-fetched. Tiers: plain HTTP+HTML-strip for public URLs, MCP client for
LinkedIn, and a `yt-dlp` subprocess for YouTube.

For every non-YouTube tier, the `Store` arm runs `extract_insight()` (LLM
summarization: agy → `claude -p` → truncated raw) and stores the summary.

## The YouTube tier

YouTube URLs get a dedicated tier because the generic HTTP tier returns the SPA
shell — title and meta tags, no captions (the `t-1349` "fetch succeeds, content
absent" class). The tier shells out to `yt-dlp` once per video
(`fetch_youtube_content`, `knowledge_pipeline.rs:2476`) — a subprocess, never a
Rust YouTube client library, same shape as the LinkedIn MCP client. It downloads
the primary-language caption track, dedupes VTT word-reveal cues
(`dedupe_vtt_cues`, pure), and stores the **raw transcript** — the youtube
branch skips `extract_insight` entirely (summarizing a 2h video's 152K-char
transcript into a blurb would reproduce t-1349 one layer deeper and strand
Phase 2's raw-transcript dependency). Tags are the fixed triple
`[youtube, transcript, <caption_source>]` with `caption_source` ∈
`manual`/`auto`, read from `yt-dlp --dump-json`'s `requested_subtitles` vs
`automatic_captions` fields (`determine_youtube_caption_source`,
`knowledge_pipeline.rs:2386`).

### Decision: flat `knowledge:url:<slug>` storage, not a directory bundle

The transcript flows through the pipeline's existing
`ruflo_memory_store(key, value, namespace, tags)` call — the same flat key
every other tier uses. No new storage function, no schema change. The idea
doc's `raw/`+`sources/`+`concepts/`+`entities/` directory bundle is
**explicitly not Phase 1**: a directory is not a string value, so it cannot be
written through the flat-value store at all — and writing one would leave the
idempotency key unset, making every scheduler cycle re-fetch every YouTube URL
forever, invisible to `brana recall`. Bundle storage is Phase 2 (t-2943),
itself gated on t-2937 (OKF adoption — a brana-wide decision this tier does
not make). Corrected 2026-08-17 by `/brana:challenge` from an earlier
bundle-shaped draft.

### Decision: no-captions is `Ok(None)`, never an error, never `Completed`

`yt-dlp` exiting 0 with zero subtitle files written is a **distinct, expected
outcome** — the video has no captions. `fetch_youtube_content` returns
`Ok(None)` for it (same shape as a LinkedIn "post not in feed" miss), and
`process_one_url` treats `Ok(None)` as "leave the task pending, never mark
`Completed`". Collapsing it into success would mark caption-less videos done
with nothing stored (t-1349's bug); collapsing it into `Err` would retry a
permanent condition forever. The contract is pinned by fixture tests, including
the t-3238 hardening: a VTT decode failure lossy-decodes with a loud warning
instead of silently resolving to the same `None` as genuinely-missing captions.

### Decision: YouTube gets its own scheduler job, not per-platform sub-caps

`select_drain_batch()` stays a bare `.take(cap)` — no per-platform accounting.
Instead the shared `link-research-extraction` job excludes YouTube
(`classify_platform(url) != "youtube"`), and a dedicated
`link-research-extraction-youtube` job runs `drain-links --cap 3 --platform
youtube` on the same 4h cadence, offset 2h so the two jobs never race the
tasks.json lock. Why: sub-cap accounting is new state-tracking logic that
Phase 3 (channel crawl, own cadence and rate-limit budget) would immediately
replace with a separate job anyway — and isolation means a stuck or retrying
YouTube fetch can only starve its own job's slots, never
LinkedIn/GitHub/Substack/arxiv's. The job ships **disabled** pending a human
enable: YouTube's bot-check blocks unauthenticated `yt-dlp` (t-3033), so a
cookie jar must first exist at `~/.config/brana/yt-cookies.txt`, mode 0600
(t-3038; export blocked on this host — t-3167).

### Rate limiting

HTTP 429 is real (observed live 2026-08-17 on the third request of a
multi-language caption fetch — which is why Phase 1 requests a single
`--sub-langs "en"` track). Retry lives **inside** the tier, not the scheduler:
`run_with_youtube_backoff` (`knowledge_pipeline.rs:2774`) retries up to
`YOUTUBE_BACKOFF_MAX_RETRIES = 5` with paced delays, matching stderr against
the literal `"HTTP Error 429"` (never a bare `429` substring — a video ID
containing those digits must not trigger a retry). Any other failure surfaces
immediately.

### Security posture

The URL is attacker-influenced input (captured via Telegram): the `yt-dlp`
argv always places `--` before the URL so a `-`-prefixed string cannot be
parsed as a flag (`yt-dlp` has `--exec`) — same untrusted-input class as the
LinkedIn `/safety/go/` unwrap (ADR-070 §Amendment 2026-08-01). The cookie jar
is refused if group/other-readable. Fetch code never acquires
`lock_pipeline()` (ADR-070 §Lock discipline).

## Known limitations / open items

- **`caption_source` provenance is unverified against live yt-dlp** — a
  Challenger finding (t-2950, sev 4, user-overridden) notes
  `requested_subtitles` may also populate on `--write-auto-sub` writes, which
  would mislabel auto-only videos as `manual`. Tag-accuracy risk only (same
  single file is stored either way). Live verification is tracked as t-3255,
  gated in practice on the t-3167 cookie jar.
- Semantic search reaches only a stored transcript's opening content (feature
  spec §6); deep-content retrieval is Phase 2's concern.
- Channel-crawl ingestion (Tier A, t-2997/t-2999) is specced separately in
  [features/youtube-channel-ingestion.md](features/youtube-channel-ingestion.md).
