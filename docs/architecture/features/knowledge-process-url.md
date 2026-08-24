# Feature: `brana knowledge process-url`

**Date:** 2026-07-24
**Status:** building
**Task:** t-1781

## Problem

LinkedIn research stubs and other JS-heavy/auth-gated URLs accumulate in the
backlog (tag `powerhouse +wave2`, and generally any research-stream task
whose `context` is a bare URL) with no automated way to extract their
content into ruflo knowledge memory. Today this is done manually, one URL at
a time, inside an interactive Claude Code session. The primary need is a
**nightly, unattended** job that drains this backlog.

## Decision Record (frozen 2026-07-24)

See [ADR-070](../decisions/ADR-070-knowledge-process-url-headless-fetch.md)
for the full architecture decision (headless-first fetch, three-tier
mechanism, scope split from t-1144). Summary: `reqwest` for public URLs,
headless `claude -p --mcp-config` shell-out to the already-installed
`linkedin-scraper-mcp` for LinkedIn, `agy` for extraction, new
`ruflo_memory_store()` for persistence. Explicitly NOT wired into the
existing tier1/2/3 pipeline (`knowledge_pipeline.rs`) — that remains t-1144's
gated decision; this ships a reusable fetch function t-1144 can later adopt.

## Constraints

- Must run fully unattended (nightly cron) after one-time interactive
  `linkedin-scraper-mcp --login` setup.
- Must not require the Chrome extension / an interactive Claude Code session
  at run time.
- Must not silently succeed on an expired LinkedIn session — fail loud.
- Must not duplicate the existing pipeline's URL tracking state
  (`~/.swarm/knowledge-pipeline-state.json`) — this command's storage is
  independent (ruflo `knowledge` namespace, keyed by slugified URL).

## Scope (v1)

- `brana knowledge process-url <url>` — single URL: fetch → extract → store,
  print the stored key + insight summary.
- `brana knowledge process-url --file tasks.jsonl` — batch: read `{id, url}`
  pairs, process each in sequence, print a list of task IDs that can now be
  cancelled (their content has been drained into knowledge memory).
- Platform detection: `linkedin.com` URLs → Tier 2 (MCP shell-out); anything
  else → Tier 1 (reqwest). No third platform-specific path in v1.
- Session health check before any LinkedIn fetch (`linkedin-scraper-mcp --status`
  equivalent) — hard-fail with a clear remediation message
  ("run `linkedin-scraper-mcp --login` to refresh") if the session is dead.

## Out of scope (v1)

- Wiring into the tier1/2/3 pipeline (t-1144).
- Platforms other than generic-HTTP and LinkedIn (Notion, etc. — mentioned
  in the original task note, deferred until a concrete need appears).
- Automatic retry/backoff scheduling — the nightly cron wrapper (not this
  task) owns retry policy; this command is a single-shot per invocation.

## Assumptions (resolved 2026-07-24)

- `linkedin-scraper-mcp --login` is a one-time manual setup step performed by
  the operator, documented in the user guide — no interactive fallback or
  scripted wrapper in v1. The command hard-fails on a dead/missing session
  (see Edge Cases) since it must work correctly when invoked unattended.
- The scoped `--mcp-config` file for the `claude -p` shell-out is generated
  at runtime to a temp file, not statically checked in — corrected 2026-07-24
  after empirical verification: `linkedin-scraper-mcp`'s install path is
  machine-specific (resolved via env-var → `~/.local/bin` → `PATH`, mirroring
  the existing `resolve_ruflo_binary`/`resolve_agy_binary`/`resolve_claude_binary`
  pattern), so a static file with a hardcoded absolute `command` path
  wouldn't be portable. Content is otherwise fixed (one server entry) and
  the temp file is written immediately before the call and not left behind.
- Storage tags `[domain, topic]`: `topic` is derived from the agy-extracted
  insight (agy returns a short topic/category label alongside the summary);
  falls back to the platform name (`linkedin`/`web`) when extraction was
  skipped (agy unavailable — see the extraction-skipped fallback above).
- Batch mode's "cancellation list" output is advisory text only (v1) — it
  does not call `brana backlog set <id> status cancelled` itself. A human
  reviews the printed list and cancels manually. Automatic cancellation was
  judged too risky for a first cut.
- `agy` unavailable/quota-exhausted during extraction → fall back to
  `claude -p` text extraction (existing `call_claude_json`/`build_claude_args`
  Layer-C pattern, already used for the LinkedIn tier — no new shell-out
  family needed) rather than immediately degrading to raw text. Only if
  *both* agy and `claude -p` fail does the command fall back to storing
  truncated raw fetched text (flagged `extraction_skipped: true`). This
  three-tier extraction fallback means a nightly agy outage alone never
  blocks the batch or degrades quality — degradation only happens on a
  double failure. Re-extraction can happen later against the stored raw text
  when `extraction_skipped` is set.

