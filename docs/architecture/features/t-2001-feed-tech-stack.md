---
depends_on:
  - docs/architecture/decisions/ADR-055-tech-stack-feed-tracking.md
  - docs/architecture/features/brana-feed-inbox.md
---
# Feature: Intelligence feed — tech-stack tracking, staleness detection, adoption hook

**Date:** 2026-06-12
**Status:** building
**Task:** t-2001

## Problem

The intelligence feed only tracks Claude/AI news, and it fails silently: the anthropic-news scraper stalled on 2026-06-03 and the Fable 5 launch (06-09) never reached the digest — discovered only by manual inspection 9 days later. Meanwhile none of the technologies the portfolio actually builds on (Supabase ×7 projects, Kapso ×5, Next.js/Vercel ×5, Rust) have their changelogs tracked, and there is no mechanism to add a feed when a new technology is adopted.

## Decision Record

> Load-bearing decisions extracted to [ADR-055](../decisions/ADR-055-tech-stack-feed-tracking.md) — staleness detection placement, FeedEntry schema change, source swap, Kapso scraper, adoption-hook placement. This spec references it rather than embedding decisions.

## Constraints

- t-585 frozen architecture: feeds.json is the single registry, `brana feed` (Rust) owns it, non-RSS sources are ~50 LOC scheduler job scripts.
- `FeedEntry` drops unknown JSON fields on rewrite → staleness config must be a real struct field.
- feed-index.sh is bash + jq; staleness check must not break when feed-log.jsonl has malformed lines (existing filter handles this).
- Digest stays a single markdown file reviewed at session start; no new surfaces.

## Scope (v1)

1. **Staleness detection** in `system/scripts/feed-index.sh`: per enabled feed in feeds.json, newest entry age in feed-log.jsonl vs `stale_after_days` (default 14, per-feed override); `⚠ Stale feeds` digest section; zero-entry feeds listed as "no entries yet". Runs even on no-new-entries days (see Design).
1b. **feed-ruflo-index.sh malformed-line filter** — same per-line JSON validation feed-index.sh already has, preventing a watermark-stuck retry loop when a non-Rust writer appends a partial line.
2. **Rust:** `stale_after_days: Option<u32>` on `FeedEntry` (+ `--stale-after-days` flag on `brana feed add`); serde round-trip preserved.
3. **Source swap:** anthropic-news → `https://raw.githubusercontent.com/Olshansk/rss-feeds/main/feeds/feed_anthropic_news.xml` (verified live 2026-06-12), `stale_after_days: 7`.
4. **New feeds** (template + live registry): supabase-changelog (`https://github.com/orgs/supabase/discussions/categories/changelog.atom`, verified), nextjs-releases (`https://github.com/vercel/next.js/releases.atom`, verified), vercel-changelog (`https://vercel.com/atom`), rust-releases (`https://github.com/rust-lang/rust/releases.atom`, verified; stale_after_days 56).
5. **Kapso scraper:** `system/scripts/kapso-changelog-check.sh` — fetch docs.kapso.ai/changelog, diff vs state file, append FeedLogEntry-shaped JSONL (feed: `kapso-changelog`) to feed-log.jsonl; scheduler job at 18:45 daily (before feed-index at 19:00); added to `HIGH_SIGNAL_FEEDS`.
6. **Adoption step** in `/brana:onboard` and `/brana:align`: after stack detection, diff against `brana feed list`, offer `brana feed add` for uncovered technologies. Documented procedure in this doc's tech-doc successor.

## Research

