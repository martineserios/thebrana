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
- Branch naming: task-convention.md (feat/ fix/ docs/ chore/ refactor/ test/ perf/).

## Worktrees, not checkout — HARD RULE

**New branches use `git worktree add -b`, never `git checkout -b`** — no exceptions, whatever a skill says. Concurrent sessions share the main checkout's `HEAD` + working tree, so a checkout-cut branch races their commits/merges/`tasks.json` writes (harm: t-2216/t-2206).

`cd` to the repo root first, `git worktree add ../repo-shortname -b prefix/name`, then `ls` a known file to verify the path before editing. After merge: `git worktree remove ../path && git branch -d prefix/name` — never `rm -rf`. Task agents can't write to worktrees; runner `claude -p` uses its own (ADR-060).

**The main checkout stays on `dev` — never `git checkout`/`switch` there** (ADR-094: checkout clobbers ignored live files; it wiped the ledger 2026-09-07). Ship via `/brana:ship`; other refs → worktrees. Check 74 lints; deny hook: t-3333.

## Commits

- **Conventional commits**: `type(scope): description`
- **Atomic**: one logical change per commit. Messages explain WHY.
- **`wip:` commits** allowed on feature branches — squash before merging.
- First file in a new worktree → commit `wip:` immediately (survives context compression).

## Keep branches short-lived

Features: days. Fixes: hours. Docs: one session.

## agy (Gemini)

agy never runs git. Output lands in `/tmp/` only — Claude applies it via Write/Edit.
Contract: cwd-discipline.md; enforced by `agy_delegate`.

## Commit attribution — HARD RULE

**Never** add `Co-Authored-By`, `Signed-off-by`, `🤖 Generated with`, "Claude Code", "Claude AI", "Anthropic", or any AI/assistant trailer to commits or PRs — no exceptions. Enforced by `system/hooks/no-attribution-commit.sh` + git pre-commit + CC `settings.json.attribution.commit/.pr=""`.
