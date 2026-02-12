# brana

> Part of [**enter_thebrana**](../) — two repos, one system. `thebrana` builds what [`enter`](../enter/) designs.
>
> The mastermind brain system — Claude Code configuration files that deploy to `~/.claude/`, creating a cross-project intelligence layer.

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
│  ~/.swarm/memory.db (ReasoningBank)     │
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
│   ├── skills/ (17)                ← Invokable skills
│   ├── rules/ (8)                  ← Always-loaded behavioral rules
│   ├── hooks/ (5)                  ← Event-driven shell scripts
│   └── agents/ (1)                 ← Specialized sub-agents
├── deploy.sh                       ← Validate + copy to ~/.claude/
├── validate.sh                     ← Pre-deploy checks
├── export-knowledge.sh             ← Export memory + ReasoningBank
└── README.md
```

## Skills (17)

### Code-Focused (12)

| Skill | Description |
|-------|-------------|
| `/build-phase` | Plan and implement the next roadmap phase |
| `/challenge` | Adversarial review of plans and decisions |
| `/cross-pollinate` | Pull patterns from other projects |
| `/debrief` | Extract errata and learnings from current session |
| `/decide` | Create Architecture Decision Records |
| `/knowledge-review` | Monthly review of ReasoningBank health |
| `/pattern-recall` | Query learned patterns relevant to current context |
| `/project-align` | Assess and align a project with brana practices |
| `/project-onboard` | Bootstrap a new project with relevant knowledge |
| `/project-retire` | Archive a project's patterns |
| `/refresh-knowledge` | Research external updates to dimension docs |
| `/retrospective` | Store learnings and patterns in the knowledge system |

### Venture/Business (5)

| Skill | Description |
|-------|-------------|
| `/growth-check` | Business health audit (AARRR funnel, metrics) |
| `/sop` | Create Standard Operating Procedures |
| `/venture-align` | Set up business management structure |
| `/venture-onboard` | Discover and diagnose a business project |
| `/venture-phase` | Plan and execute a business milestone |

## Rules (8)

| Rule | Purpose |
|------|---------|
| `git-discipline` | Branch naming, conventional commits, `--no-ff` merges |
| `memory-framework` | CLAUDE.md vs MEMORY.md separation |
| `pm-awareness` | Check issues, link commits, track progress |
| `research-discipline` | Read project docs before web research |
| `sdd-tdd` | Spec-driven and test-driven development |
| `skill-suggestions` | Proactive skill recommendations |
| `universal-quality` | Test before commit, no secrets, type safety |
| `work-preferences` | Parallelism, simplicity, automation |

## Hooks (5)

| Hook | Event | Purpose |
|------|-------|---------|
| `session-start.sh` | SessionStart | Recall relevant patterns for current project |
| `session-end.sh` | SessionEnd | Extract and store session learnings |
| `pre-tool-use.sh` | PreToolUse | SDD enforcement — block code before spec/test |
| `post-tool-use.sh` | PostToolUse | Learn from significant tool uses |
| `post-tool-use-failure.sh` | PostToolUseFailure | Learn from tool failures (anti-patterns) |

## Agents (1)

| Agent | Model | Purpose |
|-------|-------|---------|
| `scout` | Haiku | Fast research — codebase exploration, information gathering |

## Ecosystem

| Repo | Role | Contains |
|------|------|----------|
| **enter** | Architect | 33 spec docs (dimension → reflection → roadmap) |
| **thebrana** (here) | Operator | System files that deploy to `~/.claude/` |
| **brana-knowledge** | Vault | Knowledge exports and backups |

## Adding Components

### New Skill

1. Create `system/skills/{name}/SKILL.md` with YAML frontmatter (`name`, `description`, `allowed-tools`)
2. Write instructions in the body
3. `./validate.sh && ./deploy.sh`

### New Rule

1. Create `system/rules/{name}.md`
2. Omit `paths:` for unconditional loading, or add `paths:` to scope it
3. `./validate.sh && ./deploy.sh`

### New Hook

1. Create `system/hooks/{event}.sh`
2. Register in `system/settings.json` under the appropriate event
3. `./validate.sh && ./deploy.sh`

## Version History

| Version | Phase | Milestone |
|---------|-------|-----------|
| v0.1.0 | 1 — Foundation | Skills, rules, deploy scripts |
| v0.2.0 | 2 — Hooks | Learning loop (SessionStart/End, PreToolUse, PostToolUse) |
| v0.3.0 | 3 — Learning | Quarantine, two-layer memory, knowledge health |
| v0.4.0 | 4 — Quality | Validation, context budget, self-documentation |
| v0.5.0 | 5 — Alignment | `/project-align`, venture management skills |

See [enter/](../enter/) for full architecture documentation.
