# Brana CLI MCP Layer — Architecture Decision

> Investigated 2026-04-05. Status: **decided** — full Rust, zero Python.

## Decision

Option B: Cargo workspace with three crates (`brana-core`, `brana-cli`, `brana-mcp`). All business logic in Rust. Python eliminated entirely.

## Question

Should the brana CLI tools (backlog, feed, inbox, files) be exposed as an MCP server, kept as CLI-only, or built as a hybrid? And should the remaining Python logic (~2,950 lines) be absorbed into Rust or kept?

## Context

The brana Rust CLI (`system/cli/rust/`) currently serves as the primary interface for task management, feed polling, inbox monitoring, and file tracking. Skills invoke it via `Bash("brana backlog ...")` shell-outs. Memory operations already go through MCP (ruflo). This creates an inconsistent tool surface: half the calls are clean MCP, half are noisy bash wrappers.

Additionally, ~2,950 lines of Python business logic remain across 9 files (`backlog.py`, `ops.py`, `task-sync.py`, `decisions.py`, `spec_graph.py`, `generate-reference.py`, `config.py`, `theme.py`, `main.py`), creating a dual-language system with duplicated data models, inconsistent error handling, and a `delegate_python()` bridge pattern.

Related: [dynamic-skill-routing.md](./dynamic-skill-routing.md) (t-608) proposes a skill-registry MCP server — to be merged into `brana-mcp`.

## Findings

### 1. Current CLI architecture

- **Rust binary** (clap, sync, 12ms startup) + **Python fallback** (typer, for complex ops via `delegate_python()`)
- Commands: backlog (30+ subcommands), feed, inbox, files, transcribe, run, queue, doctor, validate
- **Data layer is already clean**: `tasks.rs` has `load_tasks()`, `filter_tasks()`, `compute_stats()`, `build_tree()` returning structured types
- **Presentation is coupled**: 30+ `cmd_*` functions return `()` and `println!` directly with ANSI formatting
- **Error handling inconsistent**: backlog uses `process::exit(1)`, feed/inbox use `Result<()>`
- Single crate with multiple binaries (brana, brana-query, brana-fmt)

### 2. Python logic inventory

| File | Lines | What it does | Rust overlap? |
|------|------:|--------------|---------------|
| `cli/backlog.py` | 688 | Focus scoring, burndown, blocked chains, stale detection, git diff | Partial — `brana-query` handles filtering |
| `cli/ops.py` | 483 | Scheduler status, systemd timers, job management, drift detection | None |
| `cli/main.py` | 183 | `brana doctor` checks, version detection, ruflo health | None |
| `cli/config.py` | 122 | Task loading, classification, path helpers | Duplicate — `tasks.rs` has equivalent |
| `cli/theme.py` | 111 | Icons, colors, progress bars, task line formatting | None |
| `hooks/task-sync.py` | 356 | Bidirectional task-to-GitHub-Issue sync | None |
| `scripts/decisions.py` | 260 | Append-only decision log (JSONL) | None |
| `scripts/generate-reference.py` | 315 | Deterministic reference doc generator | None |
| `scripts/spec_graph.py` | 433 | Markdown cross-reference graph | None |
| **Tests** (4 files) | 1,661 | Coverage for backlog, task-sync, spec_graph, decisions | — |

**Total: ~2,950 lines of logic + ~1,661 lines of tests.**

### 3. Call frequency from skills (measured)

| Skill | Backlog CLI calls | Memory MCP calls | Total |
|-------|------------------:|-----------------:|------:|
| `/brana:build` (medium) | 10-16 | 2-4 | 12-20 |
| `/brana:build` (large) | 15-21 | 6-9 | 21-30 |
| `/brana:backlog plan` | 10-15 | 0 | 10-15 |
| `/brana:close` | 1-2 | 3-8 | 4-10 |
| `/brana:sitrep` | 2 | 0 | 2 |
| `/brana:review` | 0 | 1-4 | 1-4 |

Typical build session (build + sitrep + close): **18-42 CLI/memory calls**.
Full day (3 builds + close): **~80 calls**.

**Critical finding**: feed, inbox, and files are **never called from skills** — they are human-operated CLI tools only.

### 4. Heaviest callers

- **backlog**: 76 references across 6 skills (build, backlog, sitrep, close, docs, brainstorm)
- **memory**: 41 references across 11 skills (build, close, research, review, reconcile, harvest, etc.)
- **build + backlog** are the dominant pair — 85 combined references

### 5. Token cost analysis

| | CLI (bash wrapper) | MCP (native tool) | Delta |
|---|---|---|---|
| Tool invocation | ~50 tokens | ~30 tokens | -20 |
| Tool result | ~300 tokens (stdout noise, ANSI, headers) | ~150 tokens (clean JSON) | -150 |
| Extra reasoning turn | ~100 tokens (parse text, handle errors) | ~0 (structured data) | -100 |
| **Per call** | **~450 tokens** | **~180 tokens** | **-270** |

