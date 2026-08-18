---
status: accepted
---
# ADR-070: `brana knowledge process-url` — headless-first fetch architecture

**Status:** Accepted
**Date:** 2026-07-24
**Task:** t-1781

## Context

t-1781 adds a `brana knowledge process-url <url>` command that fetches a URL
(public page or JS-heavy/auth-gated like LinkedIn), extracts an insight, and
stores it to ruflo memory (`namespace=knowledge`). The primary use case is
draining LinkedIn research stubs from the backlog, and the command is
expected to **run nightly, unattended** — no human present.

Three architectural questions had to be resolved before implementation:

1. **Relationship to the existing knowledge pipeline.** `brana-core/src/knowledge_pipeline.rs`
   already has a `UrlEntry.fetched_content: Option<String>` field reserved for
   "browser pre-pass" content, explicitly pointing at t-1144 ("knowledge
   pipeline v2: full LinkedIn content fetch via authenticated strategy").
   t-1144 is gated: "only start after v1 pipeline has run ≥1 full cycle and
   validated that slug+hashtag signal is insufficient." That validation has
   not happened.
2. **Where fetch orchestration can run.** The originally proposed design
   ("try WebFetch, fall back to ruflo browser_open/click/snapshot") uses two
   Claude-Code-session-only tools — WebFetch and the ruflo browser MCP tools
   require an interactive session with Chrome connected. Verified: the ruflo
   CLI (`ruflo-cli.sh`) has no `browser` subcommand, and a headless `claude -p`
   subprocess cannot reach an interactively-authenticated Chrome extension
   (same constraint as headless/cron MCP availability generally). A pure
   Rust CLI binary cannot invoke these tools directly.
3. **How to fetch LinkedIn content unattended.** LinkedIn is auth-gated and
   JS-heavy; a plain HTTP GET (reqwest) cannot retrieve authenticated post
   content.

## Decision

**Scope split from t-1144:** build the fetch+extract mechanism now, as a
reusable `brana-core` function, exposed only via the standalone
`process-url` command. Do **not** auto-wire it into the pipeline's
tier1/2/3 flow — that remains t-1144's gated decision. When t-1144 is
eventually started, it reuses this fetch function to populate
`fetched_content` rather than re-implementing fetch from scratch.

**Fetch architecture, three tiers:**

1. **Public URLs — direct HTTP.** Use `ureq` (already a `brana-core` and
   `brana-cli` workspace dependency, and the project's established
   synchronous-HTTP convention per ADR-024) for a plain GET + HTML-to-text
   extraction. No MCP, no browser, no session, no new dependency.
   Reuse the existing `classify_platform()` (`knowledge_pipeline.rs:614`)
   to route `linkedin.com` URLs to Tier 2 and everything else to Tier 1,
   rather than reimplementing platform detection.
2. **LinkedIn URLs — headless MCP shell-out to `linkedin-scraper-mcp`, fuzzy
   author-feed match (corrected 2026-07-24).** Enumerating every MCP tool
   `linkedin-scraper-mcp` registers (`server.py`'s 4 `register_*_tools`
   calls + `close_session`) found **no tool accepts an arbitrary post URL**
   — every tool takes a structured identifier (company name, job ID,
   username) and builds its own URL internally. There is no
   `get_post_by_url` and no MCP resource/prompt fallback. The closest
   available primitive is `get_person_profile(linkedin_username,
   sections="posts")`, which returns the author's *recent* posts feed as
   raw text. The mechanism is therefore best-effort: parse the URL's
   author + title-signal (already-existing `parse_linkedin_url()`), fetch
   that author's posts feed, and text-match the title-signal against the
   feed to find the target post. A miss (post not in the fetched feed —
   too old, or feed pagination not covered) is a **distinct outcome from a
   fetch failure**: `Ok(None)`, not `Err`. This is materially weaker than
   "fetch this exact post" and should be stated as a known limitation, not
   silently treated as equivalent.
   `linkedin-scraper-mcp` (confirmed installed via `uv tool` — `uv tool list`
   shows `linkedin-scraper-mcp v4.8.2`, symlinked into `~/.local/bin/`) runs
   its own headless Chromium via Playwright, independent of the Chrome
   extension. Auth persists via `--user-data-dir` (cookie storage) established
   by a **one-time interactive** `linkedin-scraper-mcp --login`. Thereafter
   it is usable fully headless (`--status` to verify a live session).
   The Rust CLI shells out to `claude -p --mcp-config <scoped-config>
   --allowedTools mcp__linkedin-scraper__... --print --output-format json`.
   > **Superseded 2026-07-31 (t-2568) — see §Amendment below.** The transport
   > described in the rest of this paragraph is no longer the Tier-2
   > substrate: `brana-core` now speaks JSON-RPC to `linkedin-scraper-mcp`
   > directly. The *mechanism* above (author-feed fetch + fuzzy match, and
   > its `Ok(None)` miss semantics) is unchanged and still current.
   This is **new** arg-building on top of the existing Layer-C infrastructure
   (`resolve_claude_binary`, `build_claude_args`, `call_claude_json` in
   `knowledge_pipeline.rs`) — those functions currently hardcode
   `--print --output-format json` (+ optional `--model`) with no MCP/tool
   support, so `--mcp-config`/`--allowedTools` plumbing and a longer timeout
   (MCP server cold-start adds latency beyond the existing 60s/180s budgets
   calibrated for pure-text calls) are new work, not reuse of
   `call_gemini_json` (that function is the unrelated agy/Gemini text path).
   The scoped `--mcp-config` points at a different MCP server via a file
   containing only the `linkedin-scraper-mcp` entry (not the project's full
   `.mcp.json` — narrows blast radius and startup cost).
3. **Insight extraction.** Shell out to `agy` (existing Layer-C pattern,
   `AGY_CLI_MIN_VERSION` / `AGY_CLI_TIMEOUT_SECS` already defined in this
   crate) to summarize fetched content into a stored insight.

**Storage:** new `ruflo_memory_store()` function in `brana-core/src/ruflo.rs`
(mirrors the existing `ruflo_memory_search_raw`), keyed by slugified URL,
namespace `knowledge`, tagged `[domain, topic]`. Idempotency (skip
already-processed URLs) requires an **exact-match** lookup, not the existing
`ruflo_memory_search_raw` (which is semantic/fuzzy — its own caller,
`check_semantic_dedup`, documents that only near-exact topic duplicates are
caught). A new `ruflo_memory_get(key, namespace)` exact-key lookup is needed
alongside `ruflo_memory_store()`; reusing semantic search for idempotency
risks a false-positive "already stored" skip on an unrelated prior entry,
which would silently omit a URL's task ID from the batch's advisory
cancellation list without ever having fetched its content.

**Lock discipline.** `knowledge.rs`'s five existing pipeline command handlers
all acquire `kp::lock_pipeline()` at their entry point (the file's dominant
local convention), and a `test_lock_discipline_source_tripwires` regression
test already guards a prior reentrant-lock deadlock in this exact lock
(core call graph must never lock). `fetch_url_content()` and the
`process_url` handler are explicitly designed to be reused by a future
t-1144 inside the pipeline's locked `process_core` call graph — so
**`fetch_url_content()` and everything it calls must never call
`lock_pipeline()`**, even though every existing sibling handler in the same
file does. This is a deliberate exception to local convention, not an
oversight, and must be called out in code comments at the new function plus
covered by extending `test_lock_discipline_source_tripwires` (or an
equivalent tripwire) once the function's file location is chosen in
DECOMPOSE.

## Empirical validation (2026-07-24)

The core mechanism was proven live before implementation, not assumed: a
scoped `--mcp-config` pointing only at `linkedin-scraper-mcp` +
`--strict-mcp-config` + `--allowedTools "mcp__linkedin-scraper__close_session"`
successfully connected (`mcp_servers:[{"name":"linkedin-scraper","status":"connected"}]`),
invoked the real tool, and returned real structured JSON
(`{"status":"success","message":"..."}`), parseable via the existing
`parse_claude_stdout`/`extract_result_from_envelope` NDJSON-envelope
handling already in `knowledge_pipeline.rs` — no new parsing logic needed
for the envelope itself, only for the tool-specific response shape.
**Cost observed: $0.40 / ~9s for one trivial `close_session` call** — a
real per-invocation cost that scales with a nightly batch size; a
`get_person_profile(sections="posts")` call will cost more (larger
response, more agentic turns). Factor this into the nightly-cron cost
model, not just latency.

## Amendment (2026-07-31, t-2568): Tier-2 transport is a direct MCP client

**What changes:** the Tier-2 *transport* only. `brana-core` speaks JSON-RPC
over stdio to `linkedin-scraper-mcp` itself, instead of shelling out to
`claude -p` as an MCP client. The Tier-2 *mechanism* — `get_person_profile
(sections="posts")` + fuzzy title-signal match against the author's feed,
with a miss as `Ok(None)` — is untouched, as is Tier 1 and Tier 3.

**Why the original choice was made, and why it no longer holds.** The
paragraph above justifies `claude -p` as *"new arg-building on top of the
existing Layer-C infrastructure"* — it was chosen for scaffolding reuse. A
direct client was never evaluated against it. That reuse argument was the
whole case, and it does not survive contact with what the transport costs:
the model was never doing any work on this path. `find_matching_post()`
does the matching in Rust. `claude -p` was pure transport.

**Three defects traced to that transport (t-2568):**

1. **Pipe-buffer deadlock.** The call emits ~147 KB into a ~64 KiB pipe
   while the parent polled `try_wait()` without reading — the child could
   never exit, so every fetch failed at *exactly* 240s with zero output.
   Fixed in 0cf60779 (`run_with_timeout`), now removed along with the
   transport it served.
2. **The CC sandbox blocks the path.** Sandboxed runs reproduce a 240s
   timeout even with the deadlock fixed. Environmental, not a code bug, but
   it confounded two verification runs. **Any live verification of Tier 2
   must run unsandboxed.**
3. **The MCP result exceeds the inline token limit.** With 1 and 2 cleared
   the fetch *succeeds* (~100 posts, ~58 KB) but `claude` cannot return it
   inline — it writes a file and answers in prose, so the caller sees an
   unparseable shape. Not fixable by re-budgeting: it is a property of
   routing 50 KB of data through a model's context.

A direct client eliminates all three structurally rather than working
around the third: responses are read as they arrive (no deadlock class),
no context window is involved (no token limit), and no `claude` subprocess
exists to be sandboxed.

**Measured 2026-07-31, unsandboxed, same author (`adrien-taravant`):**

| | via `claude -p` | direct JSON-RPC |
|---|---|---|
| `initialize` | — | 1.0s |
| `get_person_profile(sections="posts")` | 98s (137s in one verification run) | **28.8s** |
| Response | prose describing the data | `result.structuredContent.sections.posts`, a typed string (~47–50 KB; the feed is live, so the exact size varies between runs) |
| Shutdown | child kill; grandchild Chromium may outlive it | rc=0, 0.4s after stdin close |

**Cost.** §Empirical validation above records **$0.40 for one trivial
`close_session` call** and notes a `posts` call costs more. On a 4-hourly
timer over ~26 links that is a recurring per-invocation cost for transport
alone. The direct client has none. (Whether that figure is billed or merely
reported under a Code subscription was not established — it is a reason to
prefer the direct client, not a measured saving.)

**Consequences of this amendment:**

- `call_claude_json_with_mcp()` and `run_with_timeout()` had exactly one
  production call site each and are removed. `call_claude_json()` (the
  text-only path used by insight extraction) is a different function and is
  **not** affected.
- `LINKEDIN_MCP_TIMEOUT_SECS` is re-budgeted against a measured ~30s rather
  than a guess at model-plus-cold-start latency.
- **Untrusted input no longer reaches a model holding tools.** The rejected
  alternative — keeping `claude -p` and having it write the payload to a
  caller-supplied path — required granting `Write` to a model whose input is
  attacker-authorable LinkedIn post text. Recorded here because the security
  property is a reason for the decision, not a side effect of it.
- The one-time interactive `linkedin-scraper-mcp --login` setup, the
  `--status` session probe, and the fail-loud-on-expired-session rule are
  all unchanged.

## Amendment (2026-08-01, t-2589): public JSON-LD/og extract is the primary LinkedIn tier

**What changes:** the LinkedIn tier *ordering*. Every LinkedIn post URL
serves its full body unauthenticated, above the authwall, in
`<script type="application/ld+json">` → `articleBody`, with a second copy in
`og:description` — LinkedIn must serve link previews. The primary LinkedIn
path becomes one plain HTTP GET + metadata extract; the authenticated
feed-scrape (t-2568's direct MCP client) is demoted to fallback, invoked
only when the public extract is below a usability threshold (~200 chars).
`classify_platform` routing, the `Ok(None)`-vs-`Err` contract, and the
tier-2 mechanism itself are unchanged.

**Why ADR-070 missed this.** The original investigation asked "which MCP
tool accepts an arbitrary post URL?", correctly found none, and built an
authenticated scraper around `get_person_profile`. It never asked whether
the post URL itself serves the content. Same error shape as t-2568
(`claude -p` assumed necessary as MCP transport when the server spoke plain
JSON-RPC): the expensive mechanism was built without probing the cheap one.

**Measured 2026-08-01 (spike over all 15 then-pending link tasks, curl +
regex, no dependencies):**

| | tier-2 authenticated scrape | public JSON-LD/og extract |
|---|---|---|
| coverage | ~50% (feed pagination) | 15/15 fetched, 14/15 usable (≥200 chars) |
| latency | 30–60s per link | **0.8s** (15 links in 12.0s) |
| auth | login session, expires (2 real failures 2026-07-31) | none |
| runtime | headless Chromium ~1.3 GB | one HTTP GET |
| failure mode | ambiguous "not in recent feed" | clean HTTP status |

All 4 posts tier-2 missed return full content publicly; on posts tier-2
hit, JSON-LD often returns more than the feed scrape. No rate limiting
observed across 12 rapid sequential requests.

**Extraction rule — `max(articleBody, og:description)`, never articleBody
alone:** each source is individually incomplete. In the spike, og wins
outright on 2 of 15 (one post has ld=0/og=896, another ld=257/og=283).

**Semantics:**

- Public extract ≥ threshold → returned, tier-2 not invoked.
- Below threshold → tier-2 runs as enrichment; the longer result wins.
- HTTP 404 or an empty extract with no tier-2 result → still `Ok(None)`.
- Transport failure on both paths → still `Err`.
- LinkedIn `/safety/go/` wrapper URLs are unwrapped (percent-decoded `url`
  param) before platform classification, so wrapped external links route to
  their real platform.

**Caveats, stated honestly:** n=15, all recent posts from one backlog at one
moment. LinkedIn can change its markup — though parsing public preview
metadata is markedly less fragile than authenticated DOM scraping. Untested:
deleted posts, company pages, very old posts, sustained bursts. articleBody
is the post body only (no comments). The tier-2 client is deliberately NOT
deleted — it remains the right implementation for whatever the public path
cannot reach.

## Consequences

- The command is genuinely unattended-capable: no interactive session
  required after the one-time `linkedin-scraper-mcp --login` setup.
- `fetched_content` stays unpopulated by the automatic pipeline until t-1144
  explicitly wires it in — the reserved field's comment should be updated to
  reference this ADR alongside t-1144.
- No new HTTP dependency — `ureq` is already a workspace dependency and the
  project's established convention (ADR-024) for this shape of work.
- Session cookie expiry (`linkedin-scraper-mcp`'s persisted login) is an
  operational risk for a nightly job — the command must detect an expired
  session (`--status` check) and fail loud (not silently skip) rather than
  attempt a fetch with a dead session.
- Two Claude subprocess shell-out families now exist side by side in this
  crate: `call_gemini_json` (agy, pure text) and this new one (`claude -p`
  with `--mcp-config` + `--allowedTools`, tool-using). Keep them
  architecturally distinct — the new one is heavier (MCP server startup) and
  should only be invoked for LinkedIn URLs, never as a general-purpose path.

## Amendment (2026-08-17, t-2945): Tier 4 — YouTube (`yt-dlp` subprocess)

**What changes:** `classify_platform()` gains a fourth branch, `"youtube"`
(`youtube.com` / `youtu.be`, incl. `/shorts/`), and `fetch_url_content()`
routes it to a new subprocess-based fetch — neither the Tier-1 `ureq` GET
nor the Tier-2 LinkedIn MCP client, because YouTube's actual content
(captions) is not present in the fetched HTML at all (`docs/ideas/youtube-knowledge-extraction.md`
§Problem — the existing Tier-1 path stores the SPA shell, confirmed live on
`t-1349`).

**Why this doc exists.** `/brana:challenge` (2026-08-17, standard mode)
found the original brainstorm's rate-limit mitigation didn't exist, its
storage shape would have broken the pipeline's idempotency check, and its
no-captions case reproduced `t-1349`'s own bug one layer deeper — 3 CRITICAL
findings, logged to the decision log against
`docs/ideas/youtube-knowledge-extraction.md`. This amendment formalizes the
corrected design from that doc's Risks/Next-steps sections, not the
original brainstorm.

**(a) Fetch mechanism.** Shell out to `yt-dlp` (already installed,
`/usr/bin/yt-dlp`), not a library — no Rust YouTube client exists or is
warranted for one subprocess call:

```
yt-dlp --skip-download --write-sub --write-auto-sub --sub-langs "en" \
  --sub-format vtt --socket-timeout 30 -- "<url>"
```

The `--` end-of-flags separator before the URL is required, not cosmetic: a
`link`-tagged task's URL is attacker-influenced input (captured from
Telegram), and `yt-dlp` has an `--exec <cmd>` flag — the same
"decoded target is untrusted" lesson §Amendment (2026-08-01) already applied
to LinkedIn's `/safety/go/` unwrap, applied here to argv instead of an HTTP
target. Without `--`, a URL string starting with `-` is parsed as a flag.

**Corrected: `--write-sub` added alongside `--write-auto-sub`.** The
original draft of this section requested only auto-generated captions
while separately promising `caption_source: manual|auto` metadata — a
command that can never produce a manual result cannot honestly carry a
`manual` tag. `yt-dlp` writes the human-authored track when one exists and
falls back to the auto-generated track otherwise; both flags together get
the better-quality manual track when available, never worse than the
auto-only behavior. Distinguishing which track actually landed (manual vs.
auto — `yt-dlp --dump-json`'s `requested_subtitles` vs.
`automatic_captions` fields, not filename parsing) is an implementation
detail for DECOMPOSE, not this ADR — but the command must request both for
`caption_source` to ever be true.

Single primary-language (`en`) caption only for Phase 1 — the multi-language
`en.*,es.*` form validated in the brainstorm is what hit `HTTP 429` on its
third request; it is explicitly not what ships. Wrap the subprocess with an
outer kill-timeout of ~60s (generous against the 2–6s typical case measured
live 2026-08-17, bounds the pathological hang `yt-dlp`'s default leaves
open — no default `--socket-timeout` otherwise, `--retries` defaults to 10).
Raw VTT has word-level cue duplication (auto-caption artifact); a dedupe
pass runs before storage — never store raw VTT as the value.

**(b) Batch isolation — YouTube is removed from the shared `drain-links`
batch, not sub-capped within it.** `select_drain_batch()`
(`brana-cli/src/commands/knowledge.rs:166`) is today a single
platform-agnostic FIFO `.take(cap)` over every pending `link`-tagged task
(the filter that will gain the platform split lives in its caller,
`cmd_drain_links`, not in `select_drain_batch` itself — the function stays
a bare `.take(cap)`) —
adding per-platform sub-cap accounting to it is new state-tracking logic
that Phase 3 (channel-crawl, "own scheduler cadence, separate rate-limit
budget") would immediately need to replace with a fully separate job
anyway. Decided in favor of the simpler, already-established pattern
instead: `scheduler.template.json` already runs a dozen independent
one-line `"command"` jobs (`drain-links --cap 10` is one of them, line
~138) — YouTube gets its own line, not a code change to the shared
selector:

- `cmd_drain_links`'s candidate filter (currently `tag:"link",
  status:"pending"`, feeding `select_drain_batch`'s unchanged `.take(cap)`)
  excludes `classify_platform(url) == "youtube"` for the existing
  `drain-links --cap N` job — LinkedIn/GitHub/Substack/arxiv/other are
  unaffected, no change to their behavior or the tested `.take(cap)` logic.
- A new `drain-links --platform youtube --cap N` invocation (same binary,
  new flag: `cmd_drain_links`'s candidate filter becomes exactly
  `classify_platform(url) == "youtube"`) runs as its own
  `scheduler.template.json` entry, with its own
  cap and, inside `fetch_url_content`'s youtube branch, its own
  backoff/retry unit around the `yt-dlp` call for an `HTTP 429`. A stuck or
  retrying YouTube fetch can now only starve its own job's slots, never
  LinkedIn/GitHub/Substack's in the same run — the CRITICAL finding this
  section exists to close.

**(c) No-captions contract.** `yt-dlp` exiting 0 having written zero
subtitle files is a distinct, expected outcome — not an error, not success.
`fetch_url_content` returns `Ok(None)` for it, exactly like a LinkedIn
"post not in feed" miss (§Tier-2 correction above) — `process_one_url`
already treats `Ok(None)` as "leave pending, never `Completed`"
(`should_complete_link` / `is_cancellable`), so no change is needed there,
only in what the youtube branch returns. This is the same failure shape as
the original `t-1349` bug (fetch "succeeds," content is absent, task marked
`Completed` anyway) reproduced one layer deeper if left unhandled — an
explicit fixture test (no-captions video, zero subtitle files written)
covers it alongside the populated-fixture happy path.

**Storage — flat key, unchanged; the write path is not, corrected.** An
earlier draft of this amendment claimed the youtube branch's
`FetchedContent { text, platform: "youtube" }` flows through `process_one_url`
"unchanged," storing the real transcript. That is false against the actual
code: `process_one_url` (`knowledge.rs:384-416`) never stores `content.text`
for any tier — it calls `kp::extract_insight(&content.text, content.platform)`
(`knowledge_pipeline.rs:1723`) first and stores `insight.summary`, the
output of a three-tier LLM-summarization fallback (agy → `claude -p` →
2000-char truncated raw, only on double-failure). `extraction_prompt`
applies no truncation before that call — the full transcript is what's
sent, today, to every existing tier.

Summarizing a video transcript into a short blurb would reproduce the
original bug one layer deeper: `t-1349` failed because the stored
"knowledge" was shallow (an HTML shell), and a one-paragraph LLM summary of
a 152,208-character/29,248-word transcript (the 2h26m video measured live
2026-08-17) is only marginally less shallow. It would also strand Phase 2
before it starts — concepts/entities/timestamp-anchored-citation mining
needs the raw transcript, which would already be gone.

**Decision: the youtube branch bypasses `extract_insight` and stores
`content.text` (the cleaned, deduped transcript) directly.** This is a real
code change beyond "add a branch to `classify_platform`/`fetch_url_content`"
— `process_one_url`'s `Store` arm gains a platform check: youtube skips the
`extract_insight` call and calls `ruflo_memory_store(&key, &content.text,
PROCESS_URL_NAMESPACE, &tags)` directly, where `tags` becomes exactly
`[platform, "transcript", caption_source]` — a fixed 3-element array, with
`caption_source` literally `"manual"` or `"auto"` (no LLM-derived `topic` —
there is no `insight.topic` when `extract_insight` is skipped; `"transcript"`
takes its place as the fixed content-type marker). Every other tier's
summarization behavior is unchanged. **This also resolves the token-cost
second-order effect below**:
because the youtube branch never calls `extract_insight`, Phase 1 incurs no
per-video LLM summarization cost — the token-cost risk the idea doc flags
(~38K tokens/video) stays genuinely Phase 2's problem (concepts/entities
extraction reading the stored transcript), not a cost silently already
paid in Phase 1.

**No new directory-bundle storage shape ships here.** The brainstorm's
`raw/`+`sources/`+`concepts/`+`entities/` design cannot be written through
`ruflo_memory_store`'s flat-value call at all (a directory can't be a
string value) — writing one would leave the idempotency key unset, so every
scheduler cycle would re-fetch every YouTube URL forever, invisible to
`brana recall`'s knowledge-namespace query. That architecture is Phase 2,
itself gated on `t-2937` (OKF adoption, a separate brana-wide decision this
ADR does not make).

**Known limitation, documented not silent: semantic search on a stored
transcript only reaches its opening content.** `knowledge-vector-sync`
(t-2620, `system/scheduler/scheduler.template.json:266-273`, runs 20 min
after every `drain-links` pass) re-embeds every value written to the
`knowledge` namespace via `RufloEmbedder::embed`
(`brana-core/src/vector.rs`) — `ruflo`'s `all-MiniLM-L6-v2`, a 384-dim
sentence model with a ~256-token max input sequence. `vector.rs` has no
chunking anywhere; `truncate_chars` there is only a 300-char *display*
snippet, not an embedding-input bound. Every existing tier's stored value
is an `extract_insight` summary — always well inside that window, so this
never mattered before. This amendment's own decision above (store the full
transcript, not a summary) is the first write positioned to exceed it: a
152,208-character transcript gets silently truncated by the embedder to
roughly its first ~1,000–1,300 characters before it's vectorized, so
semantic (`brana recall`) search on a long video's stored entry only
matches its opening captions — the rest of the transcript is real,
stored, and reachable by exact-key lookup (`process_one_url`'s idempotency
check) and by Phase 2's raw-transcript mining, but not by semantic search.
`brana recall`'s knowledge-namespace side has no FTS fallback for this gap
(ADR-058: FTS5 covers `~/.claude/memory/*.md` only, not the ruflo
`knowledge` namespace).

Accepted as a known Phase 1 limitation, not fixed here: chunked or
multi-vector embedding is real feature work inside `vector.rs` /
`knowledge-vector-sync` — a shared consumer of four other platforms'
entries too, not a youtube-specific concern, and out of scope for an
ADR-only, single-tier task. Tracked as `t-2970` (chunked/multi-vector
embedding for long-content knowledge entries), not gating Phase 1's ship:
until it lands, a long YouTube video is fully stored and exact-key/Phase-2
reachable, just not fully semantic-searchable end to end.

**Consequences.**

- `classify_platform()`'s doc comment (`"linkedin"`, `"github"`,
  `"substack"`, `"arxiv"`, `"other"`) gains `"youtube"` — the return type is
  already `&'static str`, no signature change.
- `fetch_url_content()` gains a fourth branch alongside its existing
  `platform == "linkedin"` special case; the fallthrough `fetch_public_url`
  path is now reached only by github/substack/arxiv/other, unchanged.
- `select_drain_batch()`'s signature/logic is untouched; only its caller in
  `cmd_drain_links` gains a platform filter, applied identically regardless
  of which side of the split a given run is on.
- `process_one_url`'s `Store` arm gains a platform branch (see Storage
  above) — youtube skips `extract_insight`; every other tier's call site is
  unchanged. This is the one piece of this amendment that touches existing
  control flow shared with LinkedIn/GitHub/Substack/arxiv, not just adds a
  new branch alongside them — call it out explicitly in the DECOMPOSE task
  breakdown, not folded silently into "add classify_platform branch."
- Two independent scheduler jobs now drain the same `link`-tagged backlog
  tag by disjoint platform filters — an operational fact worth a one-line
  note in `docs/architecture/hooks.md` or the scheduler doc, not a new
  architectural mechanism. Note for whoever adds the new job entry: the
  existing `link-research-extraction` job (`scheduler.template.json:136-144`,
  the one `drain-links --cap 10` is defined on) runs against
  `project: ~/enter_thebrana/personal`, not `thebrana` — the new
  `--platform youtube` job entry needs the same `project` value, not
  `thebrana`'s, or it will drain against the wrong backlog.
- Lock discipline is unchanged: the youtube branch is reached through
  `fetch_url_content`, which must stay lock-free per §Lock discipline above
  — the `yt-dlp` subprocess call and its retry/backoff wrapper must not
  acquire `lock_pipeline()`. Known pre-existing gap, not introduced by this
  amendment but more load-bearing now (new subprocess call site):
  `test_lock_discipline_source_tripwires` (`brana-cli/src/commands/knowledge.rs`)
  scans only `knowledge.rs` via `include_str!` — it cannot see
  `fetch_url_content` at all, which lives in the `brana-core` crate's
  `knowledge_pipeline.rs`. Extending the tripwire (or adding a companion
  test in `brana-core`) to cover that file is worth doing alongside this
  work, not deferred indefinitely.

## Non-Actions

- Does not implement t-1144 (pipeline tier1/2/3 wiring of `fetched_content`).
- Does not add a custom Rust browser-automation stack (chromiumoxide/fantoccini)
  — `linkedin-scraper-mcp` already solves headless auth+fetch.
- Does not build a skill/slash-command orchestration path — rejected because
  the primary use case (nightly, unattended) has no interactive session to
  orchestrate from.
- Does not implement Phase 2 (directory-bundle `raw/`/`sources/`/`concepts/`/`entities/`
  storage, concepts/entities synthesis, timestamp-anchored citations) —
  gated on Phase 1 proving out in practice AND `t-2937` resolving first.
- Does not implement Phase 3 (channel-crawl via `yt-dlp --flat-playlist`).
- Does not decide brana-wide OKF adoption (`t-2937`) — this amendment only
  borrows OKF's frontmatter conventions where free, per
  `docs/ideas/youtube-knowledge-extraction.md` §Scope.
- Does not build the concepts/entities LLM extraction step — Phase 1 stores
  the real transcript text; extraction cost/design is Phase 2's problem
  (see that doc's Risks — Phase 2 token cost, `t-2958`/`t-2959`).

## Changelog

- 2026-07-31: Tier-2 transport replaced — `claude -p` MCP shell-out → direct
  JSON-RPC client in `brana-core` (t-2568, b4695c8e). Mechanism, tier routing,
  and `Ok(None)` miss semantics unchanged. See §Amendment.
- 2026-07-31: Subprocess failure diagnostics separated — a deadline and a
  server that closes output early no longer share wording (t-2568, 89d16ac4).
- 2026-08-01: LinkedIn tiers inverted — public JSON-LD/og extract primary
  (0.8s, 14/15 usable), authenticated scrape demoted to below-threshold
  fallback; `/safety/go/` unwrap added (t-2589). See second §Amendment.
- 2026-08-17: Fourth tier added — YouTube via `yt-dlp` subprocess (both
  `--write-sub`/`--write-auto-sub`, `--` argv-injection guard), single `en`
  caption, removed from the shared `drain-links` batch into its own
  scheduler job, `Ok(None)` no-captions contract, flat storage key with the
  youtube branch bypassing `extract_insight`'s LLM summarization to store
  the raw transcript directly, and the resulting `knowledge-vector-sync`
  semantic-search limitation documented with a tracked fast-follow
  (`t-2970`) rather than silently accepted (t-2945; corrected across two
  Challenger gate iterations — storage-claim CRITICAL in iteration 1,
  vector-sync/caption-command WARNINGs in iteration 2 — plus an earlier
  `/brana:challenge` pass against
  `docs/ideas/youtube-knowledge-extraction.md`). See §Amendment.
