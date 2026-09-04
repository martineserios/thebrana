---
status: accepted
amends: docs/architecture/decisions/ADR-002-tasks-as-data-layer.md
extends: docs/architecture/decisions/ADR-060-branch-strategy-autonomous-agents.md
informs: docs/domain/MODEL-001-brana-core.md
---

# ADR-091: Untrack `.claude/tasks.json` from git; canonical file + periodic snapshot

**Status:** Accepted (2026-09-04)
**Date:** 2026-09-04
**Deciders:** Martín Rios
**Tags:** tasks-json, worktree, concurrency, git, harness
**Tasks:** t-3283 (this ADR), t-3282 (umbrella), t-3284 (tests), t-3285 (untrack + retire), t-3286 (hook fix), t-3287 (snapshot step), t-3288/t-3289 (spec/docs sync)
**Amends:** [ADR-002](ADR-002-tasks-as-data-layer.md) (tasks-as-data-layer) — supersedes its "status changes on main only" mitigation
**Extends:** [ADR-060](ADR-060-branch-strategy-autonomous-agents.md) (branch strategy, worktree-per-task) · [ADR-071](ADR-071-scheduler-thin-layer-over-systemd.md) (scheduler, for the snapshot job)

---

## Context

Sessions routinely close leaving `.claude/tasks.json` uncommitted, with no clean way to tell
whether their local diff is safe to commit. The working theory going in — three independent
challenger agents (convergent/systems/critical lenses) spawned to stress-test two candidate
fixes — was that ADR-060's worktree-per-task model (June 2026) had broken ADR-002's original
concurrency mitigation ("status changes on main only", Feb 2026): every worktree is an
independent git checkout, so every worktree should hold its own independent physical copy of
tasks.json, diverging with no live reconciliation until git commit+merge.

**That premise was false on the current write path**, and all three challengers found this
independently, from code, not from the problem framing:

- `find_tasks_file_from()` (`system/cli/rust/crates/brana-core/src/util.rs`) resolves the
  tasks.json path via `git rev-parse --git-common-dir` **first** — which is, by definition,
  identical from every worktree of a repo. Every `brana` CLI / MCP backlog call, from any
  worktree, already reads and writes **one physical file**: the main checkout's
  `.claude/tasks.json`. `docs/domain/MODEL-001-brana-core.md`'s "State files owned" line
  already documents this correctly ("`.claude/tasks.json` (primary, worktree-aware via
  git-common-dir)") — the domain model was ahead of this ADR's starting assumption.
- That canonical file is already protected by advisory `flock(2)` around the full
  read-modify-write (`lock_tasks`/`lock_tasks_timeout`, `tasks/mod.rs`) plus atomic
  temp-file+rename writes (`write_atomic`), tested under 16-thread contention with zero lost
  writes. flock releases automatically on process death — no orphaned-lock risk.
- A keyed git merge driver already exists (`.gitattributes:6` → `system/scripts/tasks-json-merge.sh`,
  wired by `bootstrap.sh` Step 4e), originating from **t-2132** (session-end commits could
  clobber same-session completions — a same-file, cross-*commit* race, not cross-worktree
  divergence).

**What IS actually broken**, confirmed live in this repo (`thebrana` main checkout vs. the
`thebrana-t-3280` worktree): the git-tracked per-worktree checkout copies have already
diverged (87,516 vs. 87,511 lines) because `git worktree add` still materializes a stale,
disposable copy that nothing keeps in sync and that the CLI silently ignores in favor of the
common-dir-resolved canonical file. Two independent prior incidents in this project's own
history already trace to exactly this class of bug, just through different consumers:

- **t-2845** (a challenger/evaluator agent given "review this worktree" read that worktree's
  stale checked-out tasks.json instead of the canonical file, misjudging operational
  acceptance criteria — patched at the time by manually pointing the agent at the correct
  path, not fixed structurally). Recorded as ruflo pattern
  `challenger-review-needs-dev-tasksjson-pointer`.
