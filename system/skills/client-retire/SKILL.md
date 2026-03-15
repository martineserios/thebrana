---
name: client-retire
description: "Archive a client's patterns and mark them as historical. Use when retiring a client or archiving its knowledge for future reference."
argument-hint: "[client-slug]"
group: execution
allowed-tools:
  - Bash
  - Read
  - Write
  - Glob
  - Grep
  - AskUserQuestion
---

# Client Retire

1. Identify the client to retire from `$ARGUMENTS` or current client context.

2. **Primary path (ruflo available):**
   ```bash
   source "$HOME/.claude/scripts/cf-env.sh"
   ```
   Query memory DB for all patterns tagged with this client via `cd $HOME && $CF memory search --query "client:{name}"`. List them with confidence scores.

3. **Fallback path (ruflo unavailable):**
   Read the client's `~/.claude/projects/{project-hash}/memory/MEMORY.md` and list all documented patterns.

4. For each pattern, categorize:
   - **High-confidence + transferable** → keep active, remove client-specific lock
   - **High-confidence + client-specific** → archive with `status: historical`
   - **Low-confidence** → archive or flag for deletion

5. Run the archival: tag patterns with `archived: true` and `archived_date: {today}`.

6. Suggest updating `~/.claude/memory/portfolio.md` to mark the client as retired.

7. **Never delete anything** — only tag and archive. Deletion is a human decision.

8. **Backup knowledge** after archiving:
   ```bash
   "$HOME/.claude/scripts/backup-knowledge.sh"
   ```
   Skip silently if the script doesn't exist.

## Rules

- **Ask for clarification whenever you need it.** If you're unsure which patterns to keep active vs archive, or the client scope is ambiguous — ask. Don't guess.
