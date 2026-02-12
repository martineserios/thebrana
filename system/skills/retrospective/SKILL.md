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
   Locate the binary:
   ```bash
   CF=""
   for candidate in "$HOME"/.nvm/versions/node/*/bin/claude-flow; do
       [ -x "$candidate" ] && CF="$candidate" && break
   done
   [ -z "$CF" ] && command -v claude-flow &>/dev/null && CF="claude-flow"
   [ -z "$CF" ] && command -v npx &>/dev/null && CF="npx claude-flow"
   ```
   Store via `cd $HOME && $CF memory store -k "pattern:{PROJECT}:{short-title}" -v '{"problem": "...", "solution": "...", "confidence": 0.5, "transferable": false}' --namespace patterns --tags "project:NAME,tech:TECH,type:CATEGORY,outcome:success|failure|partial"`

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

6. **Review recalled patterns (promotion tracking):**

   After storing the new learning, review patterns that were recalled this session and evaluate whether they were useful.

   a. Search for existing patterns: `cd $HOME && $CF memory search --query "project:{PROJECT}" --limit 20`
   b. For each recalled pattern that **was useful** this session:
      - Retrieve: `cd $HOME && $CF memory search --query "{pattern-key}"`
      - Parse the JSON value, increment `recall_count` by 1
      - If `recall_count >= 3` → **promote**: set `confidence: 0.8`, `transferable: true`
      - Re-store with updated fields using the same key and tags
   c. For each recalled pattern that **was harmful or misleading** this session:
      - **Demote**: set `confidence: 0.1` (suspect), keep `transferable: false`
      - Re-store with updated fields
   d. Report what was promoted, demoted, or unchanged.

   **Skip this step** if no patterns were recalled this session or if the user wants to skip it.

### Tag Vocabulary

Use these prefixes consistently:
- `project:` — project name (e.g., `project:nexeye`, `project:brana`)
- `tech:` — technology (e.g., `tech:supabase`, `tech:nextjs`, `tech:python`)
- `type:` — problem category (e.g., `type:auth`, `type:deployment`, `type:testing`)
- `outcome:` — `outcome:success`, `outcome:failure`, or `outcome:partial`

### Step 7: Backup knowledge

After storing patterns, back up the knowledge artifacts:

```bash
BACKUP_SCRIPT="$HOME/enter_thebrana/brana-knowledge/backup.sh"
[ -x "$BACKUP_SCRIPT" ] && "$BACKUP_SCRIPT"
```

Skip silently if the script doesn't exist.

### Rules

- **Ask for clarification whenever you need it.** If the learning is ambiguous, you're unsure how to tag it, or you need more context — ask. Don't guess.
