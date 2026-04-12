# Inbox → Dimensions Pipeline — Shape

> Brainstormed 2026-04-09. Status: **shape / brainstorm only — no implementation.**
> Upstream findings: [`../research/2026-04-08-cc-alignment-findings.md`](../research/2026-04-08-cc-alignment-findings.md) §D10 + second addendum.
> Companion shape doc: [`memory-consolidation-kairos.md`](./memory-consolidation-kairos.md) — the Lint + Heal job that cleans whatever this pipeline produces.
> Motivating methodology: Karpathy's Living Knowledge Base infographic (Sources → raw/ → Wiki → Q&A → Output).
> Layer distinction: [`feedback_layer1-vs-layer2.md`](~/.claude/projects/-home-martineserios-enter-thebrana-thebrana/memory/feedback_layer1-vs-layer2.md). **This pipeline operates entirely on Layer 2 (brana's work).** Brana OS rules and hooks (Layer 1) govern *how* the pipeline runs, but the content flowing through is Layer 2.

## Problem

Raw sources accumulate in brana faster than manual triage can turn them into Layer 2 knowledge artifacts (dimensions, research docs, feature briefs). The user has explicitly chosen Karpathy's methodology — *"You never write the wiki. The LLM writes everything. You just steer"* — for Layer 2. The question is how brana OS enforces that workflow.

**Current state (audited 2026-04-09):**

| Input source | Count | Current flow | Bottleneck |
|---|---|---|---|
| URLs in event log | **220 unique** (200 LinkedIn, 14 GitHub, 6 misc) | `/brana:log` writes entry → maybe creates a research task → research task sits → maybe promoted to dimension | URLs accumulate faster than manual research; most never become dimension content |
| `thebrana/inbox/` files | 25 files across 5 subfolders | Manual processing per file — no standard pipeline | Mixed content (client PDFs, audio, SSH keys) — not all are knowledge inputs |
| `brana-knowledge/inbox/` | separate directory, untracked state | Untracked — no one knows what's in it | Discovered during audit, needs triage |
| Feed entries (`brana feed poll`) | unknown — `brana feed` exists but polling cadence unclear | RSS/Atom items land somewhere, likely event log | No standard routing to dimensions |
| Gmail newsletters (`brana inbox poll`) | multi-account IMAP — volume unknown | Entries land in inbox state, manual review | Bottleneck identical to URLs — accumulate, manual triage required |
| Audio transcriptions (`brana transcribe`) | ~4 audios in `audios_pollo/` | Manual transcription triggers, result is a text file in inbox | No pipeline from transcript to dimension |
| Research output from `/brana:research` | 7 research docs total | Skill-driven; writes to `docs/research/`; sometimes promoted | Skill works but is on-demand only — doesn't process the backlog |

**The signal:** LinkedIn URL accumulation is **the dominant bottleneck** — 91% of raw source volume is LinkedIn posts in the event log. Everything else is secondary. Any pipeline design should solve LinkedIn first and generalize later.

**The frame:** Karpathy's pipeline is `Sources → raw/ → Wiki → Q&A → Output`. Brana has `Sources → event log / inbox/ / feed / gmail → ??? → dimensions / research docs / feature briefs`. The `???` is missing.

## Scope — what's in and what's out

### In scope

- **URL stream** from `/brana:log` (LinkedIn, GitHub, blog posts, research papers) → dimension drafts
- **Feed entries** from `brana feed poll` → same
- **Gmail newsletters** from `brana inbox poll` → same
- **Transcribed audio** from `brana transcribe` (user-triggered, output text) → if the content is knowledge-relevant, same
- **`brana-knowledge/inbox/`** — files dropped here for brana-knowledge processing → dimension drafts
- **Research questions** that surface during sessions but don't have a current answer → routed to the pipeline for answering

### Out of scope

- **Client-specific operational artifacts** — `thebrana/inbox/greencode/*.pdf`, `computo_chicho/*.pdf`, `papa_apelacion_casanovas/` — these are client work product, not brana knowledge. Should be routed to the respective client's project, not to `brana-knowledge/dimensions/`.
- **Credentials and keys** — `ssh_oracle_keys/` — never touched by this pipeline.
- **Session patterns** — handled by `/brana:close` already. This pipeline is about *external* sources, not *internal* session output.
- **Layer 1 artifacts** — rules, CLAUDE.md, hooks.json, ADR decisions. The pipeline never writes to these.
- **Accepted dimension docs** — the pipeline writes *drafts*, not final dimensions. Draft-to-accepted transition is a separate ritual (see Key design decisions §4).
- **Fine-tuning data collection** — Karpathy mentions fine-tuning in the "looking ahead" section. Out of scope for this doc.

### Scope boundary: `thebrana/inbox/` vs `brana-knowledge/inbox/`

Two inbox locations exist. Rule proposal:

- **`thebrana/inbox/`** = per-project scratch. Mixed content. Routed to the right client project or brana-knowledge by humans. The pipeline only reads items explicitly tagged or moved into `brana-knowledge/inbox/`.
- **`brana-knowledge/inbox/`** = the *only* location the pipeline auto-processes. User moves things here to say "this is for the wiki."

This is a soft router: human drops a file in `thebrana/inbox/`, decides "this is knowledge," moves it to `brana-knowledge/inbox/`, pipeline picks it up. Low complexity, clear authority, no automatic cross-contamination between client work and brana's own knowledge.

## What Karpathy's pipeline looks like (reference)

For orientation — the target we're mapping to:

```
Sources (articles, papers, repos)
    ↓
raw/ (unprocessed files stored as-is)
    ↓  [LLM]
WIKI (.md knowledge base + backlinks + concept categories + auto-maintained index)
    ↓  [query]
Q&A Agent (against full wiki, no RAG)
    ↓  [render]
Output (markdown files, slide decks, plots)
    ↓  [filed back — knowledge compounds]
back into WIKI
```

Support layer: Lint + Heal (our sibling D2 shape doc), CLI tools, Obsidian (brana uses VS Code instead).

Core insight applied to Layer 2: the user doesn't write dimensions or research docs by hand — the LLM drafts them, the user steers via review.

## Proposed shape — four options

The options differ in **how much automation sits between a raw source landing and a dimension-doc draft existing**.

### Option 1 — Full automation with milestone review

**What:** Every source lands, gets auto-processed by a scheduled skill/job, produces a draft dimension doc in `brana-knowledge/drafts/`. Human reviews the whole batch weekly via `/brana:review`. No per-item human touch between "URL logged" and "draft written."

**Flow:**
1. Source arrives (via `/brana:log`, feed, gmail, or `brana-knowledge/inbox/` drop)
2. Scheduled job (nightly or 4x/day) runs: fetches unprocessed items, clusters by topic (grep + filename heuristics, no LLM), for each cluster calls LLM to draft a dimension addition
3. Draft lands in `brana-knowledge/drafts/YYYY-MM-DD-topic-slug.md` with `status: draft` frontmatter + source citations + LLM-written body
4. Weekly `/brana:review` surfaces drafts as a batch
5. User marks drafts as: **accept** (move to `brana-knowledge/dimensions/`), **merge into existing** (update an existing dimension with the draft content, archive the draft), **reject** (archive the draft), **defer** (leave in drafts/)

**Cost:**
- ~4 hours: scheduled job + clustering logic + draft writer
- ~2 hours: draft frontmatter spec + staging directory + promotion CLI
- ~3 hours: `/brana:review` integration to surface drafts
- ~2 hours: tests + dry-run mode
- Total: **~11 hours**
- Ongoing: token cost per scheduled run (unknown, depends on batch size)

**Pros:**
- **Closest match to Karpathy's vision.** LLM writes everything; human only steers at milestones.
- **Solves the accumulation bottleneck.** 220 URLs in the event log get processed without manual triage per-URL.
- **Compounding effect** — once running, the knowledge base grows without explicit attention.
- **Clear dependency structure** — inputs enter, drafts exit, review is the gate.

**Cons:**
- **Draft quality depends entirely on LLM.** Bad clustering or hallucinated content compounds if review cadence slips.
- **Review backlog risk.** If the user misses a weekly review, drafts pile up. `/brana:review` becomes a chore.
- **Staging directory can fork the knowledge base.** Drafts exist in a liminal state — indexed by some searches, not by others.
- **Token cost.** Unclear — depends on LinkedIn post volume, clustering granularity, batch size.
- **Clustering is hard.** 220 LinkedIn URLs across ~15 distinct topics (memory, agents, CC patterns, ontology, etc.) — grep-based clustering may miss the right grouping.

**Risk:** Medium. Needs strong rollback semantics, strong review discipline, and a way to mark drafts as "bad cluster, redo" without losing the original source pointers.

### Option 2 — Batch-assisted (clustering automated, drafting on approval)

**What:** Same as Option 1 for the clustering phase, but the LLM doesn't draft content until the human approves the *intent* of the cluster. Adds a one-click "yes, draft this" gate between cluster formation and draft writing.

**Flow:**
1. Source arrives (same as Option 1)
2. Scheduled job clusters sources by topic (grep + heuristics)
3. **New step:** the job produces a "cluster report" — a markdown file listing each cluster with its sources and a one-line LLM-generated summary ("these 7 posts are about agent memory"). No drafts written yet.
4. Weekly `/brana:review` surfaces the cluster report
5. User picks clusters to draft: checkbox per cluster via AskUserQuestion
6. For approved clusters, LLM drafts dimension content; drops in `brana-knowledge/drafts/`
7. Second review (next week or on-demand) decides accept/merge/reject/defer for each draft

**Cost:**
- ~5 hours: clustering job + cluster report generator + AskUserQuestion integration
- ~3 hours: draft writer (invoked per-cluster after approval)
- ~2 hours: review flow + tests
- Total: **~10 hours**
- Ongoing: lower token cost than Option 1 (only approved clusters get drafted)

**Pros:**
- **Human in the loop at intent-level**, not at per-item-level. Preserves steering without pre-approving every draft line.
- **Lower token cost** — only approved clusters consume LLM drafting budget.
- **Better clustering feedback loop** — if clusters look wrong in the report, user says no before tokens are spent on bad drafts.
- **Two-stage review is natural** — cluster approval is fast, draft review is deeper.

**Cons:**
- **Two reviews instead of one** — review friction is higher per cycle.
- **Cluster-to-draft lag** — source lands, next review happens, cluster approved, drafts produced next run. Weeks of latency between source and draft.
- **Still has the staging directory and review-backlog risks from Option 1.**

**Risk:** Low-medium. Extra review step catches bad clusters before LLM spends tokens.

### Option 3 — Per-source triage (current flow, faster)

**What:** Keep the current manual-triage model, but add tooling to make it fast. No auto-clustering, no auto-drafting. Just a skill/CLI that lets the user rapidly process the event log backlog.

**Flow:**
1. Source arrives (same)
2. `brana inbox triage` CLI (or `/brana:triage` skill) shows the next 10 unprocessed sources with title/snippet
3. User picks actions per source: skip / tag / research-task-create / cluster-with-existing / draft-now
4. "Draft-now" invokes `/brana:research` on that source; result goes to `docs/research/`
5. Periodic (weekly?) skill promotes research docs to dimension drafts if the topic is stable

**Cost:**
- ~3 hours: triage CLI (list unprocessed sources, keyboard-fast actions)
- ~2 hours: promotion skill (research doc → dimension draft)
- ~2 hours: tests
- Total: **~7 hours**
- Ongoing: no new token cost; LLM calls are user-triggered via existing `/brana:research`

**Pros:**
- **Minimum automation risk.** Human in the loop at every step.
- **Doesn't require staging directory or review cadence changes.**
- **Reuses existing `/brana:research`** rather than building parallel drafting logic.
- **Low blast radius** — if the triage CLI is wrong, the user just doesn't use it.

**Cons:**
- **Doesn't implement Karpathy's methodology.** This is "faster manual," not "LLM writes everything."
- **Doesn't actually solve the accumulation bottleneck.** 220 URLs still need human attention per-item, even if each item is faster.
- **Breaks the user's explicit choice** of Karpathy's methodology. The user asked for this, not for faster manual work.

**Risk:** Very low. But it's answering a different question than the user asked.

### Option 4 — Hybrid: low-stakes automation, high-stakes manual

**What:** Automate the pipeline (Option 1 or 2) for specific source types, keep others manual. Route by source origin.

**Routing rules:**
- **LinkedIn URLs via `/brana:log`** → full automation (Option 1) — high volume, low stakes per-item
- **GitHub repo URLs** → batch-assisted (Option 2) — medium stakes, benefits from clustering
- **Feed entries (blogs, Substack, YouTube, GitHub releases)** → full automation — already structured, volume justifies it
- **Gmail newsletters** → full automation with extra filter (skip marketing) — high volume
- **Transcribed audio** → manual (Option 3 path) — voice memos need human context before they're dimension-worthy
- **`brana-knowledge/inbox/` file drops** → manual — the user explicitly moved it there with intent, so they're in the loop anyway
- **Research questions from sessions** → manual — these need context from the session

**Cost:**
- ~8 hours: automation pipeline for the automated sources (shared infrastructure with Option 1)
- ~3 hours: triage CLI for manual sources (from Option 3)
- ~3 hours: routing rules + source-type tagging + tests
- Total: **~14 hours**
- Ongoing: token cost for the automated portion only

**Pros:**
- **Matches actual risk profile** — LinkedIn posts get automation, personal audio notes get human attention.
- **Pragmatic.** Not dogmatic about Karpathy. Apply the methodology where it fits, skip it where it doesn't.
- **Tunable** — can move source types between lanes as operational experience accumulates.

**Cons:**
- **Most complex option.** Two parallel pipelines, routing logic, source-type tagging.
- **Hybrid systems fragment discipline** — easy to keep adding exceptions until neither lane works well.
- **Higher total effort.**

**Risk:** Medium. The automated lane has Option 1's risks; the manual lane has Option 3's limitations; the routing adds a new surface of its own.

---

## The sub-decisions inside the pipeline

Regardless of option, these need answers:

### SD-A — Staging directory location

Where do drafts live between creation and acceptance?

| Location | Pros | Cons |
|---|---|---|
| `brana-knowledge/drafts/` | Centralized, mirrors the dimension dir structure, easy to grep | New directory, needs gitignore decision (tracked or not?) |
| `brana-knowledge/dimensions/` with `status: draft` frontmatter | No new directory, drafts live next to accepted | Search results mix drafts and accepted; risk of a draft being cited as canon |
| `~/.claude/memory/drafts/` | Out of git, local-only, less noise | Loses drafts on machine migration; not backed up |
| Per-project `drafts/` subdirs inside each topic area | Granular, topic-local | Scattered, hard to review as a batch |

**Leaning (not decided):** `brana-knowledge/drafts/` in git, with `.gitignore` NOT excluding it. Tracked, visible, reviewable as a batch. Must coordinate with `memory-consolidation-kairos.md` (sibling shape doc) — L3/L4 of Lint + Heal also needs a staging directory.

### SD-B — Draft frontmatter convention

What metadata does a draft carry?

```yaml
---
status: draft                     # or: accepted, rejected, deferred, merged
created: 2026-04-09
sources:
  - url: https://...
    logged: 2026-04-08 12:34
  - url: https://...
    logged: 2026-04-08 12:35
cluster_topic: agent-memory
cluster_confidence: 0.7            # LLM self-rated (L3+) or omitted (L1/L2)
draft_author: llm                  # vs human
review_due: 2026-04-16             # a week after creation
promotion_target: dimensions/agent-memory.md  # or: new-dimension
---
```

**Open:** do we track `draft_author`? If yes, humans editing a draft flips it to `human` and implicitly promotes. If no, the `status:` field alone carries state.

### SD-C — Promotion ritual

How does a draft become an accepted dimension doc?

| Mechanism | What happens |
|---|---|
| **CLI command** | `brana knowledge promote <draft-path>` moves the file to `dimensions/`, updates frontmatter, updates spec-graph |
| **Skill step** | `/brana:review` batch-promotes approved drafts as part of its flow |
| **Manual mv** | Human moves the file with `git mv`, edits frontmatter to `status: accepted` |
| **Hook on edit** | Saving a draft with `status: accepted` triggers a hook that moves it |

**Leaning:** CLI command + `/brana:review` integration. Explicit, scriptable, testable. Manual mv as fallback. No hooks (ordering problem — see `feedback_hooks-cant-enforce-ordering.md`).

### SD-D — Review cadence

When does the human actually look at drafts?

| Cadence | Pro | Con |
|---|---|---|
| Weekly (via `/brana:review`) | Matches existing ritual | Backlog grows 7 days between reviews |
| On-demand (when draft count crosses a threshold) | Responsive to volume | Unpredictable — user never knows when review will trigger |
| Nightly digest (email/telegram) | Passive — user reads the list even if not in a session | Notification fatigue |
| After every scheduled pipeline run | Minimizes latency | Review happens as often as drafts are created; defeats the batching point |

**Leaning:** weekly via `/brana:review`, with a digest surfacing the draft count so the user knows review is waiting. If draft count >20, `/brana:review` becomes required-before-continuing-other-work.

### SD-E — Source-type handling

Which sources flow through the pipeline? Handled by the routing rules inside each option (especially Option 4). The sub-decision is:

- **All source types, one pipeline** (simple, bad match for actual variance)
- **Source-type lanes** (Option 4, most work)
- **Opt-in source types** (user adds source types to the automated lane as trust grows)

**Leaning:** opt-in. Start with one source type (LinkedIn URLs from event log) in the automated lane. Validate. Add the next source type. Don't try to handle everything on day one.

### SD-F — Interaction with `/brana:research`

`/brana:research` already exists as a skill. Is the pipeline a replacement or an extension?

| Relationship | What it looks like |
|---|---|
| **Replacement** | Pipeline makes `/brana:research` redundant — one path to draft dimension docs |
| **Extension** | Pipeline calls `/brana:research` internally as the "drafting" step |
| **Parallel** | `/brana:research` stays for on-demand work, pipeline handles batch |

**Leaning:** extension. Pipeline invokes `/brana:research` on approved clusters, captures the output, wraps it in draft frontmatter, drops in staging. Reuses the existing skill instead of forking its logic.

---

## Comparison matrix

| Dimension | Opt 1 Full | Opt 2 Batch | Opt 3 Fast manual | Opt 4 Hybrid |
|---|---|---|---|---|
| Effort (hours) | ~11 | ~10 | ~7 | ~14 |
| Ongoing token cost | Per-run | Per-approved-cluster | None (user-triggered) | Per-run for auto lane |
| Matches Karpathy's methodology | Yes | Mostly | **No** | For automated lane |
| Human touchpoints per week | 1 (review) | 2 (cluster + review) | Many (per-source) | 1 automated + many manual |
| Solves 220-URL accumulation | Yes | Yes (slower) | Partial | Yes for URLs specifically |
| Staging directory required | Yes | Yes | No | Yes for auto lane |
| Dependency on D2 (Lint + Heal) | Yes (L3+ shares staging) | Yes | No | Yes for auto lane |
| Rollback complexity | Medium | Medium | Trivial | Medium |
| Hallucination blast radius | Whole draft | Whole draft | N/A | Whole draft (auto lane only) |
| First-run time to value | Fast (one scheduled run) | Slower (two-stage review) | Slow (per-item) | Medium |
| Matches user's explicit choice | Yes | Yes (with gate) | No | Yes (partial) |

---

## Key design decisions (non-negotiable regardless of option)

1. **Layer 2 only.** Pipeline never writes to Layer 1 (rules, hooks, CLAUDE.md, ADRs, skill SKILL.md frontmatter, CLI source, MEMORY.md CRITICAL). Hard path allow-list enforced by CLI.
2. **Drafts are separate from accepted.** A draft is never read as canonical knowledge. `/brana:research` results, skill cross-references, and spec-graph all ignore draft-status files. Only accepted dimensions influence downstream behavior.
3. **Sources are first-class.** Every draft cites its sources (URLs, file paths, transcript timestamps). No orphan content. No "draft" without traceable provenance.
4. **Promotion is explicit.** A draft does not auto-promote to accepted. Even if the LLM is confident, a human decision (CLI, skill, or manual edit) is required to move it.
5. **Archive, don't delete.** Rejected drafts go to `brana-knowledge/drafts-archive/YYYY-MM-DD/`. Sources that produced bad drafts stay traceable.
6. **Idempotent processing.** Running the pipeline twice on the same source does not produce two drafts. Source-already-processed tracking required.
7. **Scheduler is the only auto-entry-point.** Pipeline never runs from inside a session. User can manually trigger via CLI.
8. **One source type at a time.** Opt-in expansion — start with LinkedIn URLs (the 91% case), add sources as trust grows.
9. **Dry-run mandatory on first deployment.** First run in any environment is dry-run only; writes a report of what *would* be drafted. User reviews, then enables real writes.
10. **Staging directory agreement with D2.** This doc and `memory-consolidation-kairos.md` must pick the same staging location (`brana-knowledge/drafts/`). Conflicting choices are a scope violation.

## Risks

| Risk | Applies to | Mitigation |
|---|---|---|
| Bad clustering produces incoherent drafts | 1, 2, 4 | Dry-run mode; cluster report reviewable before drafting (Opt 2); cluster_confidence threshold for draft creation |
| LLM hallucinates facts in drafts | 1, 2, 4 | Source citations mandatory; draft review required; archive-don't-delete |
| Draft backlog grows faster than review | 1, 4 | Hard cap on draft directory size; review-required-before-continuing if cap hit |
| Sources lost or duplicated | All | Idempotent processing; source tracking file; processed-sources index |
| Staging directory pollutes search results | 1, 2, 4 | Spec-graph excludes `drafts/`; `/brana:research` excludes `drafts/`; ruflo index excludes `drafts/` |
| Client-specific content leaks into brana-knowledge | All | Scope boundary: only `brana-knowledge/inbox/` auto-processed; `thebrana/inbox/` ignored |
| Pipeline touches Layer 1 by accident | All | Hard path allow-list + unit test that Layer 1 paths are rejected |
| Audio transcriptions without context become bad dimension drafts | 1, 4 (if audio included) | Exclude audio from auto-lane; route to manual via Option 3 flow |
| LinkedIn URL fetch rate limits | 1, 2, 4 | Throttle fetches; cache fetched content; accept partial batches |
| `/brana:research` semantics drift when invoked from pipeline | 2, 4 | Pipeline calls it with explicit `--mode=pipeline` flag so the skill knows the context |

## Open questions

1. **Does the user want drafts tracked in git, or local-only?** Git is reviewable across machines; local-only is quieter. Leaning git.
2. **What's the right batch size for a scheduled run?** Per-day, per-week, per-N-items? Depends on cadence of inputs.
3. **How does the pipeline interact with `/brana:harvest` (extracts post ideas from recent work — now lives in `ventures/linkedin/.claude/skills/harvest`, only available when operating inside that venture)?** Both read from the knowledge base but for different outputs. Should harvest read accepted dimensions only, or drafts too?
4. **Should the pipeline have its own agent** (like `debrief-analyst` for `/brana:close`), or reuse scout/research patterns?
5. **What's the error handling when a source URL 404s or LinkedIn rate-limits?** Defer the source, retry next run, or mark-as-failed after N attempts?
6. **Does the pipeline replace the existing "research task" pattern (t-NNN in the backlog with stream=research)?** Or do research tasks continue as a parallel manual flow?
7. **What's the token budget per run?** Without this, L3/L4 of D2 can't be scheduled together with this pipeline.
8. **Does the pipeline need to support removing sources from processing** (e.g., "this URL turned out to be spam, never draft from it")?

## Cheap audit (already partially run)

Numbers from 2026-04-09:

- `thebrana/inbox/`: 25 files across 5 subfolders, mixed content (client PDFs, audio, SSH keys) — most are out of scope
- Event log URLs: **220 unique**; **200 LinkedIn (91%)**, 14 GitHub, 6 misc — LinkedIn dominates
- `brana-knowledge/dimensions/`: 47 docs, all touched in last 60 days (actively maintained)
- `docs/research/`: 7 docs
- `docs/ideas/`: 25 docs
- `brana-knowledge/inbox/`: exists, contents untracked — needs its own audit

**What the numbers say:**

- **LinkedIn URL automation is the highest-leverage single change.** 91% of the volume, 0% of the existing automation.
- **`brana-knowledge/inbox/` needs triage before this pipeline is designed further** — it's a known-unknown.
- **Dimension docs are actively maintained** — adding automated drafts won't arrive into a stale base.
- **Ideas and research docs are small enough to review manually** — batching their creation is not the bottleneck.

**Audit items still to run (~10 min each):**

```
# What's in brana-knowledge/inbox?
ls -la /home/martineserios/enter_thebrana/brana-knowledge/inbox/ 2>/dev/null
find /home/martineserios/enter_thebrana/brana-knowledge/inbox/ -type f | head -20

# How many event log URLs already have a research task?
grep -oE "https://[^ )]+" ~/.claude/projects/*/memory/event-log.md | sort -u > /tmp/logged-urls.txt
grep -oE "https://[^ )]+" /home/martineserios/enter_thebrana/thebrana/.claude/tasks.json 2>/dev/null | sort -u > /tmp/task-urls.txt
comm -23 /tmp/logged-urls.txt /tmp/task-urls.txt | wc -l  # URLs in log but not in tasks

# What's the event log growth rate? (URLs per day over last 30 days)
awk '/^## 2026/{date=$2} /https:\/\//{print date}' ~/.claude/projects/*/memory/event-log.md | sort | uniq -c | tail -30
```

## Revised shape — tiered pipeline (post-challenge, 2026-04-10)

> Supersedes Options 1-4 above. Options 1-4 remain for historical context — they document the decision path that led here.
> Two challenge rounds surfaced that Options 1-4 conflated complexity (routing, source-type lanes, full automation) with scope. The tiered model simplifies by making the pipeline stages explicit and deferring novelty to v2.

### Architecture

```
Event log (LinkedIn URLs)
    ↓  [Scheduler — batch 50/run]
Tier 1 — Relevance filter
    LLM scores URL (title + first paragraph) against known dimensions
    score < 3  → mark irrelevant in event log, skip
    score ≥ 3  → advance to Tier 2
    ↓
Tier 2 — Cluster assignment
    LLM reads full content, assigns to nearest dimension or flags "new topic"
    Produces: weekly cluster report (dimension → list of URLs + confidence)
    ↓  [manual trigger — user approves clusters via /brana:review]
Tier 3 — Draft synthesis
    LLM synthesizes approved cluster into draft dimension addition
    Output: brana-knowledge/drafts/YYYY-MM-DD-{topic}.md
```

### Four locked decisions

| Decision | v1 | v2 |
|---|---|---|
| **Ruflo feedback loop** | Dropped — full re-eval each run | Domain+author composite key → auto-skip reruns |
| **Tier 1 entry point** | Scheduler only, batch cap 50 URLs/run | Same |
| **Tier 2→Tier 3 trigger** | Manual — user approves cluster report | Auto for high-confidence/known dimensions |
| **Architectural home** | `brana knowledge process` CLI subcommand | Same, additional flags |

### Why these decisions

- **Ruflo dropped from v1:** The feedback loop is the load-bearing novelty but sits on fragile infrastructure (CWD mismatch, SIGTERM bug, pattern-search broken). Deferring makes v1 testable in isolation. v2 adds the loop after one full cycle validates the pipeline works.
- **Scheduler, not hook:** KDD-7 — pipeline never runs inside a session. Hook-on-log fires synchronously. Manual CLI contradicts Karpathy's "LLM writes everything."
- **Batch cap 50:** 269-URL backlog at 50/run = 6 scheduler runs to drain, not one giant batch.
- **Manual Tier 2→3:** LLM confidence scores on this corpus are unvalidated. One full manual cycle (user reviews cluster report, approves, sees draft quality) calibrates whether auto-trigger is safe. This is the Option 2 pattern from the original comparison matrix.
- **CLI subcommand:** Single execution model (scheduler invokes it identically to manual invocation), testable in isolation, fits brana's existing scheduled job pattern. `/brana:research` stays interactive/on-demand; `brana knowledge process` is the batch pipeline.

### Draft frontmatter (SD-B — locked)

```yaml
---
status: draft                          # draft | accepted | rejected | deferred | merged
created: 2026-04-10
sources:
  - url: https://...
    logged: 2026-04-08 12:34
  - url: https://...
    logged: 2026-04-08 12:35
cluster_topic: agent-memory
draft_author: llm
review_due: 2026-04-17                 # 7 days after creation
promotion_target: dimensions/agent-memory.md   # or: new-dimension
---
```

`cluster_confidence` omitted from v1 (not calibrated). Added in v2 after manual cycle validates scores.

### Staging directory (SD-A — locked)

`brana-knowledge/drafts/` — git-tracked, separate from accepted dimensions. Spec-graph, `/brana:research`, and ruflo index all exclude this directory. Lint+Heal (D2) reaps stale drafts; pipeline creates them. Archive → `brana-knowledge/drafts-archive/YYYY-MM-DD/`.

### Hard cap

Draft count > 10 → next `/brana:review` is non-optional before pipeline runs again. (Shape doc had 20; challenger lowered to 10 — at 12-15 URLs/day, 3 missed weekly reviews produce 30-50 drafts, recreating the original triage problem.)

## Recommendation

**Tiered pipeline, v1 scoped to LinkedIn URLs.** Four decisions locked above. Write the feature brief next.

## Dependency on D2 (Lint + Heal)

This pipeline and the Lint + Heal shape doc are *paired*:

- **This pipeline produces drafts** that need linting (missing frontmatter, contradictions between drafts, duplicate topics across drafts)
- **Lint + Heal cleans drafts** that sit in staging too long (archive after N weeks, promote obvious candidates, flag stale drafts)
- **Both want `brana-knowledge/drafts/` as the staging location**
- **Both must agree on the promotion ritual** (CLI command, explicit user action, no auto-promotion)

**Conflicts to resolve before either is shipped:**
1. Who owns the draft schema? This doc should define the draft frontmatter; Lint + Heal should respect it.
2. Who owns draft archival? Pipeline creates; Lint + Heal reaps. Must not double-archive.
3. Who owns draft review? Pipeline surfaces new drafts; Lint + Heal surfaces stale drafts. Review UX must merge both streams.

These are addressed in `memory-consolidation-kairos.md` — if that doc picks incompatible answers, raise the conflict before either is implemented.

## What is NOT in scope of this doc

- Lint + Heal behavior — see `memory-consolidation-kairos.md`
- Session memory format — see `session-memory-cc-alignment.md`
- Ruflo infrastructure — see `ruflo-native-integration.md`
- Pattern store resilience — see `resilient-pattern-store.md`
- Client-specific content (all of `thebrana/inbox/` except what's explicitly moved to `brana-knowledge/inbox/`)
- Layer 1 artifacts (rules, hooks, CLAUDE.md, ADRs, CLI source)
- Fine-tuning data collection (Karpathy's "looking ahead" — out of scope)
- `/brana:harvest` (venture-scoped, `ventures/linkedin`) and `/brana:review` internal changes beyond the review-drafts integration
- Any implementation, skill file, CLI subcommand, scheduler entry, or spec-graph schema change

## Next concrete step

> Audit complete (2026-04-10). Options evaluated and challenged (2 rounds). Sub-decisions SD-A and SD-B locked. Tiered model chosen.

1. **Write feature brief** — `docs/architecture/features/inbox-to-dimensions-pipeline.md`. Include: tiered architecture, 4 locked decisions, draft frontmatter schema, CLI subcommand spec (`brana knowledge process`), scheduler config, acceptance criteria, test plan. Effort S (2h).
2. **Coordinate SD-A/SD-B with D2** — verify `memory-consolidation-kairos.md` agrees on `brana-knowledge/drafts/` location and promotion ritual before either feature brief is accepted.
3. **Do not edit code, CLI, or procedures** until feature brief is accepted.
