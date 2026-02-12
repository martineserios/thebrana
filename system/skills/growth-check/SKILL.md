---
name: growth-check
description: Business health audit — AARRR funnel analysis and stage-appropriate metrics check with trend tracking
allowed-tools:
  - Bash
  - Read
  - Write
  - Glob
  - Grep
---

# Growth Check — Business Health Audit

AARRR funnel analysis + stage-appropriate metrics health check. The business equivalent of running tests. Produces a health report with green/yellow/red per metric, identifies the bottleneck, and recommends actions.

## When to use

Periodically (monthly or quarterly) or when something feels wrong. Also useful before major decisions (fundraise, expansion, hiring) to baseline current health.

---

## Step 1: Detect Stage

Check existing docs for stage indicators:

```bash
# Look for stage in CLAUDE.md
[ -f ".claude/CLAUDE.md" ] && grep -i "stage" ".claude/CLAUDE.md"

# Look for metrics docs
[ -d "docs/metrics" ] && ls docs/metrics/

# Look for OKRs (Growth+ indicator)
[ -d "docs/okrs" ] && ls docs/okrs/
```

If stage unclear, ask the user: "What stage is this business at? (Discovery / Validation / Growth / Scale)"

---

## Step 2: Collect Metrics

For each stage-appropriate metric, check `docs/metrics/` for current values. If not tracked there, ask the user.

### Discovery Stage Metrics

| Metric | Value | Benchmark | Status |
|--------|-------|-----------|--------|
| Customer interviews completed | {ask} | 20+ for confidence | |
| Problem validation (confidence) | {ask} | High before building | |
| Solution hypotheses tested | {ask} | 3+ before committing | |
| Monthly spend / burn rate | {ask} | As low as possible | |

### Validation Stage Metrics

