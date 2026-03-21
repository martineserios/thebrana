---
name: venture-phase
description: "Plan and execute a business milestone — product launch, hiring, fundraise, expansion, or custom — with learning loops. Use when executing a business milestone (launch, hiring, fundraise, expansion)."
effort: high
argument-hint: "[launch|hiring|fundraise|expansion|process|custom]"
group: venture
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Glob
  - Grep
  - Task
  - AskUserQuestion
---

# Venture Phase

Plan and execute a business milestone with learning loops baked into the process. After each work item you debrief. After the milestone you capture all learnings. The business equivalent of `/build-phase`.

## When to use

When executing a specific business milestone: product launch, hiring round, fundraise, market expansion, process overhaul, or any custom milestone.

**Invocation:**
- `/brana:venture-phase` — ask what milestone
- `/brana:venture-phase product launch` — plan a product launch
- `/brana:venture-phase hiring` — plan a hiring round
- `/brana:venture-phase fundraise` — plan a fundraise
- `/brana:venture-phase expansion` — plan market expansion
- `/brana:venture-phase process` — plan process overhaul
- `/brana:venture-phase {custom}` — custom milestone

---

## Step Registry

On entry, create a CC Task step registry. Follow the [guided-execution protocol](../_shared/guided-execution.md).

Register these steps: ORIENT, PLAN, RECALL, EXECUTE, VALIDATE, DEBRIEF, REPORT.

---

## Step 0: Orient

### 0a: Identify the milestone

Parse `$ARGUMENTS` for milestone type:
- `launch` or `product launch` → Product Launch
- `hiring` or `hire` → Hiring Round
- `fundraise` or `funding` or `raise` → Fundraise
- `expansion` or `expand` or `market` → Market Expansion
- `process` or `overhaul` or `ops` → Process Overhaul
- Anything else → Custom (ask the user to define scope and work items)
- Empty → Ask the user what milestone they're working on

### 0b: Detect current stage

Check existing docs for stage indicators:
- Read `.claude/CLAUDE.md` for business context
- Check `docs/metrics/` for stage-appropriate metrics
- Check `docs/okrs/` for current objectives
- If stage unclear, ask the user

### 0c: Read context

Read relevant existing docs:
- `docs/decisions/` — past decisions that affect this milestone
- `docs/sops/` — existing processes that feed into this milestone
- `docs/metrics/` — current numbers that inform planning
- `docs/okrs/` — how this milestone connects to quarterly objectives

---

## Step 1: Plan

Based on milestone type, generate work items. Present to the user for approval before executing.

### Product Launch

**Pre-launch gates** — validate these before starting work items. If any gate is red, address it first:

| Gate | Question | Red Flag |
|------|----------|----------|
| **Timing** | Is the market ready? Are customers pulling for this? | Building ahead of demand, no inbound signal |
| **IP / Moat** | What's defensible? Documented? | Nothing proprietary, easily cloned |
| **Security / Trust** | Privacy, compliance, data handling baseline? | No security review, no ToS |
| **Partnerships** | Key ecosystem partners committed? | Launching into a vacuum, no distribution allies |
| **Distribution vector** | Where do target users already spend time? How do we embed there? | Requires users to adopt a new platform or change habits |

**Production readiness gates** — for launches involving deployed systems, validate these before work items:

| Gate | Question | Red Flag |
|------|----------|----------|
| **Pipeline isolation** | Are build, test, and deploy stages cleanly separated? | Monolithic script, no staging environment |
| **Reproducibility** | Can the system be rebuilt from source? Dependencies pinned? | "Works on my machine", unpinned deps |
| **Observability** | Monitoring, alerting, logging in place? | No visibility into production behavior |
| **Rollback** | Can you revert to previous version in < 5 minutes? | No rollback procedure, destructive migrations |
| **Cost controls** | Per-request/per-agent cost tracked? Budget caps set? | Unbounded API calls, no spending alerts |
| **Governance** | Security review done? Data handling documented? Compliance checked? | No security review, no ToS for user data |

Skip this table for milestones that don't involve deployed systems (e.g., market research, hiring).

