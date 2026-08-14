# Skill Auto-Router

> **Superseded by [Brana Operating Model](brana-operating-model.md).** This doc is preserved for historical context.

> Brainstormed 2026-04-01. Status: idea. Supersedes dynamic-skill-routing.md (t-608).
> Challenger review 2026-04-01: RECONSIDER → revised to dual-path (CLI fast + HNSW smart).
> Simplification pass 2026-04-01: merged to single entry point, single routing path, 2+1 phases.

## Problem

Brana has 30+ skills but the user must know which one to invoke. No auto-matching, no
discovery of missing skills, no learning from past routing decisions. `brana skills suggest`
exists (Rust CLI, 4-factor scoring) but nothing calls it. Frontmatter is enriched but
underutilized. External skill ecosystems (skills.sh, anthropics/*, community repos) are
unreachable from inside a session.

## Core Decision

**Route or recruit.** When work arrives, the system matches it to the best local skill.
When no local skill matches, that failure IS the discovery trigger — search marketplaces,
evaluate candidates, offer install. Routing enables discovery.

## Architecture (simplified 2026-04-01)

> Challenger review → simplification brainstorm → single entry point, single routing path.
> 37ms is imperceptible. One path beats two code paths every time.

### Single-Path Routing

```
ENTRY
  brana backlog start <task-id | "freeform text">
  /brana:do "text"  (alias → backlog start "text")
         |
         v
  ROUTING (one path)
  memory_search(namespace: "skills", query: "{task subject + tags | freeform text}")
  ruflo HNSW, 384-dim, 37ms, semantic matching
         |
    ruflo down?
    └── YES → brana skills suggest (CLI fallback, <1ms, keyword scoring)
         |
    confidence score
  +------+--------+--------+
  > thresh  mid-range  < thresh
  SUGGEST   MENTION    DISCOVERY
  (offer)   (note)     (marketplace)
                            |
                            v
                  /brana:acquire-skills (auto-triggered)
                  Source-tiered trust model
```

### One entry point, two names

| Command | Input | Behavior |
|---------|-------|----------|
| `brana backlog start t-200` | Task ID | Read task metadata → `memory_search(ns: "skills", query: "{subject} {tags}")` |
| `brana backlog start "fix auth bug"` | Freeform text | Create quick task → `memory_search(ns: "skills", query: "fix auth bug")` |
| `/brana:do "fix auth bug"` | Alias | Calls `backlog start "fix auth bug"` |

Same routing code for both. The only difference: task ID has richer metadata (tags, strategy, stream) so the query is more specific.

### Graceful degradation

| Condition | Behavior |
|-----------|----------|
| Ruflo up, skills indexed | `memory_search` — full semantic matching |
| Ruflo up, skills not indexed | Index on first call, then search |
| Ruflo down | `brana skills suggest` CLI — keyword scoring, works offline |
| Both down | Claude matches from skill descriptions in context (current behavior) |

### Fast pre-filter: hooks_route

`hooks_route` runs at 2ms with 12 hardcoded task patterns + learned patterns.
Returns task-type classification (bugfix-task, feature-task, security-task, etc.).

Use as pre-filter before Layer 1:
1. `hooks_route(task)` -> task type classification (2ms)
2. If classification is high-confidence -> narrow Layer 1 search to that category
3. If low-confidence -> full Layer 1 search across all skills

`hooks_route` learns from routing outcomes over time (built-in `loadLearnedPatterns()`).

### Ruflo tools used

| Tool | Layer | Purpose |
|------|-------|---------|
| `memory_store(ns: "skills")` | 1 | Index skill frontmatter as searchable entries |
| `memory_search(ns: "skills")` | 1 | Semantic skill matching (HNSW, 384-dim, 37ms) |
| `hooks_route` | pre-filter | Fast task-type classification (2ms, learns) |
| `memory_search(ns: "all")` | 3 | Cross-client pattern matching |
| `hooks_intelligence_pattern-search` | 3 | Pattern recall for skill-task associations |
| `hooks_model-route` | enhance | Pick model tier for matched skill (haiku/sonnet/opus) |

### What already exists

| Component | Status | Gap |
|-----------|--------|-----|
| `brana skills suggest --task <id>` | Implemented (Rust CLI) | Not called from skills or hooks |
| `brana skills search <query>` | Implemented | Not wired to routing |
| 30+ skills with frontmatter | Enriched | Not indexed in ruflo |
| `/brana:acquire-skills` | Implemented | Manual only, no auto-trigger |
| ADR-025 | Designed | auto_invoke_when deferred |
| `hooks_route` | Working (ruflo, 2ms) | Routes to agent types, not skills |
| `agentdb_semantic-route` | Broken | "SemanticRouter not available" — skip |
| `agentdb skill_create/skill_search` | Available | Not tested for brana skills |

## Skill Index Pipeline

At session start (or when skills change):

```
For each SKILL.md in system/skills/*/SKILL.md:
  -> Parse frontmatter: name, description, keywords, task_strategies, stream_affinity, group
  -> Compose embedding text: "{name} {description} {keywords} {strategies}"
  -> memory_store(
       namespace: "skills",
       key: "skill:{name}",
       value: {"name": ..., "description": ..., "keywords": [...], "strategies": [...],
               "stream": [...], "group": ..., "effort": ...},
       tags: ["source:brana", "group:{group}", ...strategies],
       upsert: true
     )

For each SKILL.md in system/skills/acquired/*/SKILL.md:
  -> Same, but tags: ["source:external", "installed:{date}"]

For client-specific skills discovered via project scanning:
  -> Same, but tags: ["source:project:{client}"]
```

Re-index trigger:
- Session-start hook (diff SKILL.md mtimes vs last index)
- `brana skills index` CLI command (manual)
- Post-install in `/brana:acquire-skills`

## Routing UX

### Mode A: Silent routing (confidence > configurable threshold, default 0.9)

User says "fix the auth bug". System silently routes to `/brana:build` with
strategy `bug-fix`. User sees the skill execute, never interrupted.

### Mode B: Suggestion (confidence between suggest and silent thresholds)

```
Matched: /brana:build (strategy: bug-fix, confidence: 0.72)
Also possible: /brana:research (if you want to investigate first)
[Run build] [Run research] [Something else]
```

### Mode C: Discovery (confidence below suggest threshold)

```
No skill matches well (best: /brana:build at 0.31).
Found 2 external candidates:
  - monitoring-setup (skills.sh/official) -- scaffolds Grafana/Prometheus configs
  - observability-agent (community) -- quarantine required
[Install monitoring-setup] [Use /brana:build anyway] [Describe what you need]
```

### Configuration

```json
{
  "skill_routing": {
    "silent_threshold": 0.9,
    "suggest_threshold": 0.5,
    "enabled": true,
    "mode": "suggest",
    "sources": ["local", "anthropics", "skills.sh"],
    "auto_install_trusted": true
  }
}
```

## Entry Points

### 1. `brana backlog start <task>` (most structured)

Task has subject, tags, strategy, stream — richest signal. Always routes.

```
brana backlog start t-200
  -> memory_search(ns: "skills", query: "{subject} {tags}")
  -> If > suggest_threshold: "Suggested skill: /brana:build (bug-fix). Run it?"
  -> If < suggest_threshold: "No strong match. Search marketplace?"
```

### 2. Freeform conversation (most natural)

Detect task-like intent (action verbs + technical nouns). Uses a lightweight rule:

```
If user message matches pattern: (fix|build|add|create|research|deploy|refactor|test) + (noun):
  -> hooks_route(task: "{message}") for fast classification
  -> memory_search(ns: "skills", query: "{message}") for skill matching
  -> Suggest inline (no AskUserQuestion, just markdown suggestion)
```

### 3. `/brana:do <description>` (explicit)

New meta-skill. User explicitly asks for routing.

```
/brana:do set up monitoring for the API
  -> Full routing pipeline: hooks_route pre-filter + memory_search + marketplace
  -> AskUserQuestion with top matches and alternatives
```

## Source-Tiered Trust Model

| Source | Trust | Install behavior | Tool access |
|--------|-------|-----------------|-------------|
| `anthropics/*` | Trusted | Auto-install if `auto_install_trusted: true` | Full |
| `skills.sh/official` | Verified | Install with review prompt | Default set |
| Curated community (trailofbits, etc.) | Reviewed | Install with review + diff display | Default set |
| Unknown community | Untrusted | Quarantine: install to `acquired/`, read-only tools | Read, Glob, Grep only |
| Unknown URL | Blocked | Won't install — user must add source first | N/A |

`/brana:audit` scans incoming skills for:
- `Bash(rm:*)`, `Bash(curl:*)` in allowed-tools
- References to `~/.claude/settings.json` or credential paths
- Suspicious MCP tool requests
- Missing frontmatter fields

## Risks and Mitigations

| Risk | Mitigation |
|------|------------|
| Silent routing invokes wrong skill | Default mode is "suggest" (never silent). User configures thresholds. |
| External skills inject malicious prompts | Source-tiered trust + /brana:audit scan before install |
| Learning loop learns wrong thing | Defer SONA until explicit feedback exists (P7). P1-P6 have no learning. |
| Marketplace search is slow | Cache marketplace index locally. Refresh weekly via scheduler. |
| Freeform detection triggers on everything | Only route on action verb + technical noun pattern. Conservative. |
| Skill index goes stale | Session-start hook checks SKILL.md mtimes. Reindex on change. |
| Too many skills (100+) degrades search | HNSW scales to millions. 100 skills is trivial. |

## Phased Rollout (simplified — 2 phases + 1 deferred)

| Phase | What | Effort | Dependencies |
|-------|------|--------|-------------|
| P1 | **Index skills + wire routing** — Index 30+ skill frontmatter into `memory_store(ns: "skills")` at session start. `backlog start <id\|text>` calls `memory_search(ns: "skills")`. Suggest via AskUserQuestion. `/brana:do` as alias. CLI fallback if ruflo down. Configurable thresholds in settings. | M | Ruflo durability (done) |
| P2 | **Marketplace auto-recruit** — Low-confidence match auto-triggers `/brana:acquire-skills`. Source-tiered trust model. `/brana:audit` scans incoming skills. | M | P1 |
| P3 | **Cross-client + learning** — `memory_search(ns: "all")` for cross-client patterns. SONA trajectory tracking. Deferred until 50+ skills. | L | P1, ruflo t-823/t-824 |

**What was dropped across two simplification rounds:**
- `/brana:do` as separate skill → merged as alias for `backlog start`
- Dual routing paths (CLI + HNSW) → single HNSW path + CLI fallback
- Freeform conversation detection → no `PreUserMessage` hook in CC (killed by challenger)
- `hooks_route` pre-filter → saves nothing at 30 skills (killed by challenger)
- 8 phases → 4 → 2+1 (progressive simplification)

## Relationship to Prior Work

- **Supersedes:** `docs/ideas/dynamic-skill-routing.md` (t-608) — which recommended a standalone Rust MCP server. This design uses ruflo `memory_store/search` instead (proven durable, no new server needed).
- **Builds on:** ADR-025 (auto-invoke deferred), `brana skills suggest` (Rust CLI), frontmatter enrichment (30+ skills done).
- **Extends:** `/brana:acquire-skills` (adds auto-trigger on routing gaps), `/brana:audit` (adds incoming skill scanning).
- **Depends on:** Ruflo integration P0 (done), durability smoke test (done), close skill MCP port (done).

## Open Questions

1. Should `/brana:do` be a skill or a rule? A skill has its own SKILL.md and appears in the skill list. A rule fires silently.
2. How to handle skill versioning from marketplaces? Pin to git commit? Track upstream?
3. Should the skill index include commands (system/commands/*.md) in addition to skills?
4. How does the router handle multi-skill workflows? (e.g., "research then build" -> /brana:research + /brana:build)

## Field Notes

### 2026-04-01: Ruflo routing tools audit
- `hooks_route` works (2ms, pure JS cosine similarity, 12 hardcoded patterns, learnable)
- `agentdb_semantic-route` broken ("SemanticRouter not available" — same unimplemented pattern)
- `agentdb_route` degraded (falls back to "general")
- `agentdb skill_create/skill_search` exist in source but untested via MCP
- `hooks_route` learns from routing outcomes via `loadLearnedPatterns()` — patterns persist in file

### 2026-04-01: Simplification pass — 3 entry points → 1, 2 paths → 1, 4 phases → 2+1
Merged `/brana:do` as alias for `backlog start`. Collapsed dual routing path (CLI + HNSW) to
single HNSW path with CLI as offline fallback. Rationale: 37ms is imperceptible, one code path
beats two. Phases: 8 → 4 (challenger) → 2+1 (simplification). Final: P1 (index + wire), P2
(marketplace), P3 (cross-client, deferred).

### 2026-04-01: Challenger review — RECONSIDER → dual-path
Opus challenger found 2 critical issues: (C1) freeform detection has no CC execution mechanism
— no PreUserMessage hook exists; (C2) HNSW for 30 skills is unjustified vs existing CLI scorer.
Warnings: hooks_route pre-filter saves nothing at 30 skills; marketplace APIs assumed but don't
exist; 8 phases bloated. Revised to dual-path (CLI fast + HNSW smart), 4 phases.
Decision: ship both — CLI for structured context, HNSW for freeform/cross-client.

### 2026-04-01: External ecosystem snapshot
- SKILL.md is a de facto cross-agent standard (skills.sh, Codex, Gemini CLI)
- No npm-style registry — everything is Git-based
- anthropics/claude-plugins-official (15.7k stars), awesome-claude-code (35.4k stars)
- Smithery.ai dominates MCP marketplace (100k+ tools)
- VoltAgent/awesome-agent-skills: 1000+ cross-platform skills
