---
name: review
description: "Business review — weekly health check, monthly close + plan, or ad-hoc growth audit. Subcommands: weekly, monthly, check. Use for periodic business reviews or when metrics need assessment."
effort: high
argument-hint: "[weekly|monthly|check]"
group: venture
depends_on:
  - pipeline
  - financial-model
allowed-tools:
  - Read
  - Write
  - Glob
  - Grep
  - Bash
  - AskUserQuestion
---

# Review — Business Health

Unified business review skill. Replaces `/weekly-review`, `/monthly-close`, `/monthly-plan`, and `/growth-check`.

## Subcommand routing

Parse `$ARGUMENTS`:

- `/brana:review` or `/brana:review weekly` — weekly cadence review (default)
- `/brana:review monthly` or `/brana:review --monthly` — monthly close + forward plan
- `/brana:review check` or `/brana:review --check` — ad-hoc AARRR funnel audit

---

## /brana:review weekly

Weekly cadence review — portfolio health, zombie cleanup, metrics delta, ship log, next-week planning.

### Steps

1. **Detect stage and business model** from CLAUDE.md / docs/metrics/
2. **Spawn metrics-collector agent** to gather current metrics from all data sources (Google Sheets, docs/metrics/, tasks.json)
3. **Portfolio health:** read tasks.json across portfolio clients, compute progress per project
4. **Zombie cleanup:** identify tasks older than 30 days with no activity — present for archival or reprioritization
5. **Metrics delta:** compare current metrics vs last week's stored values
6. **Ship log:** `git log --oneline --since="7 days ago"` across active clients
7. **Pipeline check:** read pipeline state (if /brana:pipeline is configured)
8. **Store trends:**
   ```bash
   source "$HOME/.claude/scripts/cf-env.sh"
   [ -n "$CF" ] && cd "$HOME" && $CF memory store \
     -k "review:weekly:{PROJECT}:{date}" \
     -v '{"type": "weekly-review", "metrics": {...}, "zombies": N, "shipped": N}' \
     --namespace business \
     --tags "client:{PROJECT},type:weekly-review" \
     --upsert
   ```
9. **Next-week planning:** based on bottleneck identified in metrics + unblocked tasks
10. **Write report** to `docs/reviews/weekly-YYYY-MM-DD.md`

### Report format

```markdown
## Weekly Review — YYYY-MM-DD

### Health
{green/yellow/red per metric with delta vs last week}

### Shipped
{ship log}

### Zombies
{stale tasks flagged}

### Pipeline
{deal status if applicable}

### Next Week
1. {priority 1 — tied to bottleneck}
2. {priority 2}
3. {priority 3}
```

---

## /brana:review monthly

Monthly close + forward plan — P&L summary, actuals vs projections, targets for next month.

### Steps

1. **Detect stage** from CLAUDE.md
2. **Close the month:**
   - Collect revenue/expense data (Google Sheets, docs/metrics/, user input)
   - Build P&L summary: revenue, COGS, gross margin, operating expenses, net
   - Compare actuals vs projections from last month's plan
   - Compute runway: cash balance / monthly burn
   - Trend analysis: 3-month moving averages for key metrics
3. **Forward plan:**
   - Set revenue targets based on trends + stage benchmarks
   - Identify the #1 bottleneck (AARRR funnel analysis)
   - Propose 2-3 priorities tied to the bottleneck
   - Pipeline actions: follow-ups, qualification reviews
   - Budget allocation: where to spend next month
4. **Store trends** in ruflo (namespace: business)
5. **Write reports:**
   - `docs/reviews/monthly-close-YYYY-MM.md`
   - `docs/reviews/monthly-plan-YYYY-MM.md`

---

## /brana:review check

Ad-hoc AARRR funnel audit — stage-appropriate metrics health check.

### Steps

1. **Detect stage and business model type** (subscription / cycle-project / marketplace / consulting)
2. **Collect metrics** per stage:
   - **Discovery:** interviews, hypothesis validation, burn rate
   - **Validation:** MRR/revenue, activation, retention, churn, runway, DAU/MAU
   - **Validation (cycle/service):** revenue, recompra rate, AOV, concentration, channel attribution
   - **Growth:** MRR, CAC, LTV, LTV:CAC, payback, gross margin, churn, NRR
   - **Scale:** ARR, NRR, burn multiple, Rule of 40, employee NPS
3. **Traffic-light each metric:** green (healthy), yellow (watch), red (action needed)
4. **Identify bottleneck:** which AARRR stage is the weakest?
5. **Recommend actions** tied to the bottleneck
6. **Store snapshot** in ruflo
7. **Present report:**

```markdown
## Growth Check — YYYY-MM-DD

**Stage:** {stage}  **Model:** {type}

### AARRR Funnel
| Stage | Metric | Value | Status |
|-------|--------|-------|--------|
| Acquisition | ... | ... | {green/yellow/red} |
| Activation | ... | ... | ... |
| Retention | ... | ... | ... |
| Revenue | ... | ... | ... |
| Referral | ... | ... | ... |

### Bottleneck: {stage}
{why this is the bottleneck + recommended actions}

### Trend (vs last check)
{delta for key metrics}
```

---

---

## /brana:review routing (model routing calibration)

Calibration report for dynamic model routing. Requires 30+ `cost` entries in the decision log.

### Steps

1. **Read cost entries:**
   ```bash
   uv run python3 system/scripts/decisions.py read --type cost --json
   ```
2. **If fewer than 30 entries**, report: "Not enough routing data yet ({N}/30). Check again after more `/brana:backlog execute` runs."
3. **Compute per-model stats:**
   - For each model (haiku, sonnet, opus): count tasks, average complexity score, success rate (completed vs failed/partial from `agent_result.status` in tasks.json)
4. **Flag mismatches:**
   - Haiku tasks that failed (score was < 0.3 but task was too complex)
   - Opus tasks with low scores (score > 0.7 but task was trivial — wasted cost)
   - Sonnet tasks at score boundaries (0.28-0.32 or 0.68-0.72) — threshold sensitivity
5. **Present calibration report:**

```markdown
## Model Routing Calibration — YYYY-MM-DD

### Distribution
| Model | Tasks | Avg Score | Success Rate |
|-------|-------|-----------|-------------|
| haiku | N | 0.XX | NN% |
| sonnet | N | 0.XX | NN% |
| opus | N | 0.XX | NN% |

### Mismatches
- {task-id} routed to haiku (score: 0.15) but failed — consider raising threshold to 0.35
- {task-id} routed to opus (score: 0.72) but was trivial — consider lowering threshold to 0.65

### Threshold Recommendation
Current: haiku < 0.3 < sonnet < 0.7 < opus
Suggested: haiku < {X} < sonnet < {Y} < opus (based on {N} data points)
```

6. **Don't auto-adjust thresholds.** Present recommendations, let the user decide.

This sub-report is appended to `/brana:review weekly` or `/brana:review check` output when enough data exists. It can also be invoked directly via `/brana:review routing`.

---

## Rules

1. **Business model drives metrics.** Don't apply SaaS metrics to cycle-project businesses. Recompra > churn for non-subscription models.
2. **Stage drives scope.** Don't audit Scale metrics for a Validation business.
3. **Store trends consistently.** Every review stores a snapshot for comparison.
4. **Ask for data you can't find.** Don't guess metrics — ask the user or check data sources.
5. **Bottleneck → action.** Every review identifies the #1 bottleneck and proposes actions tied to it.
6. **Graceful degradation.** No Google Sheets → ask user. No ruflo → write to docs/reviews/ only.
