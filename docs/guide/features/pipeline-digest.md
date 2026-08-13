# Pipeline Digest (L0 Reporter)

A read-only gauge of your delivery pipeline: unmerged branches and their
merge-readiness, stale merged branches, inbox queue, and backlog pressure.
It reports; it never touches anything.

## Quick Start

One-off beat from the repo root:

```bash
./system/scripts/pipeline-digest.sh
```

Recurring gauge — start a **dedicated lean session** at the repo root and run:

```
/loop 30m follow system/loops/pipeline-digest.md
```

Read the current gauge any time:

```bash
cat ~/.claude/run-state/pipeline-digest/latest.md
```

## How It Works

Each beat the script sweeps local branches against `dev`:

- **Unmerged branches** — ahead/behind counts, conflict probe, last activity,
  and a **dirty worktree** flag when uncommitted changes sit in a branch's
  worktree.
- **Stale merged branches** — merged into `dev` but never deleted.
- **Inbox** — item count and names only. File contents are never read.
- **Backlog** — pending / in-progress counts, P0/P1 pending, and a stale-task
  excerpt.

It writes `latest.md` (the full gauge) and appends one summary line to
`history.jsonl` — the loop prompt compares consecutive lines and reports
"no change" in one line when nothing moved.

The gauge is L0 of the graduated-autonomy ladder: it earns trust before any
loop is allowed to prepare (L1) or merge (L2) on your behalf.

## Examples

```bash
$ ./system/scripts/pipeline-digest.sh | head -8
# Pipeline digest — 2026-08-13T23:04:07Z

Repo: /home/…/thebrana · base: dev

## Unmerged branches (6)

- `harness-core/chore/t-2622-wire-system-hooks-tests` — ahead 5 / behind 258 vs dev · merge: CONFLICTS · last activity: 10 days ago · **dirty worktree** (…/thebrana-t-2622)
```

```bash
$ tail -2 ~/.claude/run-state/pipeline-digest/history.jsonl
{"ts":"2026-08-13T23:04:07Z","unmerged":6,"stale_merged":4,"inbox":18}
{"ts":"2026-08-13T23:04:42Z","unmerged":6,"stale_merged":4,"inbox":18}
```

Point it at another repo or base branch:

```bash
BRANA_DIGEST_BASE=main ./system/scripts/pipeline-digest.sh /path/to/repo
```
