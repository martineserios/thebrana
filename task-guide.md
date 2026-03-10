# Task Management Guide

How to plan and track work across clients using brana's task system — from daily coding to multi-phase roadmaps.

The system works through natural language. You talk to Claude about your work, and it manages structured tasks behind the scenes. Commands exist as shortcuts, never requirements.

---

## Table of Contents

1. [Overview](#1-overview)
2. [Getting Started](#2-getting-started)
3. [Daily Workflow](#3-daily-workflow)
4. [Planning Work](#4-planning-work)
5. [Streams](#5-streams)
6. [Branch Integration](#6-branch-integration)
7. [Non-Code Projects](#7-non-code-projects)
8. [Portfolio View](#8-portfolio-view)
9. [The Status Line](#9-the-status-line)
10. [How Skills Use Tasks](#10-how-skills-use-tasks)
11. [Archiving and Maintenance](#11-archiving-and-maintenance)
12. [Migration from Markdown Backlogs](#12-migration-from-markdown-backlogs)
13. [Common Scenarios](#13-common-scenarios)
14. [Quick Reference](#14-quick-reference)
15. [Agent Execution](#15-agent-execution)
16. [Tags & Context](#16-tags--context)

---

## 1. Overview

The task system has three layers:

```
You (natural language)
  |
Claude Code (reads convention rule, reasons about tasks)
  |
tasks.json (structured data — one file per project)
```

No external services. No API calls. Everything runs locally inside Claude Code.

### The hierarchy

```
Phase            (big planning bucket — a roadmap chunk)
  +- Milestone     (a shippable outcome)
       +- Task       (a unit of work — one branch, one commit)
            +- Subtask  (optional detail within a task)
```

### Three zoom levels

```
Portfolio    "how are all my clients doing?"
  Client     "where's palco at?"
    Roadmap  "show me every task and dependency"
```

---

## 2. Getting Started

### First-time setup

The system activates when you deploy the brana update. No per-project setup needed — tasks.json is created on first use.

### Creating your first tasks

Just talk about it:

```
You: "I need to plan palco's next phase — API foundation.
      We need auth, database setup, and the API layer."

Claude: I'll create Phase 3: API Foundation with 3 milestones:
          1. Auth System
          2. Database Setup
          3. API Layer
        Want me to break any of these into tasks?

You: "break down auth"

Claude: Auth System:
          1. Design auth flow (S)
          2. Implement JWT middleware (M) — depends on #1
          3. Add login/register endpoints (M) — depends on #2
          4. Write auth tests (S) — depends on #3
        Look good?

You: "yes"

Claude: Created Phase 3 with 1 milestone and 4 tasks in tasks.json.
```

Or use the explicit command: `/brana:backlog plan palco "API Foundation"`

### Where tasks live

```
your-project/
  .claude/
    tasks.json          <- active tasks
    tasks-archive.json  <- completed phases (auto-managed)
```

Git-tracked. Survives machine migration. One file per project.

---

## 3. Daily Workflow

### Start of day

```
You: "morning, what's on my plate?"

Claude: palco — Phase 3: API Foundation (3/8 tasks)
        -> Next unblocked: t-005 'Implement JWT middleware' (P1)
        1 bug open: t-012 'Login 500 for some users'

        Start the JWT work or tackle the bug first?
```

### Starting work

```
You: "let's do the JWT middleware"

Claude: Starting t-005 'Implement JWT middleware'
        -> Branch: feat/t-005-jwt-middleware
        -> Status: in_progress
        Confirm?

You: "yes"
```

Or: `/brana:backlog pick t-005`

### Finishing work

```
You: "that's done, tests pass"

Claude: Completing t-005 'Implement JWT middleware'
        -> Commit: feat(auth): implement JWT middleware with refresh
        -> PR: "feat: implement JWT middleware" (Closes #5)
        -> Milestone 'Auth System': 2/4 done
        Create the PR?
```

Or: `/brana:backlog done`  (auto-detects from current branch)

### Quick status check

```
You: "where are we?"

Claude: palco — Phase 3: API Foundation
          Auth System       ====....  2/4
          Database Setup    ........  0/3
          API Layer         ........  0/2
        Next: t-006 'Add login endpoints' (unblocked)
```

Or: `/brana:backlog status palco`

---

## 4. Planning Work

### Plan a new phase

Talk through it naturally. Claude proposes structure, you approve.

```
You: "we need a payments phase for palco"
-> Claude asks about milestones
-> You discuss scope
-> Claude proposes the full tree
-> You approve
-> tasks.json updated
```

Or: `/brana:backlog plan palco "Payments"`

### Add a task mid-work

```
You: "oh, we also need rate limiting on the API"

Claude: Want me to add 'Implement rate limiting' under the API Layer
        milestone? (t-015, P2, effort S)

You: "yes, and it depends on the middleware being done"

Claude: Added t-015 with blocked_by: [t-005]
```

### Restructure a phase

```
/brana:backlog replan palco ph-003
```

Shows the current tree, lets you add/remove/reorder interactively.

---

## 5. Streams

Tasks are organized by stream — the type of work:

| Stream | What | Branch prefix |
|--------|------|:-------------|
| **roadmap** | Planned features and phases | `feat/` |
| **bugs** | Bug fixes, incidents | `fix/` |
| **tech-debt** | Refactoring, cleanup | `refactor/` |
| **docs** | Documentation | `docs/` |
| **experiments** | Spikes, research | `experiment/` |

A simple bug is one task. A complex bug gets its own hierarchy:

```
You: "login is 500ing for some users, this looks complex"

Claude: Creating bug milestone 'Login 500':
          1. Investigate root cause
          2. Fix the issue
          3. Add regression test
        Stream: bugs. Created?
```

View by stream: "show me all open bugs" or `/brana:backlog status palco`

---

## 6. Branch Integration

Tasks with `execution: code` integrate with git:

| Action | What happens |
|--------|-------------|
| **Start** | Branch created: `{stream-prefix}{id}-{slug}` |
| **Done** | Commit + PR with conventional commit format |
| **Merge** | PR merged to main, branch deleted |

Branch prefix comes from the stream (see table above).

When you're already on a task branch and say "that's done", Claude detects the task from the branch name — no need to specify the ID.

### Worktree support

If you're on a different branch and start a new task, Claude uses worktrees per your git-discipline:

```bash
git worktree add ../palco-feat-t-005 -b feat/t-005-jwt-middleware
```

---

## 7. Non-Code Projects

For projects like somos_mirada (no-code, Respond.io) or venture tasks:

```
You: "for somos, we need to configure the cold lead WhatsApp flow"

Claude: Creating task 'Configure cold lead flow'
        Execution: external (Respond.io)
        -> No branch, no git — just status tracking
        Created?
```

Three execution modes:

| Mode | On start | On done |
|------|----------|---------|
| **code** | Create branch | Commit + PR |
| **external** | Show instructions | Record outcome |
| **manual** | Show checklist | Mark done |

Auto-detected from project type (has `.git`?) but overridable per task.

---

## 8. Portfolio View

From any directory — see all clients at once:

```
You: "how are we doing across clients?"

Claude: Portfolio — 2026-02-18

  palco        Ph3: API Foundation       ====....  5/8    -> JWT middleware    1 bug
  tinyhomes    Ph1: Validation           ==......  2/7    -> Payment flow
  somos        Cold Lead Flow            ========  done
  nexeye       Ph3: Production           ======..  4/6    -> Monitoring
  psilea       —                         no tasks

  Summary: 4 active clients | 15/27 tasks | 3 in progress | 1 bug
  Stale: somos — last activity 12 days ago
```

Or: `/brana:backlog status` (no client argument)

The portfolio view reads from `~/.claude/tasks-portfolio.json` — a registry of clients and their projects with metadata. Each project entry has: `slug`, `path`, `type` (code/venture/hybrid), `stage` (discovery/validation/growth/scale), `tech_stack`, and `created` date. Multi-project clients show as `client/project` in views. See `docs/architecture/features/tasks-portfolio.md` for the full schema.

---

## 9. The Status Line

The status line shows task metrics passively — no commands needed:

**In a project:**
```
Model | project | branch | Ph3: 5/8 | -> JWT middleware | 1 bug | CTX 42%
```

**Outside a project (thebrana, home):**
```
Model | thebrana | main | 4 clients | 15/27 tasks | 1 bug | CTX 42%
```

Updates on session start. Shows: phase progress, current/next task, open bugs.

---

## 10. How Skills Use Tasks

Existing skills gain task awareness automatically:

| Skill | What it reads from tasks |
|-------|-------------------------|
| `/morning` | Active tasks, stale in-progress items, next unblocked |
| `/weekly-review` | Tasks completed this week, progress delta, carry-over items |
| `/build-phase` | Creates phase hierarchy, executes build loop per task |
| `/build-feature` | Creates milestone + tasks, tracks progress |
| `/debrief` | Reads completed tasks for session debrief context |

---

## 11. Archiving and Maintenance

When a phase completes (all children done), the system auto-archives it:
- Completed subtree moves from `tasks.json` -> `tasks-archive.json`
- Active file stays small (good for context budget)
- Archive is searchable: `/brana:backlog history palco`

Manual archive: `/brana:backlog archive palco`

### Data integrity

A PostToolUse hook validates every write to tasks.json:
- JSON syntax (catches malformed writes)
- Required fields (catches missing data)
- Optional field types: `tags` must be array of strings, `context` must be string (if present)
- Parent rollup (auto-completes parents when all children done)

You don't need to think about this — it happens automatically.

---

## 12. Migration from Markdown Backlogs

If your project has an existing `BACKLOG.md` or `roadmap.md`:

```
/brana:backlog migrate docs/planning/BACKLOG.md
```

Claude reads the markdown, proposes a tasks.json structure, and lets you approve before writing.

---

## 13. Common Scenarios

### Bug appears mid-feature

```
You: "the API is returning 500 on login"
Claude: That's a bug. Create 'Login API 500' (bugs stream, P1)?
You: "yes, let me investigate"
Claude: Created t-020. Branch: fix/t-020-login-500. Started.
...work...
You: "found it, stale Redis sessions. Fixed."
Claude: Completing t-020. Commit: fix(auth): clear expired Redis sessions. PR?
```

### Planning across multiple sessions

tasks.json persists. Start planning in one session, continue in another:

```
Session 1: "plan palco phase 3" -> creates hierarchy -> you approve
Session 2: "where were we on palco?" -> Claude reads tasks.json -> full context
```

### Reprioritize mid-phase

```
You: "move the rate limiting task to P0, a client is hitting limits"
Claude: Updating t-015 priority: P2 -> P0. Confirm?
You: "yes"
Claude: t-015 is now highest priority. It's unblocked — start it?
```

### Non-code task in a code project

```
You: "I need to email the client about the API changes"
Claude: Create task 'Email client re: API changes'? (execution: manual)
You: "yes"
...later...
You: "sent the email, they're fine with the changes"
Claude: Marking done. Notes: "Client approved API changes via email."
```

---

## 14. Quick Reference

### Natural language (primary interface)

| Say | Claude does |
|-----|-----------|
| "what's next?" | Shows next unblocked task |
| "where are we?" | Project status overview |
| "how are all clients doing?" | Portfolio view |
| "let's work on X" | Starts task (suggests confirmation) |
| "that's done" | Completes current task |
| "plan a new phase for X" | Interactive planning session |
| "add a task for Y" | Quick-add with context |
| "this is a bug" | Creates task in bugs stream |
| "show tasks tagged X" | Filter by tag |
| "tag t-008 as X" | Add tag to task |
| "add context to t-008" | Set task context |

### Commands (shortcuts, never required)

| Command | What |
|---------|------|
| `/brana:backlog status [project]` | Progress view (portfolio if no project) |
| `/brana:backlog roadmap <project>` | Full tree with all levels |
| `/brana:backlog next [project]` | Next unblocked by priority |
| `/brana:backlog pick <id>` | Begin work (branch, status) |
| `/brana:backlog done [id]` | Complete (commit, PR, status) |
| `/brana:backlog plan [project] "[phase]"` | Interactive planning |
| `/brana:backlog add "[task]"` | Quick add |
| `/brana:backlog replan [project] [phase]` | Restructure |
| `/brana:backlog archive [project]` | Archive completed phases |
| `/brana:backlog migrate <file>` | Import from markdown |
| `/brana:backlog execute [scope]` | Execute tasks via subagents |
| `/brana:backlog tags [project]` | Tag inventory, filter, add/remove |
| `/brana:backlog tags --filter "a,b"` | Tasks with ALL listed tags |
| `/brana:backlog tags add <id> "a,b"` | Add tags to task(s) |
| `/brana:backlog context <id> [text]` | View or set task context |
| `/brana:backlog next --tag X` | Next unblocked filtered by tag |

### Task file locations

| File | Location |
|------|----------|
| Active tasks | `{project}/.claude/tasks.json` |
| Archive | `{project}/.claude/tasks-archive.json` |
| Portfolio registry | `~/.claude/tasks-portfolio.json` |
| Convention rule | `~/.claude/rules/task-convention.md` |
| Skill | `~/.claude/skills/backlog/SKILL.md` |

---

## 15. Agent Execution

Tasks can be executed automatically by spawning subagents — one agent per task, with DAG-aware parallelism.

### How it works

```
You (or /brana:backlog execute)
  |
Orchestrator reads DAG, builds waves
  |
Wave 1: spawn agents for unblocked tasks (parallel)
  → agents complete → results written to tasks.json
  |
Wave 2: spawn agents for newly unblocked tasks
  → ...
  |
Write-back: code task outputs applied to worktrees (sequential)
  |
Summary report
```

### Setting up tasks for agent execution

Add the `spawn` field to any task you want agents to handle:

```json
{
  "id": "t-008",
  "subject": "Implement JWT middleware",
  "spawn": "subagent",
  "agent_config": {"type": "general-purpose", "model": "sonnet"}
}
```

Tasks without `spawn` are manual (v1 behavior). Both modes coexist — you can agent-execute some tasks and manually do others in the same phase.

On milestones/phases, `spawn_strategy` controls how children execute:

| Strategy | Behavior |
|----------|----------|
| `"auto"` | Use the DAG — parallel where dependencies allow (default) |
| `"parallel"` | All children in one wave (ignore inter-child deps) |
| `"sequential"` | One task per wave, in order |
| `null` | Manual execution — no agent spawning |

### Running it

```
You: "execute the auth milestone"

Claude: Execution plan for ms-003 Auth System (2 waves, 4 tasks):

          Wave 1:
            t-007 Design auth flow          haiku

          Wave 2 (parallel):
            t-008 Implement JWT middleware   sonnet
            t-009 Write auth tests           sonnet

        Proceed?

You: "yes"

Claude: Wave 1: spawning 1 agent...
        ✓ t-007 completed — "Auth flow: JWT with refresh, OAuth2 deferred"

        Wave 2: spawning 2 agents...
        ✓ t-008 completed — branch feat/t-008-jwt-middleware, tests pass
        ~ t-009 partial — 2/5 test cases failing

        Summary: 3/4 tasks done, 1 partial.
        Fix t-009 manually or /brana:backlog execute --retry ms-003
```

Or use the command directly: `/brana:backlog execute ms-003`

### Dry run

Preview the execution plan without running anything:

```
/brana:backlog execute ms-003 --dry-run
```

Shows wave breakdown, agent types, and models — useful for cost estimation before committing.

### Code tasks and the sandbox

Agents are sandboxed to the project directory — they can't write to worktrees (which live at `../`). For code tasks, the system uses compose-then-write:

1. **Agent phase**: agent reads code, analyzes, composes changes → writes to `/tmp/task-{id}-output.json`
2. **Write phase**: orchestrator creates worktree, applies changes, runs tests, commits

Multiple code agents compose in parallel (the expensive part). Write-backs happen sequentially (the cheap part).

### Model routing

| Task type | Default model |
|-----------|---------------|
| Research, analysis | haiku |
| Code implementation, tests | sonnet |
| Architecture, complex design | opus (user-set only) |

Override per task with `agent_config.model`.

### When things fail

| What happened | What the system does |
|---------------|---------------------|
| Agent timed out | Task marked failed. Dependents stay blocked. |
| Tests failed | Task marked partial. User decides: retry or take over. |
| Invalid output | Task reverts to pending. Try again or do manually. |
| You cancel (Ctrl+C) | Completed tasks keep status. In-progress revert to pending. |

Retry failed tasks: `/brana:backlog execute --retry <scope>`

Or take over manually: `/brana:backlog pick <id>` on any failed task.

---

## 16. Tags & Context

Two optional fields that add flexible classification and rich background to tasks.

### Tags

Tags are arbitrary strings on any task — they complement the fixed stream taxonomy with ad-hoc groupings.

```json
{
  "id": "t-008",
  "subject": "Implement JWT middleware",
  "tags": ["auth", "quick-win"],
  "stream": "roadmap"
}
```

Streams answer "what kind of work?" (5 fixed values). Tags answer "what else is this related to?" (unlimited, user-defined).

#### Working with tags

```
You: "show me all tasks tagged 'scheduler'"

Claude: Tasks tagged [scheduler]:
          t-008 Implement JWT middleware [scheduler, auth]     pending
          t-012 Seed dev data [scheduler]                      blocked
          t-018 Deploy scheduler config [scheduler, quick-win] in_progress

You: "tag t-020 and t-021 as 'research'"

Claude: Add tag 'research' to t-020, t-021? Confirm?
```

Or use commands: `/brana:backlog tags --filter "scheduler"`, `/brana:backlog tags add t-020,t-021 "research"`

#### Tag inventory

```
You: "what tags do we have?"

Claude: Tags in palco:
          scheduler     4 tasks  (2 pending, 1 in_progress, 1 completed)
          quick-win     3 tasks  (3 pending)
          auth          2 tasks  (2 pending)
```

Or: `/brana:backlog tags palco`

#### Filtering next task by tag

```
/brana:backlog next --tag scheduler
```

Narrows candidates to tasks with the specified tag.

### Context

Free-form text attached to a task — rationale, links, constraints, decisions. Richer than `notes` (which captures outcomes), context captures the *why* and *how*.

```json
{
  "id": "t-008",
  "subject": "Implement JWT middleware",
  "context": "Chose JWT over session cookies for stateless API. See ADR-005.\nKey constraint: tokens expire in 15min, refresh in 7d.",
  "notes": null
}
```

#### Setting context

```
You: "add some context to t-008 — we chose JWT because of the stateless API"

Claude: Set context on t-008: "Chose JWT for stateless API. See ADR-005."
        Confirm?
```

Or: `/brana:backlog context t-008 "Chose JWT for stateless API. See ADR-005."`

Append to existing context: `/brana:backlog context t-008 --append "Also needs PKCE for mobile clients."`

#### Viewing context

```
/brana:backlog context t-008
```

Shows the full context with the task subject as header.

### Schema

Both fields are optional — existing tasks.json files work unchanged.

| Field | Type | Default | Validation |
|-------|------|---------|-----------|
| `tags` | `string[]` | `[]` | Must be array; items must be strings |
| `context` | `string` | `null` | Must be string if present |

Tags sit after `description` (classification cluster). Context sits after `notes` (free-form text cluster).

### Planning with tags

During `/brana:backlog plan`, Claude offers to bulk-tag all tasks in a phase:

```
Claude: Tag all tasks in this phase? (comma-separated, or skip)
You: "scheduler, v2"
Claude: Applied [scheduler, v2] to all 6 tasks.
```

When adding tasks with `/brana:backlog add`, pass `--tags "tag1,tag2"` or Claude asks interactively.
