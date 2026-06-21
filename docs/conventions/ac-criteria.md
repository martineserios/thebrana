# AC: Criteria — Authoring Guide

> **Canonical grammar:** [`docs/architecture/ac-grammar.md`](../architecture/ac-grammar.md) is the
> single source of truth for the 8 heuristics (cited by both `goal-completion.sh` and the
> `/brana:backlog plan` lint). This page is the user-facing authoring view; keep the two in sync.

Acceptance criteria live in the task's **`acceptance_criteria` field** (canonical, ADR-047 §1).
`AC:` lines in `context` are a typing shorthand — `/brana:build` LOAD reads them and **normalizes
them into the field** on first build (t-2202), so the field is the durable store. Both are parsed
by `system/hooks/goal-completion.sh` at session end. Use the forms below for auto-verification;
any other form falls through to UNKNOWN (manual sign-off required).

**You usually don't hand-write these.** `/brana:backlog plan` auto-generates `acceptance_criteria`
for leaf implement/design tasks (template+LLM-fill by `work_type`), lints each via
`system/scripts/ac-lint.sh`, and warns when a criterion won't auto-complete. Write `AC:` lines by
hand only when adding criteria to an existing task outside planning.

## Supported forms

| Form | Heuristic | Example |
|------|-----------|---------|
| `{path} exists` | H1: file exists | `AC: system/hooks/goal-completion.sh exists` |
| `brana backlog get {id} returns {value}` | H2: task field check | `AC: brana backlog get t-1828 returns completed` |
| `validate.sh Check {N} passes` | H3: validate check | `AC: validate.sh Check 29 passes` |
| `hook {name}.sh exists in system/hooks/` | H4: hook file exists | `AC: hook goal-completion.sh exists in system/hooks/` |
| `file {path} contains "{string}"` | H5: file content check | `AC: file docs/architecture/decisions/ADR-045.md contains "Status: Accepted"` |
| `jq '{expr}' {file} returns "{value}"` | H6: JSON field check | `AC: jq '.jobs["feed-poll"].enabled' system/scheduler/scheduler.template.json returns "false"` |
| `"{command}" passes` | H7: test command (allowlisted) | `AC: "cargo test --test hooks" passes` |
| `changes to {file} committed` | H8: git log check | `AC: changes to system/hooks/goal-completion.sh committed` |
| `commit message contains "{string}"` | H8: git log --grep | `AC: commit message contains "t-1828"` |

## H7 allowlist

Only these command prefixes are executed. Others fall through to UNKNOWN (never executed):
- `cargo test`
- `pytest` / `python -m pytest`
- `bun test` / `npm test` / `yarn test`
- `bash tests/` / `./tests/`

## Sandbox rules

- H5 and H6 paths are sandboxed to the task's `cwd` (WORK_DIR). Absolute paths or `..` in paths → FAIL.
- H7 commands run in WORK_DIR.
- H8 git log is read-only — no sandboxing needed.

## UNKNOWN fallback

Criteria that match no heuristic surface for manual sign-off:
> `t-NNN: N criteria need manual sign-off: ? {criterion}  Run /brana:backlog done t-NNN to complete.`

Behavioral criteria like "sessions start without blocking" or "confirmed working on remote server" cannot be checked deterministically — write them as UNKNOWN-aware prose or omit them.

## Active-goal.json

Goal injection happens in `/brana:build` Step 0. When `AC:` lines exist in the task context, the build writes:
```json
{"task_id": "t-NNN", "cwd": "/path/to/repo", "session_id": "...", "criteria": ["file x exists", "..."]}
```
to `~/.claude/run-state/active-goal.json`. The Stop hook reads this on every clean stop.
