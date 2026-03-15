---
name: sitrep
description: "Situational awareness — where am I, what was I doing, what's left, what should I do next. Context recovery after compression, confusion, or mid-session reorientation."
argument-hint: ""
group: core
allowed-tools:
  - Bash
  - Read
  - Glob
  - Grep
  - Task
  - AskUserQuestion
---

# Sitrep — Situational Awareness

One command to answer: **Where am I? What was I doing? What's left? What's next?**

## When to use

- After context compression (conversation truncated)
- When confused about current progress or state
- Mid-session reorientation ("wait, what was I doing?")
- After returning from a tangent or interruption
- Proactively: anytime you're unsure whether to continue, stop, or switch

## Process

Gather from 5 sources in parallel, then synthesize into one snapshot. No writes — this is read-only.

### 1. CC Tasks (active skill flow)

```
Call TaskList
```

Look for:
- `in_progress` tasks → you're mid-step in a skill flow
- `pending` tasks with completed blockers → next step to execute
- Pattern: subject format `/brana:{skill} — {STEP}` reveals which skill is active

**If CC Tasks exist:** the active skill and current step are your primary context.
**If no CC Tasks:** no multi-step skill is running.

### 2. Git state

```bash
git branch --show-current
git status --porcelain | head -10
git log --oneline -5
git stash list 2>/dev/null | head -3
```

Extract:
- **Current branch** → maps to task convention (`feat/t-NNN-*`, `fix/t-NNN-*`, etc.)
- **Uncommitted changes** → work in progress that needs committing or stashing
- **Recent commits** → what was just accomplished
- **Stashes** → forgotten work-in-progress
- **Worktrees** → parallel work streams: `git worktree list`

### 3. Active backlog task

```bash
brana backlog query --status in_progress
```

For each in_progress task, extract:
- `id`, `subject`, `strategy`, `build_step`, `branch`
- `build_step` tells you exactly where in the /brana:build loop you are

### 4. Session handoff (last entry)

```bash
HANDOFF=$(find ~/.claude/projects/ -maxdepth 3 -name "session-handoff.md" -path "*$(basename $(git rev-parse --show-toplevel 2>/dev/null))*" 2>/dev/null | head -1)
```

Read the last `## YYYY-MM-DD` section. Extract:
- **Accomplished** → what was already done
- **Next** → planned follow-ups
- **Blockers** → anything stalling progress

### 5. Conversation scan

Review the last few conversation turns for:
- Last skill invoked (e.g., `/brana:build`, `/brana:close`)
- Last user instruction that hasn't been completed
- Any "do X next" or "after that, Y" signals

---

## Output

Present a structured snapshot — concise, actionable:

```markdown
## Sitrep

**Branch:** {branch} ({task-id if extractable})
**Uncommitted:** {N files / clean}
**Worktrees:** {list or "none"}

**Active task:** {id} "{subject}" — strategy: {strategy}, build_step: {build_step}
**Active skill:** {skill name from CC Tasks, or "none"}
  Step: {current step} ({N}/{total} complete)

**Recent:** {last 2-3 commits, one line each}

**Session handoff says next:**
- {from handoff Next section}

**Next action:** {single clear sentence — what to do RIGHT NOW}
```

### Next action logic

Determine the single most important next action:

1. **If CC Task is `in_progress`:** "Resume {step} of /brana:{skill}."
2. **If build_step is set on active task:** "Continue {build_step} step of /brana:build for {task-id}."
3. **If uncommitted changes exist:** "Commit or stash {N} uncommitted files before proceeding."
4. **If no active task but handoff has Next:** "Pick up from handoff: {first next item}."
5. **If nothing active:** "No active work. Run `brana backlog next` to pick a task."

---

## Rules

1. **Read-only.** Never modify files, tasks, or git state. Just observe and report.
2. **Fast.** All 5 sources gathered in parallel. No deep analysis — surface-level scan.
3. **Actionable.** Always end with a concrete "Next action" — never just a status dump.
4. **Honest.** If you can't determine something, say so: "Build step unknown — task may have been started in a prior session."
5. **No step registry.** This is a single-step command. No CC Tasks needed for sitrep itself.
