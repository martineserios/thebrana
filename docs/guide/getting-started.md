# Getting Started

## What is brana?

Brana is a plugin for Claude Code that adds structure to how you work with AI. Instead of starting each session from scratch, brana gives Claude:

- **Skills** -- slash commands like `/brana:build` that guide complex workflows step by step
- **Rules** -- behavioral guidelines (test before commit, branch before edit, research before building)
- **Hooks** -- automatic actions (recall relevant context on session start, enforce spec-first on feature branches)
- **Agents** -- specialized sub-agents that fire when needed (challenger reviews your plans, scout researches topics)

The result: Claude remembers what it learned, follows consistent practices, and gets better at helping you over time.

## Prerequisites

| Requirement | Minimum | Check |
|-------------|---------|-------|
| Claude Code | v1.0.33+ | `claude --version` |
| Node.js | v18+ | `node --version` |
| jq | any | `jq --version` |

Node.js is required for claude-flow (the memory layer). jq is required by bootstrap, scheduler, and several hooks. Both are strongly recommended even if not strictly mandatory for the plugin alone.

## Installation

Brana has two layers. The **plugin** provides skills, hooks, and agents. The **identity layer** provides global rules, scripts, and scheduler. You need the plugin; the identity layer is optional but recommended.

### Path 1: Marketplace install (recommended)

Open Claude Code and run:

```
/plugin marketplace add martineserios/thebrana
/plugin install brana
```

This registers the brana marketplace and installs the plugin. Skills, hooks, and agents load automatically in every session.

### Path 2: Dev mode (contributors)

Clone the repo and point Claude Code at the system directory:

```bash
git clone https://github.com/martineserios/thebrana.git
cd thebrana
claude --plugin-dir ./system
```

Changes to `system/` take effect on the next session. No install step needed -- Claude Code reads directly from disk.

### Path 3: Bootstrap the identity layer

The plugin gives Claude tools. The identity layer gives Claude a consistent personality, behavioral rules, helper scripts, and a scheduler:

```bash
cd thebrana
./bootstrap.sh
```

This copies files to `~/.claude/` -- Claude's global config directory. It is idempotent and safe to run multiple times. Run `./bootstrap.sh --check` first to preview what it would do without applying changes.

**What bootstrap deploys:**

| Target | What it does |
|--------|-------------|
| `~/.claude/CLAUDE.md` | Claude's identity -- principles, portfolio awareness, agent table |
| `~/.claude/rules/*.md` | Behavioral rules -- git discipline, TDD, context management |
| `~/.claude/scripts/*.sh` | Helper scripts used by hooks and skills |
| `~/.claude/statusline.sh` | Status bar showing branch, task, and context usage |
| `~/.claude/scheduler/` | Scheduled jobs (systemd timers for recurring tasks) |
| `~/.claude/settings.json` | PostToolUse hooks (workaround for CC plugin bug) |
| `~/.claude/plugins/` | Plugin cache and marketplace registration |

Bootstrap also sets up claude-flow (memory layer) if it is installed globally via npm.

## First session walkthrough

Start Claude Code normally after installation. Here is what happens:

1. **Session start hook fires** -- brana recalls relevant patterns from memory and shows active tasks for the current project. You will see a brief status message.

2. **You describe work** -- tell Claude what you want to do. Examples: "add user auth", "fix the login bug", "research caching strategies".

3. **Try `/brana:build`** -- this is the main command. It auto-detects the type of work (feature, bug fix, refactor, spike, migration, investigation, or greenfield) and guides you through a structured flow:

   | Type | When | Flow |
   |------|------|------|
   | Feature | Adding new capability | Specify > Plan > Build > Close |
   | Bug fix | Something's broken | Reproduce > Diagnose > Fix > Close |
   | Refactor | Same behavior, better structure | Verify coverage > Build > Close |
   | Spike | "Can we...?" questions | Question > Experiment > Answer |
   | Investigation | "Why is...?" questions | Symptoms > Investigate > Report |
   | Migration | Switching from X to Y | Specify > Plan > Build (careful) > Close |
   | Greenfield | New project from scratch | Onboard > Specify > Plan > Build > Close |

4. **Guardrails activate** -- hooks enforce tests before code, branches before edits, and specs before implementation on feature branches.

5. **Session end** -- when you finish (or run `/brana:close`), the hook captures what was learned for next time.

## Verify installation

Run through this checklist to confirm everything is working:

- [ ] **Plugin loaded** -- type `/brana:` and tab-complete. You should see skills like `/brana:build`, `/brana:backlog`, `/brana:close`.
- [ ] **Hooks active** -- start a new session. You should see a brief session-start message from brana.
- [ ] **Rules present** (if bootstrapped) -- check `ls ~/.claude/rules/*.md`. You should see files like `git-discipline.md`, `sdd-tdd.md`.
- [ ] **Scheduler available** (if bootstrapped) -- run `brana-scheduler validate` from your terminal.
- [ ] **claude-flow memory** (optional) -- if installed, run `claude-flow memory search -q "test"` to verify the memory layer responds.

## Key commands

| Command | What it does |
|---------|-------------|
| `/brana:build` | Build anything -- 7 strategies for different work types |
| `/brana:close` | End session -- extract learnings, write handoff |
| `/brana:backlog` | Manage tasks -- plan, track, navigate |
| `/brana:log` | Capture events -- calls, meetings, ideas, links |
| `/brana:research` | Research a topic -- recursive discovery |
| `/brana:memory` | Query the knowledge system |
| `/brana:onboard` | Diagnose a new project |
| `/brana:align` | Set up project structure |
| `/brana:review` | Business health -- weekly, monthly, or ad-hoc |
| `/brana:challenge` | Adversarial review of a plan or decision |

## Working across projects

Brana works from any directory. Open Claude Code in your project folder and all brana skills are available:

```bash
cd ~/projects/my-app
claude                          # brana plugin loads automatically
```

Each project can have its own `.claude/CLAUDE.md` with project-specific conventions. Brana's global rules combine with project-local rules.

## Next steps

- [Configuration](configuration.md) -- display themes, task portfolio, scheduler setup
- [Scheduler](scheduler.md) -- recurring jobs via systemd timers
- [Troubleshooting](troubleshooting.md) -- common issues and fixes
- [Upgrading](upgrading.md) -- how to update brana
- [Concepts](concepts.md) -- glossary of terms
- [Commands](commands/) -- full command reference
