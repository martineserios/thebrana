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

## Inbox

`inbox/` is a processing drop folder (gitignored). Drop files here for Claude to process: audio for transcription, docs for analysis, PDFs for review, data for import. Organized by topic subfolder. Files are transient — process and delete or move to permanent storage. Every client/project should have its own `inbox/`.

## System Architecture

```
system/                                  Plugin (loaded by Claude Code)
├── .claude-plugin/plugin.json           ← plugin manifest
├── skills/                              ← /brana:* slash commands (core: full, extended: stubs)
├── procedures/                          ← extended skill procedure bodies (ADR-034)
├── commands/                            ← agent commands
├── hooks/hooks.json + *.sh              ← event hooks
├── agents/                              ← specialized agents
├── scripts/*-mcp.sh                     ← MCP server wrappers (ADR-033)
├── CLAUDE.md                            ← mastermind identity
└── cli/rust/                            ← Cargo workspace (ADR-026)
    └── crates/
        ├── brana-core/                  ← shared business logic library
        │   ├── tasks.rs                 ← task lifecycle, filtering, scoring
        │   ├── files.rs                 ← content-addressed file tracking
        │   ├── scheduler.rs             ← job health, collisions, drift
        │   ├── sync.rs                  ← task↔GitHub sync planning
        │   └── util.rs                  ← path discovery, config loading
        ├── brana-cli/                   ← terminal interface (clap + themes)
        └── brana-mcp/                   ← MCP server (pmcp + stdio)

bootstrap.sh                             Identity layer → ~/.claude/
├── CLAUDE.md                            ← global identity
├── rules/                               ← behavioral rules
├── scripts/                             ← helper scripts
├── statusline.sh                        ← status bar
└── scheduler/                           ← scheduled jobs
```

Version: v1.0.0

### Skill Tiering (ADR-034)

All 25 skills use the universal stub pattern to reduce startup context (~34K to ~8K tokens):

- **Stub SKILL.md:** Frontmatter + Read instruction only. Procedure body in `system/procedures/{name}.md`, loaded on invoke via Read tool.

All skills remain available as slash commands. Semantic routing via ruflo is unchanged (indexes frontmatter).

### MCP Server Pinning (ADR-033)

`.mcp.json` uses `${CLAUDE_PLUGIN_ROOT}/scripts/*-mcp.sh` wrapper scripts instead of `npx`/`uvx`. Each wrapper resolves the server binary dynamically (via nvm or PATH). This eliminates 15-180s registry resolution per server at session start. Wrappers: `ruflo-mcp.sh`. (`brana-mcp` uses a direct binary path, no wrapper.)

## Installation

```bash
# One-command install (recommended)
curl -fsSL https://raw.githubusercontent.com/martineserios/thebrana/main/install.sh | bash
# or: git clone ... && ./bootstrap.sh
# bootstrap.sh registers plugin directly via installed_plugins.json — no /plugin commands needed

# Dev mode (contributors)
claude --plugin-dir ./system
```

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

### GROW

| Command | Purpose |
|---------|---------|
| `/brana:review` | Business health — weekly (default), monthly, or ad-hoc check |
| `/brana:client-retire` | Archive a client's patterns and knowledge when retiring |

> **Moved to client/venture projects:** pipeline, financial-model, venture-phase, proposal → brana-knowledge. meta-template, meta-verification, respondio-prompts → somos_mirada (+ copies to anita, brapsoclaw). harvest → ventures/linkedin (2026-04-06).

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

### CLI Tools

| Command | Purpose |
|---------|---------|
| `brana transcribe <file> [--model base\|tiny\|small]` | Transcribe audio (wav, mp3, ogg, m4a) to text via whisper.cpp. Auto-detects language. |
| `brana files list\|status\|add\|pull\|push` | Track large files via manifest (.brana-files.json). SHA-256 verified, R2/HTTP remotes. |
| `brana feed add\|list\|poll\|remove\|status` | RSS/Atom feed polling. Covers Substack, Medium, blogs, YouTube, GitHub releases. HTTP conditional requests (ETag). |
| `brana inbox add-account\|add\|list\|poll\|remove\|status\|set-password` | Gmail newsletter management via IMAP. Multi-account, OS keyring credentials. |
| `brana session read\|write\|history\|path\|migrate\|mark-consumed\|insights` | Structured session state — read/write JSON state, browse history, migrate from markdown. `insights` scans JSONL telemetry for recurring friction patterns (tool failures, hook blocks) — surfaces in `/brana:review` weekly friction section. |
| `brana handoff last\|list\|path` | Legacy alias for `brana session`. Falls back to markdown if no JSON state exists. |
| `brana skills suggest\|search\|list\|reindex\|usage` | Skill discovery and semantic routing. `reindex` indexes skills into ruflo memory. `usage` scans JSONL telemetry for invocation counts + cull candidates. |
| `brana knowledge reindex\|status\|search` | Knowledge base indexing. Indexes dimension/reflection/feature docs into ruflo memory. `--patterns` for memory files. |
| `brana knowledge process --tier1\|--tier2\|--draft <topic>\|--status\|--reset-url\|--dry-run` | Inbox→dimensions pipeline. Tier 1: relevance filter (batch 50). Tier 2: cluster assignment + report. Tier 3: draft synthesis (manual gate). |
| `brana knowledge promote <draft-path>` | Promote a draft to `dimensions/`, archive the draft. |
| `brana graph build\|orphans\|query\|path\|stats\|validate` | Knowledge graph operations — ontology-aware spec dependency graph |

