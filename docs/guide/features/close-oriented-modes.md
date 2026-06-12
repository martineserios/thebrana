# Oriented Close Modes

> `/brana:close` picks what runs from WHY you're closing. Shipped 2026-06-12 (t-1980, [ADR-053](../../architecture/decisions/ADR-053-close-oriented-modes.md)).

## The four modes

| You want to... | Type | What happens |
|---|---|---|
| Pause and resume later (context relief, task switch) | `/brana:close --continue` | Snapshot + queue + resumable handoff. Task stays `in_progress`, branch and stashes untouched. Seconds, not minutes. |
| Finish for good | `/brana:close --finish` | Snapshot + queue + handoff, task → `completed`, worktree/stash cleanup. Learnings extracted by the nightly cron. |
| Keep a discovery, regardless of task state | `/brana:close --patterns` | Errata + patterns extracted NOW, inline. Nothing else — no queue, no handoff, no task or git changes. |
| Abandon the approach | `/brana:close --abort "reason"` | Reason required. Branch archived as a pushed `aborted/*` tag, deleted, you land on main. Task back to `pending` with the reason on record. |

The classic weight flags (`--full`, `--light`, `--nano`) still work; an orientation flag beats them when both are given.

## Bare invocation — the picker

`/brana:close` with no flag never picks silently. The gate reads git state, task status, and the conversation, then asks — with the likeliest mode first and each option labeled with its flag:

```
How should this session close?
  ▸ Continue (--continue) (Recommended) — task in flight, dirty tree
    Finish (--finish) — branch merged to main
    ...
```

The labels are the learning path: after a few closes you know your flags and type them directly, skipping the picker entirely. When signals conflict (e.g. task `in_progress` but branch already merged — usually stale task state), no option is marked recommended.

`--patterns` never appears from git signals alone — git can't see "a discovery happened". It's offered only when the conversation shows pattern-worthy material, or when you type it.

## Mid-session closes

Closing is no longer end-of-session-only. The two-layer compaction guard:

1. **You'll be asked** — at 70–85% context with a task in flight, Claude offers `/brana:close --continue` before suggesting `/compact` (context-budget rule).
2. **Safety net** — even if compaction fires without a close, the pre-compact hook silently snapshots the session (idempotent per commit, never blocks compaction) so the nightly extraction loses nothing.

Running `--continue` several times in one day is correct usage: each close at a new HEAD queues another snapshot, and the nightly cron extracts from the whole arc.

## Recovering aborted work

```bash
git tag -l 'aborted/*'           # find the archive
git checkout aborted/t-NNN-slug-20260612
```

Tags are pushed at abort time; if the push fails (offline, no remote) the abort still completes but warns loudly that the archive is local-only.

## Deferred modes

`--block`, `--handoff`, and `--eod` (flush the extraction queue on demand) are designed but deferred until usage data justifies them — see ADR-053.
