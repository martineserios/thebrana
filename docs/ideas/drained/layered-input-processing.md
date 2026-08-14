# Layered Input Processing — Batch + Express Pipelines

> Brainstormed 2026-04-13. Status: idea → MVP scoping.
> Builds on: [`inbox-to-dimensions-pipeline.md`](./inbox-to-dimensions-pipeline.md) (closes the 4-option debate — batch+express is the chosen shape).
> Sibling: [`knowledge-insights-digest.md`](./knowledge-insights-digest.md) (the INSIGHTS step at batch pipeline end).
> Updated 2026-04-13: added intent classification layer (§ Intent Classification).
> Updated 2026-04-13: added URL content fetching findings — LinkedIn publicly readable via HTTP, full JSON-LD extraction (§ URL Content Fetching).
> Updated 2026-04-13: added platform extraction matrix — Tier A (LinkedIn/dev.to/Substack via JSON-LD), Tier B (GitHub API/arXiv), Tier C gaps (X/Medium/Hashnode) (§ Platform Extraction Matrix).
> Updated 2026-04-13: added URL index design — url-index.jsonl + pipeline-state.json, schema, canonicalization, async fetch, query CLI (§ URL Index Design).
> Updated 2026-04-13: added workflow + UX design — brana log as single entry point (1 or N URLs, same behavior), background pipeline, brana knowledge next as status/gate surface, two manual touchpoints (§ Workflow & User Experience).
> Updated 2026-04-13: Tier 1 scoring redesign — 4-dimension rubric, challenger-resolved: novelty gated on content_quality, evidence replaced by spot-check audit, community nullable per platform (§ URL Index Design → Tier 1 scoring).
> Updated 2026-05-24: `brana knowledge ingest` and `brana knowledge next` shipped (t-1665, t-1666). `brana knowledge run` shipped. See `docs/guide/cli.md §brana knowledge`.
> Challenger review 2026-04-13 (original): passed with changes — 2 score-4 findings fixed in design, step order corrected, risks table updated.
> Challenger review 2026-04-13 (Tier 1 scoring): RECONSIDER — 2 score-4 findings resolved, threshold accepted as first guess.
> Challenger review 2026-04-13 (URL index): RECONSIDER — 3 score-4/5 findings resolved, Option B (two files) selected.

## Problem

Raw inputs (URLs, feeds, audio, email, PDFs) accumulate faster than manual triage. The current tier1/2/3/promote pipeline handles URL-sourced LinkedIn content but has three gaps:

1. **No per-item visibility** — items are filtered and clustered without any intermediate "what is this?" view
2. **No drill-down path** — if cluster item 3 is a gem, there's no way to go deep on it before it gets synthesized into a generic cluster draft
3. **Content from feeds/email/audio not flowing in** — `brana feed poll`, `brana inbox poll`, and `brana transcribe` produce output that never reaches the knowledge pipeline

## Solution

Two pipelines sharing a unified pipeline state queue, diverging by intent:

- **Batch** — long tail, automated. Items accumulate → filter → cluster → synthesize → promote → insights
- **Express** — gems, on-demand. You pick one item → overview → research → output → flagged as done (excluded from batch)

ENRICH happens at ingest time inside each CLI command, not as a separate pipeline step.

## Architecture

