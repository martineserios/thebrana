# Backlog: Session-Scoped Epic Focus

**Status:** stable · **Task:** t-3196 · **Since:** 2026-08-24

`brana backlog focus` boosts one epic's tasks to the top of the list. This guide covers how
that epic gets picked — and why there's no command to "set" it anymore.

## TL;DR

| You want to… | Command |
|---|---|
| See today's focus (epic auto-detected) | `brana backlog focus` |
| Focus a specific epic once, no state to manage | `brana backlog focus --epic <slug>` |
| Focus a different epic than what's boosted | Start a task under that epic (`/brana:backlog start <id>`), or pass `--epic` |
| See everything across projects | `brana backlog status --all` |

There is **no** `set-active` command. It was removed — see [Why the old command is gone](#why-the-old-command-is-gone).

## How resolution works

Focus resolves an epic in this order, every time you run it — nothing is stored between runs:

1. **`--epic <slug>`** — if you pass it, that's the answer. Always wins.
2. **The most-recently-started `in_progress` task's epic** — whichever task you started last
   (in this repo) is assumed to be what you're focused on right now. Its epic comes from:
   - its flat `epic` field, for client/venture projects (the older task schema), or
   - its epic-node ancestor via the task tree's `parent` chain, for thebrana's own tasks.
3. **Nothing** — if no task is in progress, or the one that is has no epic, focus just shows
   plain priority order (P0s and P1s first). No error, no epic header.

This is entirely derived from your own task state — nothing is written to disk to remember it,
and nothing another session does can change what *you* see.

## Why the old command is gone

The previous design (`active_epic` in `.claude/tasks-config.json`) stored one epic per
**project** — but epic focus is really a per-**session** concept. Two Claude Code sessions
opened from the same directory, each working a different epic, is the normal way this project
gets used — and under the old design, whichever session last ran `set-active` silently
redirected the *other* session's focus too. There was no way to have two honest answers to
"what am I working on" in one repo at once.

Session-scoped resolution fixes this by construction: what you see is derived from what
*you* started, not from a shared file any session can overwrite.

## Everyday effect

- **Start a task, get its epic boosted automatically.** `/brana:backlog start t-123` marks the
  task `in_progress` — the next `brana backlog focus` in that repo shows that task's epic
  first, no extra step.
- **Two sessions, two epics, same directory — both work correctly**, as long as each session
  has its own task in progress (the common case — one task per session is already how work
  gets done here).
- **Switching to a different task switches focus automatically.** Start a new task under a
  different epic, and the next `focus` call reflects it — no command to remember to run.
- **A one-off check of another epic** doesn't need to disturb anything: `brana backlog focus
  --epic other-epic` looks at it without touching what your in-progress task resolves to.

## Notes & limits

- **Nothing is in progress yet?** Focus shows plain priority order — same as it always has for
  a project with no epic set. Start a task, or pass `--epic` explicitly.
- **Two sessions sharing one checkout** (rather than each having its own worktree — the
  documented git-discipline convention for concurrent sessions) can still see each other's
  resolution shift, since both read "the most-recently-started in-progress task" from the same
  shared task list. This is the same assumption the statusline's epic badge has always made;
  it isn't new here. Use a worktree per session (the standing convention) to avoid it entirely.
- `active_initiative` (a separate value from `active_epic`) is unaffected by this change and
  still resolves from `tasks-config.json` as before.
- Full design rationale: [ADR-088](../../architecture/decisions/ADR-088-session-scoped-epic-focus.md).
