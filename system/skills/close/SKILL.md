---
name: close
description: "End a session — extract learnings, write handoff note, store patterns, detect doc drift. Absorbs /session-handoff close mode and /debrief. Use when ending a work session or when the user says done/bye/closing."
group: session
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Glob
  - Grep
  - AskUserQuestion
  - Agent
  - Task
---

# Close — Session End

End a work session. Extracts what was learned, writes a handoff note for the next session, stores patterns, and detects doc drift. Replaces `/session-handoff` close mode and `/debrief`.

## When to use

- User says "done", "bye", "closing", "that's it", or similar
- End of a long implementation session
- Before switching to a different project
- Explicitly: `/brana:close`

## Step Registry

On entry, create a CC Task step registry. Follow the [guided-execution protocol](../_shared/guided-execution.md).

Register these steps: GATE, GATHER, EXTRACT, ERRATA, PATTERNS, FIELD-NOTES, DRIFT, HANDOFF, METADATA, REPORT.

## Steps

### Step 1: Gate check

Assess what happened this session:

```bash
git diff --stat HEAD~5..HEAD 2>/dev/null
git log --oneline --since="6 hours ago" 2>/dev/null
```

**If both empty** (no commits, no changes in 6 hours):
- Write a minimal handoff entry: `## YYYY-MM-DD — read-only session`
- Add only a **Next:** section from conversation context
- Skip to Step 8 (Write handoff note)

### Step 2: Gather evidence

Collect from multiple sources:

1. **Git log + diffs:**
   ```bash
   git log --oneline --since="6 hours ago" 2>/dev/null
   git diff --stat HEAD~5..HEAD 2>/dev/null
   ```
2. **Conversation context** — review for: errors hit, workarounds used, surprises, things that didn't match expectations
3. **If `$ARGUMENTS` provided** — use as focus hint (e.g., `/brana:close hooks` focuses on hook-related findings)

### Step 3: Extract and classify findings

Spawn the `debrief-analyst` agent:

```
Agent(subagent_type="debrief-analyst", prompt="Debrief this session. Focus on: what was built, any errata or spec mismatches found, process learnings. Check git log and conversation context.")
```

If the agent is unavailable, do a manual scan:
1. `git log --oneline -10` — list what was committed
2. Review conversation for: errors, workarounds, surprises
3. Classify into the three buckets below

**Classification buckets:**

| Bucket | What it is | Example |
|--------|-----------|---------|
| **Errata** | Spec says X, reality is Y | "Spec says `hooks recall`, actual API is `memory search`" |
| **Learning** | Reusable insight about how to work | "DB schema drift breaks things silently" |
| **Issue** | Something broken, not a spec mismatch | "Deploy script doesn't handle symlinks" |

### Step 4: Write errata entries (if any)

For each **errata** finding:

1. Find the errata doc: `Glob("**/*correction*")` or `Glob("**/*errata*")`
2. If found, read it for format and current error count
3. If not found, use `~/enter_thebrana/thebrana/docs/24-roadmap-corrections.md`
4. Append entries following the existing format:
   - Sequential error number
   - Title, severity (High/Medium/Low), discovery, affected files, fix
5. Add to severity summary table

**Status rules — close only logs, never resolves:**

| Finding | Status | Who resolves |
|---------|--------|-------------|
| Spec mismatch (needs doc edits) | `pending` | `/brana:maintain-specs` |
| Code bug (fixed this session) | `code-fix` | Already done |
| Code bug (not fixed) | `pending` | Next session |

### Step 5: Store learnings as patterns

For each learning from Step 3, store via ruflo:

```bash
source /home/martineserios/.claude/scripts/cf-env.sh

cd "$HOME" && $CF memory store \
  -k "pattern:{PROJECT}:{short-title}" \
  -v '{"problem": "...", "solution": "...", "confidence": 0.5, "transferable": false, "correction_weight": 0}' \
  --namespace patterns \
  --tags "client:{PROJECT},type:{CATEGORY},outcome:{OUTCOME}" \
  --upsert
```

If ruflo is unavailable, append to the project's auto memory `MEMORY.md` under `~/.claude/projects/`.

**Skip if:** session was read-only (no commits), or debrief returned no learnings.

### Step 6: Capture field notes

Review the learnings extracted in Step 3 for **practical discoveries** — gotchas, workarounds, environment-specific behaviors, things that surprised you. These are candidates for field notes (persistent, doc-embedded knowledge per ADR-021).

**Skip if:** session was read-only (no commits), or no learnings were extracted.

**For each notable learning:**

1. Identify the most relevant doc (dimension, reflection, ADR, or feature brief) where this learning belongs. Use the learning's topic to match — e.g., a Docker gotcha → the infrastructure dimension, a hook behavior surprise → the architecture reflection.

