# Task Management Guide

How to plan and track work across projects using brana's task system — from daily coding to multi-phase roadmaps.

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
Portfolio    "how are all my projects doing?"
  Project    "where's palco at?"
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

Or use the explicit command: `/tasks plan palco "API Foundation"`

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

Or: `/tasks start t-005`

### Finishing work

```
You: "that's done, tests pass"

Claude: Completing t-005 'Implement JWT middleware'
        -> Commit: feat(auth): implement JWT middleware with refresh
        -> PR: "feat: implement JWT middleware" (Closes #5)
        -> Milestone 'Auth System': 2/4 done
        Create the PR?
```

Or: `/tasks done`  (auto-detects from current branch)

### Quick status check

```
You: "where are we?"

Claude: palco — Phase 3: API Foundation
          Auth System       ====....  2/4
          Database Setup    ........  0/3
          API Layer         ........  0/2
        Next: t-006 'Add login endpoints' (unblocked)
```

Or: `/tasks status palco`

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

Or: `/tasks plan palco "Payments"`

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
/tasks replan palco ph-003
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

View by stream: "show me all open bugs" or `/tasks status palco`

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

From any directory — see all projects at once:

```
You: "how are we doing across projects?"

Claude: Portfolio — 2026-02-18

  palco        Ph3: API Foundation       ====....  5/8    -> JWT middleware    1 bug
  tinyhomes    Ph1: Validation           ==......  2/7    -> Payment flow
  somos        Cold Lead Flow            ========  done
  nexeye       Ph3: Production           ======..  4/6    -> Monitoring
  psilea       —                         no tasks

  Summary: 4 active projects | 15/27 tasks | 3 in progress | 1 bug
  Stale: somos — last activity 12 days ago
```

Or: `/tasks status` (no project argument)

The portfolio view reads from `~/.claude/tasks-portfolio.json` — a simple registry of project paths. Add projects to it when you onboard them.

---

## 9. The Status Line

The status line shows task metrics passively — no commands needed:

**In a project:**
```
Model | project | branch | Ph3: 5/8 | -> JWT middleware | 1 bug | CTX 42%
```

**Outside a project (thebrana, home):**
```
Model | thebrana | main | 4 projects | 15/27 tasks | 1 bug | CTX 42%
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
- Archive is searchable: `/tasks history palco`

Manual archive: `/tasks archive palco`

### Data integrity

A PostToolUse hook validates every write to tasks.json:
- JSON syntax (catches malformed writes)
- Required fields (catches missing data)
- Parent rollup (auto-completes parents when all children done)

You don't need to think about this — it happens automatically.

---

## 12. Migration from Markdown Backlogs

If your project has an existing `BACKLOG.md` or `roadmap.md`:

```
/tasks migrate docs/planning/BACKLOG.md
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
| "how are all projects doing?" | Portfolio view |
| "let's work on X" | Starts task (suggests confirmation) |
| "that's done" | Completes current task |
| "plan a new phase for X" | Interactive planning session |
| "add a task for Y" | Quick-add with context |
| "this is a bug" | Creates task in bugs stream |

### Commands (shortcuts, never required)

| Command | What |
|---------|------|
| `/tasks status [project]` | Progress view (portfolio if no project) |
| `/tasks roadmap <project>` | Full tree with all levels |
| `/tasks next [project]` | Next unblocked by priority |
| `/tasks start <id>` | Begin work (branch, status) |
| `/tasks done [id]` | Complete (commit, PR, status) |
| `/tasks plan [project] "[phase]"` | Interactive planning |
| `/tasks add "[task]"` | Quick add |
| `/tasks replan [project] [phase]` | Restructure |
| `/tasks archive [project]` | Archive completed phases |
| `/tasks migrate <file>` | Import from markdown |

### Task file locations

| File | Location |
|------|----------|
| Active tasks | `{project}/.claude/tasks.json` |
| Archive | `{project}/.claude/tasks-archive.json` |
| Portfolio registry | `~/.claude/tasks-portfolio.json` |
| Convention rule | `~/.claude/rules/task-convention.md` |
| Skill | `~/.claude/skills/tasks/SKILL.md` |
