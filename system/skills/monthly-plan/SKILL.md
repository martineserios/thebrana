---
name: monthly-plan
description: "Forward-looking monthly plan — revenue targets, priorities tied to bottleneck, experiments, pipeline actions, budget allocation. Use at month-start (after /monthly-close) to set targets and priorities."
allowed-tools:
  - Read
  - Write
  - Glob
  - Grep
  - Bash
---

# Monthly Plan

Forward-looking monthly plan: synthesize accumulated data into next month's revenue targets, priorities, experiments, pipeline actions, and budget allocation. The forward-looking complement to `/monthly-close`.

## When to use

End of each month (after `/monthly-close`), or start of a new month when planning. Run `/monthly-close` first if no close exists for the prior month.

**Dependencies:** `/monthly-close` (backward baseline), `/growth-check` (bottleneck, metrics), `/pipeline` (deals, forecast), `/experiment` (running, learnings), `/financial-model` (projections), `/weekly-review` (velocity, zombies).

---

## Step 1: Gather Context

Read from 6 data sources. All are optional — gracefully skip any that are missing.

### 1a: Detect stage

```bash
# Check CLAUDE.md and docs/ for stage indicators
[ -f ".claude/CLAUDE.md" ] && grep -i "stage" ".claude/CLAUDE.md"
[ -d "docs/metrics" ] && ls docs/metrics/ 2>/dev/null
[ -d "docs/okrs" ] && ls docs/okrs/ 2>/dev/null
```

If unclear, ask: "What stage is this venture at? (Discovery / Validation / Growth / Scale)"

### 1b: Last monthly close

```bash
# Most recent monthly close
ls docs/financial/close-*.md 2>/dev/null | sort | tail -1
```

