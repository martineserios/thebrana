
# Close — Session End

End a work session. Extracts what was learned, writes a handoff note for the next session, stores patterns, and detects doc drift. Replaces `/session-handoff` close mode and `/debrief`.

## When to use

- User says "done", "bye", "closing", "that's it", or similar
- End of a long implementation session
- Before switching to a different project
- Explicitly: `/brana:close`

## Step Registry

On entry, create a CC Task step registry. Follow the [guided-execution protocol](../_shared/guided-execution.md).

Register these steps: GATE, GATHER, EXTRACT, DOC-CHECK, ERRATA, PATTERNS, FIELD-NOTES, IDEATE, DRIFT, HANDOFF, RUFLO-SYNC, METADATA, MEMORY-REVIEW, REPORT.

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
- Skip to Step 9 (Write handoff note)

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

### Step 3b: Doc-update check

Detect behavioral changes that lack corresponding documentation updates.

**Skip if:** session was read-only (no commits).

1. **Get files changed this session:**
   ```bash
   git diff --name-only HEAD~10..HEAD 2>/dev/null
   ```

2. **Classify changed files:**

   | Category | Glob patterns |
   |----------|--------------|
   | **Behavioral** | `system/skills/**`, `system/hooks/**`, `system/agents/**`, `system/commands/**`, `system/cli/**`, `**/rules/**` |
   | **Documentation** | `docs/architecture/**`, `docs/guide/**`, `docs/reference/**`, `*CLAUDE.md` |

   Walk the changed file list and tag each matching file as `behavioral` or `documentation`. Files matching neither are ignored.

3. **If behavioral files changed but NO documentation files changed**, prompt:

   Build a mapping of each behavioral file to its most likely doc target. Use these heuristics:
   - `system/skills/{name}/SKILL.md` → `docs/architecture/skills.md`
   - `system/hooks/**` → `docs/architecture/hooks.md`
   - `system/agents/**` → `docs/architecture/agents.md`
   - `system/commands/**` → `docs/architecture/commands.md`
   - `system/cli/**` → `docs/architecture/cli.md` or `docs/guide/cli-reference.md`
   - `**/rules/**` → `docs/architecture/rules.md`

   Present via AskUserQuestion:
   ```
   AskUserQuestion:
     question: "Behavioral files changed without docs. Update now?"
     header: "Doc-update check"
     options:
       - "Draft doc updates now"
       - "Add to session handoff (defer)"
       - "Skip"
     context: |
       Changed behavioral files:
       - {file} → {suggested doc target}
       ...
   ```

   **If "Draft doc updates now":**
   - For each behavioral file, read it and draft a concise doc update suggestion
   - Present the drafted updates for approval before writing
   - Write approved updates via Edit

   **If "Add to session handoff (defer)":**
   - Add an entry to the session state `next` array (Step 9) with `category: "maintenance"`:
     ```json
     {"text": "Doc update needed: {behavioral file} → {doc target}", "task_id": null, "category": "maintenance"}
     ```

   **If "Skip":** continue to Step 4.

4. **If both behavioral AND documentation files changed**, or no behavioral files changed, skip silently.

5. **Track metrics** for session state (Step 9):
   - `behavioral_files_changed`: count of behavioral files in the diff
   - `doc_files_changed`: count of documentation files in the diff
   - `doc_prompts_accepted`: 1 if "Draft now", 0 otherwise
   - `doc_prompts_skipped`: 1 if "Skip", 0 otherwise

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

For each learning from Step 3, store via ruflo MCP (preferred) or CLI (fallback):

**Via MCP (preferred — durable, HNSW-indexed):**

```
mcp__ruflo__memory_store(
  key: "pattern:{PROJECT}:{short-title}",
  value: '{"problem": "...", "solution": "...", "confidence": 0.5, "transferable": false, "correction_weight": 0}',
  namespace: "pattern",
  tags: ["client:{PROJECT}", "type:{CATEGORY}", "outcome:{OUTCOME}", "tier:episodic"],
  upsert: true
)
```

**Fallback (CLI):**

