---
paths: ["system/scripts/migrate/**"]
---

# Migration Scripts Must Self-Validate

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
