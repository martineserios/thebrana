# Day-to-Day Usage

How to use brana in a typical work session — from opening Claude Code to closing out and saving what you learned.

## The loop

Every session follows the same rhythm:

```
Open Claude → Orient (sitrep) → Pick work → Build → Close
```

That's it. The rest of this guide fills in each step.

---

## 1. Open Claude Code

Navigate to your project directory before launching:

```bash
cd ~/projects/my-app
claude
```

Brana loads automatically. The session-start hook fires and:
- Recalls relevant patterns from memory
- Injects your current task summary (active phase, next unblocked task)
- Shows any high-priority corrections from past sessions

You'll see a brief status block at the top. Read it.

---

## 2. Orient with sitrep

Before touching any code, run:

```
/brana:sitrep
```

Sitrep gives you a situational snapshot: where you are, what was happening last session, what's blocking, and what the next action is. Think of it as the morning briefing.

**What sitrep shows:**
- Current branch and git status
- Active and blocked tasks
- Last session handoff note
- Stale worktrees to clean up
- Any pending learnings or backprop flags

**When to run it:**
- At the start of every session (non-negotiable)
- When you're disoriented ("what was I doing?")
- Before starting a new task to check for blockers

See [Sitrep](workflows/sitrep.md) for a full breakdown.

---

## 3. Pick your work

After sitrep, you know what's next. Three ways to start:

### From the backlog

```
/brana:backlog next        -- shows top unblocked tasks by priority
/brana:backlog start t-42  -- starts that specific task
```

### From a description

```
/brana:build "add rate limiting to the API"
```

Brana creates a task, classifies the work type, and enters the build loop.

### From the current branch

If you're already on a branch from last session, just tell Claude: "continue working on t-42." Sitrep would have surfaced the branch and last state.

---

## 4. Build the thing

Once you've started a task, `/brana:build` guides you through the appropriate flow:

| Work type | Flow |
|-----------|------|
| Feature | SPECIFY → DECOMPOSE → BUILD → CLOSE |
| Bug fix | REPRODUCE → DIAGNOSE → FIX → CLOSE |
| Refactor | VERIFY COVERAGE → BUILD → CLOSE |
| Spike | QUESTION → EXPERIMENT → ANSWER |
| Investigation | SYMPTOMS → INVESTIGATE → REPORT |

Each step is interactive — brana asks before advancing. You control the pace.

**During build, brana enforces:**
- Tests before implementation (on feat/* branches)
- Spec before code (SDD gate for features)
- Branch before edits (main-guard hook)

These aren't optional. If you hit a gate, deal with it — don't bypass.

See [Building Things](workflows/build.md) for the full build guide.

---

## 5. Close the session

When you're done (or stopping for the day):

```
/brana:close
```

Close does the work you'd otherwise skip:
- Extracts learnings from the session (via debrief-analyst agent)
- Writes errata to any docs that drifted
- Stores patterns in memory for future sessions
- Writes a handoff note so next session picks up cleanly

**Always run `/brana:close`.** Sessions without a close lose learnings. If you're in a hurry, say "quick close" — brana does a minimal version.

---

## Best practices

### Start every session with sitrep

Skipping sitrep means starting blind. It takes 5 seconds and surfaces blockers, stale branches, and last-session state. Make it muscle memory.

### One task per branch

Keep branches tight. `brana backlog start <id>` creates the branch for you — one task, one branch, one PR. Long-lived branches accumulate context debt.

### Research before building

When starting something unfamiliar, run `/brana:research <topic>` before `/brana:build`. Ten minutes of research prevents an hour of wrong-direction implementation.

### Add context to tasks, not just subjects

A task subject like "Fix auth bug" is useless to future-you. When adding tasks:
- Include the problem statement
- Include any relevant links or prior research
- Include what "done" looks like

```
/brana:backlog add "Fix JWT expiry not refreshing correctly — token issued at login, refresh call returns 401 after 1h. Expected: refresh succeeds. See logs in #auth-bugs Slack."
```

### Close every session

Non-negotiable. Even a 20-minute session has learnings worth keeping. The memory accumulates — over weeks, brana gets noticeably better at working with your codebase.

### Keep CLAUDE.md lean

The project `.claude/CLAUDE.md` loads every session. Keep it under 400 lines. Move detailed notes to dimension docs or the knowledge base. Fat CLAUDE.md files bleed context budget.

### Use backlog to think

The backlog isn't just a task list — it's how you think. Add tasks when you identify work, even speculatively. Use the `context` field for reasoning. Triage weekly with `/brana:backlog triage`.

---

## Tips

**Stuck mid-session?** Run `/brana:sitrep` — it reorients you without starting a new session.

**Lost a context?** If the session compresses (long conversation), brana's step registry helps resume in-progress builds. Run `/brana:build` with no args — it checks for in-progress work.

**Multiple projects?** Open Claude Code from each project's root directory. Each project gets its own tasks, memory, and context. They share global rules and the cross-project knowledge base.

**Dirty state at session start?** Brana surfaces uncommitted changes in sitrep. Commit or stash before starting new work — mixed-state sessions get confusing fast.

**Forgot to close last session?** Run `/brana:close` now. Brana reads git log to reconstruct what happened. Not as good as closing in-session, but better than skipping.

**Something weird?** See [Troubleshooting](troubleshooting.md).

---

## Common session patterns

### Quick fix (< 30 min)

```
/brana:sitrep
/brana:build "fix the null pointer in UserService.fetch"
-- brana classifies as bug fix, enters REPRODUCE → DIAGNOSE → FIX
/brana:close
```

### Feature work (hours or multi-session)

```
/brana:sitrep
/brana:backlog start t-88
-- brana enters build, SPECIFY → DECOMPOSE → BUILD
-- natural breakpoints every 2-3 tasks
/brana:close
-- next session: /brana:sitrep picks up where you left off
```

### Research day

```
/brana:sitrep
/brana:research "Vercel QStash fan-out pattern"
-- scout agents run in parallel
-- findings stored in knowledge base
-- follow up with /brana:brainstorm or /brana:build when ready
/brana:close
```

### Backlog grooming

```
/brana:backlog status
/brana:backlog triage
-- brana re-evaluates priorities based on current state
-- adjust estimates, add context, unblock tasks
/brana:close
```

---

## Next steps

- [Sitrep](workflows/sitrep.md) — full breakdown of what sitrep shows and how to read it
- [Building Things](workflows/build.md) — build loop in detail
- [Sessions](workflows/session.md) — what happens at session start and end
- [Backlog](workflows/build.md) — task management patterns
- [Commands](commands/) — full command reference