```bash
source "$HOME/.claude/scripts/cf-env.sh"

cd "$HOME" && $CF memory store \
  -k "pattern:{PROJECT}:{short-title}" \
  -v '{"problem": "...", "solution": "...", "confidence": 0.5, "transferable": false, "correction_weight": 0}' \
  --namespace pattern \
  --tags "client:{PROJECT},type:{CATEGORY},outcome:{OUTCOME}" \
  --upsert
```

If both MCP and CLI are unavailable, the git file (below) is the sole durable copy.

**Step 5b: Write pattern as git-durable file (always — regardless of MCP/CLI success)**

For each learning, also write an individual frontmatter markdown file to the project's
auto memory directory (`~/.claude/projects/{project-dir}/memory/`). This makes git the
durable source of truth and enables the pattern indexer to rebuild ruflo from files.

**Slug:** derive from `{short-title}` — lowercase, hyphens, no special chars.
**Category prefix:** `feedback_` for corrections/gotchas, `project_` for architectural state.

```markdown
---
name: {short-title}
description: {one-line problem summary — used for index matching}
type: {feedback or project}
---

**Problem:** {problem}
**Solution:** {solution}
**Confidence:** {0.5 for new, higher if validated}
**Transferable:** {true if applicable across clients}
```

Write via the Write tool to `~/.claude/projects/{project-dir}/memory/{prefix}_{slug}.md`.

If the file already exists (pattern was previously saved), **update it** via Edit — don't
create duplicates. Use Glob to check: `Glob("~/.claude/projects/*/memory/*{slug}*")`.

After writing the file, add a one-line pointer to the project's `MEMORY.md` if one doesn't
exist for this pattern. Follow the existing MEMORY.md format.

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

   **Via MCP (preferred):**
   ```
   mcp__ruflo__memory_store(
     key: "field-note:{PROJECT}:{YYYY-MM-DD}:{short-slug}",
     value: '{"note": "...", "source_doc": "...", "session": "YYYY-MM-DD", "action": "archived"}',
     namespace: "field-notes",
     tags: ["client:{PROJECT}", "type:field-note", "status:archived", "tier:episodic"],
     upsert: true
   )
   ```

   **Fallback (CLI):**
   ```bash
   source "$HOME/.claude/scripts/cf-env.sh"

   cd "$HOME" && $CF memory store \
     -k "field-note:{PROJECT}:{YYYY-MM-DD}:{short-slug}" \
     -v '{"note": "...", "source_doc": "...", "session": "YYYY-MM-DD", "action": "archived"}' \
     --namespace field-notes \
     --tags "client:{PROJECT},type:field-note,status:archived" \
     --upsert
   ```
   If both unavailable, append to MEMORY.md under `## Field Notes (Archived)`.

5. **For "Skip" responses** — discard silently.

6. **Reindex affected docs** — after all field notes are appended, trigger ruflo reindex for each modified doc:

   **Via MCP (preferred):**
   ```
   mcp__ruflo__memory_store(
     key: "knowledge:{doc-relative-path}",
     value: "<full doc content>",
     namespace: "knowledge",
     tags: ["type:dimension", "reindexed:{YYYY-MM-DD}"],
     upsert: true
   )
   ```

   **Fallback (CLI):**
   ```bash
   source "$HOME/.claude/scripts/cf-env.sh"

   cd "$HOME" && $CF memory store \
     -k "knowledge:{doc-relative-path}" \
     -v "$(cat {absolute-doc-path})" \
     --namespace knowledge \
     --tags "type:dimension,reindexed:$(date +%Y-%m-%d)" \
     --upsert
   ```
   If both unavailable, skip reindex silently.

**Track field note count** for the session report in Step 10: `{N} kept, {M} archived, {P} skipped`.

### Step 7: Feature ideation

Scan the session for feature ideas — new CLI commands, hook improvements, skill enhancements, system architecture changes, rule additions, scheduler jobs, or agent behaviors that came up during the work but weren't implemented.

**Skip if:** session was read-only (no commits), or no feature ideas surfaced.

1. **Mine ideas from session context:**
   - Review conversation for phrases like "it would be nice if", "we should add", "this could be a hook/skill/command", unresolved pain points, manual steps that could be automated
   - Check git diffs for TODO/FIXME/HACK comments added this session
   - Each idea gets a one-line description and a component tag

