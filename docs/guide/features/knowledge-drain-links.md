# `brana knowledge drain-links`

Drains pending `link`-tagged backlog tasks through `process-url`, and completes
**only** those whose content actually reached the knowledge base.

Replaces `personal/deploy/research-extraction.sh` (t-2557).

## Usage

```bash
# Drain the current project's backlog, 3 links this run
brana knowledge drain-links

# Another project's backlog, larger batch
brana knowledge drain-links --file ~/enter_thebrana/personal/.claude/tasks.json --cap 10

# See what would be drained — no fetches, no writes
brana knowledge drain-links --dry-run
```

| Flag | Default | Meaning |
|---|---|---|
| `--file` | current project's `tasks.json` | Which backlog to drain |
| `--cap` | `3` | Max links this run; the rest stay pending |
| `--dry-run` | off | List selections and exit |

## What it does

1. Selects `pending` tasks tagged `link` whose `context` carries a `URL: {url}`
   marker (written by `process-link-queue.sh`).
2. Takes up to `--cap` of them.
3. Runs each through `process-url`: fetch → extract → store under
   `knowledge:url:{slug}` in the ruflo `knowledge` namespace.
4. Marks a task `completed` **only** when the content reached the store.

Everything else is left `pending`, with the reason printed.

## Completion follows the artifact, not the exit code

This is the point of the command.

| Outcome | Task |
|---|---|
| `Store` — content fetched and stored | **completed** |
| `AlreadyStored` — key already present | **completed** |
| `EmptyContent` — fetched, too thin to store | left pending |
| `NotFound` — post not in the author's feed | left pending |
| fetch/store error | left pending, run exits non-zero |

The bash this replaces ran `claude -p ... >/dev/null 2>&1` and marked the task
completed whenever that exited `0`. `/brana:research` exits `0` on a bare link
without persisting anything, so links drained into `completed` with zero
knowledge captured — 33 of them were on course to vanish that way
(personal-repo t-1366, P0). Exit status is not evidence that work happened.

## Why a cap and no watermark

`process-url` short-circuits on an already-stored key, so re-scanning what a
previous run skipped costs one cheap idempotency probe per link. There is no
watermark to advance and none to corrupt: run it as often as you like, and a
capped run is safe to repeat (`pattern_per-run-cap-backlog-draining`, t-2076).

## Locking

The tasks lock is taken twice — once to select, once to write completions —
and **never held across the network**. A 27-link batch runs for minutes;
holding the sidecar lock through it would stall every other writer of that
backlog, including the capture script feeding it.

## Prerequisites

- `ruflo` on `PATH` (storage + the idempotency probe)
- LinkedIn URLs additionally need a one-time `linkedin-scraper-mcp --login`

> **Known limitation (t-2568):** the LinkedIn tier-2 fetch currently times out
> at 240s even with a valid session, so LinkedIn links fail and stay pending.
> `drain-links` behaves correctly under this — nothing is falsely completed —
> but it cannot yet drain the LinkedIn backlog. Public URLs are unaffected.

## Scheduling

Not wired to the scheduler yet — that is t-2560, which also retires the bash
script. Do not re-enable `brana-sched-link-research-extraction.timer` before
both t-2557 and t-2568 land.

## See also

- [`knowledge-process-url.md`](knowledge-process-url.md) — the per-URL command this wraps
- [ADR-070](../../architecture/decisions/ADR-070-knowledge-process-url-headless-fetch.md) — the fetch design
