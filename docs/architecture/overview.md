# Brana System Guide

> The brain for Claude Code — a cross-client intelligence layer that learns, remembers, and improves across every session.

## What is Brana?

Brana turns Claude Code from a stateless assistant into a learning development partner. It deploys a set of configuration files — skills, rules, hooks, and agents — to `~/.claude/`, creating a system that:

- **Remembers** patterns, decisions, and mistakes across sessions and projects
- **Enforces** development discipline (spec-first, test-first, branch hygiene)
- **Automates** recurring workflows (session handoff, task tracking, venture management)
- **Learns** from every interaction through a feedback loop of hooks and memory

Without brana, each Claude Code session starts from zero. With brana, Claude starts each session with context about your projects, your preferences, and what worked before.

## Architecture

Three layers, each with its own persistence:

```
┌─────────────────────────────────────────┐
│  IDENTITY — Who am I?                   │
│  ~/.claude/CLAUDE.md                     │
│  Core principles, personality, portfolio │
├─────────────────────────────────────────┤
│  INTELLIGENCE — What do I know?         │
│  claude-flow memory.db                   │
│  Cross-project patterns, learnings       │
├─────────────────────────────────────────┤
│  CONTEXT — What am I working on?        │
│  project/.claude/ (per-project)         │
│  Local rules, tasks, conventions         │
└─────────────────────────────────────────┘
```

**Identity** is the `CLAUDE.md` file that defines who the assistant is — principles, agent table, portfolio index. It's loaded every session.

**Intelligence** is the memory system — claude-flow's `memory.db` stores patterns with semantic embeddings (all-MiniLM-L6-v2, 384-dim). The knowledge base (315+ sections from 33 dimension docs) is also indexed here.

**Context** is the per-project `.claude/` directory — project-specific `CLAUDE.md`, `tasks.json`, and auto memory.

## The Deploy Model

Brana uses a **two-layer deployment**: a plugin (loaded by Claude Code) and an identity layer (deployed via `bootstrap.sh`).

```
system/                               Plugin (loaded by Claude Code)
├── .claude-plugin/plugin.json        ← plugin manifest
├── skills/                           ← /brana:* slash commands
├── commands/                         ← agent commands
├── hooks/hooks.json + *.sh           ← event hooks
├── agents/                           ← specialized agents
└── CLAUDE.md                         ← mastermind identity

bootstrap.sh                          Identity layer → ~/.claude/
├── CLAUDE.md                         ← global identity
├── rules/                            ← behavioral rules
├── scripts/                          ← helper scripts
├── statusline.sh                     ← status bar
└── scheduler/                        ← scheduled jobs
```

You never edit `~/.claude/` directly. Edit `system/` (plugin loads it) or re-run `./bootstrap.sh` (identity layer).

## Session Lifecycle

Every session follows this arc:

### 1. Session Start

Two hooks fire automatically:

- **session-start.sh** — Derives the project name from git root, queries claude-flow for recent patterns, recalls relevant knowledge. Injects context via `additionalContext`.
- **session-start-venture.sh** — Detects venture clients (by checking for `docs/sops/`, `docs/okrs/`, etc.) and nudges the daily-ops agent if found.

The result: Claude starts the session already knowing what project you're in, what patterns apply, and what happened last time.

### 2. Active Work

During work, hooks monitor tool usage:

- **pre-tool-use.sh** — The spec-first gate. On `feat/*` branches in projects with `docs/decisions/`, blocks implementation file writes until spec or test activity exists on the branch.
- **post-tool-use.sh** — Logs significant tool successes. Detects corrections (edits to recently-created files) and test-file creation.
- **post-tool-use-failure.sh** — Logs tool failures with error categorization for cascade detection.
- **post-tasks-validate.sh** — Validates `tasks.json` schema and auto-rolls-up parent task status when subtasks complete.
- **post-plan-challenge.sh** — After `ExitPlanMode`, nudges the challenger agent for adversarial review.
- **post-pr-review.sh** — After `gh pr create`, nudges the pr-reviewer agent for automated code review.
- **post-sale.sh** — Detects deal closure events in pipeline files and snapshots to memory.

### 3. Session End

- **session-end.sh** — Flushes accumulated session events to persistent storage. Computes flywheel metrics: correction rate, auto-fix rate, test write rate, cascade rate, delegation count. Writes a session summary to claude-flow memory.

## The Feedback Loop

Brana's learning works through a closed loop:

```
Session Start → Recall patterns
       ↓
   Active Work → Hooks log events
       ↓
  Session End → Compute metrics, store learnings
       ↓
  Next Session → Recall improved patterns
```

**Corrections** are the primary learning signal. When Claude edits a file it recently created, the post-tool-use hook detects this as a correction — something went wrong the first time. These accumulate across sessions and surface patterns like "always check X before Y."

**Flywheel metrics** (computed at session end):
- `correction_rate` — fraction of writes that needed correction
- `auto_fix_rate` — corrections resolved without user intervention
- `test_write_rate` — fraction of implementation files with accompanying tests
- `cascade_rate` — how often changes propagate across files
- `delegation_count` — how many tasks were delegated to agents

