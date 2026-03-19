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
├── research/                     ← /brana:research output (comparisons, deep dives)
├── guide/                        ← user-facing workflow guides + command reference
├── architecture/                 ← contributor docs (overview, skills, hooks, agents, extending)
│   ├── decisions/                ← ADRs
│   └── features/                 ← feature briefs

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

Version: v1.0.0

## Installation

```bash
# Dev mode (recommended for contributors)
claude --plugin-dir ./system

# Install from GitHub
/plugin marketplace add martineserios/thebrana
/plugin install brana

# Identity layer (CLAUDE.md, rules, scripts — run once)
./bootstrap.sh
```

## Commands

### Operator Commands

| Command | Purpose |
|---------|---------|
| `./bootstrap.sh` | Deploy identity layer (CLAUDE.md, rules, scripts) to `~/.claude/` |
| `./bootstrap.sh --check` | Show what bootstrap would change without applying |
| `./validate.sh` | Pre-deploy checks (frontmatter, budget, secrets) |
| `./export-knowledge.sh` | Export native memory + ruflo memory |

### Build & Development (Skills)

| Command | Purpose |
|---------|---------|
| `/brana:build` | Build anything — auto-detects strategy (feature, bug fix, refactor, spike, migration, investigation, greenfield) |
| `/brana:close` | End session — extract learnings, write handoff, store patterns |
| `/brana:backlog` | Manage tasks — plan, track, navigate work |
| `/brana:challenge` | Adversarial review of a plan or decision |
| `/brana:reconcile` | Detect spec-vs-implementation drift, plan fixes, apply after approval |
| `/brana:research` | Research a topic, doc, or creator — recursive discovery. `--refresh` for batch dimension updates |
| `/brana:onboard` | Scan and diagnose a project (code, venture, or hybrid) |
| `/brana:align` | Implement project structure based on /brana:onboard findings |
| `/brana:review` | Business health — weekly (default), monthly, or ad-hoc check |

### CLI Tools

| Command | Purpose |
|---------|---------|
| `brana transcribe <file> [--model base\|tiny\|small]` | Transcribe audio (wav, mp3, ogg, m4a) to text via whisper.cpp. Auto-detects language. |
| `brana files list\|status\|add\|pull\|push` | Track large files via manifest (.brana-files.json). SHA-256 verified, R2/HTTP remotes. |

### Agent Commands

| Command | Purpose |
|---------|---------|
| `/brana:maintain-specs` | Cascade spec changes: dimension → reflection → roadmap (lives in `system/commands/`, not a skill) |

## Specs Reference

| Topic | Doc |
|-------|-----|
| Architecture (layers, hooks, skills) | [ARCHITECTURE.md](../docs/reflections/ARCHITECTURE.md) |
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
| **clients/** | Portfolio | All clients live in `~/enter_thebrana/clients/` |

## Rules

- **Never edit `~/.claude/` directly** — edit `system/` (plugin loads it) or re-run `./bootstrap.sh` (identity layer)
- Keep documents concise and opinionated
- Changes propagate: dimension → reflection → roadmap (`/brana:maintain-specs`)
- Spec changes push to implementation (`/brana:reconcile`)
- Implementation changes update docs in the same commit (no separate back-propagation step)
- When adding new docs, update `docs/README.md`

## Memory and Knowledge Retrieval (ruflo)

When the ruflo MCP server is available, use it for persistent memory:

- **Store** architectural decisions, research findings, and conclusions (`memory_store`)
- **Search** before starting work on a topic (`memory_search`)
- Use namespace `specs` for specification-related patterns
- Use namespace `decisions` for architectural decisions
- Use namespace `knowledge` for dimension doc content — **315+ sections from 33 dimension docs are indexed with semantic embeddings**. Any `memory_search` query automatically searches knowledge base content alongside patterns.

### Knowledge Base Pipeline

brana-knowledge dimension docs are indexed into ruflo memory via `system/scripts/index-knowledge.sh`. Each `##` section becomes a searchable entry with 384-dim ONNX embeddings (all-MiniLM-L6-v2). Reindexing happens:
- **On commit** — post-commit hook in brana-knowledge reindexes changed files
- **Weekly** — scheduled full reindex (Sunday 3am) as safety net
- **Manual** — `index-knowledge.sh [file]` or `index-knowledge.sh` (all)
