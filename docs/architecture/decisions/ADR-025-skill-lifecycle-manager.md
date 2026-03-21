# ADR-025: Skill Lifecycle Manager

**Date:** 2026-03-21
**Status:** accepted
**Tasks:** t-609, t-610, t-611, t-612, t-613

## Context

Brana has 30 skills, 11 agents, and 4 commands. Claude Code loads all skill descriptions into context at session start (~5.6KB). During complex builds, Claude loses awareness of niche skills — it won't suggest `/brana:meta-template` for a WhatsApp task or `/brana:financial-model` for a projection unless explicitly told.

Investigation (t-608) found: CC has no programmatic skill discovery API. ToolSearch only works for MCP tools. Skills are matched purely by Claude reading descriptions — a semantic, attention-dependent mechanism that degrades as conversation length grows.

Meanwhile, external skill marketplaces exist (GitHub, Vercel skills CLI, plugin marketplaces) but brana has no systematic way to discover, evaluate, or install skills from them except the manual `/brana:acquire-skills` flow.

## Decision

Build a **Skill Lifecycle Manager** as CLI subcommands under `brana skills`, with integration into `/brana:backlog start` and `/brana:build`. No MCP server — Claude calls the CLI via Bash.

### 1. Enriched Frontmatter Schema

Add three fields to all skill/command SKILL.md frontmatter:

```yaml
keywords: [whatsapp, meta, template, messaging, waba]
task_strategies: [feature, spike]
stream_affinity: [roadmap, research]
```

| Field | Type | Purpose | Values |
|-------|------|---------|--------|
| `keywords` | string[] | Semantic search terms for matching | Free-form, lowercase, domain-specific |
| `task_strategies` | string[] | Which build strategies this skill supports | `feature`, `bug-fix`, `refactor`, `spike`, `migration`, `investigation`, `greenfield` |
| `stream_affinity` | string[] | Which task streams this skill serves | `roadmap`, `bugs`, `tech-debt`, `docs`, `experiments`, `research` |

**Constraints:**
- `keywords` must have 3-10 entries per skill. Fewer = poor matching. More = noise.
- `task_strategies` and `stream_affinity` use the same enum values as tasks.json.
- Fields are optional — skills without them still appear in `list` but score lower in `suggest`.

### 2. CLI Subcommands

Two subcommands added to the existing `brana` Rust binary:

#### `brana skills suggest --task <id>`

**Input:** Task ID (reads metadata via `brana backlog get`).
**Output:** JSON array of ranked skill matches.

**Scoring algorithm:**

```
score = (keyword_overlap × 0.4) + (tag_overlap × 0.3) + (strategy_match × 0.2) + (stream_match × 0.1)
```

| Component | How it's computed | Weight |
|-----------|------------------|--------|
| `keyword_overlap` | `|task_description_words ∩ skill_keywords| / |skill_keywords|` | 0.4 |
| `tag_overlap` | `|task_tags ∩ skill_keywords| / |skill_keywords|` | 0.3 |
| `strategy_match` | `1.0 if task.strategy ∈ skill.task_strategies, else 0.0` | 0.2 |
| `stream_match` | `1.0 if task.stream ∈ skill.stream_affinity, else 0.0` | 0.1 |

**Thresholds:**
- Score > 0.7 → **suggest** (presented to user)
- Score 0.3–0.7 → **possible match** (mentioned but not recommended)
- Score < 0.3 → **gap** (no local skill covers this)

**Output format:**
```json
[
  {"name": "meta-template", "score": 0.85, "reason": "keywords: whatsapp, template; strategy: feature"},
  {"name": "respondio-prompts", "score": 0.72, "reason": "keywords: whatsapp, messaging; stream: roadmap"}
]
```

Returns top 3 matches. Empty array if no score > 0.3.

#### `brana skills search <query>`

**Input:** Free-text query string.
**Output:** Skills where `name`, `description`, or `keywords` contain the query terms.

Simpler than `suggest` — pure text matching, no task context needed. For human exploration.

### 3. Integration Points

#### `/brana:backlog start` (after strategy confirmation, before branch creation)

```
1. Call: brana skills suggest --task <id>
2. If results with score > 0.7:
   AskUserQuestion: "Skills that match this task: X (0.85), Y (0.72). Use any?"
3. If no results (all < 0.3):
   AskUserQuestion: "No local skill matches. Search external sources? [Yes/Skip]"
   → Yes: brana skills sources search "<task description keywords>"
4. Selected skills noted in task context for the build loop
```

