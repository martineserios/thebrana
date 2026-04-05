# Brana CLI MCP Layer — Architecture Decision

> Investigated 2026-04-05. Status: recommendation ready, pending build approval.

## Question

Should the brana CLI tools (backlog, feed, inbox, files) be exposed as an MCP server, kept as CLI-only, or built as a hybrid? What's the right architecture for long-term?

## Context

The brana Rust CLI (`system/cli/rust/`) currently serves as the primary interface for task management, feed polling, inbox monitoring, and file tracking. Skills invoke it via `Bash("brana backlog ...")` shell-outs. Memory operations already go through MCP (ruflo). This creates an inconsistent tool surface: half the calls are clean MCP, half are noisy bash wrappers.

Related: [dynamic-skill-routing.md](./dynamic-skill-routing.md) (t-608) proposes a skill-registry MCP server using the same tech stack.

## Findings

### 1. Current CLI architecture

- **Rust binary** (clap, sync, 12ms startup) + **Python fallback** (typer, for complex ops)
- Commands: backlog (30+ subcommands), feed, inbox, files, transcribe, run, queue, doctor, validate
- **Data layer is already clean**: `tasks.rs` has `load_tasks()`, `filter_tasks()`, `compute_stats()`, `build_tree()` returning structured types
- **Presentation is coupled**: 30+ `cmd_*` functions return `()` and `println!` directly with ANSI formatting
- **Error handling inconsistent**: backlog uses `process::exit(1)`, feed/inbox use `Result<()>`
- Single crate with multiple binaries (brana, brana-query, brana-fmt)

### 2. Call frequency from skills (measured)

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

### 3. Heaviest callers

- **backlog**: 76 references across 6 skills (build, backlog, sitrep, close, docs, brainstorm)
- **memory**: 41 references across 11 skills (build, close, research, review, reconcile, harvest, etc.)
- **build + backlog** are the dominant pair — 85 combined references

### 4. Token cost analysis

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

21k tokens = ~10% of a 200k context window recovered. Context compression kicks in later, conversation history preserved longer, fewer parsing errors.

### 5. MCP Rust ecosystem

- **Official SDK**: `rmcp` crate (4.7M+ downloads, `#[tool]` macro, stdio transport, tokio)
- Stdio transport is the standard for Claude Code integration
- Existing anti-pattern documented: no `npx` — use compiled binaries with absolute paths

### 6. CLI vs MCP server runtime differences

| | CLI | MCP Server |
|---|---|---|
| Lifecycle | Run, print, exit | Long-running daemon |
| I/O model | Sync, blocking | Async (tokio) |
| Output | Formatted text + ANSI | Structured JSON-RPC |
| Startup | Must be fast (12ms) | Doesn't matter (starts once) |
| Dependencies | clap, minimal | rmcp, tokio, heavier |

## Options evaluated

### Option A: Single `brana mcp serve` subcommand

One binary, two modes. MCP handler calls same internal functions.

- Pro: One build, one deploy, shared code
- Con: Pulls tokio + rmcp into CLI binary (~2-3MB), startup cost for non-MCP usage

### Option B: Separate `brana-mcp` binary with shared `brana-core` lib (recommended)

```
system/cli/rust/
├── crates/
│   ├── brana-core/          <- shared data layer
│   │   ├── tasks.rs         <- load, filter, mutate, stats
│   │   ├── feeds.rs         <- load, poll, state
│   │   ├── inbox.rs         <- load, poll, state
│   │   ├── files.rs         <- manifest, status
│   │   └── lib.rs
│   │
│   ├── brana-cli/           <- thin presentation layer
│   │   └── main.rs          <- clap parse -> core fn -> format -> print
│   │
│   └── brana-mcp/           <- thin MCP adapter
│       └── main.rs          <- rmcp server -> core fn -> JSON-RPC response
│
└── Cargo.toml               <- workspace
```

- Pro: CLI stays lean (12ms), MCP can be async, clean separation
- Con: Two binaries, needs lib extraction refactor

### Option C: MCP wraps CLI via shell-out

MCP server spawns `brana` subprocess for each tool call.

- Pro: Zero refactoring, ship immediately
- Con: Process spawn overhead, stdout parsing fragility, disposable work

## Challenges considered

1. **"The problem might not exist"** — Refuted by frequency data: 18-42 calls/session, 5k-21k tokens wasted per session.

2. **"You're adding a daemon"** — Valid concern. MCP server is a new process to manage. Mitigated by Claude Code's native MCP lifecycle (spawns/kills automatically via `.mcp.json`).

