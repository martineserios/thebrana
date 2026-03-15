---
name: notebooklm-source
description: "Guided workflow to prepare and format sources for NotebookLM. Claude reads, reformats, validates, and writes optimized files. User uploads them in the browser. Step-by-step recipe with clear handoff points."
group: tools
allowed-tools:
  - Read
  - Write
  - Edit
  - Glob
  - Grep
  - Bash
  - Task
  - mcp__notebooklm__ask_question
  - mcp__notebooklm__add_notebook
  - mcp__notebooklm__list_notebooks
  - mcp__notebooklm__select_notebook
  - mcp__notebooklm__get_notebook
  - mcp__notebooklm__search_notebooks
  - mcp__notebooklm__get_health
  - mcp__notebooklm__get_library_stats
  - mcp__notebooklm__setup_auth
  - AskUserQuestion
---

# NotebookLM Source Preparation

A guided workflow. Claude does the heavy lifting (reading, reformatting, validating, writing files). The user handles what only a browser can do (creating notebooks, uploading files, running Audio Overview). Every step is labeled so both sides know who acts next.

## Usage

`/brana:notebooklm-source [subcommand] [args]`

| Subcommand | What happens |
|------------|-------------|
| (no args) | Ask what the user wants, then route |
| `prepare [path]` | Reformat one file for optimal ingestion |
| `curate [name]` | Plan a notebook: prepare multiple sources, produce upload package |
| `synthesis [notebook]` | Query a live notebook, generate a synthesis meta-source |
| `audio-prompt [topic]` | Generate a custom Audio Overview prompt |
| `validate [path]` | Score a file's NotebookLM-readiness |
| `batch [glob]` | Validate + prepare multiple files |

---

## Step Registry

On entry, create a CC Task step registry for the chosen recipe. Follow the [guided-execution protocol](../_shared/guided-execution.md).

**Per-recipe steps:**
- `prepare`: VALIDATE, REFORMAT, WRITE
- `curate`: PLAN, PREPARE-ALL, PACKAGE, UPLOAD
- `synthesis`: QUERY, COMPILE, WRITE
- `audio-prompt`: ANALYZE, GENERATE
- `batch`: SCAN, VALIDATE-ALL, PREPARE-ALL
- `validate`: SCORE (single step — skip registry)

### Resume After Compression

If context was compressed:
1. Call `TaskList` — find CC Tasks matching `/brana:notebooklm-source — {STEP}`
2. The `in_progress` task is your current step — resume from there

## Step labels

Throughout every recipe:
- **CLAUDE:** — Claude executes this step automatically. No user action needed.
- **YOU:** — The user must do this. Claude provides everything needed (files, URLs, exact instructions).
- **WAIT:** — Claude pauses and waits for the user to confirm before continuing.

---

## Recipe: `prepare [path]`

> Reformat a single file into NotebookLM-optimal Markdown.

**CLAUDE:** Check MCP auth.
```
Call mcp__notebooklm__get_health
→ If not authenticated, run mcp__notebooklm__setup_auth
```

**CLAUDE:** Read the source file at `[path]`. Analyze format:
- Already well-structured Markdown → minor cleanup only
- PDF → extract text with `pdftotext` or `pandoc` (warn if unavailable)
- Unstructured text → full restructure
- Code file → wrap in documentation context

**CLAUDE:** Apply the optimal source template (see Reference below):
- Add executive summary if missing
- Convert dense prose to bullet points
- Bold key terms and named entities
- Add H2/H3 headings to break up long sections
- Add Key Takeaways section
- Strip noise: boilerplate, empty sections, image references, broken links
- For brana-knowledge docs: replace `[doc NN](path)` links with descriptive text

**CLAUDE:** Validate the result (word count, structure, limits).

**CLAUDE:** Write the optimized file to `/tmp/notebooklm-{notebook-name}/{filename}.md` (subfolder per notebook so user can drag the whole folder at once).

**CLAUDE:** Show the user:
1. A before/after diff summary (what changed and why)
2. The validation score
3. The output file path