2. Ask the user via AskUserQuestion:
   ```
   "Capture as field note? '{brief summary of learning}' → {target-doc-name}"
   Options: ["Keep (append to doc)", "Archive (store in memory only)", "Skip"]
   ```
   Batch up to 4 field notes per AskUserQuestion call.

3. **For "Keep" responses** — append to the target doc's `## Field Notes` section:
   - If the section doesn't exist, create it at the end of the doc (before any trailing `---`)
   - Format:
     ```markdown
     ### YYYY-MM-DD: [brief title]
     [1-2 line description of the practical learning]
     Source: [session context / task ID]
     ```
   - **Cap: 20 field notes per doc.** Before appending, count existing `###` entries under `## Field Notes`. If 20+, prompt via AskUserQuestion:
     ```
     "This doc has 20+ field notes. Oldest unactioned notes should be archived. Archive oldest 5?"
     Options: ["Yes — archive oldest 5", "No — append anyway", "Skip this note"]
     ```
     If archiving: move the oldest 5 entries to ruflo (`namespace: field-notes`, tag `archived`) and remove them from the doc.

4. **For "Archive" responses** — store in ruflo only:
   ```bash
   source /home/martineserios/.claude/scripts/cf-env.sh

   cd "$HOME" && $CF memory store \
     -k "field-note:{PROJECT}:{YYYY-MM-DD}:{short-slug}" \
     -v '{"note": "...", "source_doc": "...", "session": "YYYY-MM-DD", "action": "archived"}' \
     --namespace field-notes \
     --tags "client:{PROJECT},type:field-note,status:archived" \
     --upsert
   ```
   If ruflo unavailable, append to MEMORY.md under `## Field Notes (Archived)`.

5. **For "Skip" responses** — discard silently.

6. **Reindex affected docs** — after all field notes are appended, trigger ruflo reindex for each modified doc:
   ```bash
   source /home/martineserios/.claude/scripts/cf-env.sh

   cd "$HOME" && $CF memory store \
     -k "knowledge:{doc-relative-path}" \
     -v "$(cat {absolute-doc-path})" \
     --namespace knowledge \
     --tags "type:dimension,reindexed:$(date +%Y-%m-%d)" \
     --upsert
   ```
   If ruflo unavailable, skip reindex silently.

**Track field note count** for the session report in Step 10: `{N} kept, {M} archived, {P} skipped`.

### Step 7: Detect doc drift

Check if system files were modified this session:

```bash
# Preferred: use brana CLI if available
uv run brana ops drift 2>/dev/null || \
git diff --name-only HEAD~10..HEAD 2>/dev/null | grep -E '(skills/|agents/|hooks/|rules/|commands/|CLAUDE\.md|settings\.json|deploy\.sh)'
```

**Graph-aware detection:** If `docs/spec-graph.json` exists and system files were changed, query the graph to find which specific docs are affected:

```bash
# For each changed system file, find docs that reference it
jq --arg f "system/skills/build/SKILL.md" '.nodes | to_entries[] | select(.value.impl_files | index($f)) | .key' docs/spec-graph.json
```

Include the affected doc list in the drift report instead of just "system files changed." If the graph doesn't exist, fall back to the generic message.

- **If matches found:** flag in handoff note and write a marker file:
  ```bash
  MEMORY_DIR=$(find ~/.claude/projects/ -maxdepth 2 -name "MEMORY.md" -path "*$(basename $(git rev-parse --show-toplevel))*" -exec dirname {} \; 2>/dev/null | head -1)
  [ -n "$MEMORY_DIR" ] && echo "$(date +%Y-%m-%d) $(git diff --name-only HEAD~10..HEAD 2>/dev/null | grep -E '(skills/|agents/|hooks/|rules/|commands/)' | tr '\n' ',')" > "$MEMORY_DIR/.needs-backprop"
  ```
- **If no matches:** skip silently

#### Feature doc staleness check

After detecting system-level drift, also check if session changes affect existing feature docs:

1. **Get changed implementation files** from this session:
   ```bash
   git diff --name-only HEAD~10..HEAD 2>/dev/null | grep -E '\.(ts|js|py|sh|json)$'
   ```

2. **Scan feature docs** in `docs/architecture/features/` and `docs/guide/features/`:
   - For each feature doc, check the **Key Files** table (tech doc) or content references
   - If any changed implementation file appears in a feature doc's Key Files or is referenced by path, that doc is **potentially stale**

3. **Report stale docs:**
   - List them in the handoff note under a `**Stale feature docs:**` section
   - Append to `.needs-backprop` marker: `docs-stale: {doc1.md}, {doc2.md}`
   - Suggest: "Review these docs next session or run `/brana:reconcile`"

4. **Skip if:** no feature docs exist yet, or no implementation files changed

### Step 8: Write handoff note

