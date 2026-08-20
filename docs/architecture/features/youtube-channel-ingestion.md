# YouTube channel ingestion — Phase 3, Tier A (t-2993)

> Feature spec for [ADR-070](../decisions/ADR-070-knowledge-process-url-headless-fetch.md)
> §Amendment (2026-08-19, t-2994) — channel-ingest selection surface. Builds on
> [Phase 1](youtube-knowledge-extraction.md) (single video/shorts transcript
> extraction) — reuses its fetch/dedupe/store path unchanged. Source spike:
> t-2994 (live-probed against a real channel, findings recorded in the ADR
> amendment).

Status: **shipped (implementation).** `t-2996` (this spec) → `t-2997` (tests)
→ `t-2999` (implementation + CLI) are complete. `t-2998` (tech doc) is the
one remaining follow-up task under `t-2993`.

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

## Assumptions

- **t-2997 (tests):** the tests exercise a `fetch_youtube_channel_videos_with_runner(channel_url, tab, selection, run: impl FnOnce(&[String]) -> Result<String, String>)` seam rather than calling `fetch_youtube_channel_videos` directly — mirrors `run_with_youtube_backoff`'s injected-closure pattern already used in this file (t-2955/t-2956) so the "fixture invocation, not live network" and "test double that fails if invoked" requirements (§Tests) are satisfiable without a process-mocking crate. `fetch_youtube_channel_videos` itself stays a thin wrapper that supplies the real `yt-dlp` subprocess call as `run` — needs confirmation at t-2999 that this doesn't conflict with the CLI wiring shape.
- **Argv contract (pure, asserted by tests, binding on t-2999's implementation):** `Range{start,end}` → `--playlist-start N` / `--playlist-end N` (either/both, omitted flag when `None`); `Items(v)` → `--playlist-items "a,b,c"` (comma-joined, no spaces); `MaxDuration(n)` on `Videos` → `--match-filter "duration<n"`; `MaxDuration` on `Shorts` → `Err` before any argv is returned.
- **t-2999 (implementation) — CLI surface:** `brana knowledge channel-backfill <channel_url> --tab videos|shorts --max N --dry-run`. `--max` (default 50 — this *is* §3's sanity cap; a caller who wants more overrides the flag explicitly) maps directly to `ChannelSelection::Range { start: None, end: Some(max) }` — the CLI exposes only this one selection shape; `Items`/`MaxDuration` exist as library-level `ChannelSelection` variants (exercised by t-2997's tests) but have no CLI flag yet, since the spec left the exact surface open and Range-by-count covers the "backfill the last N videos" use case this task was scoped for. Each returned URL is queued via `brana backlog add --json {subject, type:"task", tags:["link","channel-backfill"], context:"URL: {url}"}`, shelled out per video — mirrors the *shellout shape* of `feed.rs`'s existing `"task"` action (`Command::new("brana").args(["backlog","add",...])`), the only other in-repo precedent for creating a backlog task from Rust CLI code this way. **Correction (Challenger panel, t-2999):** `feed.rs` is not actually a working `link`-tagged-task precedent — it tags `["feed", &feed.name]`, never `"link"`, so tasks it creates are invisible to `cmd_drain_links`'s `tag:"link"` filter and have never actually drained; that mismatch is pre-existing and out of scope for t-2999 (tracked separately as t-2995's "brana feed → link tag wiring", already called out in this spec's §3 as independent/not-blocked-on-this). This diff's own `build_channel_link_task_json` gets the tag right (`"link"`, verified against the real `extract_capture_url` parser by an inline test) — only the shellout *mechanism* is shared with feed.rs, not its tag correctness. The extra `"channel-backfill"` tag is bookkeeping only; `drain-links`' candidate filter and platform split key on `tag:"link"` and URL substring, unaffected by it. **Needs confirmation:** whether `Items`/`MaxDuration` should get CLI flags in a follow-up, and whether the `"channel-backfill"` tag is wanted for anything beyond bookkeeping.

## Follow-up implementation tasks

File under `t-2993` (Phase 3 milestone). Suggested breakdown, each independently testable per §Tests above:

1. Tests: `fetch_youtube_channel_videos` argv construction + fixture-based flat-listing parse + `MaxDuration`-on-`Shorts` error case (§Tests) — TDD red, no dependencies beyond this spec.
2. Impl: `fetch_youtube_channel_videos()` + `ChannelTab`/`ChannelSelection` + CLI command wiring into the existing `link`-tagged queue (§1, §2) — depends on #1.
3. Docs: tech doc for channel ingestion Tier A (`docs/architecture/` per the split convention) — depends on #2.

Effort per task: S (each is a focused, independently-testable unit, and #2 reuses Phase 1's fetch/dedupe/store entirely).
Suggested wave selector once filed: `parent:t-2993`.

## Changelog

- 2026-08-20: `fetch_youtube_channel_videos()` + `brana knowledge channel-backfill` CLI implemented and shipped (t-2999). Draining a channel-backfilled URL today falls through to the generic-scrape path, not caption extraction, until `fetch_youtube_content`/`fetch_url_content`'s youtube case ships (t-2950, separate, in-progress) — tracked in t-2950's context.
