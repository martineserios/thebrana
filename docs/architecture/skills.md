# Skills Catalog

> Slash commands organized by purpose. Each skill is a markdown file (`system/skills/{name}/SKILL.md`) with YAML frontmatter defining its name, description, and allowed tools.

## Build & Development

Skills for building, shipping, and maintaining code.

### `/brana:build`
Build anything — auto-detects strategy (feature, bug fix, refactor, spike, migration, investigation, greenfield). 4-step loop: SPECIFY → PLAN → BUILD → CLOSE. Integrates with `/brana:tasks` — strategy and build_step fields track progress. Task tags and description seed the research loop.

### `/brana:close`
End a session — extract learnings, write handoff note, store patterns, detect doc drift. Absorbs the old `/session-handoff` close mode and `/debrief`.

### `/brana:challenge`
Dual-model adversarial review. Opus subagent stress-tests reasoning; Gemini stress-tests against documented knowledge. Use when a significant decision, plan, or architecture needs adversarial review.

### `/brana:reconcile`
Detect drift between spec docs and `system/` implementation. Plans fixes and applies them after approval. Use after `/brana:maintain-specs` or periodically to keep specs and code in sync.

### `/brana:research`
Research a topic, doc, or creator — check sources, follow references recursively, produce findings. Spawns scout agents for parallel web search. `--refresh` flag runs batch dimension doc updates (replaces the old `/refresh-knowledge`).

### `/brana:tasks`
Manage tasks — plan, track, navigate phases and streams. Supports `plan`, `add`, `start`, `done`, `status`, `portfolio`, `roadmap`, `next`, `reprioritize`, `tags`, `context`, `execute`, and `--wide` display mode. `/brana:tasks start` auto-classifies strategy and enters `/brana:build` for code tasks.

### `/brana:log`
Capture events — links, calls, meetings, ideas, observations — into a searchable append-only log. Includes bulk mode for WhatsApp dumps and URL-to-task promotion.

## Quality & Memory

Skills for learning, recalling, and aligning projects.

### `/brana:memory`
Knowledge system operations with subcommands:
- `recall` — Query patterns relevant to current context
- `pollinate` — Cross-pollinate learnings from other projects
- `review` — Monthly knowledge health check
- `review --audit` — Contradiction detection across docs

### `/brana:retrospective`
Store a learning or pattern in the knowledge system. Use after notable discoveries, unexpected issues, or successful workarounds.

### `/brana:onboard`
Scan and diagnose a project — auto-detects type (code, venture, or hybrid). Outputs a gap report with recommendations. Diagnostic only — no file creation.

### `/brana:align`
Actively align a project with brana practices — 6 phases: DISCOVER → ASSESS → PLAN → IMPLEMENT → VERIFY → DOCUMENT. Auto-detects project type and applies type-appropriate checklists.

### `/brana:client-retire`
Archive a project's patterns and mark them as historical. Categorizes knowledge as transferable, historical, or deletable.

## Business / Venture

Skills for managing business projects through their lifecycle.

### `/brana:review`
Business review with three subcommands:
- `weekly` (default) — portfolio health, metrics delta, ship log, next-week planning
- `monthly` — monthly close + forward plan (P&L, actuals vs projections, targets)
- `check` — ad-hoc AARRR funnel audit and growth health check

### `/brana:venture-phase`
Plan and execute a business milestone — product launch, hiring, fundraise, expansion, or custom. Includes learning loops for continuous improvement.

### `/brana:financial-model`
Revenue projections, scenario analysis, P&L template, unit economics, and cash flow analysis. Stage-aware financial modeling for founders.

### `/brana:pipeline`
Sales pipeline tracking — leads, deals, conversions, follow-ups. Stage-aware CRM that works with markdown or MCP integrations.

### `/brana:proposal`
Generate a client proposal — interview-driven, structured markdown with cost breakdown and timeline.

## Integrations

Skills that connect to external tools and platforms.

### `/brana:gsheets`
Google Sheets via MCP — read, write, create, list, share spreadsheets. Requires the google-sheets MCP server.

### `/brana:notebooklm-source`
Guided workflow to prepare and format sources for NotebookLM. Claude reads, reformats, validates, and writes optimized files. User uploads them manually.

### `/brana:export-pdf`
Convert a markdown file to PDF using `mdpdf`. Use when exporting proposals, SOPs, or documents to PDF.

### `/brana:meta-template`
Write Meta WhatsApp templates optimized for Utility classification — empirically validated formula with safe elements, kill lines, and appeal texts.

### `/brana:respondio-prompts`
Respond.io AI agent prompt engineering — write instructions, actions, KB files, and multi-agent architectures within platform constraints.

### `/brana:scheduler`
Scheduled jobs management.

### `/brana:acquire-skills`
Find and install marketplace skills for project tech gaps. Scans project files for tech signals, diffs against local skills, searches Vercel skills CLI or web for matches. User approves before install.

## Commands

Brana also includes commands in `system/commands/`. Commands orchestrate multi-step spec workflows:

| Command | Description |
|---------|-------------|
| `/brana:maintain-specs` | Full spec correction cycle — errata, reflections, synthesis, hygiene |
| `/brana:apply-errata` | Apply pending errata through the layer hierarchy |
| `/brana:re-evaluate-reflections` | Cross-check reflections against dimension docs |
| `/brana:repo-cleanup` | Commit accumulated spec changes — survey, batch, branch, merge |
| `init-project` | Initialize a new project with brana structure |

## Acquired

Skills installed from external marketplaces via `/brana:acquire-skills`. Each lives in `system/skills/acquired/<name>/SKILL.md` and deploys alongside native skills.

_No acquired skills yet. Run `/brana:acquire-skills` in a project to populate this section._

## Skill Anatomy

Every skill lives at `system/skills/{name}/SKILL.md` with this structure:

```yaml
---
name: skill-name
description: "One-line description for discovery and help text."
allowed-tools:
  - Read
  - Write
  - Bash
  - AskUserQuestion
  # ... tools this skill may use
---

# Skill Name

Instructions for Claude when this skill is invoked...
```

The `allowed-tools` list restricts which tools Claude can use during skill execution. Skills without dangerous tools (Write, Edit, Bash) are read-only.
