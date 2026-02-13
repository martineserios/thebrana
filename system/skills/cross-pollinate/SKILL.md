---
name: cross-pollinate
description: Pull patterns from other projects that might be relevant to the current one. Use when stuck on a problem, encountering a familiar pattern, or starting work on a tech stack used in another project.
allowed-tools:
  - Bash
  - Read
  - Glob
  - Grep
---

# Cross-Pollinate

1. Detect current project's tech stack and problem domain.

2. **Primary path (claude-flow available):**
   Locate the binary:
   ```bash
   CF=""
   for candidate in "$HOME"/.nvm/versions/node/*/bin/claude-flow; do
       [ -x "$candidate" ] && CF="$candidate" && break
   done
   [ -z "$CF" ] && command -v claude-flow &>/dev/null && CF="claude-flow"
   [ -z "$CF" ] && command -v npx &>/dev/null && CF="npx claude-flow"
   ```
   Run `cd $HOME && $CF memory search --query "$ARGUMENTS"` to find patterns across all projects. Filter for transferable patterns from other projects in the results.

3. **Fallback path (claude-flow unavailable):**
   Scan `~/.claude/projects/*/memory/MEMORY.md` files from OTHER projects (not current). Grep for technology and pattern type matches.

4. Filter results: only show patterns marked `transferable: true` or with confidence > 0.7 if using fallback.

5. For each pattern, show:
   - Source project
   - The pattern (problem + solution)
   - Confidence score
   - Why it might be relevant to the current project

6. If `$ARGUMENTS` provided, focus search on that topic. Otherwise, do a broad tech-stack match.

7. Explicitly note: cross-pollinated patterns should be validated in the current project context before trusting them. What works in one project may not work in another.

## Rules

- **Ask for clarification whenever you need it.** If you're unsure which patterns are relevant, the project context is unclear, or you need the user to narrow the scope — ask. Don't guess.