- **`post-tasks-validate.sh`** (the PostToolUse hook) validates whatever raw path Write/Edit
  touched rather than routing through `lock_tasks`/common-root resolution, and its fallback
  path does an **unlocked** jq read-modify-write — a live, currently-active correctness gap,
  independent of everything else in this ADR.

A related but distinct prior lesson (ruflo pattern `session-keyed-state-resolves-via-common-dir-parent`,
t-3044) cautions that not all worktree-scoped state should resolve common-dir-first: a
time-tracking bug there was fixed by trying the worktree's own toplevel *first*, falling back
to the main-checkout root, because ADR-060 runner sessions are legitimately homed in a
worktree and their time brackets are meant to be worktree-scoped. **This does not apply to
tasks.json** — the backlog ledger is deliberately global, not per-task state — but it is the
reason this ADR states the resolution order explicitly rather than assuming one true order
for all shared state in this codebase.

The real, narrower gap: `.claude/tasks.json` is still `git ls-files`-tracked, so (a) `git
worktree add` keeps materializing copies nothing needs and that other tooling can be
misled by reading directly, (b) ordinary git operations in the main checkout (`checkout`,
`merge`, `stash pop`, `reset`) can silently clobber the live, actively-flock-written file with
a stale commit/stash blob, and (c) nobody owns *when* the shared, perpetually-dirty ledger
gets committed — which is the actual reason sessions keep leaving it uncommitted: they cannot
attribute a diff that already contains other concurrent sessions' flock-serialized writes to
themselves.

## Decision

1. **Stop git-tracking `.claude/tasks.json`.** `git rm --cached .claude/tasks.json`
   (repo-wide) + add to `.gitignore`. No symlink is needed: `find_tasks_file_from()`'s dynamic
   `git-common-dir`-first resolution is already the sharing mechanism. Correction (challenge
   review): this does **not** auto-clean pre-existing worktrees — `fetch`/`pull` never
   deletes a file that becomes gitignored, so each worktree created before this change keeps
   an orphaned physical copy on disk indefinitely. Harmless (common-dir resolution ignores
   it), but t-3285 should not assume automatic cleanup — note it, don't chase it.

2. **Keep the existing concurrency machinery as-is.** `lock_tasks`/`lock_tasks_timeout` +
   `write_atomic` are correct and tested; this ADR does not touch them.

3. **Keep `tasks-json-merge.sh`, rescoped and repointed.** It is no longer needed for
   cross-worktree checkout divergence (that class of conflict no longer exists once the file
   is untracked). What it *is* still needed for, made explicit (challenge review — the
   original text here was vague enough to be non-implementable): a `git commit` race in the
   *same* checkout collides on `.git/index.lock`, not via the merge driver — that needs a
   plain flock/lockfile around the snapshot script itself (item 5 below), not a merge driver.
   The merge driver fires only on an actual `git merge`/rebase/cherry-pick **combining two
   commits with different snapshot content** — which does happen here: the close skill's
   convenience flush (item 5) can commit a snapshot on a feature-branch worktree, and that
   branch later merges into `dev`, colliding with `dev`'s own scheduled-job snapshot commits.
   That cross-branch case is what the driver stays for.
   - **Required, not optional:** repoint `.gitattributes:6` from `.claude/tasks.json
     merge=brana-tasks` to `system/state/tasks-snapshot.json merge=brana-tasks` and remove
     the old line. Without this the driver has nothing to attach to (the old path is
     untracked) and decision 3 is dead on arrival — this is a hard requirement of t-3285, not
     a nice-to-have.
   - Retire `worktree-gate.sh`'s "warn if tasks.json dirty" branch (keys off `git status`;
     unreachable once the file is untracked). Challenge review located the exact spot this
     touches: `tests/hooks/test-worktree-gate.sh` (~lines 203–246) hard-codes three cases for
     this exact carve-out and needs updating in the same commit — a known, already-located
     edit, not an open-ended audit.

4. **Fix `post-tasks-validate.sh`** to resolve the path and take the lock the same way the
   CLI does (`git rev-parse --git-common-dir` + `lock_tasks`), instead of validating/mutating
   whatever raw path the triggering Write/Edit touched. This closes the one unlocked writer
   that exists independent of everything else here.

