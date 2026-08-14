---
name: sitrep
description: "Situational awareness — where am I, what was I doing, what's next. Context recovery after compression, confusion, or mid-session reorientation."
effort: low
keywords: [status, context, recovery, orientation, compression, where-am-i]
task_strategies: [investigation]
stream_affinity: [roadmap, tech-debt]
argument-hint: "[--tag <tag>] [--stream <stream>] [--kind <kind>] [--priority <p>]"
group: core
model: haiku
allowed-tools:
  - Bash
  - Read
  - Glob
  - Grep
  - Task
  - AskUserQuestion
  - mcp__ruflo__hooks_intelligence_pattern-search
  - mcp__ruflo__memory_search_unified
  - mcp__brana__session_history
  - ToolSearch
status: stable
growth_stage: evergreen
---
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

<!-- ruflo preamble -->
ToolSearch("select:mcp__ruflo__memory_search_unified,mcp__brana__session_history")

## Process

Gather from 6 sources in parallel, then synthesize into one snapshot. No writes — this is read-only.

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

**Contention probe (t-2578) — run before recommending ANY worktree.** Merged-ness is not
liveness: a worktree can be unmerged, healthy, and *occupied by another live session right now*.
For each worktree other than the current one:

```bash
git log -1 --format='%cr|%h|%s' <worktree-branch>
```

If its last commit is **under ~30 minutes old**, mark it `CONTENDED` and treat it as
**off-limits**: exclude it from the "Next action" line, never say "worktree already cut" as if
that were an advantage, and never suggest `cd`-ing into it. Surface it instead as:

```
⚠ CONTENDED  <path> (<branch>) — last commit <N>m ago, another session is likely live there
```

Entering an occupied checkout puts two sessions in one working tree — the harm class behind the
`git worktree` HARD RULE in `git-discipline.md` (t-2216/t-2206). A worktree being *already cut*
is only an advantage when nobody is standing in it. When a task's only ready worktree is
contended, recommend a different task rather than a different directory.

The 30-minute figure is a heuristic, not a measurement — prefer a real lane key once ADR-069
(lane identity) lands, and drop this probe then.

### 3. Active backlog task

**Use the projected CLI form for this call — it is the primary, not the fallback (t-2578).**
Task bodies are large and sitrep renders ~5 fields per task, so the unprojected call is almost
all waste:

```bash
brana backlog query --status in_progress [--tag <tag>] [--kind <kind>] [--priority <p>] --output json \
  | jq -r '.[] | "\(.id) | \(.priority)/\(.effort) | \(.build_step // "-") | \(.branch // "-") | \(.subject[0:45])"'
```

Measured 2026-07-31 on the same 5-task result: unprojected `backlog_query` returned **41,781
chars (~13.6k tokens, ~15% of the window)** before sitrep emitted a single line; the projection
above returned **462 chars** — 90x less, identical table. This is a *projection* concern, not an
MCP-vs-CLI one: the general "prefer MCP" rule in `backlog/SKILL.md` still stands everywhere else.
Use `backlog_query` here only if the CLI is unavailable.

Apply any active filters to this query. If no in_progress tasks match the filter, also check for pending tasks matching the filter to surface what's next in that area.

For each in_progress task, extract:
- `id`, `subject`, `strategy`, `build_step`, `branch`
- `build_step` tells you exactly where in the /brana:build loop you are

**Fetch `context` per-task, on demand — never in bulk.** `context` is the largest field and the
main reason the unprojected query is expensive. Pull it only for the 1-2 tasks you are about to
recommend or display:

```bash
brana backlog get <id> --field context
```

**Completion-marker guard (t-2578) — check before recommending a resume.** `build_step` is a
*lagging* field: it records where the loop last was, not whether the work is done. `context` is
the evidence and it wins. Before proposing `/brana:build` on any task, scan its `context` for a
completion marker — `RESOLVED`, `SHIPPED`, `LIVE VERIFICATION`, `AC-<n> ... verified`, "all ACs
met". If one is present:

- do **not** recommend resuming the build
- recommend **"needs merge/close"** instead, and say which commits are unmerged
  (`git rev-list --count <base>..<branch>`)
- note that the owning session may still be mid-flight — closing another lane's task is its call,
  not yours

Live failure this guards (2026-07-31): sitrep read `t-2568 in_progress, build_step=fix` and
recommended `/brana:build`, while the very task dump it printed said
*"RESOLVED — ... SHIPPED ... LIVE VERIFICATION ... AC-2 key verified ... Suite: workspace green"*.
The task flipped to `completed` minutes later. Same failure shape as treating a drift-checker
warning as a work order: trusting a field over the evidence that supersedes it.

If the task has a non-empty `context` field, display it under the active task in the output. Also check top-focus tasks (from `backlog_focus` or `brana backlog next`) for context.

### 4. Session state (previous session)

```bash
brana session read --all --json
```

Returns a JSON array of `{epic, state}` objects — one per epic-scoped session file written in the last 30 days.  
- `epic` is the slug string (e.g. `"session"`, `"harness"`) or `"(orphan)"` for closes from `main` or non-epic branches.
- If only one block is returned, behaviour is identical to the previous single-file read (no regression).
- When multiple blocks are returned, render each under its own section header: `=== {epic} ===`.