- Portfolio stack survey (2026-06-12): Supabase 7+, Kapso 5+, Vercel 4+, Next.js 5, TypeScript 7+, Google Sheets 6+, Python/FastAPI 3, Cloudflare Workers 3. Kapso = WhatsApp BSP at kapso.ai; changelog page has no RSS; GitHub org `gokapso` has no product releases. Dimension doc exists: brana-knowledge/dimensions/39-kapso-ai-platform.md.
- Feed availability: Supabase/Next.js/Rust GitHub atoms verified returning valid XML with current entries; Olshansk anthropic feed verified — entry `<link>`s point to anthropic.com article URLs (feed-summarize's fetch_and_strip stays compatible); vercel.com/atom verified valid Atom, updated 2026-06-11. Meta WhatsApp: no feed exists, no compliant scrape path.
- taobojlen scraper: builds still run (lastBuildDate 06-09) but no new articles captured since 06-03 — scraper alive but capture broken.

## Assumptions

- **Feed list v1**: chose breadth-ranked top technologies (Supabase, Kapso, Next.js, Vercel, Rust) because they span 4+ projects each; excluded one-project services to limit noise — needs confirmation if user wants more (e.g. Expo, Resend, Cloudflare).
- **Default staleness 14 days**: chose 14 because most selected feeds post at least biweekly; per-feed override handles slow cadences — needs confirmation.
- **Keep feed name `anthropic-news`** on source swap: chose continuity (feed-log history, HIGH_SIGNAL_FEEDS match) over a rename.
- **Adoption step is advisory** (offer, not enforce): chose AskUserQuestion offer in onboard/align because feed noise is a cost; no hook-level enforcement.

## Design

| Piece | File(s) | Approach |
|---|---|---|
| Staleness check | `system/scripts/feed-index.sh` | New unconditional pass (see control flow below): jq over feeds.json (enabled feeds + stale_after_days) ∪ `EXTRA_STALE_FEEDS` script constant (scraper feeds), newest entry per feed over **full** feed-log.jsonl (not watermark-gated), GNU date math; `⚠ Stale feeds` section appended to digest |
| Schema field | `system/cli/rust/crates/brana-cli/src/commands/feed.rs` | `Option<u32>` + serde skip/default; clap flag on `add` |
| Kapso scraper | `system/scripts/kapso-changelog-check.sh` | curl with explicit failure guard + python3 HTML parse (stdlib), state file `~/.claude/scheduler/state/kapso-changelog-scrape.json`, append JSONL |
| Ruflo indexer hardening | `system/scripts/feed-ruflo-index.sh` | Adopt feed-index.sh's per-line malformed-JSON filter before the jq pipe (pre-existing gap, exposed by adding a non-Rust writer) |
| Scheduler | `system/state/scheduler.json` + `system/scheduler/scheduler.template.json` | job `kapso-changelog-check` daily 18:45 |
| Registry | `system/scheduler/feeds.template.json` + live `~/.claude/scheduler/feeds.json` | new entries + URL swap (live via `brana feed` CLI) |
| Adoption step | `system/skills/onboard/SKILL.md`, `system/skills/align/SKILL.md` | "Feed coverage check" step appended after each skill's stack-detection step (both are single-file skills, no phases/) |

### Staleness control flow (feed-index.sh)

The current script exits early when `NEW_COUNT <= 0` — exactly the case where staleness matters most. Restructure: the staleness pass runs **unconditionally**, before the early-exit guard; the guard then only skips digest-body generation. When all feeds are fresh and there are no new entries, behavior is unchanged (no digest written). When a stale feed exists but there are no new entries, a digest containing only the stale-feeds section is written.

- Newest entry per feed: `jq -r '[.published // .polled_at] | ...'` group-by over full feed-log.jsonl (separate read from the watermark-bounded `sed` slice; watermark contract untouched).
- Day delta: `$(( ($(date +%s) - $(date -d "$newest" +%s)) / 86400 ))` — **GNU `date -d`, Linux-only** (scheduler runs under systemd; macOS contributors must not "fix" this to `date -j`).
- Feed universe: enabled feeds from feeds.json (with per-feed `stale_after_days`, default 14) plus `EXTRA_STALE_FEEDS="kapso-changelog:21"` for scraper-fed sources that are not CLI-registered.
- feed-log.jsonl is append-only and unbounded; full-file scan is acceptable at current scale (single user, <50K lines/year). **Known limitation v1** — no truncation mechanism.

### Source swap procedure (anthropic-news)

Per-feed state (`last_entry_ids`) holds taobojlen entry IDs; the Olshansk feed emits different IDs for the same articles, so a bare URL edit floods the next digest with months-old "new" entries. Canonical swap:

```bash
brana feed remove anthropic-news   # resets state incl. last_entry_ids
brana feed add https://raw.githubusercontent.com/Olshansk/rss-feeds/main/feeds/feed_anthropic_news.xml --name anthropic-news
```

This is the documented procedure for ANY source URL change, not just this one.

### Kapso scraper failure semantics

Fetch failure (DNS, timeout, 5xx) must be distinguishable from "no new content": explicit `curl ... || { echo "[kapso-check] FETCH FAILED"; exit 1; }` guard — state file untouched, nothing appended, error surfaces in scheduler logs (`captureOutput: true`). The staleness flag then catches *persistent* failure within 21 days; transient failures self-heal on the next run. The scraper state file is intentionally `kapso-changelog-scrape.json` (not the CLI's `kapso-changelog.json`) because kapso-changelog is **not** a feeds.json-registered feed — `brana feed status` will not show it; this is documented, not accidental.

### Build/deploy ordering

The Rust binary must be rebuilt and deployed (`cargo build --release` + install) **before** `stale_after_days` lands in feeds.template.json or the live config — an old binary's `brana feed add/remove` rewrite silently drops the field from every entry. jq consumers pass unknown fields through and need no change.

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
- [ ] **Existing docs** — `docs/architecture/features/brana-feed-inbox.md` (pointer to [ADR-055](../decisions/ADR-055-tech-stack-feed-tracking.md)), `docs/README.md` if new doc added

## Challenger findings

Reviewed 2026-06-12 (adversarial agent, verdict: **proceed with changes** — all incorporated):

1. **BLOCKER — staleness control flow**: feed-index.sh's `NEW_COUNT <= 0` early-exit would skip the staleness check exactly when it matters; staleness pass now specified as unconditional, GNU `date -d` idiom named. → Design §Staleness control flow.
2. **BLOCKER — full-file scan vs watermark**: staleness scan is a separate non-watermark-gated read; feed-log growth documented as known v1 limitation. → Design.
3. **BLOCKER — source-swap re-emission flood**: `last_entry_ids` divergence between scrapers floods the digest on bare URL edit; remove-then-re-add is now the canonical swap procedure. → Design §Source swap procedure.
4. **MAJOR — scraper failure vs staleness ambiguity**: explicit curl failure guard distinguishes fetch failure (scheduler log) from content staleness (digest flag). → Design §Kapso scraper failure semantics.
5. **MAJOR — scraper state file naming**: divergence from CLI convention is intentional and documented (kapso-changelog is not CLI-registered). → Design.
6. **MAJOR — deploy ordering**: binary rebuild must precede config field rollout or `brana feed add/remove` drops the field. → Design §Build/deploy ordering; DECOMPOSE must order subtasks accordingly.
7. **MAJOR — feed-ruflo-index.sh malformed-line gap**: pre-existing; pulled into scope (1b) with test coverage.
8. **MINOR — skill phase files unnamed**: both skills are single-file (`SKILL.md`); named in Design.
9. **MINOR — vercel.com/atom unverified**: now verified (valid Atom, 2026-06-11 entries).
10. **MINOR — HIGH_SIGNAL_FEEDS is a script constant**: adding a high-signal feed requires both a registry entry and a feed-index.sh edit — documented inconsistency, acceptable v1.
11. **MINOR — Olshansk link compatibility with feed-summarize**: verified — entry links are anthropic.com article URLs.
12. **NOTE — ADR status**: flipped to Accepted (ADR-055; also renumbered from 054 after a parallel-session collision).
