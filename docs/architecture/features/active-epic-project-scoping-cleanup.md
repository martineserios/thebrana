# Feature: Active-Epic Project Scoping — Cleanup + Enforcement

**Date:** 2026-07-22
**Status:** building
**Task:** t-2281

## Problem

`active_epic`/`active_initiative` resolution is fixed at the Rust code level (t-2158, t-2155), but challenger review (2026-07-22) found the fix doesn't cover everything: two `/brana:backlog` skill procedures (`plan.md`, `done-and-add.md`) hardcode a raw read of the **global** `tasks-config.json` for epic auto-assignment, bypassing the scoped resolver entirely — a live, high-traffic bleed vector. `cmd_set_active` also silently falls back to writing the global file when no project root is determinable. Plus two smaller gaps: `sync-state.sh cmd_pull` has no contamination guard (unlike `cmd_push`, t-1883), and the global `tasks-config.json` carries an orphaned proyecto_anita epic value that predates the fix.

## Decision Record (frozen 2026-07-22)

See [ADR-066](../decisions/ADR-066-active-epic-project-scoped-only.md) — full context and decision live there, not duplicated here.

## Constraints

- Must not regress `cmd_push`'s existing t-1883 guard.
- Must not touch any project's already-correct project-local config (verified: proyecto_anita has its own, untouched).
- Migration script must be re-runnable (audit, not one-shot) since new orphans can appear until the pull-guard fully closes the write vector.

## Scope (v1)

- ADR-066 (done, see above)
- **Fix `plan.md` step 3a and `done-and-add.md` step 3a** to resolve `active_epic` via the scoped path (e.g. `brana backlog focus` output, which already calls `load_tasks_config()`) instead of a raw read of `~/.claude/tasks-config.json`. Highest priority — this is the one gap with a live blast radius today.
- **`cmd_set_active` hard-stop** when no project root is determinable, replacing the silent global-write fallback with an explicit error.
- `sync-state.sh cmd_pull` guard mirroring `cmd_push`'s t-1883 guard — same before/after single-repo diff algorithm as the existing push guard, not a portfolio-wide comparison (see Design below for why the broader version was rejected).
- `system/scripts/migrate/audit-orphaned-active-epic.py` — walks `tasks-portfolio.json`, flags/clears global `active_epic`/`active_initiative` values with no matching project-local source of truth
- Regression test extending `cli_smoke.rs:292` coverage (or new tests) covering: skill-procedure fix, `cmd_set_active` hard-stop, and the sync-state.sh guard

## Research

- `brana_core::util::load_tasks_config()` (t-2158) already strips `PROJECT_SCOPED_CONFIG_KEYS` on global fallback — confirmed via direct code read.
- `cmd_set_active` (t-2155, `backlog.rs:509`) writes only to the resolved project-local path.
- `sync-state.sh` `cmd_push` (lines 122-162) has the t-1883 guard; `cmd_pull` (lines 218-226) does not.
- Global `~/.claude/tasks-config.json` held `active_epic: "identity-commerce-rebuild"`; confirmed orphaned — proyecto_anita's actual project-local config (`~/enter_thebrana/ventures/proyecto_anita/.claude/tasks-config.json`) already holds a different, current value (`env-hardening`).

## Assumptions

- `tasks-portfolio.json` is the authoritative project list to audit against — needs confirmation it covers all active projects (some found during audit, e.g. `ventures/proyecto_anita-*` worktree copies, are NOT separately portfolio-registered; only the canonical project path per client/venture is). Audit script scopes to portfolio-registered paths only; worktree copies are out of scope. **Verified during t-2296** (not just assumed): `git_common_root()` resolves to the main checkout root shared across all its worktrees, confirmed by direct incident — a `set-active` boundary probe run from inside this task's own worktree wrote to the main repo's `.claude/tasks-config.json`, not the worktree's. Worktrees genuinely share one project-local config with their main checkout; skipping them in the audit is correct.

## Design

