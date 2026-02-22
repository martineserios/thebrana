---
name: weekly-review
description: "Weekly cadence review — portfolio health, zombie cleanup, metrics delta, ship log, and next-week planning with trend storage. Use every Friday or Monday for the weekly business and project review."
allowed-tools:
  - Read
  - Write
  - Glob
  - Grep
  - Bash
---

# Weekly Review

Non-negotiable weekly cadence: update the portfolio, kill zombies, compare metrics, log what shipped, and plan next week. The single highest-leverage meta-project practice for solo founders and small teams.

## When to use

Every Friday (end-of-week wrap) or Monday (start-of-week planning). Pick one day and never skip it. If you skipped last week, start with this week — don't try to reconstruct the past. 30 minutes is enough.

---

## Step 1: Portfolio Update

Scan all ventures/projects and classify each as green, yellow, or red.

### Gather data

```bash
# Check for portfolio file
for f in portfolio.md docs/portfolio.md ~/.claude/memory/portfolio.md; do
  [ -f "$f" ] && echo "Found portfolio: $f"
done

# Check for recent /morning outputs
[ -d "docs/daily" ] && ls -t docs/daily/ | head -7

# Check for /growth-check snapshots
[ -d "docs/metrics" ] && ls -t docs/metrics/ | head -5
```

### Classify each venture

For each project in the portfolio, assign status:

| Status | Meaning | Criteria |
|--------|---------|----------|
| **Green** | On track | Progress this week, no blockers |
| **Yellow** | Needs attention | Slowing down, minor blockers, drifting from plan |
| **Red** | At risk | Stalled, major blockers, or metrics declining |

Ask the user: "How does each venture feel right now? I have the data below — does this match your gut?"

Present a draft table and let the user override. Gut feel matters here — data confirms or challenges it, but the founder decides the color.

### Step 1b: Task progress delta (if tasks.json exists)

For each project with `.claude/tasks.json`:
1. Count tasks completed since last weekly snapshot (compare completed dates against 7 days ago)
2. Count tasks added (compare created dates against 7 days ago)
3. Compute phase progress change

Include in portfolio section:
  {project}: {tasks_completed} completed, {tasks_added} added, Phase {N}: {old%} -> {new%}

### Step 1c: Personal life areas (if personal/ exists)

```bash
PERSONAL="$HOME/enter_thebrana/personal"
[ -d "$PERSONAL" ] && [ -f "$PERSONAL/life.md" ]
```

If yes:
1. Read `$PERSONAL/life.md` — extract area ratings
2. Surface any areas rated <5 (need attention)
3. Check file modification date — flag if >90 days stale

Include in portfolio section:

   **Personal areas needing attention:**
   - {area}: {rating}/10
   {Stale warning if >90d since last review}

If all areas are healthy (>=5) or unrated, note "Personal areas: OK" or "Personal areas: not yet rated."

If personal/ doesn't exist: skip silently.

---

## Step 2: Kill Zombies

Find initiatives, projects, or tasks that have been untouched for 2+ weeks.

### Detection

```bash
# Git: files not touched in 14+ days
find docs/ -name "*.md" -mtime +14 2>/dev/null | head -20

# Check for stale experiment logs
[ -d "docs/experiments" ] && find docs/experiments/ -name "*.md" -mtime +14 2>/dev/null

# Check task lists for items older than 2 weeks
[ -f "docs/tasks.md" ] && grep -n "TODO\|NEXT\|NOW" docs/tasks.md
```

Also check:
- Open experiments with no results recorded
- Pipeline deals with no activity
- Backlog items nobody has touched

### Present for decision

For each zombie, ask the user: **Kill or Commit?**

| Zombie | Last Activity | Decision |
|--------|--------------|----------|
| {initiative} | {date} | Kill / Commit (with next action) |

**Kill** = archive it, remove from active lists, free up mental bandwidth.
**Commit** = define a concrete next action and a deadline this week.