Also search ReasoningBank:

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
cd "$HOME" && $CF memory search --query "monthly-close:$(basename $OLDPWD)" --limit 3 2>/dev/null || true
```

Extract: revenue, net income, burn rate, runway, flags, red/yellow/green counts.

### 1c: Growth-check snapshots (last 3)

```bash
ls -t docs/metrics/health-*.md 2>/dev/null | head -3
```

If `$CF` is found:
```bash
cd "$HOME" && $CF memory search --query "growth-check:$(basename $OLDPWD)" --limit 3 2>/dev/null || true
```

Extract: AARRR bottleneck, red/yellow metrics, trends.

### 1d: Pipeline state

```bash
ls docs/pipeline/*.md 2>/dev/null | sort
```

If `$CF` is found:
```bash
cd "$HOME" && $CF memory search --query "pipeline:$(basename $OLDPWD)" --limit 3 2>/dev/null || true
```

Extract: active deals, stalled deals, overdue follow-ups, pipeline value, forecast.

### 1e: Running experiments

```bash
# Filter for Running status
grep -rl "Status.*Running" docs/experiments/EXP-*.md 2>/dev/null
```

Read each running experiment. Extract: hypothesis, ICE score, measurement date, channel.

### 1f: Financial model projections

```bash
ls docs/financial/model-*.md 2>/dev/null | sort | tail -1
```

Extract: projected revenue by scenario, expense projections, runway forecast.

### 1g: Weekly reviews (last 4)

```bash
ls -t docs/metrics/weekly-*.md 2>/dev/null | head -4
```

Extract: velocity trends, committed zombies, ship log themes, Now item completion rate.

If any source is missing, note it as "Not available" and continue. Do not fabricate data.

---

## Step 2: Revenue Target

Build 3-scenario revenue targets from financial model data.

### If financial model exists:

```markdown
### Revenue Target — {YYYY-MM}

| Scenario | Revenue | Basis |
|----------|---------|-------|
| Conservative | ${amount} | {basis — e.g., "last month flat"} |
| Base | ${amount} | {basis — e.g., "current growth rate"} |
| Stretch | ${amount} | {basis — e.g., "pipeline converts at 50%"} |
```

### If no financial model:

Extrapolate from monthly close trends. If no close data either, ask: "What's your revenue target for next month?"

### Discovery stage:

Burn target only — no revenue projection.

```markdown
### Burn Target — {YYYY-MM}

| Item | Value |
|------|-------|
| Target burn | ${amount} |
| Current runway | {X} months |
| Runway after month | {X-1} months (at target burn) |
```

---

## Step 3: Priorities (3-5)

Derive priorities from data, tied to bottleneck. Maximum 5, minimum 3.

### Priority sources (in order):

1. **AARRR bottleneck** from `/growth-check` — the #1 constraint
2. **Biggest flag** from `/monthly-close` — revenue miss, expense overrun, runway concern
3. **Most promising experiment** to run or scale — highest-ICE from running experiments or new proposals
4. **Highest-value pipeline action** — overdue follow-ups, stalled high-value deals, qualification queue
5. **Committed zombies** from `/weekly-review` — items committed but repeatedly unfinished

### Format each priority:

```markdown
### Priority {N}: {What}

**Why now:** {data source and specific finding — e.g., "Activation bottleneck at 18% (growth-check 2026-01-15)"}
**Success metric:** {measurable outcome for the month}
**Owner:** {who — ask if unclear}
```

---

## Step 4: Experiments

### Running experiments:

List each with status and upcoming measurement dates.

| # | Experiment | Status | ICE | Measurement Date | Channel |
|---|-----------|--------|:---:|-----------------|---------|
| EXP-NNN | {title} | Running | {score} | {date} | {channel} |

### Proposed experiments (1-2 new):

Tied to the AARRR bottleneck. Include ICE scores.

| Proposal | Hypothesis | ICE (I/C/E) | Total | Why Now |
|----------|-----------|:-----------:|:-----:|---------|
| {title} | {one-line hypothesis} | {I}/{C}/{E} | {total} | {ties to bottleneck} |

---

## Step 5: Pipeline Actions

Actionable items from pipeline data for the month.

```markdown
### Pipeline Actions — {YYYY-MM}

**Overdue follow-ups:**
- {deal/lead} — last contact {date}, action: {what to do}

**Stalled deals:**
- {deal} — stalled at {stage} since {date}, action: {unstick tactic}

**Qualification queue:**
- {lead} — needs: {qualification step}

**Revenue gap:**
- Base target: ${target}
- Pipeline coverage: ${weighted value}
- Gap: ${difference} — action: {how to close the gap}
```

If no pipeline data exists, note: "No pipeline data available. Run `/pipeline` to start tracking."

---

## Step 6: Budget Allocation

### Discovery stage:

```markdown
### Budget — {YYYY-MM}

| Category | Amount | Notes |
|----------|--------|-------|
| Burn rate | ${total} | {trend vs last month} |
| Runway impact | {X} months remaining | |
```

### Growth+ stages:

```markdown
### Budget Allocation — {YYYY-MM}

| Category | Last Month | This Month | Change | Notes |
|----------|-----------|------------|--------|-------|
| Marketing / Ads | ${amount} | ${planned} | {+/-} | {rationale} |
| Product / Engineering | ${amount} | ${planned} | {+/-} | {rationale} |
| Operations | ${amount} | ${planned} | {+/-} | {rationale} |
| Tools / Subscriptions | ${amount} | ${planned} | {+/-} | {rationale} |
| Other | ${amount} | ${planned} | {+/-} | {rationale} |
| **Total** | **${total}** | **${planned}** | **{+/-}** | |

**Runway impact:** {X} months at planned spend (vs {Y} months at current spend)
```

Use actuals from monthly close + financial model projections. If data is missing, ask.

---

## Step 7: Key Dates

```markdown
### Key Dates — {YYYY-MM}

| Date | Event | Source |
|------|-------|--------|
| {date} | {experiment measurement deadline} | EXP-NNN |
| {date} | {pipeline follow-up deadline} | Pipeline |
| {date} | {financial deadline — tax, payroll, invoice} | Monthly close |
| {date} | {weekly review day} | Cadence |
| {date} | {growth-check scheduled} | Cadence |
| {date} | {monthly close target} | Cadence |
```

---

## Step 8: Output

Write the plan to `docs/planning/plan-{YYYY-MM}.md`.

```bash
mkdir -p docs/planning
```

Use this template:

```markdown
# Monthly Plan: {YYYY-MM}

**Date:** {today}
**Stage:** {Discovery | Validation | Growth | Scale}
**Prepared by:** /monthly-plan
**Based on:** /monthly-close {prior month}, /growth-check, /pipeline, /experiment, /financial-model, /weekly-review

---

{Step 2: Revenue Target}

---

{Step 3: Priorities}

---

{Step 4: Experiments}

---

{Step 5: Pipeline Actions}

---

{Step 6: Budget Allocation}

---

{Step 7: Key Dates}

---

## Review

This plan is a proposal. Review each section:

- [ ] Revenue target is realistic
- [ ] Priorities are correctly ordered
- [ ] Experiment proposals are worth running
- [ ] Pipeline actions are actionable
- [ ] Budget allocation matches strategy
- [ ] Key dates are accurate

Adjust anything that doesn't match your judgment, then commit to the plan.

---

*Generated by `/monthly-plan` | Data sources: /monthly-close, /growth-check, /pipeline, /experiment, /financial-model, /weekly-review*
```

---

## Step 9: Store Snapshot

Store the plan summary in ReasoningBank for historical tracking.

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
  -k "monthly-plan:{PROJECT}:{YYYY-MM}" \
  -v '{"type": "monthly-plan", "month": "YYYY-MM", "stage": "...", "revenue_target_base": N, "priority_count": N, "priorities": [...], "running_experiments": N, "proposed_experiments": N, "pipeline_gap": N, "runway_months": N}' \
  --namespace business \
  --tags "project:{PROJECT},type:monthly-plan,month:{YYYY-MM},stage:{STAGE}"
```

Search for previous plans to show planning trajectory:
```bash
cd "$HOME" && $CF memory search --query "monthly-plan:{PROJECT}" --limit 6 2>/dev/null || true
```

Fallback: append summary to `~/.claude/projects/{project-hash}/memory/MEMORY.md`:
```
## Monthly Plan: {YYYY-MM}
- File: docs/planning/plan-YYYY-MM.md
- Revenue target (base): ${amount}
- Priorities: {count} — {top priority}
- Experiments: {running} running, {proposed} proposed
- Runway: {X} months at planned spend
```

---

## Rules

- **Plan is a proposal.** Present for user review. Never execute without confirmation.
- **Every priority references a data source.** No priorities from thin air — tie each to a growth-check finding, monthly-close flag, experiment result, or pipeline state.
- **3-5 priorities maximum.** Resist the urge to plan more. If everything is a priority, nothing is.
- **Stage-appropriate depth.** Discovery gets burn target + 3 lean priorities. Growth gets the full treatment with revenue scenarios and budget allocation.
- **Run /monthly-close first if no close exists.** The plan needs backward data to project forward.
- **Don't fabricate data.** If a number isn't available, mark it "N/A" and note the gap. Never estimate unless clearly labeled as an estimate.
- **Store results in ReasoningBank when available, fall back to auto memory when not.**
- **Ask for clarification whenever you need it.** If revenue targets seem wrong, priorities conflict, or you're missing context — ask.
