---
name: backlog
description: "Manage the backlog — plan, track, navigate phases and streams. Use when planning phases, viewing roadmaps, or restructuring work."
effort: medium
model: sonnet
keywords: [tasks, planning, roadmap, milestones, phases, tracking, priority]
task_strategies: [feature, refactor]
stream_affinity: [roadmap, tech-debt]
argument-hint: "[status|add|start|done|next|roadmap|plan|triage|tags|context|theme|sync] [args]"
group: brana
allowed-tools:
  - Read
  - Write
  - Edit
  - Glob
  - Grep
  - Bash
  - AskUserQuestion
  - Task
  - mcp__ruflo__memory_search
  - mcp__ruflo__claims_claim
  - mcp__ruflo__claims_release
  - mcp__ruflo__claims_list
  - mcp__ruflo__agent_spawn
  - mcp__ruflo__swarm_init
  - mcp__ruflo__claims_mark-stealable
  - mcp__ruflo__coordination_orchestrate
  - mcp__ruflo__agent_pool
  - TaskCreate
  - TaskList
  - TaskUpdate
  - ToolSearch
status: stable
growth_stage: evergreen
---

# Backlog

Manage the project backlog — plan, track, and navigate work across phases,
milestones, and streams. Natural language is the primary interface;
these commands are shortcuts for complex operations.

## When to use

When explicitly managing the backlog: planning phases, viewing roadmaps,
restructuring work. Daily task interaction happens through natural
language guided by the task-convention rule — no skill invocation needed.

## CLI Integration — MANDATORY

**NEVER read or write tasks.json directly.**

**Prefer MCP tools** (brana server) when available — structured JSON, 65% fewer tokens:

### Initiative Model (v3)

Tasks have two new optional fields:

| Field | Values | Purpose |
|-------|--------|---------|
| `epic` | slug string (e.g. `"cc-alignment"`) | Groups tasks under a named epic |
| `work_type` | `implement` / `research` / `design` / `infra` / `review` / `chore` | Cognitive mode — what kind of work this is. Note: `kind: refactor` tasks use `work_type: implement`. |

**Active epic** is set in `~/.claude/tasks-config.json` → `active_epic`. When set, `backlog_focus` / `brana backlog focus` shows ★-marked tasks from that epic first, then P0/P1 overflow from others.

**Stream taxonomy** (v3 — 3 values):

| Value | Covers |
|-------|--------|
| `dev` | code, features, bugs, tech-debt, architecture |
| `ops` | maintenance, docs, config, deploy |
| `research` | spikes, evaluations, knowledge, experiments |

### MCP tools (preferred)

| Operation | MCP tool |
|-----------|---------|
| Get task | `backlog_get(task_id: "t-123")` |
| Get field | `backlog_get(task_id: "t-123", field: "status")` |
| Query tasks | `backlog_query(status: "pending", stream: "dev")` or `backlog_query(kind: "fix")` |
| Filter by epic | `backlog_query(epic: "cc-alignment")` |
| Filter by work type | `backlog_query(work_type: "implement", status: "pending")` |
| Multi-tag AND | `backlog_query(tag: "dx,cli")` |
| Filter by parent | `backlog_query(parent: "ph-001", task_type: "task")` |
| Search | `backlog_search(query: "enforcement")` |
| Aggregate stats | `backlog_stats()` |
| Set field | `backlog_set(task_id: "t-123", field: "status", value: "in_progress")` |
| Set epic | `backlog_set(task_id: "t-123", field: "epic", value: "cc-alignment")` |
| Add/remove tag | `backlog_set(task_id: "t-123", field: "tags", value: "+newtag")` |
| Append text | `backlog_set(task_id: "t-123", field: "context", value: "note", append: true)` |
| Create task | `backlog_add(subject: "...", kind: "feature", task_type: "task")` |
| Create with epic | `backlog_add(subject: "...", epic: "cc-alignment", work_type: "implement")` |
| Focus (top tasks) | `backlog_focus(top: 5)` or `backlog_focus(work_type: "research")` |