Per-session savings:

| Session type | Calls | CLI tokens | MCP tokens | Saved |
|-------------|------:|-----------:|----------:|---------:|
| Light build | 18 | 8,100 | 3,240 | **4,860** |
| Heavy build | 42 | 18,900 | 7,560 | **11,340** |
| Full day | ~80 | 36,000 | 14,400 | **21,600** |

21k tokens = ~10% of a 200k context window recovered.

### 6. MCP Rust ecosystem

- **Official SDK**: `rmcp` crate (4.7M+ downloads, `#[tool]` macro, stdio transport, tokio)
- Stdio transport is the standard for Claude Code integration
- Existing anti-pattern documented: no `npx` — use compiled binaries with absolute paths

### 7. CLI vs MCP server runtime differences

| | CLI | MCP Server |
|---|---|---|
| Lifecycle | Run, print, exit | Long-running daemon |
| I/O model | Sync, blocking | Async (tokio) |
| Output | Formatted text + ANSI | Structured JSON-RPC |
| Startup | Must be fast (12ms) | Doesn't matter (starts once) |
| Dependencies | clap, minimal | rmcp, tokio, heavier |

## Why full Rust, zero Python

### Arguments for keeping Python (rejected)

- **"Faster to write"** — True for first version. But code is maintained 10x longer than written. Rust's compiler pays back on every future change.
- **"Subprocess-heavy code doesn't get faster"** — The subprocess calls don't, but the logic around them (collision detection, drift comparison, health aggregation, label building, body generation) gets safer, more composable, and testable without mocks.
- **"Python is more readable for glue code"** — Subjective, and irrelevant with one contributor. Consistency beats preference.
- **"Infrequent scripts don't need Rust"** — Not about speed. About type safety, composability, and zero runtime dependencies.

### Arguments for full Rust (accepted)

1. **Single binary, zero runtime deps.** No Python version drift, no `uv`, no virtualenvs, no `pip install` breaking. `brana` is one file. Copy it. It works.

2. **One type system across the entire codebase.** Today `tasks.json` is parsed independently in Python (`config.py`) and Rust (`tasks.rs`) with slightly different classification logic. One `Task` struct in `brana-core`, used everywhere — compiler enforces the contract.

3. **Refactoring safety.** Rename a field in the task schema? Compiler shows every callsite. In Python you find out at runtime.

4. **Composability.** Today `ops.py` can't call `tasks.rs` functions. `task-sync.py` can't use the focus scoring algorithm. Everything is isolated by language boundary. In unified Rust, `task-sync` imports `brana_core::tasks::focus_score()` directly.

5. **Testability.** Pure functions on typed data = unit tests with `assert_eq!`. No subprocess mocking, no stdout capture. The hardest-to-test logic becomes the easiest to test.

6. **MCP gets everything for free.** Any function in `brana-core` is one `#[tool]` wrapper away from being an MCP tool. No new integration work per feature.

## Options evaluated

### Option A: Single `brana mcp serve` subcommand

One binary, two modes.

- Pro: One build, one deploy, shared code
- Con: Pulls tokio + rmcp into CLI binary (~2-3MB), startup cost for non-MCP usage
- **Rejected** — different runtime requirements (sync vs async, fast startup vs long-running)

### Option B: Cargo workspace with shared `brana-core` (decided)

Three crates, two binaries, one shared library.

- Pro: CLI stays lean (12ms), MCP can be async, clean separation, all logic shared
- Con: Two binaries to build
- **Selected** — right tradeoffs for long-term system quality

### Option C: MCP wraps CLI via shell-out

MCP server spawns `brana` subprocess per tool call.

- Pro: Zero refactoring
- Con: Process spawn overhead, stdout parsing fragility, disposable work
- **Rejected** — builds technical debt, doesn't address the dual-language problem

## Target architecture

