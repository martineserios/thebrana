---
name: personal-check
description: "Personal life check — tasks, life areas, journal freshness. Use at session start for personal priorities."
allowed-tools:
  - Read
  - Glob
  - Grep
  - Bash
---

# Personal Check — Life OS Focus Card

Read-only scan of `~/enter_thebrana/personal/` that surfaces personal tasks, life area health, and journal freshness. Produces a compact focus card.

## When to use

At session start for personal priorities, or anytime you want a quick personal status check. Works from any CWD — paths are absolute.

---

## Step 1: Check personal/ exists

```bash
PERSONAL="$HOME/enter_thebrana/personal"
[ -d "$PERSONAL" ] || { echo "No personal/ directory found at $PERSONAL"; exit 0; }
```

If the directory doesn't exist, output "Personal Life OS not set up — run /personal-check from enter to initialize." and stop.

---

## Step 2: Surface active tasks

Read `$PERSONAL/tasks.md`. Extract the Active table rows.

- Count total active tasks
- Flag any with status "overdue" or past due date
- Show top 3 active tasks (by table order)

If file doesn't exist or Active section is empty, note "No active personal tasks."

---

## Step 3: Check life areas

Read `$PERSONAL/life.md`.

- Check file modification date:
  ```bash
  stat -c %Y "$PERSONAL/life.md" 2>/dev/null
  ```
- If last modified >90 days ago, flag as stale: "Life areas not reviewed in {N} days — consider a quarterly review."
- Show any areas rated <5 (need attention)
- If no ratings filled in (all "—"), note "Life areas not yet rated — fill in 1-10 ratings when ready."

---

## Step 4: Check journal freshness

```bash
# Find the most recent journal entry
ls -t "$PERSONAL/journal/"*.md 2>/dev/null | head -1
```

- Parse the week number and date range from the filename and header
- If the most recent entry is >14 days old, flag: "No journal entry in {N} days — consider writing this week's 3Ls."
- If no journal entries exist, note "No journal entries yet."

---

## Step 5: Output focus card

```
PERSONAL CHECK — {date}

TASKS ({N} active)
1. {task 1}
2. {task 2}
3. {task 3}
{Overdue: {task} — due {date}}

LIFE AREAS
{Areas rated <5, or "All areas healthy" if none <5, or "Not yet rated" if all —}
{Stale warning if >90d}

JOURNAL
Last entry: {week} ({date range})
{Freshness warning if >14d}
```

Keep it compact — this is a glance, not a deep dive.

---

## Rules

- **Read-only.** Never modify tasks.md, life.md, or journal files. Only read and present.
- **Absolute paths.** Always use `$HOME/enter_thebrana/personal/` — this skill runs from any CWD.
- **Graceful absence.** If personal/ doesn't exist, say so and stop. No errors, no setup prompts.
- **Compact output.** The focus card should be <20 lines. This is a quick check, not a report.
