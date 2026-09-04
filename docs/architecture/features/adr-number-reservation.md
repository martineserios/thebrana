---
status: shipped
---
# ADR number reservation (t-3294)

Status: **implemented (t-3294, 2026-09-04).** `reserve_next_adr_number` lives in
`brana-core/src/adr.rs`; `brana adr reserve <slug>` in `brana-cli/src/commands/adr.rs`.

## Goal

ADR authoring was fully manual: a session ran `ls docs/architecture/decisions/ | tail`,
picked the next number by eye, and wrote the file. Nothing serialized this across
concurrent sessions. Two independent sessions collided on `ADR-091` for unrelated topics
within the same close window ([t-3290](../../architecture/decisions/) — see task, no
dedicated ADR); the collision was caught only because one session happened to notice the
other's commit in `git log` before push.

`brana adr reserve <slug>` reserves the next ADR number and creates a placeholder file
atomically, safe under concurrent sessions on the same machine — including sessions in
separate `git worktree` checkouts, which is this repo's mandated branching model
(`git-discipline.md` "Worktrees, not checkout — HARD RULE").

## Design Decisions

**Why a shared registry file, not a directory scan under a lock.** A spike (recorded in
`t-3294`'s task context) proved a shared `flock` alone is *not* sufficient: each
`git worktree` checkout has its own local, independently-committed copy of the tracked
`docs/architecture/decisions/` directory. Two sessions in separate worktrees, both holding
a correctly-shared lock in turn, each scan *their own* local directory and can still both
compute the same "next number" — the lock serializes *when* they run, not *what they see*.
Reproduced live: two worktree dirs + one shared lock → both picked `ADR-093`.

The fix moves the counter into a registry file (`.claude/adr-registry.json`) at the shared
session root instead of scanning the per-worktree tracked directory on every call. The
registry is read once per call, under the same lock that guards its own write — so a
placeholder created in worktree A is reflected in the registry immediately, without needing
to wait for worktree B to merge or pull.

**Why `find_session_root()`, not a bespoke git-common-dir resolver.** This repo already has
a tested, public helper for "which project's session lanes am I part of — a question every
linked worktree of one repo must answer identically" (`brana-core/src/util.rs`, ADR-069
D0b) — the same mechanism `tasks.json` and the session/memory store already use. Reused
directly rather than re-deriving `git rev-parse --git-common-dir` locally.

**Why `lock_sidecar_timeout`, not a raw `flock()` call.** Already exists in
`brana-core/src/util.rs` (t-2305), bounded (fails after 10s rather than hanging forever if
contended), and already the load-bearing lock for `tasks.json` itself
(`tasks/mod.rs::lock_tasks_timeout`). Reused rather than reimplemented.

**Why the placeholder file is written inside the lock.** A reservation that only updates
in-memory/registry state and releases the lock before the file exists would leave the same
gap the naive directory-scan design had — a second reservation could still be attempted
against a not-yet-visible number if some other consumer keyed off file existence rather
than the registry. Writing the placeholder inside the locked span closes that.

**Scope: same-machine only.** `flock` is a kernel-local primitive with no cross-host
visibility. A second physical machine sharing this repo is explicitly out of scope — it
would need a separate pre-push re-validation-against-`origin/dev` check, tracked as a
deferred follow-up in `t-3290`'s context, not solved here (the user confirmed a
single-machine workflow at the time of this build).

**Task-ID minting was investigated, not duplicated.** The original task description asked
to "generalize to task-ID minting in the backlog CLI if straightforward." Investigation
found `next_id()` (`brana-core/src/tasks/mod.rs`) already runs inside `tasks.json`'s
pre-existing `lock_tasks`/`lock_tasks_timeout` critical section — task-ID collisions were
already prevented before this task started. No code change was needed there; scope was
narrowed accordingly.

## Code Flow

1. `brana adr reserve <slug>` (`brana-cli/src/commands/adr.rs::cmd_reserve`)
2. Resolves the current worktree's project root (`find_project_root()`, git show-toplevel)
   → ensures `docs/architecture/decisions/` exists there
3. Calls `brana_core::adr::reserve_next_adr_number(decisions_dir)`
   - Resolves the shared session root (`find_session_root()`, git-common-dir)
   - Acquires `lock_sidecar_timeout` on `<shared_root>/.claude/adr-registry.json`
   - Reads the registry if it exists; if not, bootstraps `highest` from the highest
     `ADR-NNN-*.md` file currently in `decisions_dir` (first-call-ever seeding)
   - Increments, writes the registry back atomically (`write_json_atomic`), releases
     the lock (guard drop)
4. Writes `docs/architecture/decisions/ADR-{NNN}-{slug}.md` with a stub header
   (`Status: draft`, empty `## Context` / `## Decision` / `## Consequences` sections)
   in the **current worktree** — the placeholder itself follows normal git flow
   (commit → push → merge) like any other tracked file; only the *number* is
   collision-protected, not the file's propagation across worktrees.

## Key Files

- `system/cli/rust/crates/brana-core/src/adr.rs` — reservation logic + tests
- `system/cli/rust/crates/brana-cli/src/commands/adr.rs` — CLI command
- `system/cli/rust/crates/brana-cli/src/cli.rs` — `Commands::Adr` / `AdrCmd::Reserve`
- `.gitignore` — `.claude/adr-registry.json` added (ephemeral, self-healing cache; the
  `.json.lock` sidecar was already covered by the existing `*.json.lock` rule)

## API Surface

```
brana adr reserve <slug>
```
Prints `Reserved ADR-{NNN} -> <path>` on success. `slug` is a kebab-case topic string,
e.g. `backfill-retry-policy`.

## Testing

`brana-core/src/adr.rs`, `#[cfg(test)] mod tests` (4 tests, `cargo test -p brana-core adr::`):

- `bootstraps_from_highest_existing_file_on_first_call` — registry seeds correctly from an
  existing tracked directory
- `second_call_reads_the_registry_not_the_stale_directory` — proves the fix: a second
  reservation does NOT re-derive the same number from a directory that never saw the first
  reservation's placeholder (simulating an unmerged sibling worktree)
- `twenty_way_concurrent_reservation_has_no_collisions_or_gaps` — 20 real OS threads,
  synchronized with a `Barrier` to maximize actual contention, calling the real
  `flock`-backed path; asserts the result set is exactly `93..=112` with no duplicates
  or gaps
- `empty_decisions_dir_bootstraps_from_zero` — cold-start case, no existing ADR files

All tests use a testable `_at(shared_root, decisions_dir)` variant that takes the shared
root explicitly, rather than relying on `CLAUDE_PROJECT_DIR` env-var manipulation — avoids
the cross-test races that approach would introduce under `cargo test`'s default
parallelism (mirrors this codebase's existing testable-variant convention, e.g.
`git_common_root_in`, `find_tasks_file_with_hint`).

Also manually smoke-tested end-to-end against the real repo: `brana adr reserve
spike-topic-cli-test` correctly reserved `ADR-093` (the real next number after the
existing `ADR-092`) and wrote a well-formed placeholder file; both the placeholder and the
registry entry were cleaned up afterward as test artifacts.

## Known Limitations

- Same-machine only (see Design Decisions above) — cross-machine reservation is a deferred
  follow-up tracked in `t-3290`, not built here.
- The registry is a flat "highest number seen" counter — it does not detect or repair a
  registry that has drifted behind the tracked directory (e.g. after manually deleting
  `.claude/adr-registry.json` while ADR files with higher numbers than the registry's last
  bootstrap already exist and a placeholder was never actually committed). This is
  self-healing only on the registry's *first-ever* creation, not on every call.
