# thebrana — Design and Build the Brain

> The unified brana system repo. Design specs live in `docs/`, implementation lives in `system/`. One repo, one feedback loop. (Merged from enter + thebrana per ADR-006.)

## Two Workspaces, One Repo

| Workspace | Location | Purpose |
|-----------|----------|---------|
| **Architect** | `docs/` | Research, design, plan — dimension/reflection/roadmap docs |
| **Operator** | `system/` | Build, deploy, maintain — skills, hooks, rules, agents |

Branch conventions preserve the separation:
- `docs/*` branches: spec work (no `system/` edits)
- `feat/*` branches: implementation (should also touch `docs/` when behavior changes)

## Document Architecture

Docs are split by nature across two repos:

```
thebrana/docs/                    ← operational docs (this repo)
├── reflections/                  ← 08, 14, 29, 31, 32 — cross-cutting synthesis
├── 00, 15, 17-19, 24, 25, 30    ← roadmap + operational docs
├── 39-architecture-redesign      ← active migration plan
├── decisions/                    ← ADRs
└── features/                     ← feature briefs

brana-knowledge/dimensions/       ← knowledge docs (separate repo)
├── 01-07, 09-13, 16, 20-23      ← research in depth
├── 26-28, 33-38                  ← research in depth
├── client-retention, meta-whatsapp, smb-marketing ← topic docs
└── research-sources.yaml         ← tracked external sources
```

- **Dimension** → `brana-knowledge/dimensions/` (knowledge/research)
- **Reflection** → `docs/reflections/` (cross-cutting synthesis)
- **Roadmap** → `docs/` (implementation plans)

### Reflection DAG

R1(08 Triage) → R2(14 Architecture) → R3(31 Assurance) / R4(32 Lifecycle) → R5(29 Venture)

## System Architecture

```
system/          deploy.sh         ~/.claude/
├── skills/   ────────────────────→ skills/
├── scripts/  ────────────────────→ scripts/
├── commands/ ────────────────────→ commands/
├── rules/    ────────────────────→ rules/
├── hooks/    ────────────────────→ hooks (settings.json)
├── agents/   ────────────────────→ agents/
└── CLAUDE.md ────────────────────→ CLAUDE.md
```

Version: v0.6.0 (Phase 1: Unified Repo)

## Commands

### Operator Commands

| Command | Purpose |
|---------|---------|
| `./deploy.sh` | Validate + deploy system files to `~/.claude/` |
| `./validate.sh` | Pre-deploy checks (frontmatter, budget, secrets) |
| `./export-knowledge.sh` | Export native memory + ReasoningBank |

### Architect Commands

| Command | Purpose |
|---------|---------|
| `/build-phase` | Plan and implement next roadmap phase |
| `/maintain-specs` | Cascade spec changes: dimension → reflection → roadmap |
| `/back-propagate` | Propagate implementation changes back to specs |
| `/refresh-knowledge` | Research external updates to dimension docs |
| `/challenge` | Adversarial review of a plan or decision |
| `/decide` | Create an Architecture Decision Record |
| `/reconcile` | Detect spec-vs-implementation drift, plan fixes, apply after approval |
| `/debrief` | Extract errata and learnings from current session |
| `/research` | Research a topic, doc, or creator — recursive discovery |
| `/knowledge` | Browse, annotate, review, and reindex brana-knowledge |

## Specs Reference

| Topic | Doc |
|-------|-----|
| Architecture (layers, hooks, skills) | [14-mastermind-architecture.md](../docs/reflections/14-mastermind-architecture.md) |
| Lifecycle (DDD → SDD → TDD workflow) | [32-lifecycle.md](../docs/reflections/32-lifecycle.md) |
| Testing and assurance | [31-assurance.md](../docs/reflections/31-assurance.md) |
| Quality tooling (validation, linting) | [22-testing.md](~/enter_thebrana/brana-knowledge/dimensions/22-testing.md) |
| Roadmap and next steps | [18-lean-roadmap.md](../docs/18-lean-roadmap.md) |
| Errata and corrections | [24-roadmap-corrections.md](../docs/24-roadmap-corrections.md) |
| Alignment methodology | [27-project-alignment-methodology.md](~/enter_thebrana/brana-knowledge/dimensions/27-project-alignment-methodology.md) |
| Architecture redesign | [39-architecture-redesign.md](../docs/39-architecture-redesign.md) |

## Ecosystem

| Repo | Role | You go here to... |
|------|------|-------------------|
| **thebrana** (here) | Design + Build | Research, plan, implement, deploy |
| **brana-knowledge** | Knowledge base | General knowledge, research, backups |

## Rules

- **Never edit `~/.claude/` directly** — always edit `system/` and deploy
- Keep documents concise and opinionated
- Changes propagate: dimension → reflection → roadmap (`/maintain-specs`)
- Spec changes push to implementation (`/reconcile`)
- Implementation changes push back to specs (`/back-propagate`)
- When adding new docs, update `docs/README.md`

## Memory and Knowledge Retrieval (claude-flow)

When the claude-flow MCP server is available, use it for persistent memory:

- **Store** architectural decisions, research findings, and conclusions (`memory_store`)
- **Search** before starting work on a topic (`memory_search`)
- Use namespace `specs` for specification-related patterns
- Use namespace `decisions` for architectural decisions
- Use namespace `knowledge` for dimension doc content — **315+ sections from 33 dimension docs are indexed with semantic embeddings**. Any `memory_search` query automatically searches knowledge base content alongside patterns.

### Knowledge Base Pipeline

brana-knowledge dimension docs are indexed into claude-flow memory via `system/scripts/index-knowledge.sh`. Each `##` section becomes a searchable entry with 384-dim ONNX embeddings (all-MiniLM-L6-v2). Reindexing happens:
- **On commit** — post-commit hook in brana-knowledge reindexes changed files
- **Weekly** — scheduled full reindex (Sunday 3am) as safety net
- **Manual** — `index-knowledge.sh [file]` or `index-knowledge.sh` (all)
