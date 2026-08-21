# YouTube knowledge extraction — Phase 1 (t-2946)

> Feature spec for [ADR-070](../decisions/ADR-070-knowledge-process-url-headless-fetch.md)
> §Amendment (2026-08-17, t-2945) — the fourth (`youtube`) platform tier. Source
> idea: [docs/ideas/youtube-knowledge-extraction.md](../../ideas/youtube-knowledge-extraction.md)
> (challenged twice: `/brana:challenge` against the idea doc, then the build-gate
> Challenger against this ADR — see that doc's §Challenge findings and ADR-070's
> §Amendment for what each pass corrected).

Status: **shipped** (t-2950, 2026-08-21) — the youtube fetch tier described
below is implemented and merged: `classify_platform()` has a youtube case,
`fetch_youtube_content()` shells out to yt-dlp per §Fix below, and
`process_one_url`'s Store arm bypasses `extract_insight` for youtube. Tech
doc covering usage is tracked separately as t-2953 (pending).

## Changelog
- 2026-08-21: youtube fetch tier implemented and merged (t-2950).

## Problem

`brana knowledge drain-links` treats every YouTube URL as platform `"other"`
— `classify_platform()` (`brana-core/src/knowledge_pipeline.rs:619`) has no
YouTube case, so `fetch_url_content()` falls through to the Tier-1 `ureq` GET
+ HTML-strip, which returns the SPA shell (title, meta tags, no captions) for
a `youtube.com/watch` page. Confirmed live: `t-1349` (personal repo) drained
a real video URL and stored the shell as "knowledge." This spec covers the
mechanical pipeline: a fourth fetch tier that pulls real captions via
`yt-dlp` and stores them through the pipeline's existing storage mechanism.

## Design

### 1. `classify_platform()` — add the `youtube` case

`brana-core/src/knowledge_pipeline.rs:619`. Add one branch, same shape as
the existing four:

```rust
} else if url.contains("youtube.com") || url.contains("youtu.be") {
    "youtube"
```

Covers `youtube.com/watch?v=...`, `youtube.com/shorts/...`, and `youtu.be/...`
short links — all contain one of the two matched substrings. No change to
the function's `&'static str` return type or existing branches. Update the
doc comment's platform list (`"linkedin"`, `"github"`, `"substack"`,
`"arxiv"`, `"other"` → add `"youtube"`).

**Other `classify_platform` call sites, audited for safety, not silently
ignored.** Three call sites besides `fetch_url_content` (`knowledge_pipeline.rs:660`)
also receive the new `"youtube"` return value once this lands:
`knowledge_pipeline.rs:1693` and `knowledge.rs:1094`/`:1172`, all inside the
older tier1/2/3 auto-pipeline (`UrlEntry.platform` tagging + dedup/scoring),
the pipeline t-1144/ADR-070 explicitly declines to wire YouTube fetch into.
Safe today for a specific, checkable reason, not by assumption: the
scheduler job that drives that pipeline (`"brana knowledge process --tier1
&& brana knowledge process --tier2"`, `scheduler.template.json:126-135`) is
`"enabled": false`. If that job is ever enabled, YouTube URLs start flowing
through tier1/2/3 tagging/scoring with no fetch behind them — worth a
tripwire (a test asserting the job stays disabled, or a one-line comment at
the job entry) if this spec ships before that pipeline does. Not built
here; flagging so it isn't rediscovered as a surprise.

`canonicalize_url`/`TRACKING_PARAMS` (`knowledge_pipeline.rs:1442-1471`) is
already YouTube-aware (strips `?v=`/`si=` correctly, `v=` explicitly
preserved as load-bearing per the code's own comment, per its existing
test) — no change needed there. Independently re-verified against the live
source while writing this spec, not carried forward from ADR-070's text —
the ADR amendment itself doesn't mention either symbol.

### 2. `fetch_url_content()` — new youtube branch

`brana-core/src/knowledge_pipeline.rs:655`. Add a fourth arm alongside the
existing `platform == "linkedin"` special case:

```rust
if platform == "linkedin" {
    return Ok(fetch_linkedin_content(url)?.map(|text| FetchedContent { text, platform }));
}
if platform == "youtube" {
    return Ok(fetch_youtube_content(url)?.map(|text| FetchedContent { text, platform }));
}
let text = fetch_public_url(url)?;
```

