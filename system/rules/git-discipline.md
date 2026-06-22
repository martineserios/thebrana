---
always-load: true
---
# Git Discipline

## One rule

Every change starts on a branch. Always. No exceptions.

## Branching

- **Never commit directly to `main`/`master`.** Create the branch before the first edit.
- **One branch per logical unit of work.** Merge with `--no-ff`, then delete.
- **Never force-push** to main or master.
- Branch naming: see task-convention.md. Prefixes: feat/, fix/, docs/, chore/, refactor/, test/, perf/.

## Worktrees, not checkout — HARD RULE

**New branches use `git worktree add -b`, never `git checkout -b`** — every time, no size/kind exception, and this **overrides skill-procedure defaults** (if `start.md` shows `git checkout -b`, ignore it). Concurrent sessions share the main checkout's `HEAD` + working tree, so a checkout-cut branch races their commits/merges/`tasks.json` writes (harm: t-2216/t-2206, 2026-06-22).

`cd` to the repo root first (so `../` resolves correctly), `git worktree add ../repo-shortname -b prefix/name`, then `ls` a known file to verify the path before editing. After merge: `git worktree remove ../path && git branch -d prefix/name` — never `rm -rf`. **In-session** Task agents can't write to worktrees (compose in agent, write in main); runner `claude -p` writes in its own worktree (ADR-060).

## Commits

- **Conventional commits**: `type(scope): description`
- **Atomic**: one logical change per commit. Messages explain WHY.
- **`wip:` commits** allowed on feature branches — squash before merging.
- After creating a worktree and writing the first file, commit immediately as `wip:` (survives context compression).

```
feat(auth): add JWT validation middleware
fix(api): handle null response from payment gateway
wip: scaffold auth tests (squash before merge)
```

## Keep branches short-lived

Features: days. Fixes: hours. Docs: one session.

## agy (Gemini)

agy never runs git commands. Output lands in `/tmp/` only — Claude applies via Write/Edit.
Full isolation contract: cwd-discipline.md. Enforced by `agy_delegate`.

## Commit attribution — HARD RULE

**Never** add `Co-Authored-By`, `Signed-off-by`, `🤖 Generated with`, "Claude Code", "Claude AI", "Anthropic", or any AI/assistant trailer to commits or PRs. No exceptions for worktrees, parallel sessions, or auto-generated commits. Enforced by `system/hooks/no-attribution-commit.sh` + git pre-commit + CC `settings.json.attribution.commit/.pr=""`.
