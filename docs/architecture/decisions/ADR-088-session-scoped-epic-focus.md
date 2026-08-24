---
status: accepted
---
# ADR-088: Epic Focus Resolves Per-Session, Not Via a Shared `active_epic` File

- **Status:** Accepted
- **Date:** 2026-08-24
- **Amends:** [ADR-066](ADR-066-active-epic-project-scoped-only.md) (`active_epic` resolve project-scoped only)
- **Evidence:** t-3196 (this task), user verdict 2026-08-24 (memory: `feedback_active-epic-shared-state-is-bad`)
- **Related:** ADR-065 (epic-as-hierarchy-top), [pattern: session-write-epic-autodetect-wrong-file](../../../.claude/memory), [field-note: epic-auto-detection-concurrent-sessions](../../../.claude/memory)

## Context

ADR-066 fixed `active_epic` to resolve from exactly one project-local file
(`.claude/tasks-config.json`) instead of leaking across projects via the global
config. That closed the cross-*project* bleed. It did not — and could not,
given its own scope — close a second, orthogonal category error: `active_epic`
is stored as one mutable value per **project**, but epic focus is actually a
per-**session** concept. Two or more Claude Code sessions opened from the same
project directory, each intentionally working a different epic, is the
project's everyday pattern (user verdict, 2026-08-24), not an edge case. Under
ADR-066's model, one session calling `brana backlog set-active` redirects
every other concurrent session's focus ranking without warning — proven twice:
a test run polluted `active_epic` repo-wide (2026-08-24 incident), and the
"session-write epic-poisoning" pattern class was independently observed before
that. Shared mutable state standing in for a per-session concept is a
recurring defect source, not a one-off bug.

**A design constraint surfaced during this task's own SPECIFY** rules out the
most direct fix (key resolution by a session identifier). The task's original
proposal included a 3rd resolution tier — "the invoking session's own active
in_progress task's epic ancestor" — meant to disambiguate same-directory,
same-branch, concurrent sessions. The only session-identity signal available
to a `brana` CLI subprocess is `$BRANA_SESSION_ID`. t-2921 (2026-08-17, ADR-083
Metric 1 SPECIFY) already attempted exactly this kind of session-scoped
correctness dependency and reversed it after a challenger caught that the
env var's propagation to Bash-tool-invoked subprocesses is **unverified and
contradictory**: it was observed set in a live session despite
`$CLAUDE_ENV_FILE`/`$CLAUDE_PROJECT_DIR` — the documented channels that are
supposed to carry it — both being empty at the same time, meaning some other,
untraced mechanism sets it. Re-probed live during this task's SPECIFY
(2026-08-24): the identical anomaly reproduces today. Two independent findings,
eight days apart, agree — this is not safe ground to build a correctness
invariant on.

## Decision

**Retire the shared `active_epic` write path.** Focus resolution stops reading
any config file and instead resolves in this order, entirely from state that
is already scoped correctly (per-branch, per-worktree) or explicitly supplied:

1. **Explicit `--epic <slug>` flag** — always wins, same as today.
2. **Task-derived: the epic of the most-recently-started `in_progress` task.**
   Reuses the exact fallback `statusline.sh` (lines 36-98) already had to
   build and ship for this same schema split, rather than a new
   branch-string parse:
   - **v2 schema (client/venture projects)** — most-recently-started
     `in_progress` task carrying a non-empty flat `.epic` field wins ties
     broken by numeric task ID, same tie-break statusline already uses.
   - **v3 schema (thebrana)** — most-recently-started `in_progress` task,
     resolved to its epic ancestor via `resolve_epic_ancestor()`
     (`system/skills/_shared/epic-ancestor-walk.md`), the same parent-chain
     walk that already constructs branch names at
     `/brana:backlog start` time.
   - This is deliberately **task-derived, not branch-string-derived**: an
     earlier draft of this ADR proposed parsing the current branch's first
     `/`-segment directly. Challenger review (2026-08-24) caught that this
     silently drops epic-focus entirely for every v2-schema (client/venture)
     project, which uses a 2-segment branch convention
     (`{work-type}/t-{NNN}-{desc}`, no epic segment at all) and mostly stays
     on `main`/`dev` rather than cutting per-task branches — not an edge
     case, their steady state (documented in `statusline.sh:39-44`). Reading
     the in-progress task's own epic, instead of trying to recover it from
     the branch name, works identically for both schemas and needs no new
     mechanism — it generalizes a fallback that already shipped and is
     already trusted for the statusline's own epic badge.
3. **No match → no epic boost.** Falls through to plain P0/P1 priority
   ordering, identical to today's "no `active_epic` set" fallback.

