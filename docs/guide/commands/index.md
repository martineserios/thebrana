# Command Reference

All brana commands, grouped by workflow.

## Build & Development

| Command | Description |
|---------|-------------|
| `/brana:build [description]` | Build anything — auto-detects strategy (feature, bug fix, refactor, spike, migration, investigation, greenfield) |
| `/brana:close` | End session — extract learnings, write handoff, store patterns |
| `/brana:challenge` | Adversarial review of a plan or architecture decision |
| `/brana:docs [guide\|tech\|overview\|all] [task-id]` | Generate and update living documentation — composable building block for CLOSE and other skills |
| `/brana:reconcile` | Detect and fix spec-vs-implementation drift |

## Task Management

| Command | Description |
|---------|-------------|
| `/brana:backlog plan [project]` | Plan a phase interactively |
| `/brana:backlog status [project]` | Progress overview |
| `/brana:backlog next [project]` | Next unblocked task by priority |
| `/brana:backlog start <id>` | Begin work (enters /brana:build for code tasks) |
| `/brana:backlog done [id]` | Complete task (manual/external only — code tasks use /brana:build CLOSE) |
| `/brana:backlog add "description"` | Quick-add a task |
| `/brana:backlog status --all` | Cross-project task view |
| `/brana:backlog roadmap [project]` | Full tree view |
| `/brana:backlog tags [project]` | Tag inventory and filtering |
| `/brana:backlog context <id>` | View or set task context |
| `/brana:backlog triage` | Research-informed priority reassessment |

## Capture & Research

| Command | Description |
|---------|-------------|
| `/brana:log "text"` | Quick event capture with inline #tags |
| `/brana:log bulk` | Paste and parse multiple entries |
| `/brana:research [topic]` | Research a topic, doc, or creator |
| `/brana:research --refresh [scope]` | Batch refresh dimension docs |

## Knowledge & Learning

| Command | Description |
|---------|-------------|
| `/brana:memory [query]` | Search patterns (default: recall) |
| `/brana:memory pollinate` | Cross-project pattern transfer |
| `/brana:memory review` | Monthly knowledge health audit |
| `/brana:memory review --audit` | Cross-doc contradiction detection |
| `/brana:retrospective` | Store a learning or pattern |

## Project Setup

| Command | Description |
|---------|-------------|
| `/brana:onboard` | Scan and diagnose a project (code, venture, or hybrid) |
| `/brana:align` | Implement project structure based on /brana:onboard findings |
| `/brana:acquire-skills` | Find and install skills for tech gaps |
| `/brana:audit` | Security scan — secrets, hook permissions, MCP count, dangerous settings |

## Spec Maintenance

| Command | Description |
|---------|-------------|
| `/brana:maintain-specs` | Cascade spec changes through doc layers |

## Business / Venture

| Command | Description |
|---------|-------------|
| `/brana:review` | Weekly health check (default) |
| `/brana:review monthly` | Monthly close + forward plan |
| `/brana:review check` | Ad-hoc AARRR funnel audit |
| `/brana:review routing` | Model routing calibration |
| `/brana:review harness` | Harness simplification check (quarterly) |
| `/brana:pipeline` | Sales pipeline tracking |
| `/brana:venture-phase [type]` | Execute a business milestone |
| `/brana:financial-model` | Revenue projections and scenario analysis |
| `/brana:proposal` | Generate a client proposal |

## Utilities

| Command | Description |
|---------|-------------|
| `/brana:export-pdf` | Convert markdown to PDF |
| `/brana:gsheets` | Google Sheets operations |
| `/brana:notebooklm-source` | Prepare sources for NotebookLM |
| `/brana:respondio-prompts` | Respond.io AI agent prompts |
| `/brana:meta-template` | WhatsApp template optimization |
| `/brana:scheduler` | Scheduled jobs |
| `/brana:client-retire` | Archive a project |
