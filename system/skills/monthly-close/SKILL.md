---
name: monthly-close
description: "Monthly financial close — P&L summary, actuals vs projections, trend analysis, runway update. The monthly heartbeat of business health."
allowed-tools:
  - Read
  - Write
  - Glob
  - Grep
  - Bash
---

# Monthly Close

Monthly financial close: pull the month's data, compare actuals to plan, summarize P&L, track trends, update runway.

## When to use

End of each month, or when preparing for a board update, investor conversation, or quarterly review. Run after `/growth-check` snapshots exist for the month.

**Dependencies:** `/growth-check` (metric snapshots), `/financial-model` (projections), `/pipeline` (revenue data).

---

## Step 1: Gather Data

Read inputs from three sources:

### 1a: Growth-check snapshots

```bash
# Find all /growth-check snapshots from this month
ls docs/metrics/health-*.md 2>/dev/null | sort
```

Read each snapshot from the closing month. Extract: MRR, churn, CAC, retention, AARRR funnel data, stage.

### 1b: Financial model projections

```bash
# Find the latest /financial-model output
ls docs/financial/model-*.md 2>/dev/null | sort | tail -1
```

Extract projected revenue, expenses, and key targets for the closing month.

### 1c: Pipeline / revenue data

```bash
# Find pipeline data
ls docs/pipeline/*.md 2>/dev/null | sort
```

Extract closed deals, revenue by source, conversion rates for the month.

If any source is missing, note it as "Not available" in the report. Do not fabricate numbers.

---

## Step 2: P&L Summary

Build a stage-appropriate P&L. Include only line items that have data.

```markdown
### Profit & Loss — {YYYY-MM}

| Line Item | Amount |
|-----------|--------|
| **Revenue** | |
| Recurring revenue (MRR) | ${amount} |
| One-time revenue | ${amount} |
| Other revenue | ${amount} |
| **Total Revenue** | **${total}** |
| | |
| **COGS** | |
| Hosting / infrastructure | ${amount} |
| Third-party services | ${amount} |
| **Total COGS** | **${total}** |
| | |
| **Gross Profit** | **${total}** |
| Gross Margin | {X%} |
| | |
| **Operating Expenses** | |
| Payroll / contractors | ${amount} |
| Marketing / ads | ${amount} |
| Tools / subscriptions | ${amount} |
| Legal / accounting | ${amount} |
| Other | ${amount} |
| **Total OpEx** | **${total}** |
| | |
| **Net Income** | **${total}** |
```

For early-stage (Discovery/Validation): fewer line items are expected. Don't pad with zeros -- only include what's real.

---

## Step 3: Actuals vs Plan

Compare actual numbers to `/financial-model` projections.

```markdown
### Actuals vs Plan — {YYYY-MM}

| Item | Plan | Actual | Variance ($) | Variance (%) | Flag |
|------|------|--------|-------------|--------------|------|
| Revenue | ${plan} | ${actual} | ${diff} | {X%} | {flag} |
| COGS | ${plan} | ${actual} | ${diff} | {X%} | {flag} |
| Gross Profit | ${plan} | ${actual} | ${diff} | {X%} | {flag} |
| OpEx | ${plan} | ${actual} | ${diff} | {X%} | {flag} |
| Net Income | ${plan} | ${actual} | ${diff} | {X%} | {flag} |
```

Flag rules:
- Variance > +10% or < -10% = **FLAG** with brief explanation
- Revenue under plan = always flag
- Expenses over plan = always flag

If `/financial-model` output doesn't exist, skip this step and note: "No financial model projections available. Run `/financial-model` to enable actuals-vs-plan tracking."

---

## Step 4: Metrics vs Targets

Key metrics dashboard with status indicators.

```markdown
### Metrics vs Targets — {YYYY-MM}

| Metric | Target | Actual | Status | Variance |
|--------|--------|--------|--------|----------|
| MRR | ${target} | ${actual} | GREEN / YELLOW / RED | {+/-X%} |
| Monthly churn | {target%} | {actual%} | GREEN / YELLOW / RED | {+/-X pp} |
| CAC | ${target} | ${actual} | GREEN / YELLOW / RED | {+/-X%} |
| LTV:CAC | {target} | {actual} | GREEN / YELLOW / RED | {+/-X} |
| Activation rate | {target%} | {actual%} | GREEN / YELLOW / RED | {+/-X pp} |
| Retention | {target%} | {actual%} | GREEN / YELLOW / RED | {+/-X pp} |
| Runway | {target}mo | {actual}mo | GREEN / YELLOW / RED | {+/-X mo} |
```

Status thresholds (from `/growth-check` benchmarks):
- **GREEN** -- at or above target
- **YELLOW** -- within 10% of target
- **RED** -- more than 10% below target

Only include metrics that are actually tracked. Don't show empty rows.

---

## Step 5: Trend Analysis

