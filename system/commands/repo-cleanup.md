---
name: repo-cleanup
description: "Commit accumulated spec doc changes: survey, group by logical batch, branch, commit, merge"
effort: low
---

# Repo Cleanup

Commit accumulated spec doc changes that have built up across sessions. Follows GitHub Flow: branch, commit, merge, delete.

## Process

1. **Survey uncommitted changes:**
   - Run `git status` to see modified and untracked files
   - Run `git diff --stat` to see scope of changes per file
   - For each modified file, run `git diff <file> | head -60` to understand what changed

2. **Ensure .gitignore is current:**
   - Check that tooling artifacts are ignored: `.swarm/`, `.claude/memory.db`, `.mcp.json`, `*.backup.*`
   - If `.gitignore` needs updating, include that in the first commit

3. **Group changes by logical batch:**
   - Changes from the same session or cause should be one commit
   - Use `git diff <file>` content to infer what session/cause produced each change
   - Common groupings:
     - Errata applications (doc corrections from `/brana:maintain-specs` or `/brana:apply-errata`)
     - New docs (untracked `.md` files)
     - Frontmatter updates (staleness metadata)
     - Content updates from `/refresh-knowledge`
   - If grouping is unclear, ask the user

4. **For each batch:**
   - Create a branch: `git checkout -b docs/<brief-description>`
   - Stage the relevant files (by name, never `git add -A`)
   - Commit with conventional message: `docs(scope): description`
   - Merge to master: `git merge --no-ff`
   - Delete the branch

5. **Report:**
   ```
   ## Cleanup Complete
   - N commits across M branches
   - Files committed: [list]
   - Files still uncommitted: [list or "none"]
   - Files ignored: [list of tooling artifacts]
   ```

## Rules

- **Never commit tooling artifacts** (`.swarm/`, `.claude/memory.db`, `.mcp.json`) — these are runtime state, not specs.
- **Never use `git add -A` or `git add .`** — always stage by filename.
- **Ask for clarification whenever you need it.** If you can't tell why a file changed or how to group it — ask. Don't guess.
- **One logical change per commit.** Don't lump unrelated changes together.
