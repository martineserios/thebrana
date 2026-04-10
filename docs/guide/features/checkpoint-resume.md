# Checkpoint/Resume for Long Builds

If a `/brana:build` run crashes or the session closes mid-way, brana can resume from where it left off instead of restarting from scratch.

## How It Works

At the end of each major build phase (SPECIFY, DECOMPOSE, BUILD, etc.), brana writes a checkpoint to:

```
~/.claude/run-state/{task_id}.jsonl
```

When you restart the same task, brana reads this file and skips phases already completed:

```
⏩ Resuming t-1108 from checkpoint. Completed: LOAD, CLASSIFY, SPECIFY. Starting at DECOMPOSE.
```

On clean completion, the file is deleted automatically.

## Requirements

- Task must have an ID (started via `/brana:backlog start <id>`)
- Build size must be **Medium or Large** — Trivial/Small builds skip checkpoints

## Recovering a crashed build

1. Run `/brana:backlog start <id>` (same task ID as before)
2. Brana detects the run-state file and resumes from the last checkpoint
3. No action needed — it happens automatically

## Resetting a checkpoint

If you want to restart a build from the beginning (e.g., after changing direction):

```bash
rm ~/.claude/run-state/{task_id}.jsonl
# e.g.: rm ~/.claude/run-state/t-1108.jsonl
```

Or to clear all run-state:

```bash
rm -rf ~/.claude/run-state/
```

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| Build fast-forwarded past a step you want to redo | Delete the run-state file and restart |
| "⏩ Resuming" shown but wrong step skipped | Run-state file has stale data — delete and restart |
| No checkpoint behavior on a large build | Verify you started via `/brana:backlog start <id>`, not freeform |