MoM comparisons for key metrics. Requires at least 2 months of data.

```markdown
### Trend Analysis — 3-Month View

| Metric | {MM-2} | {MM-1} | {MM} | MoM Change | Direction |
|--------|--------|--------|------|------------|-----------|
| MRR | ${val} | ${val} | ${val} | {+/-X%} | up / flat / down |
| Churn | {val%} | {val%} | {val%} | {+/-X pp} | up / flat / down |
| CAC | ${val} | ${val} | ${val} | {+/-X%} | up / flat / down |
| Runway | {val}mo | {val}mo | {val}mo | {+/-X mo} | up / flat / down |
| Burn rate | ${val} | ${val} | ${val} | {+/-X%} | up / flat / down |
```

Direction thresholds:
- **up** -- improved >2% (or >2pp for percentages)
- **flat** -- within +/-2%
- **down** -- declined >2%

If fewer than 2 months of data exist, note: "Trend analysis requires 2+ months of snapshots. Will be available next month."

---

## Step 6: Cash Flow Update

```markdown
### Cash & Runway — {YYYY-MM}

| Item | Value |
|------|-------|
| Cash on hand | ${amount} |
| Monthly burn rate | ${amount} |
| Runway | {X} months |
| Break-even projection | {YYYY-MM} (at current trajectory) |
| Burn rate change (MoM) | {+/-X%} |
```

If burn rate is increasing, flag it. If runway drops below 12 months, flag it as RED.

---

## Step 7: Output

Write the close report to `docs/financial/close-{YYYY-MM}.md`.

```bash
mkdir -p docs/financial
```

Use this template:

```markdown
# Monthly Close: {YYYY-MM}

**Date:** {today}
**Stage:** {Discovery | Validation | Growth | Scale}
**Prepared by:** /monthly-close

---

{Step 2: P&L Summary}

---

{Step 3: Actuals vs Plan}

---

{Step 4: Metrics vs Targets}

---

{Step 5: Trend Analysis}

---

{Step 6: Cash Flow Update}

---

## Summary

**Month in one sentence:** {brief narrative of the month's financial story}

**Top flags:**
1. {most important variance or concern}
2. {second}
3. {third}

**Actions for next month:**
- {action tied to a flag or trend}
- {action tied to a flag or trend}

---

*Generated by `/monthly-close` | Data sources: /growth-check, /financial-model, /pipeline*
```

---

## Step 8: Store Snapshot

Store the close summary in ReasoningBank for historical tracking.

```bash
CF=""
for candidate in "$HOME"/.nvm/versions/node/*/bin/claude-flow; do
    [ -x "$candidate" ] && CF="$candidate" && break
done
[ -z "$CF" ] && command -v claude-flow &>/dev/null && CF="claude-flow"
[ -z "$CF" ] && command -v npx &>/dev/null && CF="npx claude-flow"
```

If `$CF` is found:
```bash
cd "$HOME" && $CF memory store \
  -k "monthly-close:{PROJECT}:{YYYY-MM}" \
  -v '{"type": "monthly-close", "month": "YYYY-MM", "stage": "...", "revenue": N, "net_income": N, "burn_rate": N, "runway_months": N, "red_count": N, "yellow_count": N, "green_count": N, "flags": [...]}' \
  --namespace business \
  --tags "project:{PROJECT},type:monthly-close,month:{YYYY-MM},stage:{STAGE}"
```

Also search for previous closes to confirm trend data:
```bash
cd "$HOME" && $CF memory search --query "monthly-close:{PROJECT}" --limit 12 2>/dev/null || true
```

Fallback: append summary to `~/.claude/projects/{project-hash}/memory/MEMORY.md`:
```
## Monthly Close: {YYYY-MM}
- File: docs/financial/close-YYYY-MM.md
- Revenue: ${total}
- Net Income: ${total}
- Runway: {X} months
- Flags: {red_count} red, {yellow_count} yellow
```

---

## Rules

- **Don't fabricate data.** If a number isn't available, mark it "N/A" and note the gap. Never estimate unless clearly labeled as an estimate.
- **Flag aggressively, but explain.** Every flag needs a one-line "why" -- a bare RED with no context is useless.
- **Trend over snapshot.** A single month is a data point. Trends are what matter. Always surface MoM direction when data exists.
- **Run /growth-check first if no snapshots exist.** Monthly close depends on metric snapshots. If `docs/metrics/` is empty, suggest running `/growth-check` before closing.
- **Stage-appropriate depth.** Discovery stage gets a lean close (burn rate, runway, key learnings). Growth stage gets the full treatment. Don't overwhelm an early-stage venture with Scale-stage metrics.
- **Store results in ReasoningBank when available, fall back to auto memory when not.**
- **Ask for clarification whenever you need it.** If numbers look inconsistent, a metric seems wrong, or you're missing context about the business model -- ask.
