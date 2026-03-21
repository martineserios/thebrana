---
name: maintain-specs
description: "Run the full spec repo correction cycle: apply errata, re-evaluate reflections, deepen synthesis, and check doc hygiene"
effort: high
---

# Maintain Specs

Run the full spec repo correction cycle: apply pending errata first (so reflections start from a corrected baseline), then re-evaluate reflection docs against dimension docs, deepen the reflection layer, and check if doc 25 needs updating. Each step exits early if nothing needs doing.

**Progressive refinement — roadmaps must be as detailed as possible.** Each cycle doesn't just fix errors — it's an opportunity to deepen roadmap precision. As dimension and reflection docs get corrected, they unlock more specific implementation detail. When applying errata to roadmap docs, always add precision: exact file paths, step-by-step logic, specific test cases, every branch in the code. A precise roadmap ensures near-perfect implementation. Over repeated cycles, the roadmap converges toward something directly implementable with minimal interpretation.

This does NOT include `/refresh-knowledge` (web search for external updates). Run that separately first if dimension docs might be stale relative to the outside world.

## Step Registry

On entry, create a CC Task step registry. Follow the [guided-execution protocol](../_shared/guided-execution.md).

Register these steps: ERRATA, RE-EVALUATE, DEEPEN, DOC25, MEMORY, BACKLOG, LOG, STORE, BACKUP, GRAPH.

### Resume After Compression

If context was compressed:
1. Call `TaskList` — find CC Tasks matching `/brana:maintain-specs — {STEP}`
2. The `in_progress` task is your current step — resume from there

## Step 1: Apply errata

Run `/brana:apply-errata`. Apply known fixes first so that reflection docs start from a corrected baseline before cross-checking. It handles the full layer-aware cycle: classify → dimension fixes → gate check → reflection fixes → gate check → roadmap fixes → update doc 24.

If no pending errata → it will report "No pending errata" and this step is done.

## Step 2: Re-evaluate reflections

**Graph-scoped evaluation:** If `docs/spec-graph.json` exists and a specific doc was changed in Step 1, read its `referenced_by` list from the graph. Only re-evaluate those 1-hop neighbors instead of all 5 reflections. This focuses the evaluation on docs actually affected by the change.

**Fallback:** If `docs/spec-graph.json` doesn't exist, or if the changed doc isn't in the graph, re-evaluate all 5 reflection docs (current behavior).

Run `/brana:re-evaluate-reflections`. It cross-checks reflection docs against the dimension docs they depend on and logs any new gaps as doc 24 errata entries.

If no gaps found → report "Reflections current" and skip to Step 3.

## Step 2b: Review significant findings (optional)

If Step 2 found significant cascade findings (HIGH severity or multiple related findings), optionally spawn the `challenger` agent to review them before applying. Pass it the findings list and relevant doc context. This catches false positives before they propagate through the spec layer.

If the challenger raises concerns, discuss with the user before applying.

## Step 3: Deepen reflections

After correcting and cross-checking (steps 1-2), try to **improve** the reflection layer. Every cycle is an opportunity — dimension docs evolve, new learnings get stored, errata reveal patterns. The reflections should get sharper each pass.

**This is improvement, not correction.** Step 2 catches errors. This step deepens synthesis.

For each reflection doc, check:

1. **New synthesis opportunities.** Did recent dimension doc changes, applied errata, or stored patterns unlock cross-doc interactions that the reflection doesn't capture yet? Example: a testing insight (doc 22) + a knowledge health finding (doc 16) might together reveal a quality pattern that neither doc contains alone.

2. **Sharper abstractions.** Can any reflection section be more precise? Vague synthesis ("these tools work well together") should converge toward specific claims ("claude-flow's memory namespace maps 1:1 to the skill routing table, enabling...").

3. **Coverage gaps from new content.** If dimension docs were added or significantly expanded since the reflection was last updated, check whether the reflection's synthesis still holds or needs to incorporate the new material.

4. **Cross-reflection coherence.** Do the reflections tell a consistent story? R1's triage decisions should align with R2's architecture choices. R3's quality framework should test what R2 specifies. Flag inconsistencies between reflections, not just between dimensions and reflections.

**Follow the reflection DAG when improving:**
```
R1 (08 Triage) → R2 (14 Architecture) → R3 (31 Assurance) / R4 (32 Lifecycle) → R5 (29 Transfer)
```
Improvements cascade downward — a sharper triage decision in R1 may unlock a more precise architecture in R2.

**Materiality test applies here too.** Only suggest improvements that would deepen understanding or change an implementation decision. Don't force polish where the reflection is already clear enough.

If nothing to improve → report "Reflections already sharp."
If improvements found → apply them directly (these are enhancements, not errata — no doc 24 entry needed). Report what was deepened.

## Step 4: Check doc 25

Read doc 25 (self-documentation). Check whether this run changed anything that doc 25 should reflect:

- Did the command workflow change?
- Were new error patterns discovered that the Maintenance Commands section should document?
- Are the command descriptions still accurate?
- Are the layer thresholds or dependency descriptions still correct?

If doc 25 is current → report "Doc 25 current."
If something needs updating → flag the specific sections and suggest edits.

