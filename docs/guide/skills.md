# Skills Catalog

> 39 slash commands organized by purpose. Each skill is a markdown file (`system/skills/{name}/SKILL.md`) with YAML frontmatter defining its name, description, and allowed tools.

## Development

Skills for building, shipping, and maintaining code.

### `/build-phase`
Plan and implement the next roadmap phase with built-in learning loops — debrief after each work item, maintain-specs after each phase. The main driver for progressing through the roadmap.

### `/build-feature`
Guide a feature from zero to shipped — research, brainstorm, design, plan, build, close. Works for any project and any kind of work (code, design, infra, venture, process). The general-purpose feature builder.

### `/decide`
Create an Architecture Decision Record (ADR) in `docs/decisions/`. Use before implementing a new feature to document the decision rationale. Required on `feat/*` branches by the spec-first hook.

### `/challenge`
Dual-model adversarial review. Opus subagent stress-tests reasoning; Gemini stress-tests against documented knowledge. Use when a significant decision, plan, or architecture needs adversarial review.

### `/debrief`
Extract errata, fixes, and process learnings from the current session. Use at the end of implementation sessions to capture what went right, what went wrong, and what to remember.

### `/reconcile`
Detect drift between spec docs and `system/` implementation. Plans fixes and applies them after approval. Use after `/maintain-specs` or periodically to keep specs and code in sync.

### `/back-propagate`
Propagate implementation changes back to spec docs — update `docs/` when `system/` rules, hooks, skills, agents, or config change. The reverse of `/reconcile`.

### `/research`
Research a topic, doc, or creator — check sources, follow references recursively, produce findings. Spawns scout agents for parallel web search. Use for deep research on any topic.

### `/refresh-knowledge`
Refresh external research for spec docs — web-search for updates to dimension, venture/PM, and cross-cutting topics. Use when docs may be stale or before major phase planning.

### `/knowledge`
Browse, annotate, review, and reindex the brana-knowledge dimension docs. The interface to the knowledge base.

### `/tasks`
Manage tasks — plan, track, navigate phases and streams. Supports `plan`, `add`, `start`, `list`, `reprioritize`, and `--wide` display mode. The central task management interface.

### `/pickup`
Resume from last session — read handoff notes, cross-reference task status, present actionable items. Use at session start to continue where you left off.

### `/usage-stats`
Token usage analytics — model distribution, activity trends, session efficiency. Use when checking usage patterns or evaluating model routing.

## Quality & Memory

Skills for learning, recalling, and aligning projects.

### `/memory`
Knowledge system operations with subcommands:
- `recall` — Query patterns relevant to current context
- `pollinate` — Cross-pollinate learnings from other projects
- `review` — Monthly knowledge health check
- `review --audit` — Contradiction detection across docs

### `/retrospective`
Store a learning or pattern in the knowledge system. Use after notable discoveries, unexpected issues, or successful workarounds.

### `/project-align`
Actively align a project with brana practices — assess gaps, plan fixes, implement structure, verify, and document. Use when setting up a new project or when one needs structural alignment.

### `/project-onboard`
Bootstrap a new project by scanning its structure and recalling relevant portfolio knowledge. Use when entering an unfamiliar project for the first time.

### `/project-retire`
Archive a project's patterns and mark them as historical. Categorizes knowledge as transferable, historical, or deletable.

### `/personal-check`
Personal life check — tasks, life areas, journal freshness. Use at session start for personal priorities.

## Business / Venture

Skills for managing business projects through their lifecycle.

### `/venture-align`
Set up business management structure — stage-appropriate templates, SOPs, OKRs, metrics, meeting cadences. The structural foundation for a venture project.

### `/venture-onboard`
Discover and diagnose a business project — stage classification, framework recommendation, gap report. Use when taking over a business project or starting on a new venture.

### `/venture-phase`
Plan and execute a business milestone — product launch, hiring, fundraise, expansion, or custom. Includes learning loops for continuous improvement.

### `/growth-check`
Business health audit — AARRR funnel analysis and stage-appropriate metrics check with trend tracking. Use monthly/quarterly for business health assessment.

### `/experiment`
Growth experiment loop — hypothesis, test design, success criteria, results, learning. Structured experimentation with auto-incrementing records.

### `/morning`
Daily operational check — stage-aware focus card with priorities, blockers, key metric, and optional calendar review. Use at session start on a venture project.

### `/weekly-review`
Weekly cadence review — portfolio health, zombie cleanup, metrics delta, ship log, and next-week planning with trend storage. Use every Friday or Monday.

### `/monthly-close`
Monthly financial close — P&L summary, actuals vs projections, trend analysis, runway update. The monthly heartbeat of business health.

### `/monthly-plan`
Forward-looking monthly plan — revenue targets, priorities tied to bottleneck, experiments, pipeline actions, budget allocation. Use at month-start after `/monthly-close`.

### `/financial-model`
Revenue projections, scenario analysis, P&L template, unit economics, and cash flow analysis. Stage-aware financial modeling for founders.

### `/pipeline`
Sales pipeline tracking — leads, deals, conversions, follow-ups. Stage-aware CRM that works with markdown or MCP integrations.

### `/sop`
Create a structured, versioned Standard Operating Procedure from a described process. Use when a repeatable process needs formal documentation.

### `/proposal`
Generate a client proposal — interview-driven, structured markdown with cost breakdown and timeline.

## Integrations

Skills that connect to external tools and platforms.

### `/gsheets`
Google Sheets via MCP — read, write, create, list, share spreadsheets. Requires the google-sheets MCP server.

### `/notebooklm-source`
Guided workflow to prepare and format sources for NotebookLM. Claude reads, reformats, validates, and writes optimized files. User uploads them manually.

### `/export-pdf`
Convert a markdown file to PDF using `mdpdf`. Use when exporting proposals, SOPs, or documents to PDF.

### `/meta-template`
Write Meta WhatsApp templates optimized for Utility classification — empirically validated formula with safe elements, kill lines, and appeal texts.

### `/respondio-prompts`
Respond.io AI agent prompt engineering — write instructions, actions, KB files, and multi-agent architectures within platform constraints.

### `/content-plan`
Marketing content planning — themes, calendar, distribution checklist, performance tracking. Quarterly content strategy aligned to growth goals.

### `/scheduler`
Scheduled jobs management.

## Commands

In addition to the 39 skills above, brana includes 7 commands in `system/commands/`. Commands are like skills but typically orchestrate multi-step workflows:

| Command | Description |
|---------|-------------|
| `/session-handoff` | Auto-detect pickup or close — extracts learnings, writes handoff note |
| `/maintain-specs` | Full spec correction cycle — errata, reflections, synthesis, hygiene |
| `/apply-errata` | Apply pending errata through the layer hierarchy |
| `/re-evaluate-reflections` | Cross-check reflections against dimension docs |
| `/refresh-knowledge` | Research web for updates to dimension docs |
| `/repo-cleanup` | Commit accumulated spec changes — survey, batch, branch, merge |
| `init-project` | Initialize a new project with brana structure |

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