## Memory System

Brana uses two layers of memory:

### Layer 1: Native Auto Memory

Claude Code's built-in per-project memory at `~/.claude/projects/*/memory/`. Each project gets a `MEMORY.md` file (200-line cap) for operational facts, preferences, and learnings. This works without any external dependencies.

- `CLAUDE.md` and `rules/*.md` — human-authored directives ("always X", "never Y")
- `MEMORY.md` — Claude-authored facts ("project uses X", "Y pattern worked")

### Layer 2: Claude-Flow Memory

The `claude-flow` MCP server provides semantic search over a SQLite database with ONNX embeddings. This enables cross-client pattern recall and knowledge base search.

Namespaces:
- `specs` — specification-related patterns
- `decisions` — architectural decisions
- `knowledge` — dimension doc content (315+ indexed sections)

When claude-flow is unavailable, the system degrades gracefully — auto memory still works, just without cross-client search.

## Skills

24 slash commands organized by purpose. Skills are markdown files with YAML frontmatter that define allowed tools and instructions.

Categories:
- **Development** — Build, ship, and maintain code
- **Quality & Memory** — Learn, recall, and align
- **Business/Venture** — Manage business projects
- **Integrations** — Connect to external tools

See [skills.md](skills.md) for the full catalog.

## Hooks

10 shell scripts that fire on Claude Code lifecycle events. They enforce discipline, log events, and nudge agents — without requiring user action.

See [hooks.md](hooks.md) for details on each hook.

## Agents

11 specialized sub-agents that auto-delegate when the situation matches. Agents are read-only (except Bash for CLI commands) — they return findings to the main context for the user to approve.

See [agents.md](agents.md) for the full roster.

## Rules

12 always-loaded behavioral directives that shape how Claude operates:

| Rule | Purpose |
|------|---------|
| `context-budget` | Context window management — thresholds and expensive-op avoidance |
| `delegation-routing` | Auto-delegate to agents, suggest skills when triggers match |
| `doc-linking` | Use relative-path markdown links, never bare "doc NN" |
| `git-discipline` | Branching, worktrees, conventional commits, `--no-ff` merges |
| `memory-framework` | CLAUDE.md vs MEMORY.md separation — facts vs rules |
| `pm-awareness` | Check issues before work, link commits, track progress |
| `research-discipline` | Read project docs before web research |
| `sdd-tdd` | Test-first development, spec-before-code enforcement |
| `self-improvement` | Auto-learn from corrections, failures, and sessions |
| `task-convention` | Task schema, branch mapping, status lifecycle |
| `universal-quality` | Test before commit, no secrets, type safety |
| `work-preferences` | Parallelism, simplicity, autonomous execution |

## Getting Started

### Prerequisites

- [Claude Code](https://claude.ai/code) CLI installed
- Git
- `jq` (for hooks)
- Optional: `claude-flow` MCP server for cross-client memory

### Install

```bash
# Dev mode (recommended for contributors)
claude --plugin-dir ./system

# Install from GitHub
/plugin marketplace add martineserios/thebrana
/plugin install brana

# Identity layer (CLAUDE.md, rules, scripts — run once)
./bootstrap.sh
```

### Verify

After install, start a new Claude Code session. You should see:
- Session start hook fires (pattern recall)
- `/brana:tasks` and other skills are available
- `pre-tool-use` gate activates on `feat/*` branches in projects with `docs/decisions/`

### First Session

```bash
# In any project
claude

# Check what brana knows about this project
/brana:memory recall

# See available tasks
/brana:tasks
```

## Project Setup

To configure a project for brana:

### Minimal Setup

Create `.claude/CLAUDE.md` with project identity — name, stack, conventions.

### Standard Setup (development projects)

```
project/
├── .claude/
│   ├── CLAUDE.md          ← Project identity
│   └── tasks.json         ← Task tracking
├── docs/
│   └── decisions/         ← ADRs (enables spec-first gate)
└── tests/                 ← Test directory
```

The `docs/decisions/` directory opts the project into spec-first enforcement. On `feat/*` branches, the `pre-tool-use` hook will block implementation writes until spec or test activity exists.

### Venture Setup (business projects)

```
project/
├── .claude/
│   ├── CLAUDE.md          ← Business context + stage
│   └── tasks.json         ← Task tracking
├── docs/
│   ├── sops/              ← Standard operating procedures
│   ├── okrs/              ← Objectives and key results
│   ├── metrics/           ← Health snapshots
│   ├── pipeline/          ← Deal tracking
│   └── venture/           ← Business planning
└── ...
```

The presence of venture directories (`docs/sops/`, `docs/okrs/`, etc.) triggers the `session-start-venture.sh` hook, which auto-delegates to the daily-ops agent.

## Guide Index

| Doc | What it covers |
|-----|---------------|
| [Skills Catalog](skills.md) | Skills — description, category, when to use |
| [Hooks Explained](hooks.md) | Hooks — trigger, behavior, output |
| [Agent Roster](agents.md) | Agents — model, tools, auto-delegation triggers |
| [Extending Brana](extending.md) | How to add skills, rules, hooks, and agents |
