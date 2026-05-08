# Sitrep

**One command to answer: Where am I? What was I doing? What's next?**

```
/brana:sitrep
```

Run it at the start of every session. Run it when you're lost. Run it before switching tasks. It takes a few seconds and saves you from working in the wrong direction.

---

## What it shows

Sitrep gathers from 7 sources in parallel and presents a structured snapshot:

```
## Sitrep

Branch: feat/t-088-auth-middleware (t-088)
Uncommitted: 3 files
Worktrees: ../thebrana-t-091 (docs branch)

Active task: t-088 "Implement JWT auth middleware" — strategy: feature, build_step: build
Active skill: /brana:build
  Step: BUILD (4/6 complete)

Recent:
  a3f1b2c feat(auth): add JWT decode + claims extraction
  7d20e91 feat(auth): add token expiry validation

Previous session next:
  [implement] Write integration test for refresh token flow
  [blocked] t-089 "Add rate limiting" — blocked by t-088

Next action: Continue /brana:build BUILD — write integration test for refresh token flow.
```

### Sections explained

| Section | What it tells you |
|---------|------------------|
| **Branch** | Current git branch and the task ID it maps to |
| **Uncommitted** | Files changed but not committed — work in progress |
| **Worktrees** | Parallel work streams; flags merged branches to clean up |
| **Active task** | The in_progress task from your backlog, with build step |
| **Active skill** | Which multi-step skill is running and where you are in it |
| **Recent** | Last 2-3 commits — what was just accomplished |
| **Previous session next** | Follow-ups from the last session's handoff note |
| **Next action** | A single sentence: what to do right now |

---

## When to run it

**Start of session** — always. Even if you think you know what you were doing, sitrep may surface a stale worktree, an unread correction, or a task your last session planned and you forgot about.

**After context compression** — long conversations get truncated. Sitrep reconstructs your state from git and the backlog, not from conversation memory. It's the fastest way back.

**Mid-session reorientation** — if you went down a rabbit hole or got interrupted, sitrep answers "wait, what was the actual task?" in seconds.

**Before switching tasks** — check active task and uncommitted state before starting something new. Don't leave work half-done and undocumented.

---

## Reading the output

### Branch maps to task

If you're on `feat/t-088-auth-middleware`, sitrep knows you're working on t-088. It reads the task's `build_step` to tell you exactly where in the build loop you are. This works even after a context reset.

### Worktree warnings

If a worktree's branch appears in `git branch --merged main`, sitrep flags it:

```
⚠ Worktree ../thebrana-t-091 is on a merged branch — run `git worktree remove ../thebrana-t-091` to clean up.
```

Merged-branch worktrees are usually orphans from a previous session. Clean them up — they accumulate and cause confusion.

### Previous session next

The items under "Previous session next" come from `/brana:close`'s handoff note. If your last session ended with `/brana:close`, those planned follow-ups appear here. If it didn't end cleanly, this section may be empty or stale.

### Next action

Sitrep's single most useful output. It determines the next action by priority:

1. **Active CC Task in a skill flow** — if a step of `/brana:build` or another multi-step skill is in_progress, that's your next action
2. **Uncommitted changes** — if there's uncommitted work on a task branch, commit it
3. **In-progress backlog task** — continue that task
4. **Previous session next** — the first item from the handoff note
5. **Highest-priority unblocked task** — from `brana backlog next`

---

## Common outputs and what to do

**"Continue /brana:build BUILD"**
You were mid-task. Jump back in: `/brana:backlog start t-NNN` or just `/brana:build`.

**"Commit 3 uncommitted files on feat/t-088"**
Don't start something new. Stage and commit the in-progress work first.

**"Clean up worktree: ../project-feat-t-071 is on a merged branch"**
```bash
git worktree remove ../project-feat-t-071
git branch -d feat/t-071-slug
```

**"No active task. Next unblocked: t-093 (P1)"**
Start fresh: `/brana:backlog start t-093`.

**"Previous session planned: write refresh token test"**
That was what you left off. `/brana:backlog start t-088` to pick it up.

---

## Sitrep vs session start

The session-start hook fires automatically and shows a brief summary. Sitrep is the manual, detailed version:

| | Session start hook | `/brana:sitrep` |
|--|---|---|
| When | Automatic, on Claude Code launch | On-demand |
| Depth | Brief (task summary + key patterns) | Full (7 sources, structured output) |
| Use for | Quick context injection | Reorientation, detailed state |

Run sitrep when the session-start summary isn't enough.