### MCP Tools (brana-mcp server)

Exposed via `.mcp.json`. Skills should prefer these over CLI — structured JSON, 65% fewer tokens.

| Tool | Purpose |
|------|---------|
| `backlog_query` | Filter tasks by tag, status, stream, priority, effort, type, parent |
| `backlog_get` | Get single task by ID, optionally a specific field |
| `backlog_set` | Set field on task (status, priority, tags +/-, context, notes) |
| `backlog_add` | Create new task with auto-assigned ID |
| `backlog_search` | Free-text search across all task fields |
| `backlog_stats` | Aggregate stats by status, stream, priority, type |
| `backlog_burndown` | Created vs completed over week/month |
| `backlog_focus` | Top tasks ranked by priority + staleness + effort + blocking |
| `backlog_stale` | Find tasks pending longer than threshold |
| `backlog_batch` | Multi-task, multi-field updates in single read/write cycle |

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
- Use namespace `knowledge` for dimension doc content — **315+ sections from 33 dimension docs are indexed with semantic embeddings**. Any `memory_search` query automatically searches knowledge base content alongside patterns.

### Knowledge Base Pipeline

Two-phase pipeline indexes 7 doc categories (dimensions, architecture, reflections, decisions, features, ideas, research) into ruflo memory. Phase 1 (`index-knowledge.sh`) parses markdown by `##` headers → JSONL. Phase 2 defaults to `mcp-index.mjs` (MCP-first: 5-way parallel `memory_store`, auto-embeddings, HNSW auto-maintained) with `bulk-index.mjs` as SQLite fallback (`USE_SQLITE=1` or ruflo unavailable). Skill indexing (`index-skills.sh`) uses the same 2-phase pipeline. Pattern indexing (`index-patterns.sh`) scheduled weekly (Sun 3am). Reindexing happens:
- **On commit** — post-commit hook in brana-knowledge reindexes changed files
- **Weekly** — scheduled full reindex (Sunday 3am) as safety net
- **Manual** — `brana knowledge reindex`, `brana knowledge reindex --changed`, or `brana knowledge reindex file.md`

## Field Notes

### 2026-04-10: Python in procedures = missing CLI subcommand
Every `python3 -c` in `system/procedures/` or `system/scripts/` is a gap indicator — there should be a `brana` CLI subcommand for that operation. Treat Python as a temporary placeholder, not a solution. File a task to add the CLI subcommand.
Source: feat/t-1075, friction section wiring session

### 2026-04-12: Config drift source_only alerts for rules/ are false positives
`bootstrap.sh` intentionally skips copying `system/rules/` to `~/.claude/` — rules are loaded by the Claude Code plugin at runtime. The config-drift detector doesn't know this and flags them as missing. Filter out `source_only` entries under `rules/` when reviewing drift alerts; they are expected. Real drift = scripts, hooks, agents, skills.
Source: maintenance session 2026-04-12

### 2026-04-12: Stale worktrees post-merge have untracked files from prior work
After a `--no-ff` merge, the worktree stays checked out at its last commit. Untracked files in the worktree look like active WIP but may be superseded by the merged version. Before debugging untracked files in a worktree, run `git show <merge-commit>:<path>` to confirm the committed version differs. Always run `git worktree remove <path>` immediately after merging. t-1147 tracks sitrep detection.
Source: t-1131 session 2026-04-12

### 2026-04-12: cargo build --release stale incremental cache after large changes
`cargo check` passes but `cargo build --release` fails with type errors on first attempt after significant code additions. Second attempt succeeds because the incremental cache self-heals. Reliable fix: `cargo clean -p <crate-name> && cargo build --release`. Or set `CARGO_INCREMENTAL=0` for release builds.
Source: t-1131 session 2026-04-12

### 2026-04-12: CC plugin registration is filesystem-level, not UI-gated
`bootstrap.sh` step 7d writes `~/.claude/plugins/installed_plugins.json` and snapshots `system/` to the plugin cache directly. The `/plugin marketplace add` and `/plugin install` CC commands are UI sugar over the same JSON file — they are not required. Any installer that writes `installed_plugins.json` achieves full plugin registration without entering a CC session. Apply to any future CC plugin distribution work.
Source: t-501 session 2026-04-12

### 2026-04-12: Compounding loop framing beats feature enumeration for README positioning
When comparing brana to PAI, SuperClaude, skill-kit, CCCBot — all lead with feature lists. The differentiator is behavioral accumulation over time (corrections persist, patterns compound, confidence grows). Before/after framing ("stateless Claude" vs "compounding brana") landed better than counting skills/rules/agents. Lead with the compounding loop narrative, not breadth.
Source: t-560 README + distribution brainstorm 2026-04-12

### 2026-04-12: Prefer git worktree add over git stash + git switch -c
Worktree gate blocks `git switch -c` when unstaged changes exist. Using `git worktree add ../repo-feat/branch -b branch` instead of stash+switch avoids both the gate and the tasks.json stash-pop conflict pattern. Worktrees fully isolate the merge path. Preferred flow: stash specific files if needed → worktree add → work → merge --no-ff → worktree remove.
Source: t-501 session 2026-04-12
