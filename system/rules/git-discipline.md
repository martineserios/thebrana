# Git Discipline

## One rule

Every change starts on a branch. Always. No exceptions.

## Branching

- **Never commit directly to `main` or `master`.** All work happens on a branch, no matter how small.
- **Create the branch before the first edit.** Not after — before. If you're about to change a file, you should already be on a branch.
- **One branch per logical unit of work.** A bug fix is one branch. A new skill is one branch. A phase of the roadmap is one branch.
- **Merge back to main when done.** Use `git merge --no-ff` to preserve the branch history as a merge commit, then delete the branch.
- **Never force-push** to main or master.

## Two types of work

All work falls into one of two categories. The workflow is the same for both.

### Planned work (phases, features, capabilities)

```bash
git worktree add ../repo-feat-learning-loop -b feat/phase-3-learning-loop
cd ../repo-feat-learning-loop
# ... work, commit along the way ...
cd ../repo
git merge --no-ff feat/phase-3-learning-loop
git worktree remove ../repo-feat-learning-loop
git branch -d feat/phase-3-learning-loop
```

### Unplanned work (bugs, fixes, "I just noticed this")

```bash
git worktree add ../repo-fix-doc14 -b fix/typo-in-doc-14
cd ../repo-fix-doc14
# ... fix it, commit ...
cd ../repo
git merge --no-ff fix/typo-in-doc-14
git worktree remove ../repo-fix-doc14
git branch -d fix/typo-in-doc-14
```

## Branch naming

The prefix IS the organization. It tells the story at a glance.

| Prefix | When | Example |
|--------|------|---------|
| `feat/` | New capability, roadmap phase | `feat/phase-2-hooks` |
| `fix/` | Something's broken | `fix/session-end-hook` |
| `docs/` | Spec changes, research | `docs/git-branching-research` |
| `chore/` | Cleanup, maintenance, config | `chore/deploy-scripts` |
| `refactor/` | Same behavior, better structure | `refactor/hook-api-calls` |
| `test/` | Adding or fixing tests | `test/hook-validation` |
| `perf/` | Performance improvement | `perf/memory-search-speed` |

## Worktrees for branch operations

Use `git worktree` instead of `git checkout` when switching branches. Worktrees let you have multiple branches checked out simultaneously in separate directories — no stashing, no WIP commits, no losing your place.

### The workflow

```bash
# Create worktree for a feature (new branch)
git worktree add ../repo-feat-name -b feat/feature-name

# Work in the worktree
cd ../repo-feat-name
# ... edit, commit ...

# Merge from the worktree (no checkout needed on main)
cd ../repo                          # back to main worktree
git merge --no-ff feat/feature-name

# Clean up
git worktree remove ../repo-feat-name
git branch -d feat/feature-name
```

### When to use worktrees

- **Branch operations** (merge, rebase): avoid stash/checkout dance
- **Parallel work**: work on feature A while agent works on feature B
- **Interruptions**: don't WIP-commit — just `cd` to another worktree
- **Review**: inspect a branch without leaving your current work

### Naming convention

Worktree directories sit next to the repo: `../repo-branch-shortname`. Examples:
- `../enter-feat-agents` for `feat/agent-skill-symbiosis`
- `../thebrana-fix-deploy` for `fix/deploy-script`

### Rules

- **One branch per worktree** — git enforces this
- **Always use `git worktree remove`** to clean up — never `rm -rf` the directory
- **Don't leave stale worktrees** — remove after merge
- **`git worktree list`** to see what's active

### Handling interruptions (with worktrees)

Working on a feature and notice a bug? No stashing needed:

```bash
# From your feature worktree, create a new worktree for the fix
git worktree add ../repo-fix-bug -b fix/the-bug
cd ../repo-fix-bug
# ... fix, commit ...
cd ../repo
git merge --no-ff fix/the-bug
git worktree remove ../repo-fix-bug
git branch -d fix/the-bug
cd ../repo-feat-name              # back to your feature, untouched
```

## Commits

- **Conventional commits**: `type(scope): description`
  - Types match branch prefixes: `feat`, `fix`, `refactor`, `docs`, `test`, `chore`, `perf`
- **Atomic commits**: one logical change per commit
- **Commit messages explain WHY**, not what — the diff shows what changed
- **`wip:` commits** are allowed on feature branches for context switches — squash or amend them before merging

## `--no-ff` always

Always use `--no-ff` when merging. This preserves the branch as a visible group in `git log --graph`. To make it the default:

```bash
git config --global merge.ff false
```

## Keep branches short-lived

- **Features**: days, not weeks. Split large work into smaller merges.
- **Fixes**: hours. Fix, merge, move on.
- **Docs**: one session. Write, review, merge.

## Why this matters

A clean git history is a navigable history. Branches make every change reversible, every phase inspectable, and every mistake recoverable. `git log --oneline --graph` should tell the story of what was built and when.
