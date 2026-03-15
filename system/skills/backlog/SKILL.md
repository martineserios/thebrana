---
name: backlog
description: "Manage the backlog — plan, track, navigate phases and streams. Use when planning phases, viewing roadmaps, or restructuring work."
argument-hint: "[status|add|start|done|next|roadmap|plan|triage|tags|context|theme|sync] [args]"
group: brana
allowed-tools:
  - Read
  - Write
  - Glob
  - Grep
  - Bash
  - AskUserQuestion
  - Task
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

**NEVER read or write tasks.json directly.** Use the `brana` CLI via the Bash tool for ALL task operations.
The binary is at `system/cli/rust/target/release/brana` (from git root) or
`${CLAUDE_PLUGIN_ROOT}/cli/rust/target/release/brana`.

### Read operations

| Operation | CLI command |
|-----------|------------|
| Project status | `brana backlog status` |
| Cross-client status | `brana backlog status --all --json` |
| Full roadmap tree | `brana backlog roadmap --json` |
| Subtree of phase | `brana backlog tree <id> --json` |
| Aggregate stats | `brana backlog stats` |
| Tag inventory | `brana backlog tags --output json` |
| Tag filter (AND) | `brana backlog tags --filter "a,b" --output json` |
| Next unblocked task | `brana backlog next --stream X --tag Y` |
| Query tasks | `brana backlog query --status pending --stream bugs --output json` |
| Multi-tag AND query | `brana backlog query --tag "dx,cli" --count` |
| Filter by parent | `brana backlog query --parent ph-001 --type task` |
| Get full task | `brana backlog get <id>` |
| Get single field | `brana backlog get <id> --field status` |

### Write operations

| Operation | CLI command |
|-----------|------------|
| Set any field | `brana backlog set <id> <field> <value>` |
| Set to null | `brana backlog set <id> priority null` |
| Append to text | `brana backlog set <id> context --append "note"` |
| Add/remove tag | `brana backlog set <id> tags +newtag` / `tags -oldtag` |
| Add blocked_by | `brana backlog set <id> blocked_by +t-100` |
| Create task | `brana backlog add --json '{"subject":"...","stream":"...","type":"task"}'` |
| Rollup parents | `brana backlog rollup` |

### Rules

1. **Every "Read tasks.json" instruction below → call the corresponding CLI command.**
2. **Every "Write tasks.json" instruction below → call `brana backlog set` or `brana backlog add`.**
3. For batch creates (plan command), call `brana backlog add` once per task.
4. All CLI commands return JSON on stdout. Parse with `jq` if needed.
5. All writes are atomic — no need to read-modify-write.
6. CLI auto-detects tasks.json from git root. No path argument needed.

## Display Themes

All rendering sections below use the **task-line template** to determine icons,
progress bars, and decorations. Resolve the active theme before rendering:

1. If `--theme <name>` flag is on the command, use it
2. Else read `~/.claude/tasks-config.json` → `{"theme": "<name>"}`
3. Else default to `classic`

### Task-line template

```
classic:   {icon} {id}  {subject}  {detail}
           ✓ done  ← active  → pending  · blocked  · parked
           bars: ████░░░░  {done}/{total}

emoji:     {icon} {id}  {subject}  {detail}
           ✅ done  🔨 active  🔲 pending  🔒 blocked  💤 parked
           bars: ████░░░░  {done}/{total}
           project header: 📋 {name}
           status --all header: boxed ╭╮╰╯ with 📊
           priority high: ⚡high
           blocked ref: ⛓ {id}
           health dots: 🟢 done  🟡 active  🔴 blocked

minimal:   {icon} {id}  {subject}  {detail}
           ● done  ◐ active  ○ pending  ⊘ blocked  ◌ parked
           bars: ━━━━╍╍╍╍  {done}/{total}
           blocked ref: ← {id}
```

### Wide mode (`--wide`)

Any view command (`status`, `roadmap`, `next`, `tags --filter`) accepts `--wide`.
Wide mode renders tasks as **tabular rows** with all metadata visible on one line — like `kubectl get pods -o wide`.
Wide mode composes with any theme (icons come from the active theme).

