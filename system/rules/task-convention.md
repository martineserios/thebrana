---
always-load: true
---
# Task Convention

Work-start ordering (read tasks.json → backlog gate → lifecycle → skills → delegation) is in `work-start.md`.

After completing: update task to `completed` with notes.

Fields: id, subject, description, tags, status, kind, type, parent, priority, effort, execution, blocked_by, branch, github_issue, created, started, completed, notes, context, strategy, build_step. Types: in-/ph-/ms-/t-/st-. Status: pending/in_progress/completed/cancelled. Kind (v2): feature/fix/refactor/research/docs/design/ops. Strategy: auto-classified from description.

Cancelling a parent task does NOT auto-cancel children. When cancelling a parent, manually cancel or re-parent all children. `brana backlog tree <parent-id>` shows the subtree.

Reads: free. Writes: confirm first.

Branch prefix: keyed on `kind` (authoritative — it names what the change does); falls back to `work_type` only when `kind` is absent (22% of tasks). The mapping and the shared `resolve_branch_prefix()` live in `system/skills/_shared/branch-prefix.md` — the single authority. Do not restate it here or in `start.md` (t-2494). Full branch format: CLAUDE.md §Branch naming.

Code tasks: `/brana:backlog start` enters `/brana:build`. Done: `/brana:build` CLOSE step. `/brana:backlog done` for manual/external only.

## AC: prefix — acceptance criteria

Lines in `context` starting with `AC:` are machine-readable acceptance criteria. `/brana:build` reads them to auto-generate a `/goal` string. Additive — tasks without `AC:` lines are unaffected.

```
context: "AC: all tests green\nAC: branch merged to main\nAC: tasks.json updated"
```

## Migration scripts must self-validate

Three surfaces write `tasks.json`: the Rust CLI, the Rust MCP server, and
ad-hoc Python migration scripts run via Bash. The first two share
`validate_work_type`/`validate_kind`/`validate_task_type`/`validate_status`
(single-field write-path validators, `brana-core/src/tasks.rs`) and cannot
drift from each other. The third bypasses both entirely — a migration script
writes the file directly and no hook can see it (`post-tasks-validate.sh`
only fires on Claude Code's own Write/Edit tool calls, not on a Bash-invoked
`python3 script.py`; see `rules-over-hooks-for-gates.md`).

**Every migration script touching `tasks.json` must end with `brana validate
<file>`** (the whole-file schema command) and report its exit status before
being considered done. Do not confuse this with `brana backlog lint <id>` —
that's a per-task Definition-of-Ready checker (unrelated, confusingly
similar name), not a schema validator.

```
Example: system/scripts/migrate/some-field-migration.py
  ... write tasks.json ...
  brana validate .claude/tasks.json || echo "MIGRATION LEFT INVALID SCHEMA"
```

## Issue tracking

- Check GitHub Issues before starting new work — avoid duplicating effort
- Link commits: `fixes #N`, `relates to #N`
- Don't create issues unless asked — check existing ones first

```
Example: user says "add rate limiting" → gh issue list --search "rate limit"
→ found #42 → commit: "feat(api): add rate limiting (fixes #42)"
```
