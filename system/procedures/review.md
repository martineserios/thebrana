
# Review — Business Health

Unified business review skill. Replaces `/weekly-review`, `/monthly-close`, `/monthly-plan`, and `/growth-check`.

On entry, create a CC Task step registry. Follow the [guided-execution protocol](../_shared/guided-execution.md).

Register these steps: LOAD, REVIEW (subcommand-specific), EXTRACT, EVALUATE, PERSIST.

<!-- ruflo preamble -->
ToolSearch("select:mcp__ruflo__memory_search,mcp__ruflo__agent_spawn,mcp__ruflo__memory_store")

## Step 0 — LOAD

Pull relevant business context into memory before the review. Budget: 30K tokens max.

1. **Build query** from available context: `"{project} {task.subject} {task.tags joined} {user_input}"`
2. **Primary — ruflo MCP (run all in parallel — `namespace: "all"` only returns session records):**
   ```
   mcp__ruflo__memory_search(query: "{query} metrics revenue health pipeline", namespace: "knowledge", limit: 2, threshold: 0.4)
   mcp__ruflo__memory_search(query: "{query} metrics revenue health pipeline", namespace: "pattern",   limit: 2, threshold: 0.4)
   mcp__ruflo__memory_search(query: "{query} metrics revenue health pipeline", namespace: "business",  limit: 3, threshold: 0.4)
   ```
   Merge results, rank by similarity. Focus on: prior review snapshots (namespace: business), pipeline state, event log entries, and health metrics.
2b. **Graph edge traversal** — see `build.md` LOAD step 2b. Follow `depends_on`/`informs` edges from knowledge results. Max 3 graph-derived docs. Best-effort, never blocks.
3. **Fallback — tag-based grep** (if MCP unavailable):
   ```bash
   grep -rl "{keywords}" docs/reviews/ --include="*.md" | head -5
   grep -rl "{keywords}" ~/enter_thebrana/brana-knowledge/dimensions/ --include="*.md" | head -3
   ```
   Read the most recent review file and top 2 matching dimension files (first 80 lines each).
4. **Skill match handling** — if any result has `namespace: "skills"` and score >= 0.5, mention inline: "Matching skill: /brana:{name} ({score})." Informational only — don't auto-invoke or block.
4a. **JIT skill acquisition** — if no skills match and topic involves a specific technology, offer marketplace search via `Skill(skill="brana:acquire-skills", args="{tech}")`. Read installed procedure into context immediately. See `build.md` LOAD step 4a for full logic and guard rails.
5. **Summarize loaded knowledge** as a brief context preamble (2-5 bullets). Surface prior trends, last review's bottleneck, and pipeline status so the review builds on history.

---

## Subcommand routing

Parse `$ARGUMENTS`:

- `/brana:review` or `/brana:review weekly` — weekly cadence review (default)
- `/brana:review monthly` or `/brana:review --monthly` — monthly close + forward plan
- `/brana:review check` or `/brana:review --check` — ad-hoc AARRR funnel audit
- `/brana:review routing` — model routing calibration (needs 30+ cost entries)
- `/brana:review harness` — harness simplification check (quarterly or post-model-upgrade)

---

## /brana:review weekly

Weekly cadence review — portfolio health, zombie cleanup, metrics delta, ship log, next-week planning.

### Steps

1. **Detect stage and business model** from CLAUDE.md / docs/metrics/
2. **Spawn metrics-collector agent** via ruflo for cost attribution:
   ```
   mcp__ruflo__agent_spawn(agentType: "brana:metrics-collector", model: "haiku", domain: "{venture_slug}", task: "Gather current metrics from Google Sheets, docs/metrics/, tasks.json")
   ```
   Collect the returned agentId for cost queries. Fall back to `Agent(subagent_type: "brana:metrics-collector")` if ruflo is unavailable.
3. **Portfolio health:** read tasks.json across portfolio clients, compute progress per project
4. **Zombie cleanup:** identify tasks older than 30 days with no activity — present for archival or reprioritization
5. **Metrics delta:** compare current metrics vs last week's stored values
6. **Ship log:** `git log --oneline --since="7 days ago"` across active clients
7. **Friction check:**
   ```bash
   brana session insights --limit 30 --json
   ```
   If `total < 3`, note "insufficient data ({N} sessions this week)" and omit the Friction section from the report.
   Surface `turbulent` and `blocked` sessions by label. Include `suggestions` array verbatim.