No third option. "Maybe later" is just a slower kill.

---

## Step 3: Metrics Delta

Compare this week's key metrics against last week's values.

### Gather metrics

```bash
# Find the two most recent metric snapshots
[ -d "docs/metrics" ] && ls -t docs/metrics/weekly-*.md 2>/dev/null | head -2

# Also check /growth-check snapshots
[ -d "docs/metrics" ] && ls -t docs/metrics/health-*.md 2>/dev/null | head -2
```

If structured snapshots exist, read the last two and compute deltas. If not, ask the user for this week's numbers on the 3-5 metrics that matter most for the current stage.

### Output delta table

| Metric | Last Week | This Week | Delta | Trend |
|--------|-----------|-----------|-------|-------|
| {metric} | {value} | {value} | {+/-} | up / flat / down |

Flag any metric that moved more than 10% in either direction. A flat week is fine — a flat month is a signal.

---

## Step 4: Ship Log

Record what was actually shipped this week.

### Gather evidence

```bash
# Git commits this week (all projects in current dir)
git log --oneline --since="7 days ago" --no-merges 2>/dev/null | head -20

# Check for recent experiment completions
[ -d "docs/experiments" ] && grep -rl "status.*complete\|result" docs/experiments/ 2>/dev/null

# Check for recent pipeline closes
[ -d "docs/pipeline" ] && grep -rl "status.*closed\|won" docs/pipeline/ 2>/dev/null
```

Also ask the user: "Anything you shipped this week that isn't in git? Conversations, decisions, launches, content?"

### Format

List each shipped item with one line:

```
## Shipped This Week

- {what was shipped} — {impact or context}
- {what was shipped} — {impact or context}
- {what was shipped} — {impact or context}
```

If nothing was shipped, that is a signal. Note it without judgment and move to planning.

---

## Step 5: Plan Next Week

Select 3-5 items for next week's Now list. No more than 5 — if everything is a priority, nothing is.

### Sources for candidates

1. Red/yellow items from the portfolio update (Step 1)
2. Committed zombies with deadlines (Step 2)
3. Declining metrics that need intervention (Step 3)
4. Backlog items (`docs/backlog.md`, GitHub issues, task list)
5. Carry-over from this week's unfinished Now items

### Prioritization

For each candidate, evaluate:
- **Impact** — what changes if this gets done?
- **Urgency** — what happens if it waits another week?
- **Effort** — can it realistically be done in one week?

### Output

```
## Next Week's Now (3-5 items)

1. {highest priority item} — {why now}
2. {item} — {why now}
3. {item} — {why now}
```

Get user confirmation. These become the focus for next week's `/morning` checks.

### Step 5b: Task-aware next week planning

When selecting Now items, prioritize:
1. In-progress tasks (already started, should finish)
2. Next unblocked tasks by priority
3. Open bugs by priority

Show task IDs so user can reference them: "t-008 Implement JWT middleware (P1, unblocked)"

---

## Step 6: Store Trends

Save the weekly snapshot for historical tracking and cross-session learning.

### Write weekly snapshot file

Create or update `docs/metrics/weekly-YYYY-MM-DD.md`:

```markdown
# Weekly Review — {YYYY-MM-DD}

## Portfolio Status

| Venture | Status | Notes |
|---------|--------|-------|
| {name} | Green/Yellow/Red | {one-line} |

## Zombies Killed

- {killed item} (was: {what it was})

## Zombies Committed

- {committed item} — next action: {action}, deadline: {date}

## Metrics Delta

| Metric | Last Week | This Week | Delta |
|--------|-----------|-----------|-------|
| {metric} | {value} | {value} | {+/-} |

## Shipped

- {item}

## Next Week's Now

1. {item}
2. {item}
3. {item}
```

### Store in ReasoningBank

```bash
source "$HOME/.claude/scripts/cf-env.sh"
```