`fetch_youtube_content(url: &str) -> Result<Option<String>>` is new, in the
same file (or a new `youtube.rs` submodule if it grows — sizing judgment for
implementation, not this spec). Contract:

- Shell out to `yt-dlp`, never a Rust YouTube client library — no new
  dependency, one subprocess call, same shape as the existing subprocess
  patterns in this file (LinkedIn MCP client, `call_gemini_json`).
- Command (exact, per ADR-070 §Amendment, corrected twice through Challenger
  review):
  ```
  yt-dlp --skip-download --write-sub --write-auto-sub --sub-langs "en" \
    --sub-format vtt --socket-timeout 30 -- "<url>"
  ```
  - `--write-sub` + `--write-auto-sub` together: prefer the human-authored
    track when one exists, fall back to auto-generated otherwise. (A
    Challenger pass caught that an earlier draft requested only
    `--write-auto-sub` while separately promising a `manual` result — that
    combination can never produce one.)
  - `--sub-langs "en"` — single primary-language caption only for Phase 1.
    The multi-language `en.*,es.*` form from the original brainstorm's live
    test is what hit `HTTP 429` on its third request; it does not ship.
  - `--socket-timeout 30` — no default socket timeout otherwise
    (`--retries` defaults to 10). Wrap the whole subprocess with an outer
    kill-timeout of ~60s (generous against the 2–6s typical case measured
    live 2026-08-17 on a real video; bounds the pathological hang the
    default leaves open).
  - `--` before the URL — **required, not optional.** A `link`-tagged
    task's URL is attacker-influenced input (captured via Telegram); without
    `--`, a URL string starting with `-` is parsed as a `yt-dlp` flag
    (`yt-dlp` has `--exec <cmd>`). Same "decoded target is untrusted" class
    as the existing LinkedIn `/safety/go/` unwrap (ADR-070 §Amendment
    2026-08-01).
- **Distinguishing manual vs. auto-generated** (needed for §5's
  `caption_source` tag): use `yt-dlp --dump-json`'s `requested_subtitles`
  vs. `automatic_captions` fields, not filename parsing — implementation
  detail, decide the exact extraction call during DECOMPOSE.
- **No-captions contract**: `yt-dlp` exiting 0 with zero subtitle files
  written is a distinct, expected outcome, not an error. Return `Ok(None)`
  for it — exactly the same shape as a LinkedIn "post not in feed" miss.
  `process_one_url` already treats `Ok(None)` as "leave pending, never
  `Completed`" (`should_complete_link`/`is_cancellable`); no change needed
  there. This is the same failure shape as the original `t-1349` bug (fetch
  "succeeds," content absent, task marked complete) reproduced one layer
  deeper if unhandled — needs an explicit fixture test, not just the
  populated-fixture happy path.
- **VTT cleanup**: raw VTT has word-level cue duplication (auto-caption
  artifact — each line repeats with incremental word reveals). A dedupe
  pass (new pure function, e.g. `dedupe_vtt_cues(&str) -> String`) runs
  before the text is returned — never store raw VTT as the value. Pure and
  unit-testable without any subprocess.
- **Never acquires `lock_pipeline()`** — `fetch_url_content` and everything
  it calls must stay lock-free (ADR-070 §Lock discipline; the youtube
  subprocess call and its retry/backoff wrapper are no exception).

### 3. `process_one_url` — Store arm gains a platform branch

`brana-cli/src/commands/knowledge.rs:384-416`. Today, every tier's `Store`
outcome runs through `kp::extract_insight(&content.text, content.platform)`
(an LLM-summarization fallback: agy → `claude -p` → 2000-char truncated raw)
and stores `insight.summary` — never the raw fetched text. **This is the one
piece of Phase 1 that touches existing shared control flow, not just adds a
parallel branch** — the ADR-070 amendment's storage section originally
claimed this path was "unchanged" for youtube; that claim was false and was
corrected via the build-gate Challenger review. Summarizing a full
transcript into a short blurb would reproduce `t-1349`'s bug one layer
deeper (a short summary of a 2h26m video's 152,208-character transcript is
only marginally less shallow than an HTML shell) and would strand Phase 2's
raw-transcript dependency before it starts.

**The youtube branch skips `extract_insight` and stores `content.text`
directly:**