2. **Classify by component:**

   | Component | Examples |
   |-----------|---------|
   | `cli` | New subcommand, flag, output format |
   | `hook` | New gate, validation, auto-trigger |
   | `skill` | New workflow, skill enhancement |
   | `agent` | New agent type, delegation change |
   | `rule` | New behavioral rule, rule refinement |
   | `scheduler` | New scheduled job, cron change |

3. **Offer for backlog addition** via AskUserQuestion (multiSelect):
   ```
   AskUserQuestion:
     question: "Add these feature ideas to the backlog?"
     header: "Feature ideas from this session"
     multiSelect: true
     options:
       - "[component] brief description" — one per idea
       - "Skip all"
   ```

4. **For each selected idea**, add via CLI:
   ```bash
   brana backlog add --json '{"subject":"[component] description","stream":"roadmap","type":"task","tags":["ideation","component"],"effort":"S"}'
   ```
   Report created task IDs inline.

**Track ideation count** for the session report: `{N} ideas found, {M} added to backlog`.

### Step 8: Detect doc drift

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

Collect drift results for the session state JSON (Step 9):
- **backprop.files**: system files that changed this session
- **doc_drift.stale_docs**: docs affected by those changes (from spec-graph)

**Do NOT write `.needs-backprop` flag file.** The `backprop` field in session-state.json replaces it.

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
   - Add stale feature docs to the `doc_drift.stale_docs` list in the session JSON
   - Offer via AskUserQuestion: "Stale feature docs detected: {list}. Run /brana:reconcile now?"
     Options: ["Yes — run reconcile", "Skip — defer to next session"]
     If yes: invoke `Skill(skill="brana:reconcile")`. If no: include in session state only.

4. **Skip if:** no feature docs exist yet, or no implementation files changed

#### Auto-trigger /reconcile

If system files were changed this session AND the project is brana (git root basename is "thebrana"):

1. Check if behavioral files include any of: `system/skills/`, `system/hooks/`, `system/agents/`, `system/commands/`, `system/cli/`, `**/rules/`
2. If yes, auto-invoke reconcile:
   ```
   Skill(skill="brana:reconcile", args="--scope consistency,propagation")
   ```
3. Record in session state: `"auto_reconcile": {"triggered": true, "scope": "consistency,propagation", "reason": "system files changed"}`
4. If reconcile finds issues, include them in the session report (Step 12)

**Skip if:**
- No system files changed this session
- Not in thebrana project (other projects don't have /reconcile)
- User already ran /reconcile manually this session (check conversation context)

#### Knowledge reindex

After drift detection, batch-reindex any changed docs into ruflo so the knowledge base stays current. One reindex per session replaces per-commit hooks.

```bash
brana knowledge reindex --changed 2>/dev/null || true
```

**Skip if:** no docs changed this session (git diff shows no `docs/`, `brana-knowledge/`, or `system/procedures/` changes), or ruflo is unavailable.

### Step 9: Write session state via CLI

Build a JSON object from all evidence gathered in previous steps, write it to a temp file, and call `brana session write`. The LLM never writes session files directly — the CLI validates the schema and handles atomic writes + history archival.

**Build the JSON payload:**

```json
{
  "version": 1,
  "written_at": "",
  "session_label": "<brief label from conversation context>",
  "accomplished": ["<from git log + conversation>"],
  "learnings": ["<from Step 3 classified findings>"],
  "next": [
    {"text": "<follow-up action>", "task_id": "t-NNN or null", "category": "follow-up|maintenance|suggestion"}
  ],
  "blockers": [
    {"text": "<blocker description>", "task_id": "t-NNN or null"}
  ],
  "backprop": {
    "needed": true,
    "files": ["<system files changed, from Step 8>"]
  },
  "doc_drift": {
    "detected": true,
    "stale_docs": ["<docs affected, from Step 8>"]
  },
  "auto_reconcile": {
    "triggered": false,
    "scope": null,
    "reason": null,
    "issues_found": 0
  },
  "state": {
    "key_files": ["<from git diff --stat>"],
    "test_status": {"passing": 0, "failing": 0}
  },
  "metrics": {
    "events": 0, "corrections": 0, "test_writes": 0,
    "correction_rate": 0.0, "test_write_rate": 0.0,
    "cascade_rate": 0.0, "delegation_count": 0,
    "behavioral_files_changed": 0, "doc_files_changed": 0,
    "doc_prompts_accepted": 0, "doc_prompts_skipped": 0
  }
}
```

**Populate the `metrics` field** from the session JSONL telemetry:
```bash
SESSION_FILE="/tmp/brana-session-${SESSION_ID}.jsonl"
if [ -f "$SESSION_FILE" ]; then
    brana ops metrics "$SESSION_FILE"
fi
```
Use the output to fill events, corrections, test_writes, correction_rate, test_write_rate, cascade_rate, delegation_count. If the session file doesn't exist or metrics fail, omit the metrics field (it's optional).