```
system/cli/rust/
├── crates/
│   ├── brana-core/                  <- ALL business logic
│   │   ├── src/
│   │   │   ├── tasks.rs            <- load, filter, classify, focus, burndown, blocked chains
│   │   │   ├── feeds.rs            <- load, poll, state
│   │   │   ├── inbox.rs            <- load, poll, state
│   │   │   ├── files.rs            <- manifest, status, pull/push
│   │   │   ├── scheduler.rs        <- job config, collision detect, health (from ops.py)
│   │   │   ├── sync.rs             <- task<>GitHub sync logic (from task-sync.py)
│   │   │   ├── decisions.rs        <- append-only JSONL log (from decisions.py)
│   │   │   ├── spec_graph.rs       <- cross-reference graph (from spec_graph.py)
│   │   │   ├── reference.rs        <- reference doc generation (from generate-reference.py)
│   │   │   └── lib.rs
│   │   └── Cargo.toml              <- serde, chrono, anyhow, ureq, imap — no clap, no rmcp
│   │
│   ├── brana-cli/                   <- thin presentation + subprocess calls
│   │   ├── src/
│   │   │   ├── main.rs             <- clap parse -> core fn -> format -> print
│   │   │   └── theme.rs            <- ANSI formatting (from theme.py)
│   │   └── Cargo.toml              <- brana-core + clap
│   │
│   └── brana-mcp/                   <- thin MCP adapter
│       ├── src/
│       │   └── main.rs             <- rmcp server -> core fn -> JSON-RPC response
│       └── Cargo.toml              <- brana-core + rmcp + tokio
│
└── Cargo.toml                       <- workspace
```

### What lives where

| Layer | Contains | Does NOT contain |
|-------|----------|-----------------|
| **brana-core** | All business logic, data types, algorithms, state I/O | CLI parsing, ANSI formatting, MCP protocol, subprocess calls |
| **brana-cli** | clap parsing, ANSI themes, `println!`, `Command::new("systemctl\|gh")` | Business logic, data types |
| **brana-mcp** | rmcp server, `#[tool]` wrappers, stdio transport | Business logic, CLI concerns |

### Subprocess boundary

Logic that wraps external process calls splits cleanly:

```rust
// brana-core: pure logic (testable)
let health = brana_core::scheduler::check_health(&config)?;
let collisions = brana_core::scheduler::detect_collisions(&config)?;
let sync_plan = brana_core::sync::plan_sync(&tasks, &issues)?;

// brana-cli: thin subprocess calls (not worth unit testing)
let timer_status = Command::new("systemctl").args(["is-active", &name]).output()?;
let gh_result = Command::new("gh").args(["api", &endpoint]).output()?;
```

## Python elimination plan

| Python file | Destination | What moves |
|-------------|------------|------------|
| `backlog.py` focus scoring | `core::tasks::focus_score()` | Priority weights + staleness + effort + blocking depth algorithm |
| `backlog.py` burndown | `core::tasks::burndown()` | Date bucketing, created/completed tracking |
| `backlog.py` blocked chains | `core::tasks::blocked_chain()` | Dependency graph walk with cycle detection |
| `backlog.py` stale detection | `core::tasks::stale_tasks()` | Date math threshold |
| `config.py` classify_task | Already in `tasks.rs` | Delete Python copy |
| `ops.py` scheduler logic | `core::scheduler` | Collision detection, drift comparison, health aggregation, failure tracking |
| `ops.py` systemd calls | `cli` | Thin `Command::new("systemctl")` wrappers |
| `main.py` doctor checks | `core::doctor` (checks) + `cli` (subprocess) | Health check logic vs process spawning |
| `task-sync.py` sync logic | `core::sync` | Label building, body generation, field mapping, hash-based change detection |
| `task-sync.py` gh calls | `cli` | `Command::new("gh")` wrappers |
| `decisions.py` | `core::decisions` | Session management, JSONL append, filtering, archival |
| `spec_graph.py` | `core::spec_graph` | Markdown parsing, cross-ref extraction, graph building |
| `generate-reference.py` | `core::reference` | Frontmatter parsing, table generation |
| `theme.py` | `cli::theme` | ANSI formatting, icons, progress bars |

### Files to delete after migration

- `system/cli/main.py`
- `system/cli/backlog.py`
- `system/cli/ops.py`
- `system/cli/config.py`
- `system/cli/theme.py`
- `system/cli/__init__.py`
- `system/__init__.py`
- `system/hooks/task-sync.py`
- `system/scripts/decisions.py`
- `system/scripts/generate-reference.py`
- `system/scripts/spec_graph.py`
- `tests/test_cli.py`
- `tests/hooks/test_task_sync.py`
- `tests/scripts/test_spec_graph.py`
- `tests/scripts/test_decisions.py`
- `pyproject.toml` (Python project definition)

## Challenges considered

1. **"The problem might not exist"** — Refuted by frequency data: 18-42 calls/session, 5k-21k tokens wasted per session.

2. **"You're adding a daemon"** — Valid concern. MCP server is a new process to manage. Mitigated by Claude Code's native MCP lifecycle (spawns/kills automatically via `.mcp.json`).

3. **"Refactoring is bigger than you think"** — Acknowledged. 30+ cmd_* functions need presentation/logic separation, plus ~2,950 lines of Python to port. But the data layer functions already return structured types, and the Python logic is straightforward algorithms — not framework-dependent.

4. **"Designing for futures that won't arrive"** — The second consumer (MCP server) is concrete and justified by token savings. Full Rust is justified by type safety, composability, and zero runtime deps — not speculative future consumers.

