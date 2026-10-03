# Feature: brana-knowledge divergence merge and fetch-first backup guard

**Date:** 2026-10-03
**Status:** built (2026-10-03) — gates pending
**Task:** t-3435 (epic t-3372 macos-portability)
**ADR:** [ADR-095](../decisions/ADR-095-two-machine-memory-sync.md) §Amendment 2026-10-03

## Problem

Two machines run `backup.sh` against one `brana-knowledge/master`. The script commits a whole-store snapshot and pushes without fetching, so when the other machine has pushed first the push is rejected and every later close commits further onto the stale base. The first occurrence (2026-10-02) was resolved as "keep local", which silently dropped the Mac-authored sections of `patterns.md` (17 missing from the Linux live file; four-way union 121) and one `knowledge-staging.md` section. The ruflo stores lost nothing curated.

## Decision Record (frozen 2026-10-03)

> Do not modify after acceptance.

**Context:** ADR-095 already fixes the steady-state rule (per-entry files, newest wins, union for append-only notes) but its implementation (t-3404, t-3405) is pending. This task applies that rule once by hand and adds the smallest guard that makes the next divergence visible at the first close.
**Decision:** Restore the Mac-only notes and curated entries as a union commit keyed as ADR-095 prescribes. Make `backup.sh` fetch before exporting: fast-forward when only behind, refuse when diverged, warn and continue when offline. Record the applied rule in ADR-095 and in t-3404.
**Consequences:** No memory lost from the first divergence except machine-local telemetry, which ADR-095 excludes by design. Future divergence fails loudly before a commit exists. Whole-store ping-pong between machines remains for the ruflo exports until the ADR-095 revision's sync lands (t-3436; t-3404 cancelled 2026-10-03); the section-keyed notes no longer ping-pong.

**Amendment to the record (2026-10-03, user decision after the audit):** the restore is not a union *commit* but a union of the live Linux files plus union-on-export in `backup.sh` for the section-keyed notes, so the repo copy becomes the union at the next backup and stays one; the 2 `pattern`-namespace `error-recurrence:*` rows are Mac tool-failure counters and are treated as machine-local, not restored. Merge rule as chosen: "keep as much as possible, no duplicates" — union by identity, newest wins on a shared identity.

## Constraints

- Never `git pull --rebase` or `push --force` on brana-knowledge: both pick one machine's memory over the other's.
- `backup.sh` lives in the private brana-knowledge repo, not in thebrana. The thin invoker `system/scripts/backup-knowledge.sh` is unchanged.
- The guard must never lose a local backup: an offline fetch is a warning, not a stop.
- No memory content may enter the public thebrana repo (ADR-095 privacy boundary). This spec and the ADR carry counts and keys only.

## Scope (v1)

- Union of `patterns.md` (121 sections) and `knowledge-staging.md` (6) across Linux live, Linux snapshot, merged `HEAD` and Mac tip `b04be875`, written to the Linux live files (pre-union copies archived) and carried to the repo by the next export.
- `backup.sh` unions `patterns.md`, `knowledge-staging.md` and `portfolio.md` by heading with the tracked copy on export instead of copying over it; `restore.sh` fast-forwards through the same guard instead of a swallowed `git pull --rebase`.
- `merge-snapshots.py`: the rule as a tool for JSON (identity + newest wins) and markdown (section union), with `--check`.
- Fetch-first guard at the top of `backup.sh`, before any export.
- Shell tests with a bare origin and two clones: guard (behind-only, diverged, daily-push.sh, offline, in-sync), union on export, and the merge rule itself.
- ADR-095 amendment and t-3404 context pointer.
- Out of scope: ruflo-store convergence (ADR-095 revision, t-3436), notes slug mapping and pull direction (t-3405), session-start pull (t-3406).

## Research

- Key audit of `9cf4055f` vs Mac tip `b04be875`: memory-entries 6 Mac-only keys (2 session, 2 metrics, 2 pattern error-recurrence counters); patterns.json 0 lost by content identity; patterns.md 121-section union with 17 missing from the Linux live file; knowledge-staging.md 1 section; consolidation-log 0; project memories 624/624 kept.
- `patterns.json` `id` is `INTEGER PRIMARY KEY AUTOINCREMENT`: unusable as a merge key. Identity is `(task_type, approach, ts)`; `approach` alone is not unique (242 repeated pairs on one machine). Verified: 11,643 ∪ 11,539 rows → 11,596 identities, 0 Mac-only.
- ADR-095 §2 classes `session` and `metrics` as machine-local, never synced.

## Assumptions