**Wide-mode template:**

```
Columns:  {icon} {id}  {subject}  {status}  {tags}  {pri}  {eff}  {stream}  {project}  {blocked_by}  {started}  {completed}

Header row (always shown):
  ID       Subject                         Status    Tags              Pri  Eff  Stream   Project      Blocked     Started     Done

Task rows (classic icons):
  ✓ t-007  Design auth flow                done      auth              P1   S    roadmap  —           2026-02-10  2026-02-12
  → t-008  Implement JWT middleware         pending   auth, quick-win   P1   S    roadmap  —           —           —
  · t-009  Write auth tests                blocked   auth              P1   M    roadmap  t-008       —           —

Task rows (emoji icons):
  ✅ t-007  Design auth flow                done      auth              P1   S    roadmap  —           2026-02-10  2026-02-12
  🔲 t-008  Implement JWT middleware         pending   auth, quick-win   P1   S    roadmap  —           —           —
  🔒 t-009  Write auth tests                blocked   auth              ⛓ t-008

Task rows (minimal icons):
  ● t-007  Design auth flow                done      auth              P1   S    roadmap  —           2026-02-10  2026-02-12
  ○ t-008  Implement JWT middleware         pending   auth, quick-win   P1   S    roadmap  —           —           —
  ⊘ t-009  Write auth tests                blocked   auth              P1   M    roadmap  ← t-008     —           —
```

**Rules:**
- `subject` gets remaining width after fixed columns; truncate with `…` if too long
- `tags` shows first 3 comma-separated, then `+N` if more
- Null fields render as `—` (em-dash), never blank
- `project` column: in cross-client views (`--all`), shows `client/project` for multi-project clients, client slug for single-project. In single-project views, shows project slug from tasks.json root or `—`
- Phases/milestones render as **section headers** (bold subject + progress bar, no per-column detail):
  ```
  ph-002  Phase 2: API Foundation                                        ████░░░░ 3/8
    ✓ t-007  Design auth flow              done      auth              P1   S    roadmap  —           2026-02-10  2026-02-12
    → t-008  Implement JWT middleware       pending   auth, quick-win   P1   S    roadmap  —           —           —
  ```
- Without `--wide`, all views use the compact tree layout (unchanged default behavior)

### Tree connectors (all themes)

Hierarchy views (status, roadmap) use box-drawing characters when not in `--wide` mode:

```
├── child (has siblings after)
└── child (last sibling)
│   continuation line
```

---

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

**plan steps:** DETECT, READ, MILESTONES, TASKS, DEPS, PROPOSE, WRITE
**execute steps:** READ, FILTER, WAVES, CONFIRM, EXECUTE, WRITEBACK, REPORT

### Resume After Compression

If context was compressed during a plan or execute flow:

1. Call `TaskList` — find CC Tasks matching `/brana:backlog — {STEP}`
2. The `in_progress` task is your current step — resume from there

---

## /brana:backlog plan

Interactive phase planning. Builds the hierarchy conversationally.

### Steps

1. **Detect project** from CWD (git root -> basename) or argument
2. **Read tasks.json** — if it doesn't exist, create with empty tasks array
3. **If phase title provided**, use it. Otherwise ask: "What phase are you planning?"
4. **Create the phase task** (type: phase) with next available ph-N id
5. **Ask for milestones:** "What are the key milestones in this phase?"
6. **For each milestone**, ask: "Break down {milestone} into tasks?"
   - If yes: ask for tasks, create with parent -> milestone id
   - If no: create milestone only, tasks deferred
7. **Ask about dependencies:** "Any tasks that block others?"
8. **Propose the full tree** formatted as a roadmap view
9. **Offer bulk tags:** "Tag all tasks in this phase? (comma-separated, or skip)" — applies tags to every task in the phase
10. **Wait for approval** — user can adjust before writing
11. **Write tasks.json** — one Write for the entire batch
12. **Report:** show the tree with IDs and tags for reference

### Defaults
- Stream: roadmap (unless user specifies otherwise)
- Execution: code (if project has .git), manual (otherwise)
- Priority/effort: null (user provides later if needed)
- Status: pending for all new tasks