**Write via CLI:**

```bash
# Write JSON to temp file (avoids shell escaping issues)
cat > /tmp/session-close-$$.json << 'JSON'
{ ... the payload above ... }
JSON

# CLI validates schema, archives previous state, writes atomically
brana session write --file /tmp/session-close-$$.json

# Clean up
rm -f /tmp/session-close-$$.json
```

The CLI auto-fills `written_at` (if empty) and `branch` (from git). `consumed_at` is set to null — the next session-start marks it consumed.

**`next` category values** (validated enum):
- `follow-up` — action items from this session
- `maintenance` — routine tasks (run maintain-specs, reconcile, etc.)
- `suggestion` — non-urgent ideas worth considering

**Rules:**
- Write to temp file first, never pass JSON inline via shell arguments
- If `brana session write` fails, log error and continue — the session-end hook will capture a minimal fallback
- Do NOT write to `session-handoff.md` — it's deprecated (read-only archive)
- Do NOT write `.needs-backprop` — absorbed into the backprop field

### Step 9b: Ruflo MCP — session mirror + cross-session signals

> Additive — all 3 calls are best-effort. If MCP is unavailable, skip silently.
> Local session state (Step 9) is the primary record. This step adds searchability and cross-session awareness.

**Call 1: Session state to ruflo (searchable mirror)**

```
mcp__ruflo__memory_store(
  key: "session:{PROJECT}:{YYYY-MM-DD}T{HH:MM}",
  value: "<JSON string of the same payload written in Step 9>",
  namespace: "session",
  tags: ["client:{PROJECT}", "branch:{BRANCH}", "tier:episodic"],
  upsert: true
)
```

This makes session history semantically searchable: `memory_search(namespace: "session", query: "JWT auth")` finds past sessions by topic.

**Call 2: Cross-session close announcement (transient)**

```
mcp__ruflo__hive-mind_memory(
  action: "set",
  key: "client:{PROJECT}:session:closed:{YYYY-MM-DD}",
  value: {"status": "closed", "summary": "<1-line session label>", "next": ["<top 3 next items>"], "closed_at": "<ISO timestamp>"}
)
```

Other terminals see the session ended + what's next via `/brana:sitrep`. Transient (in-memory, lost on MCP restart) — OK for session announcements.

**Call 3: Task claim release (guarded)**

Only if an active task was being worked on this session:

```
# First check if any claims exist for this session
mcp__ruflo__claims_list(status: "active")
# Filter for claims matching current session ID
# For each matching claim:
mcp__ruflo__claims_release(
  issueId: "task:{active_task_id}",
  claimant: "session:{SESSION_ID}"
)
```

If no task was claimed, skip. If `claims_list` fails (MCP down), skip silently.

**Fallback:** If any MCP call fails, log the failure and continue. The CLI-based session state from Step 9 is the authoritative record. MCP failures are non-fatal.

### Step 10: Store session metadata

**Via MCP (preferred):**

```
mcp__ruflo__memory_store(
  key: "session-meta:{PROJECT}:{YYYY-MM-DD}",
  value: '{"type": "session-close", "date": "{YYYY-MM-DD}", "commits": N, "learnings": N, "errata": N, "drift": true|false}',
  namespace: "session",
  tags: ["client:{PROJECT}", "type:session-close"],
  upsert: true
)
```

**Fallback (CLI):**

