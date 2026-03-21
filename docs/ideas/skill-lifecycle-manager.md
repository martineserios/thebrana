# Skill Lifecycle Manager — Revised Design

> Brainstormed 2026-03-21. Challenged and revised same session.
> Status: ready for decompose.
> Absorbs: t-608 (skill routing), t-550 (gap detection), t-058 (marketplace research).

## Problem

Claude "forgets" about niche skills during complex builds. With 30+ local skills and hundreds available externally, there's no systematic way to:
1. Always load the right skill for a task
2. Keep the local skill library rich and up-to-date
3. Discover and acquire useful skills from external sources

## Vision

**Claude always has the perfect skill for each task, automatically.**

## Challenge Findings (applied)

Challenger stressed the 5-phase plan was 3-4x too complex for 30 skills. Key decisions:

| Original | Decision | Rationale |
|----------|----------|-----------|
| MCP server | **Killed** | Zero capability over CLI Bash calls. Claude calls `brana skills suggest` via Bash. |
| Scheduled discovery polling | **Reframed** | Not scheduled polling — unified CLI for on-demand marketplace queries. |
| auto_invoke_when rules | **Deferred** | Conflict risk. Ship suggest-only first, promote to auto-invoke after proven accuracy. |
| SessionStart hook injection | **Replaced** | Inject at `/brana:backlog start` only — the moment task context exists. |
| Full enrichment | **Kept** | keywords, task_strategies, stream_affinity worth the maintenance for structured search. |
| Freshness/versioning | **Deferred** | Revisit when acquired skill count justifies overhead. |

## Architecture (revised)

```
brana skills <subcommand>          ← CLI interface (no MCP server)
├── suggest --task t-123           ← recommend skills for a task
├── search "whatsapp template"     ← keyword search across local index
├── sources add <url>              ← register an external marketplace
├── sources list                   ← show registered sources
├── sources search "keyword"       ← query external marketplaces
└── (future: auto-invoke, freshness)
```

### Integration points

```
/brana:backlog start t-123
  │
  ├─ Read task context (tags, stream, strategy, description)
  ├─ Call: brana skills suggest --task t-123
  │   ├─ Local match found (score > 0.7):
  │   │   "Relevant skills: /brana:meta-template (0.85). Use it?"
  │   ├─ No local match (score < 0.3):
  │   │   "No local skill matches. Search externally? [Yes/Skip]"
  │   │   → Yes: brana skills sources search "task keywords"
  │   │   → Presents candidates → /brana:acquire-skills to install
  │   └─ Moderate match (0.3-0.7):
  │       "Possible match: /brana:respondio-prompts (0.5). Use it?"
  │
  ▼
/brana:build (proceeds with or without skill suggestion)
```

## Phase 1: Frontmatter Enrichment (S — 1 hour)

Add 3 new fields to all 30 skills + 4 commands:

```yaml
keywords: [whatsapp, meta, template, messaging, waba]
task_strategies: [feature, spike]
stream_affinity: [roadmap, research]
```

These power the `suggest` matching algorithm. Same sweep pattern as t-605 (effort frontmatter).

## Phase 2: CLI — `brana skills suggest` + `search` (M — half day)

### `brana skills suggest --task <id>`

1. Read task metadata via `brana backlog get <id>`
2. Scan all SKILL.md frontmatter (system/skills/ + system/skills/acquired/)
3. Score each skill:
   - Keyword overlap: task description words ∩ skill keywords → weight 0.4
   - Tag overlap: task tags ∩ skill keywords → weight 0.3
   - Strategy match: task strategy ∈ skill task_strategies → weight 0.2
   - Stream match: task stream ∈ skill stream_affinity → weight 0.1
4. Return top 3 with scores, sorted descending

### `brana skills search <query>`

Full-text search across skill name + description + keywords. Returns matching skills with relevance score.

### Implementation

Add to existing `brana` Rust CLI binary (system/cli/rust/). Two new subcommands under `brana skills`. Frontmatter parsing with `serde_yaml`. No external dependencies.

## Phase 3: `/brana:backlog start` Integration (S — 1 hour)

Update `/brana:backlog start` skill (SKILL.md) to add a step between strategy confirmation and branch creation:

