# triage-stale spec stub

**Task:** t-1355
**Command:** `brana backlog triage-stale`

## Problem

402+ pending tasks exist. ~24 have feat/fix/merge commits on main — they were shipped but never closed. Manual reconciliation is impractical.

## Behaviour

1. Run `git log --all --oneline` in the repo root
2. Extract task IDs from branch-name patterns in merge commits and direct commits (precision match — branch prefix only, not casual mentions)
3. Cross-reference against pending tasks in tasks.json
4. Present matches in batches of N (default 10) and prompt: close / skip / quit
5. Close confirmed tasks (status → completed, completed date → today)

## Precision match patterns

A task ID `t-NNN` counts as "shipped" if it appears in git log as:
- A merge commit subject: `merge(feat/t-NNN-...)`, `merge(fix/t-NNN-...)`, `merge(refactor/t-NNN-...)`
- A branch-name-prefixed direct commit: subject starts with `feat(t-NNN` or `fix(t-NNN` — i.e. the scope IS the task ID

Does NOT count: casual mention anywhere in commit body, or `t-NNN` appearing only in a chore/docs/sync commit.

## Pure functions (testable)

- `extract_task_ids_from_git_log(log: &str) -> Vec<String>`
  Parse raw `git log --all --oneline` output. Return unique task IDs matching the precision patterns above.

- `find_shipped_pending<'a>(pending: &'a [&serde_json::Value], shipped_ids: &[String]) -> Vec<&'a serde_json::Value>`
  Cross-reference: return pending tasks whose ID appears in `shipped_ids`.

## Flags

- `--dry-run` — print what would be closed, no writes
- `--batch N` — batch size (default 10)
- `--yes` — close all without prompting (for automation)
- `--git-dir <path>` — override repo path (default: CWD)
