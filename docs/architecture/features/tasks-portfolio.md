# Feature: /brana:tasks portfolio

**Date:** 2026-02-23
**Status:** shipped
**Backlog:** enter #67
**Updated:** 2026-03-09 (t-287: enriched project metadata)

## Goal

Add a `portfolio` subcommand to the `/brana:tasks` skill that shows actionable tasks across all registered clients — answering "what should I work on next?" at a glance.

## Audience

The operator (single user) managing multiple clients via brana's task system.

## Registry Schema

`~/.claude/tasks-portfolio.json` — the canonical project registry.

### Current schema (v2, since t-287)

```json
{
  "clients": [
    {
      "slug": "nexeye",
      "projects": [
        {
          "slug": "eyedetect",
          "path": "~/enter_thebrana/projects/nexeye_eyedetect",
          "type": "hybrid",
          "stage": "growth",
          "tech_stack": ["python", "fastapi", "react", "computer-vision", "docker", "supabase"],
          "created": "2025-12-01"
        }
      ]
    }
  ]
}
```

**Client fields:**
- `slug` (required) — unique client identifier

**Project fields:**
- `slug` (required) — unique project identifier within the client
- `path` (required) — filesystem path (`~/` resolved to `$HOME` at runtime)
- `type` (optional) — `code`, `venture`, or `hybrid`. Detected by `/brana:onboard`.
- `stage` (optional) — `discovery`, `validation`, `growth`, or `scale`. Null for code-only. Advisory — reviewed via `/brana:review monthly`.
- `tech_stack` (optional) — array of technology/domain tags. Named distinctly from task-level `tags`.
- `created` (optional) — date the project was registered.

### Legacy schema (v1, still supported)

```json
{
  "projects": [
    { "slug": "nexeye_eyedetect", "path": "~/enter_thebrana/projects/nexeye_eyedetect" }
  ]
}
```

Legacy entries are treated as single-project clients (client slug = project slug).

### Resolution

```
tasks-portfolio.json
  → if .clients: iterate clients[].projects[]
  → elif .projects: wrap each as single-project client
  → resolve ~/paths to $HOME
  → for each project: read {path}/.claude/tasks.json
```

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

### Multi-project display (v2, t-287)

- **Single-project client**: header shows client slug only (e.g., `nexeye`)
- **Multi-project client**: header shows `client/project` (e.g., `nexeye/eyedetect`)
- **Emoji theme**: type badge after header — `[code]`, `[venture]`, `[hybrid]`
- **Wide mode**: `Project` column always visible
- **Unified view**: prefix with `client/project` when multi-project

### Flags

- `--unified` — priority-sorted cross-client view (default: by-project)
- `--wide` — tabular with all columns including Project

### Summary line

Top line: `Portfolio — {total} tasks across {N} clients ({pending} pending, {in_progress} in progress)`

### Distinction from `/brana:tasks status`

`/brana:tasks status` (no project) = progress bars per project (how far along)
`/brana:tasks portfolio` = individual task list (what to do next)

## Design

### Data flow

```
~/.claude/tasks-portfolio.json
  → resolve schema (v2 nested or v1 legacy)
  → resolve ~/paths to $HOME
  → for each client's project: read {path}/.claude/tasks.json
  → normalize JSON: bare array → wrap as {tasks: [...]}, object → use .tasks
  → inject project metadata (type, stage, tech_stack) from registry
  → for each task: classify status (in_progress, pending-unblocked, blocked, parked, completed)
  → blocked = blocked_by contains any non-completed task id
  → parked = tags array contains "parked"
  → sort within project: in_progress → pending unblocked → blocked → last 3 completed (by date desc)
  → render by-client or unified view (multi-project display when client has 2+ projects)
```

### Files to modify

1. `system/skills/tasks/SKILL.md` — portfolio section + wide-mode template

### Challenger findings (addressed)

- Schema inconsistency: handled via normalize step
- All-completed visibility: collapsed line instead of skip
- Flag complexity: reduced to single --unified flag
- CWD confusion: noted in deferred section, not included
- Per-task `project` field: dropped per challenger review (t-287) — project context injected at read time from registry

## Deferred

- CWD project inclusion (use `/brana:tasks status` for current project). Note: CWD not included unless registered in tasks-portfolio.json under a client.
- Frontmatter config block for parameterizable toggles (enter #69)
- Interactive task selection ("start one?")
- Integration with `/brana:tasks next` (cross-client next)
- Additional flags (--no-blocked, --completed N) — revisit if defaults don't satisfy
- Auto-registration via `/brana:onboard` (t-288)

## Open questions

None — shape and design decisions resolved interactively.