- **Skill procedure fix**: replace the literal `~/.claude/tasks-config.json` read in `plan.md`/`done-and-add.md` step 3a with `mcp__brana__backlog_focus(top: 0)`, reading its top-level `active_epic` field — that field is computed from `load_tasks_config()` and hoisted unconditionally (present even when `tasks: []`), unlike the CLI's `brana backlog focus --json`, whose array-shaped output only carries `active_epic` per scored task and loses the signal entirely when zero tasks match (confirmed via code read, `backlog.rs` `cmd_focus` vs `backlog_focus.rs` MCP tool — the two implementations diverge in output shape). No new Rust code needed. **CLI fallback** (when MCP is unavailable, per skill convention): still `brana backlog focus --json`, first element's `active_epic` field, accepting the documented zero-tasks edge case as a known, lower-severity gap — not fixed in this pass, since changing the CLI's output shape to match MCP would break `cli_smoke.rs`'s existing `backlog_focus_json_flag_outputs_json_array` assertion (a tested contract), for a fallback path that's secondary to the MCP-first design. (Considered and rejected: adding a brand-new dedicated getter subcommand — unnecessary once the already-shipped MCP tool was checked; per challenger review.)
- **`cmd_set_active` hard-stop**: when `crate::util::find_tasks_config()` returns `None`, return an error instead of falling through to `global_tasks_config_path()`. Message: "no project root found (not in a git repo, and no local .claude/ present) — cannot resolve a scoped config path for set-active."
- **`cmd_pull` guard — single-repo before/after diff, mirroring `cmd_push` exactly**: capture the global cache's `active_epic`/`active_initiative` before the pull; after pulling, compare thebrana's own repo value (just written into the cache) against what was there before. If a foreign (non-thebrana) value was present before the pull and thebrana's value would overwrite it, warn and skip those two keys — same shape as the existing `cmd_push` guard, just mirrored for the opposite direction. **Rejected alternative** (considered, then dropped per challenger review): comparing the post-pull global value against every registered project's local config. That design degrades to "never matches" once every project has its own local config (this ADR's own target end-state), permanently blocking legitimate first-run cache seeding instead of converging to a no-op — the single-repo diff avoids this because it only ever compares thebrana's own before/after state, never other projects'.
- **Audit script**: for each `path` in `tasks-portfolio.json`, read `{path}/.claude/tasks-config.json` if it exists (project-local source of truth). Compare its `active_epic`/`active_initiative` against the global file's. If the global value doesn't match ANY project's local value (and isn't itself null), it's orphaned → clear it from global, log what was removed. (This portfolio-wide scan is correct for the *audit* tool — it's a one-time/periodic check, not a per-pull gate, so the "never converges" problem above doesn't apply here.)

## Boundaries

| Always | Ask First | Never |
|--------|-----------|-------|
| Read-only audit by default (`--dry-run`) | Actually clearing the global key (confirm before running without `--dry-run`) | Touch a project's own project-local config |

## Testing Strategy

- **Unit:** audit script's "is this value orphaned" logic — pure function over parsed JSON, no I/O.
- **Integration:** sync-state.sh guard — bats/shell test simulating a diverged global cache before `cmd_pull`.
- **Mock policy:** real file fixtures (temp dirs), no network/API involved.

## Documentation Plan

- [ ] **Tech doc**: this file, plus ADR-066
- [ ] **Existing docs to update**: none — no user-facing behavior change (internal scoping enforcement)

## Challenger findings

**Verdict: RECONSIDER → addressed.** Two Critical findings, both verified directly:
1. `plan.md`/`done-and-add.md` step 3a hardcode a raw global-path read for `active_epic` auto-assignment, bypassing the scoped resolver — a live bleed vector on any project without local config. **Added to scope** (highest priority item).
2. `cmd_set_active` silently falls back to writing global when no project root is determinable. **Added to scope** (hard-stop instead).
3. ADR and spec originally specified two different `cmd_pull` guard algorithms (single-repo diff vs. portfolio-wide comparison) — the broader one would never converge to a no-op and would block legitimate first-run seeding. **Resolved**: both docs now specify the single-repo diff, matching `cmd_push`'s existing algorithm.

Warnings addressed: TDD ordering now explicit in Testing Strategy (tests block implementation, not the reverse — see task decomposition). Two Observations noted but not actioned: `themes.rs`/`gh-sync.sh` independently re-read `tasks-config.json` for non-scoped keys (correct, no change needed, documented in ADR Non-Actions); task effort backfilled to M below.

**Second pre-edit challenger pass (2026-07-22, on the skill-procedure fix specifically):** RECONSIDER — my first plan (add a new dedicated `get-active`-style CLI subcommand) was unnecessary. Direct code read confirmed the MCP `backlog_focus` tool already hoists `active_epic` to the top level unconditionally (`backlog_focus.rs:74-78`), solving the exact zero-task-array problem with zero new code — exactly matching this spec's own original "no new Rust code needed" line, which I'd abandoned without re-checking. Design section above corrected to use the MCP tool; no subcommand added. Existing `cli_smoke.rs` tests (`backlog_focus_json_flag_outputs_json_array`, `focus_does_not_inherit_global_active_epic`, `config_inherits_theme_but_not_active_epic_from_global`, `focus_local_config_without_active_epic_shows_no_foreign_epic`) already give strong CLI-level regression coverage for t-2158/t-2155 — confirmed no test yet covers `cmd_set_active`'s true no-project-root fallback case (t-2296's target).
