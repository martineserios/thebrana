# Reminders — brana remind

A per-user reminder store (`~/.claude/reminders.json`) that hooks and cron jobs write to, and that session start surfaces. Safe under parallel Claude Code sessions — all writes go through the Rust CLI with file locking.

## Quick Start

```bash
# Write a reminder
brana remind write --text "edited hooks 3x — run validate" --action "./validate.sh" --priority high

# See what's pending (also applies snooze-expiry / 30-day expiry transitions)
brana remind list
brana remind list --status pending

# Act on one
brana remind resolve r-3fa9c2d1e0b4a7f2
brana remind snooze r-3fa9c2d1e0b4a7f2 3d     # durations: 1d, 3d, 1w, 2h
```

At the next session start you'll see, when anything is pending:

```
[Reminders] Reminders: 2 pending (1 high). brana remind list
```

Silent when there's nothing pending — zero startup noise, ~2ms cost.

## Writing from hooks

Source the wrapper and call `write_reminder` — one line, never blocks:

```bash
source "$SCRIPT_DIR/lib/remind.sh"
write_reminder --text "edited hooks 3x — run validate" \
    --action "./validate.sh" --priority medium --dedup-key hooks-validate
```

If the brana binary is missing, the wrapper warns to stderr and returns 0 — hooks degrade gracefully instead of failing.

## Dedup and escalation

Pass `--dedup-key` for recurring events. A matching pending/snoozed reminder gets its `occurrences` counter incremented instead of creating a duplicate; at 3 occurrences a `medium` reminder auto-escalates to `high`. Resolved reminders don't absorb new writes — the event recurring after resolution creates a fresh entry.

## Flags for `brana remind write`

| Flag | Required | Meaning |
|------|----------|---------|
| `--text` | yes | What to surface to the human |
| `--action` | no | Suggested command to run |
| `--priority` | no | `low` / `medium` (default) / `high` |
| `--dedup-key` | no | Recurrence key — see dedup above |
| `--project` | no | Originating project slug |
| `--tags` | no | Comma-separated tags |

## Lifecycle

`pending` → `resolved` (via `resolve`) or `snoozed` (via `snooze`, returns to `pending` when the duration lapses). Pending reminders older than 30 days flip to `expired`. Transitions are applied — and persisted — by `brana remind list`; the session-start count is a pure read and may lag slightly.

## See also

- Tech doc: [reminder-system](../../architecture/features/reminder-system.md)
- Decision: [ADR-051](../../architecture/decisions/ADR-051-reminder-store-architecture.md)
