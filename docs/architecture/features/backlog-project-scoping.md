# Feature: Per-Project Backlog Scoping + Cross-Project Task Creation

**Date:** 2026-06-20
**Status:** specifying
**Task:** t-2155

## Problem

`tasks-config.json` (which stores `active_epic`, `active_initiative`, `theme`, `github_sync`) is
hardcoded to `~/.claude/tasks-config.json` — a global singleton shared across ALL projects.

- `tasks_config_path()` in `brana-cli/src/commands/backlog.rs:416` hardcodes `$HOME/.claude/tasks-config.json`
- `backlog_focus.rs:34` in brana-mcp does the same
- `themes.rs:132` does the same

When you set `active_epic: "harness"` in thebrana and then open a client session, `brana backlog
focus` shows thebrana-epic-filtered tasks. When `/brana:close` runs in the client and calls
`brana backlog focus`, it surfaces thebrana tasks. The `brana backlog set-active` command overwrites
the global config, clobbering the other project's setting.

`tasks.json` (task data) is correctly scoped per git root via `find_tasks_file()`. Only
`tasks-config.json` (config/preferences) is broken.

## Decision Record (frozen 2026-06-20)

> Do not modify after acceptance.

**Context:** Single global `tasks-config.json` was built for a single-project workflow. As the
portfolio grew, active-epic bleeding became a real UX problem. Cross-project task creation was
never designed for (default is always current project).

**Decision:**
1. **Per-project config resolution** — `find_tasks_config()` mirrors `find_tasks_file()` *exactly*:
   git common-dir root first (shared across worktrees of the same repo — config is per-repo, not
   per-worktree), then git toplevel, then `CLAUDE_PROJECT_DIR`/CWD fallback for non-git projects,
   then `~/.claude/tasks-config.json` as the final global fallback.
2. **Local-wins-wholesale + project-scoped keys never inherit** — if a project-local
   `.claude/tasks-config.json` exists, it is authoritative; the global file is NOT merged in
   (avoids the "can't clear a local key" trap, challenger M-1). When **no** local file exists:
   *inheritable* keys (`theme`, `github_sync`) fall back to global, but **project-scoped** keys
   (`active_epic`, `active_initiative`) resolve to **None** — they never inherit from global.
   Rationale (multi-client analysis): an epic belongs to exactly one project, so a global
   `active_epic` is almost always wrong in a different project. This is the direct fix for the
   reproduced bug (`brana backlog focus` in client `batrade` showed `active:
   identity-commerce-rebuild`, a thebrana epic) — and it fixes *every* client at once, with no
   opt-in. On first write in a project, the new local file is **seeded from global's inheritable
   keys only** (NOT active_epic), then the change is applied.
3. **Cross-project create via `project` param** — `brana backlog add --project <slug>` (CLI) and the
   MCP `backlog_add` tool's optional `project` field both resolve to a different project's tasks.json
   via `tasks-portfolio.json`. Explicit param required — default always stays current project.

**Consequences:**
- Each project can set its own `active_epic` without clobbering others
- First write of `set-active` in a project creates `.claude/tasks-config.json` there (seeded from
  global) — git-tracked per project (or gitignored, project owner decides)
- Global `~/.claude/tasks-config.json` becomes a fallback/default template
- Cross-project task creation requires knowing the portfolio slug — a minor friction that prevents
  accidental writes
- **Known limitation (challenger C-2):** the MCP server resolves project via its process CWD, fixed
  at CC-session launch. Per-project config works within a session (= one project) but switching
  projects mid-session without CC relaunching the MCP server would resolve to the launch-time
  project. This is the *same* assumption `find_tasks_file()` already makes for task data — not a new
  regression. Verified: 7 live `brana-mcp` processes, one per terminal/session, each with its own
  CWD → multi-session multi-project isolation holds. Out of scope to fix here.
- **Cross-project write race (multi-session):** `tasks.json` writes are atomic (`write_atomic`:
  temp + rename) so no corruption, but atomicity does not prevent lost updates — two processes that
  both read → both compute next id → both write will have the second clobber the first. This race
  *already exists* for two sessions on the same repo (e.g. worktrees); `--project` widens the blast
  radius so a client session can race a thebrana session. Mitigation: ID allocation reads fresh
  inside the add call (small window). Frequency is low × low. Documented, not locked in v1 (the
  project intentionally avoids flock — see field-note on flock removal).

