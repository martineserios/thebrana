# Feature: CLI as Composable Tool

**Date:** 2026-03-14
**Status:** planning
**Task:** t-463

## Problem

Skills read the entire 435KB tasks.json into context (100K+ tokens) to perform
operations that should take 11ms. The CLI has 12 read commands but zero write
commands. Every mutation requires Read → Edit → Write of the full file.

## Decision Record (frozen 2026-03-14)

> Do not modify after acceptance.

**Context:** The Rust CLI (brana) handles reads in 11ms with 23 tests. Skills
should orchestrate CLI calls instead of touching files directly. The gap is
write commands and a few missing read aggregations.

**Decision:** Add 8 new commands + enhance existing query. All output JSON by
default. Skills become pure orchestrators: parse intent → call CLI → format.

**Consequences:** Skills drop from ~60s to ~33ms for task operations. Context
cost drops from 100K tokens to near zero. File mutations become atomic CLI
calls instead of full-file rewrites.

## New Commands

### Write (2 commands)

1. **`backlog set <id> <field> <value>`** — Update any field on a task.
   - Scalar: `set t-1 status completed`
   - Array append/remove: `set t-1 tags +dx`, `set t-1 tags -dx`
   - Text append: `set t-1 context --append "note"`
   - Output: `{"ok":true,"id":"t-1","field":"status","value":"completed"}`

2. **`backlog add --json '<task>'`** — Create task with auto-assigned ID.
   - Defaults: status=pending, execution=code, created=today
   - Output: `{"ok":true,"id":"t-464","subject":"..."}`

### Read (4 commands)

3. **`backlog get <id> [--field F]`** — Full task JSON or single field.
4. **`backlog roadmap [--json]`** — Phase → milestone → task tree with progress.
5. **`backlog tags [--filter "a,b"] [--any "a,b"]`** — Tag inventory or filter.
6. **`backlog stats`** — Aggregates by status/stream/priority/type.

### Cross-client (1 command)

7. **`backlog status --all [--json]`** — Reads tasks-portfolio.json, aggregates
   all projects.

### Scoped (1 command)

8. **`backlog tree <id> [--json]`** — Subtree of a phase/milestone.

### Query Enhancements (existing command)

- `--tag "a,b"` → multi-tag AND (comma-separated)
- `--type task` → filter by type
- `--parent ph-012` → children of
- `--branch "feat/t-463"` → match by branch field

## Implementation Waves

### Wave 1: Write primitives (highest value)
- `backlog set` — the universal write command
- `backlog add` — task creation
- Tests for both

### Wave 2: Missing reads
- `backlog get` — full task retrieval
- `backlog stats` — aggregates
- `backlog tags` — inventory + filter
- Tests for all

### Wave 3: Tree rendering
- `backlog roadmap` — full tree
- `backlog tree <id>` — scoped subtree
- Tests for both

### Wave 4: Cross-client + query enhancements
- `backlog status --all` — portfolio aggregation
- Query: multi-tag, --type, --parent, --branch
- Tests for all

### Wave 5: Skill rewiring
- Update backlog skill to use CLI calls instead of file reads
- Update build skill to use `set` for status/build_step transitions
- Update hooks to use new commands where applicable
- Integration tests

## Constraints

- All output JSON by default, `--output themed` for human-readable
- Auto-detect tasks.json from git root; `--file <path>` override
- Atomic writes: read-modify-write with file locking (avoid corruption)
- Exit 0 on success, exit 1 on error (always JSON error body)
- No new dependencies — pure Rust, same 11ms startup
