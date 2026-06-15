---
name: pre-mortem
description: "Prospective hindsight — imagine the project already failed, then diagnose why. Surfaces hidden risks before commitment."
group: thinking
keywords: [pre-mortem, risk, failure, retrospective, prospective, planning, stress-test]
task_strategies: [spike, investigation]
stream_affinity: [roadmap, research]
allowed-tools:
  - Read
  - Glob
  - Grep
  - AskUserQuestion
status: experimental
source: "Gary Klein — Sources of Power (1999); Klein et al. — Performing a Project Premortem (HBR 2007)"
acquired: "2026-06-15"
---
# Pre-Mortem

**Imagine the project already failed. Now find out why.**

Gary Klein's prospective hindsight technique — forces the brain into a different mode than optimistic planning. Retrospective analysis of a hypothetical failure produces 2× more failure causes than prospective analysis.

---

## When to use

- Before committing to a plan, architecture, or major decision
- When the team is too confident or too aligned (groupthink risk)
- Before a launch, migration, or irreversible change
- When someone asks "what could go wrong?"

---

## Step 1 — Set the scene

State the project, plan, or decision clearly. Then say:

> "It is [6 months / 1 year] from now. We went ahead with this plan. It failed completely. What happened?"

If the subject is unclear, ask:
```
AskUserQuestion: "What plan or decision are we stress-testing?"
```

---

## Step 2 — Generate failure causes

Spend 5–10 minutes generating every plausible failure cause without filtering. Use these lenses:

| Lens | Prompt |
|------|--------|
| **Technical** | What broke, crashed, couldn't scale, or had a hidden bug? |
| **Human/team** | Who burned out, left, got blocked, or misunderstood? |
| **Assumptions** | Which assumption turned out to be completely wrong? |
| **Dependencies** | What external system, vendor, or partner let us down? |
| **Market/context** | What changed in the world that made this irrelevant? |
| **Execution** | What did we fail to actually do? Where did we slip? |
| **Second-order** | What succeeded but caused something else to fail? |

Output: a raw list, no evaluation yet.

---

## Step 3 — Rank by impact × probability

Score each cause:
- **Impact** (1–3): How bad is this failure if it happens?
- **Probability** (1–3): How likely is it given our current plan?

Sort descending by `impact × probability`. Top 5 are the critical risks.

---

## Step 4 — Write the obituary (optional, high-stakes decisions)

Write a one-paragraph "obituary" for the project as if a journalist wrote it. Forces narrative coherence — reveals the single storyline that connects the top failure causes.

---

## Step 5 — Design preventions

For each top-ranked cause:
1. What early warning signal would appear before this failure materializes?
2. What specific change to the plan would prevent or reduce it?
3. Who owns the monitoring?

Output format:
```
Risk: [cause]
Signal: [early warning]
Prevention: [plan change]
Owner: [role/person]
```

---

## Step 6 — Decision

After working through the top risks:

```
**Pre-Mortem verdict for [project/decision]**
Critical risks: [top 2-3]
Plan changes recommended: [list]
Go/No-go: [proceed / modify / stop]
```

---

## Notes

- Separate generation from evaluation — don't judge causes during Step 2
- Silent individual generation first, then share, reduces anchoring bias
- Even if no plan changes result, the exercise calibrates the team's risk model
- Pair with `/brana:inversion` for maximum coverage (inversion finds what to avoid; pre-mortem finds what will go wrong)
