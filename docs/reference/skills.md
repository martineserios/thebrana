# Skill Reference

Complete reference for all 25 brana skills. Each skill is a `/brana:*` slash command loaded from `system/skills/`.

## Group Index

| Group | Skills | Purpose |
|-------|--------|---------|
| **brana** | backlog, reconcile, acquire-skills, plugin | Core system management |
| **execution** | build, onboard, align, client-retire | Development and project lifecycle |
| **learning** | challenge, research, memory, retrospective | Knowledge acquisition and review |
| **venture** | review, venture-phase, pipeline, financial-model, proposal | Business operations |
| **session** | close | Session lifecycle |
| **capture** | log | Event capture |
| **tools** | notebooklm-source | External tool integration |
| **utility** | scheduler, export-pdf, gsheets, respondio-prompts, meta-template | Specialized utilities |

---

## brana

### `/brana:backlog`

Manage the project backlog -- plan, track, and navigate work across phases, milestones, and streams.

**Trigger:** Planning phases, viewing roadmaps, restructuring work.
**Allowed tools:** Read, Write, Glob, Grep, Bash, AskUserQuestion

**Subcommands:**

| Subcommand | Synopsis |
|------------|----------|
| `plan [project] "[title]"` | Plan a phase interactively |
| `status [project] [--wide]` | Progress overview (omit project = portfolio) |
| `portfolio [--unified] [--wide]` | Cross-client actionable tasks |
| `roadmap [project] [--wide]` | Full tree view with all levels |
| `next [project] [--stream X] [--wide]` | Next unblocked task by priority |
| `pick <id>` | Begin work on a task (enters `/brana:build` for code tasks) |
| `done [id]` | Complete current task (manual/external tasks only) |
| `add "[description]"` | Quick-add a task with intelligent suggestions |
| `replan [project] [phase-id]` | Restructure a phase |
| `archive [project]` | Move completed phases to archive |
| `migrate <file>` | Import tasks from a markdown backlog |
| `execute [scope] [--dry-run] [--max-parallel N] [--retry]` | Execute tasks via subagents |
| `tags [project]` | Tag inventory, filtering, and bulk tag management |
| `context <id> [text]` | View or set rich context on a task |
| `theme [name]` | View or set display theme (classic, emoji, minimal) |
| `triage [project] [--reresearch] [--scope P2+]` | Research-informed priority reassessment |

**Related:** build (entered via `pick`), close (CLOSE step completes tasks)

**Example:**
```
/brana:backlog status                    -- portfolio overview
/brana:backlog next --stream roadmap     -- next roadmap task
/brana:backlog add "Fix auth token expiry"
/brana:backlog pick t-008               -- start working on task
```

---

### `/brana:reconcile`

Detect drift between spec docs and `system/` implementation. Plan fixes, apply after approval.

**Trigger:** After `/brana:maintain-specs` changes, periodically to check drift, before a new build phase.
**Allowed tools:** Bash, Read, Write, Edit, Glob, Grep, Task, AskUserQuestion

**Process:** Orient (locate paths, check state, create branch) -> Scan specs ("should" state) -> Scan implementation ("is" state) -> Diff (identify drift) -> Present drift report -> Apply changes (after approval) -> Log to doc 24 -> Store in memory -> Report.

