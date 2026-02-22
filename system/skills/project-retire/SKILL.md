---
name: project-retire
description: "Archive a project's patterns and mark them as historical. Use when retiring a project or archiving its knowledge for future reference."
allowed-tools:
  - Bash
  - Read
  - Write
  - Glob
  - Grep
---

# Project Retire

1. Identify the project to retire from `$ARGUMENTS` or current project context.

2. **Primary path (claude-flow available):**
   ```bash
   source "$HOME/.claude/scripts/cf-env.sh"
   ```
   Query memory DB for all patterns tagged with this project via `cd $HOME && $CF memory search --query "project:{name}"`. List them with confidence scores.

3. **Fallback path (claude-flow unavailable):**
   Read the project's `~/.claude/projects/{project-hash}/memory/MEMORY.md` and list all documented patterns.

4. For each pattern, categorize:
   - **High-confidence + transferable** → keep active, remove project-specific lock
   - **High-confidence + project-specific** → archive with `status: historical`
   - **Low-confidence** → archive or flag for deletion

5. Run the archival: tag patterns with `archived: true` and `archived_date: {today}`.

6. Suggest updating `~/.claude/memory/portfolio.md` to mark the project as retired.

7. **Never delete anything** — only tag and archive. Deletion is a human decision.

8. **Backup knowledge** after archiving:
   ```bash
   "$HOME/.claude/scripts/backup-knowledge.sh"
   ```
   Skip silently if the script doesn't exist.

## Rules

- **Ask for clarification whenever you need it.** If you're unsure which patterns to keep active vs archive, or the project scope is ambiguous — ask. Don't guess.