## Behavior

- Happy path (public URL): `brana knowledge process-url https://example.com/post`
  fetches via reqwest, extracts via agy, stores to ruflo (`knowledge:url:{slug}`),
  prints `Stored: knowledge:url:{slug}\n{insight summary}`.
- Happy path (LinkedIn URL): same command, detects `linkedin.com`, checks
  session health, shells out to `claude -p` with the scoped MCP config to
  fetch post content via `linkedin-scraper-mcp`, then extraction + storage
  as above.
- Batch: `brana knowledge process-url --file tasks.jsonl` processes each
  `{id,url}` line, prints per-URL result, ends with a summary list of task
  IDs safe to cancel.
- Success is confirmed by the printed stored key (grep-able) and a non-zero
  exit code on any failure in the batch (so a nightly cron wrapper can alert).

## Edge Cases

- LinkedIn session expired/missing → hard fail, exit non-zero, message names
  the remediation command (`linkedin-scraper-mcp --login`).
- **LinkedIn post not found in the author's fetched feed** (corrected
  2026-07-24 — see ADR-070 §Tier-2 correction: `linkedin-scraper-mcp` has no
  arbitrary-URL fetch, only `get_person_profile(sections="posts")`
  fuzzy-matched against the URL's title-signal) → distinct outcome from a
  fetch failure: print "post not found in {author}'s recent feed", do not
  store anything, do not add the ID to the cancellation list. This is
  expected to happen for older posts and is not itself an error.
- URL already processed (slug already exists in ruflo `knowledge` namespace)
  → skip fetch, print "already stored: {key}" (idempotent — safe to re-run
  the same batch file).
- Fetch succeeds but content is empty/near-empty (e.g. a deleted post) →
  store nothing, print a warning, do not add the ID to the cancellation list.
- `agy` unavailable/quota-exhausted → per delegation-routing.md, this is the
  one sanctioned agy use case (cross-model extraction); on agy failure, fall
  back to `claude -p` extraction (same binary/pattern as the LinkedIn tier);
  only if that also fails, fall back to storing raw fetched text (truncated
  to N chars, flagged `extraction_skipped: true`) rather than hard-failing
  the whole batch.

## Design

> **Tier inversion (2026-08-01, t-2589 — ADR-070 second §Amendment):** the
> LinkedIn branch now tries a public extract first — one HTTP GET of the post
> URL, `max(ld+json articleBody, og:description)` — and invokes the
> authenticated tier-2 scrape only when that result is under ~200 chars.
> LinkedIn `/safety/go/` wrapper URLs are percent-decode-unwrapped before
> `classify_platform` routing. The bullets below predate the inversion (and
> the t-2568 transport amendment); tier ordering is as ADR-070 now states.

> **Comment/image enrichment (2026-08-24, t-3187):** the public extract's
> ld+json also carries `comment[]` (top ~10 comments, full text +
> `author.name`) and `image.url`. `extract_linkedin_public_text` now
> appends attributed comment text to the post body, with the post author's
> own comments (the classic "link in first comment" pattern) ordered
> first; a missing author name renders as `"(unknown)"`. `image.url`
> travels as best-effort metadata on `FetchedContent.image_url` — the
> image itself is never fetched or OCR'd. Both are additive: absent/empty
> `comment[]`, or a bot-shell page with no ld+json at all, leaves the base
> extract and the tiered-fetch fallback decision unchanged.

> **YouTube tier (2026-08-17, t-2945/t-2950 — ADR-070 Amendment; doc sync
> 2026-08-24, t-3214):** `fetch_url_content()` gained a fourth platform
> branch, `youtube` (`classify_platform` matches `youtube.com`/`youtu.be`,
> including `/shorts/`), shelling out to `yt-dlp --skip-download
> --write-sub --write-auto-sub` instead of either existing tier —
> YouTube's captions aren't present in the fetched HTML at all, so neither
> the Tier-1 GET nor the Tier-2 LinkedIn MCP client applies. `process-url`
> (single-URL and `--file` batch) gained `--cookies-from-browser <browser>`
> / `--cookies <jar>` flags (mutually exclusive, forwarded to `yt-dlp`);
> with neither, `~/.config/brana/yt-cookies.txt` is used if present (mode
> `0600` required, checked at argument resolution even for non-YouTube
> URLs). The Store arm skips `extract_insight` entirely when
> `platform == "youtube"` and stores caption text verbatim, tagged
> `[youtube, transcript, manual|auto]` in place of the usual
> `[platform, topic]` shape — captions are already the content, nothing to
> summarize. A zero-caption `yt-dlp` exit is treated as `EmptyContent`,
> same as any other tier's empty-fetch case. Unattended *bulk* YouTube
> draining (its own cap, its own backoff/retry so a stuck fetch can't
> starve other platforms) lives in the separate `drain-links --platform
> youtube` job — out of this command's and this doc's scope, see
> `knowledge-drain-links.md`; `process-url --file` itself applies no
> platform filter and processes YouTube URLs inline like any other
> platform. Full design: ADR-070 §Amendment (2026-08-17, t-2945). User-facing
> usage: `docs/guide/features/knowledge-process-url.md` § YouTube URLs.

