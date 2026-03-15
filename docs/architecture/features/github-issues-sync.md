# Feature: GitHub Issues Sync

**Date:** 2026-03-10
**Status:** shipped
**Task:** t-160

## Problem

tasks.json is a rich task system (23 fields, DAG dependencies, build_step tracking) but it's invisible outside Claude Code sessions. GitHub Issues and Projects provide external visibility, context persistence across sessions (comments), PR auto-linking, and portfolio-level browser views. Currently `github_issue` exists in the schema but is never populated automatically.

## Decision Record (frozen 2026-03-10, updated 2026-03-11)

> Frozen section updated post-ship to reflect what actually landed.

**Context:** Solo developer with 5+ client projects, 350+ tasks, rich task schema that GitHub Issues can't fully represent. PostToolUse hooks have known reliability issues (CC bug #24529) but work from `~/.claude/settings.json` via bootstrap.sh. GitHub CLI (`gh`) supports full CRUD for Issues and Projects v2.

**Decision:** Pragmatic hybrid sync — tasks.json owns state, GitHub provides visibility and context. Sync fires via PostToolUse hook on tasks.json edits (not skill-embedded). Projects v2 is configured per-repo. A Python helper (`task-sync.py`) handles all GitHub API calls.

**Consequences:**
- tasks.json remains single source of truth for state (status, priority, strategy, build_step, blocked_by)
- GitHub Issues mirror task lifecycle for visibility and PR linking
- Stream-based filtering: only `roadmap`, `tech-debt`, `bugs` sync to GitHub — `experiments`, `research`, `docs` stay local
- Labels represent stream + tags (prefixed: `stream:`, `tag:`) — phases/milestones get `enhancement` label
- Projects v2 configured per-repo — Kanban/table views with Status, Priority, Effort fields
- Bulk sync created issues for completed tasks (with closed status) — no retroactive exclusion
- v1 shipped cross-repo sync for all 4 clients via `~/.claude/task-sync-config.json`

## Constraints

