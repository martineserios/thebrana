<!-- backlog phase: /brana:backlog triage + sync (GitHub Issues) — loaded per the PHASES registry in ../SKILL.md (t-1942) -->

## /brana:backlog triage

Research-informed priority reassessment across project backlogs.

### Usage

```
/brana:backlog triage [project] [--reresearch] [--scope P2+]
```

### Default behavior (no flags)

1. Read tasks.json for the project (or portfolio if omitted)
2. For each pending task without a priority, analyze: revenue impact, urgency, dependencies, effort
3. Propose priority assignments (P0-P3 tiers: P0 = this week, P1 = next, P2 = queue, P3 = backlog)
4. Wait for approval before writing

### With `--reresearch`

1. Read tasks.json
2. Identify tasks with external context: URLs in description/context/notes, tool/platform names in tags (e.g., "kapso", "respond-io", "meta")
3. For each, spawn a scout agent for brief web research (latest docs, changelog, API status)
4. Compare findings against current task description — flag if scope changed, tool matured, or blocker resolved
5. Propose priority adjustments with research summary
6. Wait for approval before writing

### With `--scope P2+`

Only re-evaluate tasks at P2 or lower (skip P0/P1 which were recently triaged).

### Priority tiers

| Tier | Meaning | Review cadence |
|------|---------|----------------|
| P0 | This week — active work | Daily |
| P1 | Next up — queue | Weekly |
| P2 | Backlog — when bandwidth allows | Monthly |
| P3 | Icebox — someday/maybe | Quarterly |

### Sort order

P0 > P1 > P2 > P3 > null. Ties broken by: in_progress first, then pending, then `order` field.

---

## /brana:backlog sync

Sync tasks.json with GitHub Issues. Creates missing issues, closes completed ones, updates stale labels.

### Usage

```
/brana:backlog sync [--dry-run] [--force]
```

### Steps

1. **Check config** — read `github_sync.enabled` from `~/.claude/tasks-config.json`. If not enabled, report: "GitHub sync not configured. Add `github_sync` to `~/.claude/tasks-config.json`."
2. **Read tasks.json** — find tasks needing sync:
   - Non-completed tasks without `github_issue` → need creation
   - Completed tasks with `github_issue` + open issue → need closing
   - Tasks with label drift (compare current task fields against live GitHub labels via `gh issue view --json labels`)
3. **Report plan:** "Sync plan: ~N to create, ~M to close, ~K to update."
4. **If `--dry-run`:** show the plan (task IDs + subjects) and exit without executing.
5. **If not dry-run:** confirm with user before executing.
6. **Execute:** run `system/scripts/gh-sync.sh sync-all {tasks-json-path}`. Script handles progress output.
7. **If `--force`:** run `system/scripts/gh-sync.sh sync-all {tasks-json-path}` without filtering — re-sync all tasks.
8. **Report summary:** "Sync complete: N created, M closed, K errors."
