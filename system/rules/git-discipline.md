# Git Discipline

## One rule

Every change starts on a branch. Always. No exceptions.

## Branching

- **Never commit directly to `main` or `master`.** All work happens on a branch, no matter how small.
- **Create the branch before the first edit.** Not after — before.
- **One branch per logical unit of work.** A bug fix is one branch. A feature is one branch.
- **Merge back to main when done.** Use `git merge --no-ff` to preserve history, then delete the branch.
- **Never force-push** to main or master.

## Branch naming

| Prefix | When | Example |
|--------|------|---------|
| `feat/` | New capability, roadmap phase | `feat/phase-2-hooks` |
| `fix/` | Something's broken | `fix/session-end-hook` |
| `docs/` | Spec changes, research | `docs/git-branching-research` |
| `chore/` | Cleanup, maintenance, config | `chore/deploy-scripts` |
| `refactor/` | Same behavior, better structure | `refactor/hook-api-calls` |
| `test/` | Adding or fixing tests | `test/hook-validation` |
| `perf/` | Performance improvement | `perf/memory-search-speed` |

## Worktrees over checkout

Use `git worktree add ../repo-shortname -b prefix/name` instead of `git checkout`. Worktrees let you have multiple branches checked out simultaneously — no stashing, no WIP commits. After merge: `git worktree remove ../path && git branch -d prefix/name`.

- Naming: `../repo-branch-shortname` (e.g., `../thebrana-fix-deploy`)
- **Always use `git worktree remove`** — never `rm -rf`
- **Don't leave stale worktrees** — remove after merge
- **Agents can't write to worktrees** — sandboxed to project dir. Pattern: agents compose → main context writes.

## Commits

- **Conventional commits**: `type(scope): description` — types match branch prefixes
- **Atomic commits**: one logical change per commit
- **Messages explain WHY**, not what — the diff shows what changed
- **`wip:` commits** allowed on feature branches — squash before merging

## `--no-ff` always

Always merge with `--no-ff`. Preserves the branch as a visible group in `git log --graph`.

## Keep branches short-lived

- **Features**: days, not weeks. Split large work into smaller merges.
- **Fixes**: hours. Fix, merge, move on.
- **Docs**: one session. Write, review, merge.
