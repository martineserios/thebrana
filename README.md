# brana

> The mastermind brain system — a set of Claude Code configuration files that deploy to `~/.claude/` to create a cross-project intelligence layer.

## Quick Start

```bash
./validate.sh && ./deploy.sh
```

## What This Is

Brana is a mastermind system that gives Claude Code persistent, cross-project intelligence. It deploys identity, rules, skills, and agents to `~/.claude/`, creating a brain that learns from every project and cross-pollinates patterns across your entire development workflow.

## File Structure

```
thebrana/
├── system/                    ← Deploys to ~/.claude/
│   ├── CLAUDE.md              ← Mastermind identity (loaded every session)
│   ├── rules/                 ← Quality, git, PM rules (loaded unconditionally)
│   ├── skills/                ← 6 invokable skills (/pattern-recall, etc.)
│   └── agents/                ← Scout (Haiku research agent)
├── deploy.sh                  ← Validate + copy to ~/.claude/
├── validate.sh                ← Pre-deploy checks
├── export-knowledge.sh        ← Export memory + ReasoningBank
└── README.md
```

## Skills

| Skill | Description |
|-------|-------------|
| `/pattern-recall` | Query learned patterns relevant to current context |
| `/retrospective` | Store a learning or pattern |
| `/project-onboard` | Bootstrap a new project with relevant knowledge |
| `/cross-pollinate` | Pull patterns from other projects |
| `/project-retire` | Archive a project's patterns |
| `/challenge` | Sonnet adversarial review of plans/decisions |

## Rules

All rules load unconditionally in every session:
- **universal-quality** — test before commit, no secrets, error handling, type safety
- **git-discipline** — conventional commits, atomic changes, branch naming
- **pm-awareness** — check issues, link commits, track progress

## Adding a New Skill

1. Create `system/skills/{name}/SKILL.md`
2. Add YAML frontmatter with `name`, `description`, and `allowed-tools`
3. Write instructions in the body
4. Run `./validate.sh` to verify
5. Run `./deploy.sh` to deploy

## Adding a New Rule

1. Create `system/rules/{name}.md`
2. Omit `paths:` frontmatter for unconditional loading, or add `paths:` to scope it
3. Run `./validate.sh` to verify context budget
4. Run `./deploy.sh` to deploy

## Export Knowledge

```bash
./export-knowledge.sh [output-dir]
```

Exports native auto memory and ReasoningBank patterns to a portable format.

## Phase Status

**Phase 1** (current): Skills, rules, agents, and deploy scripts working. Hooks disabled.

**Phase 2** (next): Learning loop — SessionStart/Stop/PostToolUse hooks, quarantine, two-layer memory.

See [brana-v2-specs](../README.md) for full architecture documentation.