- No webhooks, no polling daemon — CLI-only trigger surface
- PostToolUse hooks work from `~/.claude/settings.json` (bootstrap.sh), not from plugin hooks.json (CC bug #24529)
- GitHub API: 5000 req/hr. Bulk sync of 200 tasks ≈ 400-600 calls (well within)
- Must not block task operations on GitHub failures — hook runs in background (`nohup &`)
- Must not create duplicate issues on re-sync (dedup via task-issue-map.json)

## Scope (v1) — what shipped

### Shipped
- PostToolUse hook (`system/hooks/task-sync.sh` + `task-sync.py`) fires on any Write/Edit to `*/.claude/tasks.json`
- Incremental sync: detects new tasks and changed tasks (via hash of status|priority|effort|subject)
- Cross-repo sync for all 4 clients via global `~/.claude/task-sync-config.json`
- Stream-based filtering: only `roadmap`, `tech-debt`, `bugs` stream tasks sync
- Label mapping: `stream:{stream}`, `tag:{tag}` — phases/milestones get `enhancement`
- Projects v2: add items to board, sync Status + Priority + Effort fields
- Issue body includes full metadata (type, stream, status, priority, effort, strategy, branch, parent refs, blocked_by refs, context, notes)
- Parent/blocked_by cross-references rendered as `#issue_number` links
- Completed/cancelled tasks auto-closed with appropriate reason
- State files: `.claude/task-issue-map.json` (task→issue mapping), `.claude/task-sync-hashes.json` (change detection)
- Hook runs in background (`nohup &`) — never blocks the session
- 42 unit tests (`tests/hooks/test_task_sync.py`)

### Shipped in v2 (t-475, 2026-03-15)
- `brana backlog sync [--dry-run] [--force] [--parallel N]` — bulk CLI command, parallel via `std::thread::scope` + `gh api` subprocesses
- Zero new Cargo deps, binary stays 1.3MB
- Dedup via GitHub Search API before creation (replaces local map for bulk sync)
- Per-task write-back to tasks.json (Ctrl+C safe)
- Idempotent close (checks state before patching)
- Rate limit retry (sleeps 5s on 429/secondary rate)

### Designed but not shipped (from original spec)
- `system/scripts/gh-sync.sh` helper script — replaced by `task-sync.py` (incremental) and `sync.rs` (bulk)
- Per-project `.claude/tasks-config.json` — replaced by global `~/.claude/task-sync-config.json`
- One-shot context pull (issue comments → task context at pick time) — not implemented
- Label drift detection and prune-labels command — not implemented

### Out of scope (v1)
- Continuous bidirectional sync (no webhooks)
- GitHub Issue → tasks.json creation (GitHub-first workflow)
- Milestone objects in GitHub (use labels instead)

## Research

### GitHub CLI capabilities (confirmed 2026-03-10)
- Issues: full CRUD via `gh issue create/edit/close/list`
- Projects v2: full CLI — `gh project field-list`, `item-add`, `item-edit`
- Projects v2 gotcha: field updates need opaque node IDs (3 calls per field, batchable via GraphQL)
- `--project` flag on `gh issue create` needs `project` OAuth scope
- JSON output: `--json` flag on all list/view commands

### Current state
- 3 existing manual issues (#2, #7, #15) — not linked to tasks
- 12 tasks with `github_issue` values (ph-001 through t-007, issues #3-#14)
- 3 GitHub Projects exist (#7, #8, #9) — #8 "Brana System" is the natural target
- 352 total tasks; ~160 non-completed

### Challenger findings (2026-03-10)
- "All tasks" creates noise → mitigated by stream-based filtering (only roadmap/tech-debt/bugs sync)
- Comment backflow has no trigger → not shipped (one-shot pull designed but not implemented)
- Projects v2 API complexity → mitigated by Python helper with field caching
- Sync logic bloats SKILL.md → resolved: hook-based, no skill changes needed
- Cross-repo is underspecified → shipped in v1 via PostToolUse hook + global config

## Design

### Config schema (as shipped)

Lives in `~/.claude/task-sync-config.json` (global, not per-project). The hook reads this to determine which projects to sync and where.

```json
// ~/.claude/task-sync-config.json
{
  "owner": "martineserios",
  "keep_streams": ["roadmap", "tech-debt", "bugs"],
  "projects": {
    "thebrana": {"repo": "martineserios/thebrana", "project_number": 8},
    "proyecto_anita": {"repo": "martineserios/proyecto-anita", "project_number": 10},
    "somos_mirada": {"repo": "martineserios/somos_mirada", "project_number": 11},
    "nexeye_eyedetect": {"repo": "martineserios/nexeye_eyedetect", "project_number": 12}
  }
}
```

Project slug is auto-detected from the tasks.json file path: `dirname(dirname(file_path))` gives the project dir, `basename` gives the slug.

**Note:** The original spec proposed per-project `.claude/tasks-config.json` with theme config merged in. The shipped version separates concerns: theme config stays in tasks-config.json, sync config lives in its own global file.

### Sync trigger (as shipped)

The PostToolUse hook fires on every Write/Edit to `*/.claude/tasks.json`:

1. `task-sync.sh` (bash gate) filters for Write/Edit to `.claude/tasks.json` files only
2. Detects project slug from file path
3. Checks if project is in `~/.claude/task-sync-config.json`
4. Launches `task-sync.py` in background via `nohup &`

`task-sync.py` handles all sync logic:
- Loads tasks, filters by `keep_streams`
- Compares against `task-issue-map.json` (new tasks) and `task-sync-hashes.json` (changed tasks)
- Creates new issues: `gh issue create` with labels, add to project, set fields
- Updates changed issues: edit title/body/labels, close/reopen based on status, update project fields
- Saves updated map and hashes after each operation
- 0.5s delay between API calls for rate limiting

### Sync operations

| Trigger | GitHub action |
|---------|--------------|
| New task in qualifying stream | `gh issue create` + labels + project item-add + set fields |
| Task status/priority/effort/subject changed | `gh issue edit` title + body + labels, close/reopen, update project fields |
| Task completed | `gh issue close --reason completed` + project Status → Done |
| Task cancelled | `gh issue close --reason not_planned` |
| Task reopened (pending/in_progress) | `gh issue reopen` |

### Original spec (not shipped)

The original spec designed a `system/scripts/gh-sync.sh` bash helper with subcommands (create, close, update, pull-context, sync-all, project-setup, prune-labels) and skill-embedded sync calls. This was replaced by the simpler hook-based approach. The helper script was never created.

### Label mapping (as shipped)

```
stream:roadmap, stream:bugs, stream:tech-debt    (color: c5def5 blue)
tag:{name}  (all tags, prefixed)                  (color: e4e669 yellow)
enhancement  (added for phase/milestone types)
```

Labels auto-created via `gh label create --force` on each sync. No `priority:` or `status:` labels — these are tracked via Projects v2 fields.

### Issue body template (as shipped)

```markdown
{description}

## Metadata
- **Task ID:** `{id}`
- **Type:** {type}
- **Stream:** {stream}
- **Status:** {status}
- **Priority:** {priority}        (if set)
- **Effort:** {effort}            (if set)
- **Strategy:** {strategy}        (if set)
- **Branch:** `{branch}`          (if set)
- **Parent:** #{parent_issue}     (if parent in task-issue-map)
- **Blocked by:** #{issue}, ...   (cross-referenced from map)

## Context                         (if context field non-null)
{context}

## Notes                           (if notes field non-null)
{notes}
```

### Not shipped from original spec

- **One-shot context pull** (issue comments → task context at pick time) — designed but not implemented
- **`/brana:backlog sync` bulk command** — replaced by automatic hook-based incremental sync
- **Backlog skill integration** — the hook fires independently; no skill changes were needed

## File changes (as shipped)

| File | Change |
|------|--------|
| `system/hooks/task-sync.sh` | **New** — PostToolUse gate script (bash, 61 LOC) |
| `system/hooks/task-sync.py` | **New** — sync logic (Python, 355 LOC) |
| `~/.claude/task-sync-config.json` | **New** — global config (owner, projects, keep_streams) |
| `.claude/task-issue-map.json` | **Generated** — task ID → issue number mapping (per-project) |
| `.claude/task-sync-hashes.json` | **Generated** — task field hashes for change detection (per-project) |
| `tests/hooks/test_task_sync.py` | **New** — 42 pytest tests |

### Added in v2 (t-475)
| File | Change |
|------|--------|
| `system/cli/rust/src/sync.rs` | **New** — parallel bulk sync (Rust, ~550 LOC) |
| `system/cli/rust/src/cli.rs` | **Edit** — added `BacklogCmd::Sync` variant (+14 LOC) |

### Planned but not created
| File | Original plan | Why not |
|------|--------------|---------|
| `docs/guide/workflows/github-sync.md` | User guide | Not yet written |
| `docs/reference/configuration.md` update | Config resolution change | Config approach changed |

## Challenger findings

### Round 1 (design decisions)
- "All tasks" noise → accepted risk, mitigated by labels + forward-only sync. User values full visibility.
- Comment backflow trigger gap → resolved: one-shot pull at pick time only.
- Projects v2 complexity → resolved: optional per-repo, cached field IDs.
- SKILL.md bloat → resolved: helper script extraction.
- Cross-repo → deferred to v2 (separate task).
- Existing issue migration → handled by `sync --dry-run` audit before first sync.
- PM design doc inversion (doc 19 envisioned GitHub-first) → acknowledged. tasks.json has outgrown Issues as a data model. This is intentional.

### Round 2 (spec review) — all fixed
- Config location contradiction → **fixed**: `.claude/tasks-config.json` only (per-project), not tasks.json root.
- `<task-json>` parameter undefined → **fixed**: script takes task ID + tasks.json path, extracts via jq.
- No drift detection mechanism → **fixed**: `sync-all` compares current task fields against live GitHub labels.
- Exit 0 masks failures → **fixed**: distinct exit codes (0=success, 1=API error, 2=auth, 3=args).
- `status:` labels duplicate Projects v2 Status → **fixed**: skip `status:` labels when Projects v2 is enabled.
- Comment pull loses structure → **fixed**: structured format with author/date, 5-comment cap, 2000 char max.
- No `repo` field for cross-repo v2 → **fixed**: `repo: null` in config, auto-detected from git remote.
- Tag label sprawl → **fixed**: tags prefixed with `tag:`, plus `prune-labels` subcommand.
- Missing file changes → **fixed**: added tasks-config.json and user guide.

### Round 3 (final gate) — all fixed
- Config: global vs per-project contradiction → **fixed**: per-project `.claude/tasks-config.json` with global fallback. Breaking change for theme resolution documented.
- Build SKILL.md CLOSE has no sync point → **fixed**: added to file changes table. Sync goes after step 5 (update task), before step 6 (merge).
- stdout contract underspecified → **fixed**: create prints only issue number; two-step Bash-then-Edit pattern documented.
- Race condition (concurrent sessions) → **fixed**: create dedup via `gh issue list --search` before creation.
- Deleted issues unhandled → **fixed**: 404 clears `github_issue`, next sync re-creates.
- Context field append-only growth → **fixed**: replace (not append) existing `## GitHub Comments` section.
- Phases/milestones scope unclear → all task types get issues. Phases close when auto-rollup marks them completed.
- Existing 12 issues migration → validation step only (issues already exist). `sync --dry-run` verifies links.
