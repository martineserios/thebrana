# Feature: Session-Scoped Epic Focus

**Date:** 2026-08-24
**Status:** shipped
**Task:** t-3196

## Problem

`brana backlog focus` (and everything that reads `active_epic`) boosts ranking
for one epic, sourced from `.claude/tasks-config.json` — a single mutable
value shared by every session working in that project directory. This is a
category error: epic focus is a per-session concept (which epic *this*
session is working), not a per-project one. Two or more sessions opened from
the same directory, each on a different epic, is the everyday pattern — one
session's `set-active` silently redirects every other session's focus.
Full context and the decision record: [ADR-088](../decisions/ADR-088-session-scoped-epic-focus.md).

## Decision Record

See [ADR-088](../decisions/ADR-088-session-scoped-epic-focus.md) — full
context, decision, and consequences live there, not duplicated here.

## Constraints

- Must not regress ADR-066's cross-*project* isolation guarantee — this
  change removes the shared file entirely, which is a strict superset of that
  guarantee (nothing left to leak across projects because nothing is shared).
- Must not introduce a new session-identity mechanism keyed on
  `$BRANA_SESSION_ID` or any other unverified-propagation channel (see
  ADR-088 Context — t-2921 precedent, re-confirmed live during this task's
  SPECIFY).
- `assert_active_epic_resolves()` (`brana-core/tasks/query.rs:110`) must be
  reused for branch-slug validation, not reimplemented.

## Scope (v1)

- **`brana-core`**: new `resolve_focus_epic()` helper — implements the 3-tier
  order (explicit arg → task-derived epic of the most-recently-started
  in_progress task → none), generalizing `statusline.sh`'s existing
  v2-flat-field/v3-parent-chain fallback (`statusline.sh:36-90`) into a
  reusable core function. Replaces the `load_tasks_config()["active_epic"]`
  read in both call sites below.
- **`brana-cli/commands/backlog.rs::cmd_focus`** (`backlog.rs:274`) — switch
  from `cfg["active_epic"]` fallback to `resolve_focus_epic()`.
- **`brana-mcp/tools/backlog_focus.rs`** — same switch, MCP side
  (`backlog_focus.rs:39`).
- **Remove `cmd_set_active`** (`backlog.rs:556`) and its CLI subcommand
  wiring (`cli.rs`) — the write path has no reader left once the above ship.
- **Remove `active_epic` handling from `PROJECT_SCOPED_CONFIG_KEYS`**
  (`brana-core/util.rs:228`) and `load_tasks_config()`'s scoping logic for it
  — dead code once no call site reads the key.
- **Remove `active_epic` contamination guards from `sync-state.sh`**
  (`cmd_push` ~line 146, `cmd_pull` ~line 253) — nothing left to sync.
- **Fix `assert_active_epic_resolves()`'s error string** (`query.rs:122`) —
  currently tells the user to check `tasks-config.json`'s `active_epic` or
  run `set-active`, both retired by this change.
- **`statusline.sh`** — delete only its now-dead final fallback (the
  `active_epic` config read at `statusline.sh:91-98`). Its 3-segment-branch
  match and task-derived fallback (lines 36-90) are the mechanism this spec
  generalizes into `resolve_focus_epic()` — no new statusline logic needed.
- **Skill procedures**: `system/skills/backlog/SKILL.md` — both the CLI/MCP
  command table row for `set-active` (removal) and the separate prose
  paragraph (~line 65) describing project-local `active_epic` resolution
  (rewrite to describe task-derived resolution). Also
  `system/skills/backlog/phases/views.md` or wherever `focus`'s behavior is
  documented for LLM sessions.
- **Migration script retirement**: `system/scripts/migrate/audit-orphaned-active-epic.py`
  (t-2281) becomes moot once no project's `active_epic` is ever authoritative
  — leave in place (harmless, already idempotent) or delete; not a hard
  requirement either way, noted for the implementer's judgment call during
  DECOMPOSE.
- **Migrate the 6 existing `active_epic`/`set-active` tests in**
  **`brana-cli/tests/cli_smoke.rs`** (~lines 291, 316, 335, 363, 391, 542,
  plus the fixture at ~276-288) — each asserts behavior this spec deletes;
  rewrite against the new resolution or remove, per-test judgment call
  during DECOMPOSE (don't leave any passing for the wrong reason — see
  ADR-088 Consequences for the `set_active_hard_stop...` example).
