<!-- close phase: Steps 6-7: field notes + feature ideation (parallel block 2/3) — loaded per the PHASES registry in ../SKILL.md (t-1942) -->

<!-- ruflo preamble -->
ToolSearch("select:mcp__ruflo__memory_store")

### Step 6: Capture field notes

> Target check: field notes go to `docs/architecture/<topic>.md`, never `docs/reference/` (auto-generated, silently overwritten — see `system/rules/field-note-routing.md`).

Review the learnings extracted in Step 3 for **practical discoveries** — gotchas, workarounds, environment-specific behaviors, things that surprised you. These are candidates for field notes (persistent, doc-embedded knowledge per ADR-021).

**Choosing the right target — match scope to scope:**

Each file has a scope. Match the learning's scope to it:

| File | Scope | Use when the learning... |
|------|-------|--------------------------|
| `~/.claude/projects/{project}/memory/pattern_{slug}_{date}.md` | Cross-session pattern | Is a corrective, behavioral, or reusable pattern that passes the "different codebase?" filter — handled in Step 5b |
| `~/.claude/memory/knowledge-staging.md` | Cross-session knowledge | Is a system insight, architecture fact, or domain finding |
| `brana-knowledge/dimensions/{topic}.md` | Topic/domain | Applies wherever the same tool, language, or pattern appears — useful to any project, not just this one |
| `~/.claude/projects/{project}/memory/field-note_{slug}.md` | Repo-specific | Cannot be understood outside this codebase — requires knowing brana's hooks, bootstrap, CLI layout, or conventions to be useful |
| Archive-only (ruflo, Step 5) | Ephemeral | Already captured in Step 5, or duplicates existing MEMORY.md content |

**Heuristic:** Ask "Would this be useful to someone who has never seen this repo but knows the tool?" If yes → dimension doc. If no (the repo context is load-bearing) → `field-note_{slug}.md` in auto-memory.

**CLAUDE.md is Layer 1 — human-authored only. Never write to it from `/brana:close`.**

When writing a `field-note_{slug}.md`, add a one-liner to MEMORY.md under `## Field Notes`:
```
- [YYYY-MM-DD: {slug}](field-note_{slug}.md) — one-line description
```

**Skip if:** session was read-only (no commits), or no learnings were extracted.

**For each notable learning:**

1. Identify the most relevant doc (dimension, reflection, ADR, or feature brief) where this learning belongs. Use the learning's topic to match — e.g., a Docker gotcha → the infrastructure dimension, a hook behavior surprise → the architecture reflection.

2. Ask the user via AskUserQuestion. **Five-action lifecycle** (per t-440, replaces the older Keep/Archive binary):
   ```
   "Capture as field note? '{brief summary of learning}' → {target-doc-name}"
   Options:
     - label: "Promote (integrate into doc body)"
       description: "Integrate into doc prose; bump SemVer minor in frontmatter."
     - label: "Relate (cross-reference existing sections)"
       description: "Add bidirectional cross-reference links; no new content."
     - label: "Trigger (file research task)"
       description: "File a research task and link its ID from Field Notes."
     - label: "Contradict (flag assumption for review)"
       description: "Mark documented assumption as disputed for next reconcile."
     - label: "Keep (append to Field Notes section)"
       description: "Append to ## Field Notes section of the target doc."
     - label: "Archive (memory only, defer)"
       description: "Store in ruflo field-notes namespace only; no doc edit."
     - label: "Skip"
       description: "Discard silently — not worth recording."
   ```
   Batch up to 4 field notes per AskUserQuestion call. Pick at most 4 of these 7 options per question — the most plausible ones for the specific note. "Keep" stays available as the most common path; the other actions are lighter-weight when the note doesn't fit a tail section.

   **Choosing the action:**

   | Action | Use when | Result |
   |---|---|---|
   | **Promote** | Note has matured beyond gotcha — belongs in core narrative | Integrate into doc's relevant prose section; bump SemVer minor in frontmatter |
   | **Relate** | Note connects two existing pieces of knowledge | Add bidirectional cross-reference links; no new content |
   | **Trigger** | Note hints at a deeper unknown that warrants research | `brana backlog add --json '{"work_type":"research",...}'`; link task ID in Field Notes |
   | **Contradict** | Note conflicts with a documented assumption | Mark assumption `disputed`, reset `last_verified` to null; surfaces in next `/brana:reconcile` |
   | **Keep** | Note is a useful gotcha worth recording but doesn't shift the doc's structure | Append to `## Field Notes` section (default path) |
   | **Archive** | Note is real but not yet actionable | Store in ruflo `namespace: field-notes`, no doc edit |
   | **Skip** | Note is noise / duplicate | Discard silently |

3. **For "Promote" responses** — integrate into the doc body proper (not a tail section):
   - Locate the most relevant prose section using the note's topic
   - Add a 1-2 sentence integration with `(promoted YYYY-MM-DD from session)` attribution
   - Bump the doc's SemVer minor in frontmatter (`version: X.Y.0` → `X.(Y+1).0`)
   - Skip the Keep-style append below

4. **For "Relate" responses** — add bidirectional cross-references:
   - Identify the related doc/section via the note's topic
   - In the source doc, add: `> See also: [target-section](target-path#anchor) — {one-line relation}`
   - In the target doc, add the reverse pointer
   - Skip the Keep-style append below

5. **For "Trigger" responses** — create a research task:
   ```bash
   brana backlog add --json '{"subject":"Research: {topic}","work_type":"research","type":"task","tags":["follow-up","field-note-trigger"],"effort":"S","context":"Triggered from field note in {source-doc}: {note}"}'
   ```
   Then append a Field Notes entry that links the task ID:
   ```
   ### YYYY-MM-DD: [brief title] [→ research t-NNN]
   ```

6. **For "Contradict" responses** — flag the conflicting assumption:
   - Find the assumption in the source doc's frontmatter `assumptions:` block (or in any doc the user identifies)
   - Set its `status: disputed` and `last_verified: null`
   - Append a Field Note prefixed `[CONTRADICTS assumption-id]` with the contradicting evidence
   - Next `/brana:reconcile` run surfaces this for review

7. **For "Keep" responses** — append to the target doc's `## Field Notes` section:
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

8. **For "Archive" responses** — store in ruflo only:

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

9. **For "Skip" responses** — discard silently.

10. **Reindex affected docs** — after all field notes are processed, trigger ruflo reindex for each modified doc:

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
       - label: "[component] brief description"
         description: "Add this idea to the backlog with component tag and description."
       - label: "Skip all"
         description: "Discard all feature ideas from this session."
   ```

4. **For each selected idea**, add via CLI:
   ```bash
   brana backlog add --json '{"subject":"[component] description","work_type":"implement","type":"task","tags":["ideation","component"],"effort":"S"}'
   ```
   Report created task IDs inline.

**Track ideation count** for the session report: `{N} ideas found, {M} added to backlog`.

