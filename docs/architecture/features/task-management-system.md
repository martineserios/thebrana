---
depends_on:
  - docs/architecture/decisions/ADR-002-tasks-as-data-layer.md
  - docs/architecture/decisions/ADR-003-agent-driven-task-execution.md
informs:
  - docs/architecture/features/cli-composable-tool.md
  - docs/architecture/features/smart-tasks-add.md
  - docs/architecture/features/tasks-portfolio.md
  - docs/architecture/features/github-issues-sync.md
  - docs/architecture/features/research-stream.md
---
# Feature: Task Management System

**Date:** 2026-02-18
**Status:** building

## Goal

A project planning and task management system that uses JSON files as the data layer, Claude Code as the NL interface, and hooks for enforcement — enabling hierarchical task tracking (phase > milestone > task) with branch integration, multi-stream support, and passive visibility via the status line.

## Audience

Solo developer managing 3-5 projects across code and non-code work.

## Constraints

- Claude Code subscription only — zero external API calls
- Must work for code projects (git, branches, PRs) and non-code (venture, ops)
- Convention rule budget ~80 lines (total rules budget ~23KB)
- No custom MCP servers or external services
- Git-discipline compliance (branches, worktrees, conventional commits)

## Scope (v1)

- tasks.json schema with hierarchy, streams, execution modes
- Convention rule for NL interaction (reads free, writes confirmed)
- /brana:backlog skill with 13 subcommands (v1: 10, v1.1: +execute, +tags, +context)
- PostToolUse hook: JSON validation + parent rollup
- Session start: task context injection
- Status line: phase progress, current task, bug count
- Morning + weekly-review task awareness
- Feature brief + ADR

## v2 Design: Agent Execution

See ADR-003 for agent-driven task execution — subagent spawning per task, DAG-aware wave parallelism, compose-then-write for code tasks.

## Deferred

- GitHub Issues sync (/brana:backlog sync)
- Markdown rendering (/brana:backlog render > roadmap.md)
- Time tracking (estimated vs actual)
- Recurring tasks
- Cross-project dependencies
- Task templates

## Research findings

- Native Claude Code Tasks: session-scoped, metadata doesn't query, insufficient for PM
- ruflo tasks: agent coordination tool, 4 fixed types, no hierarchy
- Agent SDK: execution layer, requires API key, doesn't solve data persistence
- JSON files: full control, no N+1, git-tracked, zero dependencies

## Design

See ADR-002 for architecture decision. Key components:
1. tasks.json per project (.claude/tasks.json)
2. Convention rule (~80 lines, teaches Claude schema + NL behavior)
3. /brana:backlog skill (13 subcommands: plan, status, roadmap, next, start, done, add, replan, archive, migrate, execute, tags, context)
4. PostToolUse hook (validation + rollup — deterministic enforcement)
5. Session start + status line integration (passive visibility)

## v3 Design: Initiative Model

**Context:** 1488 tasks across 20 files with no active-initiative concept, 49% null priorities, 11 overlapping streams, and a focus score that rewarded staleness over direction.

### Fields added

| Field | Type | Notes |
|-------|------|-------|
| `initiative` | string (slug) | Optional. Groups tasks by named initiative: "cc-alignment", "notebooklm", etc. |
| `work_type` | enum | Optional. Cognitive mode: `implement` / `research` / `design` / `ops` / `review` |

### Fields removed

| Field | Reason |
|-------|--------|
| `build_step` | Null on >95% of tasks. Intent absorbed into `context`. |
| `strategy` | Null on >95% of tasks. Replaced by `work_type`. |
| `execution` | Null on >95% of tasks. `execution=manual` → `work_type=ops`. |

### Active initiative config

`~/.claude/tasks-config.json` gains an `active_initiative` field:
```json
{ "active_initiative": "cc-alignment", "theme": "emoji" }
```

Set with: `brana backlog set active <slug>`

### Focus score rewrite

```
OLD: priority_weight + (days_since_created × 2) − effort_penalty − (blocked_depth × 50)
NEW: initiative_boost + priority_weight − effort_penalty − (blocked_depth × 50)
     initiative_boost = +500 if task.initiative == active_initiative, else 0
```

Staleness removed — it was rewarding neglect over direction.

### Work type definitions

| Value | When to use |
|-------|-------------|
| `implement` | Write code, build features, fix bugs |
| `research` | Spike, evaluate, audit, investigate |
| `design` | Architecture, schemas, decisions |
| `ops` | Deploy, config, setup, run, sync |
| `review` | PR review, audit, feedback |

### Stream taxonomy (11 → 3)

| New | Maps from |
|-----|-----------|
| `dev` | roadmap, architecture, bugs, tech-debt, dx, (null) |
| `ops` | maintenance, docs |
| `research` | research, experiments, knowledge |

`stream=personal` tasks extracted to `personal/.claude/tasks.json`.

### Migration

Five idempotent scripts in `system/scripts/migrate/`:
1. `extract-personal.py` — moves `stream=personal` tasks to personal backlog
2. `null-to-p3.py` — floors all pending null-priority tasks at P3
3. `remap-streams.py` — maps old stream values to new 3-value taxonomy
4. `drop-deprecated-fields.py` — removes build_step/strategy/execution; infers work_type=ops from execution=manual
5. `infer-work-type.py` — heuristically fills work_type from subject patterns and stream