8. **Knowledge pipeline check:**
   ```bash
   brana knowledge process --status
   ```
   Count drafts in `brana-knowledge/drafts/`. If drafts > 0:
   - Surface count: "N draft(s) awaiting review in brana-knowledge/drafts/"
   - Print cluster report path: `~/.claude/knowledge-pipeline-report.md`
   - Prompt: "Promote, merge, reject, or defer each draft? Run `brana knowledge promote <path>` to promote."
   If pipeline hasn't run (no state file / all counts zero): note "Knowledge pipeline: no runs yet — enable scheduler job `knowledge-pipeline-tier1` or run `brana knowledge process --tier1 --dry-run` to test."
9. **Store trends:**
   ```bash
   source "$HOME/.claude/scripts/cf-env.sh"
   [ -n "$CF" ] && cd "$HOME" && $CF memory store \
     -k "review:weekly:{PROJECT}:{date}" \
     -v '{"type": "weekly-review", "metrics": {...}, "zombies": N, "shipped": N}' \
     --namespace business \
     --tags "client:{PROJECT},type:weekly-review" \
     --upsert
   ```
10. **Next-week planning:** based on bottleneck identified in metrics + unblocked tasks
11. **Write report** to `docs/reviews/weekly-YYYY-MM-DD.md`

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

### Knowledge Pipeline
Drafts pending review: {N} (cap: 10)
{list draft filenames if N > 0}
Cluster report: ~/.claude/knowledge-pipeline-report.md
{omit section if N = 0 and pipeline has run}

### Friction
{N} sessions: {clean} clean / {turbulent} turbulent / {blocked} blocked / {abandoned} abandoned
Avg correction rate: {X%}
{suggestions, if any}
{omit section if < 3 sessions this week}

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
   brana decisions read --entry-type cost --json
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

## /brana:review harness

Harness simplification check — every component encodes assumptions about model limitations. Re-evaluate after model upgrades to strip components that are no longer needed. Based on Anthropic's harness design principle: "strip components as models improve."

### Steps

1. **Inventory enforcement components** — scan the harness:
   ```bash
   # Hooks with gates/enforcement
   ls system/hooks/*.sh
   # Rules
   ls ~/.claude/rules/*.md 2>/dev/null
   # Profile tier settings
   echo "BRANA_HOOK_PROFILE=${BRANA_HOOK_PROFILE:-standard}"
   ```

2. **Classify each by assumption** — for each enforcement component, identify the model limitation it encodes:

   | Component | Assumption | Category |
   |-----------|-----------|----------|
   | `pre-tool-use.sh` (spec gate) | "Model won't follow TDD without enforcement" | Discipline |
   | `worktree-gate.sh` | "Model creates branches in dirty repos" | Safety |
   | `guard-explore.sh` | "Model reads without searching first" | Efficiency |
   | `context-budget rule (55%)` | "Context quality degrades past 55%" | Context |
   | `sdd-tdd rule` | "Model skips tests without explicit rule" | Discipline |
   | `git-discipline rule` | "Model commits to main without rule" | Safety |
   | Hook profile tiers | "Some hooks aren't needed in all contexts" | Optimization |

3. **Test assumptions against current model** — for each component:
   - Check guard-explore logs: `/tmp/brana-explore-*.log` (if available)
   - Check session flywheel metrics (correction_rate, test_write_rate) from ruflo
   - Review recent session handoffs for discipline violations
   - Note which model is in use (Opus 4.6 vs Sonnet 4.6 vs Haiku)

4. **Traffic-light each component:**
   - **Keep (green):** assumption still valid, enforcement prevents real failures
   - **Relax (yellow):** model improved, enforcement could be softened (e.g., warning instead of block)
   - **Remove (red):** model handles this natively, enforcement adds friction with no benefit

