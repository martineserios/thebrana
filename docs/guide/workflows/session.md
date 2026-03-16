# Sessions

Brana tracks your work across sessions -- what you did, what you learned, where to pick up next.

## Starting a session

Sessions start automatically. The `session-start.sh` hook fires on every SessionStart event and:

1. Derives project name from git root
2. Sets `BRANA_PROJECT` and `BRANA_SESSION_ID` environment variables
3. Searches ruflo memory for project-relevant patterns
4. Searches for high-confidence corrections (confidence >= 0.8)
5. Falls back to native auto memory (`~/.claude/projects/*/memory/MEMORY.md`) when ruflo unavailable
6. Reads `tasks.json` and injects task summary (current phase, progress, next unblocked task)
7. Checks self-learning flags (`.needs-backprop`, `pending-learnings.md`)
8. Detects venture projects and nudges the daily-ops agent

No command needed -- just start working.

## Ending a session

```
/brana:close              -- when you're done for the day
```

`/brana:close` automatically:

1. Gate checks if the session had changes (read-only sessions get minimal handoff)
2. Gathers evidence from git log and conversation
3. Spawns the debrief-analyst agent to classify findings (errata, learnings, issues, correction patterns, cascade patterns, test coverage gaps)
4. Writes errata entries to affected docs
5. Stores learnings as patterns in ruflo (or MEMORY.md fallback)
6. Detects doc drift from system file changes
7. Writes handoff note for the next session
8. Reports a summary

## Background processing (session-end.sh)

The `session-end.sh` hook responds immediately, then forks heavy processing:

- Reads accumulated session events from `/tmp/brana-session-{id}.jsonl`
- Computes 7 flywheel metrics: correction_rate, auto_fix_rate, test_write_rate, cascade_rate, test_pass_rate, lint_pass_rate, delegation_count
- Stores session summary to ruflo memory
- Auto-generates minimal handoff if not written today
- Cleans up temp files

## Handoff notes

Stored at `~/.claude/projects/{project}/memory/session-handoff.md`. Each entry captures:
- What was accomplished
- What was learned
- Current state (branch, files touched, tests)
- What to do next

Next session, the hook reads this and presents context automatically.

## Tips

- Say "done", "bye", or "closing" and brana auto-detects close mode
- Read-only sessions (no commits) get a minimal handoff -- no full debrief
- The system works even without ruflo -- handoff notes and auto memory are the fallback
