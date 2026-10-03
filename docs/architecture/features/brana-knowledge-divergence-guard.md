# Feature: brana-knowledge divergence merge and fetch-first backup guard

**Date:** 2026-10-03
**Status:** specifying
**Task:** t-3435 (epic t-3372 macos-portability)
**ADR:** [ADR-095](../decisions/ADR-095-two-machine-memory-sync.md) §Amendment 2026-10-03

## Problem

Two machines run `backup.sh` against one `brana-knowledge/master`. The script commits a whole-store snapshot and pushes without fetching, so when the other machine has pushed first the push is rejected and every later close commits further onto the stale base. The first occurrence (2026-10-02) was resolved as "keep local", which silently dropped 14 `patterns.md` sections and 2 curated ruflo entries that only the Mac had.

## Decision Record (frozen 2026-10-03)

> Do not modify after acceptance.

**Context:** ADR-095 already fixes the steady-state rule (per-entry files, newest wins, union for append-only notes) but its implementation (t-3404, t-3405) is pending. This task applies that rule once by hand and adds the smallest guard that makes the next divergence visible at the first close.
**Decision:** Restore the Mac-only notes and curated entries as a union commit keyed as ADR-095 prescribes. Make `backup.sh` fetch before exporting: fast-forward when only behind, refuse when diverged, warn and continue when offline. Record the applied rule in ADR-095 and in t-3404.
**Consequences:** No memory lost from the first divergence except machine-local telemetry, which ADR-095 excludes by design. Future divergence fails loudly before a commit exists. Whole-store ping-pong between machines remains until t-3404/t-3405.

## Constraints

- Never `git pull --rebase` or `push --force` on brana-knowledge: both pick one machine's memory over the other's.
- `backup.sh` lives in the private brana-knowledge repo, not in thebrana. The thin invoker `system/scripts/backup-knowledge.sh` is unchanged.
- The guard must never lose a local backup: an offline fetch is a warning, not a stop.
- No memory content may enter the public thebrana repo (ADR-095 privacy boundary). This spec and the ADR carry counts and keys only.

## Scope (v1)

- Union restore commit on a brana-knowledge branch: 14 `patterns.md` sections, 2 `pattern`-namespace entries, from `b04be875`. Same 14 sections appended to the Linux local `~/.claude/memory/patterns.md`.
- Fetch-first guard at the top of `backup.sh`, before any export.
- Shell test with a bare origin and two clones covering: behind-only, diverged, offline, in-sync.
- ADR-095 amendment and t-3404 context pointer.
- Out of scope: per-entry export, notes slug mapping, session-start pull (t-3404..t-3406).

## Research

- Key audit of `9cf4055f` vs Mac tip `b04be875`: memory-entries 6 Mac-only keys (2 session, 2 metrics, 2 pattern); patterns.json 0 lost by content; patterns.md 14 sections; consolidation-log 0; project memories 624/624 kept.
- `patterns.json` `id` is a per-machine autoincrement: unusable as a merge key. Content (`approach`) is the key.
- ADR-095 §2 classes `session` and `metrics` as machine-local, never synced.

## Assumptions

- Behind-only is fast-forwarded silently rather than refused: chose fast-forward because refusing would fail every Linux close after any Mac push, with nothing local at risk. Needs confirmation.
- Offline fetch continues to a local commit and the existing push-failure exit, as today. Needs confirmation.
- The 4 session/metrics rows are not restored (ADR-095 §2). Confirmed by the user 2026-10-03.
- The Mac pull after the restore is the user's step; the Mac's next export will overwrite the union in the repo copy until t-3404 lands (documented limit, not fixed here).

## Behavior

- Running `backup.sh` while the remote has commits this machine lacks and this machine has none of its own: the script fast-forwards, exports, commits, pushes as usual.
- Running it while both sides have commits: the script stops before exporting, prints the two tips and the command to resolve, exits non-zero. Nothing is committed.
- Running it offline: a one-line warning, then the normal local commit; the push fails as it does today.

## Edge Cases

- No remote configured, or detached HEAD: skip the guard with a note, behave as before.
- Dirty working tree when fast-forward is needed: `--ff-only` fails; treat as diverged (refuse, print resolution).
- Remote branch name differs from local: resolve via the upstream of HEAD, fall back to `origin/<branch>`.

## Design

- `backup.sh` step 0, before "1. ReasoningBank": `git fetch origin <branch>` under a timeout; compare `HEAD` and `origin/<branch>` with `git merge-base --is-ancestor` in both directions to classify in-sync / ahead / behind / diverged.
- Resolution message names the ADR-095 rule and the exact command: `git -C <repo> fetch origin && git merge origin/<branch>` then union the conflicted files by key.
- Union restore done by a one-off Python step on the brana-knowledge branch, verified by the same key audit that found the loss.
- Test at `brana-knowledge/tests/test-backup-diverged-guard.sh`: bare origin, clones A and B, `HOME` pointed at an empty scratch dir so exports skip. Red first against the unguarded script.

## Boundaries

| Always | Ask First | Never |
|--------|-----------|-------|
| Fetch before export; refuse on true divergence | Changing the behind-only fast-forward policy | Rebase, force-push, or delete either machine's commits |
| Keep the losing version in git history | Restoring machine-local rows | Write memory content to the public repo |

## Testing Strategy

- **Unit:** classification of the four git states via the shell test (behind, diverged, offline, in-sync).
- **Integration:** full `backup.sh` run in clone B against the bare origin, asserting exit code, message, and that no commit was created on divergence.
- **E2E:** one real run of `backup.sh` on this machine after merge, expecting a clean push.
- **Mock policy:** real git repos in a scratch dir; no mocks.

## Documentation Plan

- [x] **Tech doc**: this file plus ADR-095 amendment.
- [ ] **User guide**: none; the guard's message is the guide. `docs/guide/macos-setup.md` gets one line on what to do when a close reports divergence.
- [ ] **Existing docs to update**: `docs/README.md` entry for this spec.

## Challenger findings

_pending_
