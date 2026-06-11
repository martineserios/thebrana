# Async Close — what changed about ending a session

`/brana:close` is now instant by default. Sessions that used to trigger the multi-minute FULL debrief instead snapshot their diff, queue it, write the handoff, and finish in ~30 seconds. A nightly cron (02:00) does the learning extraction and the results greet you at your next session start.

## What you see

**At close** (code session):

```
Close mode: INSTANT
queued: abc123..def456 → ~/.claude/sessions/snap-20260611-2315.diff
```

**At the next session start**, when there's something to see:

```
[Reminders] Reminders: 3 pending (1 high). brana remind list
[Yesterday] 4 learning(s) extracted overnight. Review: ~/.claude/sessions/daily-summary-2026-06-12.md
```

Both lines are silent when there's nothing — zero startup noise.

## Close modes

| You did | Mode | What happens |
|---------|------|--------------|
| tiny state/doc commit | NANO | handoff only — nothing queued |
| doc/state spread | LIGHT | handoff + queued + quick inline scan |
| real code work | INSTANT | snapshot + queued + handoff (the new default) |
| `/brana:close --full` | FULL | the old deep in-session debrief, plus queueing |

## Reviewing what the cron found

Extracted learnings arrive as **reminders** (tagged `extraction`), not as automatic memory writes — you decide what's worth keeping:

```bash
brana remind list                      # see them (applies snooze-expiry too)
brana remind resolve <id>              # reviewed, done
brana remind snooze <id> 3d            # not now
cat ~/.claude/sessions/daily-summary-$(date +%F).md   # the narrative version
```

LARGE/novel findings come in at high priority; routine ones at low. Repeated findings increment an occurrences counter instead of duplicating.

## Checking the pipeline is healthy

```bash
brana ops logs close-extraction        # per-run: processed=N failed=N stale=N
brana close-queue list --unprocessed   # what's waiting for tonight
brana close-queue list                 # full queue incl. failed/retry state
```

Self-monitoring is built in: if the cron silently stops, entries age past 3 days and a stale-queue reminder appears at session start on its own. Extraction failures retry once per night; after 3 strikes you get a high-priority failure reminder instead of silent loss.

## Escape hatches

- `--full` — full in-session debrief, exactly as before
- `--light` / `--nano` — force a lighter mode
- The queue and snapshots are plain files under `~/.claude/` — nothing is hidden

## See also

- Tech doc: [async-close](../../architecture/features/async-close.md)
- Decisions: [ADR-052](../../architecture/decisions/ADR-052-close-queue-architecture.md), [ADR-051](../../architecture/decisions/ADR-051-reminder-store-architecture.md)
- Reminder system guide: [reminder-system](reminder-system.md)
