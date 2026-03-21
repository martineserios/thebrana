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

## Commits

- **Conventional commits**: `type(scope): description`
- **Atomic**: one logical change per commit. Messages explain WHY.
- **`wip:` commits** allowed on feature branches — squash before merging.
- After creating a worktree and writing the first file, commit immediately as `wip:` (survives context compression).

## Keep branches short-lived

Features: days. Fixes: hours. Docs: one session.
