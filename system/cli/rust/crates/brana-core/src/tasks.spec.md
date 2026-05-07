# tasks.rs — spec

Task: t-1323, t-1340
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

### `compute_stats(tasks, all) -> Value`
Aggregate counts for the `brana backlog stats` CLI and `backlog_stats` MCP tool.

**Output shape:**
```
{
  "total": <usize>,
  "by_status": { <raw status> -> <count> },   // pending, in_progress, completed, cancelled
  "by_state":  { <synthetic state> -> <count> }, // pending, active, blocked, parked, done
  "by_stream":   { <stream> -> { "total": N, <raw status> -> N, "state": { <synthetic> -> N } } },
  "by_priority": { <priority> -> <count> },
  "by_type":     { <type> -> <count> }
}
```

**Contract for `by_status`:** keys are the **raw `task.status` field**. This aligns with the `filter_tasks` predicate (and the CLI `TaskStatus` enum), so a query like `brana backlog query --status completed` returns the count promised by `stats.by_status["completed"]`.

**Contract for `by_state`:** keys are the synthetic display values from `classify()` (`pending`, `active`, `blocked`, `parked`, `done`). This is the rollup view used by themed renderers and the close-session report.

Tasks with no `status` field count as `unknown` in `by_status` (defensive — should never happen for well-formed tasks).

**Rationale:** previously `compute_stats` only emitted `by_status` populated with `classify()` output, diverging from `filter_tasks` semantics. A user reading `stats.by_status["pending"] = 491` could not reproduce that count via `query --status pending` because the stats key was actually `pending` ∪ `blocked` ∪ `parked` minus those classified out. Splitting raw vs. synthetic into two named maps removes the ambiguity.

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
| `cmd_stats` (`brana-cli/commands/backlog.rs`) | — | Calls `compute_stats`; output exposes raw + synthetic |
| `backlog_stats` MCP tool (`brana-mcp/tools/backlog_stats.rs`) | — | Calls `compute_stats`; output exposes raw + synthetic |

### `validate_context_for_effort(effort, context) -> Result<(), String>` (t-939)

Gate: tasks with effort M, L, or XL **must** have a non-empty `context`.

```
effort: Option<&str>   — raw effort string from the task payload
context: Option<&str>  — raw context string from the task payload
```

**Invariants:**
- `None` effort → `Ok(())` (no effort set, no constraint)
- `"XS"` | `"S"` effort → `Ok(())` (small tasks exempt)
- `"M"` | `"L"` | `"XL"` effort + `context` is `None` or empty/whitespace → `Err`
- `"M"` | `"L"` | `"XL"` effort + non-empty `context` → `Ok(())`
- Unknown effort string → `Ok(())` (defensive: don't break on future enum additions)

**Callers:**
| Caller | Wire point |
|---|---|
| `cmd_add` (`brana-cli/commands/backlog.rs`) | After JSON parse, before defaults |
| `backlog_add` MCP tool (`brana-mcp/tools/backlog_add.rs`) | After priority validation |

## Non-goals

- Exposing synthetic `blocked`/`parked` as first-class filter values. A future `--include-blocked` or `--only-parked` flag could add that explicitly, but that's not this change.
- Changing the `classify()` contract. It stays as the display-level API.
