---
name: session-handoff
description: Read the session handoff note left by the previous session, reconcile any cross-session changes, and continue where the last session left off.
allowed-tools: [Read, Glob, Grep, Bash, Edit, Write]
---

A session transition is happening. Follow these steps exactly:

1. **Read the handoff note** at the project's memory directory: find `session-handoff.md` under `~/.claude/projects/` for the current project's memory folder. Read it fully.

2. **Read MEMORY.md** in the same directory to understand the full project context.

3. **Check for cross-session changes** — another session may have modified spec docs, MEMORY.md, or code since the handoff was written. Run:
   - `git log --oneline -10` in the project repo to see recent commits
   - `git diff HEAD~3..HEAD --stat` to see what changed recently
   - Compare what the handoff says was done vs what's actually in the repo now

4. **Reconcile conflicts** — if another session modified files that the handoff also touched:
   - Check if the changes are compatible (additive) or conflicting
   - If conflicting: undo your predecessor's work and redo it following the newer instructions
   - If compatible: note what was added and incorporate it

5. **Report to the user:**
   - What the previous session accomplished
   - What cross-session changes were found (if any)
   - What conflicts were resolved (if any)
   - Where to continue next

6. **Update the handoff note** — append a new dated section to `session-handoff.md`. The file uses a rolling log format with one section per session:

   ```markdown
   ## YYYY-MM-DD — <brief label>

   **Accomplished:**
   - ...

   **State:**
   - Branch: ...
   - Key files touched: ...
   - Tests: passing / failing / N/A

   **Next:**
   - ...

   **Blockers:**
   - ... (or "None")
   ```

   Rules for the handoff file:
   - **Always append** — never delete or overwrite previous sections.
   - **Same date, multiple sessions?** Use `## YYYY-MM-DD (2) — label` for the second session that day, `(3)` for the third, etc.
   - **Keep each section concise** — 10-15 lines max. This is a handoff, not a journal.
   - **Trim old sections** if the file exceeds ~200 lines: collapse sections older than 30 days into a single `## Archive (before YYYY-MM-DD)` summary at the top, preserving only key decisions and unresolved items.