```rust
ProcessUrlOutcome::Store => {
    let content = fetched.expect("Store outcome is only reachable with fetched content");
    if content.platform == "youtube" {
        let tags = [content.platform, "transcript", caption_source_str];
        ruflo_memory_store(&key, &content.text, PROCESS_URL_NAMESPACE, &tags)?;
    } else {
        let insight = kp::extract_insight(&content.text, content.platform);
        let tags = [content.platform, insight.topic.as_str()];
        ruflo_memory_store(&key, &insight.summary, PROCESS_URL_NAMESPACE, &tags)?;
    }
    println!("Stored: {key}");
}
```

- `tags` for youtube is a fixed 3-element array: `[platform, "transcript",
  caption_source]`, where `caption_source` is literally `"manual"` or
  `"auto"` (no LLM-derived `topic` — there is no `insight.topic` when
  `extract_insight` is skipped; `"transcript"` is the fixed content-type
  marker in its place). `caption_source` needs to flow from
  `fetch_youtube_content`'s result through `FetchedContent` or a sibling
  return value — exact plumbing is an implementation decision for
  DECOMPOSE, not fixed here.
- Every other tier's call site and summarization behavior is **unchanged**.
- **Resolves the token-cost second-order effect** the idea doc flags: since
  the youtube branch never calls `extract_insight`, Phase 1 incurs no
  per-video LLM summarization cost. The idea doc's own measured ~38K
  tokens/video risk stays genuinely Phase 2's problem (concepts/entities
  extraction reading the stored transcript), not a cost already silently
  paid in Phase 1.

### 4. Storage shape — flat key, no directory bundle

