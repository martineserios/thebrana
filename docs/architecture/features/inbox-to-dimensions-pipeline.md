---
depends_on:
  - docs/ideas/inbox-to-dimensions-pipeline.md
  - docs/ideas/memory-consolidation-kairos.md
  - docs/research/2026-04-08-cc-alignment-findings.md
informs:
  - docs/reflections/ARCHITECTURE.md
  - brana-knowledge/dimensions/ (output target)
---
# Feature: Inbox → Dimensions Pipeline — Tiered Research

**Date:** 2026-04-12
**Status:** specced
**Task:** t-1113
**Effort:** L (~18h total: 3h pre-work complete, 11h implementation, 2h tests, 2h scheduler wiring)

## Problem

Raw sources accumulate in brana faster than manual triage can produce Layer 2
knowledge artifacts. The event log holds **269 unique URLs** (243 LinkedIn),
growing at ~12-15/day. None have been routed to `brana-knowledge/dimensions/`.
The user's chosen methodology is Karpathy's *"LLM writes everything, you just
steer"* — applied to Layer 2 only. The pipeline is the missing `???` between
`Sources → event log` and `→ dimensions`.

## Scope

**In scope (v1):** LinkedIn URLs from the event log only.
One source type to start — 91% of volume, clearest signal.

**Deferred to v2:**
- Ruflo feedback loop (auto-skip re-evaluated URLs by domain+author key)
- Auto-trigger for Tier 2→3 (currently manual)
- Other source types: feed entries, Gmail newsletters, audio transcripts, `brana-knowledge/inbox/` file drops

**Layer 2 only.** This pipeline never writes to Layer 1 artifacts:
`CLAUDE.md`, `rules/`, `hooks.json`, ADRs, skill frontmatter, CLI source,
`MEMORY.md` User Preferences section. Enforced via path allow-list in CLI.

**Writable paths (allow-list):**
```
brana-knowledge/drafts/                    ← Tier 3 output
brana-knowledge/drafts-archive/            ← rejected/stale drafts
~/.swarm/knowledge-pipeline-state.json    ← processed-URL index + cluster state
~/.swarm/knowledge-pipeline.lock          ← PID lock
~/.claude/knowledge-pipeline-report.md   ← cluster report (Tier 2 output)
```

## Architecture

```
Event log (~/.claude/projects/*/memory/event-log.md)
    ↓  [parse — extract LinkedIn URLs not in processed-index]
    ↓  [Scheduler — batch cap 50 URLs/run, nightly]
Tier 1 — Relevance filter
    Fetch URL title + first paragraph (HTTP HEAD + snippet)
    LLM scores relevance 1-5 against known dimension topics
    score < 3  → mark "irrelevant" in pipeline state, skip
    score ≥ 3  → mark "tier1-passed", advance to Tier 2 queue
    ↓
Tier 2 — Cluster assignment
    Fetch full content for each tier1-passed URL
    LLM assigns to nearest existing dimension OR flags "new-topic"
    Produces cluster report: ~/.claude/knowledge-pipeline-report.md
    State: URLs marked "tier2-clustered" with cluster_topic + dimension_target
    ↓  [manual gate — user reviews report, runs: brana knowledge process --draft <topic>]
Tier 3 — Draft synthesis
    LLM synthesizes all URLs in approved cluster into draft dimension addition
    Output: brana-knowledge/drafts/YYYY-MM-DD-{topic-slug}.md
    State: URLs marked "tier3-drafted", draft path recorded
```

## CLI subcommand: `brana knowledge process`

New subcommand in `brana-cli`. Single execution model — scheduler and user
invoke identically; no session-specific behavior.

### Flags

| Flag | Behavior |
|------|----------|
| `--tier1` | Run Tier 1 on next batch (≤50) of unprocessed LinkedIn URLs |
| `--tier2` | Run Tier 2 on all tier1-passed URLs not yet clustered |
| `--report` | Print current cluster report to stdout (Tier 2 state) |
| `--draft <topic-slug>` | Trigger Tier 3 for the named cluster (manual approval gate) |
| `--status` | Show pipeline state: counts by tier, draft dir summary |
| `--dry-run` | Print planned actions without writing; works with any flag |
| `--reset-url <url>` | Remove a URL from the processed index (reprocess next run) |

### State file: `~/.swarm/knowledge-pipeline-state.json`

```json
{
  "last_tier1_run": "2026-04-12T03:00:00Z",
  "last_tier2_run": "2026-04-12T03:05:00Z",
  "urls": {
    "https://www.linkedin.com/posts/...": {
      "status": "tier1-passed | irrelevant | tier2-clustered | tier3-drafted",
      "tier1_score": 4,
      "cluster_topic": "agent-memory",
      "dimension_target": "dimensions/21-memory-patterns.md",
      "draft_path": "drafts/2026-04-12-agent-memory.md",
      "logged_date": "2026-04-08"
    }
  }
}
```

