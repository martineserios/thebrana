# tasks.rs — spec

Task: t-1323
Related memory: feedback_rust-tdd-three-commit-pattern.md, project_ruflo-agentdb-status.md

## Purpose

Shared task loading, filtering, classification, and mutation logic used by the `brana` CLI dispatcher, `brana-query`, `brana-fmt`, and the `brana-mcp` backlog tools.

## Public API — invariants

### `load_tasks(path) -> Result<TasksFile, String>`
- Accepts both `{tasks: [...]}` envelope and bare `[...]` JSON array.
- Empty file is valid — returns `TasksFile{project="unknown", tasks=[]}`.

### `classify(task, all) -> &'static str`
Maps a task to its **display-level** status. This is a computed field for humans.
- `status == "completed" | "cancelled"` → `"done"`
- `status == "in_progress"` → `"active"`
- `status == "pending"` + any incomplete dependency → `"blocked"`
- `status == "pending"` + `tags` contains `"parked"` → `"parked"`
- `status == "pending"` otherwise → `"pending"`

Used by renderers and sorters. **Not** a filter predicate.

### `filter_tasks(tasks, all, tag, status, stream, priority, effort, search, types) -> Vec<&Value>`
AND-logic filter over the task list.

**Contract for `status` parameter:** the filter compares the **raw `task.status` field** (one of `"pending"`, `"in_progress"`, `"completed"`, `"cancelled"`). This aligns with the CLI `TaskStatus` enum (`brana-cli/src/cli.rs`) and the equivalent MCP tool input strings.

Callers that want classify-based semantics (e.g. "unblocked pending") must filter the result set post-hoc via `classify()`.

**Rationale:** previously `filter_tasks` compared `classify()` output against the raw CLI input. Since `classify()` returns synthetic values (`"done"`, `"active"`, `"blocked"`, `"parked"`) that the CLI enum does not expose, every `--status` filter other than `pending` silently matched nothing — and every call with valid raw `status` values (`completed`, `cancelled`, `in_progress`) returned *all* tasks as contamination. See t-1323 for the bug trail.

### `sort_by_priority`, `focus_score`, `text_match`
Independent of the status contract. No change.

## Callers

| Caller | Passes `status=` | Depends on semantics |
|---|---|---|
| `cmd_next` (`brana-cli/commands/backlog.rs`) | `Some("pending")` | Also filters out `blocked`/`parked` post-hoc via `classify()` (new) |
| `cmd_query` (`brana-cli/commands/backlog.rs`) | User input | Raw `task.status` match |
| `cmd_search` (`brana-cli/commands/backlog.rs`) | `None` | N/A |
| `backlog_query` MCP tool (`brana-mcp/tools/backlog_query.rs`) | MCP input | Raw `task.status` match |
| `backlog_search` MCP tool (`brana-mcp/tools/backlog_search.rs`) | `None` | N/A |

## Non-goals

- Exposing synthetic `blocked`/`parked` as first-class filter values. A future `--include-blocked` or `--only-parked` flag could add that explicitly, but that's not this change.
- Changing the `classify()` contract. It stays as the display-level API.
