# ADR-023: Rust CLI Dispatcher — Single Binary Entry Point

**Date:** 2026-03-14
**Status:** accepted
**Related:** ADR-022 (brana CLI), t-427 (Rust evaluation), t-457 (system integration)

## Context

ADR-022 established the brana CLI with Python (typer+rich) as the primary surface. The Python CLI works but has a structural limitation: **430ms startup time per invocation** due to Python/uv interpreter overhead. This matters in two contexts:

1. **Scheduler jobs** — currently call shell scripts directly because Python startup is too expensive for automated jobs that run every few minutes
2. **Shell pipelines** — `bfq | bfqf` uses standalone Rust binaries that duplicate classification/theme logic

The t-428 build produced two standalone Rust binaries (`brana-query`, `brana-fmt`) that proved the concept: 12ms startup, 34x faster than Python. But they're separate tools, not a unified CLI.

## Decision

Build a **single `brana` Rust binary** that serves as the primary entry point. It handles high-frequency commands natively and delegates complex operations (diff, burndown) to the Python CLI.

### Architecture

```
brana (Rust, 12ms startup)
├── backlog {next,query,search,focus,status,blocked,stale,context}  ← native Rust
├── backlog {diff,burndown}                                         ← delegates to Python
├── ops {status,health,collisions,drift,logs,history}               ← native Rust
├── ops {run,enable,disable}                                        ← Rust + systemctl
├── ops {sync,reindex}                                              ← Rust shells out to .sh scripts
├── doctor                                                          ← native Rust
└── version                                                         ← native Rust
```

### Shared modules

- `tasks.rs` — task loading, classification, filtering, focus scoring, duplicate detection
- `themes.rs` — theme loading from `themes.json`, ANSI rendering

These replace the duplicated logic in `brana-query` and `brana-fmt`. The standalone binaries stay for backward compatibility but the dispatcher subsumes their functionality.

### Scheduler integration

Scheduler jobs can now call the Rust binary directly:
```json
{"command": "./system/cli/rust/target/release/brana ops sync --auto-commit"}
```
12ms startup vs 430ms Python or ~50ms bash script.

### Python fallback

Commands that need Rich tables, portfolio reads, or complex git operations delegate to Python:
```rust
fn delegate_python(args: &[&str]) {
    Command::new("uv").args(["run", "brana"]).args(args).status();
}
```

## Consequences

- **Positive:** Single binary, 12ms startup, no Python dependency for common operations
- **Positive:** Scheduler jobs can use CLI directly instead of shell scripts
- **Positive:** Shared task/theme modules eliminate logic duplication between brana-query and brana-fmt
- **Positive:** Graceful degradation — if Rust binary absent, Python CLI still works
- **Negative:** Two CLIs to maintain (Rust for speed, Python for Rich output). Mitigation: Rust handles data, Python handles presentation.
- **Negative:** Rust compilation step required. Mitigation: binary is committed or installed once via `cargo build --release`.
- **Risk:** Classification logic could drift between Rust and Python. Mitigation: shared test fixtures validate both produce identical results.

## Task file discovery

`find_tasks_file()` in `cli.rs` and `sync.rs` resolves `tasks.json` using a two-step strategy:

1. **Primary:** `git rev-parse --git-common-dir` → parent dir → `.claude/tasks.json`. This ensures all worktrees share the main repo's authoritative tasks.json.
2. **Fallback:** `git rev-parse --show-toplevel` → `.claude/tasks.json`. Used when git-common-dir doesn't resolve or the file doesn't exist at the common root.

This matches the pattern used by `task-id-lock.sh` for flock (shared across worktrees via `$GIT_COMMON_DIR`).

## File structure

```
system/cli/rust/
├── Cargo.toml
├── src/
│   ├── cli.rs       # main dispatcher (brana binary)
│   ├── main.rs      # standalone brana-query (backward compat)
│   ├── fmt.rs        # standalone brana-fmt (backward compat)
│   ├── tasks.rs     # shared: load, classify, filter, focus, duplicates
│   └── themes.rs    # shared: theme loading, ANSI rendering
└── .gitignore       # excludes target/
```
