# thebrana — Operator's Station

> Part of **enter_thebrana** — two repos, one system. `thebrana` builds what `enter` designs. Neither is complete without the other.

The brain that deploys to `~/.claude/`. Edit here, deploy there.

## Current State

| Component | Location |
|-----------|----------|
| Skills | `system/skills/` |
| Rules | `system/rules/` |
| Hooks | `system/hooks/` |
| Agents | `system/agents/` |
| Version | v0.5.0 (Phase 5: Alignment) |

## Deploy Flow

```
system/          deploy.sh         ~/.claude/
├── skills/ ──────────────────────→ skills/
├── rules/  ──────────────────────→ rules/
├── hooks/  ──────────────────────→ hooks (settings.json)
├── agents/ ──────────────────────→ agents/
└── CLAUDE.md ────────────────────→ CLAUDE.md
```

## Workflow

1. Edit files in `system/`
2. Run `./validate.sh` — check frontmatter, context budget (15KB), secrets, structure
3. Run `./deploy.sh` — validate + copy to `~/.claude/`
4. Start a new Claude Code session to test changes

## Commands

| Command | Purpose |
|---------|---------|
| `./deploy.sh` | Validate + deploy system files to `~/.claude/` |
| `./validate.sh` | Pre-deploy checks (frontmatter, budget, secrets) |
| `./export-knowledge.sh` | Export native memory + ReasoningBank |

## Rules

- **Never edit `~/.claude/` directly** — always edit `system/` and deploy
- **Validate before deploy** — `./validate.sh` catches errors before they reach production
- **Context budget: 15KB** — every byte of always-loaded content costs attention
- **Test after deploy** — start a new session to verify changes work

## Specs Reference

When you need the "why" behind a system component, find it in the specs:

| Topic | Doc |
|-------|-----|
| Architecture (layers, hooks, skills) | [14-mastermind-architecture.md](../../enter/14-mastermind-architecture.md) |
| Lifecycle (DDD → SDD → TDD workflow) | [32-lifecycle.md](../../enter/32-lifecycle.md) |
| Testing and assurance | [31-assurance.md](../../enter/31-assurance.md) |
| Quality tooling (validation, linting) | [22-quality-tooling-analysis.md](../../enter/22-quality-tooling-analysis.md) |
| Roadmap and next steps | [18-menu-driven-roadmap.md](../../enter/18-menu-driven-roadmap.md) |
| Errata and corrections | [24-roadmap-corrections.md](../../enter/24-roadmap-corrections.md) |
| Alignment methodology | [27-project-alignment-methodology.md](../../enter/27-project-alignment-methodology.md) |

## Portability

Two commands rebuild the brain on any machine:

```bash
./deploy.sh          # Deploy brain to ~/.claude/
./restore.sh         # Restore knowledge from brana-knowledge backup
```
