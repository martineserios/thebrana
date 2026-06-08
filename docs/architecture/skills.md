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

### Installed Acquired Skills

| Skill | Source | Purpose | Installed |
|-------|--------|---------|-----------|
| `caveman` | `JuliusBrussee/caveman` | Ultra-compressed output (~50% token reduction on brana prompts). Trigger: `/caveman`. | 2026-04-13 |

## Field Notes

### 2026-06-01: Skill retirement requires updating 10 locations in one commit
When retiring a skill, the full checklist: SKILL.md + procedure file (delete), skills.md row, guide/commands/index.md row, brana-cli.md row, component-index.md row, architecture feature docs, guide workflow docs, ideas/skill-tiering.md row, scripts.md section (if has a script). Do all in one commit — leaving any behind creates a window where docs reference deleted files.
Source: notebooklm-source retirement / close session 2026-06-01 / t-1813

### 2026-06-01: Procedure preamble ToolSearch audit — grep, not positional extraction
brana procedures place the `<!-- ruflo preamble -->` / `ToolSearch(...)` block inside the document body (after `##` headings), not before the first heading. An audit script that extracts "pre-heading content" misses all ToolSearch declarations and reports false gaps for every procedure. Correct approach: `grep -n 'ToolSearch\|mcp__brana__' "$file"` and compare sets directly.
Source: E2026-06-01-2 preamble audit / close session 2026-06-01

### 2026-05-14: system/skills/memory/ naming collision with auto-memory store
`system/skills/memory/` (the memory skill dir) shares a path component with `~/.claude/projects/.../memory/` (the auto-memory store). At least one writer created `system/skills/memory/MEMORY.md` — a spurious auto-memory index that doesn't belong in the skill tree. Deleted as a stale artifact. Risk of recurrence: any tool that walks `system/skills/` looking for `memory/` subdirs could land here. Guard: pre-commit should reject `system/skills/**/MEMORY.md`.
Source: sitrep investigation / close session 2026-05-14

### 2026-05-14: MCP tools in allowed-tools are project-scoped — use CLI when procedure already calls it
`allowed-tools` grants permission but not availability. MCP servers are registered per-project (`.mcp.json`). A skill loaded globally via plugin that lists a project-scoped MCP tool (e.g. `mcp__brana__backlog_set`) will silently fail in any session where that server isn't running. Root cause of 22 `backlog_set` failures: `/brana:fix` ran in `proyecto_anita` where brana-mcp wasn't registered. Fix: if the procedure already uses the CLI equivalent, don't add the MCP tool to `allowed-tools` — it adds failure surface with zero benefit.
Source: fix/mcp-backlog-allowed-tools / close session 2026-05-14

### 2026-06-08: Pre-edit challenger review catches category-1 spec gaps before a procedure ships
Invoke `brana:challenger` on the procedure spec **before** opening any Edit tool call — this is the mandatory pre-edit gate. The adversarial read catches structural gaps (missing write paths, ambiguous guard conditions, undefined fallbacks) that the author is blind to because they hold context. Challenger caught the missing `skill_gap_checked` write path in build.md Step 0.5 before it was committed; without the review, the token would never have been written and Step 0.5 would loop on every `/brana:build` invocation. The fix cost at draft time is one agent call; the fix cost after shipping is a debrief errata cycle + confusion for anyone following the procedure literally.
Source: t-1903 / E2026-06-08-9 / close session 2026-06-08

### 2026-06-08: Guard conditions in shared procedures must use testable artifact checks, not intent labels
"Skip for freeform tasks" is ambiguous — different callers have different definitions of "freeform." Use observable artifact checks instead: "Skip when `task_id` is absent." The condition is binary, independent of caller intent, and stays correct even as the set of callers grows beyond the original use case. Applied: build.md Step 0.5 guard changed from "skip for freeform tasks" → "skip when no task_id". General rule: if a guard condition can be rephrased as "when artifact X is present/absent," do so.
Source: t-1903 challenger review / close session 2026-06-08