```
After strategy confirmed, before branch creation:
1. Run: brana skills suggest --task <id>
2. If suggestions with score > 0.7:
   Present via AskUserQuestion:
   "Skills that match this task: /brana:X (0.85), /brana:Y (0.72). Use any?"
3. If no match > 0.3:
   "No local skill matches this task's context. Search external sources? [Yes/Skip]"
   → Yes: run brana skills sources search "<task keywords>"
4. Proceed to branch creation regardless of choice
```

Also update the `/brana:build` BUILD step to call suggest before each subtask (for Medium/Large builds with decomposed subtasks).

## Phase 4: External Sources — `brana skills sources` (M — half day)

Unified CLI interface to query multiple external skill marketplaces. Source-agnostic — each source is a plugin with a common query interface.

### Subcommands

```bash
brana skills sources add <type> <url> [--name alias]   # Register a source
brana skills sources list                                # Show registered sources
brana skills sources search "keyword"                    # Query all sources
brana skills sources remove <name>                       # Remove a source
```

### Source types

| Type | How it queries | Example |
|------|---------------|---------|
| `github-repo` | Lists SKILL.md files in a repo tree | `brana skills sources add github-repo anthropics/skills` |
| `github-search` | GitHub API code search | `brana skills sources add github-search "filename:SKILL.md stars:>50"` |
| `marketplace` | Parses marketplace.json | `brana skills sources add marketplace anthropics/claude-code` |
| `vercel-skills` | `npx skills find` wrapper | `brana skills sources add vercel-skills` |

### Config file

```json
// system/skills/.sources.json
{
  "sources": [
    {"name": "anthropic-official", "type": "github-repo", "url": "anthropics/skills"},
    {"name": "community-skills", "type": "github-repo", "url": "alirezarezvani/claude-skills"},
    {"name": "plugin-marketplace", "type": "marketplace", "url": "anthropics/claude-code"},
    {"name": "vercel", "type": "vercel-skills"}
  ]
}
```

### Query flow

```bash
$ brana skills sources search "cloudflare workers"

Searching 4 sources...

anthropic-official (github-repo):
  cloudflare-workers — "Cloudflare Workers deployment patterns" ★official

community-skills (github-repo):
  cf-workers-deploy — "Production wrangler config, D1 bindings" ★142

plugin-marketplace:
  (no matches)

vercel (vercel-skills):
  @secondsky/cloudflare — "Workers + Pages, KV, R2" 2.1K installs
```

User picks → `/brana:acquire-skills` handles install → immediately indexed by Phase 2.

## Deferred (documented for future)

### Auto-invoke (promote from suggest)

When `brana skills suggest` accuracy is validated over 2-3 months of usage, add `auto_invoke_when` frontmatter:

```yaml
auto_invoke_when:
  tags: [whatsapp, meta-template]
  stream: [roadmap]
  min_score: 0.9
```

Skills with proven high-confidence matches get auto-invoked. Start with the top 5 most-suggested skills. Keep the idea — defer execution.

### SessionStart injection

If `/brana:backlog start` integration proves valuable, extend to SessionStart hook for broader awareness. Only if the targeted injection isn't enough.

### Freshness & versioning

When acquired skill count exceeds ~10, add:
- VERSION files with source URL + hash
- `brana skills outdated` — compare against source repos
- Monthly quality review based on usage stats

### MCP server

If CLI Bash calls prove too slow or ToolSearch integration becomes necessary (e.g., 100+ skills), wrap the CLI as an MCP server. Architecture is trivial — the CLI does all the work.

## Tasks to create

| ID | Subject | Phase | Effort | Blocked by |
|----|---------|-------|--------|------------|
| new | Enrich skill frontmatter (keywords, strategies, streams) | 1 | S | — |
| new | Add `brana skills suggest` + `search` CLI subcommands | 2 | M | Phase 1 |
| new | Integrate skill suggestions into /brana:backlog start | 3 | S | Phase 2 |
| new | Add `brana skills sources` CLI for external marketplaces | 4 | M | — (independent) |

### Tasks absorbed

| Task | Action |
|------|--------|
| t-608 (investigation, completed) | Findings incorporated into this design |
| t-550 (gap detection in build) | Absorbed into Phase 3 (suggest at backlog start + build) |
| t-058 (marketplace research) | Absorbed into Phase 4 (sources CLI) |