---

## /brana:backlog status

High-level progress view with aggregation. Use `--all` for cross-client task-level drill-down.

**Delegate entirely to CLI. Do not read tasks.json or compute anything manually.**

### Steps

1. Run `brana backlog status` — outputs themed project status (progress bar, counts)
2. Run `brana backlog stats` — outputs JSON aggregate stats (by_status, by_stream, by_priority, by_type)
3. Run `brana backlog next` — outputs themed next-up list (top 3 by priority)
4. Present the CLI output directly to the user. Do not reformat or recompute.

### Cross-client view (`--all`)

Run `brana backlog status --all` — CLI handles portfolio aggregation, theming, and rendering.

For JSON output (when you need to process data): `brana backlog status --all --json`

### Additional detail (optional, only if user asks)

- Blocked chains: `brana backlog blocked`
- Stream breakdown: already in `brana backlog stats` output
- Phase tree: `brana backlog roadmap`
- Specific phase subtree: `brana backlog tree <phase-id>`

---

## /brana:backlog roadmap

Full tree view — every level expanded.

**Delegate entirely to CLI. Do not read tasks.json or build trees manually.**

### Steps

1. Run `brana backlog roadmap` — outputs themed full tree (phases -> milestones -> tasks with icons, progress bars, blocked indicators)
2. Present the CLI output directly to the user. Do not reformat.

For JSON output: `brana backlog roadmap --json`
For a subtree: `brana backlog tree <phase-or-milestone-id>`

---

## /brana:backlog next

Find the highest-priority unblocked task.

**Delegate entirely to CLI.**

### Steps

1. Run `brana backlog next` — outputs themed top-3 list sorted by priority
2. Present the CLI output directly.

Optional filters (pass through to CLI):
- By tag: `brana backlog next --tag scheduler`
- By stream: `brana backlog next --stream research`

---

## /brana:backlog start

Begin work on a specific task. For code tasks, enters the `/brana:build` loop.

### Steps

1. **Parse id** from argument, or offer candidates from /brana:backlog next
2. **Read tasks.json**, find the task
3. **Check blocked_by** — if any blocker not completed, warn and abort
4. **Auto-classify strategy** (if not already set on the task):
   - Infer from task tags, stream, and description:
     - `stream: bugs` or tag `bug` → strategy: `bug-fix`
     - `stream: research` → strategy: `spike`
     - `stream: tech-debt` or tag `refactor` → strategy: `refactor`
     - `stream: docs` → strategy: `feature` (light)
     - Tag `migration` → strategy: `migration`
     - Tag `investigation` → strategy: `investigation`
     - Default → strategy: `feature`
   - **Confirm with user:** "Start t-008 as **feature**? [feature / bug-fix / refactor / spike / other]"
   - Write the confirmed `strategy` field to the task
5. **Determine execution mode:**
   - `code`: check git status clean → create branch `{prefix}{id}-{slug}` → set status + started date + branch field → **enter `/brana:build` with the task's strategy** (build_step: classify)
   - `external`: set status + started date, show task description
   - `manual`: set status + started date, show checklist from description
6. **Write tasks.json** (status: in_progress, started: today, strategy: confirmed)
7. **GitHub sync** (if `github_sync.enabled` in `~/.claude/tasks-config.json`):
   - If task has no `github_issue`: run `system/scripts/gh-sync.sh create {task-id} {tasks-json-path}`. Read issue number from stdout, write to task's `github_issue` field.
   - If task has `github_issue`: run `system/scripts/gh-sync.sh pull-context {issue-number}`. If comments returned, replace `## GitHub Comments` section in task's `context` field.
   - If sync fails (exit code 1 or 2): warn "GitHub sync failed. Task started locally." — do NOT block start.
8. **Report:** "Started t-008 'Implement JWT middleware' as **feature**. Branch: feat/t-008-jwt-middleware."
9. **For code tasks:** proceed directly into `/brana:build` — no separate invocation needed

### Branch creation

