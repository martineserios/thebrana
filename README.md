# brana

![Version](https://img.shields.io/badge/version-v1.0.0-blue)
![License](https://img.shields.io/badge/license-MIT-green)
![Claude Code](https://img.shields.io/badge/Claude%20Code-v1.0.33+-purple)

Every Claude Code session, your model re-infers what it already knew: your stack, your naming conventions, your past decisions. This invisible per-session cost is the **knowledge retrieval tax** — and it compounds.

Brana eliminates it. A plugin for Claude Code that pre-loads structured context before reasoning begins, enforces engineering discipline automatically, and gets more useful the longer you use it.

## What you get

- **25+ skills** -- slash commands for building, researching, reviewing, managing tasks, and more
- **12 rules** -- git discipline, test-first, context budget, research methodology -- always active
- **10 hooks** -- automatic behaviors: pattern recall, spec-before-code gate, learning capture, cascade detection
- **11 agents** -- specialized sub-agents that auto-fire for code review, adversarial challenge, research, and more

### The compounding loop

Each session, brana captures what went wrong and what worked. Next session, those patterns surface automatically before you start. Corrections don't repeat. Patterns proven across 3+ sessions get promoted and recalled with higher confidence than new ones.

Without brana: Claude resets every session.
With brana: Claude remembers your corrections, follows your conventions, and gets harder to fool over time.

## Quick start

### Install

```bash
curl -fsSL https://raw.githubusercontent.com/martineserios/thebrana/main/install.sh | bash
```

Or manually:

```bash
git clone https://github.com/martineserios/thebrana.git ~/brana
cd ~/brana && ./bootstrap.sh
```

Restart Claude Code. The plugin loads automatically.

**Custom install directory:** `BRANA_DIR=~/my-dir bash install.sh`

### Start working

```
/brana:build "add user authentication"   -- auto-detects strategy (feature, bug fix, refactor...)
/brana:backlog                            -- manage tasks
/brana:close                             -- end session, capture learnings
```

## Feature highlights

### Build anything with one command

`/brana:build` detects what you're doing -- feature, bug fix, refactor, spike, migration, investigation, or greenfield -- and runs the right workflow. TDD enforced, docs included.

### Learns from every session

Hooks capture corrections, test writes, and failure cascades. `/brana:close` extracts patterns. Next session, they're recalled automatically. Confidence-weighted: new learnings start quarantined, proven ones surface first.

### Adversarial review built in

`/brana:challenge` runs an Opus-powered adversarial review with four flavors: pre-mortem, simplicity challenge, assumption buster, adversarial user. Auto-triggers after plan mode.

### Enforcement, not reminders

Rules are active constraints, not suggestions. The PreToolUse hook blocks implementation writes on `feat/*` branches until a spec or test exists. The worktree gate prevents accidental commits to `main`. The doc gate blocks commits that change behavior without updating docs. You can't skip the fundamentals because they aren't optional.

## Skills

Organized by job:

| Job | Skills |
|-----|--------|
| **DECIDE** | `backlog`, `brainstorm`, `sitrep`, `challenge` |
| **UNDERSTAND** | `research`, `onboard`, `memory`, `notebooklm-source` |
| **BUILD** | `build`, `align`, `docs`, `reconcile` |
| **SHIP** | `ship`, `review`, `client-retire` |
| **CAPTURE** | `close`, `retrospective`, `log`, `gsheets`, `export-pdf` |
| **Tools** | `acquire-skills`, `plugin`, `scheduler`, `rust-skills`, `mcp-builder` |

All skills are invoked as `/brana:<name>`. See [Skill Reference](docs/reference/skills.md) for full details.

## Agents

| Agent | Model | Auto-fires when |
|-------|-------|-----------------|
| memory-curator | Haiku | Starting work, familiar problem, stuck |
| client-scanner | Haiku | New client, project health check |
| venture-scanner | Haiku | New business project |
| challenger | Sonnet | Plan or architecture decision forming |
| debrief-analyst | Opus | End of implementation session |
| scout | Haiku | Research tasks (spawned by skills) |
| archiver | Haiku | Retiring a client |
| daily-ops | Haiku | Session start on venture project |
| metrics-collector | Haiku | Business reviews |
| pipeline-tracker | Haiku | Pipeline tracking, deal events |
| pr-reviewer | Sonnet | PR creation (auto-triggered) |

All agents are read-only. See [Agent Reference](docs/reference/agents.md) for full details.

## Documentation

| Section | Contents |
|---------|----------|
| **[Reference](docs/reference/)** | Complete specs: [skills](docs/reference/skills.md), [hooks](docs/reference/hooks.md), [agents](docs/reference/agents.md), [rules](docs/reference/rules.md), [commands](docs/reference/commands.md), [scripts](docs/reference/scripts.md), [configuration](docs/reference/configuration.md) |
| **[Guide](docs/guide/)** | [Getting started](docs/guide/getting-started.md), [configuration](docs/guide/configuration.md), [workflows](docs/guide/workflows/) (build, research, session, capture, learn, venture), [troubleshooting](docs/guide/troubleshooting.md) |
| **[Architecture](docs/architecture/)** | [Overview](docs/architecture/overview.md), [plugin structure](docs/architecture/plugin-structure.md), [extending](docs/architecture/extending.md) (skills, hooks, agents), [ADRs](docs/architecture/decisions/) |
| **[Doc Index](docs/README.md)** | Full index of all documentation |

## How it works

Brana is structured as four layers:

| Layer | What it is | Examples |
|-------|-----------|---------|
| **Commands** | Skills invoked as `/brana:*` slash commands | `build`, `backlog`, `research`, `close` |
| **Specialists** | Agents that auto-fire for specific work types | challenger, pr-reviewer, debrief-analyst |
| **Fabric** | Hooks enforcing rules automatically | spec gate, worktree guard, learning capture |
| **Memory** | Cross-session pattern storage and recall | corrections, proven patterns, session state |

Physically, these live in two places:

```
Plugin (loaded by Claude Code)              Identity layer (~/.claude/)
+-- skills/    -> /brana:* commands         +-- CLAUDE.md  -> who Claude is
+-- hooks/     -> automatic behaviors       +-- rules/     -> behavioral rules
+-- agents/    -> specialized sub-agents    +-- scripts/   -> helper scripts
+-- commands/  -> agent commands            +-- scheduler/ -> scheduled jobs
```

The **plugin** is the toolkit — what Claude can do. Loads via Claude Code's plugin system.

The **identity layer** is the foundation — how Claude thinks. Deploys once via `bootstrap.sh`.

## Dev mode

For contributors:

```bash
git clone https://github.com/martineserios/thebrana.git
cd thebrana
claude --plugin-dir ./system    # edits take effect on next session
```

## Requirements

- [Claude Code](https://claude.com/claude-code) v1.0.33+
- Git

**Optional:** Node.js v20+ (MCP integrations), [claude-flow](https://www.npmjs.com/package/claude-flow) (cross-client memory search)

## Version

v1.0.0 | [Changelog](#changelog)

### Changelog

| Version | Milestone |
|---------|-----------|
| v1.0.0 | Marketplace publication, full documentation |
| v0.7.0 | Plugin packaging, namespace migration, bootstrap.sh |
| v0.6.0 | Unified repo (enter + thebrana merged) |
| v0.5.0 | Project alignment, venture management |
| v0.4.0 | Validation, context budget, self-documentation |
| v0.3.0 | Learning loop, knowledge health |
| v0.2.0 | Hook system (session start/end, spec-first gate) |
| v0.1.0 | Skills, rules, deploy scripts |

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for setup, branch naming, and PR process. Issues tagged [`good first issue`](https://github.com/martineserios/thebrana/labels/good%20first%20issue) are a great starting point.

### Contributors

<!-- Add yourself here when your first PR is merged -->
- [Martin Eserios](https://github.com/martineserios) -- creator, maintainer

## Security

See [SECURITY.md](SECURITY.md).

## License

MIT
