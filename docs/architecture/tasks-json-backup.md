# Backlog ledger backup (interim, ADR-094)

**Status:** live (interim until t-3326's per-write rotation and t-3287's git snapshot land)
**Script:** `system/scripts/tasks-json-backup.sh`
**Schedule:** hourly at :07 via the `tasks-json-backup` scheduler job (ADR-071 thin layer)
**Backups:** `~/.claude/tasks-json-backups/<basename>-<sha1(path)[:8]>/tasks.json.<UTC>.json`, newest 48 kept — dir keyed by the repo's resolved path (a `.repo` marker inside records it; restore refuses on mismatch), dirs 700 / copies 600 via `umask 077`; `--restore` accepts only a filename inside that dir or `--latest`
**Origin:** 2026-09-07 — a `git checkout main` in the shared main checkout silently overwrote the ignored,
untracked `.claude/tasks.json` (3199 tasks) with a stale tracked blob; the fast-forward that
followed deleted it. Recovered from a 7-hour-old commit. See
[ADR-094](decisions/ADR-094-tasks-json-ledger-in-git-common-dir.md).

## Why this exists

[ADR-091](decisions/ADR-091-tasks-json-untracked-canonical-snapshot.md) untracked the ledger
from git, which also removed the only history it had. Its snapshot half (t-3287) had not
shipped when the untracking half did. Until the structural fix (the ledger moves under
`.git/brana/`, t-3324) and the per-write backups (t-3326) land, this hourly copy is the only
automatic recovery path: any loss is bounded to one schedule tick.

## Usage

```bash
system/scripts/tasks-json-backup.sh                         # back up the cwd repo's ledger
system/scripts/tasks-json-backup.sh --list                  # newest first, with task counts
system/scripts/tasks-json-backup.sh --check                 # path · count · newest backup age; exit 2 on collapse
system/scripts/tasks-json-backup.sh --restore --latest      # restore newest (keeps a .pre-restore copy)
system/scripts/tasks-json-backup.sh --restore tasks.json.20260907T224600Z.json
```

`--repo <path>` targets another repo; `TASKS_JSON_BACKUP_DIR` and `MAX_BACKUPS` override the
defaults. The script resolves the ledger via `git rev-parse --git-common-dir`, so it works from
any worktree and already prefers `.git/brana/tasks.json` once ADR-094's relocation exists.

## Refusals (exit 2, backups untouched)

- ledger missing, or not valid ledger JSON;
- ledger reads **0 tasks while the newest backup has more** — a wiped ledger must never rotate
  the good copies out of the way. `--check` reports the same condition, which is what the
  session-start gauge (t-3332) and the post-checkout hook (t-3328) build on.

## Recovery drill

1. `system/scripts/tasks-json-backup.sh --check` — confirm the collapse.
2. `system/scripts/tasks-json-backup.sh --restore --latest`.
3. Replay edits made after the backup from session transcripts (`~/.claude/projects/*/…jsonl`,
   `mcp__brana__backlog_*` tool calls carry full arguments and results) — the 2026-09-07 recovery
   did exactly this; see `pattern_git-checkout-across-untracking-commit-wipes-shared-file`.

## Tests

`system/scripts/tests/test-tasks-json-backup.sh` — isolated scratch repo + scratch backup dir:
copy, rotation, refusal on a wiped ledger, `--check` exit code, `--restore --latest`, invalid
JSON, missing ledger, and preference for the `.git/brana/` location.
