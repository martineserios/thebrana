# Skills Architecture

> 25 slash commands organized into 8 groups. Each skill is a markdown file (`system/skills/{name}/SKILL.md`) with YAML frontmatter defining its name, description, and allowed tools. For complete usage details, see [Skill Reference](../reference/skills.md).

## Group Overview

| Group | Count | Skills | Purpose |
|-------|-------|--------|---------|
| **brana** | 4 | backlog, reconcile, acquire-skills, plugin | Core system management |
| **execution** | 4 | build, onboard, align, client-retire | Development and project lifecycle |
| **learning** | 4 | challenge, research, memory, retrospective | Knowledge acquisition and review |
| **venture** | 5 | review, venture-phase, pipeline, financial-model, proposal | Business operations |
| **session** | 1 | close | Session lifecycle |
| **capture** | 1 | log | Event capture |
| **tools** | 1 | notebooklm-source | External tool integration |
| **utility** | 5 | scheduler, export-pdf, gsheets, respondio-prompts, meta-template | Specialized utilities |

## brana (core)

System management skills that operate on brana itself.

- **`backlog`** -- Task management with 16 subcommands (plan, status, portfolio, roadmap, next, pick, done, add, replan, archive, migrate, execute, tags, context, theme, triage). `pick` auto-enters `/brana:build` for code tasks.
- **`reconcile`** -- Spec-vs-implementation drift detection. Scans spec docs ("should" state) against `system/` ("is" state), produces a drift report, applies fixes after approval.
- **`acquire-skills`** -- Scans project context for tech gaps, searches external marketplaces, installs approved skills to `system/skills/acquired/`.
- **`plugin`** -- Manages Claude Code plugins from GitHub marketplaces: add, install, list, remove, update, sync.

## execution

Development lifecycle from project onboarding through retirement.

- **`build`** -- The unified development command. 7 strategies (feature, bug fix, refactor, spike, migration, investigation, greenfield), each with a tailored step flow. CLASSIFY is mandatory. TDD enforced except spike. Runs in fork context for challenge step.
- **`onboard`** -- Diagnostic scan of a project: tech stack, structure, alignment gaps. Auto-detects code/venture/hybrid. Read-only -- does not create files.
- **`align`** -- Implements structure based on onboard findings. 6 phases (DISCOVER -> ASSESS -> PLAN -> IMPLEMENT -> VERIFY -> DOCUMENT). 3 tiers for code projects (Minimal/Standard/Full).
- **`client-retire`** -- Archives a client's patterns. Categorizes as transferable/historical/deletable. Never deletes.

## learning

Knowledge acquisition, recall, and review.

- **`challenge`** -- Dual-model adversarial review (Opus stress-tests reasoning, Gemini retrieves constraints). 4 flavors: pre-mortem, simplicity, assumption buster, adversarial reviewer. Runs in isolated fork context.
- **`research`** -- 3-phase research with scout agents (wide scan -> triage -> deep dive). Max 14 scouts. Supports `--nlm` for NotebookLM, `--refresh` for batch dimension updates. Runs in fork context.
- **`memory`** -- Knowledge operations: recall (search patterns), pollinate (cross-client transfer), review (monthly audit), review --audit (contradiction detection).
- **`retrospective`** -- Stores a learning as a pattern. Confidence starts at 0.5; promoted at 3+ recalls or correction_weight >= 2.

## venture

Business project management, stage-aware.

- **`review`** -- Three modes: weekly (portfolio health + ship log), monthly (P&L close + forward plan), check (ad-hoc AARRR funnel audit).
- **`venture-phase`** -- Milestone execution: product launch, hiring, fundraise, market expansion, process overhaul, custom. Each has exit criteria and learning loops.
- **`pipeline`** -- Deal tracking with stage-dependent templates (Discovery -> Validation -> Growth+). Flags overdue follow-ups and stale deals.
- **`financial-model`** -- Revenue projections with 3 scenarios (base/upside/downside). Detects business model type. Outputs to `docs/financial/model-YYYY-MM.md`.
- **`proposal`** -- Interview-driven client proposal in Spanish. Default rate $65/hr. Outputs to `propuesta-{slug}.md`.

## session

- **`close`** -- End-of-session extraction. Gate checks for changes, spawns debrief-analyst agent, writes errata, stores patterns, detects doc drift, writes handoff note.

## capture

- **`log`** -- Append-only event capture to `~/.claude/memory/event-log.md`. Inline `#tags`, URL detection, WhatsApp dump parsing, auto-archival at 500+ lines.

## tools

- **`notebooklm-source`** -- 6 recipes: prepare, curate, synthesis, audio-prompt, validate, batch. Formats files for optimal NotebookLM ingestion.

## utility

- **`scheduler`** -- Manages scheduled jobs via `brana-scheduler` CLI. Job types: skill (runs `/brana:*`), command (runs shell). Config at `~/.claude/scheduler/scheduler.json`.
- **`export-pdf`** -- Converts markdown to PDF via mdpdf. Uses project CSS if available.
- **`gsheets`** -- Google Sheets via MCP: list, read, write, create, summary, share.
- **`respondio-prompts`** -- Respond.io AI agent prompt engineering. 15-item audit checklist, 4-part writing framework (CONTEXT -> ROLE -> FLOW -> BOUNDARIES).
- **`meta-template`** -- WhatsApp templates optimized for Utility classification. C-level formula with kill-line scanning and appeal generation.

## Commands

Commands in `system/commands/` orchestrate multi-step spec workflows:

| Command | Purpose |
|---------|---------|
| `maintain-specs` | Full spec correction cycle: errata -> reflections -> synthesis -> hygiene |
| `apply-errata` | Apply pending errata through the layer hierarchy |
| `re-evaluate-reflections` | Cross-check reflections against dimension docs |
| `repo-cleanup` | Commit accumulated spec changes: survey -> batch -> branch -> merge |
| `init-project` | Initialize a new project with brana structure |

See [Command Reference](../reference/commands.md) for details.

## Skill anatomy

Every skill lives at `system/skills/{name}/SKILL.md`:

```yaml
---
name: skill-name
description: "One-line description for discovery and help text."
allowed-tools:
  - Read
  - Write
  - Bash
  - AskUserQuestion
---

# Skill Name

Instructions for Claude when this skill is invoked...
```

The `allowed-tools` list restricts which tools Claude can use during execution. Skills without Write, Edit, or Bash are read-only. Acquired skills from external marketplaces live in `system/skills/acquired/<name>/SKILL.md`.