```
INGEST
  │
  ├── brana feed poll    → FeedLogEntry {title, link, summary, content}   ← ENRICH done at parse time
  ├── brana log <url>    → EventLog {url, title, tags}                     ← LinkedIn=blocked, public=fetchable
  ├── brana inbox poll   → InboxEntry {subject, body}                      ← ENRICH done at parse time
  ├── brana transcribe   → transcript .txt                                 ← ENRICH done at transcription
  └── inbox/ drop        → file + optional note                            ← intent often in filename/note
                ↓
         INTENT CLASSIFY (heuristic → LLM only if uncertain)
           research   → PIPELINE STATE (auto-routed, no triage)
           task       → TRIAGE LIST (confirmation required)
           scheduled  → TRIAGE LIST (confirmation required)
           instruction→ TRIAGE LIST (confirmation required)
           uncertain  → TRIAGE LIST
                ↓ (research track only)
         PIPELINE STATE
           items tagged: source, content_quality (full | metadata | fetchable)
                ↓
         FILTER (tier1) — adapts scoring to content_quality
           full content → richer relevance scoring
           metadata-only → title-based scoring (current behavior for LinkedIn)
              /                                        \
         BATCH                                       EXPRESS
    (auto, scheduled)                           (on-demand, one item)
    CLUSTER (tier2)                             OVERVIEW (2-sentence summary + insight if notable)
    SYNTHESIZE (tier3 — draft dim)              RESEARCH (/brana:research <url>)
    PROMOTE                                     OUTPUT → docs/research/
         \                                      flag item DONE → excluded from BATCH
          └──────────────┬─────────────────────┘
                    INSIGHTS (unified)
              § Promoted to dimensions (batch)
              § Express research docs (express)
              one digest, two sections
```

## Intent Classification

Sits between INGEST and PIPELINE STATE. Every item gets an intent before being routed.

### Intent taxonomy

| Intent | Example | Routes to |
|--------|---------|-----------|
| `research` | LinkedIn post, paper, RSS item, newsletter | knowledge pipeline (auto) |
| `task` | "Add a task to fix X", action email | `brana backlog add` via triage |
| `scheduled` | "Remind me on Tuesday", time-bound voice note | `brana scheduler add` via triage |
| `instruction` | "Update config Z", "Change setting W" | execute or session note via triage |
| `uncertain` | No clear signal | triage list — you pick |

### Source-level defaults (classification skipped)

- `brana feed poll` → always `research`. No classification needed.
- Gmail from known newsletter senders → always `research`.
- Everything else → run classifier.

### Heuristic classifier (no API call)

Pattern-match on content, subject line, or filename before touching the LLM:

```
"task", "todo", "can you", "please add", "add to backlog"   → task
"remind me", "schedule", "on Monday", "at 3pm", "by Friday" → scheduled
"update", "change", "set", "configure", "fix"               → instruction
bare URL or "research", "look into", "what is"              → research
no match                                                     → uncertain → LLM classify
```

Catches ~70% of cases with zero API calls. LLM only runs on uncertain items.

### inbox/ filename convention

Files dropped in `inbox/` often carry intent in their name or an accompanying note:

```
inbox/
  research-paper.pdf        ← prefix "research-" → research
  task-review-auth.pdf      ← prefix "task-" → task
  2026-04-13-note.md        ← read first line for intent
  randomfile.pdf            ← no signal → classify from content
```

The accompanying `.md` note (if present) takes precedence over filename heuristics.

### Routing behavior

**Auto-route to pipeline (no triage):**
- RSS feeds (`brana feed poll`) → always `research`, always silent
- Known newsletter senders (`brana inbox poll`) → always `research`, always silent
- `brana log <url>` (bare URL, no surrounding text) → `research` default, silent

**Always triage (confirmation required before entering pipeline):**
- `brana log <text>` (non-URL input) → triage regardless of classification
- `brana transcribe` output → triage regardless of classification
- `inbox/` file drops → triage regardless of classification
- Any item classified `task` / `scheduled` / `instruction` / `uncertain` → triage

Inline capture prints:
```
⚠ Intent: task — run 'brana triage' to route
```