Idempotency: URLs already in `urls` map are skipped. `--reset-url` removes
the entry to force reprocessing.

### Draft frontmatter (SD-B locked)

```yaml
---
status: draft
created: 2026-04-12
sources:
  - url: https://www.linkedin.com/posts/...
    logged: 2026-04-08
  - url: https://www.linkedin.com/posts/...
    logged: 2026-04-09
cluster_topic: agent-memory
draft_author: llm
review_due: 2026-04-19
promotion_target: dimensions/21-memory-patterns.md
---
```

`cluster_confidence` omitted in v1 — LLM scores on this corpus are uncalibrated.
Added in v2 after one manual cycle validates score quality.

### Staging directory (SD-A locked)

`brana-knowledge/drafts/` — git-tracked, reviewed as a batch.
Excluded from: spec-graph traversal, `/brana:research` cross-refs, ruflo index.
Lint+Heal (D2 / t-1075) reaps stale drafts; this pipeline creates them.
Rejected or stale → `brana-knowledge/drafts-archive/YYYY-MM-DD/`.

### Hard cap

Draft count > 10 → pipeline prints warning and exits 1 on next `--tier1` or
`--tier2` invocation. Clears only after user runs `brana knowledge process --status`
acknowledging the backlog (sets `draft_cap_acknowledged: true` in state file).
This forces a review session before more drafts are produced.

## Promotion ritual (SD-C locked)

```bash
brana knowledge promote <draft-path>
```

Moves draft to `brana-knowledge/dimensions/` (or merges into existing file if
`promotion_target` is an existing path). Updates frontmatter to `status: accepted`.
Updates spec-graph. Logs to pipeline state.

Manual `git mv` + frontmatter edit is the fallback. No hooks (hooks can't enforce
ordering — see `feedback_hooks-cant-enforce-ordering.md`).

## Scheduler integration

```json
{
  "id": "knowledge-pipeline-tier1",
  "command": "brana knowledge process --tier1",
  "schedule": "0 3 * * *",
  "enabled": false,
  "description": "Nightly Tier 1 relevance filter — LinkedIn URLs, batch 50"
}
```

`enabled: false` on first deploy. Enable manually after dry-run passes clean.

Tier 2 does NOT run on a scheduler — it runs after Tier 1 completes (same
scheduler invocation, sequential: `--tier1 && --tier2`). This keeps cluster
state consistent within a single run.

## Content sourcing — locked (2026-04-12)

**Option (a): event log text only. No HTTP fetch.**

LinkedIn post URLs are behind a login wall — unauthenticated fetch returns a login
redirect. v1 uses signals already present in the event log entry:

```
- 21:14 — https://www.linkedin.com/posts/walid-boulanouar_everyone-using-claude-code-is-paying-for-share-... #claude-code #cost
```

Extracted fields:
- **author**: URL path segment before first `_` (`walid-boulanouar`)
- **title_signal**: URL path segment between first `_` and `-share-` or `-ugcPost-`, hyphens → spaces
- **tags**: hashtags the user added at capture time (`#claude-code #cost`)

This is sufficient for relevance scoring (Tier 1) and cluster assignment (Tier 2).
Full content fetch deferred to v2 (t-1144) pending a LinkedIn auth strategy.

## LLM call mechanism — locked (2026-04-12)

**Shell out to `claude` CLI. No Anthropic API key.**

```rust
std::process::Command::new(resolve_claude_binary())
    .args(["--print", "--output-format", "json", prompt_text])
    .output()
```

Binary resolution order (same pattern as `resolve-brana.sh`):
1. `$CLAUDE_PLUGIN_DATA/claude`
2. `~/.local/bin/claude`
3. `PATH`

Cron-safe: explicit path resolution, no shell PATH dependency.

### Output format differentiation

Tier 1 and Tier 2 instruct the model to respond with JSON only. The Rust implementation
parses the CLI envelope's `result` field via `call_claude_json` (strips code fences,
calls `serde_json::from_str`).

**Model assignment:**
- **Tier 1** uses `claude-haiku-4-5-20251001` (passed as `model` arg to `call_claude_json`).
  Relevance scoring is a lightweight classification task — Haiku is sufficient and ~10× cheaper.
- **Tier 2** uses the session default model (Sonnet). Cluster assignment requires more
  reasoning about dimension fit.
- **Tier 3** uses `call_claude_text` with the session default (Sonnet/Opus). Prose drafting
  needs the highest quality.

