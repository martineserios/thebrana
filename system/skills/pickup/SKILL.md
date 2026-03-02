---
name: pickup
description: "Resume from last session — read handoff follow-ups, cross-ref task status, present actionable items. Use at session start to continue where you left off."
allowed-tools:
  - Read
  - Glob
  - Grep
  - Bash
---

# Pickup — Resume From Last Session

Reads the last session-handoff entry, extracts follow-up suggestions and next items, cross-references with tasks.json blocker status, and presents what's actionable now.

## Step 1: Find and read the last handoff

```bash
MEMORY_DIR=$(find ~/.claude/projects/ -maxdepth 2 -name "session-handoff.md" -path "*$(basename $(git rev-parse --show-toplevel))*" -exec dirname {} \; 2>/dev/null | head -1)
```

Read `$MEMORY_DIR/session-handoff.md`. Find the **last section** (the most recent `## YYYY-MM-DD` heading). Extract:

- **Accomplished** — what was done
- **Next** — explicit next items
- **Follow-up suggestions** — from the session close report (may be inline or after the main sections)
- **Doc drift** — pending backprop or errata
- **Blockers** — anything flagged

Also check for flag files:
```bash
[ -f "$MEMORY_DIR/.needs-backprop" ] && cat "$MEMORY_DIR/.needs-backprop"
```

## Step 2: Cross-reference with tasks.json

If `{project-root}/.claude/tasks.json` exists:

1. Read it. For every task ID mentioned in the Next/Follow-up items (e.g., "t-054", "t-032"), check:
   - **status**: pending / in_progress / completed
   - **blocked_by**: list of blocker task IDs
   - For each blocker: is IT completed? If all blockers are completed, the task is actually unblocked.

2. Also scan for any tasks that became unblocked since last session (status=pending, all blocked_by items now completed).

3. Collect all pending tasks with NO blockers as "available work."

## Step 3: Present the pickup card

Output format:

```
PICKUP — {Project Name}
Last session: {date} — {brief label from heading}

LAST SESSION
{1-2 line summary of what was accomplished}

ACTIONABLE NOW
1. {item} — {source: "handoff" or "unblocked since last session"}
2. {item}
3. {item}

BLOCKED
- {item} ← blocked by {blocker-id}: {blocker-subject}
- {item} ← blocked by {blocker-id}: {blocker-subject}

DEFERRED
- {items from Follow-up that aren't task-linked, e.g., "quarterly GATE re-run"}
```

Sections with no items are omitted entirely.

## Step 4: Ask what to work on

After presenting the card, ask: "What do you want to tackle?"

Do NOT auto-start work. The user picks.

## Rules

1. **Read-only.** This skill reads handoff + tasks. It writes nothing.
2. **Fast.** No web searches, no agent spawning, no deep exploration. Reads 2 files, outputs 1 card.
3. **Last section only.** Never summarize the full handoff history — only the most recent entry.
4. **Task IDs are links.** When mentioning a task, include its ID and subject from tasks.json.
5. **No guessing.** If handoff has no Next section, say "No follow-ups recorded." Don't invent items.