- New regression tests covering: task-derived resolution for both v2
  (flat `.epic` field) and v3 (parent-chain) schemas, no-match fallback (no
  in-progress task, or none carrying a resolvable epic), explicit `--epic`
  override still wins, `set-active` command absence (CLI no longer accepts
  it), `cmd_focus`/MCP `backlog_focus` parity (both use the same core helper
  — no shape divergence like the one ADR-066's spec found between them).

## Research

- `brana_core::util::load_tasks_config()` and `PROJECT_SCOPED_CONFIG_KEYS`
  (t-2158) — current active_epic read/scoping, confirmed via direct code
  read (`util.rs:226-234`).
- `cmd_set_active` (t-2155, `backlog.rs:556`) — current write path.
- `assert_active_epic_resolves()` (`query.rs:110`) — existing
  epic-node-or-flat-tag validator, reusable as-is against a branch-derived
  slug instead of a config-sourced one.
- `resolve_epic_ancestor()` (`system/skills/_shared/epic-ancestor-walk.md`)
  — the existing shell-level mechanism that derives a task's epic slug from
  its `parent` chain, used today to *construct* branch names
  (`{epic-slug}/{work-type}/t-{NNN}-{desc}`) at `/brana:backlog start`. This
  feature's tier 2 is the inverse operation — parsing that same slug back out
  of the branch name at focus-time — so no new epic-encoding is introduced;
  this only reads back what branch creation already writes.
- `sync-state.sh` push guard (t-1883, ~line 146) and pull guard (t-2469,
  ~line 253) — both retired wholesale, not modified, once `active_epic` has
  no authoritative source to sync.
- `statusline.sh:95` — direct `jq` read of `active_epic`, confirmed the only
  other non-Rust, non-sync-state.sh consumer.
- t-2921 (2026-08-17) — `$BRANA_SESSION_ID` propagation to Bash-tool
  subprocesses found unverified and contradictory; redesigned its own
  session-scoped correctness invariant (ADR-083 Metric 1's open-bracket lock)
  to per-worktree (`git rev-parse --git-dir`) instead. Re-probed live during
  this task's SPECIFY (2026-08-24): `$BRANA_SESSION_ID` present and stable
  across two Bash calls, but `$CLAUDE_ENV_FILE`/`$CLAUDE_PROJECT_DIR` both
  empty at the same time — identical anomaly, independently reproduced eight
  days later.

## Assumptions

- **Tier 3 (same-checkout, same-branch, multi-session disambiguation) is
  dropped, not deferred with a stub.** Discussed directly with the user
  during SPECIFY: given no reliable session-identity signal exists, the
  choice was between (a) collapsing to explicit-flag + branch-derived
  resolution only, or (b) building a new purpose-built session registry
  (PID-keyed or transcript-mtime-keyed, mirroring t-2921's own resolution).
  User chose (a) — confirmed 2026-08-24.
- **Task-derived resolution assumes an in-progress task exists and is
  current.** A session with nothing started yet (no `in_progress` task in
  the project), or one whose worktree has drifted from the task it was
  started for, gets no epic boost or a stale one respectively — the latter
  is the accepted worktree-rule-violation risk documented in ADR-088
  Decision, not a new failure mode this design introduces (statusline.sh
  carries the identical assumption today).
- **Task-derived, not branch-derived** (revised during challenger review,
  2026-08-24): the original draft parsed the branch name's first segment
  directly. That approach silently drops epic-focus for every v2-schema
  (client/venture) project, which uses a 2-segment branch convention with no
  epic segment and mostly works on `main`/`dev` rather than per-task
  branches. Reading the in-progress task's own epic — the same fallback
  `statusline.sh` already implements — covers both schemas with one
  mechanism.
- **`active_initiative` is out of scope** — no evidence it shares the
  same-directory-multi-session problem; see ADR-088 Non-Actions.

## Behavior

- Running `brana backlog focus` (or the MCP `backlog_focus` tool) from a
  worktree with an `in_progress` task parented under the `session` epic
  boosts tasks under `session` — no config file involved.
- Running the same command with no `in_progress` task in the project (or one
  whose epic ancestor doesn't resolve) shows plain P0/P1-ordered focus, same
  as "no active epic" behaves today.
- Passing `--epic <slug>` explicitly still overrides both, unchanged.
- `brana backlog set-active <slug>` no longer exists as a command — running
  it returns "unknown subcommand" (or equivalent CLI error), not a silent
  write to a file nothing reads.
- The statusline's epic segment continues to reflect the current branch (3-segment
  match) or the most-recently-started in-progress task's epic, exactly as it
  does today — unchanged behavior, only its dead config-read fallback is
  removed.
- Client/venture (v2-schema) projects, which mostly work on `main`/`dev` with
  a 2-segment branch convention, now get epic-boosted focus from their
  in-progress task's flat `.epic` field — a case the original branch-string
  draft of this design silently dropped.

## Edge Cases

- **No `in_progress` task in the project** — falls through to no-epic-boost;
  not an error.
- **In-progress task's epic doesn't resolve** (v3: parent chain has no valid
  epic-node ancestor; v2: flat `.epic` field present but doesn't match any
  real epic node or tag) — falls through to no-epic-boost, same as tier 2's
  removal case; not an error.
- **Multiple in-progress tasks in one project** — most-recently-started wins,
  tie-broken by numeric task ID (identical to `statusline.sh`'s existing
  tie-break); this is the accepted worktree-rule-violation risk from ADR-088
  when two sessions share one checkout.
- **A project with zero epic nodes at all** (v3) or no task ever carrying a
  flat `.epic` value (v2) — `resolve_focus_epic()` returns `None` for every
  invocation; focus behaves exactly as it does today for such a project
  (pure P0/P1).

## Design

- `resolve_focus_epic(explicit: Option<&str>, all_tasks: &[Value]) -> Option<String>`
  in `brana-core` (new, colocated with `assert_active_epic_resolves` in
  `tasks/query.rs` or a new `focus.rs` — implementer's call during DECOMPOSE):
  1. If `explicit.is_some()`, return it as-is (existing behavior — caller
     already validates via `assert_active_epic_resolves` downstream).
  2. Else, find the most-recently-started task with `status == "in_progress"`
     in `all_tasks` — same selection and tie-break (started date, then
     numeric task ID descending) `statusline.sh:78-89`'s jq query already
     uses. If none exists, return `None`.
  3. If that task carries a non-empty flat `.epic` field (v2/client-venture
     schema), return it directly — this is already-validated data (a task
     wouldn't carry an `.epic` value that doesn't correspond to real prior
     usage in that project).
  4. Else (v3/thebrana schema, no flat `.epic` field), resolve the task's
     epic ancestor via the same parent-chain walk
     `resolve_epic_ancestor()` already performs
     (`system/skills/_shared/epic-ancestor-walk.md`) — ported to Rust here
     rather than shelled out to, since this runs inside `brana-core`, not a
     shell skill procedure. Validate the result against real epic nodes
     using the same logic `assert_active_epic_resolves()` already runs, but
     non-fatal: return `Some(slug)` on match, `None` on no match (the
     caller-facing contract differs from `assert_active_epic_resolves`:
     `cmd_focus`/`backlog_focus` need "give me an epic or nothing," not
     "fail if the epic doesn't resolve" — that stricter fail-loud behavior
     stays `assert_active_epic_resolves`'s job for an *explicit* `--epic`
     that didn't resolve, unchanged).
  5. Both `cmd_focus` and MCP `backlog_focus` call this one helper — closes
     the exact shape-divergence class ADR-066's spec found between the two
     (t-2281 Design section).
- **`assert_active_epic_resolves()`** (`query.rs:110-124`): validation logic
  reused as-is; its error string (line 122) is rewritten to drop the
  `tasks-config.json`/`set-active` references and describe the new
  resolution order instead.
- **`statusline.sh`**: no new logic. Delete the dead final fallback
  (`statusline.sh:91-98`, the `active_epic` config read) — lines 36-90
  already implement the exact task-derived resolution `resolve_focus_epic()`
  generalizes into Rust; both now share one mechanism, expressed twice
  (shell for the hot-path statusline render, Rust for `cmd_focus`/MCP) rather
  than the statusline shelling out to `brana` per-render (a new
  `brana`-subprocess-per-render would very likely blow the statusline's
  existing latency budget — `docs/architecture/features/statusline-test-coverage.md`
  — so the two implementations stay independent, both derived from the same
  design, not unified into a single code path).
- `cmd_set_active` and its `cli.rs` subcommand entry: deleted, not
  deprecated-with-a-warning — ADR-088's decision is that writing it is
  actively misleading (implies an effect it no longer has), so a clean
  removal with a clear CLI error is preferable to a silent no-op.

## Boundaries

| Always | Ask First | Never |
|--------|-----------|-------|
| Resolve epic focus from `--epic` or the most-recently-started in-progress task's epic | Deleting `system/scripts/migrate/audit-orphaned-active-epic.py` outright (vs. leaving it as inert) | Add a new session-identity mechanism keyed on `$BRANA_SESSION_ID` or an unverified propagation channel |
| Reuse `assert_active_epic_resolves()`'s validation logic and `statusline.sh`'s existing v2/v3 fallback shape | Changing `active_initiative`'s resolution (out of scope) | Reintroduce `active_epic` as a config-file-read value anywhere |

## Testing Strategy

- **Unit:** `resolve_focus_epic()` — most-recently-started-task selection and
  tie-break, v2 flat-`.epic` path, v3 parent-chain path, no-in-progress-task
  case, unresolvable-epic case, explicit-arg short-circuit. Target 70%+ of
  test budget — pure logic over an in-memory task list, no I/O.
- **Integration:** `cmd_focus`/`backlog_focus` end-to-end against fixtures —
  a v3-schema project with a resolvable in-progress task's epic ancestor, a
  v2-schema project with a flat `.epic` in-progress task, a project with no
  in-progress task; `set-active` subcommand absence (CLI parse error, not a
  silent write); `sync-state.sh` push/pull run clean with no `active_epic`
  key present in either file (guard code removed, not just untriggered).
- **Migration:** the 6 existing `active_epic`/`set-active` tests in
  `cli_smoke.rs` (~291, 316, 335, 363, 391, 542, fixture ~276-288) are
  updated or removed as part of this same change — not left to fail, and not
  left "passing" against the wrong mechanism (e.g. a bare clap parse error
  standing in for the removed command's intended application-level error).
- **E2E:** one CLI smoke test confirming `brana backlog focus` on a real v3
  fixture repo with an in-progress task under a real epic shows that epic
  boosted, and one confirming the same for a v2 fixture — extending
  `cli_smoke.rs`'s active-epic coverage rather than only replacing it —
  target 5%.
- **Mock policy:** real task-list fixtures (in-memory or temp-file JSON), no
  network, no `git` shellout needed for the core resolver (task-derived, not
  branch-derived) — simpler to test than the rejected branch-parsing design
  would have been.

## Documentation Plan

- [ ] **User guide** — `docs/guide/features/session-scoped-epic-focus.md`
  (or fold into an existing backlog/focus guide page if one covers `focus`
  already): explain the new resolution order, that `set-active` is gone, and
  how to get epic-boosted focus (start a task under the epic, or pass
  `--epic`).
- [x] **Tech doc** — this file, plus ADR-088.
- [ ] **Existing docs to update**: `system/skills/backlog/SKILL.md` — both
  the CLI/MCP table rows referencing `set-active` (remove) AND the separate
  prose paragraph (~line 65) describing project-local `active_epic`
  resolution (rewrite for task-derived resolution) — these are two distinct
  edits in the same file, not one; `system/skills/backlog/phases/views.md`
  or wherever `focus` behavior is documented for LLM sessions; ADR-066 gets
  a superseding pointer to ADR-088 at its top (not rewritten — historical
  record stays intact, per how ADR-066 itself points forward, not backward,
  when things change).

## Challenger findings

**Round 1 (2026-08-24): RECONSIDER.** Findings and resolutions:
1. **[Sev 4] Branch-string tier 2 silently drops epic-focus for v2-schema
   (client/venture) projects** — their 2-segment branch convention has no
   epic segment, and they mostly stay on `main`/`dev`. **Fixed**: tier 2
   redesigned as task-derived (most-recently-started in-progress task's
   epic), generalizing `statusline.sh`'s existing v2/v3 fallback instead of
   parsing the branch name. See Design, Assumptions.
2. **[Sev 4] 6 existing `cli_smoke.rs` tests assert deleted behavior**,
   unaddressed in the original Testing Strategy. **Fixed**: explicit
   migration item added to Scope and Testing Strategy.
3. **[Sev 4] `SKILL.md`'s prose paragraph (not just its table row) references
   the retired mechanism** — a recurrence of a pattern already seen once in
   this ADR lineage. **Fixed**: both edits now named explicitly in Scope and
   Documentation Plan.
4. **[Sev 3-4] `assert_active_epic_resolves()`'s error string names both
   retired mechanisms** (`tasks-config.json`, `set-active`) and was going to
   ship unchanged. **Fixed**: added to Scope and Design as an explicit edit.
5. **[Sev 3] Worktree-rule violation is a sharper trigger for the original
   bug than the old mechanism** (an ordinary `git checkout`, no
   epic-setting intent needed, vs. a deliberate `set-active` call).
   **Addressed, not fixed**: documented as an accepted, pre-existing risk in
   ADR-088 Decision — `statusline.sh` already carries the identical
   assumption today without incident; the mitigation is the standing
   worktree-per-session hard rule, not new code this design owes.

Verified sound by the challenger (no change needed): the tier-3 drop's
justification ($BRANA_SESSION_ID unreliability, independently reproduced
twice 8 days apart); `assert_active_epic_resolves()`'s reusability; the
consumer sweep's completeness (Rust/shell call sites confirmed accurate via
independent grep).