| Metric | Value | Benchmark | Status |
|--------|-------|-----------|--------|
| MRR | {ask/check} | Growing month-over-month | |
| Monthly growth rate | {ask/check} | >15% (Paul Graham's "ramen profitable" pace) | |
| Activation rate | {ask/check} | >25% (signup → first value) | |
| Monthly retention | {ask/check} | >80% (or weekly >60%) | |
| Churn rate | {ask/check} | <10% monthly | |
| Burn rate (monthly) | {ask/check} | — | |
| Runway (months) | {calc} | 12+ months ideal | |
| DAU/MAU ratio | {ask/check} | >20% = sticky product | |

### Growth Stage Metrics

| Metric | Value | Benchmark | Status |
|--------|-------|-----------|--------|
| MRR | {ask/check} | Consistent growth | |
| ARR | {calc} | MRR × 12 | |
| CAC (Customer Acquisition Cost) | {ask/check} | Varies by domain | |
| LTV (Lifetime Value) | {ask/check} | Should grow over time | |
| LTV:CAC ratio | {calc} | 3:1+ healthy, 5:1+ excellent | |
| Payback period | {calc} | <12 months ideal | |
| Gross margin | {ask/check} | >70% SaaS, >50% service | |
| Monthly churn | {ask/check} | <5% B2B, <7% B2C | |
| Net revenue retention | {ask/check} | >100% = expansion revenue | |
| Employee count | {ask} | — | |
| Revenue per employee | {calc} | $100K+ for efficiency | |

### Scale Stage Metrics

| Metric | Value | Benchmark | Status |
|--------|-------|-----------|--------|
| ARR | {ask/check} | — | |
| YoY growth rate | {ask/check} | >40% early scale, >25% mature | |
| Net revenue retention | {ask/check} | >110% best-in-class | |
| Burn multiple | {calc} | <2x healthy, <1x excellent | |
| Rule of 40 | {calc} | Growth% + Margin% ≥ 40 | |
| Magic Number | {calc} | >0.75 = efficient growth | |
| Employee NPS | {ask} | >50 strong culture | |
| CAC payback | {calc} | <18 months | |

---

## Step 3: AARRR Funnel Analysis

If the business has a product (SaaS, marketplace, app), analyze the AARRR pirate metrics funnel:

```
AARRR FUNNEL
============

Acquisition → Activation → Retention → Referral → Revenue
   {N}    →    {N}     →    {N}    →   {N}    →   {N}
          {X%}         {X%}        {X%}        {X%}

Bottleneck: {stage with worst conversion}
```

For each stage:

| Stage | Question | Metric | Healthy |
|-------|----------|--------|---------|
| **Acquisition** | How do users find you? | Visitors, signups, leads | Growing, CAC stable |
| **Activation** | Do they get value quickly? | Signup → first value event | >25% |
| **Retention** | Do they come back? | DAU/MAU, monthly retention | >80% monthly |
| **Referral** | Do they tell others? | NPS, viral coefficient | NPS >50, k-factor >0.5 |
| **Revenue** | Do they pay? | Conversion rate, ARPU | Growing ARPU |

**Identify the bottleneck** — the stage with the worst conversion rate. This is where effort should focus. Improving stages downstream of the bottleneck is wasted work (you're optimizing revenue when nobody activates).

---

## Step 4: Benchmark Comparison

Compare metrics against benchmarks from [28-startup-smb-management.md](../../enter/28-startup-smb-management.md). For each metric, classify as:

- **Green** — at or above benchmark, healthy
- **Yellow** — below benchmark but not critical, needs attention
- **Red** — significantly below benchmark, requires immediate action

Thresholds (adjust for domain):

| Metric | Green | Yellow | Red |
|--------|-------|--------|-----|
| LTV:CAC | ≥3:1 | 2:1 - 3:1 | <2:1 |
| Monthly churn | <3% | 3-7% | >7% |
| Gross margin | >70% | 50-70% | <50% |
| Net retention | >110% | 100-110% | <100% |
| Burn multiple | <1.5x | 1.5-2.5x | >2.5x |
| Rule of 40 | ≥40 | 30-40 | <30 |
| Runway | >18 months | 12-18 months | <12 months |
| Activation rate | >30% | 15-30% | <15% |
| Monthly retention | >85% | 70-85% | <70% |

---

## Step 5: Health Report

Output a structured report:

```markdown
## Growth Check: {Business Name}

**Date:** {today}
**Stage:** {Discovery | Validation | Growth | Scale}

### Health Dashboard

| Metric | Value | Benchmark | Status |
|--------|-------|-----------|--------|
| {metric} | {value} | {benchmark} | 🟢 / 🟡 / 🔴 |

### AARRR Funnel (if applicable)

Acquisition ({N}) → Activation ({X%}) → Retention ({X%}) → Referral ({X%}) → Revenue ({X%})

**Bottleneck:** {stage} — {why it's the bottleneck, what to do}

### Key Findings

**Strengths (green):**
- {What's working well}

**Watch (yellow):**
- {What needs attention}

**Critical (red):**
- {What needs immediate action}

### Recommended Actions (prioritized)

1. **{Most impactful action}** — addresses {metric/bottleneck}
2. **{Second priority}** — addresses {metric}
3. **{Third priority}** — addresses {metric}

### Trend (vs previous check)

{If previous /growth-check snapshots exist in ReasoningBank, show trend:}

| Metric | Previous | Current | Trend |
|--------|----------|---------|-------|
| {metric} | {old} | {new} | ↑ / → / ↓ |
```

---

## Step 6: Store Snapshot

Store the health check in ReasoningBank for trend tracking across sessions:

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
  -k "growth-check:{PROJECT}:{date}" \
  -v '{"type": "growth-check", "stage": "...", "metrics": {...}, "bottleneck": "...", "red_count": N, "yellow_count": N, "green_count": N}' \
  --namespace business \
  --tags "project:{PROJECT},type:growth-check,stage:{STAGE}"
```

Also search for previous snapshots to enable trend comparison:
```bash
cd "$HOME" && $CF memory search -q "growth-check:{PROJECT}" --limit 5 2>/dev/null || true
```

Fallback: append summary to `~/.claude/projects/{project-hash}/memory/MEMORY.md`.

---

## Also save to docs/metrics/

If `docs/metrics/` exists, update or create `docs/metrics/health-{YYYY-MM-DD}.md` with the full report. This creates a local, readable history of health checks within the project.

---

## Rules

- **Don't fake data.** If a metric isn't available, mark it as "Not tracked" and recommend tracking it. Never estimate or guess metric values.
- **Bottleneck identification is the highest-value output.** The user can read a dashboard — what they need is "here's where your effort should go and why."
- **Compare against benchmarks, not absolute values.** A 5% churn rate is green for B2C SaaS and red for enterprise. Context matters.
- **Trend over snapshot.** A single check is useful. A series of checks over time is powerful. Always search for previous snapshots and show trends.
- **Don't overwhelm.** If only 3 metrics are tracked, check those 3. Don't present 20 blank rows. Suggest adding 1-2 more metrics, not all of them.
- **Store results in ReasoningBank when available, fall back to auto memory when not.**
- **Ask for clarification whenever you need it.** If metrics seem inconsistent, you're unsure about the business model for benchmarking, or values look unusual — ask.
