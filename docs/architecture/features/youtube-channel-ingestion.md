# YouTube channel ingestion — Phase 3, Tier A (t-2993)

> Feature spec for [ADR-070](../decisions/ADR-070-knowledge-process-url-headless-fetch.md)
> §Amendment (2026-08-19, t-2994) — channel-ingest selection surface. Builds on
> [Phase 1](youtube-knowledge-extraction.md) (single video/shorts transcript
> extraction) — reuses its fetch/dedupe/store path unchanged. Source spike:
> t-2994 (live-probed against a real channel, findings recorded in the ADR
> amendment).

Status: **spec — not yet decomposed into implementation tasks.** This is the
M-effort spec-gate artifact `t-2993` (Phase 3 — Channel ingestion milestone)
requires before any `system/`, `src/`, `lib/`, or `bin/` write can begin. Once
reviewed, file implementation tasks under `t-2993` per §Follow-up below.

## Problem

Phase 1 fetches one video URL at a time — there's no way to say "give me
channel X's videos" without manually listing every URL by hand. t-2994's
spike confirmed `yt-dlp --flat-playlist` can enumerate a channel's videos
cheaply, but only a subset of possible selection criteria are actually cheap
to evaluate; picking the wrong tier to build first either wastes effort on
an unusable design (date filtering that silently no-ops) or over-builds
(per-video full-metadata fetches nobody asked for yet). This spec scopes the
first implementation cut to exactly what the spike proved cheap and correct
— Tier A — and explicitly punts Tier B.

## Design

### 1. `fetch_youtube_channel_videos()` — new function, `knowledge_pipeline.rs`

Same file as `fetch_youtube_content` (t-2950). Signature:

```rust
pub fn fetch_youtube_channel_videos(
    channel_url: &str,
    tab: ChannelTab,           // Videos | Shorts — caller picks explicitly, never inferred
    selection: ChannelSelection,
) -> Result<Vec<String>>       // video URLs, in channel order
```

```rust
pub enum ChannelTab { Videos, Shorts }

pub enum ChannelSelection {
    Range { start: Option<u32>, end: Option<u32> },   // --playlist-start/-end
    Items(Vec<u32>),                                   // --playlist-items "3,7,10"
    MaxDuration(u32),                                  // --match-filter "duration<N"  (Videos tab only — Shorts has no flat duration field)
}
```

Shells out once: `yt-dlp --flat-playlist --skip-download [range/items/match-filter flags] --print "%(id)s" <channel_url>/<tab>`, same subprocess discipline as `fetch_youtube_content` (never acquires `lock_pipeline()`, subject to the same lock-discipline tripwire gap noted in Phase 1's spec §Tests). Output is one video ID per line; map to full `https://www.youtube.com/watch?v=<id>` URLs.

`ChannelSelection::MaxDuration` on `tab: Shorts` is a **caller error** — the spike confirmed `duration` is unset for Shorts-tab flat entries — return `Err` immediately rather than silently returning an unfiltered list.

### 2. Queueing — reuse the existing `link` tag, no new storage mechanism

`fetch_youtube_channel_videos()` returns URLs; the caller (a new `brana knowledge channel-backfill <channel_url> --tab videos --max N` CLI command, or equivalent) queues each one as a `link`-tagged backlog task exactly the way any other link enters the queue today. **No new fetch/dedupe/store code** — every queued URL drains through Phase 1's existing `fetch_youtube_content` → `dedupe_vtt_cues` → `process_one_url` Store-arm path unchanged. This is the entire point of building Tier A after Phase 1: a channel is "many single-video fetches," nothing more.

### 3. What Tier A does NOT do

- No date-range or tag/category selection (ADR-070 amendment §Tier B — deferred, undecided).
- No pacing changes to `run_with_youtube_backoff` — queuing N videos from one channel-backfill call means N separate `drain-links` youtube-job cycles will pull them over time, already rate-limited by the existing per-fetch 429 backoff. A large `--max N` on a popular channel is a user footgun (queues a lot of work at once), not a code gap — worth a CLI-level sanity default (e.g. cap `--max` at 50 unless overridden), not a pipeline redesign.
- No `brana feed` RSS wiring (t-2995 — independent, parallel task, not blocked on this).

## What does NOT change

- `fetch_youtube_content`, `dedupe_vtt_cues`, `determine_youtube_caption_source`, `process_one_url`'s Store arm, `run_with_youtube_backoff`, the youtube scheduler job — all Phase 1 (t-2950/t-2956), untouched.
- `classify_platform` — untouched; a channel-backfill-queued video URL is a normal `youtube.com/watch?v=...` URL, classified exactly like any other.

## Tests (TDD, key cases for DECOMPOSE)

- `fetch_youtube_channel_videos` — subprocess wrapper tested against a recorded/fixture `yt-dlp --flat-playlist` invocation, not live network (same discipline as `fetch_youtube_content`'s tests).
- `ChannelSelection::Range`/`Items`/`MaxDuration` each produce the correct argv (position range vs. explicit items vs. match-filter flag) — pure argv-construction tests, no subprocess.
- `MaxDuration` on `tab: Shorts` returns `Err` immediately, no subprocess call made (assert via a test double that fails the test if the subprocess mock is invoked).
- Empty-channel / zero-results fixture returns `Ok(vec![])`, not an error.
- Video-ID-to-URL mapping is a pure function, unit tested independently of the subprocess call.

## Out of scope

- **Tier B** (date-range, tags/categories selection) — ADR-070 amendment explicitly defers this; needs its own design pass on full-metadata fetch cost and backoff-budget sharing before it's buildable.
- **`t-2995`** (`brana feed` → `link` tag wiring for automatic new-upload flow) — independent, parallel task, not blocked on Tier A.
- **`t-2970`** (knowledge-vector-sync chunking) — shared infra, tracked separately, applies equally to channel-backfilled videos as to single ones.
- Exact CLI surface (`brana knowledge channel-backfill` vs. some other command shape, exact flag names) — a DECOMPOSE-time implementation decision, not fixed here.
- Default `--max` cap value — DECOMPOSE-time implementation decision (§3 flags this as needed, doesn't fix the number).

## Follow-up implementation tasks

File under `t-2993` (Phase 3 milestone). Suggested breakdown, each independently testable per §Tests above:

1. Tests: `fetch_youtube_channel_videos` argv construction + fixture-based flat-listing parse + `MaxDuration`-on-`Shorts` error case (§Tests) — TDD red, no dependencies beyond this spec.
2. Impl: `fetch_youtube_channel_videos()` + `ChannelTab`/`ChannelSelection` + CLI command wiring into the existing `link`-tagged queue (§1, §2) — depends on #1.
3. Docs: tech doc for channel ingestion Tier A (`docs/architecture/` per the split convention) — depends on #2.

Effort per task: S (each is a focused, independently-testable unit, and #2 reuses Phase 1's fetch/dedupe/store entirely).
Suggested wave selector once filed: `parent:t-2993`.