If `--all` returns an empty array, fall back to `brana session read --json` (current-branch only), then to `brana handoff last` (legacy markdown).

For each `state` block, extract structured fields directly:
- **accomplished** → what was already done (array of strings)
- **next** → planned follow-ups (array of `{text, task_id, category}`)
- **blockers** → anything stalling progress (array of `{text, task_id}`)
- **consumed_at** → if non-null, this state was already loaded by session-start (don't re-present). The `consumed_at` check applies **per-epic block** — a consumed epic block is still shown but de-emphasised.
- **metrics** → session flywheel metrics (events, corrections, test writes)

**Task-ID staleness filter** — before displaying `next[]` items, suppress stale references:
For each item where `task_id` is non-null:
```bash
brana backlog get {task_id} 2>/dev/null | jq -r '.status // empty'
```
If status is `completed` or `cancelled`, suppress the item from display. If any items were filtered, append `({N} already done — not shown)` to the "Previous session next:" block header. This prevents completed tasks from surfacing as open follow-ups across sessions.

**Also surface these fields when non-trivial (belt-and-suspenders for items that may not have reached next[]):**
- `backprop.needed: true` + `backprop.files` non-empty → show: "Backprop needed for: {files}"
- `doc_drift.stale_docs` non-empty → show: "Stale docs from last session: {list}"
- `state.test_status.failing > 0` → show: "⚠ {N} failing tests at last close"

**4a. Same-day session-history recovery (belt-and-suspenders):**

Call session history to catch any same-day closes whose `next[]` items may have been missed if the merge path was bypassed:

```
mcp__brana__session_history(limit: 3)
```

Or CLI fallback: `brana session history --limit 3 --json`

Filter the returned entries to those whose `written_at` date (local timezone) matches today's date. For each same-day entry, check if any of its `next[]` items are absent from the current session-state `next[]` (compare by text and task_id). Surface any unique items under a separate "Also from earlier today:" block — do not merge them into the primary next[] display to avoid confusion with the authoritative merged state.

Skip silently if session history returns nothing or no same-day entries exist.

**4b. Epic accumulator (if session has epic field):**

Resolve `$INITIATIVE_SLUG` via two sources in order (first hit wins):
1. **Session JSON** — `epic` field in the session state (set by close Step 9c)
2. **Session-start marker** (fallback, when session JSON lacks the field):
   ```bash
   brana session epic read-marker 2>/dev/null
   ```
   Use this when the active task was started in the current session (marker written by `brana run`) but not yet closed (no session-state.json epic field).

If `$INITIATIVE_SLUG` is non-empty, load the cross-day arc:
```bash
brana session epic read "$INITIATIVE_SLUG" --json
```

Surface in the sitrep output:
- **Epic:** `{slug}` — {sessions_count} sessions, last closed {last_closed}
- **Arc accomplished ({N}):** first 3 items from `acc.accomplished[]`
- **Open next ({N}):** items from `acc.next[]` with non-completed task_ids (apply the same task-ID staleness filter from Source 4 — suppress completed/cancelled items; these span multiple sessions)
- **Recently resolved ({N}):** last 3 from `acc.resolved[]`

If `brana session epic read` returns nothing (epic not yet seeded), skip silently.

### 5. Conversation scan

Review the last few conversation turns for:
- Last skill invoked (e.g., `/brana:build`, `/brana:close`)
- Last user instruction that hasn't been completed
- Any "do X next" or "after that, Y" signals

### Source 6 — Memory context (ruflo)

```
mcp__ruflo__memory_search_unified(
  query: "{TASK_SUBJECT} {BRANCH}",
  namespace: "pattern",
  limit: 3
)
```

**Output rules:**
- Suppress memory results with similarity < 0.25
- If all results below threshold, omit the memory context block entirely
- Use plain-language labels: "from past sessions" not "[episodic]"
- If a correction pattern matches current task, surface it explicitly

```markdown
**Memory context:**
- {pattern description, similarity: 0.35} — from past sessions
- Note: past correction on this topic — {correction}
```

**Fallback:** If MCP unavailable, skip Source 6 entirely. Sitrep works as today — local-only.

> **Removed 2026-08-12 (t-2754):** a "Source 7 — Cross-session awareness" via `claims_board`/`hive-mind_memory` used to run here. Both are in-memory stores that reset on every ruflo MCP restart (a new session gets a fresh server process), so they structurally cannot answer "what's active in *other* sessions" — the one thing this source existed for. `autopilot_predict` (the "shadow" line above) is removed for the same reason: hardcoded `confidence: 0.5, reason: "Heuristic (learning not available)"`, live-verified 2026-08-12. See ADR-059 and `field-note_ruflo-agentic-layer-subscription-theater`.

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

**Previous session next:** {if any task_id items filtered: ({N} already done — not shown)}
- {from session state next[] array, with [category] prefix — completed/cancelled task_ids suppressed}

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
