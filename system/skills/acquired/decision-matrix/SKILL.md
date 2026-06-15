---
name: decision-matrix
description: "Weighted criteria scoring for multi-option decisions — makes trade-offs explicit and defensible with sensitivity analysis."
group: thinking
keywords: [decision-matrix, weighted-scoring, criteria, trade-off, comparison, evaluation, vendor, tool-selection]
task_strategies: [spike, investigation]
stream_affinity: [roadmap, research]
allowed-tools:
  - Read
  - Glob
  - Grep
  - AskUserQuestion
status: experimental
source: "Pugh Concept Selection (1981); Stuart Pugh — Total Design (1990); weighted scoring matrix method"
acquired: "2026-06-15"
---
# Decision Matrix

**Make trade-offs explicit. Score each option against weighted criteria.**

A decision matrix forces you to separate "what matters" from "how each option performs" — avoiding the trap of choosing the option you want and then finding criteria that justify it.

---

## When to use

- Choosing between 2–6 alternatives with multiple competing criteria
- Vendor/tool/technology selection
- Architecture decision records (ADRs) with real trade-offs
- When the team is split and needs a shared evaluation framework
- When you need a defensible, transparent decision
- Pairs with `/brana:swot-analysis` for strategic decisions; `/brana:six-thinking-hats` for perspective sweep before scoring

---

## Step 1 — Define the decision

What are we choosing between?

```
AskUserQuestion: "What decision are we making? List the alternatives (2–6)."
```

---

## Step 2 — Define criteria

What factors matter for this decision? Generate 4–8 criteria. Each criterion should be:
- Independently measurable (you can score options against it without circular reasoning)
- Relevant to the decision (not just "nice to have")
- At the right level of abstraction (not too broad, not too narrow)

Common criteria clusters:

| Category | Example criteria |
|----------|-----------------|
| **Cost** | Upfront cost, ongoing cost, switching cost |
| **Performance** | Speed, throughput, reliability, scalability |
| **Risk** | Vendor lock-in, maturity, team familiarity, security |
| **Fit** | Integration effort, ecosystem compatibility, flexibility |
| **Time** | Time to implement, time to value, maintenance burden |
| **Strategic** | Alignment with long-term direction, community/support |

---

## Step 3 — Assign weights

Distribute 100 points across criteria based on importance to this specific decision.

```
Criteria                | Weight
------------------------|--------
[Criterion 1]           | [X]
[Criterion 2]           | [Y]
...                     | ...
Total                   | 100
```

Rule: if two criteria have the same weight, that's fine. If one criterion has >40% of weight, consider splitting it — a single criterion dominating is often a sign it contains multiple concerns.

---

## Step 4 — Score each option

Score each alternative against each criterion on a 1–5 scale:
- 1 = Poor / doesn't meet the need
- 2 = Below average
- 3 = Adequate / meets minimum
- 4 = Good / clearly meets the need
- 5 = Excellent / exceeds expectations

```
Criteria           | Wt | Option A | Option B | Option C
-------------------|----|----------|----------|----------
[Criterion 1]      | 30 | 4        | 3        | 5
[Criterion 2]      | 25 | 3        | 5        | 2
[Criterion 3]      | 20 | 5        | 4        | 3
[Criterion 4]      | 15 | 2        | 4        | 4
[Criterion 5]      | 10 | 4        | 3        | 3
-------------------|----|----------|----------|----------
Weighted total     |    | [calc]   | [calc]   | [calc]
```

Weighted total = sum of (weight × score) for each criterion. Divide by 100 to normalize.

---

## Step 5 — Sensitivity analysis

The winner is often fragile. Test it:

1. **Swap the top two weights** — does the winner change?
2. **Remove the highest-weight criterion** — does the winner change?
3. **Shift the top option's lowest score by +1** — does it change the ranking?

If the winner changes under any of these: the decision is sensitive to assumptions. State which assumptions are load-bearing.

```
Sensitivity:
- Winner holds if [assumption A] remains true
- Winner changes if [criterion X] weight drops below [Y]
- Risk: [what to monitor that could invalidate this choice]
```

---

## Step 6 — Output

```
**Decision matrix: [decision]**

Options evaluated: [list]
Criteria: [N] factors, highest weight: [criterion] ([W]%)

Results:
1. [Option A] — [score] (winner)
2. [Option B] — [score]
3. [Option C] — [score]

Gap between top 2: [X pts]
If gap < 10 pts: decision is close — review scores for calibration bias

Sensitivity: winner is [stable/fragile] — [key assumption]

Recommendation: [Option A]
Key trade-off accepted: [what we're giving up]
```

---

## Notes

- Score independently, then calculate — don't set scores to make your preferred option win
- If the matrix produces a surprise winner you're reluctant to accept, that's a signal: either the scoring was biased, or your preference is based on an unlisted criterion (add it and re-score)
- The matrix is a decision support tool, not a decision-making machine. It surfaces trade-offs; humans make the call
- For ADRs: include the matrix as the evidence base for the chosen option
- Calibration check: if all options score 4–5 on every criterion, your criteria aren't discriminating — tighten them