| # | Work Item | Description | Exit Criteria |
|---|-----------|-------------|---------------|
| 1 | Market research | Competitive landscape, positioning gaps, target audience | Documented in docs/decisions/ |
| 2 | Positioning | Value proposition, messaging, differentiation | One-pager created |
| 3 | Channel strategy | Which channels, why, budget allocation. Prioritize channels where users already are — embed, don't demand adoption | Channel plan documented with distribution vector rationale |
| 4 | Launch checklist | Pre-launch, launch day, post-launch tasks | Checklist created in docs/ |
| 5 | Go-to-market plan | Timeline, milestones, responsibilities | Plan documented |
| 6 | Post-launch metrics | What to measure, targets, review cadence | Metrics framework in docs/metrics/ |

### Hiring Round

| # | Work Item | Description | Exit Criteria |
|---|-----------|-------------|---------------|
| 1 | Role definition | Responsibilities, skills, level, compensation range | Job spec in docs/ |
| 2 | Job description | External-facing posting, employer brand | JD created |
| 3 | Sourcing strategy | Where to find candidates, outreach templates | Strategy documented |
| 4 | Interview process | Stages, questions, rubric, decision criteria | SOP created via /sop |
| 5 | Onboarding SOP | First day, first week, first month | SOP created via /sop |

### Fundraise

| # | Work Item | Description | Exit Criteria |
|---|-----------|-------------|---------------|
| 1 | Pitch deck | Problem, solution, market, traction, team, ask | Deck outline documented |
| 2 | Financial model | Revenue projections, unit economics, use of funds | Model assumptions documented |
| 3 | Investor list | Target investors, warm intros, research | List in docs/ |
| 4 | Outreach plan | Sequence, follow-up cadence, materials | Process documented |
| 5 | Term sheet prep | Key terms to negotiate, walkaway points | ADR in docs/decisions/ |

### Market Expansion

| # | Work Item | Description | Exit Criteria |
|---|-----------|-------------|---------------|
| 1 | Market research | New market size, competition, regulations, culture | Research doc created |
| 2 | Positioning adaptation | What changes, what stays, localization needs | Documented |
| 3 | Channel testing | Test 2-3 channels with small budget | Experiment tracked |
| 4 | Metrics framework | What to measure for new market success | Added to docs/metrics/ |
| 5 | Scale or pivot decision | Decision criteria, timeline, review date | ADR in docs/decisions/ |

### Process Overhaul

| # | Work Item | Description | Exit Criteria |
|---|-----------|-------------|---------------|
| 1 | Current state audit | Document existing processes, measure performance | Audit doc created |
| 2 | Process debt inventory | What's broken, what's manual, what's redundant | Prioritized list |
| 3 | Prioritize improvements | Impact vs effort, dependencies | Ranked list with rationale |
| 4 | Implement SOPs | Create SOPs for top-priority processes | SOPs created via /sop |
| 5 | Verify improvements | Measure before/after, validate with team | Metrics comparison |

### Custom

Ask the user to define:
1. **Milestone name** — what are we calling this?
2. **Work items** — what are the steps?
3. **Exit criteria** — how do we know it's done?
4. **Timeline** — any deadlines?

**Wait for user approval before proceeding.**

---

## Step 2: Recall

Search for relevant patterns before executing:

```bash
source "$HOME/.claude/scripts/cf-env.sh"
```

If `$CF` is found:
```bash
# Search for milestone-specific patterns
cd "$HOME" && $CF memory search --query "milestone:{TYPE} business" --limit 10 2>/dev/null || true

# Search for stage-specific patterns
cd "$HOME" && $CF memory search --query "stage:{STAGE} venture" --limit 10 2>/dev/null || true

# Search for transferable patterns from code clients
cd "$HOME" && $CF memory search --query "transferable:true type:process" --limit 5 2>/dev/null || true
```

Fallback: grep `~/.claude/projects/*/memory/MEMORY.md` for relevant terms.

Summarize relevant patterns. Note which are high-confidence (proven) vs quarantined (unproven).

---

## Step 3: Execute

For each work item, follow this cycle:

```
┌─────────────────────────────────────────┐
│            FOR EACH WORK ITEM           │
│                                         │
│  1. State what you're doing             │
│  2. Create/update docs                  │
│  3. Verify exit criteria                │
│  4. Mini-debrief (see below)            │
│  5. Store learning in memory            │
│                                         │
│  → Next work item                       │
└─────────────────────────────────────────┘
```