- New `brana-core` module or extension to `knowledge_pipeline.rs`:
  `fetch_url_content(url: &str) -> Result<FetchedContent>` — three-tier
  dispatch (`ureq` / `linkedin-scraper-mcp` shell-out via a new
  `--mcp-config`/`--allowedTools`-capable Claude-CLI arg builder, distinct
  from the existing text-only `call_claude_json`/`build_claude_args`),
  reusing `classify_platform()` (`knowledge_pipeline.rs:614`) for routing.
  Returns raw content + platform tag. Shaped to be reusable by a future
  t-1144. **Must never call `kp::lock_pipeline()`** (see ADR-070 §Lock
  discipline) — this is the one place in this file allowed to skip the
  otherwise-universal handler convention, and must say so in a comment.
- `brana-core/src/ruflo.rs`: add `ruflo_memory_store(key, value, namespace, tags) -> Result<()>`
  AND `ruflo_memory_get(key, namespace) -> Result<Option<String>>` (exact-match,
  for idempotency — do not reuse the existing semantic/fuzzy
  `ruflo_memory_search_raw` for this), mirroring its binary resolution,
  timeout, and fail-open semantics.
- `brana-cli/src/cli.rs`: extend `KnowledgeCmd` with a `ProcessUrl` variant
  (`url: Option<String>`, `#[arg(long)] file: Option<PathBuf>`).
- `brana-cli/src/commands/knowledge.rs`: new handler function, following the
  existing command module's error-handling conventions (`anyhow::Result`,
  `bail!` for hard failures). Extend `test_lock_discipline_source_tripwires`
  (or an equivalent tripwire) to cover the new function's file range.
- Scoped MCP config file for the `claude -p` shell-out: new file under
  `system/cli/rust/` (exact path TBD in DECOMPOSE) containing only the
  `linkedin-scraper-mcp` server entry.
- `Cargo.toml`: no new production dependency (`ureq` already present); add a
  dev-dependency for the Tier-1 integration test mock HTTP server if one
  isn't already available (check before adding).
- Storage record shape: the "extraction-skipped" fallback (agy unavailable)
  must be a named, typed field on the stored value — e.g.
  `{"content": "...", "extraction_skipped": true}` — not an untyped flag in
  free text, so a later re-extraction pass can query for it.

## Boundaries

