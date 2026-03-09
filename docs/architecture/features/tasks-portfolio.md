# Feature: /brana:tasks portfolio

**Date:** 2026-02-23
**Status:** shipped
**Backlog:** enter #67

## Goal

Add a `portfolio` subcommand to the `/brana:tasks` skill that shows actionable tasks across all registered clients — answering "what should I work on next?" at a glance.

## Audience

The operator (single user) managing multiple clients via brana's task system.

## Constraints

- Read-only — no task mutations, just a view
- Reads from `~/.claude/tasks-portfolio.json` (registered clients only, not CWD)
- Paths use `~/` prefix — resolve to `$HOME` at runtime
- Must handle missing tasks.json gracefully (skip silently)
- Must handle all-completed projects (show collapsed line, not skip)
- Must handle both JSON shapes: bare `[{...}]` array and `{"tasks": [...]}` wrapper
- Skill is a SKILL.md section (instructions, not code)

## Scope (v1)

### Two view modes

**By client** (default): grouped by client, each showing:
- In-progress tasks (← icon)
- Pending unblocked tasks (→ icon)
- Blocked tasks (· icon, with "blocked by" indicator)
- Parked tasks flagged with `[parked]` (detected via tags containing "parked")
- Last 3 completed tasks (✓ icon, with completion date)
- All-completed clients shown as collapsed line: `{slug}  all done ({N} tasks)`

**Unified priority** (`--unified`): flat list sorted by priority across all clients, prefixed with client slug. Sort order: P0 > P1 > P2 > null. Ties broken by: in_progress first, then pending, then order field.

### Flags

- `--unified` — priority-sorted cross-client view (default: by-project)

Other options baked in as sensible defaults (no flags):
- Blocked tasks: always shown
- Last 3 completed: always shown
- Parked detection: always on

### Summary line

Top line: `Portfolio — {total} tasks across {N} clients ({pending} pending, {in_progress} in progress)`

### Distinction from `/brana:tasks status`

`/brana:tasks status` (no project) = progress bars per project (how far along)
`/brana:tasks portfolio` = individual task list (what to do next)

## Design

### Data flow

```
~/.claude/tasks-portfolio.json
  → resolve ~/paths to $HOME
  → for each client's project: read {path}/.claude/tasks.json
  → normalize JSON: bare array → wrap as {tasks: [...]}, object → use .tasks
  → for each task: classify status (in_progress, pending-unblocked, blocked, parked, completed)
  → blocked = blocked_by contains any non-completed task id
  → parked = tags array contains "parked"
  → sort within project: in_progress → pending unblocked → blocked → last 3 completed (by date desc)
  → render by-client or unified view
```

### Files to modify

1. `system/skills/tasks/SKILL.md` — add command to table + new section

### Challenger findings (addressed)

- Schema inconsistency: handled via normalize step
- All-completed visibility: collapsed line instead of skip
- Flag complexity: reduced to single --unified flag
- CWD confusion: noted in deferred section, not included

## Deferred

- CWD project inclusion (use `/brana:tasks status` for current project). Note: CWD not included unless registered in tasks-portfolio.json under a client.
- Frontmatter config block for parameterizable toggles (enter #69)
- Interactive task selection ("start one?")
- Integration with `/brana:tasks next` (cross-client next)
- Additional flags (--no-blocked, --completed N) — revisit if defaults don't satisfy

## Open questions

None — shape and design decisions resolved interactively.
