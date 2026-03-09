---
name: tasks
description: "Manage tasks — plan, track, navigate phases and streams. Use when planning phases, viewing roadmaps, or restructuring work."
group: brana
allowed-tools:
  - Read
  - Write
  - Glob
  - Grep
  - Bash
  - AskUserQuestion
---

# Tasks

Manage project tasks — plan, track, and navigate work across phases,
milestones, and streams. Natural language is the primary interface;
these commands are shortcuts for complex operations.

## When to use

When explicitly managing tasks: planning phases, viewing roadmaps,
restructuring work. Daily task interaction happens through natural
language guided by the task-convention rule — no skill invocation needed.

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
           portfolio header: boxed ╭╮╰╯ with 📊
           priority high: ⚡high
           blocked ref: ⛓ {id}
           health dots: 🟢 done  🟡 active  🔴 blocked

minimal:   {icon} {id}  {subject}  {detail}
           ● done  ◐ active  ○ pending  ⊘ blocked  ◌ parked
           bars: ━━━━╍╍╍╍  {done}/{total}
           blocked ref: ← {id}
```

### Wide mode (`--wide`)

Any view command (`status`, `portfolio`, `roadmap`, `next`, `tags --filter`) accepts `--wide`.
Wide mode renders tasks as **tabular rows** with all metadata visible on one line — like `kubectl get pods -o wide`.
Wide mode composes with any theme (icons come from the active theme).

**Wide-mode template:**

```
Columns:  {icon} {id}  {subject}  {status}  {tags}  {pri}  {eff}  {stream}  {blocked_by}  {started}  {completed}

Header row (always shown):
  ID       Subject                         Status    Tags              Pri  Eff  Stream   Blocked     Started     Done

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

- `/brana:tasks plan [project] "[phase-title]"` — plan a phase interactively
- `/brana:tasks status [project] [--wide]` — progress overview (omit project = portfolio)
- `/brana:tasks portfolio [--unified] [--wide]` — cross-project actionable tasks
- `/brana:tasks roadmap [project] [--wide]` — full tree view with all levels
- `/brana:tasks next [project] [--stream X] [--wide]` — next unblocked task by priority
- `/brana:tasks start <id>` — begin work on a task
- `/brana:tasks done [id]` — complete current task
- `/brana:tasks add "[description]"` — quick-add a task
- `/brana:tasks replan [project] [phase-id]` — restructure a phase
- `/brana:tasks archive [project]` — move completed phases to archive
- `/brana:tasks migrate <file>` — import tasks from a markdown backlog
- `/brana:tasks execute [scope] [--dry-run] [--max-parallel N] [--retry]` — execute tasks via subagents
- `/brana:tasks tags [project]` — tag inventory, filtering, and bulk tag management
- `/brana:tasks context <id> [text]` — view or set rich context on a task
- `/brana:tasks theme [name]` — view or set display theme (classic, emoji, minimal)

---

## /brana:tasks plan

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

## /brana:tasks status

High-level progress view with aggregation.

### Steps

