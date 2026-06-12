---
depends_on:
  - docs/architecture/decisions/ADR-054-tech-stack-feed-tracking.md
  - docs/architecture/features/brana-feed-inbox.md
---
# Feature: Intelligence feed — tech-stack tracking, staleness detection, adoption hook

**Date:** 2026-06-12
**Status:** specifying
**Task:** t-2001

## Problem

The intelligence feed only tracks Claude/AI news, and it fails silently: the anthropic-news scraper stalled on 2026-06-03 and the Fable 5 launch (06-09) never reached the digest — discovered only by manual inspection 9 days later. Meanwhile none of the technologies the portfolio actually builds on (Supabase ×7 projects, Kapso ×5, Next.js/Vercel ×5, Rust) have their changelogs tracked, and there is no mechanism to add a feed when a new technology is adopted.

## Decision Record

> Load-bearing decisions extracted to **ADR-054-tech-stack-feed-tracking.md** — staleness detection placement, FeedEntry schema change, source swap, Kapso scraper, adoption-hook placement. This spec references it rather than embedding decisions.

## Constraints

- t-585 frozen architecture: feeds.json is the single registry, `brana feed` (Rust) owns it, non-RSS sources are ~50 LOC scheduler job scripts.
- `FeedEntry` drops unknown JSON fields on rewrite → staleness config must be a real struct field.
- feed-index.sh is bash + jq; staleness check must not break when feed-log.jsonl has malformed lines (existing filter handles this).
- Digest stays a single markdown file reviewed at session start; no new surfaces.

## Scope (v1)

1. **Staleness detection** in `system/scripts/feed-index.sh`: per enabled feed in feeds.json, newest entry age in feed-log.jsonl vs `stale_after_days` (default 14, per-feed override); `⚠ Stale feeds` digest section; zero-entry feeds listed as "no entries yet".
2. **Rust:** `stale_after_days: Option<u32>` on `FeedEntry` (+ `--stale-after-days` flag on `brana feed add`); serde round-trip preserved.
3. **Source swap:** anthropic-news → `https://raw.githubusercontent.com/Olshansk/rss-feeds/main/feeds/feed_anthropic_news.xml` (verified live 2026-06-12), `stale_after_days: 7`.
4. **New feeds** (template + live registry): supabase-changelog (`https://github.com/orgs/supabase/discussions/categories/changelog.atom`, verified), nextjs-releases (`https://github.com/vercel/next.js/releases.atom`, verified), vercel-changelog (`https://vercel.com/atom`), rust-releases (`https://github.com/rust-lang/rust/releases.atom`, verified; stale_after_days 56).
5. **Kapso scraper:** `system/scripts/kapso-changelog-check.sh` — fetch docs.kapso.ai/changelog, diff vs state file, append FeedLogEntry-shaped JSONL (feed: `kapso-changelog`) to feed-log.jsonl; scheduler job at 18:45 daily (before feed-index at 19:00); added to `HIGH_SIGNAL_FEEDS`.
6. **Adoption step** in `/brana:onboard` and `/brana:align`: after stack detection, diff against `brana feed list`, offer `brana feed add` for uncovered technologies. Documented procedure in this doc's tech-doc successor.

## Research

- Portfolio stack survey (2026-06-12): Supabase 7+, Kapso 5+, Vercel 4+, Next.js 5, TypeScript 7+, Google Sheets 6+, Python/FastAPI 3, Cloudflare Workers 3. Kapso = WhatsApp BSP at kapso.ai; changelog page has no RSS; GitHub org `gokapso` has no product releases. Dimension doc exists: brana-knowledge/dimensions/39-kapso-ai-platform.md.
- Feed availability: Supabase/Next.js/Rust GitHub atoms verified returning valid XML with current entries; Olshansk anthropic feed verified; vercel.com/atom is Vercel's own published link (unverified fetch). Meta WhatsApp: no feed exists, no compliant scrape path.
- taobojlen scraper: builds still run (lastBuildDate 06-09) but no new articles captured since 06-03 — scraper alive but capture broken.

## Assumptions

- **Feed list v1**: chose breadth-ranked top technologies (Supabase, Kapso, Next.js, Vercel, Rust) because they span 4+ projects each; excluded one-project services to limit noise — needs confirmation if user wants more (e.g. Expo, Resend, Cloudflare).
- **Default staleness 14 days**: chose 14 because most selected feeds post at least biweekly; per-feed override handles slow cadences — needs confirmation.
- **Keep feed name `anthropic-news`** on source swap: chose continuity (feed-log history, HIGH_SIGNAL_FEEDS match) over a rename.
- **Adoption step is advisory** (offer, not enforce): chose AskUserQuestion offer in onboard/align because feed noise is a cost; no hook-level enforcement.

## Design

| Piece | File(s) | Approach |
|---|---|---|
| Staleness check | `system/scripts/feed-index.sh` | After digest body: jq over feeds.json (enabled feeds + stale_after_days), jq max published/polled_at per feed over full feed-log.jsonl, date math in bash; emit section only when flags exist |
| Schema field | `system/cli/rust/crates/brana-cli/src/commands/feed.rs` | `Option<u32>` + serde skip/default; clap flag on `add` |
| Kapso scraper | `system/scripts/kapso-changelog-check.sh` | curl + python3 HTML parse (stdlib), state file `~/.claude/scheduler/state/kapso-changelog-scrape.json`, append JSONL |
| Scheduler | `system/state/scheduler.json` + `system/scheduler/scheduler.template.json` | job `kapso-changelog-check` daily 18:45 |
| Registry | `system/scheduler/feeds.template.json` + live `~/.claude/scheduler/feeds.json` | new entries + URL swap (live via `brana feed` CLI / jq) |
| Adoption step | `system/skills/onboard/`, `system/skills/align/` phase files | "Feed coverage check" step post stack-detection |

## Boundaries

| Always | Ask First | Never |
|--------|-----------|-------|
| Flag stale/empty feeds in the digest | Adding feeds beyond the v1 list | Scrape Meta developer docs |
| Preserve feeds.json round-trip | Removing existing feeds | Break existing digest sections / watermark logic |
| Append-only to feed-log.jsonl | — | Edit `~/.claude/` deployed copies directly (template-first, bootstrap/deploy applies) |

## Testing Strategy

- **Unit (bash):** extend `system/hooks/tests/test-feed-index.sh` — stale feed flagged; fresh feed not flagged; per-feed override respected; zero-entry feed reported; no stale section when all fresh. Fixture feeds.json + feed-log.jsonl in temp dir.
- **Unit (Rust):** serde round-trip of `FeedEntry` with and without `stale_after_days`; `brana feed add --stale-after-days` writes the field. `cargo test -p brana-cli`.
- **Integration:** kapso scraper parse test against a saved HTML fixture (no network); `--dry-run` flag prints instead of appending.
- **E2E:** run `feed-index.sh --force` against real log after changes; verify digest renders.
- **Mock policy:** network mocked via fixtures only (scraper test); everything else uses real files in mktemp dirs.

## Documentation Plan

- [ ] **Tech doc** — `docs/architecture/features/t-2001-feed-tech-stack.md` (this file, updated to shipped) + adoption procedure section
- [ ] **User guide** — `docs/guide/features/brana-feed-inbox.md`: staleness section, new feeds table, adoption workflow
- [ ] **Existing docs** — `docs/architecture/features/brana-feed-inbox.md` (pointer to ADR-054), `docs/README.md` if new doc added

## Challenger findings

_(pending challenger review)_
