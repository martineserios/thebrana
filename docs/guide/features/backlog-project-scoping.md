# Backlog: Per-Project Scoping & Cross-Project Tasks

**Status:** stable · **Task:** t-2155 · **Since:** 2026-06-20

Each project (thebrana, every client, every venture) keeps its **own** backlog and its
**own** backlog config. This guide covers how scoping works and how to file a task into a
*different* project when you spot something mid-work.

## TL;DR

| You want to… | Command |
|---|---|
| See this project's focus | `brana backlog focus` |
| Set this project's active epic | `brana backlog set-active <slug>` |
| File a task in **another** project | `brana backlog add --project <slug> --subject "…"` |
| Focus a specific epic once (no state change) | `brana backlog focus --epic <slug>` |
| See everything across projects | `brana backlog status --all` |

## How scoping works

Two files live under each repo's `.claude/`:

- **`tasks.json`** — the backlog (tasks). Always per-repo, committed with the repo.
- **`tasks-config.json`** — backlog config: `active_epic`, `theme`, `github_sync`.

Both resolve **per-repo** via the git root (shared across worktrees of the same repo, the
same way `tasks.json` always has been). `tasks-config.json` is **gitignored** — it holds
personal, per-machine working state (which epic you're focused on, your theme).

### Config resolution

1. Project-local `{repo}/.claude/tasks-config.json` — if it exists, it is authoritative.
2. Otherwise the global `~/.claude/tasks-config.json` is consulted **only** for inheritable
   keys (`theme`, `github_sync`).
3. **Project-scoped keys never inherit.** `active_epic` and `active_initiative` belong to
   exactly one project — a global value is never borrowed into a different project. This is
   why opening a client no longer shows thebrana's epic.

`brana backlog set-active <slug>` writes the project-local file (creating it, seeded from the
global theme/sync defaults). The global file is never modified by normal operations.

## Cross-project task creation

Spotted a thebrana bug while working in a client? File it without leaving:

```bash
brana backlog add --project thebrana --subject "[bug] focus shows wrong epic" --kind fix
```

- `--project <slug>` resolves the target repo's `tasks.json` via `~/.claude/tasks-portfolio.json`.
- The default (no `--project`) is always the **current** project — cross-project writes are
  never accidental.
- Unknown slug → error. `--project` and `--file` are mutually exclusive.
- Works the same from the MCP `backlog_add` tool (optional `project` field), so it works inside
  a Claude Code session too.

## Worktrees

Config is per-**repo**, so all worktrees of a repo share one `active_epic`. To focus a
different epic in one worktree without changing the shared pointer, use the per-invocation
override:

```bash
brana backlog focus --epic <slug>
```

## Notes & limits

- The MCP server resolves the project from its launch-time working directory. Switching
  projects mid-session (without Claude Code relaunching the server) keeps the launch-time
  project — the same assumption task data already makes. Open a fresh session per project.
- New client repos should add `.claude/tasks-config.json` to `.gitignore` (thebrana already
  does; `brana:align`/`onboard` carry the convention forward).
