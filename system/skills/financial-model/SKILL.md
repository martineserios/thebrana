---
name: financial-model
description: "Revenue projections, scenario analysis, P&L template, unit economics, and cash flow analysis. Stage-aware financial modeling for founders."
allowed-tools:
  - Read
  - Write
  - Glob
  - Grep
  - Bash
---

# Financial Model

Build a stage-aware financial model: revenue projections across three scenarios, a P&L with line items matched to your stage, unit economics, and cash flow analysis. Produces a dated markdown model in `docs/financial/` and optionally a Google Sheets template.

## When to use

- Fundraise prep (investors will ask for projections)
- Monthly or quarterly planning (re-forecast against actuals)
- Building a business case for a new initiative
- When investors, advisors, or co-founders ask "what do the numbers look like?"

---

## Step 1: Detect Context

Read existing project context before building anything.

```bash
# Stage and business context
[ -f ".claude/CLAUDE.md" ] && grep -i -E "stage|domain|business|model" ".claude/CLAUDE.md"

# Previous financial models
[ -d "docs/financial" ] && ls -t docs/financial/model-*.md 2>/dev/null | head -5

# Latest growth-check for actuals
[ -d "docs/metrics" ] && ls -t docs/metrics/health-*.md 2>/dev/null | head -1
```

If a previous model exists, read it for assumptions and actuals. The new model should show variance from the prior forecast.

If stage is unclear, ask: "What stage is this business at? (Discovery / Validation / Growth / Scale)"

---

## Step 2: Business Model Type

Detect or ask the user. The model type determines revenue projection methodology.

| Type | Revenue Driver | Key Metric |
|------|---------------|------------|
| **SaaS** | MRR x growth rate | MRR, churn, expansion |
| **Marketplace** | GMV x take rate | GMV, take rate, liquidity |
| **Service / Consulting** | Billable hours x rate (or project fees) | Utilization, avg project size |
| **E-commerce** | Orders x AOV | AOV, conversion rate, repeat rate |
| **Hybrid** | Combine applicable models | Varies |

If detectable from CLAUDE.md or metrics docs, confirm with user. If not, ask:
"What's the primary revenue model? (SaaS / Marketplace / Service / E-commerce / Hybrid)"

---

## Step 3: Revenue Projection (3 Scenarios)

Build 12-month projections for three scenarios. Assumptions must be explicit and justified.

### Scenario Definitions

| Scenario | Philosophy | Typical Assumption |
|----------|-----------|-------------------|
| **Base** | Realistic — current trajectory continues | Current growth rate holds, no new channels |
| **Upside** | Optimistic — things go well | +50% on growth assumptions, new channel wins |
| **Downside** | Conservative — things go wrong | -30% on growth, higher churn, slower sales |

### Model-Specific Revenue Drivers

**SaaS:**
```
Month N Revenue = (Previous MRR + New MRR - Churned MRR + Expansion MRR)
  New MRR       = new customers x avg plan price
  Churned MRR   = previous MRR x monthly churn rate
  Expansion MRR = existing customers x expansion rate
```

**Marketplace:**
```
Month N Revenue = GMV x take rate
  GMV           = transactions x avg transaction value
  Transactions  = active buyers x purchase frequency
```

**Service / Consulting:**
```
Month N Revenue = billable hours x effective rate
  Billable hrs  = headcount x utilization rate x working hours
  — OR —
Month N Revenue = projects x avg project value
```

**E-commerce:**
```
Month N Revenue = orders x AOV
  Orders        = visitors x conversion rate
  Repeat orders = existing customers x repeat purchase rate
```

Ask the user for current values and growth assumptions. If `/growth-check` data exists, pull actuals from there.

Output a 12-month table per scenario:

```
| Month | Revenue | New Customers | Churn | Growth % | Cumulative |
|-------|---------|--------------|-------|----------|------------|
| M1    | ...     | ...          | ...   | ...      | ...        |
| ...   | ...     | ...          | ...   | ...      | ...        |
| M12   | ...     | ...          | ...   | ...      | ...        |
```

---

## Step 4: P&L Template