5. **Present report:**

   ```markdown
   ## Harness Simplification Check — YYYY-MM-DD

   **Model:** {current model}
   **Profile:** {current BRANA_HOOK_PROFILE}
   **Components audited:** {N}

   ### Assessment

   | Component | Assumption | Verdict | Evidence |
   |-----------|-----------|---------|----------|
   | spec gate | TDD needs enforcement | Keep | correction_rate still >15% |
   | worktree-gate | Dirty repo branching | Relax | 0 violations in 30 days |
   | guard-explore | Blind reads | TBD | Logging started {date}, review {date+7d} |
   | context-budget 55% | Quality degrades early | Relax | Opus 4.6 1M context, 55% may be too conservative |

   ### Recommended actions
   - {component}: {action} — {rationale}
   ```

6. **Don't auto-remove.** Present recommendations, let the user decide. Removing enforcement is a one-way door — only do it with evidence.

This check runs quarterly, or after a major model upgrade. It can be appended to `/brana:review monthly` output or invoked directly via `/brana:review harness`.

---

## Step E — EXTRACT

At review end, identify what was learned during the business health check:

1. Review findings from the completed review — what changed since last review, what metrics surprised, what decisions were implied by the data
2. Classify each finding using ontology entity types:
   - **Pattern** — recurring business pattern (e.g., "revenue dips in week 3 of month")
   - **FieldNote** — market or client observation (e.g., "client X churned after pricing change")
   - **Dimension** — topic worth researching deeper (e.g., "marketplace unit economics need a knowledge doc")
3. Review-specific: flag metrics that contradict previous assumptions or stored trends
4. Skip if review surfaced no new information beyond existing tracked metrics

## Step F — EVALUATE

Score each finding (0-10) on two axes:

| Axis | SMALL (0-1) | MEDIUM (2-4) | LARGE (5+) |
|------|------------|-------------|------------|
| **Scope** | Single metric, event log entry | Business pattern, client insight | Strategic shift, cross-client pattern |
| **Novelty** | Already tracked | New trend on known topic | Contradicts existing strategy |

**Gate by size:**
- **SMALL:** Auto-persist (no prompt). Metric snapshots, event log entries.
- **MEDIUM:** Inline eval — dedup via `mcp__ruflo__memory_search(query: "{finding summary}", namespace: "knowledge", limit: 2)` and `mcp__ruflo__memory_search(query: "{finding summary}", namespace: "pattern", limit: 2)`. If top result similarity > 0.9, skip or merge. Present remaining to user via AskUserQuestion.
- **LARGE:** Present to user with recommendation via AskUserQuestion. For strategic shifts or cross-client patterns, suggest `/brana:challenge` review.

## Step G — PERSIST

Route each accepted finding by type:

| Type | Destination | Auto/Prompted |
|------|------------|---------------|
| Pattern | `mcp__ruflo__memory_store(namespace: "pattern")` + memory file (tag: `transferable: true` for cross-client) | SMALL: auto, MEDIUM+: prompted |
| Strategic insight | `mcp__ruflo__memory_store(namespace: "business")` | Prompted |
| FieldNote | Append to relevant dimension doc `## Field Notes` | Prompted |
| Event | Event log via `/brana:log` | Auto |
| Metric | Session state JSON via `brana session write` | Auto |

For ruflo stores, use:
```
mcp__ruflo__memory_store(
  key: "pattern:{PROJECT}:{slug}",
  value: '{"finding": "...", "source": "review", "confidence": 0.6}',
  namespace: "pattern",
  tags: ["client:{PROJECT}", "source:review"],
  upsert: true
)
```

If ruflo unavailable, write to `~/.claude/projects/{project}/memory/` as markdown file.

---

## Rules

1. **Business model drives metrics.** Don't apply SaaS metrics to cycle-project businesses. Recompra > churn for non-subscription models.
2. **Stage drives scope.** Don't audit Scale metrics for a Validation business.
3. **Store trends consistently.** Every review stores a snapshot for comparison.
4. **Ask for data you can't find.** Don't guess metrics — ask the user or check data sources.
5. **Bottleneck → action.** Every review identifies the #1 bottleneck and proposes actions tied to it.
6. **Graceful degradation.** No Google Sheets → ask user. No ruflo → write to docs/reviews/ only.
