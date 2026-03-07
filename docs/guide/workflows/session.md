# Sessions

Brana tracks your work across sessions — what you did, what you learned, where to pick up next.

## Starting a session

Sessions start automatically. The `session-start` hook:
- Recalls relevant patterns from memory
- Shows active tasks and next unblocked item
- Checks for flags from the previous session (doc drift, pending errata)
- Detects venture projects and nudges daily-ops

No command needed — just start working.

## Ending a session

```
/close              — when you're done for the day
```

`/close` automatically:
1. Gathers what you did (git log + conversation)
2. Extracts learnings and classifies them (errata, learnings, issues)
3. Writes a handoff note for the next session
4. Stores patterns in the knowledge system
5. Detects if system files changed (doc drift)
6. Suggests follow-ups

## Handoff notes

Stored at `~/.claude/projects/{project}/memory/session-handoff.md`. Each entry captures:
- What was accomplished
- What was learned
- Current state (branch, files touched, tests)
- What to do next

Next session, the hook reads this and presents context automatically.

## Tips

- Say "done", "bye", or "closing" and brana auto-detects close mode
- Read-only sessions (no commits) get a minimal handoff — no debrief needed
- The system works even without claude-flow — handoff notes are the fallback