5. **Add a periodic snapshot-to-git step**, giving "who/when commits the ledger" a formal,
   automatic owner instead of the current ad hoc per-session judgment call:
   - A new script (`system/scripts/tasks-json-snapshot.sh push|pull`) copies the live
     canonical `.claude/tasks.json` (main checkout, untracked) → `system/state/tasks-snapshot.json`
     (tracked) and commits, and reverses for `pull`. It mirrors `sync-state.sh`'s
     one-directional push/pull *shape* only — NOT its `git add system/state/` line
     (`auto_commit_state`, sync-state.sh:451 adds the whole directory). That would sweep in
     unrelated dirty files (event-log.md, portfolio.md, scheduler.json) under the same commit,
     recreating the exact "whose changes are these" attribution problem this ADR exists to
     fix. `tasks-json-snapshot.sh` must `git add` only its own snapshot file.
   - **Same-checkout race guard:** wrap the push side in a flock/lockfile the same way
     `lock_sidecar` already does in `util.rs`, so two concurrent invocations in one checkout
     serialize instead of both racing `git commit`.
   - **Trigger:** a scheduled job via the existing ops scheduler (ADR-071), committing on
     `dev`, not tied to any particular session's close. The close skill may additionally
     request an immediate snapshot as a convenience flush **on whatever branch it's currently
     on** (including a feature-branch worktree) — this is the source of the cross-branch merge
     case decision 3 keeps the merge driver for, not a hypothetical.
   - **Bootstrap/fresh-clone:** `bootstrap.sh` gains a step that runs `tasks-json-snapshot.sh
     pull` (restore `.claude/tasks.json` from the last tracked snapshot) before first CLI/MCP
     invocation, so a fresh clone doesn't silently start with an empty backlog.
     `find_tasks_file_from()`'s existing auto-create-if-missing behavior remains the correct
     fallback for a genuinely first-ever setup with no prior snapshot.
   - **Cadence and durability are linked, not independent** (challenge review): a fixed
     "start conservative, e.g. hourly" cadence creates a real backup-exposure window (losing
     the machine loses up to one cadence window of backlog state that continuous tracking
     used to capture per-write) AND breaks a live practice — this session's own git log
     includes `d34e62e6 chore(backlog): t-2521 evidence note from this session's own
     close-anchor repro`, a single-field change isolated in its own commit, used as an
     attributable audit trail. Default to **event-triggered** snapshotting (on meaningful
     write, debounced) over a fixed interval, so isolated evidence-note-style commits mostly
     survive as their own commits; t-3287 tunes the debounce window from observed diff sizes
     rather than picking a fixed clock interval up front.

## Consequences

**Easier:**
- The live-reproduced divergence bug (main vs. `thebrana-t-3280`) cannot recur — there is no
  per-worktree copy to diverge.
- t-2845's failure class (agents/tools reading a stale worktree-local tasks.json by mistake)
  is closed structurally, not by remembering to point agents at the right path.
- Ordinary git worktree operations (`add`, `remove`, branch switches) stop having any
  relationship to tasks.json at all.
- Removes machinery instead of adding it, net of the new snapshot script.

**Harder:**
- Git history/blame on tasks.json moves from continuous (every commit) to periodic
  (snapshot cadence) — acceptable per ADR-002's original rationale (history is a nice-to-have,
  not the primary job of tracking this file) but is a real, named trade-off, sharpened by
  challenge review into two concrete costs: (a) a **backup-exposure window** — losing the
  machine/repo between snapshots loses more backlog state than continuous tracking did; (b)
  loss of the **one-commit-per-evidence-note practice** this project actively uses (e.g.
  `d34e62e6`, a single-field context change isolated in its own commit) — event-triggered
  snapshotting (decision 5) is the chosen mitigation, not a full acceptance of the loss.
- A new scheduled job is new operational surface (ADR-071-governed) that didn't exist before.
- `worktree-gate.sh` loses its tasks.json dirty-check; the specific test file needing the
  matching edit is already located (`tests/hooks/test-worktree-gate.sh` ~203–246), so this is
  scoped work for t-3285, not open-ended discovery.
