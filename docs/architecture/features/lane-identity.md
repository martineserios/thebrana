# Feature: Lane Identity — Session-State Key Unification and Miss Semantics

**Date:** 2026-09-02 (ADR Accepted 2026-09-03)
**Status:** t-2520 shipped (D0b, dev aa8dfe62) and t-2521 shipped 2026-09-04 (D0+D1+D2, 7 subtasks
t-3292/t-3293/t-3295/t-3296/t-3297/t-3298/t-3299 — see the Retirement Decisions and Rollback
subsections below for two scope decisions made during implementation). **t-2524 (D3) not started**
— shared-checkout guards remain future work.
**Task:** t-2517 (spec) — gates t-2520, t-2521, t-2524
**Governing ADR:** [ADR-069](../decisions/ADR-069-lane-identity-and-miss-semantics.md) (**Accepted** 2026-09-03 — D3.2 and D3b's original fail-loud row retracted; D0, D0b, D1, D2, D3.1/D3.3, D4, D5, D6 stand)

## Problem

Session-state read/write/consume resolve through *different* key functions (epic-first on
write, branch-only on read/consume). On `dev` — the branch every close lands on after merge —
the read-key can never match the write-key, so a read silently returns a *different lane's*
state instead of failing. This is not hypothetical: it has now recurred at least eight times
since ADR-069 was drafted (t-2502, t-2506, t-2618, t-2674, t-2578's D0/D2-class defects, and
most recently a 2026-09-02 incident where Tier 0 epic-focus corroboration in `/brana:close`
picked the wrong epic file for a session's real handoff, caught only by manual timestamp
inspection — see t-2517's context log). Every one of these has been patched at the
*consumer* layer (close's corroboration tiers, CAS tokens, union-merge fallbacks,
visibility-only warnings). None of them can fix the underlying asymmetry, because none of
them change the key.

This spec turns ADR-069's D0/D0b/D1/D2/D3(.1,.3) decisions into an implementable contract:
every surface that must change, named with its current file:line, its current behavior, and
its required behavior after this ships.

## Decision Record (frozen 2026-09-02)

> Do not modify after acceptance. See ADR-069 for the full context, alternatives considered,
> and verification history (t-2516). This section is a pointer, not a restatement — ADR-069
> is the frozen decision; this spec is the surface-by-surface implementation contract that
> follows from it.

**Context:** Session handoff state is keyed by `epic` (a *deliverable*, ADR-065) instead of a
*lane* (an execution context: worktree + branch + session). `write_state` resolves epic-first;
`read_state` and `mark_consumed` resolve branch-only. On `dev`, branch-only resolution always
misses the epic-keyed write and falls through to a stale/empty file — a **miss that returns
`exit 0` and a plausible-looking wrong answer**, never an error.

**Decision:** D0 (one key function for read/write/consume) + D0b (session state resolves via
`git_common_root()`, matching `tasks.json`) + D1 (a miss is always a non-zero exit, never a
substitution) + D2 (write keys by session id captured at session start; resume is a ranked
*query* over the lane store, not a key lookup) ship as **one change** — D1 alone is unusable
without D0b (fires on every worktree lane) and without D2 (a fresh session has no state under
its own id, so miss would be the universal case at start). D3 (commit attribution: reflog +
three mechanical guards, **D3.2 excluded** — retracted, see Amendment) ships as a second,
dependent change once D2's lane pin exists.

**Consequences:** every session-state consumer must handle a non-zero exit from `session
read` (Consequences below enumerates each). `brana session path` and the session-end hook's
unlocked read-modify-write both come into scope. D2 is not revert-safe once any close has run
under it — a rollback/migration script is a required deliverable, not a contingency.

## Constraints

- **Context economy (NFR, from ADR-069 Consequences):** "session-start gains one file
  write" for the lane pin must add no tokens to session start — a file write, not a context
  injection. Testable: session-start output/context payload size must be unchanged by this
  work.
- **Precondition MET (2026-09-03):** ADR-069 flipped to Accepted as part of closing this
  task — t-2516's verification (2026-07-28) plus the 2026-08-23 Amendment had already
  resolved every open mechanism question; nothing remained pending a human call once this
  spec's own re-verification against live code (both challenger iterations) confirmed the
  surviving decisions' surfaces still exist as described. t-2520/t-2521/t-2524 are unblocked.
- **Do not touch `save_tasks`, `write_atomic`, or `lock_tasks`.** D4 refuted the torn-read
  hypothesis against these; they are correct. This spec is about *which key* resolves a file,
  never about the write mechanics of the file itself.
- **No new hierarchy node for a lane.** A lane is session-state's concern, not the backlog's;
  `task.branch` already exists there.
- **`BRANA_SESSION_ID` is set but never exported** — confirmed by direct measurement (ADR-069
  Context). No mechanism may rely on environment inheritance (child process, git hook,
  delegated script) to see it. The lane pin must be discoverable by `worktree_path` (cwd is
  inherited) and carry `session_id` inside itself.
- **The autonomous sandbox cannot fire `SessionStart`** (`system/scripts/autonomous-runner.sh`
  `sandbox_claude`, `~/.claude/settings.json`/`~/.claude/hooks/`/`~/.claude/projects/` all
  unmounted, `env -i`). D3b's "missing pin ⇒ fail loud" is retracted for exactly this reason —
  it would reward disabling the sandbox. A run without a pin must degrade to a named
  `autonomous:<run-id>` lane, never hard-fail.
- **D3.2 (reflog-based commit attribution) is retracted and must not be implemented as
  specified.** `git worktree remove` deletes the worktree's own reflog (verified, t-2516 G1);
  attribution must be recorded *at commit time* (D3.3's guard already installs a commit-time
  hook — D3 work appends there), never reconstructed from the reflog at close.
- **Resolved ambiguity, stated explicitly (no-silent-ambiguity-fill):** ADR-069's Amendment
  retracts "D3b (missing pin ⇒ fail loud)" — read literally this could mean all of D3b or
  just its missing-pin row. This spec reads it as **the missing-pin row only**: D3b's other
  properties (atomic write, single writer, liveness window, stale-pin pruning, corrupt-pin
  handling — all in its table) are load-bearing for D2's lane pin and have no verified defect
  against them; only "absence ⇒ fail loud" is contradicted by the autonomous-sandbox finding
  (VERIFIED block, t-2516 G2) cited two bullets above. If this reading is wrong, say so before
  t-2521 starts — D3b's other properties are assumed in the Design section below.

## Scope (v1)

In scope (this spec governs all of it; implementation split across t-2520/t-2521/t-2524):

1. **D0b — store scoping.** Session-state resolution moves from `find_project_root()` /
   `git_toplevel()` (per-worktree) to `git_common_root()` (shared), mirroring
   `find_tasks_config()`. Existing per-worktree stores are migrated or explicitly adopted as
   `legacy:<slug>` lanes.
2. **D0 + D1 + D2 — one key function, fail-loud miss, lane pin.**
   - One key function serves read, write, and consume.
   - Write keys by a session-id lane pin captured at session start (file, atomic same-dir
     temp+rename, single-writer, discovered by `worktree_path`).
   - Resume is a ranked query (`worktree_path` match → `branch` match → `task_id` match),
     reporting which rule matched and the candidate count. Two equally-ranked candidates is a
     **miss**, not a coin flip.
   - Every fallback surface named in ADR-069's D1 table (see Surfaces below) closes: no
     silent substitution anywhere in the call chain, including shell callers that today do
     `2>/dev/null || VAR=""`.
   - Legacy identity-less files become addressable only via `--all` + explicit
     `--lane legacy:<slug>` — never an implicit fallback target.
   - Autonomous bootstrap: `brana session lane init --session-id <id>` is the explicit,
     runner-called pin-creation path for the sandboxed surface (no SessionStart available).
   - **A rollback/migration script ships as part of this change**, not after — D2 is not
     revert-safe once any close has run under it (ADR-069 Consequences).
3. **D3 (excluding D3.2) — mechanical shared-checkout guards**, dependent on D2's lane pin:
   - D3.1 — a pin resolving to the main checkout is marked `shared: true`; any consumer
     deriving a commit set from a `shared` pin fails loud rather than computing a window.
   - D3.3 — pre-commit guard in the shared checkout rejects a commit whose staged set
     includes a path `dirty_at_start` (recorded on the pin), unless explicitly adopted
     (`--adopt-path`); `git commit -a` is rejected outright in the shared checkout.
   - D3b's atomicity/single-writer/liveness/stale-pin/missing-pin/corrupt-pin properties
     (table in ADR-069) apply to the pin itself — **excluding** the retracted "missing pin ⇒
     fail loud" row, replaced by the autonomous degrade above.

Out of scope for this spec (explicitly, per ADR-069 Non-Actions / Amendment):

- D3.2 (reflog attribution) and D3b's original fail-loud-on-missing-pin — retracted, not to
  be implemented as originally written. A commit-time attribution mechanism (appended to
  D3.3's guard) is a candidate for a *future* ADR, not this one.
- Per-commit ledger / `--commits LIST` into `close-snapshot.sh` — a contiguous range cannot
  express a non-contiguous commit set; D3 makes the over-reach visible, not solved.
- D4 (atomicity), D5 (waves), D6 (epic cleanup) — separate clusters/decisions per ADR-069;
  no diff from this spec.
- Any change to `save_tasks`, `write_atomic`, `lock_tasks`.

## Assumptions

- **`git_common_root()` is a shared, tested primitive already used by `find_tasks_config()`**
  (`util.rs:210-213`) and can be reused for session-state resolution without modification —
  needs confirmation against current `brana-core/src/util.rs` before t-2520 starts (ADR-069
  is dated 2026-07-28; verify the function still exists at that signature).
- **The lane pin's file location is under the shared common-root tree** (not per-worktree),
  consistent with D0b — chose this over a per-worktree pin because the ADR's own worked
  example (main-checkout `shared: true` detection) requires a store all lanes can see to
  detect "two live pins matching one cwd."
- **`brana session lanes --prune`** (named in D3b's Stale pins row) is a new subcommand, not
  yet implemented — confirmed absent from current CLI help; scoped as part of D2's delivery
  since a lane store with no prune path accumulates crashed-session litter immediately.

**Re-verified against live `brana-core/src/session.rs` on 2026-09-02** (challenger-caught gap
in an earlier draft of this spec — the file has moved since ADR-069 was drafted 2026-07-28,
via three tasks the ADR predates):

- **`dedup_next_items` (session.rs:175) and `merge_states` (session.rs:712)'s `next[]`
  handling are ALREADY FIXED** by t-2506 — both dedupe by case-folded trimmed *text*
  (`next_item_key`, session.rs:185), not `task_id`, exactly matching D0/D2's own reasoning
  about `task_id` being a reference, not a key. **Do not re-fix.** What ADR-069's
  Consequences actually names as the still-open decision is narrower: whether
  `merge_states`'s *same-day-merge code path itself* should be retired once D2 gives every
  session its own per-session-id file (no more "two writes, same day, same branch" collision
  for it to resolve) — see Boundaries below.
- **`write_state` (session.rs:509) already delegates to `write_state_with_base`
  (session.rs:536)**, which already implements exactly the replace-if-base-matches /
  union-if-stale/absent CAS semantics D2's "resume is a query, not a lookup" section
  presupposes. D2's lane-pin work should call and extend this, not build parallel CAS logic.
- **`read_state_from_unit` (session.rs:408, t-3185) already exists** as an opt-in read that
  resolves by the same unit key `write_state` uses (an explicit `epic`, including
  `ORPHAN_EPIC_SENTINEL`) — it is exposed today via MCP `session_read`'s optional `epic`
  input param (`brana-mcp/src/tools/session_read.rs:16`, also t-3185). **This is the
  reusable primitive for D0's "one key function" — the D0/D1 work is to make the *default*
  `read_state()` (session.rs:414, still branch-only via `read_state_from`) call this instead
  of building a new resolver, and to make a miss return an unambiguous typed error instead of
  `session_read.rs`'s current `{"found": false}`** (updates the D1 MCP row below).
- **`is_safe_epic_slug` (session.rs:99, t-3169)** is a live path-traversal guard on epic/slug
  interpolation into a filename — D2's `legacy:<slug>` naming must reuse it, not re-invent
  slug validation.

## Design

### Surfaces — every location named in ADR-069, mapped to its required change

**D0 — key unification** (source line numbers per ADR-069, 2026-07-28 — re-verify against
current `brana-core/src/session.rs` before implementing, per Assumptions above):

| Surface | Function chain | File:line (re-verified 2026-09-02) | Current | Required |
|---|---|---|---|---|
| Write | `write_state` → `write_state_with_base` → `unit_scoped_state_path` | `session.rs:509,536,105` | epic-first (unit key), branch fallback — already correct and already has CAS-aware base-matching (reuse, don't rebuild) | no change to the key itself; the lane pin (D2) becomes the source of the `epic`/session-id argument this already accepts |
| Read | `read_state` → `read_state_from` → `epic_scoped_state_path` | `session.rs:414,397,63` | branch-only (the asymmetry) | switch the default to call `read_state_from_unit` (session.rs:408, already exists, t-3185) with the lane pin's key; miss → non-zero exit (D1) |
| Read (opt-in, already exists) | `read_state_from_unit` → `unit_scoped_state_path` | `session.rs:408,105` | resolves by the same unit key `write_state` uses, when caller supplies an explicit `epic` | promote from opt-in to the default path's resolver (see Read row) |
| Consume | `mark_consumed_for` → `epic_scoped_state_path` | `session.rs:881,63` | branch-only, and **writes** | same key function as write/read; a miss here must never write `consumed_at` onto another lane's file |
| Third resolution surface | `brana session path` → `cmd_session_path` | `brana-cli/src/commands/session.rs:275-280` (re-verified 2026-09-02) | resolves branch-first via `epic_scoped_state_path`, independent of the above | must resolve via the same key function — this is the mechanism that produced ADR-069 Reproduction 1's orphan-stub read (session-end hook probes with `path`, writes with `write`, reads a different file than it wrote) |

**D0b — store scoping:**

| Surface | File:line | Current | Required |
|---|---|---|---|
| Session state root | **SHIPPED t-2520** — `find_session_root()` → `git_common_root_in()` | `brana-core/src/util.rs` (`find_session_root_resolved`) | shared across worktrees | done; `find_project_root()` stays per-worktree for file-editing callers |
| Reference (already correct) | `find_tasks_config()` → `git_common_root()` | `brana-core/src/util.rs:158-165` | shared | no change — this is the pattern to copy |
| Known orphan | `~/.claude/projects/-home-martineserios-enter-thebrana-thebrana-feat-t-798/` | — | **SHIPPED t-2520** — adopted read-only | surfaced by `session read --all` as `legacy:feat-t-798/<lane>` via `session::find_legacy_stores`; never an implicit fallback target; stderr note when every legacy state falls outside the date window |

**D1 — every fallback surface must close, not just the first:**

| Surface | File:line | Current miss behavior | Required |
|---|---|---|---|
| `session-state.json` fallthrough | `brana-core/src/session.rs:56-64` | returns another lane's state | non-zero exit, actionable message |
| `handoff last` fallback | `brana-cli/src/commands/session.rs:106-135` (`cmd_session_read`, miss branch at 130 calls `handoff::cmd_handoff_last(1)`, re-verified 2026-09-02) | prints legacy markdown, `Ok(())` at line 134 regardless — exit 0 | non-zero exit on a real miss |
| MCP `session_read` | `brana-mcp/src/tools/session_read.rs:16-40` (re-verified 2026-09-02 — already has an opt-in `epic` param, t-3185; default path is still the branch-only guess) | `{"found": false}` on the default path — no exit code, and a caller cannot distinguish "genuinely nothing yet" from "wrong key, real state exists elsewhere" | the MCP tool result must carry an unambiguous typed miss signal distinguishing those two cases, on both the default and explicit-`epic` paths |
| `mark_consumed` | `session.rs:881` (`mark_consumed_for`) | writes to the mis-resolved file | see D0 row above |
| Shell caller idiom | `system/hooks/session-start.sh:514`, `session-end.sh:109` | `2>/dev/null \|\| VAR=""` converts loud failure back into silence | remove the swallow; handle the non-zero exit explicitly (log + documented degraded behavior, never silent empty-string substitution) |
| Chained legacy scan | `system/hooks/session-start.sh:575` | an empty result from the swallowed read activates another legacy scan | re-evaluate once the swallow above is removed — this trigger condition should no longer occur from a *miss*; confirm no other trigger depends on it |

**D2 — lane pin + resume query:**

- New pin file (location per Assumptions), atomic same-dir temp+rename write, written once
  at session start by the owning session only.
- Pin fields: `session_id`, `worktree_path`, `branch`, `task_id`, `head_at_start`,
  `dirty_at_start` (recorded, non-key per ADR-069 D2).
- New CLI surface: `brana session lane init --session-id <id>` (autonomous bootstrap path,
  called by the runner as it constructs the sandbox — not discovered from inside it).
- Resume query ranking: `worktree_path` match → `branch` match → `task_id` match. Report the
  matched rule and candidate count. Two equal-rank candidates = miss (D1), not arbitrary pick.
- Legacy files addressable as `legacy:<slug>`, enumerated only via `--all`, never resolved
  implicitly. Disambiguate filename-derived slug collisions at migration time (ADR-069 notes
  three files today all claim `harness-core`).
- **Rollback script** — required deliverable, not optional: session-id-keyed filenames are
  unreadable by a reverted (branch-regex-based) reader; a rename migration path back must
  ship alongside D2, not be improvised after the fact if D2 needs reverting.
- Also affected, per ADR-069 Consequences — **re-verified 2026-09-02, two of the four items
  below already shipped a partial fix (t-2506) and must not be re-fixed; the decision each
  still needs is narrower than "fix the bug":**
  - `dedup_next_items` (`session.rs:175`) and `merge_states`'s `next[]` handling
    (`session.rs:712`, key fn `next_item_key` at `session.rs:185`) **already dedupe by
    case-folded text, not `task_id` (t-2506) — this half is done.**
  - **Still open:** ADR-069 names "the same-day merge branch [i.e. `merge_states`'s own code
    path] stops firing" as one of exactly **two** live behaviors D2 silently retires (the
    other is `branch_has_active_worktree` below) — once every session writes its own
    per-session-id file, there is no more same-day/same-branch collision for `merge_states`
    to resolve. **This is a decision item, not a bug fix:** explicitly re-provide an
    equivalent (e.g. still merge same-lane same-day writes) or explicitly retire the whole
    code path. See Boundaries.
  - `branch_has_active_worktree` clobber guard (`session.rs:1191`, added for t-2263) is
    **still live** (D2 hasn't shipped) and becomes dead code once filenames are per-session
    rather than per-path — decide explicitly whether to re-provide its guarantee under the
    new keying or drop it deliberately. See Boundaries.
  - `system/hooks/session-end-persist.sh:240-242` performs an unlocked `jq … > tmp && mv`
    read-modify-write on a session-state file after `session write` — D3b's single-writer
    premise must extend to cover this writer, not just the pin.

**D3 (excluding D3.2) — shared-checkout guards, dependent on D2:**

| Surface | Notes |
|---|---|
| `system/scripts/git-hooks/pre-commit` | already worktree-safe via `git rev-parse --git-path`; D3.3's guard composes here, must compose with `no-attribution-commit.sh` rather than replace it |
| `commit-msg` sibling hook | D3.3 host surface |
| bootstrap's `core.hooksPath` resolution step | must resolve the effective hooks path correctly for the guard to install |
| D3.3 guard predicate | `dirty_at_start` alone (the "and this lane never wrote it" predicate is dropped as unknowable — no per-lane write ledger exists, and building one is out of scope). `--adopt-path`'s exact argument shape (single path vs. repeatable vs. glob) is undecided by ADR-069 and this spec — resolve during t-2524 implementation, default to repeatable single-path flags unless a concrete multi-path case is found |
| `git commit -a` in the shared checkout | rejected outright — cannot express authorship |
| Git-dir resolution inside the guard | must use `git rev-parse --git-common-dir`, not an assumption that `.git/` is a directory (worktrees use gitlinks) |

**Accepted limitation, named not silently absorbed (challenger review, 2026-09-02):**
`git commit --no-verify`, or reassigning `core.hooksPath`, trivially and totally bypasses
D3.3's pre-commit guard — same as it bypasses `no-attribution-commit.sh` today. This is a
cooperative-safety mechanism (catches accidents, not adversarial bypass), consistent with
this repo's existing hook posture; it is not a security boundary, and D3.3 does not attempt
to become one. No backstop is proposed here — flagging so a future reader does not assume one
exists.

**Sitrep** (Consequences, not a Surfaces-table item but load-bearing): must state which lane a
handoff came from; ambiguity there is the ADR's own named operator-visible symptom.

## Behavior

- **Happy path (worktree lane):** a session starts in a linked worktree, `SessionStart`
  writes a lane pin keyed by session id. All session-state reads/writes/consumes for that
  session resolve through the pin — no epic or branch guessing. `/brana:close` on that
  worktree reads back exactly what that session wrote, every time, regardless of what branch
  it's on or what other lanes exist.
- **Resume:** a new session in the same worktree queries the lane store, finds the prior
  lane's pin by `worktree_path` match, and states "resuming via worktree_path match, 1
  candidate" before loading that lane's handoff.
- **Miss:** no lane resolves (fresh worktree, pin missing/corrupt/stale) → `session read`
  exits non-zero with an actionable message naming which resolution rule was tried and
  failed. No consumer may silently substitute another lane's file or an empty stub.
- **Autonomous run:** the runner calls `brana session lane init --session-id <id>` before
  launching the sandboxed `claude -p`; that run's session state resolves through the same
  pin mechanism as an interactive session, just without ever passing through `SessionStart`.

## Edge Cases

- **Two live pins match one cwd** (shared main checkout, two sessions both working there) →
  detected as a miss per D1, not resolved by picking either.
- **Crashed session leaves a stale pin** → `brana session lanes --prune` reaps it; a stale pin
  found before pruning must degrade toward *more* fail-loud, never toward silent success.
- **Corrupt pin file** → treated identically to a missing pin (never partially parsed).
- **A lane merges and its worktree is removed before it closes** → D3.2 would have been
  unavailable here anyway (reflog gone); this spec does not implement D3.2, so this edge case
  has no attribution regression to worry about — commit attribution for this spec's scope is
  D3.1's `shared`-refusal only, not per-commit attribution.
- **`git commit -a` attempted in the shared main checkout** → rejected outright by D3.3,
  regardless of whether the staged set actually includes a foreign-dirty path.

## Boundaries

| Always | Ask First | Never |
|--------|-----------|-------|
| Resolve session-state read/write/consume through one key function | Redesigning D3.2 (reflog attribution) as a commit-time mechanism — that's new-ADR scope, not this spec | Touch `save_tasks`, `write_atomic`, or `lock_tasks` |
| Fail loud (non-zero exit) on a session-state key miss | ~~Dropping or re-providing the `branch_has_active_worktree` guard's guarantee~~ — **DECIDED 2026-09-04 (t-3296): KEPT, unmodified.** See Retirement Decisions below. | Silently substitute another lane's file, or an empty stub, for a miss |
| Ship the D2 rollback/migration script alongside D2 itself | ~~Dropping or re-providing `merge_states`'s same-day-merge code path~~ — **DECIDED 2026-09-04 (t-3296): KEPT, unmodified.** See Retirement Decisions below. | Implement D3b's original "missing pin ⇒ fail loud" for the autonomous surface (retracted) |
| Reuse `write_state_with_base`'s existing CAS logic, `is_safe_epic_slug`'s existing slug guard, and `read_state_from_unit`'s existing unit-keyed read for D0/D2 | Choosing the lane pin's exact file path/format if it diverges from the Assumptions section | Re-implement CAS matching, slug validation, or unit-keyed reads from scratch when a correct primitive already exists (t-2506/t-3169/t-3185) |

### Retirement Decisions (t-3296, 2026-09-04)

Both decisions this spec flagged as "must be explicit, not silent by omission" turned out
to hinge on one fact discovered while implementing t-3292/t-3295: **this implementation
did not rekey session-state files by `session_id`.** D0's Read/path rows and D2's lane
pin were both implemented via the *existing* initiative/focus-marker mechanism
(`session_initiative::read_focus_marker`/`read_initiative_marker`) rather than by
changing `unit_scoped_state_path`'s naming scheme — see t-2521's context log for the full
rationale (a genuine test contradiction between two already-merged RED tests made the
literal "lane pin's key" reading unsafe to implement as an epic/session-id rekeying; the
conservative, test-verified fix was chosen instead). Session-state files are therefore
still keyed by epic/branch, exactly as before this spec — **not** one file per session id.

Both retirement candidates were premised on "once every session writes its own
per-session-id file" — a precondition that never became true here. Consequently:

- **`merge_states`'s same-day-merge code path (`session.rs:803`, called from
  `write_state_with_base`): KEPT, unmodified.** Multiple sessions can still land writes on
  the exact same file (same epic/branch, same day) exactly as before D0/D1/D2 shipped —
  the collision case this code resolves is unchanged and still live.
- **`branch_has_active_worktree` clobber guard (`session.rs:1282`, t-2263): KEPT,
  unmodified.** Files are still shared per-unit, not per-session, so a mis-detected epic
  can still route a write into another still-live session's file — the guard's guarantee
  is still needed for the same reason it was added.

If a future task *does* rekey session-state files by session_id (the D2 "Also affected"
bullets' original premise), both of these decisions must be revisited — they are sound
only under "files are shared per-unit," which remains this implementation's actual state.

### Rollback (t-3297, 2026-09-04)

The spec's rollback/migration script requirement was premised on session-state
*filenames* becoming session-id-keyed and therefore unreadable by a reverted
branch-regex-based reader. Per the Retirement Decisions above, that rekeying never
happened here — `session-state.json`/`session-state-{epic}.json` naming is byte-for-byte
unchanged from before this spec. The only new persistent artifact is the lane pin store
(`{memory_dir}/lanes/*.json`), which is purely additive: no existing file was renamed,
moved, or reformatted to create it.

**Consequence: no migration script is needed.** Reverting D2 is `rm -rf
{memory_dir}/lanes/` (or simply reverting the code — `session-start.sh`'s `lane init`
call and the `brana session lane init/resume` CLI surface) plus removing the SessionStart
hook's call to it; every session-state file underneath is untouched and immediately
readable by pre-D2 code with zero data loss. No script was built for a migration that
does not exist — the AC as originally written assumed a precondition (t-2521 context has
the full record of why it wasn't implemented) that turned out false.

## Testing Strategy

- **Unit:** the key-resolution function (D0) — read/write/consume must resolve identically
  given the same lane pin; miss detection logic (D1); resume-query ranking (D2, including the
  equal-rank-is-a-miss case); D3.1's `shared` classification; D3.3's `dirty_at_start` guard
  predicate. Target 70%+ of the test budget — nearly all of this logic is pure given a lane
  pin and a store snapshot as fixtures.
- **Integration:** D0b's `git_common_root()`-based resolution against a real multi-worktree
  checkout (mirrors `find_tasks_config`'s own test shape); the pin's atomic write under
  concurrent session starts; the pre-commit guard (D3.3) against a real shared checkout with
  a foreign-dirty path staged.
- **E2E / smoke:** one full lifecycle — session start in a worktree → work → close →
  worktree removed → new session resumes correctly via `worktree_path`/`branch`/`task_id`
  ranking; one autonomous-runner smoke test confirming `lane init --session-id` produces a
  working pin without `SessionStart`.
- **Mock policy:** real git repos/worktrees in temp dirs for D0b/D3.3 tests (git behavior is
  exactly what's under test); no mocking of `save_tasks`/`write_atomic`/`lock_tasks` — those
  are out of scope and already correct.

## Documentation Plan

- [x] **User guide** — `docs/guide/features/lane-identity.md` (2026-09-04): lane pin
  existence, resume's matching-rule reporting, miss-is-an-error, `lane init`/`lane resume`
  usage. `lanes --prune` and the shared-checkout `git commit -a`/`--adopt-path` material
  are D3 (t-2524) scope, not built here — the guide says so rather than documenting
  commands that don't exist yet.
- [x] **Tech doc** — this file doubles as the tech doc; Status line updated 2026-09-04
  to reflect t-2520+t-2521 shipped, t-2524 (D3) not started.
- [ ] **Existing docs to update** — `docs/guide/workflows/drain-loop.md` and
  `docs/guide/workflows/epic-drain.md`'s close-anchor language (once D2 lands, `t-2502`'s
  epic-scoped anchor workaround should be revisited per ADR-069 Consequences: "t-2502
  unparks once D1 + D2 land"); `system/skills/close/phases/gate-and-evidence.md`'s
  CLOSE-ANCHOR-BLOCK and `system/skills/close/phases/session-state.md`'s Tier 0-3
  corroboration cascade both become largely unnecessary once reads resolve by lane pin
  instead of epic-guessing — flag for simplification, not deletion, in the implementation
  tasks (t-2520/t-2521), not this spec.

## Challenger findings

**Iteration 1 (2026-09-02): RECONSIDER.** Exhaustive ADR-table-to-Surfaces cross-check
confirmed complete and file:line-accurate; status framing and scope/out-of-scope internal
consistency confirmed correct; no scope creep found. Two Critical findings, both fixed in
this revision:

1. The spec's "current behavior" premise had drifted behind three tasks that landed after
   ADR-069 was drafted (t-2506, t-3169, t-3185) — `dedup_next_items`/`merge_states` were
   described as still-open `task_id`-keyed bugs when they're already fixed by text-based
   dedup; `read_state_from_unit`, `is_safe_epic_slug`, `write_state_with_base`, and
   `ORPHAN_EPIC_SENTINEL` are new reusable primitives that existed nowhere in the spec.
   **Fixed:** re-verified every session.rs/session_read.rs claim directly against the live
   worktree, corrected the D0/D1 tables and D2's "Also affected" bullets, and added an
   Assumptions subsection naming each primitive to reuse.
2. ADR-069 names exactly two live behaviors D2 silently retires
   (`branch_has_active_worktree` and `merge_states`'s same-day-merge path); only the first
   was captured as a Boundaries decision item. **Fixed:** added the second to Boundaries.

Three Warnings addressed: ADR-069's Accepted-status gap named as an explicit Constraint
precondition; D3.3's `git commit --no-verify`/`core.hooksPath` bypass named as an accepted,
non-security-boundary limitation; the D3b retraction-scope ambiguity ("all of D3b" vs. "just
its missing-pin row") resolved explicitly per no-silent-ambiguity-fill, with the reading
stated and open to correction before t-2521 starts.

Two Observations addressed: `--adopt-path`'s argument shape flagged as undecided (default
proposed, resolve at t-2524); the context-economy NFR restated as an explicit, testable
Constraint.

**Iteration 2 (2026-09-02, final): PROCEED WITH CHANGES.** Verification-only pass confirmed
both Critical fixes and all three Warning fixes against live code, with one exact-match
regression test found supporting the `session_read` miss-signal claim
(`test_session_read_explicit_epic_finds_state_branch_guess_would_miss`). Found the identical
stale-citation class one bullet outside the first fix's aperture — `find_tasks_config`'s
`git_common_root()` call site was cited as `util.rs:158-165`, actually `util.rs:210-213` —
plus two more drifted `brana-cli/src/commands/session.rs` line ranges and a
`next_item_key`/`dedup_next_items` off-by-4 (181→185). **All four fixed in this revision,
re-verified directly:** `cmd_session_path` (the `brana session path` surface) is at
`session.rs:275-280`; the `handoff last` fallback is `cmd_session_read`'s miss branch at
`session.rs:106-135`, calling `handoff::cmd_handoff_last(1)` at line 130 and returning
`Ok(())` regardless at line 134 — substance of both ADR claims confirmed exactly, only line
numbers had drifted. No RECONSIDER-severity finding in either iteration. Repair loop closed
at 2/2 iterations per the hard cap.
