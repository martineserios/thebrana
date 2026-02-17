---
name: knowledge-review
description: "Monthly review of ReasoningBank health — pattern stats, staleness, confidence distribution, and suggested actions. Use monthly to audit knowledge store health and pattern quality."
allowed-tools:
  - Bash
  - Read
  - Glob
  - Grep
---

# Knowledge Review

Monthly health check for the ReasoningBank. Shows what you know, how much you trust it, and what needs attention. Human-powered review, not automated cleanup.

1. **Locate claude-flow binary** using smart discovery:
   ```bash
   CF=""
   for candidate in "$HOME"/.nvm/versions/node/*/bin/claude-flow; do
       [ -x "$candidate" ] && CF="$candidate" && break
   done
   [ -z "$CF" ] && command -v claude-flow &>/dev/null && CF="claude-flow"
   [ -z "$CF" ] && command -v npx &>/dev/null && CF="npx claude-flow"
   ```

2. **Gather stats** from ReasoningBank:
   - Run `cd $HOME && $CF memory list --namespace patterns --limit 100` to get all patterns
   - For each pattern with a meaningful key (skip `test:*` entries), retrieve the full value:
     `cd $HOME && $CF memory retrieve -k "KEY" --namespace patterns --format json`
   - Parse JSON values to extract: `confidence`, `transferable`, `recall_count`, `project`

3. **Compute health metrics:**

   ```
   ## Knowledge Health Snapshot — YYYY-MM-DD

   ### Overview
   - Total patterns: N
   - By project: project-a (N), project-b (N), ...

   ### Confidence Distribution
   - Proven (>= 0.7): N patterns
   - Quarantined (0.2 - 0.7): N patterns
   - Suspect (< 0.2): N patterns

   ### Transferability
   - Transferable: N patterns (available for cross-pollination)
   - Project-specific: N patterns

   ### Recall Activity
   - Never recalled (recall_count = 0): N patterns
   - Recalled 1-2 times: N patterns
   - Recalled 3+ times (promotion candidates): N patterns

   ### Staleness
   - Stored > 60 days ago, never recalled: N patterns (candidates for demotion)
   ```

4. **Flag items for review:**

   ```
   ### Needs Attention

   #### Promotion Candidates (recalled 3+ times, still quarantined)
   - [key]: [brief description] — recalled N times, confidence still 0.5

   #### Staleness Candidates (old, never recalled)
   - [key]: [brief description] — stored N days ago, 0 recalls

   #### Suspect Patterns (confidence < 0.2)
   - [key]: [brief description] — demoted, consider converting to anti-pattern or removing
   ```

5. **Suggest actions** — present options, let the user decide:
   - Promote candidates: "Run `/retrospective` to promote these if they've been genuinely useful"
   - Demote stale: "Lower confidence on these? They've never been recalled."
   - Remove suspect: "Delete these or convert to explicit anti-patterns?"
   - No action needed: "Knowledge base looks healthy" is a valid outcome.

6. **If ReasoningBank is empty or has only test data**, report that clearly:
   ```
   ReasoningBank has N entries (M are test data).
   The system needs real-world usage to accumulate patterns.
   Use the system in real projects and run /retrospective after notable sessions.
   ```

7. **Backup knowledge** if any patterns were promoted, demoted, or modified:
   ```bash
   BACKUP_SCRIPT="$HOME/enter_thebrana/brana-knowledge/backup.sh"
   [ -x "$BACKUP_SCRIPT" ] && "$BACKUP_SCRIPT"
   ```
   Skip silently if the script doesn't exist or if no changes were made.

## Rules

- **Don't auto-modify patterns.** This skill reports and suggests. The user decides what to change.
- **Skip test data.** Entries with keys starting with `test:` are from the test suite, not real patterns.
- **Ask for clarification whenever you need it.** If the user wants to focus on a specific project or metric — ask. Don't guess.