## Worktree behavior (verified 2026-06-20)

`find_tasks_config()` reuses `find_tasks_file()`'s `git --git-common-dir` resolution. Verified
empirically:

| Context | `git-common-dir` returns | Resolves config to |
|---------|--------------------------|--------------------|
| Main checkout | `.git` (relative) → `.parent()` = `""` → CWD-relative | `{repo-root}/.claude/tasks-config.json` (CWD is repo root) |
| Worktree | `/abs/path/to/mainrepo/.git` (absolute) → `.parent()` | `{main-repo-root}/.claude/tasks-config.json` |

**Consequence — config is per-repo, shared across all worktrees** (identical to how `tasks.json`
already behaves). One repo → one backlog → one config file, living only at the main checkout's
`.claude/`. Worktrees never get their own copy; they read/write the main checkout's file by absolute
path. Because the file is gitignored, it is always "live" — never tied to whatever commit a worktree
has checked out.

**Tension — `active_epic` is shared across worktrees of one repo.** If you run `set-active harness`
in worktree A and `set-active backlog-git-alignment` in worktree B (both thebrana worktrees), the
second clobbers the first — they write the same shared file. This is consistent with tasks.json
being shared, but defeats per-worktree epic focus *if set via the persistent pointer*.

**Mitigation (already exists):** `brana backlog focus --epic <slug>` overrides the active epic
per-invocation without touching the shared pointer (verified: flag present in `focus --help`). A
worktree on the harness branch runs `focus --epic harness` for per-worktree focus while the shared
`active_epic` stays untouched. Note: session-state is *already* correctly per-worktree (epic derived
from branch via `unit_scoped_state_path`/`epic_scoped_state_path`) — only the focus pointer is
repo-global, and `--epic` covers that gap. No code change needed for worktrees in v1.

## Config tracking decision (multi-machine analysis)

Project-local `.claude/tasks-config.json` is **gitignored**. It is dominated by personal, volatile,
per-machine working state (`active_epic`, `theme`). Tracking it would cause cross-machine clobber
(machine A on epic X, machine B on epic Y) and a merge conflict on nearly every pull. thebrana's
`.gitignore` adds the entry; client repos inherit the convention when first created. (Shareable
repo config like `github_sync.repo` is rare and can be reintroduced as a tracked concern later if
needed — out of scope for v1.)

## Constraints

- Backward compatible: projects without a local `tasks-config.json` silently fall back to global
- No task data migration — tasks.json files are unaffected
- The `--project` flag for cross-project add must resolve strictly from `tasks-portfolio.json`
  (prevents arbitrary path injection)
- `brana backlog set-active` must write project-local, not global

## Scope (v1)

1. `find_tasks_config()` — new function in `brana-core/src/util.rs` mirroring `find_tasks_file()`:
   checks `{CLAUDE_PROJECT_DIR}/.claude/tasks-config.json`, then git common root, then git toplevel,
   then `~/.claude/tasks-config.json`
2. `load_tasks_config()` / `save_tasks_config()` / `tasks_config_path()` in
   `brana-cli/src/commands/backlog.rs` — use `find_tasks_config()`
3. `backlog_focus.rs` in brana-mcp — use `brana_core::util::find_tasks_config()`
4. `themes.rs` — use `find_tasks_config()`
5. `brana backlog add --project <slug>` — resolve target tasks.json from portfolio, write there

**Out of scope (v1):** theme-per-project UI, `github_sync` per-project (config merges handle it),
migrating existing global config (fallback is enough).

## Research

- `find_tasks_file()` in `brana-core/src/util.rs:13-20` is the reference implementation for
  per-project resolution. Uses `CLAUDE_PROJECT_DIR` → git common root → git toplevel → CWD.
- `tasks_config_path()` in `brana-cli/src/commands/backlog.rs:416-419` is the global singleton
  to replace.
- `backlog_focus.rs:34` in brana-mcp duplicates the hardcoded path — needs the same fix.
- `tasks-portfolio.json` at `~/.claude/tasks-portfolio.json` has a `clients[].projects[].slug`
  and `clients[].projects[].path` structure — this is the resolution table for `--project`.