3. **"Refactoring is bigger than you think"** — Partially valid. 30+ cmd_* functions need presentation/logic separation. But data layer functions (tasks.rs, load/filter/stats) already return structured types — those move to core as-is.

4. **"Designing for futures that won't arrive"** — The second consumer (MCP server) is concrete and justified by token savings. TUI/WASM are speculative and NOT part of this plan.

5. **"MCP resources/subscriptions solve a problem Claude doesn't have"** — Valid for now. Claude Code sessions are ephemeral. Resources are Phase 3 / nice-to-have, not driving the decision.

6. **"Opportunity cost"** — Real. Mitigated by phased approach — Phase 1 delivers value in ~1 week.

## Recommendation: Option B, phased

### Phase 1 — Workspace + core extraction (~1 week)

- Create Cargo workspace with `brana-core`, `brana-cli`, `brana-mcp` crates
- Move data layer functions into `brana-core`: `load_tasks`, `filter_tasks`, `compute_stats`, `build_tree`, `portfolio_status` (already return structured types)
- CLI imports core, cmd_* handlers become: `let data = core::query(...); println!("{}", format(data));`
- Standardize error handling on `Result<T, anyhow::Error>` (kill `process::exit(1)` pattern)

### Phase 2 — MCP server for backlog (~1 week)

- Build `brana-mcp` binary using `rmcp` with stdio transport
- Priority tools (covers 80% of call volume):

| MCP Tool | Maps to | Calls/session |
|----------|---------|--------------|
| `backlog_query` | `core::tasks::filter_tasks()` | 5-10 |
| `backlog_get` | single task lookup | 3-5 |
| `backlog_set` | `core::tasks::set_field()` | 3-6 |
| `backlog_add` | `core::tasks::add_task()` | 2-5 |
| `backlog_stats` | `core::tasks::compute_stats()` | 1-2 |
| `backlog_search` | `core::tasks::search()` | 2-3 |

- Register in `.mcp.json` with absolute path to binary
- Update skills to use MCP tools instead of bash shell-outs

### Phase 3 — Expand + polish (later, as needed)

- Add feed/inbox read-only tools (low priority — not called from skills today)
- Merge skill-registry MCP (t-608b) into same server
- MCP resources: `brana://tasks/current`, `brana://tasks/{id}`
- MCP prompts: pre-built templates for common operations

### What NOT to do

- Don't expose transcribe, run, push/pull via MCP — inherently interactive/local
- Don't build MCP resources until there's a concrete consumer (Phase 3 / speculative)
- Don't over-engineer the core lib — extract what exists, don't redesign

## Tool surface (full plan)

| MCP Tool | Priority | Source |
|----------|----------|--------|
| `backlog_query` | P0 | `filter_tasks() + sort_by_priority()` |
| `backlog_get` | P0 | single task lookup |
| `backlog_set` | P0 | `cmd_set()` extracted |
| `backlog_add` | P0 | `cmd_add()` extracted |
| `backlog_stats` | P1 | `compute_stats()` |
| `backlog_tree` | P1 | `build_tree()` |
| `backlog_search` | P0 | text search across tasks |
| `feed_list` | P2 | `load_feeds()` |
| `feed_poll` | P2 | `poll_one()` |
| `feed_status` | P2 | state file reads |
| `inbox_poll` | P2 | `poll_account()` |
| `inbox_status` | P2 | state file reads |
| `files_status` | P2 | `Manifest::status()` |
| `skill_search` | P1 | t-608b merge |
| `skill_suggest` | P2 | t-608b merge |

## Dependencies

- `rmcp` crate (official Rust MCP SDK)
- `tokio` (async runtime, MCP server only)
- Existing: `serde`, `chrono`, `anyhow`, `ureq`, `imap`, `feed-rs` (move to core)
- `clap` stays in CLI crate only

## Open questions

1. **State location discovery**: MCP server needs to find `tasks.json` and `~/.claude/scheduler/`. Discover via git root? Config arg? Environment variable?
2. **Async boundary**: feed polling and IMAP are blocking I/O. Use `tokio::task::spawn_blocking` or switch to async HTTP/IMAP crates in core?
3. **Skill updates**: When MCP tools are ready, update skills to prefer MCP calls over bash. Gradual migration or big-bang?
4. **One server or two**: Merge skill-registry (t-608b) into brana-mcp, or keep separate? Leaning merge (one `.mcp.json` entry, shared state access).