Generate stage-appropriate line items. Early stages need fewer categories; over-detailing a pre-revenue P&L wastes time.

### Discovery Stage

```
Revenue
  Product revenue              $___

Cost of Goods Sold (COGS)
  Hosting / infrastructure     $___
  ─────────────────────────────────
  Gross Profit                 $___

Operating Expenses
  Marketing experiments        $___
  Contractor / freelance       $___
  Tools & subscriptions        $___
  ─────────────────────────────────
  Total OpEx                   $___

Net Income (Loss)              $___
```

### Validation Stage

```
Revenue
  Product revenue              $___
  Service / consulting         $___
  ─────────────────────────────────
  Total Revenue                $___

COGS
  Hosting / infrastructure     $___
  Third-party services         $___
  ─────────────────────────────────
  Gross Profit                 $___
  Gross Margin                 ___%

Operating Expenses
  Salaries & benefits          $___
  Marketing & advertising      $___
  Tools & SaaS                 $___
  Office / coworking           $___
  Legal & accounting           $___
  Contractor / freelance       $___
  ─────────────────────────────────
  Total OpEx                   $___

Net Income (Loss)              $___
```

### Growth Stage

```
Revenue
  Product revenue              $___
  Service / consulting         $___
  Expansion / upsell           $___
  ─────────────────────────────────
  Total Revenue                $___

COGS
  Hosting / infrastructure     $___
  Third-party APIs / services  $___
  Customer support             $___
  ─────────────────────────────────
  Gross Profit                 $___
  Gross Margin                 ___%

Operating Expenses
  Engineering
    Salaries                   $___
    Tools & infrastructure     $___
  Sales & Marketing
    Salaries                   $___
    Advertising                $___
    Events & content           $___
  General & Admin
    Salaries (ops, finance)    $___
    Office / rent              $___
    Legal & accounting         $___
    Insurance                  $___
  ─────────────────────────────────
  Total OpEx                   $___

EBITDA                         $___
Net Income (Loss)              $___
```

### Scale Stage

Full departmental P&L — add R&D, People/HR, and departmental cost centers to the Growth template. Only use this level of detail if the team is 20+ people and the data exists to populate it.

Use the stage detected in Step 1. **Do not over-detail.** If only 4 expense categories are real, show 4 categories.

---

## Step 5: Unit Economics

Calculate the core unit economics. Ask the user for inputs or pull from `/growth-check` data.

### Formulas

```
CAC  = Total Sales & Marketing Spend / New Customers Acquired
       (use a specific period — monthly or quarterly)

LTV  = ARPU x Gross Margin % x (1 / Monthly Churn Rate)
       — OR for non-subscription —
LTV  = Avg Revenue per Customer x Gross Margin % x Avg Customer Lifespan

LTV:CAC Ratio = LTV / CAC
       3:1+  = healthy
       5:1+  = excellent (or under-investing in growth)
       <2:1  = unsustainable

Payback Period = CAC / (ARPU x Gross Margin %)
       (months to recover acquisition cost)

Gross Margin = (Revenue - COGS) / Revenue x 100
```

### Output Table

```
| Metric          | Value   | Benchmark       | Status |
|-----------------|---------|-----------------|--------|
| CAC             | $___    | Varies by model | —      |
| LTV             | $___    | > 3x CAC        | —      |
| LTV:CAC         | ___:1   | 3:1+ healthy    | —      |
| Payback Period  | ___ mo  | < 12 months     | —      |
| Gross Margin    | ___%    | > 70% SaaS      | —      |
```

If data is insufficient, mark as "Not enough data" and note what needs to be tracked.

---

## Step 6: Cash Flow Analysis

### Burn Rate

```
Monthly Burn Rate = Total Monthly Expenses - Total Monthly Revenue
                  = Net cash consumed per month

Gross Burn  = Total monthly expenses (ignoring revenue)
Net Burn    = Gross burn - monthly revenue
```

### Runway

```
Runway (months) = Current Cash Balance / Monthly Net Burn Rate
```

Classify:
- **Green:** 18+ months
- **Yellow:** 12-18 months
- **Red:** < 12 months

### Break-Even Projection

