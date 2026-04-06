
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

Prefer MCP: `backlog_query(status: "in_progress")`. Fallback:
```bash
brana backlog query --status in_progress
```

For each in_progress task, extract:
- `id`, `subject`, `strategy`, `build_step`, `branch`
- `build_step` tells you exactly where in the /brana:build loop you are

### 4. Session state (previous session)

```bash
brana session read --json
```

If JSON is available, extract structured fields directly:
- **accomplished** → what was already done (array of strings)
- **next** → planned follow-ups (array of `{text, task_id, category}`)
- **blockers** → anything stalling progress (array of `{text, task_id}`)
- **consumed_at** → if non-null, this state was already loaded by session-start (don't re-present)
- **metrics** → session flywheel metrics (events, corrections, test writes)

If `brana session read --json` returns nothing, fall back to `brana handoff last` (legacy markdown).

### 5. Conversation scan

Review the last few conversation turns for:
- Last skill invoked (e.g., `/brana:build`, `/brana:close`)
- Last user instruction that hasn't been completed
- Any "do X next" or "after that, Y" signals

### Source 6 — Memory context (ruflo)

Query ruflo for confidence-scored patterns related to current work:

```
mcp__ruflo__hooks_intelligence_pattern-search(
  query: "{TASK_SUBJECT} {BRANCH}",
  topK: 3,
  minConfidence: 0.3,
  namespace: "pattern"
)
```

**Output rules:**
- Suppress results below 0.25 similarity
- If all results below threshold, omit this section entirely
- Use plain-language labels: "from past sessions" not "[episodic]"
- If a correction pattern matches current task, surface it explicitly

```markdown
**Memory context:**
- {pattern description, confidence: 0.35} — from past sessions
- Note: past correction on this topic — {correction}
```

**Fallback:** If MCP unavailable, skip Source 6 entirely. Sitrep works as today — local-only.

### Source 7 — Cross-session awareness (hive-mind)

Check if other sessions are active:
```
mcp__ruflo__hive-mind_memory(
  action: "list"
)
```
Filter for keys matching `client:*:build:*` or `client:*:session:*`.

**Output:** If active sessions found:
```markdown
**Active sessions:**
- {project}: building {task} on {branch} — {status}
```
If no active sessions or MCP unavailable, omit this section.

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

**Previous session next:**
- {from session state next[] array, with [category] prefix}

**Next action:** {single clear sentence — what to do RIGHT NOW}
```

### Next action logic

Determine the single most important next action:

1. **If CC Task is `in_progress`:** "Resume {step} of /brana:{skill}."
2. **If build_step is set on active task:** "Continue {build_step} step of /brana:build for {task-id}."
3. **If uncommitted changes exist:** "Commit or stash {N} uncommitted files before proceeding."
4. **If no active task but session state has next[]:** "Pick up from previous session: {first next item}."
5. **If nothing active:** "No active work. Run `backlog_focus()` (MCP) or `brana backlog next` to pick a task."

---

## Rules

1. **Read-only.** Never modify files, tasks, or git state. Just observe and report.
2. **Fast.** All 5 sources gathered in parallel. No deep analysis — surface-level scan.
3. **Actionable.** Always end with a concrete "Next action" — never just a status dump.
4. **Honest.** If you can't determine something, say so: "Build step unknown — task may have been started in a prior session."
5. **No step registry.** This is a single-step command. No CC Tasks needed for sitrep itself.