**Drift types:** Missing (spec exists, implementation doesn't), Stale (implementation contradicts specs), Incomplete (implementation missing parts), Extra (implementation has undocumented items).

**Related:** maintain-specs (triggers reconcile), build (implements new capabilities)

---

### `/brana:acquire-skills`

Scan project context, identify missing skills, search external marketplaces, install approved skills.

**Trigger:** New or unfamiliar tech in a project.
**Allowed tools:** Read, Write, Bash, Glob, Grep, WebSearch, WebFetch, AskUserQuestion, Agent

**Usage:**
```
/brana:acquire-skills                    -- scan current project
/brana:acquire-skills <task-id>          -- scan a specific task's needs
/brana:acquire-skills <keyword>          -- direct search ("cloudflare")
```

**Process:** Gather tech keywords -> Diff against local skills -> Search marketplaces (Vercel CLI or WebSearch) -> Evaluate and present candidates -> Install selected to `system/skills/acquired/`.

**Related:** plugin (manages whole plugins, not individual skills)

---

### `/brana:plugin`

Manage Claude Code plugins from GitHub marketplaces.

**Trigger:** Installing, updating, or managing plugins.
**Allowed tools:** Read, Write, Bash, Glob, Grep, WebFetch, AskUserQuestion, Agent

**Subcommands:**

| Subcommand | Synopsis |
|------------|----------|
| `add <owner/repo>` | Register a GitHub marketplace |
| `install <name>` | Install a plugin from known marketplaces |
| `list` | Show installed + available plugins |
| `remove <name>` | Uninstall a plugin |
| `update [name]` | Update all or a specific plugin |
| `sync` | Sync dev plugin cache (`--plugin-dir` users) |

**Related:** acquire-skills (for individual skills, not plugins)

---

## execution

### `/brana:build`

The unified development command. One entry point for all work types.

**Trigger:** Starting any development work -- features, bug fixes, refactors, spikes, migrations, investigations.
**Allowed tools:** Bash, Read, Write, Edit, Glob, Grep, Task, WebSearch, WebFetch, AskUserQuestion
**Dependencies:** backlog, challenge, retrospective

**Strategies:**

| Strategy | Flow | When |
|----------|------|------|
| Feature | SPECIFY -> PLAN -> BUILD -> CLOSE | Default -- adds capability |
| Bug fix | REPRODUCE -> DIAGNOSE -> FIX -> CLOSE | "fix", "broken", "bug" |
| Greenfield | ONBOARD -> SPECIFY -> PLAN -> BUILD -> CLOSE | "new project", "from scratch" |
| Refactor | SPECIFY (light) -> VERIFY COVERAGE -> BUILD -> CLOSE | "refactor", "clean up" |
| Spike | QUESTION -> EXPERIMENT -> ANSWER | "can we", "spike", "prototype" |
| Migration | SPECIFY -> PLAN -> BUILD (careful) -> CLOSE | "migrate", "switch from" |
| Investigation | SYMPTOMS -> INVESTIGATE -> REPORT | "why", "investigate", "diagnose" |

**Key rules:** CLASSIFY is mandatory and confirmed with user. TDD always (except spike). User controls pace in SPECIFY. Challenger is context-isolated. Shipped without docs means not shipped. Don't auto-merge.

**Example:**
```
/brana:build "JWT authentication for the API"
/brana:build                              -- asks what to build
```

**Related:** backlog (enters build via `pick`), challenge (reviews spec), retrospective (stores learnings at CLOSE)

---

### `/brana:onboard`

Scan and diagnose a project -- tech stack, structure, stage, gaps, patterns.

**Trigger:** First session on a new project, taking over an existing project, periodic health check.
**Allowed tools:** Bash, Read, Glob, Grep, Write, AskUserQuestion

**Process:** Detect project type (code/venture/hybrid) -> Scan structure (manifests, docs, CLAUDE.md, tests) -> Recall patterns from memory -> Gap report (present/partial/missing) -> Output summary.

**Key rule:** Diagnostic only -- does not create files. Use `/brana:align` for active structure creation.

**Related:** align (implements what onboard finds), client-scanner agent (spawned during assessment)

---

### `/brana:align`

Actively align a project with brana practices.

**Trigger:** Initial project setup or structural realignment.
**Allowed tools:** Bash, Read, Write, Edit, Glob, Grep, AskUserQuestion
**Dependencies:** onboard

**Phases:** DISCOVER -> ASSESS -> PLAN -> IMPLEMENT -> VERIFY -> DOCUMENT.

**Tiers (code):** Minimal (4 items), Standard (13 items), Full (28 items).
**Stages (venture):** Cumulative by business stage (Discovery through Scale).

**Related:** onboard (runs diagnostic first), build (implements features after alignment)

---

### `/brana:client-retire`

Archive a client's patterns and mark them as historical.

**Trigger:** Retiring a client or archiving knowledge.
**Allowed tools:** Bash, Read, Write, Glob, Grep, AskUserQuestion

**Process:** Identify client -> Query all patterns -> Categorize (transferable / historical / deletable) -> Archive with tags -> Update portfolio.md.

**Key rule:** Never deletes -- only tags and archives.

**Related:** archiver agent (spawned for pattern categorization), memory (manages patterns)

---

## learning

### `/brana:challenge`

Dual-model adversarial review. Opus stress-tests reasoning; Gemini retrieves documented constraints.

**Trigger:** Significant decision, plan, or architecture needs review.
**Allowed tools:** Task, Read, Glob, Grep, NotebookLM MCP tools, AskUserQuestion
**Context:** fork (runs in isolated context)

**Flavors:** Pre-mortem, Simplicity challenger, Assumption buster, Adversarial reviewer.

**Process:** Gather context -> Choose flavor -> Launch Opus challenger + Gemini retriever in parallel -> Merge findings with confidence tiers -> Present report -> Store outcome.

**Confidence tiers:** HIGH (both models agree or compliance check), MEDIUM (Opus-only or Gemini with citation), LOW (Gemini citing things not in docs).

**Key rule:** No arguments = self-challenge (targets your own last answer). Gemini is optional -- skill works with Opus alone.

**Example:**
```
/brana:challenge                         -- self-challenge last answer
/brana:challenge "the migration plan"    -- challenge specific plan
```

**Related:** build (spawns challenger during SPECIFY), retrospective (stores challenge outcomes)

---

### `/brana:research`

Research a topic, doc, or creator -- check sources, follow references recursively, produce findings.

**Trigger:** Deep research needed on any topic.
**Allowed tools:** Read, Glob, Grep, Bash, Write, WebSearch, WebFetch, Task, NotebookLM MCP tools, AskUserQuestion
**Context:** fork

**Usage:**
```
/brana:research context engineering       -- topic research
/brana:research 14                        -- research updates for doc 14
/brana:research creator:simon-willison    -- check a creator's output
/brana:research leads                     -- process queued leads
/brana:research registry                  -- registry health report
/brana:research --refresh [scope]         -- batch dimension doc refresh
```

**Flags:** `--nlm` (enhance with NotebookLM), `--refresh [scope]` (batch refresh mode).

**Architecture:** 3-phase loop. Phase 1: Wide scan (metadata only, max 5-8 scouts). Phase 2: Triage (classify findings). Phase 3: Deep dive (targeted WebFetch, max 3 scouts). Max 14 scouts total.

**Key rules:** Never modify dimension docs directly. Never modify the registry directly. No WebFetch in Phase 1. Read temp files incrementally.

**Related:** memory (stores findings), maintain-specs (propagates research updates)

---

### `/brana:memory`

Knowledge system operations -- recall, cross-pollinate, audit.

**Trigger:** Pattern queries, cross-client transfer, monthly knowledge audits.
**Allowed tools:** Bash, Read, Glob, Grep, AskUserQuestion

**Subcommands:**

| Subcommand | Synopsis |
|------------|----------|
| `recall [query]` | Search patterns (default when no subcommand) |
| `pollinate [query]` | Cross-client pattern transfer |
| `review` | Monthly knowledge health audit |
| `review --audit [doc]` | Cross-doc contradiction detection |

**Key rules:** Don't auto-modify patterns. Skip test data. Ask for clarification when needed.

**Related:** retrospective (stores patterns), close (stores session patterns), research (produces findings)

**Example:**
```
/brana:memory Docker Swarm networking    -- recall patterns
/brana:memory pollinate auth patterns    -- find cross-client auth patterns
/brana:memory review                     -- monthly health audit
/brana:memory review --audit 14          -- audit doc 14 for contradictions
```

---

### `/brana:retrospective`

Store a learning or pattern in the knowledge system.

**Trigger:** After notable discoveries, unexpected issues, successful workarounds, or reusable patterns.
**Allowed tools:** Bash, Read, Write, Glob, Grep, AskUserQuestion

**Process:** Structure learning as pattern (problem, solution, tags, confidence 0.5) -> Store in claude-flow or MEMORY.md fallback -> Review recalled patterns for promotion/demotion -> Backup knowledge.

**Promotion:** Patterns with 3+ recalls or correction_weight >= 2 get promoted to confidence 0.8 and transferable.

**Related:** close (triggers retrospective at session end), build (runs mini-debrief after each task), memory (manages stored patterns)

---

## venture

### `/brana:review`

Business review -- weekly health check, monthly close + plan, or ad-hoc growth audit.

**Trigger:** Periodic business reviews or metrics assessment.
**Allowed tools:** Read, Write, Glob, Grep, Bash, AskUserQuestion
**Dependencies:** pipeline, financial-model

**Subcommands:**

| Subcommand | Synopsis |
|------------|----------|
| `weekly` (default) | Portfolio health, zombie cleanup, metrics delta, ship log, next-week planning |
| `monthly` | Monthly close + forward plan (P&L, actuals vs projections, targets) |
| `check` | Ad-hoc AARRR funnel audit with traffic-light metrics |

**Key rules:** Business model drives metrics. Stage drives scope. Store trends consistently. Bottleneck -> action.

**Example:**
```
/brana:review                -- weekly review
/brana:review monthly        -- monthly close + plan
/brana:review check          -- ad-hoc health check
```

**Related:** pipeline (feeds deal data), financial-model (feeds projections), metrics-collector agent (gathers data)

---

### `/brana:venture-phase`

Plan and execute a business milestone with learning loops.

**Trigger:** Executing a business milestone (launch, hiring, fundraise, expansion).
**Allowed tools:** Bash, Read, Write, Edit, Glob, Grep, Task, AskUserQuestion

**Milestone types:** Product Launch (with pre-launch and production readiness gates), Hiring Round, Fundraise, Market Expansion, Process Overhaul, Custom.

**Process:** Orient (identify milestone, detect stage) -> Plan (generate work items, wait for approval) -> Recall (search patterns) -> Execute (work items with mini-debriefs) -> Validate (check exit criteria) -> Debrief -> Report.

**Related:** review (assesses business health), pipeline (tracks leads from launches)

---

### `/brana:pipeline`

Sales pipeline tracking -- leads, deals, conversions, follow-ups.

**Trigger:** Tracking leads, updating deals, reviewing pipeline health.
**Allowed tools:** Read, Write, Glob, Grep, Bash, AskUserQuestion

**Actions:** Add lead, Update deal, Log interaction, Mark closed, Pipeline snapshot.

**Stage-dependent templates:** Discovery (simple contact list), Validation (basic funnel: Lead -> Trial -> Paid), Growth+ (full pipeline with weighted stages).

**Key rules:** Markdown first (MCP integrations are optional). Follow-ups are the highest-value output. Flag stale deals. Record win/loss reasons.

**Related:** review (consumes pipeline data), pipeline-tracker agent (analyzes pipeline state)

---

### `/brana:financial-model`

Revenue projections, scenario analysis, P&L, unit economics, cash flow.

**Trigger:** Fundraise prep, quarterly planning, building a business case.
**Allowed tools:** Read, Write, Glob, Grep, Bash, AskUserQuestion

**Process:** Detect context -> Business model type (SaaS/Marketplace/Service/E-commerce/Hybrid) -> Revenue projection (3 scenarios: base/upside/downside) -> P&L template (stage-appropriate) -> Unit economics (CAC, LTV, LTV:CAC, payback, margin) -> Cash flow (burn rate, runway, break-even) -> Output to `docs/financial/model-YYYY-MM.md` -> Optional Google Sheets export.

**Key rules:** Assumptions must be explicit. Three scenarios are mandatory. Stage drives detail level.

**Related:** review (monthly close uses financial data), gsheets (optional spreadsheet export)

---

### `/brana:proposal`

Generate a client proposal -- interview-driven, structured markdown.

**Trigger:** Preparing a service proposal for a client.
**Allowed tools:** Bash, Read, Write, Glob, Grep

**Process:** Parse arguments -> Locate project -> Scan existing context -> Interview (problem, findings, options, recommendation, rate, timeline, deliverables) -> Generate proposal in Spanish -> Add page breaks -> Write file.

**Output:** `propuesta-{slug}.md` at project root. All content in Spanish.

**Key rules:** Rate defaults to $65/hr. Author is always "Martin Rios". Hours must be specific. Don't invent technical details.

**Related:** export-pdf (converts proposal to PDF)

---

## session

### `/brana:close`

End a session -- extract learnings, write handoff note, store patterns, detect doc drift.

**Trigger:** User says "done", "bye", "closing", or similar. End of implementation session. Before switching projects.
**Allowed tools:** Bash, Read, Write, Edit, Glob, Grep, AskUserQuestion, Agent

**Steps:** Gate check (skip if read-only session) -> Gather evidence (git log, conversation) -> Extract and classify findings (errata/learning/issue via debrief-analyst agent) -> Write errata entries -> Store learnings as patterns -> Detect doc drift -> Write handoff note -> Store session metadata -> Report.

**Key rules:** Extract from evidence, don't invent. Learnings must be actionable. Gate on changes (read-only = minimal handoff). Suggest, don't execute.

**Related:** retrospective (stores individual patterns), build (CLOSE step at end of builds), debrief-analyst agent (spawned for analysis)

---

## capture

### `/brana:log`

Capture events -- links, calls, meetings, ideas, observations -- into a searchable append-only log.

**Trigger:** Something happened and you want to record it quickly.
**Allowed tools:** Read, Write, Edit, Glob, Grep, Bash, AskUserQuestion

**Subcommands:**

| Subcommand | Synopsis |
|------------|----------|
| `"text with #tags"` | Quick append (default) |
| `bulk` | Paste multi-line content (WhatsApp dumps, meeting notes) |

**File:** `~/.claude/memory/event-log.md` (single global file).

**Features:** Inline `#tags` for filtering. URL detection with optional research task creation. Automatic archival (entries >90 days when file >500 lines). WhatsApp dump parsing and deduplication.

**Key rules:** Append-only. Tags, not CWD. Confirm URLs before creating tasks.

**Related:** backlog (log entries can become tasks via URL promotion), pipeline (log captures first contact)

**Example:**
```
/brana:log "Call with Juan from Kapso -- interested in onboarding #somos #call"
/brana:log bulk                        -- paste WhatsApp dump
```

---

## tools

### `/brana:notebooklm-source`

Guided workflow to prepare and format sources for NotebookLM.

**Trigger:** Preparing documents for NotebookLM ingestion.
**Allowed tools:** Read, Write, Edit, Glob, Grep, Bash, Task, NotebookLM MCP tools, AskUserQuestion

**Recipes:**

| Recipe | Synopsis |
|--------|----------|
| `prepare [path]` | Reformat one file for optimal ingestion |
| `curate [name]` | Plan a notebook: prepare multiple sources, produce upload package |
| `synthesis [notebook]` | Query a live notebook, generate a synthesis meta-source |
| `audio-prompt [topic]` | Generate a custom Audio Overview prompt |
| `validate [path]` | Score a file's NotebookLM-readiness |
| `batch [glob]` | Validate + prepare multiple files |

**Step labels:** CLAUDE (automatic), YOU (user action), WAIT (pause for confirmation).

**Validation scores:** EXCELLENT (all pass), GOOD (1-2 minor issues), NEEDS WORK (structural issues), POOR (no structure).

**Related:** research (produces findings that can be prepared as NotebookLM sources), challenge (uses NotebookLM for Gemini retrieval)

---

## utility

### `/brana:scheduler`

Manage scheduled brana jobs.

**Trigger:** Managing scheduled jobs.
**Allowed tools:** Bash, AskUserQuestion

**Commands (via `brana-scheduler` CLI):**

| Action | Command |
|--------|---------|
| Show all jobs | `brana-scheduler status` |
| Show job logs | `brana-scheduler logs <job-name>` |
| Enable/disable | `brana-scheduler enable/disable <job-name>` |
| Run now | `brana-scheduler run <job-name>` |
| Validate config | `brana-scheduler validate` |
| Deploy | `brana-scheduler deploy` |
| Teardown | `brana-scheduler teardown` |

**Job types:** `skill` (runs a `/brana:*` skill), `command` (runs a shell command). Config at `~/.claude/scheduler/scheduler.json`. Schedule syntax: systemd OnCalendar format.

---

### `/brana:export-pdf`

Convert a markdown file to PDF using mdpdf.

**Trigger:** Exporting proposals, SOPs, or any markdown to PDF.
**Allowed tools:** Bash, Read, Glob, AskUserQuestion

**Process:** Parse arguments -> Resolve path -> Check for project CSS (`pdf-style.css`) -> Run mdpdf -> Report with file size and open option.

**Related:** proposal (recommends export-pdf after generating)

**Example:**
```
/brana:export-pdf propuesta-integracion-payway.md
```

---

### `/brana:gsheets`

Google Sheets via MCP -- read, write, create, list, share spreadsheets.

**Trigger:** Reading, writing, or managing Google Sheets data.
**Allowed tools:** (uses MCP tools dynamically via ToolSearch)

**Actions:**

| Action | Synopsis |
|--------|----------|
| `list` | List spreadsheets or folders |
| `read <spreadsheet> [sheet] [range]` | Read data |
| `write <spreadsheet> <sheet> <range>` | Update data |
| `create <title>` | Create new spreadsheet |
| `summary <spreadsheet>` | Quick overview |
| `share <spreadsheet> <email> [role]` | Share access |

**Performance rules:** Always specify a range. Never set `include_grid_data: true`. Batch over individual. Use `get_multiple_sheet_data` for 2+ sheets.

**Related:** review (reads metrics from Sheets), financial-model (optional Sheets export)

---

### `/brana:respondio-prompts`

Respond.io AI agent prompt engineering -- instructions, actions, KB files, multi-agent architectures.

**Trigger:** Writing or reviewing Respond.io agent prompts, designing multi-agent flows.
**Allowed tools:** Read, Write, Edit, Glob, Grep, Task, WebSearch, WebFetch, AskUserQuestion

**Process:** Orient (detect context, classify task) -> Audit (15-item checklist against platform constraints) -> Write/Fix (4-part framework: CONTEXT -> ROLE -> FLOW -> BOUNDARIES) -> Validate (char counts, field names, handoff safety, anti-loop).

**Key constraints:** Instructions <= 10,000 chars. Action prompts <= 1,000 chars. Last 20 messages visible. 8 action types with specific syntax.

**Related:** meta-template (WhatsApp templates for the same ecosystem)

---

### `/brana:meta-template`

Write Meta WhatsApp templates optimized for Utility classification.

**Trigger:** Creating or reviewing WhatsApp Business templates.
**Allowed tools:** Read, Write, Edit, Glob, Grep, Task, AskUserQuestion

**Process:** Orient (detect project, gather requirements) -> Classify (Utility or Marketing, pick tier) -> Write (C-level formula with transactional anchor) -> Validate (kill line scan, char limits, anchor check) -> Appeal (if needed).

**Kill lines (never include):** Emojis, "Como estas?", generic greetings without anchor, promotional buttons.

**Tiers:** Tier 1 (C-level, natural transactional anchor -- no appeal needed), Tier 2 (D-level, appeal required), Marketing (submit as Marketing).

**Related:** respondio-prompts (same Respond.io ecosystem)