- Each client dir is a separate git repo (batrade, bemol, crea, etc.) — git-root scoping works.
- Non-git client dirs (mandawa, nexeye_eyedetect, proyecto-anita, sunflower) fall back to
  `CLAUDE_PROJECT_DIR` / CWD — same fallback used by `find_tasks_file()`, so consistent.

## Assumptions

- A project that has never set `active_epic` locally will get the global value (desired: YES, this
  is the backward-compat fallback).
- `save_tasks_config()` writes project-local, never global — old global config remains untouched
  as fallback. (needs confirmation: OK?)
- `--project` slug lookup is case-sensitive (portfolio slugs are lowercase kebab).

## Behavior

**`brana backlog focus` in client A:**
- Before: reads `~/.claude/tasks-config.json` → sees thebrana's `active_epic` → shows thebrana tasks
- After: reads `{client_A_git_root}/.claude/tasks-config.json` → finds no `active_epic` → falls
  back to global → BUT global active_epic was last set per-project, not overwritten → clean

**`brana backlog set-active harness` in thebrana:**
- Before: overwrites `~/.claude/tasks-config.json` → affects all projects
- After: writes to `{thebrana_git_root}/.claude/tasks-config.json` → isolated

**`brana backlog add --project batrade --subject "..."` from thebrana:**
- Resolves batrade → `~/.claude/tasks-portfolio.json` → path → `.claude/tasks.json` → writes there
- Without `--project`: writes to current project's tasks.json (unchanged)

**`brana backlog add --project unknown`:**
- Error: "project 'unknown' not found in tasks-portfolio.json"

## Edge Cases

- Non-git directory: CWD fallback applies (same as `find_tasks_file()`). Looks for
  `.claude/tasks-config.json` in CWD if `.claude/` exists, else global.
- Project local config has partial keys: merge with global (local wins per-key)
- `--project` in `backlog add` + `--file` flag conflict: error, require one or the other
- Portfolio slug collision (two entries same slug): use first match; log a warning

## Design

### New function `find_tasks_config()` in `brana-core/src/util.rs`

```rust
/// Find tasks-config.json using the same layering as find_tasks_file().
/// Returns (path, is_project_local) where is_project_local=true if found in git root.
pub fn find_tasks_config() -> (PathBuf, bool) {
    // 1. CLAUDE_PROJECT_DIR
    // 2. git common root
    // 3. git toplevel
    // 4. CWD (if .claude/ exists there)
    // 5. Fallback: ~/.claude/tasks-config.json (always exists as default)
    // Returns project-local path if any .claude/ dir was found, else global path
}
```

### Read semantics (local-wins + project-scoped keys never inherit)

```rust
const PROJECT_SCOPED_KEYS: &[&str] = &["active_epic", "active_initiative"];

fn load_tasks_config() -> serde_json::Value {
    let (local_path, has_local) = find_tasks_config();
    if has_local && local_path.exists() {
        // Local file is authoritative — no merge with global.
        return read_json(&local_path);
    }
    // No local file: inherit ONLY non-project-scoped keys from global.
    let mut global = read_json(&global_path());
    if let Some(obj) = global.as_object_mut() {
        for k in PROJECT_SCOPED_KEYS { obj.remove(*k); }   // never inherit active_epic
    }
    global
}
```

`load_theme_name()` in themes.rs reads `theme` from this resolved config (inheritable), defaulting
to `"classic"` on absence — no error propagation needed (challenger m-1).

`load_theme_name()` in themes.rs reads the same resolved config, defaulting to `"classic"` on
absence (no error propagation needed — challenger m-1).

### Write semantics (seed-from-global on first write)

`save_tasks_config()` writes to the project-local path. If the local file does not yet exist, it is
**seeded from the global config** first (so theme/github_sync defaults carry over), then the change
is applied. The global file is never written by normal operations.

```rust
fn save_tasks_config(cfg: &Value) -> Result<()> {
    let (path, _) = find_tasks_config();
    // cfg already reflects seed-on-create at the call site:
    //   let mut cfg = load_or_seed();  // local if exists; else global MINUS project-scoped keys
    //   cfg["active_epic"] = ...;       // the value being set this call
    write_atomic(&path, cfg)
}
```

### `--project` flag on `brana backlog add`