**Rationale (challenger finding #1):** The dangerous mis-route direction is task→research, not research→task. A voice note or text log entry classified as `research` would silently enter the pipeline, get synthesized into a dimension draft, and never appear in triage. Non-URL, non-feed sources must always triage — even when the heuristic is confident. Only URL-shaped and feed inputs have a reliable enough signal to auto-route.

### brana triage command

Processes the pending triage list. Research items never appear here.

**Persistence:** triage queue is a `status: "triage"` slice of `pipeline-state.json` — not a separate file. Items transition: `triage` → `routed` (after action) or `archived` (after 7-day expiry, status written back to state).

**Hard cap:** if triage queue > 20 items, `brana triage` prints an error and refuses to add more until the queue drains. This is enforced, not advisory.

**Expiry:** items older than 7 days transition to `status: "archived"` on the next `brana triage` run. Archived items are visible in `brana triage --archived` but never surface in the default view.

```
brana triage          # show pending queue (max 20), route interactively
brana triage --count  # show queue size without entering interactive mode
brana triage --archived  # review expired items
```

Per item: confirm intent, edit subject, route (`backlog add` / `scheduler add` / note / discard).

**UX split:**
- **Inline** (`brana log`, `brana inbox poll`, `brana transcribe`): classifies at capture. Auto-route sources = silent. Triage sources = flag with one-liner.
- **`brana triage`**: batch processes the flagged queue. Run when you have 2 minutes.

## Key design decisions

### 1. ENRICH at CLI layer, not pipeline layer
`brana feed poll` already uses `feed_rs` to parse the full RSS/Atom entry — content and summary are in memory. Current code throws them away (`FeedLogEntry` stores only title/link/published). Fix: add `summary` and `content` fields to `FeedLogEntry`. No new network call — content is already fetched.

This pattern applies to all input types: enrich at the source CLI, the pipeline inherits content quality.

### 2. `PipelineItem` schema — non-URL inputs require a new type

Current `knowledge_pipeline.rs` state is `HashMap<String (url), UrlEntry>`. New input types break this:
- `brana transcribe` → file path as ID
- `brana inbox poll` → email message-ID or subject+date
- `inbox/` drop → filesystem path

**Required schema change (before any Rust implementation):**

```rust
enum ItemId {
    Url(String),
    FilePath(String),
    EmailId(String),  // message-id or subject+date hash
}

enum SourceType { Feed, UrlLog, Email, Transcript, InboxDrop }
enum ContentQuality { Full, Metadata, PublicUnfetched }  // "fetchable" renamed for clarity

struct PipelineItem {
    id: ItemId,
    source: SourceType,
    content_quality: ContentQuality,
    title: Option<String>,
    content: Option<String>,
    link: Option<String>,
    done: bool,
    intent: Option<Intent>,
    ingested_at: DateTime<Utc>,
}
```

State becomes `HashMap<String (serialized ItemId), PipelineItem>`.

Tier1 scoring adapts to `content_quality`: `Full` → richer relevance analysis; `Metadata` → title-based scoring (current behavior). `PublicUnfetched` = same as `Metadata` until a fetch step is scheduled.

### 3. Express items excluded from batch via `done` flag
When you run `brana knowledge express <url>` on an item, the research doc IS the contribution for that item. A `done` flag in pipeline state marks it; tier1 skips `done` items on the next batch run. No duplication — no divergent representations.

### 4. Two insight signals, not one
- **Item-level** (express): OVERVIEW catches one-off gems — a single paper, a single post with a breakthrough idea
- **Cluster-level** (batch): INSIGHTS digest catches patterns only visible across a group of related items

Both are needed; neither replaces the other.

### 5. Unified insights digest covers batch + express

`brana knowledge insights` reads two sources:
- Promoted dimension content (batch track output)
- New research docs in `docs/research/` (express track output, filtered by mtime — today or this week)

Output has two distinct sections with provenance labels so quality signals don't blur (challenger finding #4):
```
## Insights — YYYY-MM-DD
### Promoted to dimensions (N) [batch — metadata-derived]
- cluster: agent memory patterns → dim 21 §3 updated
### Express research (N) [express — full content]
- someurl.md — key finding: X
```

The `[batch — metadata-derived]` label stays until t-1144 ships (full LinkedIn content fetch). After that it becomes `[batch — full content]`.

Rationale: express research docs written to `docs/research/` are effectively write-only without a forcing function to revisit them. The insights digest is that forcing function — already read weekly. Unifying costs one extra glob; not unifying means express docs get forgotten.

### 6. RSS is the easiest first extension
- Content already available in the feed (no auth wall)
- `feed_rs` already parses it — just save 2 extra fields
- OVERVIEW for RSS is "summarize `entry.summary`" — one LLM call per flagged item
- Wiring to knowledge pipeline: read from `feed-log.jsonl` as a second input source alongside event log

## Risks and mitigations

| Risk | Mitigation |
|------|-----------|
| LinkedIn ENRICH stays blocked | Batch still runs on metadata only; t-1144 (full content fetch) unlocks this later |
| Express UX is undefined | Start with `brana knowledge express <url>` CLI; no UI needed for MVP |
| RSS feed volume — many items/day | Tier1 relevance threshold already handles volume; `content_quality: full` makes filtering more accurate |
| `done` flag coordination across runs | Store in pipeline state JSON alongside existing item fields |
| Heuristic classifier mis-routes task→research | Dangerous direction: non-URL/non-feed sources always go to triage regardless of classification. Only URL-shaped and feed inputs auto-route. (Challenger finding #1) |
| Triage list accumulates and becomes a chore | Hard cap enforced at 20 (not advisory). 7-day expiry writes `archived` status back to pipeline-state.json. `brana triage --count` for quick health check. (Challenger finding #3) |
| Heuristic "~70% accuracy" is untested | Run classifier offline against existing inbox/ files and transcripts before wiring into production CLI. If uncertain rate > 35%, LLM fallback cost assumption needs revisiting. (Challenger finding #6) |
| `brana knowledge express` trigger is undefined | Specify at implementation time: CLI prompts interactively ("research this item? [y/n]"), shells out to `claude -p` if yes. Latency is acceptable for an on-demand command. (Challenger finding #8) |

## Engineering disciplines

- **DDD:** ADR needed — formalizes batch vs. express as first-class concepts; intent taxonomy; `content_quality` tag semantics; `done` flag contract; closes inbox-to-dimensions 4-option debate
- **TDD:** Unit tests for `FeedLogEntry` with content fields; `content_quality` tagging; `done` flag exclusion from tier1; heuristic classifier (keyword patterns → intent); OVERVIEW prompt builder; triage list persistence
- **SDD:** Update `inbox-to-dimensions-pipeline.md` (converge to batch+express, mark 4-option debate closed); update CLAUDE.md command table with `brana knowledge express` and `brana triage`; update `docs/architecture/features/knowledge-pipeline.md`

## Next steps (ordered by dependency)

> Step order corrected by challenger review — ADR and schema must precede implementation.

1. **ADR** — batch+express + intent classification as the canonical pipeline model; formalizes `PipelineItem` schema, `ContentQuality` enum, `Intent` enum, `done` flag contract, triage queue persistence (challenger finding #7)
2. **`PipelineItem` schema** — extend `knowledge_pipeline.rs` state from `HashMap<url, UrlEntry>` to `HashMap<ItemId, PipelineItem>`; define `ItemId`, `SourceType`, `ContentQuality`, `Intent` enums (challenger finding #2)
3. **`brana triage` CLI subcommand** — triage queue as `status: "triage"` slice of pipeline-state.json; hard cap at 20; 7-day expiry; `--count` / `--archived` flags (must exist before intent wiring — challenger finding #5)
4. **Intent classifier** — heuristic keyword matcher in `brana-core`; returns `Intent` enum; validate offline against existing inbox/ files before wiring (challenger finding #6)
5. **Wire intent classify** into `brana log` (text input) and `brana inbox poll` and `brana transcribe` — auto-route sources silent, triage sources flagged; `brana triage` must be live before this ships
6. **`feed.rs`** — add `summary`, `content` to `FeedLogEntry`; extract from `entry.summary` and `entry.content.body` in `poll_one`
7. **`knowledge_pipeline.rs`** — read from `feed-log.jsonl` as input source; tag items with `content_quality`
8. **`brana knowledge express <url>`** — OVERVIEW prompt → output + interactive `/brana:research` trigger (shell out to `claude -p`); sets `done` flag
9. **Update `inbox-to-dimensions-pipeline.md`** — close the 4-option debate, link here

## Connection to existing pipeline

```
Existing: tier1 → tier2 → tier3 → promote → insights
This doc: FILTER → CLUSTER → SYNTHESIZE → PROMOTE → INSIGHTS  (batch track)
                                                     EXPRESS → OVERVIEW → RESEARCH → OUTPUT (express track)
```

No existing pipeline steps are replaced. This doc adds:
- **Intent classification layer** — between INGEST and PIPELINE STATE
- `brana triage` command — processes task/instruction/uncertain items
- Feed/email/audio as input sources (alongside URL event log)
- `PipelineItem` schema replacing URL-keyed state
- `content_quality` tag (renamed from `fetchable` → `PublicUnfetched`)
- Express track with OVERVIEW + `done` flag
- `brana knowledge express` CLI subcommand
- Unified insights with provenance labels per section

## URL Content Fetching — LinkedIn & Public URLs (2026-04-13)

> Discovery session. Validated by live HTTP fetch against real logged URLs.

### LinkedIn is publicly readable — no auth needed

A plain HTTP GET with a browser `User-Agent` returns a full `SocialMediaPosting` JSON-LD block
embedded in the page HTML. No MCP, no browser automation, no scraper API required.

Validated on: `https://www.linkedin.com/posts/walid-boulanouar_everyone-using-claude-code-...`

### Full extraction inventory (one HTTP GET)

| Field | Source | Notes |
|-------|--------|-------|
| Post body | `articleBody` (JSON-LD) | ~2000 chars, full text |
| Author real name | `author.name` (JSON-LD) | e.g. `"Walid Boulanouar"` not slug |
| Post date | `datePublished` (JSON-LD) | ISO timestamp |
| Likes count | `interactionStatistic[LikeAction].userInteractionCount` | engagement signal |
| Comment count (total) | `commentCount` (JSON-LD) | even beyond what's in HTML |
| Comments (up to ~10) | `comment[].text` + `datePublished` | full text, paginated beyond 10 |
| Hashtags in body | regex `#\w+` on `articleBody` | author-chosen topic signals |
| Links in body | regex on `articleBody` | often `lnkd.in/` shortened |
| Links in comments | regex on `comment[].text` | author frequently drops resources here |
| Hashtags in comments | regex on `comment[].text` | additional topic signals |
| Canonical URL + activity URN | `@id` / `lnkd:url` meta | `urn:li:activity:743...` |

**`lnkd.in` shortened links** are resolvable via a HEAD request → follow redirect → real URL.

**Comment links are high-value**: post authors frequently drop GitHub repos, articles, and tool
links in their own first comment (confirmed on both test posts).

### What this means for Tier 1

| Signal | Today (metadata-only) | After fetch |
|--------|-----------------------|-------------|
| Author | `walid-boulanouar` (URL slug) | `Walid Boulanouar` (real name) |
| Content | `everyone-using-claude-code` (7 words) | full post body |
| Tags | user-added only | user-added + author hashtags from body |
| Links | none | body links + comment links (resolved) |
| Engagement | none | like count |
| Context | none | top ~10 comments |

Tier 1 scoring goes from guessing relevance from a truncated slug to reading the actual post.

### Architectural implication

LinkedIn and public URLs use the **same fetch mechanism** — one HTTP GET, parse JSON-LD +
meta tags. The two-channel complexity (LinkedIn vs public URLs) collapses into a single
`fetch_url_content(url)` function. No separate paths needed.

`content_quality: Metadata` (formerly the LinkedIn-only case) becomes rare — only for URLs
that actively block HTTP fetches (paywalls, auth-walled apps). Most URLs, including LinkedIn,
return `content_quality: Full` after a simple GET.

### Implementation notes

- Fetch at **log time** (`brana log <url>`) — content is freshest, no staleness risk
- Store extracted content in the event log entry alongside the URL
- Single `reqwest` (or `ureq`) call with `User-Agent: Mozilla/5.0 ...` browser header
- Parse: JSON-LD block via regex + `serde_json`; hashtags + links via regex on `articleBody` and `comment[].text`
- Resolve `lnkd.in` links: HEAD request, follow `Location` header, store real URL

## Platform Extraction Matrix (2026-04-13)

> Validated by live HTTP fetch against real logged URLs and public API endpoints.

### Tier A — Full content, one HTTP GET + JSON-LD parse

Same fetch function, same parse logic for all three.

| Platform | JSON-LD type | What you get |
|----------|-------------|-------------|
| **LinkedIn** | `SocialMediaPosting` | Full post body (~2000 chars), real author name, date, likes count, ~10 comments (full text), hashtags in body, links in body + comments |
| **dev.to** | `Article` | Headline, author, date, full article body |
| **Substack** | `NewsArticle` | Headline, author, date, description (~150 chars) |

### Tier B — Full content, platform-specific API (no auth)

| Platform | Method | What you get |
|----------|--------|-------------|
| **GitHub repo** | `api.github.com/repos/{owner}/{repo}` + `/readme` | Description, stars, topics, language, last push date, full README (up to ~20K chars) |
| **arXiv** | HTML parse on `export.arxiv.org/abs/{id}` | Full abstract, title, all authors |

GitHub repos also expose `og:description` via HTTP (repo description only — no README). Use the API for full content.

GitHub issues/PRs: `og:description` gives first ~200 chars of issue body + title. No API needed for basic signal.

### Tier C — Gap: log URL, score on title + user tags only

| Platform | Blocker | Notes |
|----------|---------|-------|
| **X/Twitter** | Full JS shell — no content in HTML | Twitter API v2: free = 100 reads/month (unusable at scale); Basic = $100/mo. Not worth it for MVP. |
| **Medium** | 403 on direct fetch; RSS gives title + date only, body truncated | No reliable workaround without auth. |
| **Hashnode** | 403 on both direct fetch and RSS | Hashnode has a GraphQL API but requires auth. |

Tier C URLs still enter the pipeline — Tier 1 just scores them with weaker signal (title slug + user-added tags). No special handling needed; they degrade gracefully.

### Implementation shape

```
fetch_url_content(url) -> ContentResult {
    match domain(url):
        linkedin.com/posts/  -> http_get + parse_json_ld()        // Tier A
        dev.to/              -> http_get + parse_json_ld()        // Tier A
        *.substack.com/      -> http_get + parse_json_ld()        // Tier A
        github.com/{o}/{r}   -> github_api_repo() + readme()     // Tier B
        arxiv.org/abs/       -> http_get + parse_arxiv_html()    // Tier B
        github.com/*/*/issues/ -> http_get + parse_og()          // partial
        _                    -> http_get + parse_og()            // fallback: title + description
}
```

Single `User-Agent: Mozilla/5.0 ...` browser header covers all Tier A fetches.
GitHub API: no auth header needed for public repos (60 req/hour unauthenticated, 5000/hour with token).

### What this means for Tier 1 scoring

Tier 1 prompt adapts to available content:
- **Tier A/B**: score against full body text — high accuracy
- **Fallback (og only)**: score against title + description — same as current LinkedIn behavior
- **Tier C**: score against title slug + user tags — weakest, but acceptable for MVP

No separate code paths in Tier 1 itself — the scoring prompt just gets more or less content depending on what `fetch_url_content()` returned.

## URL Index Design (2026-04-13)

> Two challenger rounds. All score-3+ findings resolved.

### Architecture decision: two files

**`~/.swarm/url-index.jsonl`** — permanent raw record, append-only, never deleted
**`~/.swarm/knowledge-pipeline-state.json`** — mutable processing state (existing, unchanged)

Rejected alternatives:
- **Extend pipeline-state.json** — full parse+rewrite on every status change; 40MB at 5K URLs
- **SHA256 content sidecar** — over-engineered for personal tool scale; thousands of tiny files

Join overhead is trivial in Rust: both files loaded into memory, HashMap lookup O(1) per item.
Separation is semantically correct: the index is permanent record; pipeline-state is volatile.
Pipeline-state can be rebuilt from the index if corrupted.

### url-index.jsonl schema (one JSON object per line)

```jsonl
{
  "url": "https://www.linkedin.com/posts/...",        // canonical (normalized)
  "original_url": "https://lnkd.in/gXYZ",            // as logged (may differ)
  "logged_at": "2026-04-13T21:14:00Z",               // ISO 8601 datetime
  "fetched_at": "2026-04-13T21:14:02Z",              // null if fetch pending
  "source": "linkedin",
  "content_quality": "full",                         // full | meta-only | unfetched
  "title": "...",
  "author": "...",
  "date": "2026-03-11T10:43:44Z",                    // post publish date
  "likes": 75,
  "body": "...",                                      // capped at 8K chars
  "hashtags": ["claude-code", "ai"],
  "links": ["https://github.com/..."],               // lnkd.in resolved
  "comments": [                                       // capped at 10
    { "text": "...", "date": "...", "links": [...] }
  ]
}
```

**No `status` field** — processing state is owned exclusively by pipeline-state.json.

### URL canonicalization (dedup)

Before writing, normalize the URL:
- Strip trailing slash
- Strip `www.` prefix
- Follow `lnkd.in` / short-link redirects → store resolved URL as canonical
- Check canonical URL against existing index entries before inserting (skip duplicate)

### Fetch behavior at log time

`brana log <url>` is instant — never blocked by network:
1. Write index entry immediately with `content_quality: unfetched`, `fetched_at: null`
2. Attempt fetch in background (or inline if fast)
3. On success: update entry with content, set `fetched_at`
4. On failure: entry stays `unfetched` — resolved on next `brana knowledge index fetch --pending`

### Query CLI

```
brana knowledge index list                              # all entries
brana knowledge index list --status unprocessed        # join with pipeline-state
brana knowledge index list --tag claude-code           # filter by hashtag
brana knowledge index list --source linkedin --since 2026-04-01
brana knowledge index list --quality unfetched         # pending fetch
brana knowledge index show <url>                       # full metadata
brana knowledge index fetch --pending                  # resolve unfetched entries
```

### Tier 1 scoring — challenger resolutions (2026-04-13)

Four-dimension scoring (topical relevance, signal density, novelty, community) with the following fixes applied after challenger review:

| Finding | Score | Resolution |
|---------|-------|------------|
| Novelty unassessable from metadata | 4 | Gate novelty behind `content_quality: full`. When unfetched/meta-only: novelty = NULL, threshold drops to 4/8 |
| Evidence fields accelerate hallucination | 4 | Drop per-item evidence requirement. Replace with 5% spot-check audit path via `brana knowledge process --review` (shows borderline items 5–7 total) |
| Threshold 6/11 is arbitrary | 3 | Accept as first guess. Log all dimension breakdowns. Recalibrate after 50+ runs |
| Community validation is LinkedIn-only | 3 | Community score is nullable per platform. arXiv/GitHub/feed items get NULL community; threshold adjusts to 4/9 |
| 4 dimensions = 4x prompt or 4x calls | 3 | One compound prompt per item returning all dimensions as single JSON object |

## Workflow & User Experience (2026-04-13)

### Entry point: `brana knowledge ingest`

> **Shipped** (t-1665): `brana knowledge ingest` is the canonical URL entry point — accepts direct URLs, file paths (URL lists, WA exports, any text), or stdin. Queues extracted URLs as `Unprocessed` in `pipeline-state.json`.

`brana knowledge ingest` is the source-agnostic entry point for URLs — one URL or many, behavior is identical.

```
brana log <url>
brana log <url1> <url2> <url3> ...
```

No modes, no flags, no separate batch command.

### What happens on every `brana log` call

```
1. canonicalize URL(s) + dedup check     — instant, no network
2. write to url-index.jsonl              — instant
3. fetch content for each URL            — 2–3s per URL, blocking, parallel for batch
4. update index entries with content     — instant
5. queue pipeline in background          — instant, then exit
```

Steps 1–5 complete before the command returns. The user sees:

```
$ brana log https://linkedin.com/posts/...

  ✓ Logged
  ✓ Content fetched (linkedin, full)
  Pipeline queued.
```

```
$ brana log <url1> <url2> <url3>

  ✓ Logged 3 URLs
  ✓ Content fetched 3/3
  Pipeline queued.
```

### Pipeline runs in background

After `brana log` exits, the pipeline runs autonomously:

```
background:
  Tier 1 — score all new items (4-dimension rubric)
  Research expansion — enrich Tier 1 passes (HN, Reddit, related posts)
  Tier 2 — cluster by dimension
  → stops at cluster review gate
```

No blocking. No waiting. The user continues with other work.

### Checking pipeline state

> **Shipped** (t-1666): `brana knowledge next` reads `pipeline-state.json` and emits exactly one command (the next step to run).

```
$ brana knowledge next
```

Reports what's pending and what to do:

```
$ brana knowledge next

  Nothing pending.                          # nothing logged or all processed

  8 items fetching content...               # background fetch in progress
  Run again in a moment.

  Tier 1 running (4/8 scored)...            # pipeline mid-run

  Pipeline complete.                        # manual gate reached
  1 cluster ready: agent-tooling (3 items)
  Run: brana knowledge process --report

  Draft ready for review:                   # Tier 3 complete
  brana-knowledge/drafts/2026-04-13-agent-tooling.md
  Accept: brana knowledge promote <path>
  Reject: brana knowledge reject <path>
```

### Full workflow diagram

```
brana log <url(s)>
  │
  ├── fetch content (inline, 2–3s)
  │
  └── background ──────────────────────────────────────────┐
                                                           │
      Tier 1: score items                                  │
          ↓ pass                                           │
      Research expansion                                   │
          ↓                                                │
      Tier 2: cluster                                      │
          ↓                                                │
      ── GATE: brana knowledge next ──────────────────────┘
          "cluster ready → brana knowledge process --report"

      YOU: review clusters, pick topic to draft
          ↓
      Tier 3: brana knowledge process --draft <topic>
          ↓
      ── GATE: brana knowledge next ──────────────────────
          "draft ready → brana knowledge promote <path>"

      YOU: read draft, accept/reject/edit
          ↓
      brana knowledge promote <path>
          ↓
      dimension doc updated + reindex → ruflo
```

### Your two manual touchpoints

| Gate | Command | Decision |
|------|---------|---------|
| After Tier 2 | `brana knowledge process --report` | which clusters to draft |
| After Tier 3 | `brana knowledge promote / reject` | accept or reject draft |

Everything else is automated. You interact with the pipeline only when it needs a judgment call.

## Challenger findings (2026-04-13)

| # | Score | Finding | Resolution |
|---|---|---|---|
| 1 | 4 | Task→research is the dangerous mis-route direction; doc said opposite | Fixed in routing behavior — non-URL/non-feed sources always triage |
| 2 | 4 | Pipeline state is URL-keyed; non-URL inputs (transcripts, emails) break the schema | Fixed — `PipelineItem` type specified in design decision §2 |
| 3 | 3 | Triage list has no enforcement; cap is advisory | Fixed — hard cap at 20, expiry writes back to state, `--count` flag |
| 4 | 3 | Unified insights blends different quality levels without labeling | Fixed — provenance labels added per section from day one |
| 5 | 3 | Step 3 (intent wiring) shipped before step 4 (triage CLI) exists | Fixed — step order corrected, triage CLI is now step 3 |
| 6 | 3 | "~70% heuristic accuracy" untested on real corpus | Added to risks — validate offline before wiring into production |
| 7 | 2 | ADR listed last; should be first per DDD lifecycle | Fixed — ADR is now step 1 |
| 8 | 2 | `brana knowledge express` trigger mechanism undefined | Added to risks — interactive prompt + `claude -p` shell-out |
| 9 | 1 | `content_quality: fetchable` defined but never acted on | Renamed to `PublicUnfetched` for honesty; no fetch step scheduled yet |
| 10 | 1 | inbox/ filename convention has no enforcement | Acknowledged — lives in this doc only; will surface in `brana triage --help` |
