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
git checkout -b feat/phase-3-learning-loop
# ... work, commit along the way ...
git checkout main && git merge --no-ff feat/phase-3-learning-loop
git branch -d feat/phase-3-learning-loop
```

### Unplanned work (bugs, fixes, "I just noticed this")

```bash
git checkout -b fix/typo-in-doc-14
# ... fix it, commit ...
git checkout main && git merge --no-ff fix/typo-in-doc-14
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

## Handling interruptions

Working on a feature and notice a bug? Commit what you have, switch, fix, come back:

```bash
git add -A && git commit -m "wip: pause for bugfix"
git checkout main
git checkout -b fix/the-bug
# ... fix, commit, merge to main, delete branch ...
git checkout feat/your-feature    # back to work
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
