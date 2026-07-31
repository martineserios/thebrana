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

## Non-Actions

- Does not implement t-1144 (pipeline tier1/2/3 wiring of `fetched_content`).
- Does not add a custom Rust browser-automation stack (chromiumoxide/fantoccini)
  — `linkedin-scraper-mcp` already solves headless auth+fetch.
- Does not build a skill/slash-command orchestration path — rejected because
  the primary use case (nightly, unattended) has no interactive session to
  orchestrate from.

## Changelog

- 2026-07-31: Tier-2 transport replaced — `claude -p` MCP shell-out → direct
  JSON-RPC client in `brana-core` (t-2568, b4695c8e). Mechanism, tier routing,
  and `Ok(None)` miss semantics unchanged. See §Amendment.
- 2026-07-31: Subprocess failure diagnostics separated — a deadline and a
  server that closes output early no longer share wording (t-2568, 89d16ac4).
