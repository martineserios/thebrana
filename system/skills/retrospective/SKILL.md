---
name: retrospective
description: Manually store a learning or pattern in the knowledge system
allowed-tools:
  - Bash
  - Read
  - Write
  - Glob
  - Grep
---

# Retrospective

1. If `$ARGUMENTS` is empty, ask what was learned. Otherwise, use `$ARGUMENTS` as the learning.

2. Structure the learning as a pattern:
   - `problem`: what was the issue or context
   - `solution`: what worked (or what didn't)
   - `tags`: project name, technology, problem type, outcome
   - `confidence`: 0.5 (quarantined — new learnings start unproven)
   - `transferable`: false (locked to source project until proven)

3. **Primary path (claude-flow available):**
   Store via `npx claude-flow hooks learn --patterns '{"problem": "...", "solution": "...", "tags": ["project:NAME", "tech:TECH", "type:CATEGORY", "outcome:success|failure|partial"], "confidence": 0.5, "transferable": false}'`

4. **Fallback path (claude-flow unavailable):**
   Append to `~/.claude/projects/{project-hash}/memory/MEMORY.md` in a structured format:
   ```
   ## Pattern: {title}
   - Problem: ...
   - Solution: ...
   - Tags: ...
   - Confidence: 0.5
   - Transferable: false
   - Date: {today}
   ```

5. Confirm what was stored and where.

### Tag Vocabulary

Use these prefixes consistently:
- `project:` — project name (e.g., `project:nexeye`, `project:brana`)
- `tech:` — technology (e.g., `tech:supabase`, `tech:nextjs`, `tech:python`)
- `type:` — problem category (e.g., `type:auth`, `type:deployment`, `type:testing`)
- `outcome:` — `outcome:success`, `outcome:failure`, or `outcome:partial`