#### `/brana:build` BUILD step (Medium/Large builds, before each subtask)

```
1. Call: brana skills suggest --task <subtask-id>  (or keyword-based if no subtask ID)
2. If match > 0.7: suggest
3. If gap: offer external search
```

**Not integrated into:** SessionStart hook (noise 80% of time), other skills.

### 4. External Sources CLI

Unified interface to query multiple external skill marketplaces.

#### `brana skills sources add <type> <url> [--name alias]`

Registers an external source in `system/skills/.sources.json`.

#### `brana skills sources list`

Shows registered sources.

#### `brana skills sources search <keyword>`

Queries all registered sources and returns aggregated results.

#### `brana skills sources remove <name>`

Removes a registered source.

**Source adapter types:**

| Type | Query method | What it searches |
|------|-------------|-----------------|
| `github-repo` | GitHub API: list repo tree, filter `SKILL.md` | A single repo's skills |
| `github-search` | GitHub API: code search | Cross-repo SKILL.md discovery |
| `marketplace` | HTTP fetch + parse `marketplace.json` | Plugin marketplace catalogs |
| `vercel-skills` | `npx skills find <keyword>` | Vercel skills registry |

**Config schema** (`system/skills/.sources.json`):
```json
{
  "sources": [
    {"name": "anthropic-official", "type": "github-repo", "url": "anthropics/skills"},
    {"name": "community", "type": "github-repo", "url": "alirezarezvani/claude-skills"},
    {"name": "plugin-marketplace", "type": "marketplace", "url": "https://raw.githubusercontent.com/anthropics/claude-code/main/.claude-plugin/marketplace.json"}
  ]
}
```

**Output format** (same for all source types):
```json
[
  {"name": "cloudflare-workers", "source": "anthropic-official", "description": "...", "url": "https://github.com/...", "stars": 1200}
]
```

User picks → `/brana:acquire-skills` handles install → immediately indexed by `suggest`.

### 5. What's NOT in scope (deferred)

| Feature | Why deferred | Revisit when |
|---------|-------------|-------------|
| **MCP server** | CLI via Bash achieves the same. Zero added capability. | 100+ skills or ToolSearch proves necessary |
| **auto_invoke_when** | Conflict risk between skills. Suggest-only first. | Suggest accuracy proven over 2-3 months |
| **SessionStart injection** | Noise 80% of time. Backlog start is the right moment. | Backlog start integration proves insufficient |
| **Scheduled discovery polling** | Ecosystem is nascent. On-demand is enough. | Marketplace matures with structured feeds |
| **Version tracking / freshness** | <10 acquired skills. Manual is fine. | Acquired count > 10 |
| **Quality scoring** | Need usage data first. | Hook-based usage tracking shipped |

## Alternatives Considered

### A. MCP Skill Registry Server (rejected)

Standalone MCP stdio server wrapping the CLI. Rejected because:
- Zero capability over CLI Bash calls
- Adds process management, protocol layer, maintenance surface
- ToolSearch already loads skill descriptions from plugin manifest

### B. Full 5-phase system (rejected after challenge)

Original design had MCP server, scheduled polling, auto-invoke rules, SessionStart hooks, freshness tracking. Challenger showed this was 3-4x too complex for 30 skills. Scoped down to CLI + suggest-only + on-demand sources.

### C. Description-only improvement (rejected)

Just rewrite skill descriptions with better keywords. Cheapest but:
- Doesn't solve the "Claude forgets" problem
- No structured search capability
- No external discovery

### D. Static routing table (rejected)

One JSON file mapping strategies → skills. Simple but:
- Doesn't scale to keyword matching
- Can't handle nuanced task context
- Requires central maintenance instead of per-skill declaration

## Consequences

- **Binary size:** Minimal — frontmatter parsing uses `serde_yaml` (already a dependency). GitHub API queries use `ureq` (already a dependency).
- **Context budget:** No change — enriched frontmatter fields are not loaded into CC context. Only existing `description` lines are loaded.
- **Maintenance:** Each skill author maintains their own `keywords`, `task_strategies`, `stream_affinity`. Drift is possible but contained per-skill.
- **External dependency:** `brana skills sources search` requires network access and `gh` CLI for GitHub queries. Graceful fallback if offline.
- **Skill discovery becomes active, not passive.** Instead of hoping Claude remembers a skill, the system explicitly recommends skills at the moment of task start.
