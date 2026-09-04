# Lane Identity — what changed about session-state and resume

Session handoffs used to resolve by guessing an epic from the current branch name. On `dev` — the branch every close lands on after merge — that guess never matches an epic-routed write, so a read silently returned a *different session's* state instead of failing. Reads, writes, and consume now resolve the same way; a miss is an error, never a silent substitution; and every session gets a **lane pin** recording which worktree/branch/task it belongs to.

## What you see

**At session start**, nothing new by default — a lane pin is written silently in the background (a file write, not a context line). If something goes wrong writing it, session start still completes normally; the pin is best-effort.

**On a genuine miss**, commands that used to succeed quietly now report the failure:

```
$ brana session read
Error: no session state found for this unit — nothing to read (any legacy handoff
shown above is not a substitute; re-check the branch/epic this session is on)
```

**Resuming into a lane:**

```
$ brana session lane resume
resuming via WorktreePath match — session_id abc123, worktree_path /path/to/worktree
```

## Commands

```bash
brana session lane init --session-id <id> [--task-id <id>]   # write this session's pin
brana session lane resume [--task-id <id>] [--json]          # resolve which lane to resume into
```

`lane init` runs automatically at session start (wired into the `SessionStart` hook) — you don't normally call it yourself. It's also the autonomous-bootstrap path: `claude -p` runs inside a sandbox that fires no `SessionStart` hook, so a runner launching one calls `lane init` from the host first. (As of this writing, `system/scripts/autonomous-runner.sh` doesn't call it yet — tracked separately, t-3301.)

`lane resume` ranks candidate lanes **worktree_path > branch > task_id** and returns at most one. Ambiguity at a rank (two lanes tied) is a miss, not a coin-flip — it never silently falls through to a weaker rank that happens to resolve uniquely.

## What resolves through the marker now

`brana session read`, `brana session path`, and `brana session lane resume` all check the same initiative/focus marker (`brana session epic focus <slug>`) that `brana session write` already consulted for an epic-less payload — so a write routed via the focus marker is now findable by a plain read, which wasn't true before. Falls back to the old branch-only guess when no marker is set.

## Cleaning up stale pins

There's no `brana session lanes --prune` yet — a crashed session's pin file just sits in `{memory_dir}/lanes/` until removed by hand:

```bash
rm ~/.claude/projects/<encoded-project>/memory/lanes/<session_id>.json
```

Harmless to leave in place; a stale pin only matters if it happens to win a `resume` match.

## Reverting

The lane-pin mechanism is purely additive — no existing session-state file was renamed or reformatted to build it. To turn it off: remove the `lane init` call from `system/hooks/session-start.sh` and delete `{memory_dir}/lanes/`. Every session-state file underneath is untouched.

## Known follow-ups

- `brana session lanes --prune` (automatic stale-pin cleanup) — not yet built.
- Autonomous/sandboxed runs don't get a pin yet (t-3301) — the sandbox's `~/.claude/projects/` isn't bind-mounted, a decision that needs its own review before wiring `lane init` into the runner.
- `system/skills/close/phases/gate-and-evidence.md`'s CLOSE-ANCHOR-BLOCK and `session-state.md`'s Tier 0-3 epic-corroboration cascade were built to work around exactly the key-mismatch problem this feature closes — they're candidates for simplification now, flagged but not touched here (see [ADR-069](../../architecture/decisions/ADR-069-lane-identity-and-miss-semantics.md) Consequences).

## See also

- Tech doc: [lane-identity](../../architecture/features/lane-identity.md)
- Decision: [ADR-069](../../architecture/decisions/ADR-069-lane-identity-and-miss-semantics.md)
