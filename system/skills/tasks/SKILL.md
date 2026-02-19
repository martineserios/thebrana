---
name: tasks
description: "Manage tasks — plan, track, navigate phases and streams. Use when planning phases, viewing roadmaps, or restructuring work."
allowed-tools:
  - Read
  - Write
  - Glob
  - Grep
  - Bash
---

# Tasks

Manage project tasks — plan, track, and navigate work across phases,
milestones, and streams. Natural language is the primary interface;
these commands are shortcuts for complex operations.

## When to use

When explicitly managing tasks: planning phases, viewing roadmaps,
restructuring work. Daily task interaction happens through natural
language guided by the task-convention rule — no skill invocation needed.

## Commands

- `/tasks plan [project] "[phase-title]"` — plan a phase interactively
- `/tasks status [project]` — progress overview (omit project = portfolio)
- `/tasks roadmap [project]` — full tree view with all levels
- `/tasks next [project]` — next unblocked task by priority
- `/tasks start <id>` — begin work on a task
- `/tasks done [id]` — complete current task
- `/tasks add "[description]"` — quick-add a task
- `/tasks replan [project] [phase-id]` — restructure a phase
- `/tasks archive [project]` — move completed phases to archive
- `/tasks migrate <file>` — import tasks from a markdown backlog
- `/tasks execute [scope] [--dry-run] [--max-parallel N] [--retry]` — execute tasks via subagents
- `/tasks tags [project]` — tag inventory, filtering, and bulk tag management
- `/tasks context <id> [text]` — view or set rich context on a task

---

## /tasks plan

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

## /tasks status

High-level progress view with aggregation.

### Steps

1. **Detect project** or show portfolio if omitted
2. **Read tasks.json** (for portfolio: read from each project path in tasks-portfolio.json)
3. **Compute per-phase:** total tasks, completed, in_progress, blocked
4. **Compute per-stream:** roadmap progress, bug count, tech-debt count
5. **Render:**

```
{project} — {active-phase-subject}

  Roadmap
    {phase-subject}         {bar} {done}/{total}
      {milestone-subject}   {bar} {done}/{total}

  Bugs
    {bug-subject}           {bar} {done}/{total}
    {bug-subject}           done

  Tech Debt
    {item}                  pending

  Tags: scheduler(4) research(3) quick-win(2)
```

Progress bars: filled = completed, empty = remaining
Tag summary line at bottom: shows all tags with counts across active tasks (non-completed). Omit line if no tasks have tags.

### Portfolio view (no project argument)

```
palco       Phase 2: API Foundation    ████░░░░ 60%   2 bugs
tinyhomes   Phase 1: Validation        ██░░░░░░ 25%
somos       Cold Lead Flow             ████████ done
```

Read project paths from `~/.claude/tasks-portfolio.json`. For each, read `.claude/tasks.json` if it exists.

---

## /tasks roadmap

Full tree view — every level expanded.

### Steps

1. Read tasks.json
2. Build tree from parent references
3. Render with indentation, status icons, tags (if any), and blocked indicators:

```
{project} Roadmap

  ph-001 Phase 1: Setup                    ████████ done
    ms-001 Dev Environment                 ████████ done
      t-001 Install dependencies           ✓
      t-002 Configure linting              ✓

  ph-002 Phase 2: API Foundation           ████░░░░ 3/8
    ms-003 Auth System                     ██░░░░░░ 1/3
      t-007 Design auth flow               ✓
      t-008 Implement JWT middleware [auth, quick-win] → next (unblocked)
      t-009 Write auth tests               · blocked by t-008
    ms-004 Database Setup                  ░░░░░░░░ 0/3
      t-010 Design schema                  · blocked by ms-003
      t-011 Write migrations               · blocked by t-010
      t-012 Seed dev data [scheduler]      · blocked by t-011

  Bugs
    ms-005 Auth token expiry               ██░░░░░░ 1/3
      t-013 Investigate root cause         ✓
      t-014 Fix token refresh              ← in progress
      t-015 Add regression test            · blocked by t-014
```

Status icons: completed, -> next unblocked, <- in progress, . pending/blocked
Tags shown inline as `[tag1, tag2]` after subject — only when tags array is non-empty.

---

## /tasks next

Find the highest-priority unblocked task.

### Steps

1. Read tasks.json
2. Filter: status=pending, blocked_by all completed, type=task|subtask
3. If `--tag X` provided, additionally filter to tasks containing tag X
4. Sort by: priority (P0 first) -> order -> created date
5. Show top 3 candidates with tags inline:

```
Next up:
  1. t-008 Implement JWT middleware [auth, quick-win]  P1  S  roadmap
  2. t-014 Fix token refresh                           P1  M  bugs
  3. t-020 Update API docs [docs]                      P2  S  docs

Start one? (number or "1" to begin)
```

Optional `--tag` narrows candidates: `/tasks next --tag scheduler`

---

## /tasks start

Begin work on a specific task.

### Steps

