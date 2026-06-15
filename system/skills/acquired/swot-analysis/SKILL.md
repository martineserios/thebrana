---
name: swot-analysis
description: "Map Strengths, Weaknesses, Opportunities, Threats — then generate cross-referenced strategic moves (SO, WO, ST, WT)."
group: thinking
keywords: [swot, foda, strengths, weaknesses, opportunities, threats, strategy, positioning, analysis]
task_strategies: [spike, investigation]
stream_affinity: [roadmap, research]
allowed-tools:
  - Read
  - Glob
  - Grep
  - AskUserQuestion
status: experimental
source: "Albert Humphrey — Stanford Research Institute (1960s); Kenneth Andrews — The Concept of Corporate Strategy (1971)"
acquired: "2026-06-15"
---
# SWOT Analysis (FODA)

**Map internal position and external landscape. Then generate strategic moves.**

SWOT is not a list exercise — it's a cross-reference exercise. The value is not in generating the four lists but in asking "how does each internal factor interact with each external factor?" That intersection generates strategy.

---

## When to use

- Before committing to a product direction, market entry, or partnership
- When re-evaluating an existing strategy
- When you need to defend or argue for a direction
- At the start of a new project or initiative
- Pairs with `/brana:jobs-to-be-done` (JTBD tells you the job to win; SWOT tells you if you're positioned to win it)

---

## Step 1 — Define the scope

What are we analyzing? One product, feature, business, team, or personal situation.

```
AskUserQuestion: "What are we doing a SWOT analysis for? Be specific."
```

Clarify the timeframe: current state, or projected 12–24 months?

---

## Step 2 — Internal analysis

**Strengths** — what do we do better than alternatives? What assets, capabilities, or advantages do we have?
- Technical (codebase, infrastructure, data)
- Team (skills, domain knowledge, network)
- Product (UX, features, reliability)
- Market (brand, distribution, relationships)
- Financial (runway, margins, revenue)

**Weaknesses** — what do alternatives do better? Where are we genuinely behind?
Same categories as Strengths. Be honest — overoptimism here kills the rest of the analysis.

For each item, ask: "Is this real, specific, and verifiable?" Remove vague entries.

---

## Step 3 — External analysis

**Opportunities** — what external trends, shifts, or gaps could we capitalize on?
- Market trends (growing demand, underserved segments)
- Technology shifts (new capabilities, falling costs)
- Competitor moves (retreating from a segment, product gaps)
- Regulatory/social changes (new compliance requirements, behavior shifts)
- Partnership/ecosystem openings

**Threats** — what external forces could harm us?
Same categories as Opportunities. A competitor's strength is a threat. A trend you're not riding is a threat.

---

## Step 4 — Cross-reference analysis (the actual strategy)

This is where SWOT generates value. Create four strategic quadrants:

| | **Opportunities (O)** | **Threats (T)** |
|---|---|---|
| **Strengths (S)** | **SO — Build** | **ST — Protect** |
| **Weaknesses (W)** | **WO — Improve** | **WT — Defend** |

**SO (Maxi-Maxi) — Build:** How can we use our strengths to capture opportunities?
```
S[1] + O[2] → [strategic move]
```

**WO (Mini-Maxi) — Improve:** How can we address weaknesses to capture opportunities?
```
W[1] + O[3] → [investment or partnership that bridges the gap]
```

**ST (Maxi-Mini) — Protect:** How can we use our strengths to neutralize threats?
```
S[2] + T[1] → [defensive move]
```

**WT (Mini-Mini) — Defend:** How do we avoid the worst-case (weak position meeting active threat)?
```
W[2] + T[2] → [contingency plan or exit]
```

Generate 2–4 moves per quadrant. The SO quadrant is growth; the WT quadrant is survival.

---

## Step 5 — Prioritize

Rate each strategic move:
- **Impact**: High / Medium / Low
- **Feasibility**: High / Medium / Low (given current resources)
- **Urgency**: Now / Soon / Later

Focus first on High Impact + High Feasibility moves. Flag any WT moves with High Urgency as immediate risks.

---

## Step 6 — Output

```
**SWOT Analysis — [scope]**

Internal:
  Strengths: [top 3]
  Weaknesses: [top 3]

External:
  Opportunities: [top 3]
  Threats: [top 3]

Strategic moves:
  SO (Build): [top move]
  WO (Improve): [top move]
  ST (Protect): [top move]
  WT (Defend): [top move]

Priority 1 action: [move with highest Impact + Feasibility]
Key risk to monitor: [WT move with highest urgency]
```

---

## Notes

- Distinguish between symptoms and causes. "Low brand awareness" is a symptom; "no marketing budget and no viral mechanism" are causes
- SWOT becomes stale fast. Mark the date; revisit quarterly for anything strategic
- External factors (OT) are things you don't control — internal factors (SW) are things you do
- The cross-reference matrix is often skipped. Don't skip it — it's where the strategy lives
- Pair with `/brana:second-order-thinking` on the top SO move to trace its consequences before committing
