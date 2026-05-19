
# Sitrep — Situational Awareness

One command to answer: **Where am I? What was I doing? What's left? What's next?**

## Filters (optional args)

Sitrep accepts optional filter args after the skill name:

| Arg | Example | Applies to |
|-----|---------|-----------|
| `--tag <tag>` | `sitrep --tag harness-engineering` | Source 3, Next action |
| `--stream <stream>` | `sitrep --stream roadmap` | Source 3, Next action |
| `--kind <kind>` | `sitrep --kind feature` | Source 3, Next action |
| `--priority <p>` | `sitrep --priority P0` | Source 3, Next action |

Multiple filters combine with AND. When any filter is active, show a **Filter:** line in the output header and scope all backlog queries to the filter. The session handoff (Source 4) and git state (Source 2) are never filtered.

---

## When to use

- After context compression (conversation truncated)
- When confused about current progress or state
- Mid-session reorientation ("wait, what was I doing?")
- After returning from a tangent or interruption
- Proactively: anytime you're unsure whether to continue, stop, or switch

## Process

Gather from 7 sources in parallel, then synthesize into one snapshot. No writes — this is read-only.

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
git worktree list
git branch --merged main
```

Extract:
- **Current branch** → maps to task convention (`feat/t-NNN-*`, `fix/t-NNN-*`, etc.)
- **Uncommitted changes** → work in progress that needs committing or stashing
- **Recent commits** → what was just accomplished
- **Stashes** → forgotten work-in-progress
- **Worktrees** → parallel work streams from `git worktree list`; cross-check each worktree's branch against `git branch --merged main`. If any worktree branch appears in the merged list, surface a warning: `⚠ Worktree <path> is on a merged branch — run \`git worktree remove <path>\` to clean up.`

### 3. Active backlog task

Prefer MCP: `backlog_query(status: "in_progress", tag: <if provided>, stream: <if provided>, kind: <if provided>, priority: <if provided>)`. Fallback:
```bash
brana backlog query --status in_progress [--tag <tag>] [--stream <stream>] [--kind <kind>] [--priority <p>]
```

Apply any active filters to this query. If no in_progress tasks match the filter, also check for pending tasks matching the filter to surface what's next in that area.

For each in_progress task, extract:
- `id`, `subject`, `strategy`, `build_step`, `branch`
- `context` — tactical details appended via `brana backlog set context --append` (cross-session continuity)
- `build_step` tells you exactly where in the /brana:build loop you are

If the task has a non-empty `context` field, display it under the active task in the output. Also check top-focus tasks (from `backlog_focus` or `brana backlog next`) for context.

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

**Also surface these fields when non-trivial (belt-and-suspenders for items that may not have reached next[]):**
- `backprop.needed: true` + `backprop.files` non-empty → show: "Backprop needed for: {files}"
- `doc_drift.stale_docs` non-empty → show: "Stale docs from last session: {list}"
- `state.test_status.failing > 0` → show: "⚠ {N} failing tests at last close"

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
{if filter active: **Filter:** --tag <tag> | --stream <stream> | ...}
{if any worktree on merged branch: ⚠ Worktree <path> is on a merged branch — run `git worktree remove <path>` to clean up.}

**Active task:** {id} "{subject}" — strategy: {strategy}, build_step: {build_step}
**Context:** {task context field, if present — show for in_progress and top-focus tasks}
**Active skill:** {skill name from CC Tasks, or "none"}
  Step: {current step} ({N}/{total} complete)

**Recent:** {last 2-3 commits, one line each}

**Previous session next:**
- {from session state next[] array, with [category] prefix}

{if backprop.needed and files: **Backprop needed:** {backprop.files — comma-separated}}
{if doc_drift.stale_docs non-empty: **Stale docs:** {list — shown even if already in next[]}}
{if state.test_status.failing > 0: ⚠ **Failing tests at last close:** {N}}

**Next action:** {single clear sentence — what to do RIGHT NOW}
```

### Next action logic

Determine the single most important next action:

1. **If CC Task is `in_progress`:** "Resume {step} of /brana:{skill}."
2. **If build_step is set on active task:** "Continue {build_step} step of /brana:build for {task-id}."
3. **If uncommitted changes exist:** "Commit or stash {N} uncommitted files before proceeding."
4. **If no active task but session state has next[]:** "Pick up from previous session: {first next item}."
5. **If filter active and pending tasks match filter:** "Next in {filter}: {task-id} '{subject}'. Run `/brana:backlog start {task-id}`."
6. **If nothing active:** "No active work. Run `backlog_focus()` (MCP) or `brana backlog next` to pick a task."

---

## Rules

1. **Read-only.** Never modify files, tasks, or git state. Just observe and report.
2. **Fast.** All 7 sources gathered in parallel. No deep analysis — surface-level scan.
3. **Actionable.** Always end with a concrete "Next action" — never just a status dump.
4. **Honest.** If you can't determine something, say so: "Build step unknown — task may have been started in a prior session."
5. **No step registry.** This is a single-step command. No CC Tasks needed for sitrep itself.