```bash
# Check for existing branch
git branch --list "feat/t-008-*" 2>/dev/null
# If exists: "Branch already exists. Resume?" -> checkout
# If not: create new
git checkout -b feat/t-008-jwt-middleware
```

Integrate with worktree pattern if on a different branch:
```bash
git worktree add ../project-feat-t-008 -b feat/t-008-jwt-middleware
```

---

## /brana:backlog done

Complete the current task. For code tasks that went through `/brana:build`, the CLOSE step already handles completion — use `/brana:backlog done` only for manual and external tasks.

### Steps

1. **Identify task:**
   - If id provided, use it
   - If on a task branch (feat/t-NNN-*), extract id from branch name
   - Otherwise: show in_progress tasks, ask which one
2. **Read tasks.json**, find the task
3. **Check if build-managed:** if the task has a `build_step` field set, warn: "This task is in the /brana:build loop (step: {build_step}). Use /brana:build CLOSE to complete it, or force-complete here?"
4. **For execution: code** (non-build-managed):
   - Stage changes: `git add -A` (or ask user what to stage)
   - Commit with conventional type from stream mapping
   - Create PR: `gh pr create --title "{type}: {subject}" --body "Closes #{github_issue}"`
   - Offer to merge: "Merge to main? (PR #{N})"
   - **Worktree cleanup:** if task was started in a worktree (`git worktree list` shows `../project-{prefix}{id}`), offer to remove it after merge: `git worktree remove ../project-{prefix}{id} && git branch -d {branch}`
5. **For execution: external/manual:**
   - Ask: "Any notes on the outcome?"
   - Record in task.notes
   - **Doc prompt:** if the task produced user-visible deliverables (check: tags contain `docs`, `feature`, `workflow`, `skill`, or description mentions "build", "create", "launch", "design"), ask via AskUserQuestion:
     ```
     question: "This task produced deliverables. Generate documentation?"
     options:
       - "Tech doc + user guide" (writes both from templates)
       - "Tech doc only"
       - "User guide only"
       - "Skip docs"
     ```
     If user selects any doc option, generate using templates at `system/skills/build/templates/tech-doc.md` and/or `system/skills/build/templates/user-guide.md`. Output to `docs/architecture/features/{task-slug}.md` and/or `docs/guide/features/{task-slug}.md`.
6. **Update task:** status → completed, completed → today's date, clear build_step
7. **Write tasks.json** — hook handles rollup + validation
8. **GitHub sync** (if `github_sync.enabled` in `~/.claude/tasks-config.json`):
   - If task has `github_issue`: run `system/scripts/gh-sync.sh close {issue-number}`.
   - If sync fails: warn "GitHub issue not closed. Close manually: gh issue close #{issue-number}" — do NOT block done.
9. **Report:** "Completed t-008. Milestone 'Auth System': 2/3 done."

---

## /brana:backlog add

Quick-add a single task with intelligent suggestions.

### Steps

All interactive confirmations use the **AskUserQuestion** tool for a selectable UI experience. Batch independent questions into a single AskUserQuestion call (up to 4 questions per call).

1. **Parse description** from argument. If no description provided: scan recent conversation turns for actionable items — problems discussed, ideas proposed, improvements suggested, or work identified. Draft a subject + description from the strongest candidate and present it: "Add task: '{subject}'? [Confirm / Edit / Cancel]". If no actionable item found in conversation, ask for a description.
2. Read tasks.json (all pending tasks, active milestones, tag vocabulary)
3. **URL auto-detection:** if the description contains `https://`, suggest `stream: research`, auto-extract the URL to the `context` field (format: `URL: {url}`), and skip the milestone/stream prompt.
4. **First question batch** — use a single AskUserQuestion with up to 4 questions:
   - **Stream** (skip if URL auto-detected): options from active streams, recommended first. Header: "Stream"
   - **Tags**: suggest tags from description keywords matched against existing vocabulary. Options: "Accept {suggested}" (recommended), "Edit", "Skip". Header: "Tags"
   - **Effort**: suggest from description complexity (S/M/L/XL). Options: each size with description. Header: "Effort"
   - **Milestone** (skip if URL auto-detected or no active milestones): options from active milestones + "None". Header: "Milestone"
