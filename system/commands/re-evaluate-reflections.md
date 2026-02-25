---
name: re-evaluate-reflections
description: "Cross-check reflection docs against dimension docs to find gaps, contradictions, and missed findings"
---

# Re-Evaluate Reflections

Check whether the 5 reflection docs (08-triage, 14-architecture, 31-assurance, 32-lifecycle, 29-transfer) fully account for everything in the dimension docs they depend on. Find gaps, contradictions, and missed findings — then log them as new errata in doc 24's format.

## Why This Exists

Dimension docs are the research layer. Reflection docs synthesize that research into architecture decisions. But synthesis can miss things — especially when dimension docs are updated after the reflection was written. This command catches that drift.

## How It Works

### Phase 1: Build the dependency map

Read the reflection docs to understand what dimension docs they claim to depend on:

- **Doc 08 (R1: Triage)** — triages all dimension docs into keep/drop/defer decisions
- **Doc 14 (R2: Architecture)** — builds the system design from diagnosis + dimension research
- **Doc 31 (R3: Assurance)** — verification framework: structural, behavioral, and outcome evaluation
- **Doc 32 (R4: Lifecycle)** — development workflow, context management, maintenance cadences, evolution
- **Doc 29 (R5: Transfer)** — what generalizes from code to business projects

For each reflection doc, extract:
- Which dimension docs it references (explicit cross-references + inline "doc NN" mentions)
- What key claims/decisions it makes
- What evidence from dimension docs it cites

### Phase 2: Cross-check each dimension doc

For each dimension doc referenced by a reflection doc, spawn a **parallel research agent** using the Task tool (`subagent_type: "general-purpose"`, `model: "haiku"`) that:

1. Reads the dimension doc fully
2. Reads the relevant sections of the reflection doc that reference it
3. Checks for:
   - **Missed findings** — the dimension doc contains conclusions or data that the reflection doc doesn't account for
   - **Contradictions** — the reflection doc states something that conflicts with what the dimension doc says
   - **Outdated references** — the reflection doc references a specific version, feature, or detail that the dimension doc has since updated
   - **Implicit assumptions** — the reflection doc assumes something about the dimension doc's topic that the dimension doc doesn't actually support

Each agent should be specific: "Read doc 09 sections on hooks. Read doc 14 sections that reference hooks. Report any findings in doc 09 that doc 14 doesn't account for."

### Phase 3: Also check unreferenced dimension docs

Some dimension docs might be relevant to the reflections but aren't explicitly referenced. Check:

- Are there dimension docs that SHOULD inform doc 08 or doc 14 but aren't mentioned?
- Did any new dimension docs get added after the reflection docs were written?

### Phase 4: Compile findings

Gather all agent results. For each finding, format it as a potential doc 24 errata entry:

```markdown
## Potential Error N: [Title]

**Severity:** High | Medium | Low
**Source:** Dimension doc [N] vs Reflection doc [N]
**Gap:** [What the reflection doc missed or got wrong]
**Evidence:** [Specific section/quote from the dimension doc]
**Suggested fix:** [What should change in the reflection doc]
**Docs to update:** [List]
```

## Agent Prompt Template

For each dimension doc being checked against a reflection doc:

```
You are checking whether reflection doc [REF_NUM] ([REF_TITLE]) fully accounts for the findings in dimension doc [DIM_NUM] ([DIM_TITLE]).

Read both documents carefully. Then report:

1. MISSED FINDINGS: Key conclusions, data, or recommendations in doc [DIM_NUM] that doc [REF_NUM] doesn't mention or account for. Only flag things that would materially affect the architecture or implementation decisions.

2. CONTRADICTIONS: Places where doc [REF_NUM] states something that conflicts with doc [DIM_NUM]. Include the specific quotes from each.

3. STALE REFERENCES: Where doc [REF_NUM] references a specific detail from doc [DIM_NUM] that has since changed or been corrected.

4. MISSING DEPENDENCY: If doc [REF_NUM] should depend on doc [DIM_NUM] but doesn't reference it at all, explain why the dependency matters.

Be strict about materiality — don't flag minor omissions or stylistic differences. Only flag things that would lead to wrong implementation decisions if left uncorrected.

If everything checks out, say: "No material gaps found between doc [DIM_NUM] and doc [REF_NUM]."
```

## Output Format

```markdown
## Re-Evaluation Results

### Summary

| Dimension Doc | vs Reflection Doc | Status | Findings |
|---------------|-------------------|--------|----------|
| 04 Claude 4.6 | 14 Mastermind | ok | No gaps |
| 09 Native Features | 14 Mastermind | gap found | SessionEnd discovery not propagated |
| ... | ... | ... | ... |

### New Errata Candidates

[Formatted as doc 24 entries, ready to be appended]

### No Issues Found
[List of dimension-reflection pairs that checked out clean]
```

## Important Notes

- Read doc 24 first to avoid re-discovering errors already documented there
- Skip dimension docs 01-03 (internal systems — reflection docs intentionally don't cover these in detail)
- Focus on **material** gaps — things that would cause wrong implementation. Not every dimension doc detail needs to appear in the reflections.
- The reflections are meant to be opinionated synthesis, not comprehensive summaries. A dimension doc finding that was deliberately excluded (the reflection doc says "we considered X and rejected it") is not a gap.
- **Ask for clarification whenever you need it.** If you're unsure whether a gap is material, a contradiction is intentional, or the user wants to handle a finding differently — ask. Don't guess.

## Note

This command is also available as Step 1 of `/maintain-specs`, which runs the full correction cycle (re-evaluate + apply + doc 25 check). Use this standalone command when you only want to cross-check without applying fixes.