Find `session-handoff.md` in `~/.claude/projects/` for the current project. Append:

```markdown
## YYYY-MM-DD — <brief label>

**Accomplished:**
- {from git log + conversation context}

**Learnings:**
- {from Step 3 classified findings}

**State:**
- Branch: {current branch}
- Key files touched: {from git diff --stat}
- Tests: passing / failing / N/A

**Doc drift:**
- {system files changed, or "None"}

**Next:**
- {follow-up actions, deferred items}
- {if errata found: "Run /brana:maintain-specs"}
- {if doc drift: "Consider updating specs"}

**Blockers:**
- ... (or "None")
```

**Rules for the handoff file:**
- Always append — never delete or overwrite previous sections
- Same date, multiple sessions: use `## YYYY-MM-DD (2) — label`
- Keep each section concise — 15 lines max
- Trim old sections if file exceeds ~200 lines: collapse entries older than 30 days into an `## Archive (before YYYY-MM-DD)` summary

### Step 9: Store session metadata

```bash
source /home/martineserios/.claude/scripts/cf-env.sh

cd "$HOME" && $CF memory store \
  -k "session:{PROJECT}:{YYYY-MM-DD}" \
  -v '{"type": "session-close", "date": "{YYYY-MM-DD}", "commits": N, "learnings": N, "errata": N, "drift": true|false}' \
  --namespace patterns \
  --tags "client:{PROJECT},type:session-close" \
  --upsert
```

If ruflo unavailable, skip — the handoff note is the fallback.

Then backup:

```bash
# CLI alias: bbackup (or source system/cli/aliases.sh)
"$HOME/.claude/scripts/backup-knowledge.sh" 2>/dev/null || true
```

### Step 10: Memory review

Read the project's auto memory (`MEMORY.md`) and audit each entry:

1. **Read** `~/.claude/projects/{project-slug}/memory/MEMORY.md`
2. **For each entry**, classify:
   - **Keep** — still relevant to this project, not yet implemented
   - **Delete** — client-specific (belongs in that client's memory), outdated, or the described feature/fix has been implemented
   - **Feature idea** — the entry describes a gap, wish, or improvement that could become a task
3. **Delete stale entries** — remove lines that are no longer relevant
4. **Extract feature ideas** — for each feature idea found:
   - Search existing tasks: `brana backlog query --search "keyword" --count`
   - If already exists (count > 0): delete the memory entry (it's tracked)
   - If new: `brana backlog add --json '{"subject":"...","stream":"...","type":"task"}'` then delete the memory entry
5. **Report** feature ideas extracted and entries cleaned in the session report

**Skip if:** session was read-only, or MEMORY.md has fewer than 10 entries.

### Step 11: Report

```markdown
## Session Close

**Commits this session:** {N}
**Learnings extracted:** {N} ({errata} errata, {learnings} learnings, {issues} issues)
**Field notes:** {N kept} kept, {M archived} archived, {P skipped} skipped
**Patterns stored:** {N}
**Memory reviewed:** {N entries deleted}, {M feature ideas extracted}
**Doc drift detected:** {yes/no}
**Handoff note updated:** {path}

### Follow-up
- {if errata: "/brana:maintain-specs to propagate findings"}
- {if drift: "Specs may need updating for changed system files"}
- {if issues: "Issues logged for next session"}
- {if field notes kept: "Docs updated with field notes: {list of docs}"}
- {if features extracted: "New tasks from memory: {list of task IDs}"}
```

---

## Rules

1. **Extract from evidence, don't invent.** Every finding traces to something that happened — a command that failed, a mismatch observed, a workaround applied.
2. **Learnings must be actionable.** Each contains a concrete rule someone can follow. If you can't state it as a rule, it's not a learning yet.
3. **Don't duplicate.** Read existing errata before adding. If already documented, skip or note confirmation.
4. **Gate on changes.** Read-only sessions get a one-line handoff and no debrief.
5. **Don't block on failures.** Agent fails → manual scan. Claude-flow fails → handoff note is the fallback. Backup fails → skip.
6. **Suggest, don't execute.** Doc drift → suggest updating specs. Errata → suggest `/brana:maintain-specs`. Let the user decide when.
7. **Be specific.** "The API was wrong" is useless. "Spec says `hooks recall`, actual is `memory search`" is useful.
8. **Ask for clarification when needed.** Ambiguous findings → ask. Don't guess classifications.
9. **Step registry.** Follow the [guided-execution protocol](../_shared/guided-execution.md). Register steps on entry, update as each completes.

---

## Resume After Compression

If context was compressed and you've lost track of progress:

1. Call `TaskList` — find CC Tasks matching `/brana:close — {STEP}`
2. The `in_progress` task is your current step — resume from there
3. Check git log and handoff file for what was already accomplished
