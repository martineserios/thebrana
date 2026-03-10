# brana

A plugin for [Claude Code](https://claude.com/claude-code) that turns it into a systematic development partner. It adds skills (slash commands), behavioral rules, event hooks, and specialized agents — so Claude learns from every session, follows engineering discipline, and works consistently across all your projects.

## What you get

- **37 skills** — `/brana:build`, `/brana:backlog`, `/brana:research`, `/brana:close`, and more. One command to build features, fix bugs, run spikes, manage tasks, or review business health.
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

## Documentation

| Guide | What it covers |
|-------|---------------|
| [Getting Started](docs/guide/getting-started.md) | Install, first session, core workflow |
| [Commands](docs/guide/commands/index.md) | All 37 skills with descriptions and usage |
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

## Version

v0.7.0 — Plugin Architecture

| Version | Milestone |
|---------|-----------|
| v0.7.0 | Plugin packaging, namespace migration, bootstrap.sh |
| v0.6.0 | Unified repo (enter + thebrana merged), documentation |
| v0.5.0 | Project alignment, venture management |
| v0.4.0 | Validation, context budget, self-documentation |
| v0.3.0 | Learning loop, knowledge health |
| v0.2.0 | Hook system (session start/end, spec-first gate) |
| v0.1.0 | Skills, rules, deploy scripts |

## License

MIT
