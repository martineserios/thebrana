---
name: decision-matrix
description: "Compare multiple alternatives against weighted criteria — transparent, defensible choices with trade-off analysis. Use when choosing between vendors/tools/strategies, balancing competing priorities (cost vs quality vs speed), or when comparing options with explicit weights and scores."
group: thinking
keywords: [decision-matrix, weighted-criteria, trade-offs, compare, alternatives, vendor-selection, sensitivity-analysis, options]
allowed-tools:
  - Read
  - Glob
  - Grep
  - AskUserQuestion
status: acquired
source: "https://github.com/lyndonkl/claude"
acquired: "2026-06-15"
---

# Decision Matrix

## Overview

A decision matrix scores each option on each criterion, making subjective factors visible and comparable. It includes weighted criteria, sensitivity analysis, and clear recommendations.

**Quick example:**

| Option | Cost (30%) | Speed (25%) | Quality (45%) | Weighted Score |
|--------|-----------|------------|---------------|----------------|
| Option A | 8 (2.4) | 6 (1.5) | 9 (4.05) | **7.95** ← Winner |
| Option B | 6 (1.8) | 9 (2.25) | 7 (3.15) | 7.20 |
| Option C | 9 (2.7) | 4 (1.0) | 6 (2.7) | 6.40 |

Option A wins despite not being fastest or cheapest because quality matters most (45% weight).

## Workflow

```
Decision Matrix Progress:
- [ ] Step 1: Frame the decision and list alternatives
- [ ] Step 2: Identify and weight criteria
- [ ] Step 3: Score each alternative on each criterion
- [ ] Step 4: Calculate weighted scores and analyze results
- [ ] Step 5: Validate quality and deliver recommendation
```

**Step 1: Frame the decision and list alternatives**

Ask user for decision context (what are we choosing and why), list of alternatives (specific named options, not generic categories), constraints or dealbreakers (must-have requirements), and stakeholders (who needs to agree).

**Step 2: Identify and weight criteria**

Collaborate with user to identify criteria (what factors matter for this decision), determine weights (which criteria matter most, as percentages summing to 100%), and validate coverage (do criteria capture all important trade-offs).

**Step 3: Score each alternative on each criterion**

For each option, score on each criterion using consistent scale (typically 1-10 where 10 = best). Ask user for scores or research objective data where available. Document assumptions and data sources.

**Step 4: Calculate weighted scores and analyze results**

Calculate weighted score for each option (sum of criterion score × weight). Rank options by total score. Identify close calls (options within 5% of each other). Check for sensitivity (would changing one weight flip the decision).

**Step 5: Validate quality and deliver recommendation**

Present clear recommendation, highlight key trade-offs revealed by analysis, note sensitivity to assumptions, and suggest next steps (gather more data on close calls, validate with stakeholders).

## Framing Questions

- What specific decision are we making? (Choose X from Y alternatives)
- What happens if we don't decide or choose wrong?
- Are there absolute dealbreakers? (Budget cap, timeline requirement, compliance need)
- Which constraints are flexible vs rigid?

## Criterion Types

**Financial:** Upfront cost, ongoing cost, ROI, payback period (weight: 20-40%)
**Performance:** Speed, quality, reliability, scalability (weight: 30-50%)
**Risk:** Implementation risk, reversibility, vendor lock-in (weight: 10-25%)
**Strategic:** Goal alignment, future flexibility, competitive advantage (weight: 15-30%)
**Operational:** Ease of use, maintenance burden, integration complexity (weight: 10-20%)

## Weighting Approaches

**Direct Allocation:** Assign percentages totaling 100%. Quick but can be arbitrary.
**Pairwise Comparison:** Compare each criterion pair. More rigorous.
**Must-Have vs Nice-to-Have:** Separate pass/fail requirements from weighted criteria.
**Stakeholder Averaging:** Each stakeholder assigns weights independently, then average.

## Sensitivity Analysis

After calculating scores, check robustness:
- **Close calls:** Options within 5-10% → Need more data
- **Dominant criteria:** One criterion driving everything → Is weight too high?
- **Weight sensitivity:** Swapping weights flips winner → Decision is fragile
- **Score sensitivity:** Adjusting one score by ±1 flips winner → Gather more data

## When NOT to Use This

- Only one viable option
- Binary yes/no with single criterion (use simpler analysis)
- Decision is urgent and stakes are low
- You already know the answer (using matrix to justify pre-made decision)

**Use instead:**
- Single criterion → Simple ranking
- Binary decision → Pro/con list
- Highly uncertain → Scenario planning or decision tree
- Purely subjective → Gut check

## Quick Reference

1. Frame decision → List alternatives
2. Identify criteria → Assign weights (sum to 100%)
3. Score each option (1-10 scale)
4. Calculate weighted scores → Rank
5. Check sensitivity → Deliver recommendation
