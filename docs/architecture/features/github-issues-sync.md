# Feature: GitHub Issues Sync

**Date:** 2026-03-10
**Status:** specifying
**Task:** t-160

## Problem

tasks.json is a rich task system (23 fields, DAG dependencies, build_step tracking) but it's invisible outside Claude Code sessions. GitHub Issues and Projects provide external visibility, context persistence across sessions (comments), PR auto-linking, and portfolio-level browser views. Currently `github_issue` exists in the schema but is never populated automatically.

## Decision Record (frozen 2026-03-10)

> Do not modify after acceptance.

**Context:** Solo developer with 5+ client projects, 350+ tasks, rich task schema that GitHub Issues can't fully represent. PostToolUse hooks have known reliability issues (CC bug #24529). GitHub CLI (`gh`) supports full CRUD for Issues and Projects v2.

**Decision:** Pragmatic hybrid sync — tasks.json owns state, GitHub provides visibility and context. Sync is skill-embedded (fires during pick/done/add) with a bulk sync command for catch-up. Projects v2 is optional per-repo via config. Helper script keeps sync logic out of the SKILL.md.

**Consequences:**
- tasks.json remains single source of truth for state (status, priority, strategy, build_step, blocked_by)
- GitHub Issues mirror task lifecycle for visibility and PR linking
- Issue comments pulled once at `pick` time for context enrichment — no continuous backflow
- Labels represent stream + priority (max 3 dimensions) — not all 7 task fields
- Projects v2 opt-in per repo — Kanban/table views available but not required
- No retroactive issue creation for completed tasks
- v1 scoped to thebrana; other repos opt in via config

## Constraints

- No webhooks, no polling daemon — CLI-only trigger surface
- PostToolUse hooks unreliable — sync must NOT depend on hooks
- GitHub API: 5000 req/hr. Bulk sync of 200 tasks ≈ 400-600 calls (well within)
- Must not block task operations on GitHub failures — warn and continue
- Must not create duplicate issues on re-sync

## Scope (v1)

### In scope
- GitHub Issue create/close synced to task lifecycle (pick, done, add, close)
- Label mapping: `stream:{stream}`, `priority:{P0-P3}`, task tags (first 2)
- Config-driven opt-in: `github_sync` in `.claude/tasks-config.json` (per-project)
- Optional Projects v2: add items to board, sync Status + Priority fields
- `/brana:backlog sync` command for bulk operations, dry-run auditing, recovery
- One-shot context pull: issue comments → task `context` field at `pick` time
- Helper script: `system/scripts/gh-sync.sh`
- Idempotent: re-running sync on already-synced tasks is safe (checks `github_issue` field)
- Migration path for existing 12 tasks with `github_issue` values

### Out of scope (v1)
- Continuous bidirectional sync (no webhooks)
- Cross-repo portfolio sync (thebrana only in v1)
- Retroactive issue creation for completed tasks
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
- "All tasks" creates noise → mitigated by labels and forward-only sync
- Comment backflow has no trigger → mitigated by one-shot pull at pick time
- Projects v2 API complexity → mitigated by making it optional
- Sync logic bloats SKILL.md → mitigated by helper script extraction
- Cross-repo is underspecified → deferred to v2

## Design

### Config schema

Lives in per-project `.claude/tasks-config.json`. **Breaking change:** tasks-config.json resolution moves from global-only (`~/.claude/tasks-config.json`) to per-project first, global fallback. Theme config continues to work from either location.

Resolution order: `.claude/tasks-config.json` (project root) → `~/.claude/tasks-config.json` (global fallback). Per-project overrides global entirely (no merge).

```json
// {project}/.claude/tasks-config.json
{
  "theme": "classic",
  "github_sync": {
    "enabled": true,
    "repo": null,                // auto-detect from git remote; override for cross-repo v2
    "project": "Brana System",   // null = issues only
    "labels": {
      "stream": true,            // label: stream:roadmap
      "priority": true,          // label: priority:P1
      "tags": 2                  // sync first N tags as labels (prefixed: tag:{name})
    }
  }
}
```

`repo` defaults to `null` — auto-detected from `gh repo view --json nameWithOwner`. Explicit value enables cross-repo sync in v2.

**Note:** This changes the backlog skill's theme resolution from global-only to per-project-first. The backlog SKILL.md theme resolution section and `docs/reference/configuration.md` must be updated.

### Sync operations

| Task event | GitHub action |
|------------|--------------|
| `/brana:backlog add` | `gh issue create` with labels. Store issue # in `github_issue`. If project: add item + set fields. |
| `/brana:backlog pick` | If no issue: create one. Update labels to include `status:in-progress`. If project: set Status = "In Progress". Pull issue comments → task `context`. |
| `/brana:build` CLOSE | `gh issue close`. If project: set Status = "Done". |
| `/brana:backlog done` | Same as CLOSE. |
| `/brana:backlog sync` | Bulk: create missing issues, update stale labels, close completed, dry-run audit. |
| Task priority change | Update priority label. If project: update Priority field. |

### Helper script: `system/scripts/gh-sync.sh`