1. **Resolve active theme** (see Display Themes)
2. **Detect project** or show portfolio if omitted
3. **Read tasks.json** (for portfolio: read from each client's project paths in tasks-portfolio.json)
4. **Compute per-phase:** total tasks, completed, in_progress, blocked
5. **Compute per-stream:** roadmap progress, bug count, tech-debt count, research triage counts (new/reviewed/applied)
6. **If `--wide`**, render using **wide-mode template** (see Display Themes > Wide mode). Otherwise render using task-line template with tree connectors:

```
{project} — {active-phase-subject}

  Roadmap
  ├── {phase-subject}                  {bar} {done}/{total}
  │   ├── {milestone-subject}          {bar} {done}/{total}
  │   └── {milestone-subject}          {bar} {done}/{total}
  │
  ├── Bugs
  │   ├── {bug-subject}                {bar} {done}/{total}
  │   └── {bug-subject}                done
  │
  └── Tech Debt
      └── {item}                       pending

  Research                              5 new · 2 reviewed · 1 applied
  ├── → t-105 GraphRAG evaluation           pending [knowledge-graphs]
  └── ...(+62 more)

  Tags: scheduler(4) research(3) quick-win(2)
```

Progress bars use active theme fill/empty characters.
Tag summary line at bottom: shows all tags with counts across active tasks (non-completed). Omit line if no tasks have tags.
For in-progress tasks with a `build_step` field, show the step inline: `← t-008 Implement JWT [BUILD]`.

### Portfolio view (no project argument)

Render using task-line template icons. Emoji theme adds health dots and project emoji prefix.

```
classic/minimal:
palco       Phase 2: API Foundation    ████░░░░ 60%   2 bugs
tinyhomes   Phase 1: Validation        ██░░░░░░ 25%
somos       Cold Lead Flow             ████████ done

emoji:
📊 Portfolio

🟡 palco       Phase 2: API Foundation    ████░░░░ 60%   2 bugs
🟡 tinyhomes   Phase 1: Validation        ██░░░░░░ 25%
🟢 somos       Cold Lead Flow             ████████ done
```

Health dots (emoji only): 🟢 all done, 🟡 has active/pending work, 🔴 has blocked tasks.

Read client/project paths from `~/.claude/tasks-portfolio.json`. Schema: `{ clients: [{ slug, projects: [{ slug, path }] }] }`. Legacy flat `{ projects: [...] }` also supported. Paths use `~/` prefix — resolve to `$HOME` before reading. For each project, read `{path}/.claude/tasks.json` if it exists.

---

## /brana:tasks portfolio

Cross-client actionable task view. Shows individual tasks you can work on across all registered clients. Complements `/brana:tasks status` (progress bars) with a task-level drill-down.

### Usage

```
/brana:tasks portfolio              — by-project view (default)
/brana:tasks portfolio --unified    — priority-sorted flat list
/brana:tasks portfolio --wide       — tabular with all columns
```

### Steps

1. **Resolve active theme** (see Display Themes)
2. **Read `~/.claude/tasks-portfolio.json`** — get client list
3. **Resolve paths** — replace `~/` with `$HOME`
4. **For each client**, iterate its projects array. For each project, read `{path}/.claude/tasks.json`
   - If file doesn't exist: skip silently
   - **Normalize JSON**: if root is a bare array `[{...}]`, treat as the tasks list. If root is an object with `.tasks`, use that.
   - **Legacy schema**: if root has `.projects` instead of `.clients`, treat each entry as a single-project client (slug = project slug)
5. **Classify each task** (type: task or subtask only — skip phases and milestones):
   - `in_progress`: status is `in_progress`
   - `pending`: status is `pending` AND all `blocked_by` IDs have status `completed`
   - `blocked`: status is `pending` AND any `blocked_by` ID is not `completed`
   - `parked`: tags array contains `"parked"` (shown with `[parked]` flag)
   - `completed`: status is `completed`
6. **Sort within each client**: in_progress → pending → blocked → last 3 completed (by `completed` date descending)
7. **Compute summary**: total actionable tasks, client count, pending count, in_progress count
8. **If `--wide`**, render using **wide-mode template** (see Display Themes > Wide mode) — flat table grouped by project. Otherwise render using task-line template — by-project or unified view.

### By-project view (default)

Render task lines using active theme icons. Example in **classic**:

```
Portfolio — 17 tasks across 4 clients (14 pending, 3 in progress)

  nexeye
    ← t-003 First production deploy                    in_progress
    → t-016 Fix inference-worker-2 overlay failure      pending
    · t-017 Fix staging deploy                          blocked by t-003
    ✓ t-015 Configure GitHub Actions CI                 completed 2026-02-18
    ✓ t-014 Fix DNS resolution                          completed 2026-02-17
    ✓ t-013 Set up Docker Swarm                         completed 2026-02-16

  palco
    ← t-003 V2→V3 cutover                              in_progress
    → t-004 Review metrics Google Sheet                 pending
    → t-011 Run Supabase migration                      pending
    ✓ t-010 Build V3 trigger endpoint                   completed 2026-02-15
    ✓ t-009 Migrate campaign schema                     completed 2026-02-14
    ✓ t-008 Add rate limiting                           completed 2026-02-13

  somos
    → t-001 Fill kb-indicaciones-consulta-virtual-bsas  pending
    → t-002 Fill kb-indicaciones-consulta-virtual-eng   pending
    ...(+7 more pending)
    (no recent completions)

  tinyhomes — all done (3 tasks)
```

Same view in **emoji** — note boxed header, health dots, themed icons:

```
╭──────────────────────────────────────────────────────╮
│  📊 Portfolio — 17 tasks · 4 clients                 │
│  🔨 3 in progress · 🔲 14 pending                    │
╰──────────────────────────────────────────────────────╯

  🟡 nexeye
    🔨 t-003 First production deploy                    in_progress
    🔲 t-016 Fix inference-worker-2 overlay failure      pending
    🔒 t-017 Fix staging deploy                          ⛓ t-003
    ✅ t-015 Configure GitHub Actions CI                 completed 2026-02-18
    ✅ t-014 Fix DNS resolution                          completed 2026-02-17
    ✅ t-013 Set up Docker Swarm                         completed 2026-02-16

  🟡 palco
    🔨 t-003 V2→V3 cutover                              in_progress
    🔲 t-004 Review metrics Google Sheet                 pending
    🔲 t-011 Run Supabase migration                      pending
    ✅ t-010 Build V3 trigger endpoint                   completed 2026-02-15
    ✅ t-009 Migrate campaign schema                     completed 2026-02-14
    ✅ t-008 Add rate limiting                           completed 2026-02-13

  🟡 somos
    🔲 t-001 Fill kb-indicaciones-consulta-virtual-bsas  pending
    🔲 t-002 Fill kb-indicaciones-consulta-virtual-eng   pending
    ...(+7 more pending)
    (no recent completions)

  🟢 tinyhomes — all done (3 tasks)
```

Parked tasks show inline: `{blocked-icon} ms-007 Wire AgentDB [parked]  blocked (upstream)`.
Clients with no tasks.json are omitted. All-completed clients show as a collapsed line.
When a project has more than 5 pending tasks, show the first 3 then `...(+N more pending)`.

### Unified priority view (`--unified`)

Render using task-line template icons. Example in **classic**:

```
Portfolio — priority view (17 tasks across 4 clients)

  1. ← nexeye  t-003 First production deploy            in_progress  P1
  2. ← palco   t-003 V2→V3 cutover                      in_progress  P1
  3. → palco   t-004 Review metrics Google Sheet         pending
  4. → palco   t-011 Run Supabase migration              pending
  5. → somos   t-001 Fill kb-indicaciones-virtual-bsas   pending
  6. → somos   t-002 Fill kb-indicaciones-virtual-eng    pending
  ...
```

Sort order: P0 > P1 > P2 > null. Ties broken by: in_progress first, then pending, then `order` field.
Blocked and completed tasks are excluded from the unified view (only actionable tasks).

---

## /brana:tasks roadmap

Full tree view — every level expanded.

### Steps

1. **Resolve active theme** (see Display Themes)
2. Read tasks.json
3. Build tree from parent references
4. **If `--wide`**, render using **wide-mode template** (see Display Themes > Wide mode) with phase/milestone section headers. Otherwise render using task-line template with tree connectors:

```
{project} Roadmap

  ph-001 Phase 1: Setup                            ████████ done
  ├── ms-001 Dev Environment                       ████████ done
  │   ├── ✓ t-001 Install dependencies
  │   └── ✓ t-002 Configure linting
  │
  ph-002 Phase 2: API Foundation                   ████░░░░ 3/8
  ├── ms-003 Auth System                           ██░░░░░░ 1/3
  │   ├── ✓ t-007 Design auth flow
  │   ├── → t-008 Implement JWT middleware [auth, quick-win]  next
  │   └── · t-009 Write auth tests                 blocked by t-008
  └── ms-004 Database Setup                        ░░░░░░░░ 0/3
      ├── · t-010 Design schema                    blocked by ms-003
      ├── · t-011 Write migrations                 blocked by t-010
      └── · t-012 Seed dev data [scheduler]        blocked by t-011

  Bugs
  └── ms-005 Auth token expiry                     ██░░░░░░ 1/3
      ├── ✓ t-013 Investigate root cause
      ├── ← t-014 Fix token refresh
      └── · t-015 Add regression test              blocked by t-014
```

Icons come from the active theme's task-line template. Example above uses classic.
Tags shown inline as `[tag1, tag2]` after subject — only when tags array is non-empty.

---

## /brana:tasks next

Find the highest-priority unblocked task.

### Steps

1. **Resolve active theme** (see Display Themes)
2. Read tasks.json
3. Filter: status=pending, blocked_by all completed, type=task|subtask
4. If `--tag X` provided, additionally filter to tasks containing tag X. If `--stream X` provided, additionally filter to tasks in that stream.
5. Sort by: priority (P0 first) -> order -> created date
6. **If `--wide`**, render top 3 using **wide-mode template** (all columns). Otherwise render using task-line template — show top 3 candidates with tags inline:

```
Next up:
  1. → t-008 Implement JWT middleware [auth, quick-win]  P1  S  roadmap
  2. → t-014 Fix token refresh                           P1  M  bugs
  3. → t-020 Update API docs [docs]                      P2  S  docs

Start one? (number or "1" to begin)
```

Icons come from active theme (example above uses classic `→`).
Optional `--tag` narrows candidates: `/brana:tasks next --tag scheduler`
Optional `--stream` narrows by stream: `/brana:tasks next --stream research`

---

## /brana:tasks start

Begin work on a specific task. For code tasks, enters the `/brana:build` loop.

### Steps

1. **Parse id** from argument, or offer candidates from /brana:tasks next
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
7. **Report:** "Started t-008 'Implement JWT middleware' as **feature**. Branch: feat/t-008-jwt-middleware."
8. **For code tasks:** proceed directly into `/brana:build` — no separate invocation needed

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

## /brana:tasks done

Complete the current task. For code tasks that went through `/brana:build`, the CLOSE step already handles completion — use `/brana:tasks done` only for manual and external tasks.

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
6. **Update task:** status → completed, completed → today's date, clear build_step
7. **Write tasks.json** — hook handles rollup + validation
8. **Report:** "Completed t-008. Milestone 'Auth System': 2/3 done."

---

## /brana:tasks add

Quick-add a single task with intelligent suggestions.

### Steps

All interactive confirmations use the **AskUserQuestion** tool for a selectable UI experience. Batch independent questions into a single AskUserQuestion call (up to 4 questions per call).

1. Parse description from argument
2. Read tasks.json (all pending tasks, active milestones, tag vocabulary)
3. **URL auto-detection:** if the description contains `https://`, suggest `stream: research`, auto-extract the URL to the `context` field (format: `URL: {url}`), and skip the milestone/stream prompt.
4. **First question batch** — use a single AskUserQuestion with up to 4 questions:
   - **Stream** (skip if URL auto-detected): options from active streams, recommended first. Header: "Stream"
   - **Tags**: suggest tags from description keywords matched against existing vocabulary. Options: "Accept {suggested}" (recommended), "Edit", "Skip". Header: "Tags"
   - **Effort**: suggest from description complexity (S/M/L/XL). Options: each size with description. Header: "Effort"
   - **Milestone** (skip if URL auto-detected or no active milestones): options from active milestones + "None". Header: "Milestone"
5. Auto-assign next id, set defaults. Auto-classify `strategy` from description/stream/tags (same heuristic as `/brana:tasks start`). Leave `build_step` null.
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
8. Priority: **leave null** (user sets manually via `/brana:tasks reprioritize` or direct edit)
9. **Final confirmation** — AskUserQuestion: "Add {id} '{subject}' [{tags}, {effort}] under {milestone}? blocked_by: [{deps}]" Options: "Confirm" (recommended), "Edit", "Cancel". Header: "Confirm"
10. Write tasks.json

---

## /brana:tasks replan

Restructure an existing phase.

### Steps

1. Read tasks.json, show current tree for the phase
2. Interactive: "What changes? (add tasks, reorder, move, remove)"
3. Propose updated structure
4. Confirm before writing
5. Handle orphan prevention: if removing a milestone, reassign or remove its children

---

## /brana:tasks archive

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

## /brana:tasks migrate

Import tasks from an existing markdown backlog.

### Steps

1. Read the markdown file
2. Parse structure: headings -> phases/milestones, checkboxes -> tasks
3. Propose tasks.json structure with assigned IDs
4. Wait for approval — user adjusts mapping
5. Write tasks.json
6. Report: "Imported {N} tasks from {file}."

---

## /brana:tasks tags

Tag inventory, filtering, and bulk tag management.

### Usage

```
/brana:tasks tags [project]                    — tag inventory (all tags + task counts)
/brana:tasks tags --filter "tag1,tag2"         — AND filter (tasks with ALL listed tags)
/brana:tasks tags --any "tag1,tag2"            — OR filter (tasks with ANY listed tag)
/brana:tasks tags add <id|ids> "tag1,tag2"     — add tags to one or more tasks
/brana:tasks tags remove <id|ids> "tag1"       — remove a tag from one or more tasks
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

## /brana:tasks context

View or set rich context on a task — rationale, links, notes, decisions.

### Usage

```
/brana:tasks context <id>                     — show context for a task
/brana:tasks context <id> "context text"      — set context (replaces existing)
/brana:tasks context <id> --append "note"     — append to existing context
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

## /brana:tasks theme

View or set the display theme.

### Usage

```
/brana:tasks theme              — show current theme
/brana:tasks theme emoji        — set theme to emoji
/brana:tasks theme classic      — set theme to classic
/brana:tasks theme minimal      — set theme to minimal
```

### Steps

**View (no argument):**
1. Read `~/.claude/tasks-config.json`
2. If file exists and has `theme` field, show: "Current theme: **{name}**"
3. If no file: "Current theme: **classic** (default). Set with `/brana:tasks theme <name>`."

**Set (with name):**
1. Validate name is one of: `classic`, `emoji`, `minimal`
2. Read `~/.claude/tasks-config.json` (create if missing)
3. Set `theme` field to the given name, preserve other fields
4. Write the file
5. Report: "Theme set to **{name}**. All `/brana:tasks` output will use {name} icons."

### Config format

```json
{
  "theme": "emoji"
}
```

Stored at `~/.claude/tasks-config.json` (global, not per-project).

---

## /brana:tasks execute

Execute tasks via subagents — DAG-aware parallel execution with automatic wave scheduling.

```
/brana:tasks execute [scope] [--dry-run] [--max-parallel N] [--retry]
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
   Next: /brana:tasks execute --retry ph-002
   ```
   Icons come from active theme (✓/✅/● for completed).

### Model routing

| Task characteristic | Default model | Override via |
|---------------------|---------------|-------------|
| Research, analysis | haiku | `agent_config.model` |
| Code, tests | sonnet | `agent_config.model` |
| Architecture, design | opus | user sets explicitly |

### Failure recovery

- `--retry` re-runs tasks with `agent_result.status` of `"failed"` or `"partial"`
- Completed tasks are skipped
- User can also fall back to manual: `/brana:tasks start <id>` on any failed task

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

## /brana:tasks reprioritize

Research-informed priority reassessment across project backlogs.

### Usage

```
/brana:tasks reprioritize [project] [--reresearch] [--scope P2+]
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