The proposed 3rd tier from the original ask (same-checkout, same-branch,
multi-session disambiguation via "this session's own in-progress task") is
**not built as a separate tier** — tier 2 above already resolves to a
specific in-progress task, which is as close as this design gets to that
intent without a session-identity signal. Two independent findings (t-2921,
and this task's live re-probe) agree `$BRANA_SESSION_ID` cannot carry a
correctness guarantee across the Bash-tool subprocess boundary, and no other
session-identity signal exists at the CLI layer.

**Accepted risk — worktree-rule violation.** This repo's hard rule
(git-discipline.md) is one worktree per concurrent session; tier 2's
"most-recently-started in-progress task" heuristic assumes that holds. If two
sessions share one checkout in violation of that rule, an ordinary
`git checkout` by either session — no epic-setting intent required — changes
which task is "current" for tier 2's resolution in that shared checkout, and
both sessions' focus ranking shifts together. This is a real, sharper trigger
than the old mechanism (which needed a deliberate `set-active` call to
misdirect another session), but it is **not a new risk this ADR introduces**:
`statusline.sh` already resolves its epic badge the same way, under the same
assumption, and has shipped without incident. Not fixed here — the fix is
"don't violate the worktree rule," which is already the standing hard rule,
not a new mitigation this design owes.

**Consequently, the entire shared-file mechanism this ADR retires becomes
unreachable code once its last reader is removed:**
- `brana backlog set-active` (CLI write path, t-2155) — removed. Nothing reads
  `active_epic` from a config file anymore, so writing one is a no-op that
  misleads whoever runs it into thinking it did something.
- `PROJECT_SCOPED_CONFIG_KEYS` handling of `active_epic` in
  `brana_core::util::load_tasks_config()` (t-2158) — the key is no longer read
  by anything; the scoping logic for it is dead code once removed from all
  call sites.
- `sync-state.sh`'s `active_epic` contamination guards, both directions
  (t-1883 push guard, t-2469 pull guard) — nothing left to contaminate; the
  key is no longer copied between the deployed cache and the repo state at
  all.
- `active_epic` in the `tasks-config.json` schema itself — the field is
  dropped, not just unread; a `tasks-config.json` on disk with a leftover
  `active_epic` key from before this change is a harmless orphan, matching
  the same shape ADR-066's own migration script already handles.

**`statusline.sh` needs no new logic — only a deletion.** It already
implements tier 2's exact resolution (3-segment branch match, then
most-recently-started in-progress task's epic, v2-flat-field or v3-parent-chain
depending on schema — `statusline.sh:36-90`); this ADR's tier 2 generalizes
that existing, shipped fallback to `cmd_focus`/`backlog_focus` rather than
inventing a new one. The only change to `statusline.sh` itself is removing
its now-dead final fallback — the `active_epic` config read at
`statusline.sh:91-98` — since nothing will remain to write that key.

## Consequences

- **Focus ranking becomes correct per-session with zero new state.** No file
  to leak across sessions, nothing to poison, nothing to restore after a test
  run pollutes it.
- **`brana backlog set-active` disappears as a user-facing command.** Anyone
  relying on it to "pin" focus for a session must instead cut a branch under
  that epic (the existing, required first step of starting code work anyway)
  or pass `--epic` explicitly per invocation.
- **A session with no matching in-progress task gets no epic boost.**
  Accepted narrowing (see Decision) — freeform sessions with nothing started
  yet are the only path this meaningfully affects, and they're free to pass
  `--epic` explicitly.
- **`assert_active_epic_resolves()` is repurposed, not deleted** — same
  epic-node-or-flat-tag validation logic, now validating a task-derived slug
  instead of a config-sourced one. Its error string (`query.rs:122`, "check
  tasks-config.json's active_epic, or run `brana backlog set-active`") names
  both retired mechanisms and must be rewritten as part of this change, not
  left stale.
- **Six existing `active_epic`/`set-active` regression tests in
  `brana-cli/tests/cli_smoke.rs`** (lines ~291, 316, 335, 363, 391, 542, plus
  the fixture at ~276-288) assert behavior this ADR deletes. They are
  rewritten or removed as part of implementation, not left to fail
  (or worse, silently pass for the wrong reason — e.g. a removed `set-active`
  subcommand still makes `set_active_hard_stop_when_no_project_root_determinable`
  "pass," but via a generic clap parse error instead of the intended
  application-level one).
- **`system/skills/backlog/SKILL.md`** has two separate `active_epic`
  references — the CLI/MCP command table (row removal is the obvious part)
  and a prose paragraph at line ~65 describing the project-local resolution
  model. Both need updating; ADR-066's own lineage already saw this exact
  pattern once (table fixed, adjacent prose left stale) — not repeating it
  here is the whole point of naming it.
- **This ADR supersedes ADR-066's active_epic-specific provisions.**
  ADR-066's `active_initiative` provisions are untouched — this task's user
  verdict and evidence are scoped to `active_epic`/focus only; `active_initiative`
  is a separate value with no reported same-directory-multi-session complaint,
  and folding it in here would be solving a problem nobody has raised (see
  Non-Actions).
- **Deploy/migration:** existing project-local `tasks-config.json` files with
  a leftover `active_epic` key need no active migration — it simply stops
  being read. A cleanup pass removing the stale key from tracked config
  templates is cosmetic, not correctness-required, and can ride with the
  implementation commit rather than needing its own task.

## Non-Actions

- Does **not** touch `active_initiative` — same file, same shared-state shape,
  but no evidence (incident, user complaint, or pattern) that it suffers the
  same same-directory-concurrent-session problem `active_epic` does. Extending
  this design to `active_initiative` is a separate, symmetric follow-up if and
  when the same complaint surfaces for it — not folded in here per
  no-patches-root-cause (closing a demonstrated problem class, not a
  hypothetical adjacent one).
- Does **not** revisit ADR-065's epic-as-hierarchy-top schema — orthogonal;
  this ADR is about *where focus resolution reads its epic from*, not how
  epics are represented in the task tree.
- Does **not** attempt a 3rd, same-checkout-same-branch disambiguation tier by
  any other mechanism (PID, process-tree walk, a new purpose-built session
  registry) — considered during SPECIFY and explicitly rejected: the user
  confirmed dropping tier 3 rather than building new state to recover it (see
  feature spec's Assumptions). A future task may reopen this if a concrete
  need for same-branch multi-session disambiguation emerges beyond today's
  `--epic`-flag escape hatch.
- Does **not** change how `themes.rs::load_theme_name()` or `gh-sync.sh`
  resolve `theme`/`github_sync` — both correctly non-project-scoped,
  unaffected by this change (carried over from ADR-066's own Non-Actions).
