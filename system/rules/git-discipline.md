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

## Worktrees over checkout

Use `git worktree add ../repo-shortname -b prefix/name` instead of `git checkout`. After merge: `git worktree remove ../path && git branch -d prefix/name`. Never `rm -rf` worktrees. **In-session** agents (Task tool, CWD-bound) can't write to worktrees — compose in agent, write in main context. (Runner `claude -p` writes in its own worktree — ADR-060.)

**Always `cd` to the repo root before `git worktree add`** so `../` resolves to the repo's parent directory, not wherever the shell happens to be. After adding, spot-check with `ls` on a known file inside the worktree before doing any work there.

```bash
# Start work
git worktree add ../myapp-auth -b feat/t-015-jwt-auth
ls ../myapp-auth/README.md  # verify path resolved correctly
# Done — merge and clean up
git merge --no-ff feat/t-015-jwt-auth
git worktree remove ../myapp-auth && git branch -d feat/t-015-jwt-auth
```

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
