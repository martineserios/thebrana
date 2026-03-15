# Skills Architecture

> Design principles and structure for brana skills. For the complete per-skill catalog, see [Skill Reference](../reference/skills.md).

## Group Overview

| Group | Purpose | Examples |
|-------|---------|---------|
| **brana** | Core system management | backlog, reconcile, plugin |
| **execution** | Development lifecycle | build, onboard, align |
| **learning** | Knowledge acquisition | challenge, research, memory |
| **venture** | Business operations | review, pipeline, proposal |
| **session** | Session lifecycle | close |
| **capture** | Event capture | log |
| **tools** | External integrations | notebooklm-source |
| **utility** | Specialized tools | scheduler, gsheets, export-pdf |

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

## Acquired Skills

Skills installed from external marketplaces via `/brana:acquire-skills` live in `system/skills/acquired/{name}/SKILL.md`. They follow the same anatomy but are tracked separately for update management.