5. Auto-assign next id, set defaults. Auto-classify `strategy` from description/stream/tags (same heuristic as `/brana:backlog start`). Leave `build_step` null.
6. **Dependency scan** — cross-reference all pending tasks:
   - Match by **tag overlap** (2+ shared tags with the new task)
   - Match by **subject keyword** overlap (significant words from description appear in existing task subjects)
   - If candidates found, present via AskUserQuestion (multiSelect: true):
     ```
     question: "Link any as blocked_by?"
     options: one per candidate task ("{id} {subject} (reason)")
     ```
   - If no candidates found, skip silently
   - **Never auto-commit dependencies** — always ask
   - **Research cross-reference** (runs alongside dependency scan):
     - Adding a **non-research** task → scan research stream for tag overlap → include in dependency question or separate AskUserQuestion
     - Adding a **research** task → scan non-research tasks for tag overlap → surface as informational note
7. **Build-trap check** — if the description contains solution verbs ("build", "implement", "create", "add", "setup") without outcome/problem context:
   - AskUserQuestion: "This looks like a solution. What problem does it solve?" Options: user provides context via "Other" free text, or "Skip". Header: "Problem"
   - If the user provides text, store it in the `context` field
   - If skipped, proceed without context
8. Priority: **leave null** (user sets manually via `/brana:backlog triage` or direct edit)
9. **Final confirmation** — AskUserQuestion: "Add {id} '{subject}' [{tags}, {effort}] under {milestone}? blocked_by: [{deps}]" Options: "Confirm" (recommended), "Edit", "Cancel". Header: "Confirm"
10. Write tasks.json
11. **GitHub sync** (if `github_sync.enabled` in `~/.claude/tasks-config.json`):
    - Run `system/scripts/gh-sync.sh create {task-id} {tasks-json-path}`. Read issue number from stdout, write to task's `github_issue` field.
    - If sync fails: warn "GitHub issue not created. Run `/brana:backlog sync` later." — do NOT block add.

---

## /brana:backlog replan

Restructure an existing phase.

### Steps

1. Read tasks.json, show current tree for the phase
2. Interactive: "What changes? (add tasks, reorder, move, remove)"
3. Propose updated structure
4. Confirm before writing
5. Handle orphan prevention: if removing a milestone, reassign or remove its children

---

## /brana:backlog archive

Move completed phases to archive.

### Steps

