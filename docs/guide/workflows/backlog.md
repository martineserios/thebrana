# Managing the Backlog

The backlog is where work lives between sessions. It's not just a task list — it's how you think about what matters and why.

## Quick start

```
/brana:backlog next          -- what should I work on right now?
/brana:backlog start t-42   -- begin this specific task
/brana:backlog add "..."    -- capture something before you forget
/brana:backlog status       -- how is the project progressing?
```

## The daily loop

At session start, `sitrep` already surfaces the top unblocked task. When you're ready to pick work:

```
/brana:backlog next                  -- top unblocked task by priority
/brana:backlog next --stream bugs    -- next bug specifically
/brana:backlog start t-88            -- start it (enters /brana:build for code tasks)
```

`start` wires the task to your branch, sets `status: in_progress`, and hands off to `/brana:build`. You don't run both — `start` calls `build`.

## Adding tasks with enough context

Bare task subjects rot. Add context at creation time so future-you (or future sessions) can pick up without re-reading code:

```
-- Bad
/brana:backlog add "Fix JWT refresh"

-- Good
/brana:backlog add "Fix JWT refresh — token issued at login, refresh call returns 401
after 1h. Reproduce: login, wait 61 min, call /refresh. Expected: 200. See #auth-bugs Slack."
```

For effort M+ tasks, always include reproduction steps, expected behavior, or decision rationale in the description. The `context` field is for ongoing notes (see below).

**Dedup before adding.** Search first:

```
/brana:backlog search "JWT"    -- check if it already exists
```

## Using the context field

The `context` field is a running notepad for a task — tactical details that accumulate across sessions:

```
/brana:backlog context t-88                           -- view current context
/brana:backlog add t-88 "tried approach X, failed because Y"   -- append a note
```

Or via MCP:
```
backlog_set(task_id: "t-88", field: "context", value: "tried X, failed because Y", append: true)
```

When a task spans multiple sessions, this field is what lets you resume without re-reading code. Update it at `/brana:close` time with what you tried, what blocked you, and where to pick up.

## Viewing progress

```
/brana:backlog status            -- current phase, progress bars, next task
/brana:backlog roadmap           -- full tree: phases → milestones → tasks
/brana:backlog status --all      -- cross-project view (all clients/ventures)
```

For a flat priority-sorted list (useful mid-session):

```
/brana:backlog status --unified
```

## Triage cadence

Run triage weekly to keep priorities honest:

```
/brana:backlog triage
```

Triage re-evaluates each pending task against current context: blockers resolved, priorities drifted, effort estimates off. It surfaces stale tasks (no activity for 30+ days) and asks what to do with them.

## Blocking and unblocking

```
brana backlog set t-88 blocked_by +t-77     -- mark t-88 blocked by t-77
brana backlog set t-88 blocked_by -t-77     -- unblock when t-77 is done
```

`/brana:backlog next` automatically skips blocked tasks. You never need to manually filter them out.

## Streams

Tasks belong to streams that reflect their nature:

| Stream | What goes here |
|--------|---------------|
| `roadmap` | Planned features and milestones |
| `bugs` | Things that are broken |
| `tech-debt` | Code quality, refactors, cleanup |
| `docs` | Documentation |
| `experiments` | Spikes, research, proof-of-concepts |
| `research` | Knowledge gathering |
| `personal` | Non-project personal tasks |

Filter by stream when you want to focus:

```
/brana:backlog next --stream bugs       -- only bugs
/brana:backlog status --stream roadmap  -- roadmap health
```

## How backlog connects to build

```
/brana:backlog start t-88     → enters /brana:build, sets build_step
                              → sitrep shows build_step in "Active task" line
                              → /brana:build CLOSE marks task completed
```

You don't complete tasks manually for code work. The build CLOSE step does it. For non-code tasks (research, meetings, decisions):

```
/brana:backlog done t-88      -- manual completion
```

## Key rules

- **Never read tasks.json directly** -- always use the CLI or MCP tools
- **Always dedup before adding** -- `backlog_search` first
- **Rich context beats bare subjects** -- effort M+ tasks need description + context
- **`start` calls `build`** -- don't run both separately
- **Triage weekly** -- stale priorities mislead `next`
