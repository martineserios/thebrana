# Getting Started

## What is brana?

Brana is a plugin for Claude Code that adds structure to how you work with AI. Instead of starting each session from scratch, brana gives Claude:

- **Skills** — slash commands like `/brana:build` that guide complex workflows step by step
- **Rules** — behavioral guidelines (test before commit, branch before edit, research before building)
- **Hooks** — automatic actions (recall relevant context on session start, enforce spec-first on feature branches)
- **Agents** — specialized sub-agents that fire when needed (challenger reviews your plans, scout researches topics)

The result: Claude remembers what it learned, follows consistent practices, and gets better at helping you over time.

## Install

You need [Claude Code](https://claude.com/claude-code) v1.0.33 or later.

### Step 1: Install the plugin

Open Claude Code and run:

```
/plugin marketplace add martineserios/thebrana
/plugin install brana
```

This gives you all skills, hooks, and agents. They load automatically in every session.

**For contributors** who want to edit brana itself:

```bash
git clone https://github.com/martineserios/thebrana.git
cd thebrana
claude --plugin-dir ./system
```

### Step 2: Set up the identity layer (optional but recommended)

The plugin gives Claude tools. The identity layer gives Claude a consistent personality and rules:

```bash
cd thebrana
./bootstrap.sh
```

This copies a few files to `~/.claude/` — Claude's global config directory. It's safe to run multiple times. Run `./bootstrap.sh --check` first if you want to see what it would do.

**What it deploys:**

| File | What it does |
|------|-------------|
| `CLAUDE.md` | Claude's identity — principles, portfolio awareness, agent table |
| `rules/*.md` | Behavioral rules — git discipline, TDD, context management |
| `scripts/*.sh` | Helper scripts used by hooks and skills |
| `statusline.sh` | Status bar showing branch, task, and context usage |
| `scheduler/` | Scheduled jobs (optional, for recurring tasks) |

## First session

Start Claude Code normally. If hooks are active, you'll see brana working automatically:

1. **Session start** — the hook recalls relevant patterns and shows active tasks
2. **You describe work** — "add user auth", "fix the login bug", "research caching strategies"
3. **Claude picks the right approach** — `/brana:build` detects whether it's a feature, bug fix, refactor, spike, migration, or investigation
4. **Work happens with guardrails** — tests before code, branches before edits, specs before implementation
5. **Session end** — the hook captures what was learned for next time

## Core workflow

### Building things

```
/brana:build "add payment processing"
```

This is the main command. It auto-detects the type of work and guides you through:

| Type | When | Flow |
|------|------|------|
| Feature | Adding new capability | Specify → Plan → Build → Close |
| Bug fix | Something's broken | Reproduce → Diagnose → Fix → Close |
| Refactor | Same behavior, better structure | Verify coverage → Build → Close |
| Spike | "Can we...?" questions | Question → Experiment → Answer |
| Investigation | "Why is...?" questions | Symptoms → Investigate → Report |
| Migration | Switching from X to Y | Specify → Plan → Build (careful) → Close |
| Greenfield | New project from scratch | Onboard → Specify → Plan → Build → Close |

### Managing tasks

```
/brana:backlog plan              — break work into tasks
/brana:backlog pick t-015       — pick a task, enter the build loop
/brana:backlog list              — see what's pending
```

Tasks live in `.claude/tasks.json` in your project. They track status, priority, dependencies, and connect to git branches.

### Ending a session

```
/brana:close
```

Extracts what was learned, writes a handoff note for the next session, and stores patterns in the knowledge system.

## Working across clients

Brana works from any directory. Open Claude Code in your project folder and all brana skills are available:

```bash
cd ~/projects/my-app
claude                          # brana plugin loads automatically
```

Each project can have its own `.claude/CLAUDE.md` with project-specific conventions. Brana's global rules combine with project-local rules.

## Key commands

| Command | What it does |
|---------|-------------|
| `/brana:build` | Build anything — 7 strategies for different work types |
| `/brana:close` | End session — extract learnings, write handoff |
| `/brana:backlog` | Manage tasks — plan, track, navigate |
| `/brana:log` | Capture events — calls, meetings, ideas, links |
| `/brana:research` | Research a topic — recursive discovery |
| `/brana:memory` | Query the knowledge system |
| `/brana:onboard` | Diagnose a new project |
| `/brana:align` | Set up project structure |
| `/brana:review` | Business health — weekly, monthly, or ad-hoc |
| `/brana:challenge` | Adversarial review of a plan or decision |

See [commands/index.md](commands/index.md) for the full list.

## Concepts

See [concepts.md](concepts.md) for the glossary of terms (skills, rules, hooks, agents, identity layer, knowledge system).
