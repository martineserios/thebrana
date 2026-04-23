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

Use `git worktree add ../repo-shortname -b prefix/name` instead of `git checkout`. After merge: `git worktree remove ../path && git branch -d prefix/name`. Never `rm -rf` worktrees. Agents can't write to worktrees — compose in agent, write in main context.

```bash
# Start work
git worktree add ../myapp-auth -b feat/t-015-jwt-auth
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

## Commit attribution — HARD RULE

**Never** add `Co-Authored-By`, `Signed-off-by`, `🤖 Generated with`, "Claude Code", "Claude AI", "Anthropic", or any AI/assistant trailer to commits or PRs. No exceptions for worktrees, parallel sessions, or auto-generated commits. Enforced by `system/hooks/no-attribution-commit.sh` + git pre-commit + CC `settings.json.attribution.commit/.pr=""`.
