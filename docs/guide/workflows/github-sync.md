# GitHub Issues Sync

Sync tasks.json with GitHub Issues for external visibility, PR linking, and context persistence.

## Setup

Add `github_sync` to `~/.claude/tasks-config.json`:

```json
{
  "theme": "emoji",
  "github_sync": {
    "enabled": true,
    "repo": null,
    "project": null,
    "labels": {
      "stream": true,
      "priority": true,
      "tags": 2
    }
  }
}
```

Ensure `gh` CLI is installed and authenticated: `gh auth status`.

## How it works

**tasks.json is the source of truth.** GitHub Issues mirror task state for visibility.

| Event | What happens |
|-------|-------------|
| `/brana:backlog add` | Creates a GitHub Issue with labels |
| `/brana:backlog start` | Creates issue (if missing), pulls comments into task context |
| `/brana:backlog done` | Closes the GitHub Issue |
| `/brana:build` CLOSE | Closes the GitHub Issue |
| `/brana:backlog sync` | Bulk sync — creates missing, closes completed, updates labels |

All sync operations are **non-blocking** — if GitHub is down, the task operation succeeds locally with a warning.

## Labels

Labels are auto-created on first use:

| Prefix | Source | Color | Example |
|--------|--------|-------|---------|
| `stream:` | task stream field | Blue | `stream:roadmap` |
| `priority:` | task priority field | Red | `priority:P1` |
| `tag:` | first 2 task tags | Gray | `tag:workflow` |

## Commands

### Bulk sync

```
/brana:backlog sync              — sync all tasks
/brana:backlog sync --dry-run    — show what would be synced
/brana:backlog sync --force      — re-sync all tasks regardless of state
```

### Direct script usage

```bash
system/scripts/gh-sync.sh create <task-id> <tasks-json-path>
system/scripts/gh-sync.sh close <issue-number>
system/scripts/gh-sync.sh update <task-id> <tasks-json-path>
system/scripts/gh-sync.sh pull-context <issue-number>
system/scripts/gh-sync.sh sync-all <tasks-json-path> [--dry-run]
system/scripts/gh-sync.sh prune-labels
```

## Config options

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `enabled` | boolean | — | Enable/disable sync |
| `repo` | string\|null | auto-detect | Override repo (for cross-repo sync in v2) |
| `project` | string\|null | null | GitHub Project name (v2 — not yet implemented) |
| `labels.stream` | boolean | true | Sync `stream:X` labels |
| `labels.priority` | boolean | true | Sync `priority:X` labels |
| `labels.tags` | number | 2 | Number of task tags to sync as labels |

## Troubleshooting

**"GitHub sync failed"** — Check `gh auth status`. If expired: `gh auth login`.

**Duplicate issues** — The script dedup-checks by searching issue titles before creating. Run `sync --dry-run` to audit.

**Stale labels** — Run `system/scripts/gh-sync.sh prune-labels` to remove labels not used by any open issue.

**Deleted issues** — If an issue is manually deleted, the next sync detects the 404, clears the `github_issue` field, and re-creates on the following sync.