- `.gitattributes` must be repointed at the snapshot path, not left pointing at the
  now-untracked live path (decision 3) — a required step, not an optional cleanup.

**Amends [ADR-002](ADR-002-tasks-as-data-layer.md):** its "Harder" consequence "Git merge
conflicts on tasks.json (mitigated by convention: status changes on main only)" is superseded
— the convention was never re-enforced after ADR-060 shipped and is replaced here by a
structural fix (untracking) rather than a convention.

## Non-actions (explicitly out of scope)

- **Does not change `find_tasks_file_from()`'s resolution order.** It is already correct;
  this ADR relies on it, does not modify it.
- **Does not introduce a new database (sqlite etc.).** The existing flock + atomic-write
  mechanism is sufficient; a DB migration is a much larger, unjustified change for this
  problem.
- **Does not change time-tracking's resolution order** (ruflo pattern
  `session-keyed-state-resolves-via-common-dir-parent`) — that state is legitimately
  worktree-scoped in some cases (ADR-060 runners) and tasks.json is not; the two should not
  be unified onto one resolution rule.

## Open questions

1. **Exact snapshot cadence** — left to t-3287's implementation; start conservative (e.g.
   hourly or on scheduler's existing tick) and tune from observed commit-diff sizes.
2. **Does the rescoped `tasks-json-merge.sh` ever actually fire post-change?** Only if two
   snapshot-push attempts race — expected to be rare given a single scheduled owner: verify
   via t-3284's tests rather than assuming.

## Alternatives considered

- **Symlink every worktree to one canonical file (original "Option A").** Rejected — the
  canonical-file behavior already exists dynamically via `git-common-dir` resolution; a
  symlink would duplicate that mechanism for zero benefit and adds a new integration point
  (creating the symlink on every `git worktree add`) with no existing precedent in this
  codebase.
- **Build a new keyed 3-way JSON merge tool ("Option B").** Rejected — one already exists
  (`tasks-json-merge.sh`) and is kept, rescoped to the narrower case it's still needed for.
- **Move to a real embedded DB (sqlite).** Rejected as disproportionate — the existing
  flock + atomic-rename mechanism is already correct and tested; a DB migration solves a
  concurrency problem that isn't actually the live bug.
- **Do nothing; keep tasks.json git-tracked.** Rejected — the divergence bug is live and
  reproducible today, and has already caused a real incident (t-2845).

## Challenge record (2026-09-04)

Reviewed same-day by an independent challenger pass (code-verified against `util.rs`,
`tasks/mod.rs`, `sync-state.sh`, `post-tasks-validate.sh`, `worktree-gate.sh` directly, not
against this ADR's paraphrase). Two CRITICAL findings, both amended into the text above:
decision 3's retained merge driver was non-functional as originally written (`.gitattributes`
was never repointed at the new snapshot path, so the driver had nothing to attach to — now an
explicit, required t-3285 step) and its stated race scenario was the wrong mechanism (a
same-checkout `git commit` race collides on `.git/index.lock`, not the merge driver, which
only fires on an actual cross-branch merge — decision 5 now separates a same-checkout flock
guard from the cross-branch case the merge driver is actually for, and names the close
skill's convenience flush as the real source of that cross-branch scenario). Four WARNING
findings also folded in: no backup-durability discussion (now a named Consequence);
continuous-history loss understated against a live practice found in this session's own git
log (`d34e62e6`, now cited, with event-triggered cadence as the stated mitigation); the
worktree-gate test-file edit was "deferred to audit" when it was already a known, located
edit (`tests/hooks/test-worktree-gate.sh` ~203–246, now named directly); and the snapshot
script was told to mirror `sync-state.sh`'s directory-wide `git add` literally, which would
recreate the attribution problem this ADR exists to fix (now scoped to the single snapshot
file). Three OBSERVATIONs confirmed clean and required no change: no other git-diff/blame
tooling depends on tasks.json's tracked status; `git fetch`/`pull` does not auto-clean
pre-existing worktrees' orphaned copies (decision 1 corrected to say so); the autonomous
runner's tasks.json access already goes through common-dir resolution, no runner-specific
gap.
