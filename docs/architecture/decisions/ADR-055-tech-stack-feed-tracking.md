---
status: accepted
date: 2026-06-12
---
# ADR-055: Tech-Stack Changelog Tracking in the Intelligence Feed

**Status:** Accepted
**Date:** 2026-06-12
**Task:** t-2001
**Extends:** the t-585 feed architecture (docs/architecture/features/brana-feed-inbox.md) and ADR-024.

## Context

The intelligence feed (feed-poll → feed-summarize → feed-index → feed-ruflo-index) only tracks Claude/AI news. Two gaps surfaced on 2026-06-12:

1. **Silent staleness.** The `anthropic-news` feed is a third-party scraper (taobojlen/anthropic-rss-feed) that stalled on 2026-06-03 and missed the Fable 5 launch (06-09). Nothing in the pipeline detects a feed that stops producing entries — the digest just quietly omits it.
2. **No tech-stack coverage.** The portfolio runs on Supabase (7+ projects), Kapso (5+), Next.js/Vercel (5), Rust (system CLI) — none of their changelogs are tracked. Kapso has no RSS feed at all (static changelog page at docs.kapso.ai/changelog); Meta WhatsApp Business Platform has none either.

Constraints inherited from t-585 (frozen decision record): feeds.json is the single registry, the Rust CLI (`brana feed`) owns it, each non-RSS source is a ~50 LOC scheduler job script (pattern: cc-changelog-check.sh), pure Rust polling via feed-rs.

`FeedEntry` in `brana-cli/src/commands/feed.rs` is a closed struct — unknown JSON fields are dropped on any `brana feed add/remove` rewrite, so staleness config cannot live in feeds.json as an ad-hoc field.

## Decision

1. **Staleness detection lives in feed-index.sh** (the digest builder), not the Rust poller. Per enabled feed, compute the newest entry date in feed-log.jsonl; if older than the feed's `stale_after_days` (default **14**), append a `⚠ Stale feeds` section to the digest. Feeds with zero log entries are listed as "no entries yet". The digest is the surface the user already reviews — a stall can no longer be silent.
2. **`stale_after_days: Option<u32>` becomes a first-class field on `FeedEntry`** (Rust), `#[serde(skip_serializing_if = "Option::is_none", default)]` — backward compatible with existing feeds.json, survives CLI rewrites. Slow-cadence feeds override it (e.g. rust-releases: 56).
3. **anthropic-news swaps source** to the Olshansk/rss-feeds scraper (`feed_anthropic_news.xml`, Claude-powered, hourly, verified live 2026-06-12). Same feed name — history continuity in feed-log.jsonl. `stale_after_days: 7`. Swap executes as `brana feed remove` + `brana feed add` (never a bare URL edit) — resets `last_entry_ids`, preventing a re-emission flood from the new generator's divergent entry IDs.
4. **Tech-stack feeds register through the existing registry** (no new abstraction): supabase-changelog (GitHub Discussions atom), nextjs-releases (releases.atom), vercel-changelog (vercel.com/atom), rust-releases (releases.atom). Template (`system/scheduler/feeds.template.json`) and live config both updated.
5. **Kapso gets a scraper scheduler job** (`kapso-changelog-check.sh`, pattern: cc-changelog-check.sh) that diffs docs.kapso.ai/changelog and appends `FeedLogEntry`-shaped lines (feed: `kapso-changelog`) to feed-log.jsonl, upstream of feed-index. Joins `HIGH_SIGNAL_FEEDS`.
6. **Adoption mechanism is a skill step, not a new command** (work-preferences: automation through usage). `/brana:onboard` and `/brana:align` gain a "feed coverage check": diff the detected stack against `brana feed list`, offer `brana feed add` for gaps. Documented in the feature tech doc as the canonical procedure.

## Consequences

- A stalled feed is visible within one digest cycle instead of being discovered by accident.
- feeds.json schema grows one optional field; old configs parse unchanged. Rebuilding the CLI binary is required.
- Kapso coverage depends on their changelog page structure — scraper breakage now self-reports via the staleness flag (the two mechanisms compose).
- Digest grows ~4 feeds; low-signal feeds stay title-only (tail -20 cap unchanged).
- New tech adoption only registers a feed when onboard/align runs — manual `brana feed add` remains the fallback between runs.

## Non-Actions

- No Meta WhatsApp changelog scraping (login-walled, ToS risk) — revisit if a third-party feed appears.
- No per-project feed lists or new registry abstraction (t-585 decision stands).
- No one-project-only service feeds in v1 (fal.ai, ElevenLabs, Resend, Tienda Nube, …) — noise outweighs signal; the adoption step can add them case-by-case.
- No staleness alerting outside the digest (no push notifications, no separate report file).