1. **Parse id** from argument, or offer candidates from /tasks next
2. **Read tasks.json**, find the task
3. **Check blocked_by** — if any blocker not completed, warn and abort
4. **Determine execution mode:**
   - `code`: check git status clean -> create branch `{prefix}{id}-{slug}` -> set status + started date + branch field
   - `external`: set status + started date, show task description
   - `manual`: set status + started date, show checklist from description
5. **Write tasks.json**
6. **Report:** "Started t-008 'Implement JWT middleware'. Branch: feat/t-008-jwt-middleware."

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

## /tasks done

Complete the current task.

### Steps

1. **Identify task:**
   - If id provided, use it
   - If on a task branch (feat/t-NNN-*), extract id from branch name
   - Otherwise: show in_progress tasks, ask which one
2. **Read tasks.json**, find the task
3. **For execution: code:**
   - Stage changes: `git add -A` (or ask user what to stage)
   - Commit with conventional type from stream mapping
   - Create PR: `gh pr create --title "{type}: {subject}" --body "Closes #{github_issue}"`
   - Offer to merge: "Merge to main? (PR #{N})"
4. **For execution: external/manual:**
   - Ask: "Any notes on the outcome?"
   - Record in task.notes
5. **Update task:** status -> completed, completed -> today's date
6. **Write tasks.json** — hook handles rollup + validation
7. **Report:** "Completed t-008. Milestone 'Auth System': 2/3 done."

---

## /tasks add

Quick-add a single task.

### Steps

1. Parse description from argument
2. Read tasks.json
3. Ask: "Which stream?" (default: roadmap) and "Which milestone?" (show active ones)
4. If `--tags "tag1,tag2"` provided, use those. Otherwise ask: "Any tags? (comma-separated, or skip)"
5. Auto-assign next id, set defaults (tags default to `[]`)
6. Confirm: "Add t-013 'Handle rate limiting' [scheduler] under ms-003 Auth System?"
7. Write tasks.json

---

## /tasks replan

Restructure an existing phase.

### Steps

1. Read tasks.json, show current tree for the phase
2. Interactive: "What changes? (add tasks, reorder, move, remove)"
3. Propose updated structure
4. Confirm before writing
5. Handle orphan prevention: if removing a milestone, reassign or remove its children

---

## /tasks archive

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

## /tasks migrate

Import tasks from an existing markdown backlog.

### Steps

1. Read the markdown file
2. Parse structure: headings -> phases/milestones, checkboxes -> tasks
3. Propose tasks.json structure with assigned IDs
4. Wait for approval — user adjusts mapping
5. Write tasks.json
6. Report: "Imported {N} tasks from {file}."

---

## /tasks tags

Tag inventory, filtering, and bulk tag management.

### Usage

```
/tasks tags [project]                    — tag inventory (all tags + task counts)
/tasks tags --filter "tag1,tag2"         — AND filter (tasks with ALL listed tags)
/tasks tags --any "tag1,tag2"            — OR filter (tasks with ANY listed tag)
/tasks tags add <id|ids> "tag1,tag2"     — add tags to one or more tasks
/tasks tags remove <id|ids> "tag1"       — remove a tag from one or more tasks
```

### Steps

**Inventory (no subcommand):**
1. Read tasks.json
2. Collect all unique tags across all tasks
3. Count tasks per tag (include status breakdown)
4. Render:

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
4. Render matching tasks as a flat list with status and tags:

```
Tasks tagged [scheduler]:
  t-008 Implement JWT middleware [scheduler, auth]     → pending
  t-012 Seed dev data [scheduler]                      · blocked
  t-018 Deploy scheduler config [scheduler, quick-win] ← in_progress
  t-021 Scheduler v2 research [scheduler, research]    ✓ completed
```

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

## /tasks context

View or set rich context on a task — rationale, links, notes, decisions.

### Usage

```
/tasks context <id>                     — show context for a task
/tasks context <id> "context text"      — set context (replaces existing)
/tasks context <id> --append "note"     — append to existing context
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

## /tasks execute

Execute tasks via subagents — DAG-aware parallel execution with automatic wave scheduling.

```
/tasks execute [scope] [--dry-run] [--max-parallel N] [--retry]
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
9. **Report summary:**
   ```
   Execution complete:
     ✓ 6 tasks completed
     ~ 1 task partial (t-009: tests failed)
     ✗ 1 task failed (t-012: agent timeout)

   Milestone 'Auth System': 3/4 done
   Next: /tasks execute --retry ph-002
   ```

### Model routing

| Task characteristic | Default model | Override via |
|---------------------|---------------|-------------|
| Research, analysis | haiku | `agent_config.model` |
| Code, tests | sonnet | `agent_config.model` |
| Architecture, design | opus | user sets explicitly |

### Failure recovery

- `--retry` re-runs tasks with `agent_result.status` of `"failed"` or `"partial"`
- Completed tasks are skipped
- User can also fall back to manual: `/tasks start <id>` on any failed task

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
