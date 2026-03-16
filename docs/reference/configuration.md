# Configuration Reference

All configuration file schemas used by the brana system.

## tasks.json

Per-project task backlog. Located at `{project}/.claude/tasks.json`.

### Top-level schema

```json
{
  "version": 1,
  "project": "project-name",
  "last_modified": "2026-03-10T12:00:00-03:00",
  "tasks": []
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `version` | number | Yes | Schema version (currently 1) |
| `project` | string | Yes | Project identifier |
| `last_modified` | ISO 8601 | No | Auto-updated by hooks |
| `tasks` | array | Yes | Task objects |

### Task object schema

```json
{
  "id": "t-015",
  "subject": "JWT authentication",
  "description": "Implement JWT auth middleware",
  "tags": ["auth", "security"],
  "status": "pending",
  "stream": "roadmap",
  "type": "task",
  "parent": "ph-002",
  "order": 1,
  "priority": "P1",
  "effort": "M",
  "execution": "code",
  "blocked_by": ["t-014"],
  "branch": "feat/t-015-jwt-auth",
  "github_issue": 42,
  "created": "2026-03-01",
  "started": null,
  "completed": null,
  "notes": null,
  "context": null,
  "strategy": "feature",
  "build_step": "specify"
}
```

| Field | Type | Required | Values | Description |
|-------|------|----------|--------|-------------|
| `id` | string | Yes | `ph-*`, `ms-*`, `t-*`, `st-*` | Unique ID with type prefix |
| `subject` | string | Yes | -- | Short title |
| `description` | string | No | -- | Detailed description |
| `tags` | string[] | No | -- | Categorization tags (null default) |
| `status` | string | Yes | `pending`, `in_progress`, `completed`, `cancelled` | Current state |
| `stream` | string | Yes | `roadmap`, `bugs`, `tech-debt`, `docs`, `experiments`, `research` | Work category |
| `type` | string | Yes | `phase`, `milestone`, `task`, `subtask` | Hierarchy level |
| `parent` | string | No | -- | Parent task ID |
| `order` | number | No | -- | Sort order within parent |
| `priority` | string | No | `P0`-`P3` | Urgency (null unless user specifies) |
| `effort` | string | No | `XS`, `S`, `M`, `L`, `XL` | Size estimate (null unless user specifies) |
| `execution` | string | No | `code`, `external`, `manual` | How the task is done |
| `blocked_by` | string[] | No | -- | IDs that must complete first |
| `branch` | string | No | -- | Git branch name |
| `github_issue` | number | No | -- | Linked GitHub issue |
| `created` | date | No | -- | Creation date |
| `started` | date | No | -- | When set to in_progress |
| `completed` | date | No | -- | When set to completed |
| `notes` | string | No | -- | Completion notes |
| `context` | string | No | -- | Additional context (null default) |
| `strategy` | string | No | `feature`, `bug-fix`, `refactor`, `spike`, `migration`, `investigation`, `greenfield` | Auto-classified, user-confirmed |
| `build_step` | string | No | `specify`, `decompose`, `build`, `close` | Position in /brana:build loop |

### ID conventions

| Prefix | Type | Example |
|--------|------|---------|
| `ph-` | phase | `ph-001` |
| `ms-` | milestone | `ms-005` |
| `t-` | task | `t-015` |
| `st-` | subtask | `st-022` |

### Branch conventions by stream

| Stream | Branch prefix | Example |
|--------|--------------|---------|
| roadmap | `feat/` | `feat/t-015-jwt-auth` |
| bugs | `fix/` | `fix/t-022-session-timeout` |
| tech-debt | `refactor/` | `refactor/t-030-hook-cleanup` |
| docs | `docs/` | `docs/t-030-api-contracts` |
| experiments | `experiment/` | `experiment/t-040-graphrag` |
| research | `research/` | `research/t-091-graphrag-eval` |

### Validation (post-tasks-validate.sh)

The `post-tasks-validate.sh` hook validates on every Write/Edit:
1. Valid JSON
2. Required top-level fields: `version`, `project`, `tasks` (array)
3. Per-task required fields: `id`, `subject`, `status`, `type`, `stream`
4. Status enum: `pending`, `in_progress`, `completed`, `cancelled`
5. Type enum: `phase`, `milestone`, `task`, `subtask`
6. Tags must be string array if present
7. Context must be string if present
8. Auto-rollup: parents whose children are all completed get auto-completed

---

## tasks-portfolio.json

Cross-client project registry. Located at `~/.claude/tasks-portfolio.json`.

### Schema

```json
{
  "clients": [
    {
      "slug": "brana",
      "projects": [
        {
          "slug": "thebrana",
          "path": "~/enter_thebrana/thebrana",
          "type": "ai-system",
          "stage": "active",
          "tech_stack": "bash, markdown",
          "created": "2025-12-01"
        }
      ]
    }
  ]
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `clients` | array | Yes | Client objects |
| `clients[].slug` | string | Yes | Client identifier |
| `clients[].projects` | array | Yes | Project objects |
| `clients[].projects[].slug` | string | Yes | Project identifier |
| `clients[].projects[].path` | string | Yes | Path to project (supports `~/` prefix, resolved to `$HOME`) |
| `clients[].projects[].type` | string | No | Project type descriptor |
| `clients[].projects[].stage` | string | No | Current stage |
| `clients[].projects[].tech_stack` | string | No | Technologies used |
| `clients[].projects[].created` | date | No | Creation date |

A legacy flat format `{ "projects": [...] }` is also supported for backward compatibility.

For each project, the backlog skill reads `{path}/.claude/tasks.json` if it exists. Projects without a tasks.json are silently skipped.

---

## tasks-config.json

Display preferences for the backlog skill. Located at `~/.claude/tasks-config.json`.

### Schema

```json
{
  "theme": "classic"
}
```

| Field | Type | Required | Default | Values | Description |
|-------|------|----------|---------|--------|-------------|
| `theme` | string | No | `classic` | `classic`, `emoji`, `minimal` | Display theme for task views |

Theme resolution order:
1. `--theme <name>` flag on the command
2. `~/.claude/tasks-config.json` `theme` field
3. Default: `classic`

---

## scheduler.json

Scheduled job configuration. Template at `system/scheduler/scheduler.template.json`, deployed to `~/.claude/scheduler/scheduler.json` by bootstrap.

### Schema

```json
{
  "version": 1,
  "defaults": {
    "model": "haiku",
    "allowedTools": "Read,Glob,Grep,WebSearch",
    "logRetention": 30,
    "timeoutSeconds": 300
  },
  "jobs": {
    "job-name": { }
  }
}
```

### Top-level fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `version` | number | Yes | Schema version (currently 1) |
| `defaults` | object | Yes | Default settings for all jobs |
| `defaults.model` | string | Yes | Default model for skill jobs |
| `defaults.allowedTools` | string | Yes | Comma-separated tool list |
| `defaults.logRetention` | number | Yes | Days to keep logs |
| `defaults.timeoutSeconds` | number | Yes | Default timeout per job |
| `jobs` | object | Yes | Named job definitions |

### Job object schema

```json
{
  "type": "command",
  "command": "./scripts/staleness-report.sh",
  "project": "~/enter_thebrana/thebrana",
  "schedule": "Mon *-*-* 09:00:00",
  "enabled": true,
  "model": "sonnet",
  "allowedTools": "Read,Glob,Grep,WebSearch,WebFetch",
  "maxRetries": 1,
  "retryBackoffSec": 60,
  "captureOutput": true,
  "timeoutSeconds": 600,
  "_comment": "Description of the job"
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `type` | string | Yes | `command` (shell) or `skill` (Claude skill) |
| `command` | string | Conditional | Shell command to run (type=command) |
| `skill` | string | Conditional | Skill path to invoke (type=skill) |
| `project` | string | Yes | Project directory (supports `~/`) |
| `schedule` | string | Yes | systemd calendar format |
| `enabled` | boolean | Yes | Whether the job runs |
| `model` | string | No | Override default model |
| `allowedTools` | string | No | Override default tools |
| `maxRetries` | number | No | Retry count on failure |
| `retryBackoffSec` | number | No | Seconds between retries |
| `captureOutput` | boolean | No | Store stdout/stderr |
| `timeoutSeconds` | number | No | Override default timeout |
| `_comment` | string | No | Human-readable description |

### Built-in jobs

| Job | Type | Schedule | Default state |
|-----|------|----------|---------------|
| `staleness-report` | command | Monday 09:00 | disabled |
| `link-check` | command | Monday 09:00 | disabled |
| `knowledge-review` | skill | 1st of month 10:00 | disabled |
| `morning-check` | skill | Mon-Fri 08:00 | disabled |
| `weekly-review` | skill | Friday 17:00 | disabled |
| `agentdb-watch` | command | Daily 09:00 | enabled |
| `reindex-knowledge` | command | Sunday 03:00 | enabled |

---

## plugin.json

Plugin manifest. Located at `system/.claude-plugin/plugin.json`.

### Schema

```json
{
  "name": "brana",
  "description": "AI development system -- skills, agents, and hooks for systematic software engineering with Claude Code",
  "version": "1.0.0",
  "author": {
    "name": "Martin Eserios"
  },
  "repository": "https://github.com/martineserios/thebrana",
  "license": "MIT",
  "keywords": ["ai", "development", "tdd", "skills", "agents", "hooks"]
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `name` | string | Yes | Plugin name (used as skill namespace prefix: `/brana:*`) |
| `description` | string | Yes | Human-readable description |
| `version` | string | Yes | Semantic version |
| `author` | object | No | Author info |
| `author.name` | string | No | Author name |
| `repository` | string | No | Source repository URL |
| `license` | string | No | License identifier |
| `keywords` | string[] | No | Discovery keywords |

The plugin name determines the skill namespace. All skills in `system/skills/` are exposed as `/brana:<skill-name>` (e.g., `/brana:build`, `/brana:backlog`).

For marketplace distribution, a `marketplace.json` file at the repo root enables: `/plugin marketplace add martineserios/thebrana` then `/plugin install brana`.
