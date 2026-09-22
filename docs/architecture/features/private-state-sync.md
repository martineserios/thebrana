---
title: Private state sync — keep client/venture data out of the public repo
status: implemented
task: t-3352
created: 2026-09-20
related:
  - ../decisions/ADR-015-state-consolidation-plugin-first.md
  - ../memory-backup.md
---

# Private state sync

## Problem

`thebrana` is a **public** repo. `sync-state.sh push --auto-commit` copied two
files from the `~/.claude/` cache into `system/state/` and committed them:

| File | Contents | Sensitivity |
|------|----------|-------------|
| `portfolio.md` | portfolio notes | client fees and amounts, spreadsheet ids, a cloud project id, client and venture names |
| `tasks-portfolio.json` | project registry | client and venture paths and descriptors |

They were tracked from 2026-03 in ~47 commits. Nothing in the pipeline asked
whether a file was safe to publish, so every new client descriptor went public the
next time the auto-commit ran. The 2026-09-20 ship (`/brana:ship` Gate 3) caught
new descriptors in the diff; the older exposure was already on `main`.

No credentials are involved. The exposure is commercial and identity data.

## Root cause

A file's *classification* (private vs publishable) lived nowhere. `sync-state.sh`
treated every state file as "repo state" and `--auto-commit` published it. Fixing
the leaked lines would only narrow what leaks; the capability, "generated private
state is auto-committed to a public repo," is what has to go.

## Design

State files are split by where their git home is:

| Class | Files | Git home |
|-------|-------|----------|
| public | `event-log.md`, `tasks-config.json`, `scheduler.json` | `system/state/` (unchanged) |
| private | `tasks-portfolio.json` | `$BRANA_PRIVATE_REPO/backup/state/` (default `~/enter_thebrana/brana-knowledge`, a private repo) |
| private, already covered | `portfolio.md` | `brana-knowledge/backup/memory/portfolio.md`, written by `brana-knowledge/backup.sh` (which copies `~/.claude/memory/*.md`); restore by copying it back — `brana-knowledge/restore.sh` reads `memory/`, `projects/` and `swarm/` at the repo root while `backup.sh` writes under `backup/`, so it currently restores nothing (tracked separately) |

Rules:

1. `push` writes private files only into the private repo's working tree.
   `brana-knowledge/backup.sh` commits everything in that repo with
   `git add -A --ignore-errors` and pushes (1,100+ commits, several a day), so they
   are committed there without changing that repo's scripts. (`daily-push.sh` also
   exists but has never run and is not relied on.)
2. The private destination is used **only if** `$BRANA_PRIVATE_REPO/.git` exists.
   If it doesn't, `push` logs a skip and exits 0. It **never falls back** to the
   public dir; a missing private repo must not degrade into a public write.
3. `pull` restores `~/.claude/tasks-portfolio.json` from the private repo's working
   tree. On a second machine, `git pull` brana-knowledge first, or the restore copies a
   stale registry; `pull` does not fetch the private repo itself (it is unidirectional
   and never touches another repo's history). Runtime edits always go to the cache.
4. Runtime readers (`session-start.sh`, `migrate/audit-orphaned-active-epic.py`)
   read the `~/.claude/` cache, not the repo copy, so untracking changes nothing
   for them.
5. Both public-repo paths are untracked and gitignored, and `validate.sh` fails if
   either becomes tracked again (a guard, with a must-fire test).

## Restore on a new machine

1. Clone brana-knowledge (or `git pull` an existing clone): `pull` reads that
   working tree and does not fetch it, so a stale clone restores a stale registry.
2. `sync-state.sh pull` restores `~/.claude/tasks-portfolio.json` from `backup/state/`.
3. `portfolio.md`: copy `brana-knowledge/backup/memory/portfolio.md` to
   `~/.claude/memory/` by hand until `restore.sh` is fixed.

## Known gaps (not closed by this change)

- Other tracked state files can name clients too (`system/state/event-log.md` is on the
  auto-commit allowlist; `session-handoff.md` is tracked). Same class of exposure,
  pre-existing; tracked as a separate task.
- The private route only checks that `$BRANA_PRIVATE_REPO/.git` exists, not that the
  repo is private.

## Non-goals

- **No history rewrite.** The old commits stay public. Rewriting would need a
  force-push to `main`, which `git-discipline.md` forbids, and clones and caches
  already hold the data. The old values are treated as public.
- No redaction layer. A redacted tracked copy could not restore the real data.

## Human follow-up

Check whether any of the spreadsheets referenced in the old `portfolio.md` are
shared by link, and tighten sharing if so. An id alone grants nothing, but a
link-shared sheet is readable by anyone who has the id, and the id is public.

## Verification

- `tests/scripts/test-sync-state-private-files.sh` (sandboxed: temp `HOME`,
  `BRANA_STATE_DIR`, `BRANA_PRIVATE_REPO`; never touches the real `~/.claude`)
- validate.sh guard check plus its must-fire test.
