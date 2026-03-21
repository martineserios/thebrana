# Dynamic Skill Routing — Investigation Report (t-608)

> Investigated 2026-03-21. Status: recommendation ready.

## Question

How can `/brana:build` dynamically discover and invoke the best skills for the current task context, instead of relying on hardcoded skill references?

## Findings

### 1. CC has no programmatic skill discovery

- **ToolSearch** only works for MCP tools, not skills
- Skills can't query or invoke each other at runtime
- No `listSkills()` or `searchSkills()` API exists
- Skills are discovered by Claude reading descriptions at session start (~5.6KB)

### 2. Current routing is semantic-only

Claude reads all 30 skill descriptions loaded in context. When conversation context matches a skill's description keywords, Claude naturally suggests it. This is CC's intended pattern — declarative, not imperative.

### 3. Current frontmatter has routing-useful fields

| Field | Present in | Routing value |
|-------|-----------|--------------|
| `description` | all 30 skills | Primary — loaded into context, Claude matches on keywords |
| `group` | 28/30 skills | Category routing (execution, learning, venture, utility) |
| `depends_on` | 3 skills | Prerequisite chaining |
| `effort` | all 30 skills | Cost-aware selection |

### 4. Missing metadata for better routing

| Field | Purpose | Impact |
|-------|---------|--------|
| `keywords` | Semantic tags (["whatsapp", "testing", "financial"]) | HIGH — enables search |
| `task_strategies` | Which build strategies skill supports | HIGH — strategy→skill mapping |
| `stream_affinity` | Which task streams skill is for | HIGH — stream→skill mapping |
| `problem_domain` | Problem types solved | MEDIUM — context matching |
| `output_artifacts` | What the skill produces | MEDIUM — composition planning |

## Options Evaluated

### A. Enrich frontmatter + build prompt (lightweight)

Add `keywords`, `task_strategies`, `stream_affinity` to frontmatter. Add a "skill consideration" step to `/brana:build`. Claude matches using enriched descriptions.

- **Pro:** Works with CC's design, no infrastructure
- **Con:** Relies on Claude's attention span, doesn't scale past ~50 skills, descriptions eat context budget

### B. Skill registry MCP server (robust)

Custom MCP tool that indexes skill frontmatter into a searchable registry. Exposed via ToolSearch. `/brana:build` calls `skill_search("whatsapp template")` and gets ranked results.

- **Pro:** Programmatic, scales to 100+ skills, context-efficient (only load what's needed), works with ToolSearch
- **Con:** Needs MCP server infrastructure, must re-index on skill changes

### C. Improve descriptions only (cheapest)

Rewrite skill descriptions with routing-relevant keywords. No new fields.

- **Pro:** Zero infrastructure, immediate
- **Con:** Doesn't scale, competes with 28KB context budget

## Recommendation: Option B — Skill Registry MCP Server

**Why:** Best long-term. Robust, performant, scales. Brana already has MCP infrastructure (ruflo). A skill registry is a small, focused MCP server.

### Architecture

```
skill-registry MCP server
├── Index: reads all system/skills/*/SKILL.md frontmatter
├── Tools:
│   ├── skill_search(query, strategy?, stream?) → ranked skill list
│   ├── skill_get(name) → full frontmatter + usage info
│   └── skill_suggest(task_context) → recommended skills for a task
├── Re-index: on SessionStart or file change
└── Storage: in-memory (30 skills = trivial)
```

### Integration with /brana:build

```
BUILD step:
  1. Analyze subtask context (description, tags, files)
  2. Call skill_suggest(subtask_context)
  3. If relevant skills found → "Available skills for this step: X, Y. Invoke?"
  4. User approves → Skill(skill="brana:X", args="...")
```

### Prerequisites

1. **Enrich frontmatter** with `keywords`, `task_strategies`, `stream_affinity` (Option A is a prerequisite for Option B)
2. **Build the MCP server** (Rust or TypeScript, ~200 LOC)
3. **Register in plugin.json** as MCP server
4. **Update /brana:build** to call `skill_suggest` during BUILD step

### Effort estimate

| Step | Effort |
|------|--------|
| Frontmatter enrichment (30 skills) | S (1 hour) |
| MCP server (index + search + suggest) | M (half day) |
| /brana:build integration | S (1 hour) |
| Testing + docs | S (1 hour) |
| **Total** | **M-L (1 day)** |

## Refined Architecture: Standalone MCP Skill Registry

### Why standalone

- Clean separation from ruflo (no coupling to ruflo availability)
- Small, focused, fast startup (~30 skills = trivial in-memory index)
- Lives in the brana plugin (`system/mcp/skill-registry/`)
- Registered in plugin.json as an MCP server

### Implementation: Rust CLI + MCP stdio wrapper

```
system/mcp/skill-registry/
├── src/
│   ├── main.rs          ← MCP stdio server (jsonrpc)
│   ├── index.rs         ← Reads SKILL.md frontmatter, builds in-memory index
│   ├── search.rs        ← Keyword + strategy + stream matching
│   └── suggest.rs       ← Task-context-aware skill recommendation
├── Cargo.toml
└── README.md
```

### MCP Tools exposed

| Tool | Input | Output |
|------|-------|--------|
| `skill_search` | `{query: "whatsapp template", strategy?: "feature", stream?: "roadmap"}` | Ranked list of matching skills with relevance score |
| `skill_get` | `{name: "meta-template"}` | Full frontmatter + description + usage examples |
| `skill_suggest` | `{task_subject: "...", task_tags: [...], task_stream: "...", files_touched: [...]}` | Top 3 recommended skills with reasoning |
| `skill_list` | `{group?: "venture", effort?: "low"}` | Filtered list of all skills |

### Enriched frontmatter schema (prerequisite)

```yaml
# NEW FIELDS (add to all 30 skills)
keywords: [whatsapp, meta, template, messaging]  # semantic search terms
task_strategies: [feature, spike]                  # which build strategies match
stream_affinity: [roadmap, research]               # which task streams match
```

### /brana:build integration

During BUILD step, before each subtask:
```
1. Call skill_suggest({task_subject, task_tags, task_stream, files_touched})
2. If relevant skills found with score > 0.7:
   "Available skills for this step: /brana:meta-template (0.9), /brana:respondio-prompts (0.75)"
   "Invoke any? [Yes — pick / No — proceed manually]"
3. User picks → Skill(skill="brana:meta-template", args="...")
```

### Re-indexing

- On MCP server start: scan `system/skills/*/SKILL.md` + `system/commands/*.md`
- Lightweight — 30 files, pure frontmatter parsing, <100ms
- No persistent storage needed — rebuild on every session

## Next Steps

1. **t-608a**: Enrich frontmatter — add `keywords`, `task_strategies`, `stream_affinity` to all 30 skills
2. **t-608b**: Build standalone MCP skill registry server (Rust, stdio)
3. **t-608c**: Register in plugin.json, test with ToolSearch
4. **t-608d**: Update `/brana:build` BUILD step to call `skill_suggest`
5. **t-608e**: Update `/brana:backlog start` to surface skill recommendations

Decompose via `/brana:build decompose t-608` when ready to build.