### CLI fallback (when MCP unavailable)

| Operation | CLI command |
|-----------|------------|
| Project status | `brana backlog status` |
| Cross-client status | `brana backlog status --all --json` |
| Full roadmap tree | `brana backlog roadmap --json` |
| Subtree of phase | `brana backlog tree <id> --json` |
| Aggregate stats | `brana backlog stats` |
| Tag inventory | `brana backlog tags --output json` |
| Tag filter (AND) | `brana backlog tags --filter "a,b" --output json` |
| Next unblocked task | `brana backlog next --kind feature --tag Y` |
| Next by stream | `brana backlog next --stream dev` |
| Query tasks | `brana backlog query --status pending --kind fix --output json` |
| Filter by epic | `brana backlog query --epic cc-alignment` |
| Filter by work type | `brana backlog query --work-type implement --status pending` |
| Multi-tag AND query | `brana backlog query --tag "dx,cli" --count` |
| Filter by parent | `brana backlog query --parent ph-001 --type task` |
| Get full task | `brana backlog get <id>` |
| Get single field | `brana backlog get <id> --field status` |
| Focus (active epic) | `brana backlog focus` |
| Focus by work type | `brana backlog focus --work-type research` |
| Focus override epic | `brana backlog focus --epic cc-alignment` |

### Write operations

| Operation | CLI command |
|-----------|------------|
| Set any field | `brana backlog set <id> <field> <value>` |
| Set epic | `brana backlog set <id> epic cc-alignment` |
| Set work type | `brana backlog set <id> work_type implement` |
| **Set active epic** | `brana backlog set-active <slug>` (per-repo — writes project-local `.claude/tasks-config.json`, t-2155) |
| Set to null | `brana backlog set <id> priority null` |
| Append to text | `brana backlog set <id> context --append "note"` |
| Add/remove tag | `brana backlog set <id> tags +newtag` / `tags -oldtag` |
| Add blocked_by | `brana backlog set <id> blocked_by +t-100` |
| Create task (JSON) | `brana backlog add --json '{"subject":"...","kind":"feature","type":"task"}'` |
| Create task (shorthand) | `brana backlog add --subject "..." --kind feature --type task --tags "a,b" --effort S` |
| Create with epic | `brana backlog add --subject "..." --epic cc-alignment --work-type implement` |
| Create in another project | `brana backlog add --subject "..." --project <slug>` (cross-project via portfolio; default = current project, t-2155) |
| Create initiative | `brana backlog add --subject "..." --kind feature --type initiative` |
| Create task (from file) | `brana backlog add --json @/tmp/task.json` |
| Create task (stdin) | `echo '{"subject":"..."}' \| brana backlog add --json -` |
| Rollup parents | `brana backlog rollup` |

### Rules

1. **Prefer MCP tools** (`backlog_query`, `backlog_get`, `backlog_set`, `backlog_add`, `backlog_search`, `backlog_stats`) when available. Fall back to CLI if MCP server is not running.
2. **Every "Read tasks.json" instruction below → call MCP tool or CLI command.**
3. **Every "Write tasks.json" instruction below → call `backlog_set`/`backlog_add` (MCP) or `brana backlog set`/`brana backlog add` (CLI).**
4. For batch creates (plan command), call `backlog_add` once per task.
5. All operations return JSON. MCP returns structured data natively; CLI returns JSON on stdout.
6. All writes are atomic — no need to read-modify-write.
7. Both MCP and CLI auto-detect tasks.json from git root.


## Phase Protocol — how to execute this skill

