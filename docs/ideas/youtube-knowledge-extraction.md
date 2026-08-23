---
title: YouTube Knowledge Extraction
status: draft
created: 2026-08-17
---
# YouTube Knowledge Extraction

> Brainstormed 2026-08-17.

## Problem

`brana knowledge drain-links` (the live scheduler pipeline that turns Telegram-captured links into stored knowledge, ADR-070) treats YouTube URLs as a generic `"other"` platform. `classify_platform()` in `system/cli/rust/crates/brana-core/src/knowledge_pipeline.rs` only special-cases `linkedin.com`, `github.com`, `substack.com`, `arxiv.org` — YouTube falls through to `fetch_public_url()`, a raw `ureq::get()` + HTML-tag-strip. For a YouTube watch page that returns the SPA shell (title, meta tags, boilerplate), never the video's actual content.

**Confirmed live, not theoretical:** task `t-1349` (personal repo) — `https://www.youtube.com/watch?v=9VlvbpXwLJs`, captured via Telegram 2026-07-26 — was drained and marked `completed` by the scheduler on 2026-07-31/08-01. It almost certainly stored the shallow HTML shell as "knowledge," not the video's content.

## Scope

The research below surfaced three adjacent ideas that got tangled up with this one mid-brainstorm. They're deliberately split out to their own backlog items so this doc stays buildable in 1-2 weeks:

- **OKF adoption as brana's general knowledge storage format** — a source-agnostic decision (affects LinkedIn/GitHub/dimension docs, not just YouTube). Tracked separately as `t-2937`; **not decided by this doc.**
- **Cole Medin as an ongoing knowledge source** — using the pipeline below to mine his channel specifically. A *consumer* of this pipeline, tracked separately as `t-2938`.
- **Consuming Cole's existing published knowledge base** (`coleam00/cole-medin-knowledge-base`) directly — may need zero pipeline work, just importing his bundle. Tracked separately as `t-2939`, can happen independently of and sooner than this build.

This doc's scope is **only** the mechanical pipeline: YouTube video/channel → real transcript → extracted knowledge, integrated into the existing `drain-links` scheduler. The storage shape below borrows OKF's frontmatter conventions where they're free (they already resemble brana's existing markdown+frontmatter pattern) without committing to full OKF adoption — that commitment is the separate task's job.

## Proposed solution

Add `"youtube"` as a platform tier in `classify_platform()` (same pattern LinkedIn already uses — ADR-070 three-tier fetch), with a dedicated fetch path that pulls the video's subtitles/captions instead of scraping the page.

**Objective (phased):** whole-channel knowledge extraction is the end goal, but scope starts narrow — single video/shorts URL → transcript → knowledge, matching today's Telegram-link-capture flow — then extends to channel-level crawl (list a channel's videos, process each).

### Technical mechanism (validated live)

`yt-dlp` is already installed on this machine (`/usr/bin/yt-dlp`, v2026.03.17) — no new dependency. Confirmed working end-to-end against the exact video from `t-1349`, using a multi-language exploratory command:

```
yt-dlp --skip-download --write-auto-sub --sub-langs "en.*,es.*" --sub-format vtt "<url>"
```

Pulled 1.37MB of real, word-timed English captions ("I am good at only one thing business for the last 30 years I built 19 companies...") — genuine transcript content, not the HTML-shell junk the current pipeline stores.

**What actually ships in Phase 1 is a different, narrower command** — `/brana:challenge` (2026-08-17) caught that the exploratory command above is the one that hit rate limiting below, while the Risks mitigation described a different, never-validated single-language variant. Pinning it explicitly:

```
yt-dlp --skip-download --write-auto-sub --sub-langs "en" --sub-format vtt "<url>"
```

Single primary-language caption only, per video. `--flat-playlist` (no download) lists a channel's video URLs for the channel-crawl phase (Phase 3).

**Findings from the live test:**
- Subtitle/auto-caption download is free, no API key, no quota — cheapest option, confirmed superior to YouTube Data API (quota-limited) or timedtext scraping (fragile, undocumented).
- **Rate limiting is real, not hypothetical**: requesting a third subtitle language (`es`) back-to-back on the same video hit `HTTP 429 Too Many Requests`. Channel-scale crawling (dozens–hundreds of videos) will need backoff/retry and pacing, not naive looping.
- Raw VTT output has word-level cue duplication (auto-caption artifact — each line repeats with incremental word reveals) — needs a cleanup pass (dedupe cues → plain text) before feeding an LLM for knowledge extraction. Don't pipe raw VTT into extraction as-is.