Using the Base scenario revenue trajectory, find the month where:
```
Monthly Revenue >= Monthly Expenses
```

If break-even is beyond the 12-month projection window, state that and note the gap.

### Output

```
| Metric              | Value        |
|---------------------|-------------|
| Current cash        | $___        |
| Gross burn (monthly)| $___        |
| Net burn (monthly)  | $___        |
| Runway              | ___ months  |
| Break-even (est.)   | Month ___   |
```

---

## Step 7: Output

Write the full model to `docs/financial/model-YYYY-MM.md`:

```bash
mkdir -p docs/financial
```

### Template

````markdown
# Financial Model — {YYYY-MM}

**Business:** {name}
**Stage:** {Discovery | Validation | Growth | Scale}
**Model type:** {SaaS | Marketplace | Service | E-commerce | Hybrid}
**Date:** {today}
**Previous model:** {link to prior model or "First model"}

---

## Assumptions

| Assumption | Base | Upside | Downside |
|-----------|------|--------|----------|
| {growth rate, churn, new customers, etc.} | {val} | {val} | {val} |

---

## Revenue Projections

### Base Scenario

| Month | Revenue | New Customers | Churn | Growth % |
|-------|---------|--------------|-------|----------|
| M1    |         |              |       |          |
| ...   |         |              |       |          |
| M12   |         |              |       |          |

**12-month total:** $___

### Upside Scenario

{Same table format}

**12-month total:** $___

### Downside Scenario

{Same table format}

**12-month total:** $___

---

## P&L (Monthly — Base Scenario)

{Stage-appropriate P&L from Step 4, populated with base scenario numbers}

---

## Unit Economics

| Metric          | Value   | Benchmark       | Status |
|-----------------|---------|-----------------|--------|
| CAC             |         |                 |        |
| LTV             |         |                 |        |
| LTV:CAC         |         |                 |        |
| Payback Period  |         |                 |        |
| Gross Margin    |         |                 |        |

---

## Cash Flow

| Metric              | Value        |
|---------------------|-------------|
| Current cash        |             |
| Gross burn (monthly)|             |
| Net burn (monthly)  |             |
| Runway              |             |
| Break-even (est.)   |             |

---

## Variance vs Previous Model

{If a prior model exists, compare key metrics:}

| Metric | Previous Forecast | Actual | Variance |
|--------|------------------|--------|----------|
|        |                  |        |          |

---

## Key Risks & Assumptions to Validate

1. {Assumption that most affects the model}
2. {Second biggest risk}
3. {Third}

---

*Generated by /financial-model on {today}. Review monthly.*
````

---

## Step 8: Google Sheets (Optional)

If a Google Sheets MCP tool is available, offer to create a spreadsheet version:

1. Check for Google Sheets MCP: look for `mcp__google-sheets` or similar in available tools
2. If available, ask: "Want me to also create a Google Sheets version with live formulas?"
3. If yes, create a sheet with tabs: Assumptions, Revenue (3 scenarios), P&L, Unit Economics, Cash Flow
4. Link formulas so changing assumptions auto-updates projections

If MCP is not configured, suggest: "For a live spreadsheet version, configure the Google Sheets MCP server and re-run this step."

---

## Rules

- **Assumptions must be explicit.** Every number in the model traces back to a stated assumption. No magic numbers.
- **Don't fabricate data.** If a metric isn't available, mark it as "TBD" and note what needs tracking. Never estimate actuals.
- **Stage drives detail.** A Discovery-stage model with 30 line items is theater. Match complexity to reality.
- **Three scenarios are mandatory.** A single-scenario model is a guess. Three scenarios show range and risk.
- **Pull actuals from /growth-check.** If health snapshots exist in `docs/metrics/`, use them. Don't ask the user for data you already have.
- **Variance matters more than absolutes.** If a previous model exists, the most valuable output is how actuals differed from forecast and why.
- **Monthly cadence.** Suggest re-running monthly. Financial models decay fast — a 3-month-old model is fiction.
- **Ask for clarification whenever you need it.** If assumptions seem inconsistent, the business model is unclear, or numbers don't add up — ask.
