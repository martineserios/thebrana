---
name: apply-errata
description: "Apply pending errata from doc 24 through the layer hierarchy: dimension, reflection, roadmap — with gate checks between layers"
---

# Apply Errata

Read doc 24 (roadmap corrections) and apply fixes following the layer hierarchy: dimension docs first, then reflection docs, then roadmap docs — with gate checks between each layer to catch cascading inconsistencies.

## How It Works

### Step 0: Read and classify

1. Read `24-roadmap-corrections.md` to get the full error list
2. Classify each error into one of four buckets:

| Classification | Description | Action |
|---|---|---|
| `dimension-fix` | Wrong facts about tools, capabilities, or external systems (docs 01-07, 09-13, 15-16, 20-23, 25) | Apply in Step 1 |
| `reflection-fix` | Wrong architecture decisions or synthesis (docs 08, 14) | Apply in Step 3 |
| `roadmap-fix` | Wrong implementation steps or plans (docs 17, 18, 19) | Apply in Step 5 |
| `code-fix` | Targets implementation code (`deploy.sh`, `validate.sh`, hook scripts) | Skip — note as "applies to implementation repo" |
| `informational` | No fix needed, just awareness for implementers | Skip |

### Step 1: Apply dimension-level fixes

For each `dimension-fix` error:
- Read the affected dimension doc(s)
- Apply the correction described in doc 24
- Note what was changed

### Step 2: Gate check — do reflections still hold?

After dimension fixes are applied, check whether reflection docs (08, 14) are still consistent with the corrected dimension docs. This is a **targeted check**, not a full re-evaluation:

- For each dimension doc that was just modified, find the sections of docs 08 and 14 that reference it
- Read those specific sections
- Check: does the reflection's claim still match the corrected dimension doc?
- If not, note it as a **cascade finding** — a new inconsistency caused by the dimension fix

Spawn parallel agents (one per modified dimension doc, `subagent_type: "general-purpose"`, `model: "haiku"`) with this prompt:

```
Dimension doc [NUM] was just corrected. The fix: [SUMMARY OF FIX].

Read doc [NUM] (the corrected version) and the sections of reflection doc [08 or 14] that reference it.

Check: does the reflection doc's claim still hold after this correction?
- If yes: "No cascade impact."
- If no: report the specific inconsistency, the section in the reflection doc, and what needs to change.

Be strict — only flag things where the correction materially changes what the reflection doc says. Don't flag stylistic or minor differences.
```

### Step 3: Apply reflection-level fixes

Apply fixes from two sources:
1. `reflection-fix` errors from doc 24 (classified in Step 0)
2. Cascade findings from Step 2 (new inconsistencies found by gate check)

For each fix:
- Read the affected reflection doc
- Apply the minimum edit to correct the error
- Note what was changed

### Step 4: Gate check — do roadmaps still hold?

Same pattern as Step 2, but one layer down. For each reflection doc that was modified (in Step 3), check whether roadmap docs (17, 18, 19) are still consistent:

- Find the sections of roadmap docs that reference the modified reflection doc
- Check: do the roadmap's implementation steps still match the corrected reflection?
- Note any new cascade findings

Spawn parallel agents (one per modified reflection doc) with this prompt:

```
Reflection doc [NUM] was just corrected. The fix: [SUMMARY OF FIX].

Read doc [NUM] (the corrected version) and the sections of roadmap docs [17, 18, 19] that reference it.

Check: do the roadmap implementation steps still hold after this correction?
- If yes: "No cascade impact."
- If no: report the specific inconsistency, the section in the roadmap doc, and what needs to change.
```

### Step 5: Apply roadmap-level fixes

Apply fixes from two sources:
1. `roadmap-fix` errors from doc 24 (classified in Step 0)
2. Cascade findings from Step 4

**Deepen while you're there — roadmaps must be as detailed as possible.** When touching a roadmap section to apply a fix, actively add implementation precision that the corrected dimension/reflection docs now make possible: exact file paths, step-by-step logic with every branch documented, specific test cases, exact JSON structures. For example: a dimension fix that clarifies how an API actually works should turn a vague roadmap step ("integrate with X") into a concrete one ("call X.method() in the hook, pass Y, expect Z"). A precise roadmap ensures near-perfect implementation. The goal is that each maintenance cycle leaves the roadmap more directly implementable with less room for interpretation.

### Step 6: Update doc 24

After all fixes are applied, update the severity summary table:

1. **Mark applied errors** — change Status to `applied (YYYY-MM-DD)`
2. **Add comments** — fill the Comments column with a brief note of what was done (e.g., "Blockquote caveat added to doc 14", "Docs 08, 14, 17, 18 updated")
3. **Log cascade findings** — append any new inconsistencies discovered in Steps 2 and 4 as new error entries with status `pending`
4. **Skip `code-fix` and `informational` entries** — these don't need spec-level processing

The Comments column is the resolution record. It should say *what was done*, not repeat the error description. Keep it short — one line per entry.

## Rules

- **Only apply fixes that doc 24 explicitly describes or that gate checks surface.** Don't invent corrections beyond what the evidence shows.
- **Preserve doc voice and structure.** Change the minimum text needed. Don't rewrite surrounding paragraphs.
- **Show each fix before applying.** State: which doc, which section, what changes. Then edit.
- **Gate checks are targeted, not exhaustive.** Only check sections that touch the corrected content. A full cross-check is what `/re-evaluate-reflections` is for.
- **Cascade findings get logged to doc 24.** Even if you apply them immediately, document them as new errata entries so there's a record.
- **Ask for clarification whenever you need it.** If a fix is ambiguous, a cascade finding is unclear, or you're unsure whether a change is material — ask. Don't guess.

## Output Format

```markdown
## Errata Applied

### Classification

| # | Error | Layer | Classification | Action |
|---|-------|-------|---------------|--------|
| 1 | Settings merge bug | code | code-fix | Skipped |
| 2 | Stop vs SessionEnd | reflection + roadmap | reflection-fix | Applied |
| ... | ... | ... | ... | ... |

### Layer 1: Dimension Fixes
- [List of changes or "No dimension-level errors in doc 24"]

### Gate Check: Dimension → Reflection
- [Cascade findings or "Reflections still consistent after dimension fixes"]

### Layer 2: Reflection Fixes
- [List of changes, noting which came from doc 24 vs cascade]

### Gate Check: Reflection → Roadmap
- [Cascade findings or "Roadmaps still consistent after reflection fixes"]

### Layer 3: Roadmap Fixes
- [List of changes, noting which came from doc 24 vs cascade]

### Doc 24 Updated
- Marked N errors as applied
- Added N new cascade findings as errors [next number]-[next number]

### Remaining
[Any errors that couldn't be applied and why]
```

## Note

This command is also available as Step 2 of `/maintain-specs`, which runs the full correction cycle (re-evaluate + apply + doc 25 check). Use this standalone command when you already have errata in doc 24 and just want to apply them.