The subcommand procedures live in per-phase files under `phases/` (this skill's base directory). **Never execute a subcommand from memory.** Three rules:

1. **On invocation:** parse the subcommand from the arguments, then Read its phase file from the PHASES registry below BEFORE doing any of its work. A phase you have not Read this session does not exist — do not improvise its steps.
2. **When a subcommand chains into another** (e.g. `start` proposing `execute`, `done` after `start`): Read the new subcommand's phase file at that boundary.
3. **On resume after compression:** identify the active subcommand (CC TaskList `/brana:backlog — {STEP}` entries, or the conversation), then Read its phase file before continuing. Previously loaded phase content did NOT survive compression.

<!-- PHASES -->
| Subcommand(s) | File | Load when |
|------|------|-----------|
| plan | phases/plan.md | `/brana:backlog plan` invoked |
| status, roadmap, next | phases/views.md | Any view subcommand invoked |
| start (+ `/brana:do` freeform routing) | phases/start.md | `/brana:backlog start` or `/brana:do` invoked |
| done, add, replan, archive, migrate | phases/done-and-add.md | Any of these subcommands invoked |
| tags, context, theme | phases/tags-context-theme.md | Any of these subcommands invoked |
| execute | phases/execute.md | `/brana:backlog execute` invoked |
| triage, sync | phases/triage-sync.md | Either subcommand invoked |
| Display themes + task-line/wide templates | phases/display-themes.md | Before rendering any themed view (status, roadmap, next, tags) |
<!-- /PHASES -->

In the deployed-plugin layout the same relative paths apply: `{base-dir}/phases/{file}`. If a path doesn't resolve, use Glob: `**/skills/backlog/phases/{file}`.

## Commands

- `/brana:backlog plan [project] "[phase-title]"` — plan a phase interactively
- `/brana:backlog status [project] [--all] [--unified] [--wide]` — progress overview (`--all` = cross-client task drill-down, `--unified` = priority-sorted flat list)
- `/brana:backlog roadmap [project] [--wide]` — full tree view with all levels
- `/brana:backlog next [project] [--stream X] [--wide]` — next unblocked task by priority
- `/brana:backlog start <id>` — begin work on a task
- `/brana:backlog done [id]` — complete current task
- `/brana:backlog add "[description]"` — quick-add a task
- `/brana:backlog replan [project] [phase-id]` — restructure a phase
- `/brana:backlog archive [project]` — move completed phases to archive
- `/brana:backlog migrate <file>` — import tasks from a markdown backlog
- `/brana:backlog execute [scope] [--dry-run] [--max-parallel N] [--retry]` — execute tasks via subagents
- `/brana:backlog tags [project]` — tag inventory, filtering, and bulk tag management
- `/brana:backlog context <id> [text]` — view or set rich context on a task
- `/brana:backlog theme [name]` — view or set display theme (classic, emoji, minimal)
- `/brana:backlog triage [project] [--reresearch] [--scope P2+]` — research-informed priority reassessment
- `/brana:backlog sync [--dry-run] [--force]` — sync tasks.json with GitHub Issues

---

## Step Registry (plan and execute subcommands)

For the `plan` and `execute` subcommands, create a CC Task step registry on entry. Follow the [guided-execution protocol](../_shared/guided-execution.md). Other subcommands (status, roadmap, next, add, etc.) are single-step and don't need a registry.

**plan steps:** DETECT, READ, MILESTONES, TASKS, DEPS, PROPOSE, CHALLENGE, WRITE
**execute steps:** READ, FILTER, WAVES, CONFIRM, EXECUTE, WRITEBACK, REPORT

### Resume After Compression

If context was compressed during a plan or execute flow:

1. Call `TaskList` — find CC Tasks matching `/brana:backlog — {STEP}`
2. The `in_progress` task is your current step — resume from there

---

## Field Notes

### 2026-06-10: `deleted` is not a valid task status — use `cancelled`
`brana backlog set <id> status deleted` returns `{"ok":false,"error":"invalid status \"deleted\" — must be pending/in_progress/completed/cancelled or null"}`. The correct status for superseded, extracted, or migrated tasks is `cancelled`. When marking tasks cancelled, add a context note explaining why: `brana backlog set <id> context --append "[t-NNN] cancelled: moved to clients/proyecto-anita/..."`. There is no `deleted` status in the CLI schema (E2026-06-10-6).
Source: t-1950 client migration 2026-06-10

