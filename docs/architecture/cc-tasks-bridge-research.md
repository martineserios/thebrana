# CC native Tasks bridge — research findings (t-2746)

Status: research spike, no implementation. Recommendation only.

## Question

Should brana pilot Claude Code's native Tasks feature
(`CLAUDE_CODE_TASK_LIST_ID`, backed by `TaskCreate`/`TaskList`/`TaskUpdate`/
`TaskGet`) so subagents and concurrent sessions can see the main session's
work state? Today, subagents spawned via the `Agent` tool operate blind to
`.claude/tasks.json` — they get whatever context is in their prompt, nothing
live.

Flagged as the highest-value untapped capability in
`knowledge:research:2026-05-19-cc-tasks-vs-ruflo-pm-evaluation`; reconfirmed
by a 2026-08-12 inbox research report (`research-report-1786533986536`,
processed and deleted per inbox-convention).

## What CC native Tasks actually is

A separate object model from brana's `tasks.json` — session-scoped, stored
under `~/.claude/tasks/`, broadcasting updates to every session sharing the
same `CLAUDE_CODE_TASK_LIST_ID`. It supports dependency edges (`blockedBy`/
`blocks`), status (`pending`/`in_progress`/`completed`), and ownership
(`owner` field for teammate claiming). It is designed for **in-session /
cross-subagent coordination during one unit of work**, not as a durable
project backlog — that's what `tasks.json` + the `brana` CLI already are,
with 2,600+ tasks, priorities, epics, effort, and a full lifecycle.

## Live evidence from this very session

This session used `TaskCreate`/`TaskUpdate` to track the 7-task
backlog-audit-2026-08 batch (see the task list carried through this
session). Two observations, gathered first-hand rather than from the
generic inbox report:

1. **Injection is automatic and repeats.** Every few tool calls, the harness
   injected a system-reminder dumping the full current task list back into
   context — even with only 7 tasks tracked. This is the exact mechanism
   `system/rules/context-budget.md` warns about: uncontrolled auto-injection
   competing with the 55%/70%/85% thresholds.
2. **It scales with list size, not session relevance.** The reminder dumps
   *all* tracked tasks each time, not just the one in flight. A list sized
   to this session's 7 items was already a repeating, multi-line injection.

## Recommendation

**Do not mirror `tasks.json` into CC native Tasks in bulk or continuously.**
A one-way sync from the 2,600+-task backlog (even filtered to "pending")
would turn every native-Tasks injection into a large, repeating context
cost — directly violating the context-economy constraint t-2484 is meant to
enforce ("assemble the exact context needed for the work at hand"). This
also isn't what native Tasks is for: it has no priority/epic/effort model,
no `brana` CLI parity, and syncing it bidirectionally with `tasks.json`
would recreate the two-sources-of-truth drift pattern ADR-065's Consequences
section already warns about (the same class of bug t-2765 exists to fix).

**Do formalize the narrow, already-effective pattern used manually in this
session**: at the start of a bounded multi-task or multi-subagent unit of
work (a `/brana:backlog execute` batch, or a `/brana:build` step that spawns
several subagents), create native CC Tasks for *only that batch* — a
handful of items, scoped and short-lived, not a mirror of the backlog. Set
`CLAUDE_CODE_TASK_LIST_ID` to something stable for the unit of work (e.g.
the epic slug or branch name) so subagents launched within it can see and
update shared state. This is a **one-way, ephemeral, batch-scoped mirror**,
not a bidirectional bridge — `tasks.json` stays the single source of truth
for anything that must survive past the current unit of work; native Tasks
is scratch coordination state for the duration of one batch.

Concrete follow-up (not this task's scope): a small step in
`system/skills/backlog/phases/execute.md` and/or `system/skills/build/
phases/build-loop.md` that creates native CC Tasks for the in-flight batch
only, sized to stay well under the context-budget thresholds, and never
attempts to sync the full backlog.

## What NOT to build

- A bidirectional sync between `tasks.json` and native Tasks — two sources
  of truth for the same state is the exact failure mode this project keeps
  re-discovering (ADR-065 consequences, t-2325, t-2765).
- Any full or filtered *mirror of the whole backlog* into native Tasks —
  the injection-size problem is real and already observable at 7 tasks; it
  does not scale to 2,600.
