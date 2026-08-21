# YouTube channel backfill — Tier A tech doc (t-2998)

> Tech doc for the shipped capability designed in
> [youtube-channel-ingestion.md](youtube-channel-ingestion.md) (the spec —
> problem framing, design rationale, argv contract, assumptions) and built in
> `t-2999`. This doc describes what exists today as a reference, not the
> design process; see the spec for *why*.

Status: **shipped.** `t-2999` (implementation + CLI) is complete and merged.
Tasks: `t-2993` (parent/decomposition) → `t-2996` (spec) → `t-2997` (tests) →
`t-2999` (impl) → `t-2998` (this doc).

## What this is

`brana knowledge channel-backfill` enumerates a YouTube channel tab's videos
via `yt-dlp --flat-playlist` and queues each resulting URL as a
`link`-tagged backlog task — draining through the existing `drain-links`
path with **no changes** to the fetch/dedupe/store pipeline built for single
videos in [Phase 1](youtube-knowledge-extraction.md). A channel is "many
single-video fetches enumerated in bulk," nothing more.

## CLI command

```
brana knowledge channel-backfill <channel_url> [--tab videos|shorts] [--max N] [--dry-run]
```

| Flag | Default | Behavior |
|---|---|---|
| `channel_url` (positional, required) | — | e.g. `https://www.youtube.com/@example` |
| `--tab` | `videos` | `videos` or `shorts`. Any other value errors, naming the bad value in the message. |
| `--max` | `50` | Caps how many videos are queued this run. Maps to `ChannelSelection::Range { start: None, end: Some(max) }` — "first N videos in channel order," not date-bounded. This default *is* the sanity cap the spec's §3 called for; pass a larger value explicitly to override. |
| `--dry-run` | off | Prints what would be queued; writes nothing. |

Implementation: `cmd_channel_backfill()` in
`system/cli/rust/crates/brana-cli/src/commands/knowledge.rs`; arg definition
`KnowledgeCmd::ChannelBackfill` in
`system/cli/rust/crates/brana-cli/src/cli.rs`.

Each returned video URL is queued individually via a shelled-out
`brana backlog add --json`:

```json
{
  "subject": "[channel-backfill] <channel_url> — <video_url>",
  "type": "task",
  "tags": ["link", "channel-backfill"],
  "context": "URL: <video_url>"
}
```

`tags: ["link", ...]` is load-bearing — it's what makes the task visible to
`drain-links`'s candidate filter (`extract_capture_url` parses the `context`
field's `"URL: {url}"` marker back out on the drain side). `"channel-backfill"`
is bookkeeping only. A `brana backlog add` failure for one URL is logged and
skipped, not fatal to the run — the queued count printed at the end reflects
only URLs actually written. Next step after queuing:
`brana knowledge drain-links --platform youtube`.

No user guide beyond `brana knowledge channel-backfill --help` — the command
surface is small enough that the flag table above and the CLI's own help
text cover it.

## Tier A selection surface (library level)

```rust
pub fn fetch_youtube_channel_videos(
    channel_url: &str,
    tab: ChannelTab,
    selection: ChannelSelection,
) -> Result<Vec<String>>
```

`system/cli/rust/crates/brana-core/src/knowledge_pipeline.rs`. Shells out
once to:

```
yt-dlp --flat-playlist --skip-download [selection flags] --print "%(id)s" <channel_url>/<tab>
```

— never acquires `lock_pipeline()`, same subprocess discipline as
`fetch_youtube_content` (Phase 1).

`ChannelSelection` has three variants. Argv construction
(`build_channel_selection_args`) is pure and covers all three, but only one
is reachable from the CLI today:

| Variant | Maps to | CLI-reachable? |
|---|---|---|
| `Range { start, end }` | `--playlist-start N` / `--playlist-end N` (either/both flag omitted when `None`) | Yes — the only shape `--max` produces (`Range { start: None, end: Some(max) }`) |
| `Items(Vec<u32>)` | `--playlist-items "a,b,c"` (comma-joined) | No — library-only, exercised by tests, no CLI flag |
| `MaxDuration(u32)` | `--match-filter "duration<N"` — **`Videos` tab only** | No — library-only, exercised by tests, no CLI flag |

`MaxDuration` paired with `tab: Shorts` returns `Err` immediately, before any
subprocess call — the `t-2994` spike confirmed `yt-dlp`'s flat `Shorts`-tab
listing entries have no `duration` field, so the combination can never be
evaluated meaningfully.

Whether `Items`/`MaxDuration` get CLI flags is an open follow-up, not
resolved by this doc (see the spec's Assumptions section).

## Tier B boundary — explicitly deferred

Tier B (date-range and tag/category channel selection) is **not
implemented and not designed** beyond being named in ADR-070's amendment.
This is a deliberate boundary, not an oversight: `yt-dlp --flat-playlist`'s
cheap listing mode carries no per-video date or tag data — evaluating
either would require a second, per-video full-metadata fetch
(`yt-dlp --dump-json` per video), which changes the cost and
rate-limit-backoff-budget shape of the whole operation from "one shellout"
to "one shellout plus N." Tier B's selection criteria need to be driven by
what `yt-dlp`'s real listing/filter capabilities can do cheaply, evaluated
directly against a live channel, not assumed in advance — that's its own
design pass (its own spike + spec), gated on Tier A proving out in
practice, not a follow-up flag bolted onto this command.

Practical consequence today: there is no way to say "back-fill everything
from March" or "only videos tagged X" through `channel-backfill` — only
"the first N videos in channel order" (`--max`, `Range` selection).

## What does NOT change

Reuses Phase 1's fetch/dedupe/store path entirely — `fetch_youtube_content`,
`dedupe_vtt_cues`, `determine_youtube_caption_source`, `process_one_url`'s
Store arm, `run_with_youtube_backoff`, the youtube scheduler job are all
untouched. A channel-backfill-queued URL is a normal
`youtube.com/watch?v=...` URL, classified by `classify_platform` and drained
exactly like any manually captured one.

`fetch_youtube_content`/`fetch_url_content`'s youtube case shipped separately
as `t-2950` (merged 2026-08-21, after this doc's first draft) — a
channel-backfilled URL now gets real caption extraction on drain, the same
as any manually captured youtube URL, not the generic-scrape fallback.

## Out of scope

- **Tier B** (date/tag selection) — see above; needs its own design pass.
- **`Items`/`MaxDuration` CLI flags** — exist at the library level, exercised
  by tests, not yet exposed on the command line.
- **`brana feed` RSS wiring** (`t-2995`) for automatic new-upload ingestion —
  independent, parallel task, not blocked on or by this capability.
- **`t-2970`** (knowledge-vector-sync chunking) — shared infra affecting all
  platforms' stored entries equally, not channel-backfill-specific.

## References

- Spec (design rationale, argv contract, assumptions):
  [youtube-channel-ingestion.md](youtube-channel-ingestion.md)
- Phase 1 (fetch/dedupe/store path reused unchanged):
  [youtube-knowledge-extraction.md](youtube-knowledge-extraction.md)
- [ADR-070](../decisions/ADR-070-knowledge-process-url-headless-fetch.md)
- Implementation commit: `b179ac79` (`feat(knowledge-pipeline): brana
  knowledge channel-backfill CLI (t-2999)`)
