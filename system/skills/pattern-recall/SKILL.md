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
   Run `cd $HOME && npx claude-flow memory search -q "$ARGUMENTS"` to search the memory DB for matching patterns. Parse and present results grouped by confidence level.

3. **Fallback path (claude-flow unavailable):**
   Search `~/.claude/projects/*/memory/` for relevant MEMORY.md files. Grep for keywords from the query. Present findings.

4. For each recalled pattern, show:
   - Pattern description
   - Confidence score
   - Source project
   - Whether it's transferable

5. If no patterns found, say so explicitly — don't hallucinate past experience.
