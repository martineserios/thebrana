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
9. **Wait for approval** — user can adjust before writing
10. **Write tasks.json** — one Write for the entire batch
11. **Report:** show the tree with IDs for reference

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
```

Progress bars: filled = completed, empty = remaining

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
3. Render with indentation, status icons, and blocked indicators:

```
{project} Roadmap

  ph-001 Phase 1: Setup                    ████████ done
    ms-001 Dev Environment                 ████████ done
      t-001 Install dependencies           ✓
      t-002 Configure linting              ✓

  ph-002 Phase 2: API Foundation           ████░░░░ 3/8
    ms-003 Auth System                     ██░░░░░░ 1/3
      t-007 Design auth flow               ✓
      t-008 Implement JWT middleware        → next (unblocked)
      t-009 Write auth tests               · blocked by t-008
    ms-004 Database Setup                  ░░░░░░░░ 0/3
      t-010 Design schema                  · blocked by ms-003
      t-011 Write migrations               · blocked by t-010
      t-012 Seed dev data                  · blocked by t-011

  Bugs
    ms-005 Auth token expiry               ██░░░░░░ 1/3
      t-013 Investigate root cause         ✓
      t-014 Fix token refresh              ← in progress
      t-015 Add regression test            · blocked by t-014
```

Status icons: completed, -> next unblocked, <- in progress, . pending/blocked

---

## /tasks next

Find the highest-priority unblocked task.

### Steps

1. Read tasks.json
2. Filter: status=pending, blocked_by all completed, type=task|subtask
3. Sort by: priority (P0 first) -> order -> created date
4. Show top 3 candidates:

```
Next up:
  1. t-008 Implement JWT middleware     P1  S  roadmap
  2. t-014 Fix token refresh            P1  M  bugs
  3. t-020 Update API docs              P2  S  docs

Start one? (number or "1" to begin)
```

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
4. Auto-assign next id, set defaults
5. Confirm: "Add t-013 'Handle rate limiting' under ms-003 Auth System?"
6. Write tasks.json

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