## Step 5: Memory hygiene

Keep project MEMORY.md files current with the latest skill commands and project state.

1. **Check the skill commands table.** Read the "Skill commands — when to suggest each" section in MEMORY.md (for every project memory dir that exists: `~/.claude/projects/*/memory/MEMORY.md`). If the table is missing, outdated, or doesn't match the current skills in `~/.claude/skills/`, update it. The canonical list is in doc 25 "All Commands" section.

2. **Check stale facts.** If this run changed docs or applied errata, scan MEMORY.md for claims that now contradict the corrected docs. Common staleness: error counts ("7 errors found" when there are now 20), outdated command descriptions, superseded architectural decisions.

3. **Minimal edits.** Fix what's wrong, don't rewrite what's fine. MEMORY.md is a lossy cache — it doesn't need to be complete, just not misleading.

If memory is current → report "Memory current."

## Step 6: Backlog review

Read doc 30 (backlog). Show the user any `pending` items and ask: "Want to work on any of these?" If the user picks one, work on it. If not, move on.

Also check: are there items that have already been researched and implemented but are still marked `pending`? If so, mark them `done` with a date.

If no pending items or user declines → report "Backlog reviewed, no action."

## Step 7: Log findings to decision log

For each errata applied or cascade propagated during this run, log a summary entry:

```bash
uv run python3 system/scripts/decisions.py log maintain-specs action \
  "Applied {N} errata, {M} cascade findings across {docs list}" \
  --severity "{HIGH if any HIGH errata, else MEDIUM}" 2>/dev/null || true
```

If individual findings were HIGH severity, log them separately:

```bash
uv run python3 system/scripts/decisions.py log maintain-specs finding \
  "{finding summary}" --severity HIGH --refs "{affected doc numbers}" 2>/dev/null || true
```

Skip if no errata were applied and no cascades occurred.

## Step 8: Surface findings for storage

Review what was discovered during this maintain-specs run. If any of these emerged, **ask the user** whether to store them in ruflo memory via `/brana:retrospective`:

- A new pattern or insight about how the docs relate to each other
- A recurring error type that suggests a process improvement
- A finding that would be useful in other clients (transferable)
- A correction that reveals a broader lesson (not just "doc X was wrong" but "we keep making this kind of mistake because...")

**Don't auto-store.** Present the candidate findings and let the user decide. Example: "This run found that Context7 and claude-flow were conflated in doc 14 — a recurring pattern of mixing tool identities in recommendation tables. Want to store this as a learning via `/brana:retrospective`?"

If nothing worth storing → report "No findings to store."

## Step 9: Backup knowledge

If this run modified any knowledge artifacts (MEMORY.md files, ReasoningBank entries, portfolio), back them up:

```bash
BACKUP_SCRIPT="$HOME/enter_thebrana/brana-knowledge/backup.sh"
[ -x "$BACKUP_SCRIPT" ] && "$BACKUP_SCRIPT"
```

If the script doesn't exist, skip silently — the user hasn't set up the knowledge repo yet.

## Step 10: Regenerate spec graph

If any steps above modified docs (applied errata, deepened reflections, updated doc 25), regenerate the spec dependency graph so consumers stay current:

```bash
uv run python3 system/scripts/spec_graph.py generate
```

If `spec_graph.py` doesn't exist, skip silently.

If no docs were modified this run → skip: "Spec graph unchanged."

## Rules

- **Early exit at every step.** If a step finds nothing, say so and move on. Don't force work where there's none.
- **Sub-commands own their rules.** `/brana:re-evaluate-reflections` and `/brana:apply-errata` each have their own rules for doc voice, materiality, gate checks, etc. Don't override them here.
- **Ask for clarification whenever you need it.** If the user's intent is unclear — ask. Don't guess.

## Output Format

```markdown
## Spec Maintenance Report

### Step 1: Apply Errata
[Output from `/brana:apply-errata` / "No pending errata"]

### Step 2: Re-evaluate Reflections
[Output from `/brana:re-evaluate-reflections` / "Reflections current — no gaps found"]

### Step 3: Deepen Reflections
[Improvements applied / "Reflections already sharp"]

### Step 4: Doc 25
[Sections flagged / "Doc 25 current"]

### Step 5: Memory
[What was updated / "Memory current"]

### Step 6: Backlog
[Items shown to user / "Backlog reviewed, no action"]

### Step 7: Findings Worth Storing
[Candidates for /brana:retrospective / "No findings to store"]

### Step 8: Backup Knowledge
[Backed up N entries / "No changes to back up" / "Backup script not found"]

### Summary
- Errors applied: N
- Reflections deepened: N
- Cascade findings: N
- Docs modified: [list]
- Memory updated: yes/no
- Everything current: yes/no
- **Reconcile suggested:** yes/no (if changes touched implementation-relevant specs)
```

**After the report:** If any changes during this run touched specs that describe thebrana behavior (skills, hooks, rules, agents, config, deploy, CLAUDE.md conventions), suggest:

> "This run changed specs that affect thebrana implementation. Run `/brana:reconcile` to push those changes into the built system?"
