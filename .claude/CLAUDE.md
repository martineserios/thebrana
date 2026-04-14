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

- **Dimension** → `brana-knowledge/dimensions/` (knowledge/research)
- **Reflection** → `docs/reflections/` (cross-cutting synthesis)
- **Roadmap** → `docs/` (implementation plans)

### Reflection DAG

R1(08 Triage) → R2(14 Architecture) → R3(31 Assurance) / R4(32 Lifecycle) → R5(29 Venture) / R6(33 Agent Loop)

## Inbox

`inbox/` is a processing drop folder (gitignored). Drop files here for Claude to process: audio for transcription, docs for analysis, PDFs for review, data for import. Organized by topic subfolder. Files are transient — process and delete or move to permanent storage. Every client/project should have its own `inbox/`.

## System Architecture

### Skill Tiering (ADR-034)

All skills use the universal stub pattern to reduce startup context (~34K to ~8K tokens). Current count in [Skill Reference](docs/reference/skills.md).

- **Stub SKILL.md:** Frontmatter + Read instruction only. Procedure body in `system/procedures/{name}.md`, loaded on invoke via Read tool.

All skills remain available as slash commands. Semantic routing via ruflo is unchanged (indexes frontmatter).

### MCP Server Pinning (ADR-033)

`.mcp.json` uses `${CLAUDE_PLUGIN_ROOT}/scripts/*-mcp.sh` wrapper scripts instead of `npx`/`uvx`. Each wrapper resolves the server binary dynamically (via nvm or PATH). This eliminates 15-180s registry resolution per server at session start.

## Commands

### The 6 Jobs

| Job | Question | Entry Point |
|-----|----------|-------------|
| DECIDE | "What should I work on?" | `/brana:backlog`, `/brana:brainstorm` |
| UNDERSTAND | "What do I need to know?" | `/brana:research`, `/brana:onboard` |
| BUILD | "Make the thing" | `/brana:build` |
| SHIP | "Get it to users" | `/brana:ship`, `./bootstrap.sh`, `./validate.sh` |
| MAINTAIN | "Keep it healthy" | `/brana:reconcile` |
| GROW | "Build the business" | `/brana:review` |

### DECIDE

| Command | Purpose |
|---------|---------|
| `/brana:do` | Route freeform text to the best skill — semantic matching via ruflo |
| `/brana:backlog` | Manage tasks — plan, track, navigate work |
| `/brana:brainstorm` | Interactive idea maturation — explore, research, shape into plans |
| `/brana:sitrep` | Situational awareness — where am I, what's next, context recovery |
| `/brana:challenge` | Adversarial review of a plan or decision |

### UNDERSTAND

| Command | Purpose |
|---------|---------|
| `/brana:research` | Research a topic, doc, or creator — recursive discovery. `--refresh` for batch dimension updates |
| `/brana:onboard` | Scan and diagnose a project (code, venture, or hybrid) |
| `/brana:memory` | Knowledge ops — recall, cross-pollinate, review health, audit |
| `/brana:notebooklm-source` | Prepare and format sources for NotebookLM |

### BUILD

| Command | Purpose |
|---------|---------|
| `/brana:build` | Build anything — auto-detects strategy (feature, bug fix, refactor, spike, migration, investigation, greenfield) |
| `/brana:reconcile` | Detect drift across 4 domains (consistency, security, propagation, knowledge), plan fixes, apply after approval |
| `/brana:docs` | Generate and update tech docs, user guides, philosophy overview |
| `/brana:align` | Implement project structure based on /brana:onboard findings |

### SHIP

| Command | Purpose |
|---------|---------|
| `/brana:ship` | Ship a build — pre-flight, deploy, document, verify, monitor |
| `./bootstrap.sh` | Deploy identity layer (CLAUDE.md, rules, scripts) to `~/.claude/` |
| `./bootstrap.sh --check` | Show what bootstrap would change without applying |
| `./validate.sh` | Pre-deploy checks (frontmatter, budget, secrets) |
| `./export-knowledge.sh` | Export native memory + ruflo memory |

### MAINTAIN

| Command | Purpose |
|---------|---------|
| `/brana:reconcile` | 4-domain drift detection (consistency, security, propagation, knowledge) |
| `/brana:maintain-specs` | Full spec correction cycle: errata → reflections → synthesis → hygiene |
| `/brana:apply-errata` | Apply pending errata from doc 24 through layer hierarchy |
| `/brana:re-evaluate-reflections` | Cross-check reflections against dimensions for gaps |
| `/brana:repo-cleanup` | Commit accumulated spec doc changes in logical batches |

> Spec maintenance commands live in `system/commands/`, not skills — invoked by agents or manually.
> **Enforcement hooks:** `tdd-gate.sh` (tests), `doc-gate.sh` (docs), `main-guard.sh` (branch discipline), `branch-verify.sh` (staging on main) — all fire on every branch.

### Capture & Tools

| Command | Purpose |
|---------|---------|
| `/brana:close` | End session — extract learnings, write handoff, store patterns |
| `/brana:retrospective` | Store a learning or pattern in the knowledge system |
| `/brana:log` | Capture events (links, calls, meetings, ideas) into searchable log |
| `/brana:gsheets` | Google Sheets via MCP — read, write, create, list, share |
| `/brana:export-pdf` | Convert markdown to PDF via mdpdf |
| `/brana:scheduler` | Manage scheduled jobs |
| `/brana:plugin` | Manage Claude Code plugins — install, update, remove |
| `/brana:acquire-skills` | Find and install skills for project tech gaps |
| `init-project` | Initialize a new project with CLAUDE.md template (shell script) |

<!-- CLI reference: brana --help | Full subcommand docs: docs/reference/ -->

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
| MCP server pinning (wrapper scripts, no npx/uvx) | [ADR-033-pin-mcp-servers.md](../docs/architecture/decisions/ADR-033-pin-mcp-servers.md) |
| Skill tiering (core full + extended stubs) | [ADR-034-skill-tiering.md](../docs/architecture/decisions/ADR-034-skill-tiering.md) |

## Ecosystem

| Repo | Role | You go here to... |
|------|------|-------------------|
| **thebrana** (here) | Design + Build | Research, plan, implement, deploy |
| **brana-knowledge** | Knowledge base | General knowledge, research, backups |
| **clients/** | Paid work | External stakeholder projects (`~/enter_thebrana/clients/`) |
| **ventures/** | Your IP | Side projects, learning, monetizing (`~/enter_thebrana/ventures/`) |
| **personal/** | Personal OS | Journal, goals, identity (`~/enter_thebrana/personal/`) |

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
- Use namespace `knowledge` for dimension doc content — any `memory_search` query automatically searches knowledge base content alongside patterns.

<!-- Knowledge base pipeline details: docs/architecture/ -->

## Field Notes

<!-- TODO: route to MEMORY.md → tests/bootstrap/ is home for root-level installer tests (not in MEMORY.md yet) -->
<!-- TODO: strengthen MEMORY.md worktree entry → stale worktrees post-merge have untracked files from prior work -->