Storage flows through the pipeline's **existing** `ruflo_memory_store(key,
value, PROCESS_URL_NAMESPACE, tags)` call — same `knowledge:url:<slug>` flat
key every other tier uses, no new storage function, no schema change. The
idea doc's original `raw/`+`sources/`+`concepts/`+`entities/` directory
bundle is **explicitly not Phase 1**: it cannot be written through
`ruflo_memory_store`'s flat-value call at all (a directory isn't a string
value) — writing one would leave the idempotency key unset, so every
scheduler cycle would re-fetch every YouTube URL forever, invisible to
`brana recall`'s knowledge-namespace query. That architecture is Phase 2
(`t-2943`), itself gated on `t-2937` (OKF adoption, a separate brana-wide
decision this spec does not make).

### 5. Batch isolation — YouTube gets its own scheduler job

`select_drain_batch()` (`brana-cli/src/commands/knowledge.rs:166`) stays a
bare `.take(cap)` — no code change, no per-platform sub-cap accounting.
Instead:

- `cmd_drain_links`'s candidate filter (currently `tag:"link",
  status:"pending"`) gains a platform exclusion for the existing
  `drain-links --cap N` job: `classify_platform(url) != "youtube"`.
  LinkedIn/GitHub/Substack/arxiv/other are unaffected.
- A new `--platform <name>` flag on `drain-links` (or an equivalent CLI
  surface — decide exact shape in DECOMPOSE) makes the candidate filter
  exactly `classify_platform(url) == "youtube"` when passed. This runs as
  its own `scheduler.template.json` entry, own `--cap`, and its own
  backoff/retry unit (inside `fetch_youtube_content`) around `HTTP 429`.
- **Why a separate job, not a sub-cap**: adding per-platform sub-cap
  accounting to `select_drain_batch` is new state-tracking logic that Phase
  3 (channel-crawl, "own scheduler cadence, separate rate-limit budget" —
  already the stated design) would immediately need to replace with a
  fully separate job anyway. `scheduler.template.json` already runs a
  dozen independent one-line `"command"` jobs — YouTube gets its own line.
  A stuck or retrying YouTube fetch can then only starve its own job's
  slots, never LinkedIn/GitHub/Substack's in the same run.
- **Cross-repo detail for whoever adds the job entry**: the existing
  `link-research-extraction` job (`scheduler.template.json:136-144`, where
  `drain-links --cap 10` is defined) runs against
  `project: ~/enter_thebrana/personal`, not `thebrana` — the new
  `--platform youtube` entry needs the same `project` value or it drains
  against the wrong backlog.

### 6. Known limitation: semantic search reaches only a stored transcript's opening content

`knowledge-vector-sync` (`t-2620`, `brana-core/src/vector.rs`) re-embeds
every value written to the `knowledge` namespace through `ruflo`'s
`all-MiniLM-L6-v2` (384-dim, ~256-token max input sequence), with no
chunking anywhere in `vector.rs`. Every existing tier's stored value is an
`extract_insight` summary — always well inside that window. Phase 1's own
decision (§3: store the full transcript, not a summary) is the first write
positioned to exceed it — a 152,208-character transcript is silently
truncated by the embedder to roughly its first ~1,000–1,300 characters
before vectorizing, so semantic (`brana recall`) search on a long video's
entry only matches its opening captions. The rest of the transcript is
real, stored, and reachable by exact-key lookup and Phase 2's raw-transcript
mining — just not by semantic search. `brana recall`'s knowledge-namespace
side has no FTS fallback for this (ADR-058: FTS5 covers `~/.claude/memory/*.md`
only).

**Not fixed in Phase 1.** Chunked or multi-vector embedding is real feature
work inside `vector.rs`/`knowledge-vector-sync` — a shared consumer of four
other platforms' entries too, not youtube-specific. Tracked as `t-2970`.
Phase 1 ships with this documented, not silent.

## What does NOT change

- Tier 1 (public HTTP), Tier 2 (LinkedIn), Tier 3 (GitHub/Substack/arxiv via
  `fetch_public_url`) — no code changes to their fetch paths.
- `extract_insight`'s three-tier LLM-summarization fallback — unchanged,
  used by every tier except youtube.
- `select_drain_batch`'s `.take(cap)` logic — unchanged.
- `ruflo_memory_store`/`ruflo_memory_get` — unchanged, youtube is a new
  caller with the same signature.
- Lock discipline — `fetch_url_content` stays lock-free; no new lock
  acquisition anywhere in this design.

## Tests (TDD, key cases for DECOMPOSE)

- `classify_platform` returns `"youtube"` for `youtube.com/watch`,
  `youtube.com/shorts/...`, and `youtu.be/...` URLs; unaffected for the
  existing four platforms plus `"other"`.
- `fetch_youtube_content` — subprocess wrapper tested against a
  recorded/fixture `yt-dlp` invocation, not live network (same discipline
  as the LinkedIn tier's existing tests).
- **No-captions fixture**: `yt-dlp` exit 0, zero subtitle files written →
  `Ok(None)`, never `Completed`. Not just the populated-fixture happy path.
- `dedupe_vtt_cues` — pure function, unit tested against a fixture VTT with
  known word-level cue duplication.
- `process_one_url`'s youtube branch — stores `content.text` unmodified
  (not `insight.summary`), tags shape is exactly `[platform, "transcript",
  caption_source]`; every other platform's existing tests still pass
  unmodified (regression guard on the shared `Store` arm change).
- Backoff/retry unit — simulated `HTTP 429`, verifies pacing without a live
  network call.
- `test_lock_discipline_source_tripwires` — **known pre-existing gap**,
  flagged during the ADR-070 Challenger review: it scans only
  `brana-cli/src/commands/knowledge.rs` via `include_str!`, so it cannot
  see `fetch_url_content`/`fetch_youtube_content` at all — those live in
  `brana-core`'s `knowledge_pipeline.rs`. Extending the tripwire (or adding
  a companion test in `brana-core`) to cover that file is worth doing
  alongside this work, not deferred indefinitely — call out explicitly in
  DECOMPOSE as its own task, not folded into the fetch-mechanism task.

## Out of scope

- **Phase 2** (`t-2943`): directory-bundle storage (`raw/`+`sources/`+
  `concepts/`+`entities/`), concepts/entities synthesis, timestamp-anchored
  citations. Gated on Phase 1 proving out in practice AND `t-2937`
  resolving first.
- **Phase 3** (`t-2944`): channel-crawl via `yt-dlp --flat-playlist`.
- **`t-2937`** (OKF adoption, brana-wide) — this spec borrows OKF's
  frontmatter conventions nowhere; Phase 1 has no bundle to put frontmatter
  in.
- **`t-2970`** (chunked/multi-vector embedding for `knowledge-vector-sync`)
  — real fix for §6's limitation; shared infra work, not youtube-specific,
  tracked separately.
- **`t-2958`/`t-2959`** (Phase 2 cost/token-usage tracking) — Phase 1
  incurs no LLM summarization cost per §3, so this doesn't block Phase 1;
  it's Phase 2's concern once concept/entity extraction reads the stored
  transcripts.
- Exact CLI shape of the new `--platform` flag (or equivalent) on
  `drain-links` — a DECOMPOSE-time implementation decision, not fixed here.
- Exact plumbing of `caption_source` from fetch result through to the
  `Store` arm's tag array — DECOMPOSE-time implementation decision.

## Follow-up implementation tasks

File under `t-2942` (Phase 1 milestone — subject and description corrected
2026-08-18 to match this spec; previously encoded the pre-correction
`raw/`+`sources/` design). Suggested task breakdown, each independently
testable per §Tests above:

1. `classify_platform` youtube case (§1) — trivial, no dependencies.
2. `fetch_youtube_content` + `dedupe_vtt_cues` + no-captions `Ok(None)`
   contract (§2) — the core fetch mechanism.
3. `process_one_url` Store-arm platform branch (§3) — depends on #2's
   `FetchedContent`/`caption_source` shape.
4. Backoff/retry unit for `HTTP 429` (§2) — can parallel #3.
5. `cmd_drain_links` platform filter + `--platform` flag + new
   `scheduler.template.json` entry, **plus the one-line operational note in
   `docs/architecture/hooks.md` or the scheduler doc that ADR-070's
   Consequences section asks for** (two independent scheduler jobs now
   drain the same `link` tag by disjoint platform filters) — depends on #1.
6. Extend `test_lock_discipline_source_tripwires` to cover
   `knowledge_pipeline.rs` (§Tests) — independent, can run anytime.

Effort per task: S (each is a focused, independently-testable unit).
Suggested wave selector once filed: `parent:t-2942`.

## Assumptions

Implementation decisions this spec explicitly deferred to DECOMPOSE-time
(t-2950), recorded here rather than left implicit:

- **`--dump-json` combined with `--write-sub`/`--write-auto-sub` in the
  SAME `yt-dlp` invocation** — the spec's "distinguish manual vs.
  auto-generated" note said "use `--dump-json`'s fields, not filename
  parsing" without fixing how, given the design's own "one subprocess
  call, not two" constraint. Chose: `yt-dlp` supports printing JSON
  metadata to stdout while ALSO writing the requested subtitle files to
  disk in one call — `requested_subtitles`/`automatic_captions` on that
  JSON determine `caption_source`, the actual `.vtt` file is read
  separately from disk. Needs confirmation: verified against `yt-dlp`'s
  documented flag semantics, not live-tested (no `yt-dlp`/network access
  in this build's sandbox) — same "verified live instead" discipline this
  file already applies to `mcp_call_tool` and the LinkedIn fetch.
- **Fixed `-o "video.%(ext)s"` output template** — makes the caption
  file's path deterministic (`{work_dir}/video.en.vtt`) regardless of the
  video's actual title/id, avoiding a second `yt-dlp --dump-json` parse
  just to locate the file yt-dlp wrote.
- **`caption_source` plumbing**: added `pub caption_source:
  Option<YoutubeCaptionSource>` to `FetchedContent` (`None` for every
  non-youtube platform) — the "sibling return value" option the spec
  left open, chosen over overloading `platform` or a second return type
  from `fetch_url_content`.
- **`fetch_youtube_content`'s own return type** changed from the spec's
  original `Result<Option<String>>` sketch to `Result<Option<(String,
  YoutubeCaptionSource)>>` — nothing depended on the original signature
  (no test called it directly; t-2947 only pinned `resolve_youtube_captions`
  and `dedupe_vtt_cues`'s shapes), so this was a free choice at
  implementation time, not a breaking change.
- **`resolve_store_value` pure-function extraction** in `process_one_url`'s
  Store arm — factors the storage decision (value + tags) out from the
  `extract_insight`/`ruflo_memory_store` I/O so the youtube-bypass branch
  is unit-testable without real agy/`claude -p` subprocess calls, matching
  this file's established "test the decision, not the I/O" pattern
  (`resolve_process_url_outcome`, `candidate_passes_platform_filter`).
- **Tech doc deferred to t-2953**, not written here — t-2950's own
  approved acceptance criteria don't require doc changes, and t-2953
  ("Docs: tech doc for the youtube fetch tier") is the dedicated
  downstream task, gated on this one.