5. **"MCP resources/subscriptions solve a problem Claude doesn't have"** — Valid for now. Resources are Phase 4 / nice-to-have.

6. **"Opportunity cost"** — Real. Mitigated by phased approach. Each phase delivers standalone value.

7. **"Speed/performance gains are marginal"** — Fork/exec savings (~5ms) are negligible. In-memory caching is unnecessary (files are small). The real gains are **token efficiency** (65% reduction per tool call) and **context window preservation** (10% recovered on full-day sessions). IMAP connection reuse is a genuine performance win for inbox polling.

8. **"Python is fine for glue code"** — True in isolation. But in a system, dual-language means duplicated data models, inconsistent error handling, language boundary preventing composability, and a runtime dependency that can break. One language eliminates an entire class of integration problems.

## MCP tool surface

| MCP Tool | Priority | Source |
|----------|----------|--------|
| `backlog_query` | P0 | `core::tasks::filter_tasks()` |
| `backlog_get` | P0 | `core::tasks::get_task()` |
| `backlog_set` | P0 | `core::tasks::set_field()` |
| `backlog_add` | P0 | `core::tasks::add_task()` |
| `backlog_search` | P0 | `core::tasks::search()` |
| `backlog_stats` | P1 | `core::tasks::compute_stats()` |
| `backlog_tree` | P1 | `core::tasks::build_tree()` |
| `backlog_focus` | P1 | `core::tasks::focus_score()` |
| `backlog_burndown` | P1 | `core::tasks::burndown()` |
| `feed_list` | P2 | `core::feeds::list()` |
| `feed_poll` | P2 | `core::feeds::poll()` |
| `feed_status` | P2 | `core::feeds::status()` |
| `inbox_poll` | P2 | `core::inbox::poll()` |
| `inbox_status` | P2 | `core::inbox::status()` |
| `files_status` | P2 | `core::files::status()` |
| `skill_search` | P1 | t-608b merge |
| `skill_suggest` | P2 | t-608b merge |

## Phased implementation

### Phase 1 — Workspace + core extraction

- Create Cargo workspace with `brana-core`, `brana-cli`, `brana-mcp` crates
- Move existing Rust data layer into `brana-core` (tasks.rs functions already return structured types)
- CLI imports core, cmd_* handlers become thin formatters
- Standardize error handling on `Result<T, anyhow::Error>` (kill `process::exit(1)`)
- Delete `config.py` (duplicate of tasks.rs)

### Phase 2 — MCP server for backlog

- Build `brana-mcp` using `rmcp` with stdio transport
- Expose P0 backlog tools (query, get, set, add, search)
- Register in `.mcp.json`
- Update heaviest skills (build, backlog) to use MCP tools

### Phase 3 — Absorb Python logic

- Port `backlog.py` algorithms to `core::tasks` (focus, burndown, blocked chains, stale)
- Port `ops.py` logic to `core::scheduler` + CLI subprocess wrappers
- Port `task-sync.py` to `core::sync` + CLI `gh` wrappers
- Port `decisions.py` to `core::decisions`
- Port `spec_graph.py` to `core::spec_graph`
- Port `generate-reference.py` to `core::reference`
- Write Rust tests replacing Python test suite
- Delete all Python files + `pyproject.toml`

### Phase 4 — Expand MCP + polish (as needed)

- Add P1/P2 MCP tools (stats, burndown, feed, inbox, files)
- Merge skill-registry (t-608b) into `brana-mcp`
- MCP resources: `brana://tasks/current`, `brana://tasks/{id}` (only if concrete need arises)
- Update remaining skills to prefer MCP over bash

## Dependencies

### brana-core
`serde`, `serde_json`, `serde_yaml`, `chrono`, `anyhow`, `ureq`, `imap`, `feed-rs`, `native-tls`, `keyring`, `regex`, `walkdir`

### brana-cli
`brana-core`, `clap`, ANSI formatting (inline or small crate)

### brana-mcp
`brana-core`, `rmcp`, `tokio`

## Open questions

1. **State location discovery**: MCP server needs to find `tasks.json` and `~/.claude/scheduler/`. Discover via git root? Config arg? Environment variable?
2. **Async boundary**: feed polling and IMAP are blocking I/O. Use `tokio::task::spawn_blocking` or switch to async HTTP/IMAP crates in core?
3. **Skill migration**: When MCP tools are ready, update skills to prefer MCP calls over bash. Gradual migration or big-bang?
4. **One server or two**: Merge skill-registry (t-608b) into brana-mcp, or keep separate? Leaning merge.
5. **brana-query and brana-fmt**: Fold into brana-cli as subcommands, or keep as separate binaries? Leaning fold — workspace makes them unnecessary.
