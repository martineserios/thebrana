# Command Reference

All brana commands, grouped by workflow.

## Build & Development

| Command | Description |
|---------|-------------|
| `/build [description]` | Build anything — auto-detects strategy (feature, bug fix, refactor, spike, migration, investigation, greenfield) |
| `/close` | End session — extract learnings, write handoff, store patterns |
| `/challenge` | Adversarial review of a plan or architecture decision |
| `/reconcile` | Detect and fix spec-vs-implementation drift |

## Task Management

| Command | Description |
|---------|-------------|
| `/tasks plan [project]` | Plan a phase interactively |
| `/tasks status [project]` | Progress overview |
| `/tasks next [project]` | Next unblocked task by priority |
| `/tasks start <id>` | Begin work (enters /build for code tasks) |
| `/tasks done [id]` | Complete task (manual/external only — code tasks use /build CLOSE) |
| `/tasks add "description"` | Quick-add a task |
| `/tasks portfolio` | Cross-project task view |
| `/tasks roadmap [project]` | Full tree view |
| `/tasks tags [project]` | Tag inventory and filtering |
| `/tasks context <id>` | View or set task context |
| `/tasks reprioritize` | Research-informed priority reassessment |

## Capture & Research

| Command | Description |
|---------|-------------|
| `/log "text"` | Quick event capture with inline #tags |
| `/log bulk` | Paste and parse multiple entries |
| `/research [topic]` | Research a topic, doc, or creator |
| `/research --refresh [scope]` | Batch refresh dimension docs |

## Knowledge & Learning

| Command | Description |
|---------|-------------|
| `/memory [query]` | Search patterns (default: recall) |
| `/memory pollinate` | Cross-project pattern transfer |
| `/memory review` | Monthly knowledge health audit |
| `/memory review --audit` | Cross-doc contradiction detection |
| `/retrospective` | Store a learning or pattern |

## Project Setup

| Command | Description |
|---------|-------------|
| `/onboard` | Scan and diagnose a project (code, venture, or hybrid) |
| `/align` | Implement project structure based on /onboard findings |
| `/acquire-skills` | Find and install skills for tech gaps |

## Spec Maintenance

| Command | Description |
|---------|-------------|
| `/maintain-specs` | Cascade spec changes through doc layers |

## Business / Venture

| Command | Description |
|---------|-------------|
| `/review` | Weekly health check (default) |
| `/review monthly` | Monthly close + forward plan |
| `/review check` | Ad-hoc AARRR funnel audit |
| `/pipeline` | Sales pipeline tracking |
| `/venture-phase [type]` | Execute a business milestone |
| `/financial-model` | Revenue projections and scenario analysis |
| `/proposal` | Generate a client proposal |

## Utilities

| Command | Description |
|---------|-------------|
| `/export-pdf` | Convert markdown to PDF |
| `/gsheets` | Google Sheets operations |
| `/notebooklm-source` | Prepare sources for NotebookLM |
| `/respondio-prompts` | Respond.io AI agent prompts |
| `/meta-template` | WhatsApp template optimization |
| `/scheduler` | Scheduled jobs |
| `/project-retire` | Archive a project |