```rust
// In AddArgs struct:
/// Write task to a different project (slug from tasks-portfolio.json)
#[arg(long)]
project: Option<String>,

// In handler:
let tasks_file = if let Some(slug) = &args.project {
    resolve_project_tasks_file(slug)?  // reads tasks-portfolio.json
} else {
    find_tasks_file().ok_or_else(|| ...)?
};
```

### Files to change

| File | Change |
|------|--------|
| `brana-core/src/util.rs` | Add `find_tasks_config() -> (PathBuf, bool)` + `resolve_project_tasks_file(slug)` |
| `brana-cli/src/commands/backlog.rs` | Rewrite `load_tasks_config`/`save_tasks_config` (local-wins + seed); add `--project` to `add` (mutually exclusive with `--file`) |
| `brana-mcp/src/tools/backlog_focus.rs` | Use `brana_core::util::find_tasks_config()` |
| `brana-mcp/src/tools/backlog_add.rs` | Add optional `project` input field → `resolve_project_tasks_file()` (challenger M-2) |
| `brana-cli/src/themes.rs` | Use `find_tasks_config()` |
| `brana-cli/tests/cli_smoke.rs` | Update `backlog_set_active_updates_config` to set CWD to tmp + assert project-local path (challenger M-3); add test: no-local-config → `active_epic` resolves None but `theme` inherits global |
| `.gitignore` (thebrana) | Add `.claude/tasks-config.json` (per multi-machine analysis) |

## Boundaries

| Always | Ask First | Never |
|--------|-----------|-------|
| Find project-local config first | Global fallback merge strategy | Write to global `~/.claude/tasks-config.json` during normal ops |
| Write `set-active` to project-local | Whether to gitignore `.claude/tasks-config.json` in clients | Let `--project` bypass portfolio validation |
| Resolve `--project` via portfolio only | | Touch tasks.json (task data) — only config changes |

## Testing Strategy

- **Unit:** `find_tasks_config()` with temp dirs — git root present/absent, local config present/absent, `CLAUDE_PROJECT_DIR` set/unset. Merge semantics (local key overrides global, missing local key uses global).
- **Integration:** `brana backlog focus` in a temp dir with its own `.claude/tasks-config.json` — verify it uses local epic. `brana backlog set-active` writes to project-local.
- **E2E:** `brana backlog add --project <slug>` resolves to correct tasks.json and writes there.
- **Mock policy:** Real filesystem (temp dirs). No network. No mocks needed.

## Documentation Plan

- [ ] **User guide** — `docs/guide/features/backlog-project-scoping.md`: per-project config,
  `set-active` scope, `--project` flag usage, portfolio setup
- [ ] **Tech doc** — update this file to `decomposing` status after spec approved
- [ ] **Existing docs to update** — backlog skill SKILL.md (mention per-project config),
  tasks-convention.md rule

## Challenger findings (2026-06-20)

| # | Severity | Finding | Resolution |
|---|----------|---------|------------|
| C-1 | CRITICAL→MINOR | Pseudocode listed CLAUDE_PROJECT_DIR first; doesn't match `find_tasks_file()` (common-dir first) | Spec corrected to mirror `find_tasks_file()` exactly. Per-repo (common-dir) scope is *correct* for config — worktrees share. |
| C-2 | CRITICAL→KNOWN-LIMIT | MCP server CWD fixed at launch; per-call project resolution not designed | Verified: within one CC session (= one project) resolution is correct, same assumption as existing `find_tasks_file()`. Documented as limitation; out of scope. |
| M-1 | MAJOR | Merge-on-read can't clear a local key (global bleeds back) | Changed design: local file authoritative wholesale; global only when no local file. First write seeds from global. |
| M-2 | MAJOR | `brana-mcp/.../backlog_add.rs` omitted; cross-project add would be CLI-only | Added to files-to-change + scope: MCP `backlog_add` gets optional `project` field. |
| M-3 | MAJOR | Existing smoke test `backlog_set_active_updates_config` asserts global path | Added test update to scope (set CWD to tmp, assert project-local). |
| m-1 | MINOR | `themes.rs::load_theme_name` returns String, no error path | Read resolved config, default `"classic"` on absence. No merge impedance. |
| m-2 | MINOR | `--file` vs `--project` conflict; is `--file` user-facing? | Make `--project`/`--file` mutually exclusive via clap. `--file` stays as the internal/explicit override. |