## Research findings

- No existing YouTube-specific tooling in the repo before this (`grep` for `yt-dlp`/`youtube-transcript`/`youtube.com` across `system/` found only the generic `fetch_url_content` path).
- Existing precedent: `docs/ideas/drained/telegram-link-capture.md` (shipped) — links captured via Telegram queue → `brana knowledge drain-links` → stored as `knowledge:url:<slug>` in ruflo `knowledge` namespace. This is the exact integration point; no new capture mechanism needed, only a better fetch tier for URLs already flowing through it.
- `brana feed` (t-585, shipped) already polls YouTube via RSS/Atom for *new upload* notifications — relevant if/when this extends to ongoing channel monitoring, so the "new video appeared" signal doesn't need to be reinvented.

**Open Knowledge Format (OKF)** — Google Cloud spec, announced 2026-06-12 ([Google Cloud blog](https://cloud.google.com/blog/products/data-analytics/how-the-open-knowledge-format-can-improve-data-sharing), [annotated spec](https://okf.md/spec/)):
- A bundle is a directory of markdown "concept" files with YAML frontmatter, cross-linked via relative markdown links into a navigable graph, indexed via `index.md`.
- Only `type` is required; recommended fields in priority order: `title`, `description`, `resource`, `tags`, `timestamp`. Producers may add arbitrary extra keys — consumers must preserve unknown fields, never reject on them.
- **v0.2 adds a trust/provenance layer directly relevant to the auto-caption-accuracy risk below**: a `generated` field (who/what produced a concept + when, supersedes plain `timestamp`), a `sources` field for citations, a `status` lifecycle (`draft`/`stable`/`deprecated`), and `stale_after` dates.

**Reference implementation exists** — [`coleam00/cole-medin-knowledge-base`](https://github.com/coleam00/cole-medin-knowledge-base), an OKF bundle built from ~198 YouTube videos (the one surfaced via the LinkedIn post shared mid-brainstorm). Structure:
```
raw/            immutable, timestamped transcripts — source of truth, + manifest.json
concepts/       ideas, techniques, patterns — synthesized ACROSS videos discussing them
entities/       tools, people, organizations mentioned
sources/        one summary page per video, provenance-linked back to raw/
index.md        compiled wiki — the search index
```
Each concept/entity page ends with a `## Sources` section citing specific videos and timestamps — the mechanism that makes "citations back to the exact moment" work. This is structurally the same `Sources → raw/ → Wiki → Q&A → Output` pipeline Karpathy's methodology describes, which `docs/ideas/drained/inbox-to-dimensions-pipeline.md` already adopted as brana's target shape for Layer 2 knowledge.

**Corrected by `/brana:challenge` (2026-08-17, systems finding, CRITICAL):** this directory-bundle shape is NOT what Phase 1 ships. The `drain-links` pipeline's actual idempotency check — `process_one_url`'s only skip condition — is a flat-value lookup, `ruflo_memory_get("knowledge:url:<slug>", "knowledge")` (`knowledge.rs:384-416`), written back via `ruflo_memory_store`, a single string value per key. A directory bundle can't be written through that call, so writing one for YouTube would leave the idempotency key unset — **every 4-hourly scheduler cycle would re-fetch every YouTube link forever**, and the content would be invisible to `brana recall`'s knowledge-namespace query (silent, no error). Phase 1 ships on this existing flat shape instead, with real transcript text as the stored value — see Next steps. The directory-bundle/`concepts/`/`entities/` architecture above is deferred to Phase 2, itself gated on `t-2937` (OKF adoption decision) so brana doesn't end up with three incompatible knowledge-storage shapes live at once (this doc's bundle, `t-2939`'s imported Cole Medin bundle, and the existing flat store).

**Claim/chunking approach**: current best practice (2026) favors structure-aware segmentation over fixed-token chunking — splitting a transcript along natural concept boundaries (topic shifts, paragraph-like breaks in speech) rather than mechanical 512/1024-token windows, since the goal is "smallest semantically complete unit," not RAG-optimized retrieval chunks. This matches the concepts/entities extraction the reference implementation does (mine each transcript for the concepts/entities it teaches, with timestamped quotes) rather than raw chunking.

## Risks

> Updated 2026-08-17 after `/brana:challenge` (standard mode, 3 native challengers: convergent/critical/systems, all completed; Gemini step failed on a headless permission error and was skipped per the skill's error rule). Verdict: **PROCEED WITH CHANGES**. 9 findings (3 CRITICAL, 6 WARNING) logged to the decision log against this doc. The three risks below are rewritten to reflect what the challenge actually found, not what was originally assumed.

- **CRITICAL — the rate-limit mitigation described in the first draft didn't exist.** [3-way agreement, HIGH confidence] "Reuse the LinkedIn-tier `--cap N` pattern" is not rate-limiting infrastructure — `knowledge_pipeline.rs` has zero matches for `429`/`backoff`/`retry` anywhere. `t-2560`'s `--cap N` is a link-count-per-scheduler-run wall-clock budget (~30-50s/link against a 1800s job timeout), not pacing; `t-2583` is an unrelated URL-dedup fix. Worse: `drain-links --cap 10` is **one platform-agnostic FIFO batch shared by every tier from day one** (`scheduler.template.json:138`, `select_drain_batch` is pure `.take(cap)`) — a stalled/retrying YouTube fetch can starve LinkedIn/GitHub/Substack's slots in the *same run*, not just at YouTube channel-scale.
  → Fix: build real backoff/retry as its own tested unit (see Next steps, new Phase 1 task). Give YouTube a per-platform sub-cap within the shared batch, or move it off the shared job entirely for Phase 1 — decide which in the ADR.
- **CRITICAL — "yt-dlp succeeds but writes nothing" was unhandled.** [2-way agreement, HIGH confidence] Many videos have no manual or English auto captions; `yt-dlp` exits 0 having written no subtitle file — no crash, no error surfaced. This is the *same failure shape* as the original `t-1349` bug: a fetch that "succeeds" while producing nothing usable, silently marked `Completed`. Without an explicit contract, a future yt-dlp/YouTube-side drift reproduces the same bug class one layer deeper.
  → Fix: exit 0 + no subtitle file written → `Ok(None)`/stays pending, **never** `Completed`. Explicit acceptance criterion + fixture test for the no-captions case (not just the populated-fixture happy path).
- **Auto-generated captions can be wrong** (original risk, still valid, storage mechanism corrected below). Accents, jargon, non-English audio all degrade auto-caption accuracy. Storing that as "knowledge" without provenance is worse than today's junk — it now *looks* legitimate instead of obviously being an HTML shell.
  → Mitigation: yt-dlp reports caption track type (manual `en` vs. auto-generated `en-orig`/`a.en`). Carry `caption_source: manual|auto` as metadata alongside the flat-stored transcript value (not OKF frontmatter — see storage-shape correction above; Phase 1 has no bundle to put frontmatter in). Note (convergent, LOW severity): nothing in Phase 1's own scope *consumes* this field yet — it's forward-looking bookkeeping for Phase 2, not a present-tense filtering capability.
- **Corrected 2026-08-17 (direct investigation, post-challenge) — the cited precedent did NOT die from scope creep, and both challengers' split-verdict theories were wrong.** `inbox-to-dimensions-pipeline.md` is not an abandoned shape doc: its task tree (`t-1113`, 9/10 subtasks) is `completed`, `brana knowledge process --tier1/--tier2/--draft` is real, live, documented CLI (verified via `--help`), and **it is still running nightly** — `brana knowledge process --status` (checked 2026-08-17) shows Tier 1 last ran *today*, Tier 2 on 2026-08-15, 857 URLs clustered, 100 drafts synthesized. The actual, observed failure mode is that its draft cap (10) is **currently maxed at 10/10** — exactly what the original 2026-04 doc's own "Cons" section predicted: *"Review backlog risk. If the user misses a weekly review, drafts pile up."* The real lesson for this doc: **automation that generates review-requiring artifacts faster than a human reviews them is the actual risk, not never-shipping.** This bears directly on Phase 2 (concepts/entities synthesis) and Phase 3 (channel-crawl, which multiplies content volume) — neither should generate faster than review capacity without an explicit cap-and-stop mechanism, same as the precedent now enforces.
  → Mitigation: hard-phase it (unchanged, still correct for a different reason — see Next steps). Additionally: if Phase 2 introduces any human-review step (e.g. draft promotion), give it the same hard cap discipline the precedent uses, from day one, not as a retrofit.
- **`t-2939` (importing Cole Medin's existing bundle) could cannibalize this build's momentum** [systems, MEDIUM]. Treat `t-2939` landing as a deliberate scope-recheck, not a parallel track — and diff its imported bundle against anything this doc produces before `t-2937` picks a canonical shape, to avoid three incompatible knowledge formats live at once.
- **Phase 2 token cost is a different order of magnitude than the existing pipeline's, and was previously untracked.** [investigated 2026-08-17] `knowledge process --tier1/--tier2/--draft`'s LLM calls (`call_claude_json`/`call_claude_text`) operate on metadata only — author, title, hashtags, a 500-char dimension summary — never full content (v1 design note: "no HTTP fetch"). Roughly 300-1,000 tokens/call. Phase 2 here reads the *whole transcript*: live-measured on the 2h26m video, cleaned captions are 152,208 characters / 29,248 words ≈ **~38,000 input tokens for one video** — a typical 15-30 min video would be ~4,000-9,000. Multiplied by videos-per-channel (Phase 3's stated end goal), this is a real budget question, not a rounding error. Separately: `claude --print --output-format json` returns `total_cost_usd` + token usage in its envelope, but `call_claude_json`/`call_claude_text` discard everything except the result text — zero cost/usage tracking exists anywhere in the pipeline today.
  → Fix: `t-2958`/`t-2959` (filed 2026-08-17, under Phase 2) — capture and log per-call cost/token usage before Phase 2 ships, so channel-scale cost is measured, not discovered after the fact. Billing note: this runs through the local `claude` CLI (subscription usage), not a metered API key — not a separate dollar line-item, but real usage-pool consumption worth seeing at volume.
- **yt-dlp subprocess timeout — measured 2026-08-17, no longer a guess.** Two controlled live runs: a 2h26m video with real captions → 2.25s; a video with zero available captions (exit 0, zero files written — the exact no-captions scenario from the CRITICAL finding above, reproduced live) → 5.51s. Both dominated by extractor/API-JSON overhead, not video length or caption volume. Separately confirmed via `yt-dlp --help`: **no default `--socket-timeout`** (unbounded hang risk on a stalled connection) and `--retries` defaults to 10.
  → Fix: pin an explicit `--socket-timeout 30` on every yt-dlp invocation (generous relative to the observed 2-6s typical case, bounds the pathological hang the default leaves open) plus an outer process kill-timeout of ~60s, following the same measured-not-guessed pattern the LinkedIn tier's `LINKEDIN_MCP_TIMEOUT_SECS` constant already documents.

## Second-order effects

- Ship phase 1 (single-video fix) → the existing `t-1349`-style junk entries for YouTube links become correctly re-extractable → re-running drain on old YouTube links surfaces genuinely new knowledge that was silently missing → **surprise: this may reveal the LinkedIn/GitHub/Substack tiers have similar shallow-fetch gaps** (e.g. GitHub README-only vs. actual code, Substack paywall shells) that were never audited the way this one was — worth a quick platform-coverage pass after this ships, not before.
- Ship timestamp-anchored storage (phase 2) → knowledge docs can cite `t=142s` back to source → **opportunity**: this makes brana's own `recall`/dimension docs meaningfully more verifiable than the current text-only citations — a reader (or an agent) can jump straight to the claim's origin instead of trusting a paraphrase.

## Next steps

> Rewritten 2026-08-17 after `/brana:challenge` — Phase 1 now ships on the pipeline's existing flat storage, not a directory bundle. See Risks above for why.

1. **Phase 1 — single video/shorts, flat `knowledge:url:<slug>` storage (corrected).** Add `"youtube"` tier to `classify_platform()`; new fetch path shells out to `yt-dlp --skip-download --write-auto-sub --sub-langs "en" --sub-format vtt` (single primary-language caption — the exact command that ships, per the Technical Mechanism correction above); clean VTT cue-duplication into plain text; store the real transcript as the value under the existing `ruflo_memory_store("knowledge:url:<slug>", ...)` call every other tier already uses — same idempotency/recall mechanism, just real content instead of HTML-shell junk. `caption_source: manual|auto` carried as metadata on that same value. **Explicit no-captions contract**: yt-dlp exits 0 with no subtitle file → stays pending, never marked `Completed`. **Real backoff/retry** as its own tested unit, plus a per-platform sub-cap (or removal from the shared batch) so a stuck YouTube fetch can't starve other platforms' slots in `drain-links --cap N`. Ships through the existing `drain-links` scheduler job — no new capture mechanism needed. No `raw/`/`sources/`/`concepts/`/`entities/` bundle yet — that's Phase 2, and it's a materially bigger architectural step than originally scoped.
2. **Phase 2 — directory-bundle storage (`raw/`+`sources/`+`concepts/`+`entities/`), concepts/entities synthesis, timestamp-anchored citations.** Mine transcripts for concepts/entities via structure-aware (not fixed-token) segmentation, per `coleam00/cole-medin-knowledge-base`'s pattern; write/update `concepts/*.md` and `entities/*.md` docs, each ending in a `## Sources` section citing `resource` + `&t=Ns` back to the originating video. **Gated on two things, not one**: Phase 1 actually being used in practice (the original "earn the scope" decision), AND `t-2937` (OKF adoption decision) resolving first — shipping a bundle format here before that decision lands risks pre-biasing it and risks schema-drift against `t-2939`'s imported Cole Medin bundle.
3. **Phase 3 — channel-crawl.** `yt-dlp --flat-playlist` to list a channel's videos/shorts; feed each through the Phase 1+2 pipeline; own scheduler cadence, separate rate-limit budget from the Telegram single-link job. Backfill mode first; ongoing monitoring (new-upload detection) can likely reuse `brana feed`'s existing YouTube RSS polling (t-585) rather than reinventing it.

### Engineering disciplines

- **DDD (Decision):** ADR needed — extends ADR-070 (three-tier fetch, more precisely a restructure of `fetch_url_content()`'s binary branch into an N-tier dispatch, per convergent's LOW finding that "same pattern LinkedIn uses" overstated the current mechanism) with a fourth tier. Must also decide: per-platform sub-cap vs. removal from the shared `drain-links` batch, and the no-captions `Ok(None)` contract. Directory-bundle storage is Phase 2's decision, deferred — does NOT decide brana-wide OKF adoption (`t-2937`, separate task).
- **TDD (Tests):** `classify_platform()` returns `"youtube"` for youtube.com/youtu.be URLs (incl. shorts); yt-dlp subprocess wrapper tested against a recorded/fixture VTT, not live network (same discipline as the LinkedIn tier's existing tests); VTT cue-dedup function unit tested; **no-captions fixture** (yt-dlp exit 0, zero subtitle files → `Ok(None)`, not `Completed`); backoff/retry unit tested against a simulated `429`.
- **SDD (Spec/Docs):** `docs/architecture/decisions/` gets the new ADR; `docs/architecture/features/` gets a feature spec before Phase 1 implementation begins (this is M-effort — spec-gate applies).
- **Docs:** tech doc for the new tier; no user guide needed (internal pipeline, no user-facing surface beyond what `drain-links` already has).

## Challenge findings

Full report from `/brana:challenge` (2026-08-17, standard mode, pre-mortem flavor) is in the decision log, tagged against this doc. Verdict: **PROCEED WITH CHANGES** — core motivation and phased structure are sound (critical's positive observation: this doc is *not* a scope-creep risk in the way its own cited precedent was), but Phase 1 as originally specified would have shipped with a fictional rate-limit mitigation, an unhandled recurrence of the original bug, and a storage design that broke the pipeline's actual re-fetch/recall mechanism. All three are addressed in the Risks and Next steps sections above. Highest-leverage single change, per all three challengers: ship Phase 1 on the existing flat `knowledge:url:<slug>` storage — done.
