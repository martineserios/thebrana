# brana

A plugin for [Claude Code](https://claude.com/claude-code) that turns it into a systematic development partner. It adds skills (slash commands), behavioral rules, event hooks, and specialized agents — so Claude learns from every session, follows engineering discipline, and works consistently across all your projects.

## What you get

- **25 skills** — `/brana:build`, `/brana:backlog`, `/brana:research`, `/brana:close`, and more. One command to build features, fix bugs, run spikes, manage tasks, or review business health.
- **12 rules** — Git discipline, test-first development, context budget management, research methodology. Always active, no setup needed.
- **10 hooks** — Automatic behaviors: recall patterns on session start, enforce spec-before-code on feature branches, capture learnings on session end.
- **11 agents** — Specialized sub-agents for code review, adversarial challenge, research, business ops, and more. They fire automatically when the situation matches.

## Install

### Option A: Plugin install (recommended)

In any Claude Code session:

```
/plugin marketplace add martineserios/thebrana
/plugin install brana
```

Done. All skills, hooks, and agents are available in every session.

### Option B: Dev mode (for contributors)

```bash
git clone https://github.com/martineserios/thebrana.git
cd thebrana
claude --plugin-dir ./system
```

Edits to `system/` take effect on next session — no deploy step.

### Optional: Identity layer

The plugin gives you the toolkit. The identity layer gives Claude a persistent personality, behavioral rules, and helper scripts across all sessions:

```bash
cd thebrana
./bootstrap.sh           # deploy to ~/.claude/ (safe to re-run)
./bootstrap.sh --check   # preview what would change
```

This copies CLAUDE.md, rules, and scripts to `~/.claude/`. Most users want both the plugin and the identity layer.

## Quick start

```
/brana:build "add user authentication"    — start building (auto-detects strategy)
/brana:backlog plan                         — plan work across a project
/brana:backlog pick t-015                  — pick a task and enter the build loop
/brana:close                              — end session, capture learnings
```

## Skills

| Skill | Description |
|-------|-------------|
| `/brana:build` | Build anything — features, bug fixes, refactors, spikes, migrations, investigations. Auto-detects strategy. |
| `/brana:backlog` | Manage the backlog — plan, track, navigate phases and streams. |
| `/brana:close` | End session — extract learnings, write handoff, store patterns. |
| `/brana:research` | Research a topic, doc, or creator — recursive discovery with source tracking. |
| `/brana:challenge` | Dual-model adversarial review of plans and architecture decisions. |
| `/brana:memory` | Knowledge operations — recall patterns, cross-pollinate, audit docs. |
| `/brana:retrospective` | Store a learning or pattern in the knowledge system. |
| `/brana:onboard` | Scan and diagnose a project — tech stack, structure, gaps. |
| `/brana:align` | Implement project structure based on onboard findings. |
| `/brana:reconcile` | Detect drift between specs and implementation, plan fixes. |
| `/brana:review` | Business review — weekly, monthly, or ad-hoc health check. |
| `/brana:venture-phase` | Plan and execute a business milestone — launch, hiring, fundraise. |
| `/brana:pipeline` | Sales pipeline tracking — leads, deals, conversions, follow-ups. |
| `/brana:financial-model` | Revenue projections, scenario analysis, P&L, unit economics. |
| `/brana:proposal` | Generate a client proposal — interview-driven with cost breakdown. |
| `/brana:log` | Capture events — links, calls, meetings, ideas — into a searchable log. |
| `/brana:gsheets` | Google Sheets via MCP — read, write, create, list, share. |
| `/brana:export-pdf` | Convert markdown to PDF. |
| `/brana:meta-template` | Write Meta WhatsApp templates optimized for Utility classification. |
| `/brana:respondio-prompts` | Respond.io AI agent prompt engineering and multi-agent flows. |
| `/brana:notebooklm-source` | Prepare and format sources for NotebookLM. |
| `/brana:scheduler` | Manage scheduled jobs. |
| `/brana:client-retire` | Archive a client's patterns and mark as historical. |
| `/brana:acquire-skills` | Find and install skills for project tech gaps. |

## Agents

| Agent | Model | When it fires |
|-------|-------|---------------|
| memory-curator | Haiku | Starting work, familiar problem, stuck |
| client-scanner | Haiku | New client, project health check |
| venture-scanner | Haiku | New business project |
| challenger | Opus | Plan or architecture decision forming |
| debrief-analyst | Opus | End of implementation session |
| scout | Haiku | Research tasks |
| archiver | Haiku | Retiring a client |
| daily-ops | Haiku | Session start on venture project |
| metrics-collector | Haiku | Business reviews (weekly, monthly, ad-hoc) |
| pipeline-tracker | Haiku | Pipeline tracking, deal events |
| pr-reviewer | Sonnet | PR creation (auto-triggered) |

## Documentation

| Guide | What it covers |
|-------|---------------|
| [Getting Started](docs/guide/getting-started.md) | Install, first session, core workflow |
| [Commands](docs/guide/commands/index.md) | All skills with descriptions and usage |
| [Concepts](docs/guide/concepts.md) | Key terms: skills, rules, hooks, agents, identity layer |
| [Build Workflow](docs/guide/workflows/build.md) | The unified build loop — 7 strategies |
| [Task Management](task-guide.md) | Planning and tracking work |
| [Venture Management](venture-guide.md) | Business projects — reviews, pipelines, milestones |

## How it works

Brana has two layers:

```
Plugin (loaded by Claude Code)              Identity layer (~/.claude/)
├── skills/    → /brana:* commands          ├── CLAUDE.md  → who Claude is
├── hooks/     → automatic behaviors        ├── rules/     → behavioral rules
├── agents/    → specialized sub-agents     ├── scripts/   → helper scripts
└── commands/  → agent commands             └── scheduler/ → scheduled jobs
```

The **plugin** is the toolkit — what Claude can do. It loads automatically via Claude Code's plugin system.

The **identity layer** is the foundation — how Claude thinks. It deploys once via `bootstrap.sh` and persists across sessions.

## Requirements

- [Claude Code](https://claude.com/claude-code) v1.0.33 or later
- Git

### Optional (for extended features)

- Node.js v20+ (for MCP integrations like context7)
- [claude-flow](https://www.npmjs.com/package/claude-flow) (for `/brana:memory` cross-client search)

## Version

v1.0.0

| Version | Milestone |
|---------|-----------|
| v1.0.0 | Marketplace publication, full documentation |
| v0.7.0 | Plugin packaging, namespace migration, bootstrap.sh |
| v0.6.0 | Unified repo (enter + thebrana merged), documentation |
| v0.5.0 | Project alignment, venture management |
| v0.4.0 | Validation, context budget, self-documentation |
| v0.3.0 | Learning loop, knowledge health |
| v0.2.0 | Hook system (session start/end, spec-first gate) |
| v0.1.0 | Skills, rules, deploy scripts |

## Security

See [SECURITY.md](SECURITY.md).

## License

MIT