**YOU:** Upload `/tmp/notebooklm-{filename}.md` to your notebook at [notebooklm.google](https://notebooklm.google).

---

## Recipe: `curate [name]`

> Plan a thematic notebook, prepare all sources, produce a ready-to-upload package.

**CLAUDE:** Check MCP auth + list existing notebooks.
```
Call mcp__notebooklm__get_health
Call mcp__notebooklm__list_notebooks
```
Show existing notebooks. Ask:
- What topic does this notebook cover?
- What sources should go in? (files, URLs, Google Docs)
- What's the primary use case? (Q&A, audio overview, synthesis, research)

**WAIT:** User provides topic, sources, and use case.

**CLAUDE:** For each source:
- Files → run `prepare` on each one (read, reformat, validate, write to `/tmp/`)
- URLs → verify accessible, note for manual addition
- Google Docs → note Doc ID for manual addition

**CLAUDE:** Write a manifest to `/tmp/notebooklm-curate-{name}.md`:

```markdown
# Notebook Plan: [name]

**Topic:** [topic]
**Use case:** [use case]
**Prepared:** [date]

## Files to upload (drag these into NotebookLM)
1. `/tmp/notebooklm-{file1}.md` — [description] (X words, score: GOOD)
2. `/tmp/notebooklm-{file2}.md` — [description] (Y words, score: EXCELLENT)

## URLs to add (paste these in NotebookLM's "Add source" → "Website")
1. [url1]
2. [url2]

## Google Docs to add (paste these in "Add source" → "Google Docs")
1. [doc title] — [Doc URL]
```

**CLAUDE:** Present the manifest to the user.

**YOU:** Now do these steps in order:
1. Open [notebooklm.google](https://notebooklm.google)
2. Click **"+ New notebook"**
3. Upload the files from the `/tmp/notebooklm-{name}/` folder (drag the whole folder)
4. Add any URLs listed under "URLs to add"
5. Add any Google Docs listed under "Google Docs to add"
6. Wait for ingestion to finish (progress bar)
7. Click **Share** → **"Anyone with the link"** → copy the link
8. Paste the link back here

**WAIT:** User provides the notebook share URL.

**CLAUDE:** Register the notebook in the local library:
```
Call mcp__notebooklm__add_notebook with name, description, topics, use_cases, url
```

**CLAUDE:** Confirm: "Notebook registered. You can now query it or run `/brana:notebooklm-source synthesis {name}`."

---

## Recipe: `synthesis [notebook]`

> Query a live notebook and generate a synthesis document to upload back as a meta-source.

**CLAUDE:** Find the target notebook:
```
Call mcp__notebooklm__list_notebooks or mcp__notebooklm__search_notebooks
```
If not in library → ask user for the notebook URL.

**CLAUDE:** Set the notebook as active:
```
Call mcp__notebooklm__select_notebook
```

**CLAUDE:** Verify it's queryable:
```
Call mcp__notebooklm__ask_question: "What sources are in this notebook?"
→ If no sources or error → abort: "This notebook has no sources yet. Upload sources first."
```

**CLAUDE:** Extract key findings:
```
Call mcp__notebooklm__ask_question:
"List the 10 most important claims, findings, or conclusions across all sources.
 For each, quote the exact sentence and cite which source it comes from."
```

**CLAUDE:** Extract cross-source connections:
```
Call mcp__notebooklm__ask_question:
"What connections, contradictions, or tensions exist between different sources?
 Cite specific sources for each."
```

**CLAUDE:** Combine responses into a synthesis document using the synthesis template (see Reference below). Write to `/tmp/notebooklm-synthesis-{notebook}.md`.

**CLAUDE:** Show the user the synthesis document.

**YOU:** Upload `/tmp/notebooklm-synthesis-{notebook}.md` as a new source to the same notebook. This biases NotebookLM's attention toward the most important cross-source insights.

---

## Recipe: `audio-prompt [topic]`

> Generate a custom prompt for NotebookLM's Audio Overview. Purely local — no MCP needed.

**CLAUDE:** Ask:
- What audience? (technical team, executives, students, general public)
- What focus? (overview, deep dive, comparison, tutorial)
- What tone? (casual, professional, academic)
- Anything to emphasize or skip?

**WAIT:** User provides preferences.

**CLAUDE:** Generate the prompt:

```
Focus this discussion on [specific topic/aspect].

Audience: [audience description] who [what they need/want].

Emphasis:
- Spend most time on: [primary focus areas]
- Mention briefly: [secondary topics]
- Skip entirely: [irrelevant or already-known material]

Tone: [tone description]. [Specific guidance.]

Structure: Start with [hook/context], then [main content flow],
close with [actionable takeaways / open questions / next steps].
```

**CLAUDE:** Present the prompt for review.

**YOU:** In NotebookLM, open your notebook → click **"Audio Overview"** → click **"Customize"** → paste the prompt → click **"Generate"**.

---

## Recipe: `validate [path]`

> Score a file's readiness for NotebookLM. Heuristic — passing correlates with better retrieval but doesn't guarantee it.

**CLAUDE:** Read the file. Run all checks:

Hard limits:
- [ ] Word count < 500,000
- [ ] File size < 200 MB

Structural quality:
- [ ] Has an H1 title
- [ ] Has an executive summary in the first 5 lines
- [ ] Uses H2/H3 headings (at least 2 H2s for docs > 500 words)
- [ ] Has bullet points (at least a few for docs > 300 words)
- [ ] Has bold key terms (at least a few for docs > 200 words)
- [ ] No image references (NotebookLM ignores images in text)
- [ ] No excessively long paragraphs (flag > 200 words)
- [ ] Has a Key Takeaways / Summary section

**CLAUDE:** Score and report:
- **EXCELLENT** — all pass
- **GOOD** — 1-2 minor issues
- **NEEDS WORK** — structural issues
- **POOR** — no structure

Show specific fix suggestions for each issue found. If score is NEEDS WORK or POOR, offer to run `prepare` to fix automatically.

---

## Recipe: `batch [glob]`

> Validate and prepare multiple files at once.

**CLAUDE:** Glob for matching files. Run `validate` on each.

**CLAUDE:** Show summary table:
```
| # | File | Words | Score | Issues |
|---|------|-------|-------|--------|
| 1 | ... | ... | ... | ... |
```

**CLAUDE:** Ask which files to prepare (all, or specific numbers from the table).

**WAIT:** User selects files.

**CLAUDE:** Run `prepare` on selected files. Write a manifest to `/tmp/notebooklm-batch-{timestamp}.json`:
```json
{
  "created": "ISO timestamp",
  "files": [
    {"source": "original/path.md", "prepared": "/tmp/notebooklm-file.md", "words": 1234, "score": "GOOD"}
  ]
}
```

**CLAUDE:** Report: "N files prepared. Upload them from `/tmp/notebooklm-*.md`."

**YOU:** Upload the prepared files to your notebook at [notebooklm.google](https://notebooklm.google).

---

## Reference

### Optimal source template

```markdown
# [Document Title]

> **Executive Summary:** [2-3 sentence summary. What it covers, key takeaway, who it's for.]

## [Major Section 1]

[Introductory sentence.]

- **[Key concept 1]:** [Explanation]
- **[Key concept 2]:** [Explanation]

### [Subsection 1a]

[Content with **bold key terms**, bullet points, and tables.]

| Column A | Column B |
|----------|----------|
| data     | data     |

## [Major Section 2]

[Same pattern.]

---

## Key Takeaways

- **[Takeaway 1]:** [One sentence]
- **[Takeaway 2]:** [One sentence]
- **[Takeaway 3]:** [One sentence]
```

### Why this template works (best-practice assumptions)

Based on general RAG behavior and community reports. Google does not publish NotebookLM's chunking strategy.

- **Executive summary at top** — seeds the auto-generated Source Guide
- **H1/H2/H3 hierarchy** — most RAG systems chunk at heading boundaries
- **Bold key terms** — act as retrieval anchor points
- **Bullet points** — discrete retrievable facts, cleaner than dense prose
- **Tables** — best for structured data
- **Key Takeaways** — redundant retrieval path
- **No noise** — no boilerplate, images, or broken links

### Synthesis document template

```markdown
# Synthesis: [Notebook Name]

> **Purpose:** Synthesizes key findings across all sources. Upload this as an
> additional source to bias AI attention toward core insights.

## Core Findings

### 1. [Finding title]
> "[Exact quote]" — Source: [source name]

**Why it matters:** [1 sentence]

## Cross-Source Connections

- **[Connection]:** [Source A] and [Source B] both conclude...
- **[Contradiction]:** [Source C] contradicts [Source D] on...

## Open Questions

- [Question no source fully answers]

## Key Takeaways

- **[Takeaway 1]:** [One sentence]
- **[Takeaway 2]:** [One sentence]
```

### Hard limits

<!-- Last verified: 2026-03-02. Check https://support.google.com/notebooklm for current values. -->

| Constraint | Limit |
|------------|-------|
| Words per source | 500,000 |
| File size per source | 200 MB |
| Sources per notebook | 50 (free), 250 (Pro/Ultra) |
| Daily queries | 50 (free), 250 (Pro/Ultra) |

### Anti-patterns

| Don't | Why | Do instead |
|-------|-----|------------|
| Dump all files into one notebook | Dilutes retrieval | One topic per notebook |
| Select all sources for every query | Confused answers | Toggle relevant sources only |
| Upload raw PDFs with complex layouts | OCR artifacts | Convert to Markdown first |
| Paste unformatted text | Bad chunking | Format with headings + bullets |
| Skip executive summary | AI guesses purpose | Always start with 2-3 line summary |
| Dense paragraphs | Poor chunk boundaries | Break into bullets + subsections |
| Include image references | NotebookLM ignores them | Describe visuals in text |

## Rules

1. **Always validate before handoff.** Every source gets structural checks.
2. **Default to Markdown.** Unless user needs Google Docs features.
3. **Executive summary is mandatory.** 2-3 sentences at the top.
4. **Bold key terms.** Retrieval anchors.
5. **One topic per notebook.** Propose splitting if mixed content.
6. **Strip noise.** Boilerplate, empty sections, image refs, broken links.
7. **Preserve meaning.** Restructure and format, never alter substance.
8. **Show diffs.** Always show what changed before writing.
9. **Write to /tmp/notebooklm-{name}/.** One subfolder per notebook. Never modify original source files.
10. **Label every step.** User must always know if Claude acts next or they do.