Tier 3 instructs the model to return markdown prose. It uses `call_claude_text` instead —
`call_claude_json` would always fail on unstructured output. This distinction is critical:
**never route a prose-returning tier through `call_claude_json`.**

## Tier 1 LLM prompt (spec)

```
You are classifying a LinkedIn post for relevance to a personal knowledge base
about AI systems, agent design, developer tooling, and knowledge management.

Author: {author}
Title signal: {title_signal}
Tags: {tags}

Score the relevance 1-5 where:
1 = personal update, marketing, unrelated
2 = tangentially related, low signal
3 = relevant, worth reading
4 = directly relevant to known topics (memory, agents, CLI tooling, CC patterns)
5 = high-signal, likely new dimension content

Known dimension topics: {dimension_slugs}

Respond with JSON only: {"score": N, "reason": "one sentence"}
```

## Tier 2 LLM prompt (spec)

```
You are assigning a LinkedIn post to the nearest topic in a knowledge base.

Author: {author}
Title signal: {title_signal}
Tags: {tags}

Existing dimension topics:
{dimension_list_with_slugs}

Assign this post to the best-matching dimension, or flag as "new-topic" if it
doesn't fit any existing dimension.

Respond with JSON only:
{"dimension_target": "slug or new-topic", "cluster_topic": "short label", "reason": "one sentence"}
```

## Tier 3 LLM prompt (spec)

```
You are writing an addition to a knowledge base dimension document.

Dimension: {dimension_name}
Existing content summary: {first_500_chars_of_dimension}

Source posts ({n} posts, approved cluster: {cluster_topic}):
{url_list_with_content}

Write a new section to add to this dimension. Use the same writing style as the
existing content. Cite each source post inline as [Author, date].
Do not repeat content already in the dimension. Focus on new insights only.

Output: markdown section only (no frontmatter, no preamble).
```

## `/brana:review` integration

`/brana:review` weekly surfaces:
1. Count of drafts in `brana-knowledge/drafts/` needing review
2. Link to cluster report (`~/.claude/knowledge-pipeline-report.md`)
3. Prompt: "Promote, merge, reject, or defer each draft?"

Promotion via `brana knowledge promote <path>` or manual mv.

## Non-negotiables

1. **Layer 2 only.** Hard path allow-list; exits non-zero on any write outside it.
2. **Idempotent.** Same URL processed twice → same output, no duplicates.
3. **`--dry-run` on every flag.** First deployment always dry-run.
4. **Lock file.** `~/.swarm/knowledge-pipeline.lock`. Stale PID detection same as lint-heal.
5. **Archive, don't delete.** Rejected drafts → archive dir. Sources traceable.
6. **Manual Tier 2→3 in v1.** No auto-synthesis without explicit `--draft <topic>`.
7. **Scheduler is the only automated entry point.** Never wired to a session hook.
8. **Draft cap enforced at 10.** Pipeline halts if cap hit; clears on acknowledgement.

## Files

| File | Change |
|------|--------|
| `system/cli/rust/crates/brana-cli/src/knowledge.rs` | New — `process` subcommand (tier1/tier2/tier3/report/status/promote/reset-url) |
| `system/cli/rust/crates/brana-core/src/knowledge_pipeline.rs` | New — state file R/W, URL extraction from event log, allow-list enforcement |
| `system/scheduler/scheduler.template.json` | +`knowledge-pipeline-tier1` job, `enabled: false` |
| `system/state/scheduler.json` | Same addition |
| `brana-knowledge/drafts/` | New directory (empty, with `.gitkeep`) |
| `brana-knowledge/drafts-archive/` | New directory (empty, with `.gitkeep`) |

## Subtasks

| ID | Subject | Effort |
|----|---------|--------|
| t-1113-a | `brana-core`: knowledge_pipeline.rs — state R/W, URL extraction, allow-list | M |
| t-1113-b | `brana-cli`: `brana knowledge process --tier1` (Tier 1 loop + LLM call) | M |
| t-1113-c | `brana-cli`: `brana knowledge process --tier2` (Tier 2 loop + cluster report) | M |
| t-1113-d | `brana-cli`: `brana knowledge process --draft` (Tier 3 synthesis) | S |
| t-1113-e | `brana-cli`: `brana knowledge promote` (promotion ritual) | S |
| t-1113-f | Scheduler entry + dry-run validation | XS |
| t-1113-g | `/brana:review` integration (draft count + report surface) | S |

## Out of scope (v1)

- Ruflo feedback loop (domain+author auto-skip) → v2
- Auto-trigger Tier 2→3 → v2
- Feed entries, Gmail newsletters, audio, `brana-knowledge/inbox/` → v2
- LLM confidence scoring on clusters → v2 (after manual cycle calibrates)
- `/brana:research --mode=pipeline` flag → not needed; CLI subcommand replaces this