```bash
gh-sync.sh create <task-id> <tasks-json-path>   # create issue from task, print issue # to stdout
gh-sync.sh close <issue-number>                  # close issue
gh-sync.sh update <task-id> <tasks-json-path>    # update labels/state from current task fields
gh-sync.sh pull-context <issue-number>           # print last 5 comments (structured, max 2000 chars)
gh-sync.sh sync-all <tasks-json-path> [--dry-run]  # bulk sync with progress
gh-sync.sh project-setup <project-name>          # cache field IDs for Projects v2
gh-sync.sh prune-labels                          # remove orphaned sync labels
```

Script reads task data from tasks.json via `jq` using the task ID — no inline JSON passing.

**Exit codes:**
- `0` — success
- `1` — GitHub API error (issue not found, rate limit, network)
- `2` — auth failure (`gh auth status` failed)
- `3` — invalid arguments or missing tasks.json

Calling code uses exit codes to distinguish success/failure and provide appropriate user messages.

**Stdout contract:**
- `create` prints only the issue number (integer) to stdout. The skill reads this output and writes it to the task's `github_issue` field via a separate tasks.json edit. This is a two-step Bash-then-Edit pattern.
- `pull-context` prints formatted comments to stdout. Skill reads and appends to context field.

**Other contracts:**
- All operations are idempotent
- `create` dedup: before creating, search `gh issue list --search "Task: {id} in:title" --json number`. If found, return existing issue number instead of creating duplicate.
- Script checks `gh auth status` before any API call; if not authed, exits 2 with message
- If `gh` CLI not installed, exits 2 with "gh CLI required" message
- Caches project/field IDs in `.claude/github-sync-cache.json`
- Deleted issue handling: if `gh issue view` returns 404, clear `github_issue` from task and log warning. Next sync re-creates.
- Bulk operations (`sync-all`) use 100ms delay between API calls to stay well under rate limits. Show progress: "Syncing ~N tasks, estimated 30-60 seconds..."

### Label mapping

```
stream:roadmap, stream:bugs, stream:tech-debt, stream:research, stream:docs
priority:P0, priority:P1, priority:P2, priority:P3
tag:{name}  (first 2 tags from task, prefixed to distinguish from manual labels)
```

**Note:** `status:` labels are only used when Projects v2 is NOT enabled. When Projects v2 is active, Status is tracked via the Project field — no `status:` labels to avoid dual state.

Labels auto-created on first use. Colors: stream=blue, priority=red, tags=gray.

### Issue body template

```markdown
**Task:** {id} | **Stream:** {stream} | **Priority:** {priority} | **Effort:** {effort}
**Strategy:** {strategy} | **Execution:** {execution}

---

{description}

{context if non-null}

---
*Synced from tasks.json by brana*
```

### One-shot context pull (at pick time)

When `/brana:backlog pick` runs and the task has a `github_issue`:

1. Run `gh-sync.sh pull-context <issue-number>`
2. Script returns last 5 comments, formatted as:
   ```
   --- @username on 2026-03-10 ---
   Comment body here...

   --- @username on 2026-03-09 ---
   Earlier comment...
   ```
3. Truncate to 2000 chars max
4. **Replace** (not append) any existing `## GitHub Comments` section in the task's `context` field. Format: `\n\n## GitHub Comments (pulled {date})\n{comments}`
5. If no comments exist, skip silently

This is a one-shot pull, not continuous sync. Replace prevents context growth on re-picks.

### Backlog skill changes

Minimal — each command adds a sync call after writing tasks.json:

```
# After writing tasks.json in pick/done/add/close:
if github_sync_enabled (read .claude/tasks-config.json):
    exit_code = run gh-sync.sh {operation} {task-id} {tasks-json-path}
    if exit_code == 0: update github_issue field in tasks.json
    if exit_code == 1: warn "GitHub sync failed: {error}. Task updated locally."
    if exit_code == 2: warn "GitHub auth required. Run: gh auth login"
```

### `/brana:backlog sync` command

```
/brana:backlog sync [--dry-run] [--force]
```

Steps:
1. Read config — check `github_sync.enabled`
2. Read tasks.json — find tasks needing sync:
   - Non-completed tasks without `github_issue` → need creation
   - Completed tasks with `github_issue` + open issue → need closing
   - Tasks with label drift (compare current task fields against live GitHub labels via `gh issue view --json labels`)
3. If `--dry-run`: report plan and exit
4. Execute sync operations with progress output
5. If `--force`: re-sync all tasks regardless of current state
6. Report summary

## File changes

| File | Change |
|------|--------|
| `system/scripts/gh-sync.sh` | **New** — sync helper script |
| `system/skills/backlog/SKILL.md` | Add sync calls to pick/done/add commands + new sync subcommand + update theme resolution to per-project-first |
| `system/skills/build/SKILL.md` | Add sync call to CLOSE step (after step 5 "Update task", before step 6 "Merge") |
| `.claude/tasks-config.json` | Add `github_sync` config block (per-project) |
| `docs/reference/configuration.md` | Update tasks-config.json resolution from global-only to per-project-first |
| `docs/guide/workflows/github-sync.md` | **New** — user guide for setup and usage |

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