```bash
source "$HOME/.claude/scripts/cf-env.sh"

cd "$HOME" && $CF memory store \
  -k "session:{PROJECT}:{YYYY-MM-DD}" \
  -v '{"type": "session-close", "date": "{YYYY-MM-DD}", "commits": N, "learnings": N, "errata": N, "drift": true|false}' \
  --namespace session \
  --tags "client:{PROJECT},type:session-close" \
  --upsert
```

If both MCP and CLI are unavailable, skip — the handoff note is the fallback.

Then backup:

```bash
# CLI alias: bbackup (or source system/cli/aliases.sh)
"$HOME/.claude/scripts/backup-knowledge.sh" 2>/dev/null || true
```

### Step 11: Memory review

Audit every entry in MEMORY.md using the **"Where to store what"** classification table from `self-improvement.md`.

1. **Read** `~/.claude/projects/{project-slug}/memory/MEMORY.md`
2. **For each entry**, classify using the full gate:

   | Classification | Action |
   |---------------|--------|
   | **Directive** ("always", "never", "must", "should") | Move to `rules/*.md` |
   | **Convention** (architecture, stack, domain terms) | Move to `CLAUDE.md` |
   | **Automation** (should trigger on events) | Flag for hook creation |
   | **Recipe** (multi-step reusable workflow) | Flag for skill creation |
   | **Log entry** (event that happened) | Move to `/brana:log` |
   | **Derivable** (obtainable via command or file read) | Delete |
   | **Historical** (completed, no future value) | Delete |
   | **Not project-specific** (applies across all projects) | Move to global `~/.claude/rules/` |
   | **Feature idea** (gap, wish, improvement) | Create task via `backlog_add()` (MCP) or `brana backlog add`, then delete |
   | **True memory** (external API, pointers, non-derivable context) | Keep |

3. **Execute moves** — for directives and conventions, create/update the target file and delete from MEMORY.md
4. **Feature ideas** — search existing tasks first: `backlog_search(query: "keyword")` (MCP) or `brana backlog search "keyword"`. If duplicate, just delete. If new, `backlog_add(subject: "...", stream: "...", task_type: "task")` (MCP) or `brana backlog add --json '{"subject":"...","stream":"...","type":"task"}'`
5. **Report** — entries moved, deleted, kept, and feature ideas extracted

**Skip if:** session was read-only, or MEMORY.md has fewer than 5 entries.

### Step 12: Report

```markdown
## Session Close

**Commits this session:** {N}
**Learnings extracted:** {N} ({errata} errata, {learnings} learnings, {issues} issues)
**Field notes:** {N kept} kept, {M archived} archived, {P skipped} skipped
**Patterns stored:** {N}
**Feature ideation:** {N ideas found}, {M added to backlog}
**Memory reviewed:** {N entries deleted}, {M feature ideas extracted}
**Doc drift detected:** {yes/no}
**Auto-reconcile:** {triggered (N issues) / skipped}
**Handoff note updated:** {path}

### Follow-up
- {if errata: "/brana:maintain-specs to propagate findings"}
- {if drift: "Specs may need updating for changed system files"}
- {if issues: "Issues logged for next session"}
- {if field notes kept: "Docs updated with field notes: {list of docs}"}
- {if features extracted: "New tasks from memory: {list of task IDs}"}
- {if ideation added: "Feature ideas added: {list of task IDs}"}
```

After presenting the report, **offer to create tasks from actionable follow-ups**.

Collect all follow-up items that are actionable (not just informational). Filter out items that already have tasks (e.g., "New tasks from memory" items were already created in Step 11, ideation items in Step 7). Present the remaining via AskUserQuestion (multiSelect: true):

```
AskUserQuestion:
  question: "Create tasks from these follow-ups?"
  header: "Follow-ups"
  multiSelect: true
  options:
    - one per actionable follow-up: "{follow-up description}" → creates a task via brana backlog add
    - "Skip all"
```

For each selected follow-up:
- Run `brana backlog add --json '{"subject":"{follow-up}","stream":"tech-debt","type":"task","tags":["{relevant tags}"],"effort":"S"}'`
- Report the created task ID inline

**Skip the offer if:** no actionable follow-ups exist (all items are informational or already have tasks).

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