If `$CF` is found:

```bash
cd "$HOME" && $CF memory store \
  -k "weekly-review:{PROJECT}:{YYYY-MM-DD}" \
  -v '{"type": "weekly-review", "date": "{YYYY-MM-DD}", "portfolio": {"green": N, "yellow": N, "red": N}, "zombies_killed": N, "zombies_committed": N, "items_shipped": N, "next_week_now": [...], "metrics_trending_up": [...], "metrics_trending_down": [...]}' \
  --namespace business \
  --tags "project:{PROJECT},type:weekly-review,week:{YYYY-WNN}"
```

Search for previous reviews to show multi-week trends:

```bash
cd "$HOME" && $CF memory search --query "weekly-review:{PROJECT}" --limit 8 2>/dev/null || true
```

Fallback: append summary to `~/.claude/projects/{project-hash}/memory/MEMORY.md`.

### Update portfolio file

If `~/.claude/memory/portfolio.md` exists, update the venture entries with the new green/yellow/red status from Step 1.

### GitHub Issues (Optional)

If `gh` CLI is available and the project has a GitHub repo, create issues for committed action items. Markdown snapshots remain the primary record — Issues provide a queryable secondary index.

```bash
if command -v gh &>/dev/null && gh repo view &>/dev/null 2>&1; then
    # Create labels (idempotent)
    for label in "source:weekly-review" "type:action-item" "priority:high"; do
        gh label create "$label" --force 2>/dev/null || true
    done

    # Issue for each committed zombie (from Step 2)
    # For each zombie the user chose "Commit":
    gh issue create \
      --title "Committed: {zombie item}" \
      --label "source:weekly-review,type:action-item,priority:high" \
      --body "Committed during weekly review {YYYY-MM-DD}. Next action: {action}. Deadline: {date}." \
      2>/dev/null || true

    # Issue for #1 priority Now item (from Step 5)
    gh issue create \
      --title "Priority: {#1 Now item}" \
      --label "source:weekly-review,type:action-item,priority:high" \
      --body "Top priority for week of {YYYY-MM-DD}. Why now: {reason}." \
      2>/dev/null || true
fi
```

Skip silently if `gh` is not installed or the project has no GitHub remote.

---

## Output Template

Present the complete review to the user:

```markdown
## Weekly Review: {YYYY-MM-DD}

### Portfolio

| Venture | Status | Notes |
|---------|--------|-------|
| {name} | {G/Y/R} | {one-line} |

### Zombies (2+ weeks untouched)

| Item | Last Activity | Decision |
|------|--------------|----------|
| {item} | {date} | Killed / Committed |

### Metrics Delta

| Metric | Last Week | This Week | Trend |
|--------|-----------|-----------|-------|
| {metric} | {value} | {value} | {arrow} |

### Shipped This Week

- {item} — {impact}

### Next Week's Now

1. {item}
2. {item}
3. {item}

---

*Snapshot saved to docs/metrics/weekly-{date}.md*
```

---

## Rules

- **Never skip the weekly review.** If time is short, do Steps 1 and 5 only (portfolio update + plan next week). The other steps can be abbreviated but these two are mandatory.
- **3-5 Now items maximum.** Resist the urge to plan more. Unfinished items carry over — that is useful information, not failure.
- **Kill aggressively.** Zombie projects consume mental bandwidth even when you are not working on them. Killing is a productive act.
- **Don't fabricate metrics.** If a metric is not tracked, mark it as "Not tracked" and suggest adding it. Never estimate or guess values.
- **Gut feel is valid data.** The portfolio colors combine data and intuition. If the numbers say green but the founder says yellow, it is yellow.
- **Store results in ReasoningBank when available, fall back to auto memory when not.**
- **Ask for clarification whenever you need it.** If the user's portfolio is unclear, metrics are ambiguous, or you are unsure which items qualify as zombies — ask.