| Always | Ask First | Never |
|--------|-----------|-------|
| Check LinkedIn session health before any LinkedIn fetch | Adding a new platform-specific fetch path beyond generic-HTTP/LinkedIn | Wire into the tier1/2/3 pipeline (t-1144's scope) |
| Fail loud (non-zero exit) on session expiry or hard errors | Auto-cancelling backlog tasks from batch mode | Use the Chrome-extension browser MCP tools (session-only, unavailable headless) |
| Store with a deterministic slugified-URL key (idempotent) | Changing the scoped MCP config to include other servers | Silently skip a URL without printing a reason |
| Use exact-match lookup (`ruflo_memory_get`) for idempotency | | Call `kp::lock_pipeline()` from `fetch_url_content()` or anything it calls |
| Use `ureq` for HTTP, not a new dependency | | Reuse `ruflo_memory_search_raw` (semantic) for idempotency checks |

## Testing Strategy

- **Unit (70%):** URL→slug key derivation; platform detection (linkedin vs.
  generic); JSON parsing of `claude -p --output-format json` envelopes
  (reuse existing parser if shape matches `call_gemini_json`'s); batch
  file (`tasks.jsonl`) parsing; idempotency check (already-stored skip logic).
- **Integration (25%):** `ruflo_memory_store`/`ruflo_memory_get` against a
  live/local ruflo instance if available in test env, else a stubbed binary
  (matches the existing `resolve_ruflo_binary` test pattern —
  `test_resolve_ruflo_binary_does_not_panic`); `ureq` fetch against a local
  mock HTTP server (check for an existing dev-dependency pattern in this
  crate before adding a new one).
- **E2E (5%):** one smoke test invoking the CLI subcommand end-to-end against
  a real public URL (network-gated, likely `#[ignore]`d by default like
  other network-dependent tests in this crate — confirm convention during
  BUILD).
- **Mock policy:** Real > Fake > Stub > Mock. The LinkedIn MCP shell-out
  path is the one boundary where mocking the subprocess call is appropriate
  (can't hit real LinkedIn in CI); everything else prefers real
  reqwest/local-server or real ruflo binary where available, matching the
  `resolve_ruflo_binary` fail-open pattern already established.

## Documentation Plan

- [x] **User guide** — `docs/guide/features/knowledge-process-url.md`:
      command usage, `--login` one-time setup, batch file format, nightly
      cron wiring example. Verified 2026-08-24 (t-3214): exists, and covers
      all of the above plus the later YouTube/`--cookies*` addition and
      per-outcome troubleshooting table — current with implementation.
- [x] **Tech doc** — this file (`docs/architecture/features/knowledge-process-url.md`),
      kept in sync with implementation. Verified 2026-08-24 (t-3214): was
      stale — missing the Tier-4 YouTube branch (ADR-070 Amendment,
      2026-08-17, t-2945/t-2950) that a `knowledge.rs` code comment already
      assumed this doc described ("feature spec §3"). Added a dated Design
      amendment covering the YouTube tier, its `--cookies*` flags, and the
      `extract_insight`-skipping Store arm; now in sync.
- [x] **Existing docs to update** — verified 2026-08-24 (t-3214), item by item:
      - `fetched_content` field comment in `knowledge_pipeline.rs` (line ~93)
        — already points at ADR-070 alongside t-1144's gated-decision status.
        Done, no change needed.
      - t-1144's backlog `context` field — already corrected (2026-07-24,
        re-corrected 2026-07-29 for the ADR-068→ADR-070 renumber) to point at
        `fetch_url_content()`/ADR-070 instead of the superseded browser-MCP
        design. Done, no change needed.
      - `docs/reference/skills.md` — re-checked and corrected: that file is
        the *skill* reference (`/brana:*` slash commands), not a CLI
        reference table, so it was never the right place for this and has no
        `process-url` entry to add. The actual CLI reference table is
        `docs/reference/brana-cli.md`, which *was* missing a `process-url`
        section (only `ingest`/`next`/`process`/`run`/`search`/`vector-sync`
        existed) — added a `## brana knowledge process-url` section there
        covering usage, flags, and platform routing.

## Challenger findings

Reviewed 2026-07-24 (brana:challenger, ADR-070 + this spec). Verdict:
RECONSIDER on the original draft — 4 findings, all addressed in this
revision:

1. **Lock discipline** — `fetch_url_content()`/`process_url` must never call
   `kp::lock_pipeline()`, despite that being every existing sibling
   handler's convention in `knowledge.rs`. Addressed: called out explicitly
   in ADR-070 and this spec's Design/Boundaries; DECOMPOSE must add a task
   extending `test_lock_discipline_source_tripwires`.
2. **Idempotency mechanism was unspecified** — the only existing ruflo read
   path (`ruflo_memory_search_raw`) is semantic/fuzzy, not exact-match; using
   it for "already processed" risks false-positive skips that would
   silently include an un-fetched URL's task ID in the cancellation list.
   Addressed: new `ruflo_memory_get()` exact-match lookup added to Design.
3. **`reqwest` proposed without checking the established convention** — this
   project already has `ureq` (ADR-024) as a workspace dependency covering
   exactly this "plain GET" use case. Addressed: swapped to `ureq`, no new
   dependency.
4. **Misattributed reuse** — ADR text cited `call_gemini_json` (the
   unrelated agy/Gemini path) as the precedent for the `claude -p
   --mcp-config` shell-out; the real, more distant precedent is
   `call_claude_json`/`build_claude_args`, and MCP-tool-use arg building is
   new work, not reuse. Addressed: ADR corrected to describe this
   accurately as new work built on existing Layer-C infrastructure.

One finding (binary-existence claim for `linkedin-scraper-mcp`) was raised
as Critical but was a false negative from the challenger's Glob-only
verification (no Bash access) missing a `uv tool`-installed symlink;
independently re-verified in the main session via `ls -la`, direct
execution, and `uv tool list` (`linkedin-scraper-mcp v4.8.2`, confirmed
installed). The challenger's calibration memory was corrected to reflect
this so future reviews don't over-weight a Glob miss on a symlinked binary
as proof of fabrication.

Also flagged (Observation): reuse `classify_platform()` for platform
detection instead of reimplementing — addressed in Design.
