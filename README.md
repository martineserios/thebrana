# brana

> The mastermind brain system — Claude Code configuration files that deploy to `~/.claude/`, creating a cross-project intelligence layer that learns, remembers, and improves across every session.

## Quick Start

```bash
./validate.sh && ./deploy.sh
```

## Architecture

Three layers, each with its own persistence and scope:

```
┌─────────────────────────────────────────┐
│  IDENTITY — Who am I?                   │
│  ~/.claude/CLAUDE.md                     │
│  Universal principles, personality       │
├─────────────────────────────────────────┤
│  INTELLIGENCE — What do I know?         │
│  claude-flow memory.db                   │
│  Cross-project patterns, learnings       │
├─────────────────────────────────────────┤
│  CONTEXT — What am I working on?        │
│  project/.claude/ (per-project)         │
│  Local rules, skills, conventions        │
└─────────────────────────────────────────┘
```

## File Structure

```
thebrana/
├── system/                         ← Deploys to ~/.claude/
│   ├── CLAUDE.md                   ← Mastermind identity
│   ├── skills/ (39)                ← Invokable slash commands
│   ├── rules/ (12)                 ← Always-loaded behavioral rules
│   ├── hooks/ (10)                 ← Event-driven shell scripts
│   ├── agents/ (11)               ← Specialized sub-agents
│   ├── scripts/ (7)               ← Helper scripts
│   ├── commands/ (7)              ← CLI commands
│   └── settings.json              ← Hook registration
├── docs/
│   └── guide/                     ← System documentation
├── deploy.sh                       ← Validate + copy to ~/.claude/
├── validate.sh                     ← Pre-deploy checks
├── task-guide.md                   ← Task management user guide
├── venture-guide.md                ← Venture management user guide
└── README.md
```

## Guides

| Guide | For |
|-------|-----|
| **[System Guide](docs/guide/system-guide.md)** | What brana is, how it works, getting started |
| **[Skills Catalog](docs/guide/skills.md)** | All 39 skills — description, category, when to use |
| **[Hooks Explained](docs/guide/hooks.md)** | All 10 hooks — trigger, behavior, output |
| **[Agent Roster](docs/guide/agents.md)** | All 11 agents — model, tools, auto-delegation triggers |
| **[Extending Brana](docs/guide/extending.md)** | How to add skills, rules, hooks, and agents |
| **[Venture Guide](venture-guide.md)** | Managing business projects with brana |
| **[Task Guide](task-guide.md)** | Planning and tracking work across projects |

## Skills (39)

### Development (13)

| Skill | Description |
|-------|-------------|
| `/build-phase` | Plan and implement the next roadmap phase |
| `/build-feature` | Guide a feature from zero to shipped |
| `/decide` | Create Architecture Decision Records |
| `/brana:challenge` | Dual-model adversarial review of plans and decisions |
| `/debrief` | Extract errata and learnings from current session |
| `/brana:reconcile` | Detect spec-vs-implementation drift, plan fixes |
| `/back-propagate` | Propagate implementation changes back to specs |
| `/brana:research` | Research a topic, doc, or creator with recursive discovery |
| `/refresh-knowledge` | Research external updates to dimension docs |
| `/knowledge` | Browse, annotate, review, and reindex the knowledge base |
| `/brana:tasks` | Manage tasks — plan, track, navigate phases and streams |
| `/pickup` | Resume from last session with handoff context |
| `/usage-stats` | Token usage analytics and model distribution |

### Quality & Memory (6)

| Skill | Description |
|-------|-------------|
| `/brana:memory` | Recall, cross-pollinate, review knowledge health |
| `/brana:retrospective` | Store learnings and patterns in the knowledge system |
| `/project-align` | Align a project with brana development practices |
| `/project-onboard` | Bootstrap a new project with portfolio knowledge |
| `/brana:project-retire` | Archive a project's patterns when retiring |
| `/personal-check` | Personal life check — tasks, life areas, journal |

### Business / Venture (13)

| Skill | Description |
|-------|-------------|
| `/venture-align` | Set up business management structure |
| `/venture-onboard` | Discover and diagnose a business project |
| `/brana:venture-phase` | Plan and execute a business milestone |
| `/growth-check` | Business health audit — AARRR funnel analysis |
| `/experiment` | Growth experiment loop — hypothesis to learning |
| `/morning` | Daily operational check — focus card with priorities |
| `/weekly-review` | Weekly cadence review — portfolio health, ship log |
| `/monthly-close` | Monthly financial close — P&L, trends, runway |
| `/monthly-plan` | Forward-looking monthly plan — targets, priorities |
| `/brana:financial-model` | Revenue projections, scenario analysis, unit economics |
| `/brana:pipeline` | Sales pipeline tracking — leads, deals, follow-ups |
| `/sop` | Create Standard Operating Procedures |
| `/brana:proposal` | Generate client proposals with cost breakdown |