1. Read tasks.json
2. Find phases with status: completed
3. Show: "Archive these completed phases? [list]"
4. Move subtrees to tasks-archive.json (create if doesn't exist)
5. Remove from tasks.json
6. Update next_id counters (don't reset — IDs are never reused)
7. Report: "Archived {N} phases ({M} tasks). Active file: {remaining} tasks."

---

## /brana:backlog migrate

Import tasks from an existing markdown backlog.

### Steps

1. Read the markdown file
2. Parse structure: headings -> phases/milestones, checkboxes -> tasks
3. Propose tasks.json structure with assigned IDs
4. Wait for approval — user adjusts mapping
5. Write tasks.json
6. Report: "Imported {N} tasks from {file}."

---

## /brana:backlog tags

Tag inventory, filtering, and bulk tag management.

### Usage

```
/brana:backlog tags [project]                    — tag inventory (all tags + task counts)
/brana:backlog tags --filter "tag1,tag2"         — AND filter (tasks with ALL listed tags)
/brana:backlog tags --any "tag1,tag2"            — OR filter (tasks with ANY listed tag)
/brana:backlog tags add <id|ids> "tag1,tag2"     — add tags to one or more tasks
/brana:backlog tags remove <id|ids> "tag1"       — remove a tag from one or more tasks
```

### Steps

**Inventory (no subcommand):**
1. **Resolve active theme** (see Display Themes)
2. Read tasks.json
3. Collect all unique tags across all tasks
4. Count tasks per tag (include status breakdown)
5. Render:

```
Tags in {project}:

  scheduler     4 tasks  (2 pending, 1 in_progress, 1 completed)
  quick-win     3 tasks  (3 pending)
  research      2 tasks  (1 in_progress, 1 completed)
  auth          2 tasks  (2 pending)
```

**Filter (`--filter` or `--any`):**
1. Read tasks.json
2. `--filter`: keep tasks where tags array contains ALL specified tags (AND)
3. `--any`: keep tasks where tags array contains ANY specified tag (OR)
4. **If `--wide`**, render using **wide-mode template** (all columns). Otherwise render using task-line template — flat list with status and tags:

```
Tasks tagged [scheduler]:
  → t-008 Implement JWT middleware [scheduler, auth]     pending
  · t-012 Seed dev data [scheduler]                      blocked
  ← t-018 Deploy scheduler config [scheduler, quick-win] in_progress
  ✓ t-021 Scheduler v2 research [scheduler, research]    completed
```

Icons come from active theme (example above uses classic).

**Add tags:**
1. Parse task id(s) — comma-separated or space-separated
2. Parse tags — comma-separated quoted string
3. Read tasks.json, find tasks
4. Append new tags (deduplicate, preserve existing)
5. Confirm: "Add tags [scheduler, auth] to t-008, t-009?"
6. Write tasks.json

**Remove tags:**
1. Parse task id(s) and tag to remove
2. Read tasks.json, filter out the tag from each task's tags array
3. Confirm: "Remove tag 'scheduler' from t-008, t-009?"
4. Write tasks.json

---

## /brana:backlog context

View or set rich context on a task — rationale, links, notes, decisions.

### Usage

```
/brana:backlog context <id>                     — show context for a task
/brana:backlog context <id> "context text"      — set context (replaces existing)
/brana:backlog context <id> --append "note"     — append to existing context
```

### Steps

**View (no text):**
1. Read tasks.json, find task by id
2. If context is null/empty: "No context set for {id}. Add some?"
3. If context exists: display it with task subject as header

```
t-008 Implement JWT middleware

Context:
  Rationale: chose JWT over session cookies for stateless API. See ADR-005.
  Key constraint: tokens must expire in 15min, refresh tokens in 7d.
  Related: t-009 (tests), ms-003 (parent milestone).
```

**Set (with text):**
1. Read tasks.json, find task
2. Replace context field with provided text
3. Confirm: "Set context on t-008?"
4. Write tasks.json

**Append (`--append`):**
1. Read tasks.json, find task
2. If context is null, set to the appended text
3. If context exists, append with newline separator
4. Confirm: "Append to t-008 context?"
5. Write tasks.json

---

## /brana:backlog theme

View or set the display theme.

### Usage

```
/brana:backlog theme              — show current theme
/brana:backlog theme emoji        — set theme to emoji
/brana:backlog theme classic      — set theme to classic
/brana:backlog theme minimal      — set theme to minimal
```

### Steps

**View (no argument):**
1. Read `~/.claude/tasks-config.json`
2. If file exists and has `theme` field, show: "Current theme: **{name}**"
3. If no file: "Current theme: **classic** (default). Set with `/brana:backlog theme <name>`."

**Set (with name):**
1. Validate name is one of: `classic`, `emoji`, `minimal`
2. Read `~/.claude/tasks-config.json` (create if missing)
3. Set `theme` field to the given name, preserve other fields
4. Write the file
5. Report: "Theme set to **{name}**. All `/brana:backlog` output will use {name} icons."

### Config format

```json
{
  "theme": "emoji"
}
```

Stored at `~/.claude/tasks-config.json` (global, not per-project).

---

## /brana:backlog execute

Execute tasks via subagents — DAG-aware parallel execution with automatic wave scheduling.

```
/brana:backlog execute [scope] [--dry-run] [--max-parallel N] [--retry]
```

**Arguments:**
- `scope`: task/milestone/phase ID, or `"next"` for the next unblocked wave. Default: next
- `--dry-run`: show execution plan without running agents
- `--max-parallel N`: max concurrent subagents per wave (default: 3)
- `--retry`: re-run failed/partial tasks, skip completed

### Prerequisites

Tasks must have `spawn` field set (see ADR-003 for schema). Tasks without `spawn` are skipped with a message: "no tasks configured for agent execution."

### Steps

1. **Read tasks.json**, identify scope
2. **Filter executable tasks** — only tasks with `spawn: "subagent"` and status `pending` (or `in_progress`/failed for `--retry`)
3. **Build execution waves** from `blocked_by` DAG (topological sort):
   - Wave 1: tasks with no unmet dependencies
   - Wave 2: tasks whose blockers are all in wave 1
   - Wave N: tasks whose blockers are all in earlier waves
4. **Check parent `spawn_strategy`** — if set, override wave ordering:
   - `"parallel"`: all children in one wave (ignore inter-child deps)
   - `"sequential"`: one task per wave, in order
   - `"auto"`: use DAG (default behavior)
5. **Present execution plan:**
   ```
   Execution plan for ph-002 (3 waves, 8 tasks):

     Wave 1 (parallel):
       t-007 Design auth flow          haiku   research
       t-010 Design schema             haiku   research

     Wave 2 (parallel):
       t-008 Implement JWT middleware   sonnet  code
       t-011 Write migrations           sonnet  code

     Wave 3 (parallel):
       t-009 Write auth tests           sonnet  code
       t-012 Seed dev data              sonnet  code

   Estimated: 3 waves, max 2 parallel agents per wave.
   Proceed? (yes / dry-run was requested)
   ```
6. **User confirms**
7. **Execute wave-by-wave:**
   - For each task in the wave, spawn a subagent via the Task tool:
     - `subagent_type`: from `agent_config.type` (default: `"general-purpose"`)
     - `model`: from `agent_config.model` (default: haiku for research, sonnet for code)
     - `prompt`: task subject + description + relevant context (file paths, dependencies)
   - **Non-code tasks** (research, analysis, manual):
     - Agent produces a summary/deliverable
     - Write `agent_result` to tasks.json: `{status: "completed", summary: "...", completed_at: "..."}`
     - Mark task status: completed
   - **Code tasks** (execution: code):
     - Agent reads code, composes changes, writes output to `/tmp/task-{id}-output.json`
     - Agent does NOT write to project files — compose only
     - Queue task for write-back phase
   - **Failed tasks:**
     - Write `agent_result`: `{status: "failed", error: "...", completed_at: "..."}`
     - Task stays `in_progress`. Dependents remain blocked.
     - Log error and continue with remaining tasks in wave
8. **Write-back phase** (code tasks, sequential):
   - For each completed code task:
     - Read `/tmp/task-{id}-output.json`
     - Create worktree: `git worktree add ../project-{prefix}{id} -b {prefix}{id}-{slug}`
     - Apply changes in worktree
     - Run tests (if applicable)
     - If tests pass: commit, mark completed
     - If tests fail: mark `agent_result.status: "partial"`, leave for user
     - Clean up: remove worktree
9. **Report summary** (render using task-line template icons for completed):
   ```
   Execution complete:
     ✓ 6 tasks completed
     ◐ 1 task partial (t-009: tests failed)
     ✗ 1 task failed (t-012: agent timeout)

   Milestone 'Auth System': 3/4 done
   Next: /brana:backlog execute --retry ph-002
   ```
   Icons come from active theme (✓/✅/● for completed).

### Model routing

Before spawning an agent for a task, compute a complexity score (0.0–1.0):

| Input | Score contribution | Max |
|-------|-------------------|-----|
| `min(word_count(description) / 100, 0.3)` | Description length | 0.3 |
| `min(len(blocked_by) * 0.1, 0.2)` | Dependency count | 0.2 |
| `0.2` if stream is `roadmap` | Stream type | 0.2 |
| `0.1` if `architecture` in tags | Architecture tag | 0.1 |
| `0.1` if effort is `L` or `XL` | Effort estimate | 0.1 |

Score → model mapping:
- **< 0.3** → haiku (simple tasks)
- **0.3–0.7** → sonnet (standard tasks)
- **> 0.7** → opus (complex tasks)

**Override:** If the task or `agent_config.model` specifies a model explicitly, that wins over the computed score.

**Logging:** Log each routing decision to the decision log as a `cost` entry: `uv run python3 system/scripts/decisions.py log "backlog" "cost" "t-NNN routed to MODEL (score: X.XX)"`

**User override tracking:** If the user explicitly requests a different model than the computed score suggests (e.g., "use opus for this"), log the override: `uv run python3 system/scripts/decisions.py log "backlog" "cost" "t-NNN override: computed=MODEL1 (score: X.XX), user chose MODEL2"`. After 10+ overrides in the same direction (e.g., user keeps upgrading haiku→sonnet), `/brana:review routing` will flag this as a threshold adjustment signal.

**Fallback:** If no task metadata is available (e.g., ad-hoc agent spawn), use the agent's default model from its frontmatter.

### Failure recovery

- `--retry` re-runs tasks with `agent_result.status` of `"failed"` or `"partial"`
- Completed tasks are skipped
- User can also fall back to manual: `/brana:backlog start <id>` on any failed task

### Schema fields (on task objects)

```json
{
  "spawn": "subagent",
  "agent_config": {"type": "general-purpose", "model": "sonnet"},
  "agent_result": null
}
```

After execution:
```json
{
  "agent_result": {
    "status": "completed",
    "summary": "Implemented JWT middleware with refresh token rotation",
    "error": null,
    "completed_at": "2026-02-18T14:30:00Z"
  }
}
```

On parent tasks, `spawn_strategy` controls child batching:
```json
{
  "type": "milestone",
  "spawn_strategy": "auto"
}
```

---

## /brana:backlog triage

Research-informed priority reassessment across project backlogs.

### Usage

```
/brana:backlog triage [project] [--reresearch] [--scope P2+]
```

### Default behavior (no flags)

1. Read tasks.json for the project (or portfolio if omitted)
2. For each pending task without a priority, analyze: revenue impact, urgency, dependencies, effort
3. Propose priority assignments (P0-P3 tiers: P0 = this week, P1 = next, P2 = queue, P3 = backlog)
4. Wait for approval before writing

### With `--reresearch`

1. Read tasks.json
2. Identify tasks with external context: URLs in description/context/notes, tool/platform names in tags (e.g., "kapso", "respond-io", "meta")
3. For each, spawn a scout agent for brief web research (latest docs, changelog, API status)
4. Compare findings against current task description — flag if scope changed, tool matured, or blocker resolved
5. Propose priority adjustments with research summary
6. Wait for approval before writing

### With `--scope P2+`

Only re-evaluate tasks at P2 or lower (skip P0/P1 which were recently triaged).

### Priority tiers

| Tier | Meaning | Review cadence |
|------|---------|----------------|
| P0 | This week — active work | Daily |
| P1 | Next up — queue | Weekly |
| P2 | Backlog — when bandwidth allows | Monthly |
| P3 | Icebox — someday/maybe | Quarterly |

### Sort order

P0 > P1 > P2 > P3 > null. Ties broken by: in_progress first, then pending, then `order` field.

---

## /brana:backlog sync

Sync tasks.json with GitHub Issues. Creates missing issues, closes completed ones, updates stale labels.

### Usage

```
/brana:backlog sync [--dry-run] [--force]
```

### Steps

1. **Check config** — read `github_sync.enabled` from `~/.claude/tasks-config.json`. If not enabled, report: "GitHub sync not configured. Add `github_sync` to `~/.claude/tasks-config.json`."
2. **Read tasks.json** — find tasks needing sync:
   - Non-completed tasks without `github_issue` → need creation
   - Completed tasks with `github_issue` + open issue → need closing
   - Tasks with label drift (compare current task fields against live GitHub labels via `gh issue view --json labels`)
3. **Report plan:** "Sync plan: ~N to create, ~M to close, ~K to update."
4. **If `--dry-run`:** show the plan (task IDs + subjects) and exit without executing.
5. **If not dry-run:** confirm with user before executing.
6. **Execute:** run `system/scripts/gh-sync.sh sync-all {tasks-json-path}`. Script handles progress output.
7. **If `--force`:** run `system/scripts/gh-sync.sh sync-all {tasks-json-path}` without filtering — re-sync all tasks.
8. **Report summary:** "Sync complete: N created, M closed, K errors."
