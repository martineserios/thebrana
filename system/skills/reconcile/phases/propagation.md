<!-- reconcile phase: Propagation scope: errata cascade, fitness check, spec-graph consistency — loaded per the PHASES registry in ../SKILL.md (t-1942) -->

## Propagation Domain (`--scope propagation`)

Cascade pending errata through the spec layer hierarchy. Invokes existing commands as building blocks.

### PROP-1: Fitness check

Run `/brana:verify-docs` to check for doc drift, structural errors, and staleness. Surface any findings as candidates for manual correction.

### PROP-2: Spec-graph consistency

If `docs/spec-graph.json` exists:
1. Run `brana graph build` to regenerate
2. Compare output with existing graph
3. Flag new orphan nodes, broken edges, missing docs

### PROP-3: Dim "Could Adopt" scan [INTERACTIVE if untracked ideas found]

Dimension docs are otherwise a pull system — enrichment writes ideas that nothing reads back
out. This step surfaces untracked ones into the backlog (t-1706).

1. Glob dimension docs:
   ```bash
   KNOWLEDGE="$HOME/enter_thebrana/brana-knowledge/dimensions"
   grep -rlniE '^#{2,4}\s.*could adopt' "$KNOWLEDGE" --include="*.md"
   ```
2. For each matching file, extract candidates under each `Could Adopt` / `What * Could Adopt`
   heading (through the next heading of the same or shallower level):
   - Bullet-list items become one candidate each (including nested bullets under a bold
     sub-group label, e.g. `**From ECC:**` — the sub-group label is not itself a candidate).
   - A heading with prose instead of bullets: the paragraph text becomes one candidate.
   - **Skip struck-through items** (`~~text~~`) — this is the dim-doc convention for "already
     done," usually followed by `Implemented t-NNN` or similar. These are resolved, not
     untracked; re-surfacing them would spam the approval prompt with closed work (found via
     dim 46 §6.3 during implementation — 2 of 8 items there were already struck through).
3. Diff each remaining candidate against the live backlog:
   ```bash
   brana backlog query --status pending --output json
   brana backlog query --status in_progress --output json
   ```
   (`--status` takes one value, not a comma list — unlike `--tag`. Run both and merge.)
   A candidate is **already tracked** if either:
   - **Keyword overlap:** 2+ significant words (ignore stopwords) shared between the candidate
     text and a task's `subject` — same fuzzy-match bar as `build/phases/load.md` Step 0a.
   - **Tag overlap:** the dim doc's slug (e.g. `46-cc-harness-ecosystem`) or an obvious topic
     word from its title appears in a task's `tags`.
4. Collect every candidate that matches neither into an `untracked_ideas` list (dim doc path +
   heading + candidate text). If empty, skip to PROP-REPORT with "0 untracked ideas found."
5. Present via `AskUserQuestion` (multiSelect):
   ```
   "N untracked 'Could Adopt' ideas found across M dimension docs.
   Select which to add to the backlog, or dismiss:"
   ```
   Options: one per candidate (dim doc + heading + truncated text), plus "Skip — take no
   action (Recommended)".
6. For each selected candidate, create a task:
   ```bash
   brana backlog add --subject "{candidate text, trimmed to a subject-length summary}" \
     --kind feature --tags "{dim-slug}" \
     --context "Sourced from brana-knowledge/dimensions/{file} § {heading} via /brana:reconcile --scope propagation PROP-3 ({date})"
   ```
   Never edit the dim doc itself — this step is read-only against `brana-knowledge/`.

### PROP-REPORT

Summary: errata applied, reflections updated, graph changes, dim ideas scanned/tracked/added
(PROP-3). Commit all propagation changes as one logical group.

---

