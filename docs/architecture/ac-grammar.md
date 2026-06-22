# AC Grammar — Machine-Checkable Acceptance Criteria

> **Single source of truth** for the acceptance-criteria heuristic grammar.
> Both the **producer** (`/brana:backlog plan` criteria generation + lint) and the
> **consumer** (`system/hooks/goal-completion.sh`) cite this file. Keep them in sync
> by editing here first, then the implementations. See [ADR-047](decisions/ADR-047-acceptance-criteria-schema.md) §3.

## Why this file exists

The loop+goal auto-completion contract has three parties:

```
/brana:backlog plan   ──writes──▶   acceptance_criteria   ──read by──▶   goal-completion.sh
   (producer)                          (the contract)                      (consumer)
```

A criterion auto-completes its task **only** when `goal-completion.sh` can parse and
check it. Criteria that don't match any grammar below fall to **UNKNOWN** → manual
sign-off → the loop stalls. ADR-047 §3 originally documented 4 patterns while the hook
implemented 8; the table drifted. This file is the de-drift anchor (t-2199).

## The 8 heuristics

Each row is a pattern `goal-completion.sh` recognizes (regex = the actual match in
`system/hooks/goal-completion.sh:59-206`), the check it runs, and an authoring example.
A leading `AC: ` prefix is stripped before matching.

| # | Criterion shape | Match (ERE) | Check performed | Example |
|---|-----------------|-------------|-----------------|---------|
| 1 | **file exists** | `exists$` or `^file .+ exists` | extract a path ending in `.sh/.md/.json/.rs/.py/.ts/.js/.toml`; `test -f` under the work dir | `file docs/architecture/ac-grammar.md exists` |
| 2 | **backlog get returns** | `^brana backlog get .+ returns` | run the `brana backlog get …` command; `grep -F` the expected substring in output | `brana backlog get t-123 --field status returns completed` |
| 3 | **validate.sh check** | `validate\.sh.*check [0-9]+` | run `./validate.sh --check N`; pass on exit 0 | `validate.sh Check 18 passes` |
| 4 | **hook exists** | `hook .+\.sh exists` | `test -f system/hooks/{name}.sh` | `hook goal-completion.sh exists` |
| 5 | **file contains** | `^file .+ contains "` | `grep -F "{string}"` the named file | `file system/skills/build/phases/load.md contains "acceptance_criteria"` |
| 6 | **jq returns** | `^jq '.+' .+ returns` | run `jq '{expr}' {file}`; string-equal the expected value | `jq '.version' docs/spec-graph.json returns "1"` |
| 7 | **command passes** | `^"[^"]+" passes$` | run the quoted command (allowlist only); pass on exit 0 | `"cargo test" passes` |
| 8 | **git log check** | `^changes to .+ committed$` **or** `^commit message contains "` | `git log` for the path / `--grep` the message; pass if a commit matches | `commit message contains "t-2199"` · `changes to load.md committed` |
| 9 | **validate.sh passes (full)** | `validate\.sh` + `(passes\|exit 0\|exit code 0)` + NOT `check [0-9]` | run `./validate.sh` (whole suite); pass on exit 0 | `validate.sh passes` (the `/brana:reconcile` /goal done-signal, t-2206) |

Anything else → **UNKNOWN** → surfaced for manual sign-off (the task is NOT auto-completed).

## Sandbox constraints (consumer-enforced)

`goal-completion.sh` runs criteria checks unattended, so it constrains what it executes:

- **Path traversal rejected** — heuristics 5 and 6 reject paths that are absolute (`^/`)
  or contain `..`; such criteria fall to UNKNOWN rather than reading outside the work dir.
- **Command allowlist (heuristic 7)** — only these prefixes execute; anything else → UNKNOWN:
  `cargo test`, `pytest`, `python -m pytest`, `bun test`, `npm test`, `yarn test`,
  `bash tests/`, `./tests/`.
- **Work-dir scoped** — all relative paths resolve under the goal's recorded `cwd`
  (`active-goal.json`), never the hook's own `/tmp` cwd.

## Authoring rules (producer)

From ADR-047 §1 — a criterion is valid only if:

- **Falsifiable** — "X does Y when Z", not "X works correctly".
- **Observable** — CLI output, file state, test pass/fail, HTTP response.
- **What, not how** — no implementation detail.
- **Max 10 per task** — more is a scope signal; split the task.

`/brana:backlog plan` generates criteria by `work_type` template, then **lints** each
against the 8 heuristics above: a criterion matching none is kept but flagged
(`won't auto-complete — loop needs manual sign-off`), never silently dropped (lint+warn,
not hard-block — genuine human-judgment criteria are allowed).

## Keeping this in sync

When a heuristic is added/changed in `goal-completion.sh`:

1. Edit the table here first.
2. Update the implementation (`goal-completion.sh`) and `ADR-047` §3 to match.
3. The lint in `/brana:backlog plan` reads this file's heuristic list — no separate copy.

This is the contract `tests/procedures/` should assert against so the three never diverge again.
