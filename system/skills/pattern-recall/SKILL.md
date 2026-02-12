---
name: pattern-recall
description: Query learned patterns relevant to the current context or a specific topic
allowed-tools:
  - Bash
  - Read
  - Glob
  - Grep
---

# Pattern Recall

1. If `$ARGUMENTS` provided, use it as query. Otherwise, infer query from current project context (tech stack, current task, recent errors).

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
   Run `cd $HOME && $CF memory search --query "$ARGUMENTS"` to search the memory DB for matching patterns. Parse the JSON value of each result to extract `confidence`, `transferable`, and `recall_count` fields.

3. **Fallback path (claude-flow unavailable):**
   Search `~/.claude/projects/*/memory/` for relevant MEMORY.md files. Grep for keywords from the query. Present findings.

4. **Group results by confidence tier:**

   ```
   ## Proven patterns (confidence >= 0.7)
   - [pattern] — confidence: X, recalls: N, source: PROJECT, transferable: yes/no

   ## Quarantined patterns (confidence >= 0.2, < 0.7)
   - [pattern] — confidence: X, recalls: N, source: PROJECT (treat with caution — not yet validated)

   ## Suspect patterns (confidence < 0.2)
   - [pattern] — confidence: X, recalls: N, source: PROJECT (previously demoted — use at own risk)
   ```

   For each pattern show: description, confidence score, recall count, source project, transferable status.

5. If no patterns found, say so explicitly — don't hallucinate past experience.

## Rules

- **Ask for clarification whenever you need it.** If the query is too broad, you're unsure what domain to search, or the results are ambiguous — ask. Don't guess.
