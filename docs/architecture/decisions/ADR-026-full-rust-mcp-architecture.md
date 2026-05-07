---
status: accepted
---
# ADR-026: Full Rust + MCP Architecture — Cargo Workspace with pmcp

**Date:** 2026-04-05
**Status:** accepted
**Related:** ADR-022 (brana CLI), ADR-023 (Rust dispatcher), t-608 (dynamic skill routing), ph-cli-arch (phase)

## Context

ADR-023 established the Rust CLI dispatcher with a Python fallback (`delegate_python()`) for complex operations. This created a dual-language system:

- **Rust**: 30+ backlog subcommands, feed, inbox, files, transcribe, run — 12ms startup
- **Python**: focus scoring, burndown, blocked chains, stale detection, scheduler ops, GitHub sync, decision log, spec graph, reference generation — ~2,950 lines across 9 files

Skills invoke the CLI via `Bash("brana backlog ...")` shell-outs. Memory operations go through MCP (ruflo). This creates two problems:

1. **Token overhead**: Each bash shell-out costs ~450 tokens (command + stdout noise + extra reasoning turn). MCP tool calls cost ~180 tokens. With 18-42 backlog calls per build session, that's 5k-21k tokens wasted — ~10% of a 200k context window.

2. **Dual-language friction**: Python and Rust parse `tasks.json` independently with slightly different classification logic. Cross-language function calls go through subprocess. No shared type safety.

### Measured call frequency

| Skill | Backlog CLI calls | Memory MCP calls | Total |
|-------|------------------:|-----------------:|------:|
| `/brana:build` (medium) | 10-16 | 2-4 | 12-20 |
| `/brana:build` (large) | 15-21 | 6-9 | 21-30 |
| `/brana:backlog plan` | 10-15 | 0 | 10-15 |
| `/brana:close` | 1-2 | 3-8 | 4-10 |

Feed, inbox, and files are never called from skills — human-operated only.

## Decision

Restructure the brana CLI into a **Cargo workspace with three crates**. Absorb all Python business logic into Rust. Expose backlog operations as MCP tools using the pmcp SDK.

### Workspace structure

```
system/cli/rust/
├── crates/
│   ├── brana-core/              ← ALL business logic (no I/O framework deps)
│   │   ├── src/
│   │   │   ├── backlog.rs       ← task lifecycle, filtering, scoring, analysis
│   │   │   ├── feeds.rs         ← feed registry, polling, state
│   │   │   ├── inbox.rs         ← IMAP accounts, subscriptions, polling
│   │   │   ├── files.rs         ← manifest, SHA-256, status
│   │   │   ├── scheduler.rs     ← job config, collision detection, health
│   │   │   ├── sync.rs          ← task↔GitHub sync logic
│   │   │   ├── decisions.rs     ← append-only JSONL log
│   │   │   ├── spec_graph.rs    ← markdown cross-reference graph
│   │   │   ├── reference.rs     ← frontmatter doc generation
│   │   │   └── lib.rs
│   │   └── Cargo.toml
│   │
│   ├── brana-cli/               ← presentation + subprocess orchestration
│   │   ├── src/
│   │   │   ├── main.rs          ← clap → core → format → print
│   │   │   └── theme.rs         ← ANSI formatting
│   │   └── Cargo.toml           ← brana-core + clap
│   │
│   └── brana-mcp/               ← MCP adapter
│       ├── src/
│       │   └── main.rs          ← pmcp server → core → JSON-RPC
│       └── Cargo.toml           ← brana-core + pmcp + tokio
│
└── Cargo.toml                   ← workspace
```

### MCP SDK: pmcp (paiml)

Using [paiml/rust-mcp-sdk](https://github.com/paiml/rust-mcp-sdk) v2.0 instead of the official rmcp. Rationale:

- Full ecosystem: SDK + `cargo-pmcp` CLI (scaffold, test, loadtest, deploy)
- Production-grade with zero-tolerance quality standards
- Supports all needed transports (stdio for Claude Code)
- Automatic JSON schema generation via schemars
- Claude Code subagent (`mcp-developer.md`) for guided development

### Domain model

Nine bounded contexts defined in `docs/domain/MODEL-001-brana-core.md`:

1. **Backlog** — task lifecycle (aggregate root: TaskStore)
2. **Feeds** — RSS/Atom polling (aggregate root: FeedRegistry)
3. **Inbox** — IMAP monitoring (aggregate root: InboxRegistry)
4. **Files** — content-addressed tracking (aggregate root: Manifest)
5. **Scheduler** — job health/collisions (from ops.py)
6. **Sync** — GitHub Issue sync (from task-sync.py)
7. **Decisions** — structured log (from decisions.py)
8. **Spec Graph** — doc cross-refs (from spec_graph.py)
9. **Reference** — doc generation (from generate-reference.py)

Cross-context communication happens through the application layer (CLI/MCP), never within brana-core.

### Python elimination

All ~2,950 lines of Python business logic absorbed into brana-core. Files deleted:

- `system/cli/*.py`, `system/__init__.py`
- `system/hooks/task-sync.py`
- `system/scripts/decisions.py`, `spec_graph.py`, `generate-reference.py`
- `tests/` (Python test suite — replaced by Rust tests)
- `pyproject.toml`

After migration: zero Python dependencies, single `cargo build --release` produces both binaries.

## Consequences

### Positive

- **65% fewer tokens per tool call** — MCP structured responses vs bash stdout parsing
- **10% context window recovered** on heavy sessions (21k tokens saved on full-day usage)
- **Single type system** — one `Task` struct, compiler-enforced schema consistency
- **Composability** — any core function callable from any other module
- **Zero runtime deps** — no Python, no uv, no virtualenvs
- **12ms CLI startup preserved** — async/tokio isolated to brana-mcp
- **Refactoring safety** — Rust compiler catches schema drift across entire codebase

### Negative

- **Migration effort** — 30+ cmd_* handlers need presentation/logic separation, ~2,950 lines of Python to port, ~1,661 lines of tests to recreate
- **New daemon** — MCP server is a persistent process (mitigated by Claude Code's automatic lifecycle management via .mcp.json)
- **Two binaries** — brana-cli + brana-mcp to build and distribute
- **Tokio dependency** — brana-mcp pulls in async runtime (isolated from CLI)

### Neutral

- Agent management (PID, tmux, worktrees) stays in brana-cli — not worth abstracting
- `delegate_python()` eliminated — no more cross-language bridge
- `brana-query` and `brana-fmt` folded into brana-cli — workspace makes them redundant