### Integrations (7)

| Skill | Description |
|-------|-------------|
| `/brana:gsheets` | Google Sheets via MCP — read, write, manage |
| `/brana:notebooklm-source` | Prepare sources for NotebookLM upload |
| `/brana:export-pdf` | Convert markdown to PDF |
| `/brana:meta-template` | Write Meta WhatsApp templates for Utility classification |
| `/brana:respondio-prompts` | Respond.io AI agent prompt engineering |
| `/content-plan` | Marketing content planning — themes, calendar, tracking |
| `/brana:scheduler` | Scheduled jobs management |

## Rules (12)

| Rule | Purpose |
|------|---------|
| `context-budget` | Context window management thresholds |
| `delegation-routing` | Auto-delegate to agents, suggest skills |
| `doc-linking` | Relative-path markdown links |
| `git-discipline` | Branching, worktrees, conventional commits, `--no-ff` |
| `memory-framework` | CLAUDE.md vs MEMORY.md separation |
| `pm-awareness` | Check issues, link commits, track progress |
| `research-discipline` | Read project docs before web research |
| `sdd-tdd` | Test-first development, spec-before-code enforcement |
| `self-improvement` | Auto-learn from corrections, failures, sessions |
| `task-convention` | Task schema, branch mapping, status lifecycle |
| `universal-quality` | Test before commit, no secrets, type safety |
| `work-preferences` | Parallelism, simplicity, autonomous execution |

## Hooks (10)

| Hook | Event | Purpose |
|------|-------|---------|
| `session-start.sh` | SessionStart | Recall relevant patterns for current project |
| `session-start-venture.sh` | SessionStart | Detect venture projects, nudge daily-ops agent |
| `pre-tool-use.sh` | PreToolUse | Spec-first gate — block code before spec/test |
| `post-tool-use.sh` | PostToolUse | Log significant tool successes, detect corrections |
| `post-pr-review.sh` | PostToolUse | Nudge pr-reviewer agent after PR creation |
| `post-plan-challenge.sh` | PostToolUse | Nudge challenger agent after plan finalization |
| `post-sale.sh` | PostToolUse | Detect deal closures, snapshot to memory |
| `post-tasks-validate.sh` | PostToolUse | Validate tasks.json schema, auto-rollup parents |
| `post-tool-use-failure.sh` | PostToolUseFailure | Log tool failures, categorize errors |
| `session-end.sh` | SessionEnd | Flush session events, compute flywheel metrics |

## Agents (11)

| Agent | Model | Purpose |
|-------|-------|---------|
| `scout` | Haiku | Fast research — codebase exploration, web search |
| `memory-curator` | Haiku | Recall patterns, cross-pollinate, check knowledge health |
| `project-scanner` | Haiku | Scan project structure, detect stack, check alignment |
| `venture-scanner` | Haiku | Diagnose business project — stage, frameworks, gaps |
| `challenger` | Opus | Adversarial review of plans and architecture decisions |
| `debrief-analyst` | Opus | Extract errata, learnings, and patterns from sessions |
| `pr-reviewer` | Sonnet | Review PR diffs for quality, security, and correctness |
| `daily-ops` | Haiku | Daily venture focus card — health, actions, experiments |
| `metrics-collector` | Haiku | Collect venture metrics from multiple sources |
| `pipeline-tracker` | Haiku | Pipeline status — deal stages, follow-ups, trends |
| `archiver` | Haiku | Archive project patterns when retiring |

## Adding Components

See [Extending Brana](docs/guide/extending.md) for detailed instructions on adding skills, rules, hooks, and agents.

## Version History

| Version | Phase | Milestone |
|---------|-------|-----------|
| v0.1.0 | 1 — Foundation | Skills, rules, deploy scripts |
| v0.2.0 | 2 — Hooks | Learning loop (SessionStart/End, PreToolUse, PostToolUse) |
| v0.3.0 | 3 — Learning | Quarantine, two-layer memory, knowledge health |
| v0.4.0 | 4 — Quality | Validation, context budget, self-documentation |
| v0.5.0 | 5 — Alignment | `/project-align`, venture management skills |
| v0.6.0 | 6 — Documentation | System guide, skills catalog, hooks/agents/extending docs |
