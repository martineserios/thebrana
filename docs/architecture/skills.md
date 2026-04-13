# Skills Architecture

> Design principles and structure for brana skills. For the complete per-skill catalog, see [Skill Reference](../reference/skills.md).

## Group Overview

| Group | Purpose | Examples |
|-------|---------|---------|
| **brana** | Core system management | backlog, reconcile, plugin, do |
| **core** | System foundations | docs, sitrep |
| **execution** | Development lifecycle | build, onboard, align |
| **learning** | Knowledge acquisition | challenge, research, memory |
| **thinking** | Interactive ideation | brainstorm |
| **venture** | Business operations | review, client-retire |
| **session** | Session lifecycle | close |
| **capture** | Event capture | log |
| **tools** | External integrations | notebooklm-source |
| **utility** | Specialized tools | scheduler, gsheets, export-pdf |

## Skill Tiering (ADR-034)

Skills are split into two tiers to reduce startup context loading (~34K to ~8K tokens):

| Tier | Count | SKILL.md | Procedure location |
|------|-------|----------|--------------------|
| **Core** | 7 | Full (frontmatter + procedure) | Inline in SKILL.md |
| **Extended** | 20 | Stub (frontmatter + Read instruction) | `system/procedures/{name}.md` |

**Core skills** (always loaded): build, backlog, close, research, brainstorm, sitrep, do

**Extended skills** use a stub SKILL.md that preserves full frontmatter (for discovery, routing, and the skill index) but replaces the procedure body with a Read instruction pointing to `system/procedures/{name}.md`. The procedure is loaded on invoke via the Read tool (~200ms overhead).

If CC fixes #14882 (frontmatter-only loading), tiering becomes unnecessary — merge stubs back.

## Skill Anatomy

Every skill lives at `system/skills/{name}/SKILL.md`:

```yaml
---
name: skill-name
description: "One-line description for discovery and help text."
argument-hint: "[optional args]"
group: execution
depends_on:
  - other-skill
allowed-tools:
  - Read
  - Write
  - Bash
  - AskUserQuestion
---

# Skill Name

Instructions for Claude when this skill is invoked...
```

For extended skills, the body is replaced with a Read instruction:

```markdown
Read the procedure file before executing: `system/procedures/{name}.md`
```

Key fields:
- **`allowed-tools`** restricts which tools Claude can use during execution. Skills without Write, Edit, or Bash are read-only.
- **`depends_on`** declares skill dependencies (e.g., build depends on backlog, challenge, retrospective).
- **`argument-hint`** shows expected arguments in help text.
- **`group`** determines where the skill appears in the reference catalog.

## Composability

Skills compose with each other — each is a building block that other skills call:

| Caller | Callee | When |
|--------|--------|------|
| `/brana:build` CLOSE | `/brana:docs all` | Post-merge doc updates |
| `/brana:build` PLAN | `brana backlog add` | Persist subtasks (Medium/Large) |
| `/brana:backlog start` | `/brana:build` | Auto-enters build loop for code tasks |
| `/brana:close` | `debrief-analyst` agent | Session-end extraction |
| `/brana:challenge` | `challenger` agent | Adversarial review |

## Commands

Commands in `system/commands/` orchestrate multi-step spec workflows. They are agent-executed protocols, not slash commands.

| Command | Purpose |
|---------|---------|
| `maintain-specs` | Full spec correction cycle: errata -> reflections -> synthesis -> hygiene |
| `apply-errata` | Apply pending errata through the layer hierarchy |
| `re-evaluate-reflections` | Cross-check reflections against dimension docs |
| `repo-cleanup` | Commit accumulated spec changes: survey -> batch -> branch -> merge |
| `init-project` | Initialize a new project with brana structure |

See [Command Reference](../reference/commands.md) for details.

## MCP Tool Integration

Several skills now use ruflo MCP calls as their preferred data path (2026-04-01):

| Skill | MCP usage |
|-------|-----------|
| **close** | Step 9b: 3 MCP calls — `memory_store` (ns:session), `hive-mind_memory`, `claims_release`. Steps 5, 6, 10 prefer MCP paths over CLI fallbacks. |
| **sitrep** | Source 6: `hooks_intelligence_pattern-search` for recent patterns. Source 7: `hive-mind_memory list` for active swarm context. |
| **research** | Phase 0: `memory_search` (ns:all) for prior findings. Phase 2: `embeddings_compare` for dedup against existing knowledge. |
| **build** | `hive-mind` announce at strategy start and build completion for multi-agent coordination. |
| **backlog** | `claims_claim`/`claims_release` at task start/done. Step 5: `memory_search` (ns:skills) for semantic skill suggestion — configurable thresholds (suggest >0.5, mention >0.3, gap <0.3 triggers marketplace). CLI `brana skills suggest` as fallback. See ADR-026, feature brief `skill-routing-in-backlog-start.md`. |

When ruflo is unavailable, every skill degrades gracefully to CLI or native memory fallbacks.

## Acquired Skills

Skills installed from external marketplaces via `/brana:acquire-skills` live in `system/skills/acquired/{name}/SKILL.md`. They follow the same anatomy but are tracked separately for update management.

### Source-Tiered Trust Model (ADR-026)

External skills are classified by source into trust tiers that determine install behavior:

| Source | Tier | Install | Tool access |
|--------|------|---------|-------------|
| `anthropics/*` | Trusted | Auto with confirm | Full |
| `skills.sh` official, `trailofbits/*` | Verified | Review prompt | Default set |
| Other GitHub/npm | Community | Quarantine | Read, Glob, Grep only |
| Unknown | Blocked | Rejected | N/A |

Community skills install with `quarantine: true` in frontmatter and read-only tools. `/brana:audit` includes an incoming skill scan that checks acquired skills for dangerous allowed-tools, credential path references, suspicious MCP tool requests, and missing frontmatter.