- Behind-only is fast-forwarded (one line printed) rather than refused: chose fast-forward because refusing would fail every Linux close after any Mac push, with nothing local at risk. Confirmed by the user's plan approval 2026-10-03.
- Offline fetch continues to a local commit and the existing push-failure exit, as today. Confirmed 2026-10-03.
- Diverged exits 2 (integrity failure keeps exit 1) so callers can tell the two apart; `run_knowledge_backup()` treats both as a warning, not a halt.
- Union order on export is live-first (this machine's section order and body win on a shared heading), the tracked copy's new sections are appended: chose live-first because the local file is what the machine's own sessions edit — needs no confirmation, the content is identical either way.
- The 4 session/metrics rows and the 2 error-recurrence counters are not restored (ADR-095 §2). Confirmed by the user 2026-10-03.
- The Mac's step is `git pull --ff-only` only; its next export then unions instead of clobbering. The repo union is not copied onto the Mac's live files: the Mac is company-managed and tabz-only (ADR-095 revision, t-3436), so Linux-authored sections reach it only through the client allowlist (t-3418).
- Trust direction: the 17 Mac-authored sections merged into the owner machine's live `patterns.md` crossed lower-to-higher trust without the T1 import review (t-3416, not built). Accepted for this one-time pass on the user's approval of the heading list; reversible from `~/.claude/memory/archive/patterns_2026-10-03-pre-union.md`.

## Behavior

- Running `backup.sh` while the remote has commits this machine lacks and this machine has none of its own: the script fast-forwards, exports, commits, pushes as usual.
- Running it while both sides have commits: the script stops before exporting, prints the two tips and the command to resolve, exits non-zero. Nothing is committed.
- Running it offline: a one-line warning, then the normal local commit; the push fails as it does today.

## Edge Cases

- No `origin/<branch>` yet (first push ever) or the fetch fails: continue with a warning, behave as before.
- Dirty working tree when fast-forward is needed: `--ff-only` fails; treat as diverged (refuse, print resolution).
- Branch name: taken from `HEAD` (`master` when detached); the remote is always `origin`.
- `python3` missing (bare macOS without CLT): the union step falls back to a plain copy with a warning rather than failing the backup.

## Design

- `lib/remote-guard.sh` → `ensure_remote_base [branch]`, sourced by `backup.sh` (right after `cd`, before any export) and `daily-push.sh`: `git fetch origin <branch>`; ahead/behind counted with `git rev-list --count`; behind-only → `git merge --ff-only`; diverged → recipe on stderr, return 2; fetch failure → warning, return 0.
- Resolution recipe printed verbatim: `git merge origin/master`, then for each unmerged path `git show :2:` / `:3:` into temp files and `./merge-snapshots.py ours theirs -o <path>`, `git add`, commit, push. Names `--rebase` and `--force` as forbidden.
- `backup.sh` step 4: `UNION_FILES="patterns.md knowledge-staging.md"` go through `merge-snapshots.py <live> <tracked> -o <tracked>`; every other `*.md` stays a plain copy; `ENTRIES`/`PATTERNS` default to 0 (a `set -u` crash when `memory.db` is absent, found by the test).
- `merge-snapshots.py`: reads all inputs before writing (output may be an input), compact JSON, `--check` exits 3 when ours would change.
- Tests in `brana-knowledge/tests/`: `test-merge-snapshots.sh` (23), `test-backup-guard.sh` (18), `test-backup-union.sh` (9); bare origin + clones A/B, `HOME` pointed at a scratch dir so the exports skip. All red first.

## Boundaries

| Always | Ask First | Never |
|--------|-----------|-------|
| Fetch before export; refuse on true divergence | Changing the behind-only fast-forward policy | Rebase, force-push, or delete either machine's commits |
| Keep the losing version in git history | Restoring machine-local rows | Write memory content to the public repo |

## Testing Strategy

- **Unit:** merge rule (`test-merge-snapshots.sh`): identity, newest/largest-uses wins, section order, idempotence, `--check`.
- **Integration:** full `backup.sh` and `daily-push.sh` runs in clone A against the bare origin (`test-backup-guard.sh`, `test-backup-union.sh`), asserting exit code, message, commit count and the unioned file.
- **E2E:** one real run of `backup.sh` on this machine after merge, expecting a clean push.
- **Mock policy:** real git repos in a scratch dir; no mocks.

## Documentation Plan

- [x] **Tech doc**: this file plus ADR-095 amendment.
- [x] **User guide**: none; the guard's message is the guide. `docs/guide/macos-setup.md` has one line on what to do when a close reports divergence.
- [x] **Existing docs to update**: `docs/README.md` entry for this spec; `docs/architecture/memory-backup.md` changelog line.

## Sibling sweep (ADR-082 rung 1, 2026-10-03)

Fixed in this task: `restore.sh:29` swallowed `git pull --rebase` (class A); `portfolio.md` outside the union list (class B). Already tracked, left alone: `restore.sh` copying repo files over live memory and `sync-state.sh` copying `event-log.md` both ways — t-3405 / t-3367; HNSW/RVF index copies keyed by per-machine row ids — ADR-095 revision (t-3436); per-project memory `cp` becomes a two-writer clobber once t-3405's slug remap lands. Observed, not tracked: thebrana `dev` is pushed by both machines without a fetch (`ship`, `close`, `sync-state.sh`) — git rejects the non-fast-forward and a human resolves, so no cron retry stacks commits; the per-machine task-id counter (`task-id-lock.sh`, `tasks/mod.rs` max+1) can mint the same `t-NNN` on both machines before a sync (class C).

## Challenger findings

_pending_