### Mini-debrief (after each work item)

Quick extraction — not a full `/debrief`:

1. **Did anything surprise you?** An assumption that was wrong, a market dynamic that was unexpected.
2. **Did you discover something reusable?** A template, a framework, a question that should be asked in future milestones.
3. **Should the plan change?** Based on what you just learned, should remaining work items be reordered, added, or removed?

For each finding, store immediately:

```bash
cd "$HOME" && $CF memory store \
  -k "venture:{PROJECT}:{MILESTONE}:item-{N}:{short-id}" \
  -v '{"type": "venture-learning", "milestone": "...", "item": "...", "finding": "...", "severity": "..."}' \
  --namespace business \
  --tags "client:{PROJECT},type:venture-learning,milestone:{TYPE},stage:{STAGE}"
```

Fallback: append to `~/.claude/projects/{project-hash}/memory/MEMORY.md`.

---

## Step 4: Validate

After all work items are complete, check exit criteria:

```markdown
### Exit Criteria Check

- [x] criterion 1 — verified by [how]
- [x] criterion 2 — verified by [how]
- [ ] criterion 3 — NOT MET: [what's missing]
```

If any criteria are not met, create additional work items and loop back to Step 3.

---

## Step 5: Debrief

Spawn the `debrief-analyst` agent for a mini-debrief after milestone completion. Pass it the milestone type, work items completed, and any mini-debrief notes. Review its classified findings, then write approved entries to ReasoningBank.

If the agent is unavailable, run the debrief manually:

1. **Gather evidence** — all mini-debrief findings, docs created, decisions made.
2. **Classify** into:
   - **Errata** — things doc 28 or doc 29 got wrong about this milestone type
   - **Learnings** — things worth remembering for next time
   - **Issues** — things that remain unresolved
3. **Store in ReasoningBank:**

```bash
cd "$HOME" && $CF memory store \
  -k "venture:{PROJECT}:{MILESTONE}:debrief" \
  -v '{"type": "milestone-debrief", "milestone": "...", "work_items": N, "learnings": [...], "errata": [...], "issues": [...]}' \
  --namespace business \
  --tags "client:{PROJECT},type:milestone-debrief,milestone:{TYPE},stage:{STAGE},outcome:{success|partial|failed}"
```

---

## Step 6: Report

```markdown
## Milestone Complete: {Title}

**Type:** {Product Launch | Hiring | Fundraise | Expansion | Process | Custom}
**Stage:** {Discovery | Validation | Growth | Scale}
**Date:** {today}

### What was done
| # | Work Item | Output | Verified |
|---|-----------|--------|----------|
| 1 | {description} | {doc/artifact created} | {how} |

### What was learned
- **Learnings:** {N} entries stored in ReasoningBank
- **Errata:** {N} findings about doc 28/29 accuracy
- **Key insight:** {single most important thing learned}

### Exit criteria
- [x] criterion 1
- [x] all met / [ ] {N} not met

### What comes next
{Suggested follow-up actions based on milestone type and learnings}
```

---

## Rules

- **One milestone per invocation.** Don't try to run multiple milestones in one session.
- **Never skip the mini-debrief.** It takes 30 seconds and prevents losing learnings.
- **Wait for plan approval.** The plan in Step 1 is a proposal. The user decides.
- **Exit criteria are non-negotiable.** Don't declare a milestone complete if criteria aren't met.
- **Create docs, not just notes.** Every work item should produce a durable artifact in `docs/`.
- **Store results in ReasoningBank when available, fall back to auto memory when not.**
- **Ask for clarification whenever you need it.** If the milestone scope is unclear, work items seem wrong, or you need the user to make a decision — ask.
- **Step registry.** Follow the [guided-execution protocol](../_shared/guided-execution.md). Register steps on entry, update as each completes.

---

## Resume After Compression

If context was compressed and you've lost track of progress:

1. Call `TaskList` — find CC Tasks matching `/brana:venture-phase — {STEP}`
2. The `in_progress` task is your current step — resume from there
3. Check docs/ for artifacts already created by earlier steps
