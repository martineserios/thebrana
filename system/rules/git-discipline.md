# Git Discipline

## One rule

Every change starts on a branch. Always. No exceptions.

## Branching

- **Never commit directly to `main` or `master`.** All work happens on a branch, no matter how small.
- **Create the branch before the first edit.** Not after — before.
- **One branch per logical unit of work.** A bug fix is one branch. A feature is one branch.
- **Merge back to main when done.** Always `git merge --no-ff` to preserve branch history, then delete the branch.
- **Never force-push** to main or master.

## Branch naming

| Prefix | When |
|--------|------|
| `feat/` | New capability, roadmap phase |
| `fix/` | Something's broken |
| `docs/` | Spec changes, research |
| `chore/` | Cleanup, maintenance, config |
| `refactor/` | Same behavior, better structure |
| `test/` | Adding or fixing tests |
| `perf/` | Performance improvement |

## Worktrees

Use `git worktree` instead of `git checkout`. Multiple branches checked out simultaneously — no stashing, no WIP commits.

**The workflow** (same for planned and unplanned work):

```bash
git worktree add ../repo-feat-name -b feat/feature-name
cd ../repo-feat-name
# ... work, commit along the way ...
cd ../repo
git merge --no-ff feat/feature-name
git worktree remove ../repo-feat-name
git branch -d feat/feature-name
```

Worktree dirs sit next to the repo: `../repo-branch-shortname` (e.g., `../enter-feat-agents`).

- Always use `git worktree remove` to clean up — never `rm -rf`
- Don't leave stale worktrees — remove after merge
- `git worktree list` to see what's active
- Interruptions: create a second worktree for the fix, merge it, return to your feature

## Commits

- **Conventional commits**: `type(scope): description` — types match branch prefixes
- **Atomic commits**: one logical change per commit
- **Messages explain WHY**, not what — the diff shows what changed
- **`wip:` commits** allowed on feature branches — squash before merging

## Keep branches short-lived

- **Features**: days, not weeks. Split large work into smaller merges.
- **Fixes**: hours. Fix, merge, move on.
- **Docs**: one session. Write, review, merge.
