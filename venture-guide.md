# Venture Management Guide

How to use brana to manage a business project — from first diagnostic to ongoing operations.

Brana was designed for software projects, but its learning loop is domain-agnostic: research, synthesize, plan, execute, debrief, maintain. The venture skills extend this loop to business management, using the same memory system, the same learning patterns, and the same session discipline.

---

## Table of Contents

1. [Overview](#1-overview)
2. [Getting Started](#2-getting-started)
3. [The Twelve Venture Skills](#3-the-twelve-venture-skills)
4. [Universal Skills That Transfer](#4-universal-skills-that-transfer)
5. [How Skills Interact](#5-how-skills-interact)
6. [The Document Structure](#6-the-document-structure)
7. [The Stage Model](#7-the-stage-model)
8. [Daily / Weekly / Monthly Cadences](#8-daily--weekly--monthly-cadences)
9. [Growth and Experiments](#9-growth-and-experiments)
10. [Financial Management](#10-financial-management)
11. [Sales Pipeline](#11-sales-pipeline)
12. [The Learning System](#12-the-learning-system)
13. [Good Practices](#13-good-practices)
14. [Common Scenarios](#14-common-scenarios)
15. [Quick Reference](#15-quick-reference)

---

## 1. Overview

Brana gives you **13 venture-specific skills**, **1 venture agent**, and **7 universal skills** that transfer from code projects. Together they form a complete business operating system.

```
VENTURE SKILLS (Foundation)           VENTURE SKILLS (Operations)
──────────────────────────           ───────────────────────────
/venture-onboard  (diagnose)         /morning         (daily check)
/venture-align    (build)            /weekly-review   (weekly cadence)
/venture-phase    (execute)          /pipeline        (sales tracking)
/growth-check     (monitor)          /experiment      (growth testing)
/sop              (document)         /financial-model (projections)
                                     /content-plan    (marketing)
                                     /monthly-close   (financial close)
                                     /monthly-plan    (forward planning)

UNIVERSAL SKILLS (transfer as-is)
─────────────────────────────────
/decide          (record decisions)
/retrospective   (store learnings)
/debrief         (end-of-session extraction)
/challenge       (stress-test plans)
/pattern-recall  (query past learnings)
/cross-pollinate (pull from other projects)
/knowledge-review(memory health check)
```

The foundation skills create and maintain a `docs/` structure inside your project. The operational skills run your daily, weekly, and monthly rhythms. The universal skills feed a cross-project memory system (ReasoningBank) that accumulates learnings over time.

---

## 2. Getting Started

### First-time setup (do this once per venture)

```
Step 1:  Navigate to your project directory
         cd ~/projects/my-venture

Step 2:  Run /venture-onboard
         Diagnoses the business: stage, gaps, framework recommendation.
         Read-only — doesn't create files. Just produces a report.

Step 3:  Run /venture-align
         Takes the diagnostic and builds the management structure:
         directories, templates, decision log, metrics, meeting cadence.
         Asks for confirmation before creating each file.
```

That's it. After these two steps you have a working management structure. Everything else is ongoing operations.

### Prerequisites

- Claude Code installed and configured
- Brana deployed (`./deploy.sh` from the thebrana repo)
- Venture extension deployed (`./deploy.sh` from this repo)
- A project directory for your venture (can be empty or existing)
- Optionally: claude-flow for cross-project memory (works without it, just no persistent patterns)
- Optionally: Google Workspace MCP for calendar integration
- Optionally: Airtable/HubSpot MCP for CRM integration

---

## 3. The Twelve Venture Skills

### Foundation Skills (thebrana core)

#### `/venture-onboard` — The Diagnostic

**Purpose:** Scan a business project, classify its stage, and produce a gap report.

**When to use:**
- First time entering a business project
- Periodic reassessment (every 3-6 months)
- After a major change (new funding, team doubles, pivot)
- When something feels off but you can't pinpoint it

**What it does:**
1. Interviews you (5 questions — skips what's already in docs)
2. Scans the project directory for business artifacts
3. Classifies the stage (Discovery / Validation / Growth / Scale)
4. Recommends stage-appropriate frameworks
5. Searches ReasoningBank for relevant patterns
6. Produces a prioritized gap report

**Key rule:** This is read-only. It observes, it doesn't change.

---

#### `/venture-align` — The Builder

**Purpose:** Take the diagnostic and build the management structure.

**When to use:**
- After `/venture-onboard` identifies gaps
- Setting up a new venture from scratch
- When the stage changes and structure needs to evolve

**What it does (6 phases):**

```
DISCOVER → ASSESS → PLAN → IMPLEMENT → VERIFY → DOCUMENT
```

**What it creates (depends on stage):**

| Stage | What gets created |
|-------|-------------------|
| All | CLAUDE.md, docs/decisions/, docs/metrics/, docs/meetings/cadence.md |
| + Validation | customer-hypothesis.md, mvp-definition.md, docs/experiments/ |
| + Growth | docs/okrs/, docs/sops/ (with index), hiring plan, decision framework |
| + Scale | Org chart, cascading OKRs, process automation docs, onboarding playbook |

**Key rule:** Asks for confirmation before every file. Never overwrites existing files.

---

#### `/venture-phase` — The Executor

**Purpose:** Plan and execute a specific business milestone with learning loops.

**Invocation:**
```
/venture-phase                    — asks what milestone
/venture-phase product launch     — plans a product launch
/venture-phase hiring             — plans a hiring round
/venture-phase fundraise          — plans a fundraise
/venture-phase expansion          — plans market expansion
/venture-phase process            — plans process overhaul
/venture-phase custom             — you define the milestone
```

**The execution loop:**
```
ORIENT → PLAN → RECALL → EXECUTE (per work item) → VALIDATE → DEBRIEF → REPORT
```

Each work item gets a mini-debrief: anything surprising? anything reusable? should the plan change?

**Key rule:** The plan is a proposal. You approve it. Exit criteria are non-negotiable.

---

#### `/sop` — The Process Documenter

**Purpose:** Interview you about a repeatable process and produce a structured, versioned SOP.

**When to use:** When a process has repeated 3+ times and needs documenting.

**What it does:**
1. Interviews you (8 questions: what, who, trigger, frequency, steps, output, failure modes, success criteria)
2. Auto-increments the SOP number (SOP-001, SOP-002, ...)
3. Creates `docs/sops/SOP-NNN-slug.md` with full template
4. Updates `docs/sops/README.md` (index)

**Key rule:** Don't systematize too early. Wait for 3+ repetitions.

---

#### `/growth-check` — The Health Monitor

**Purpose:** AARRR funnel analysis + stage-appropriate metrics audit.

**When to use:**
- Monthly or quarterly (set a cadence and stick to it)
- Before major decisions to baseline health
- When something feels wrong and you need data

**What it does:**
1. Detects the business stage
2. Collects stage-appropriate metrics
3. Runs AARRR funnel analysis (Acquisition → Activation → Retention → Referral → Revenue)
4. Benchmarks each metric (GREEN / YELLOW / RED)
5. Identifies the bottleneck
6. Compares against previous checks for trend tracking
7. Saves report to `docs/metrics/health-YYYY-MM-DD.md`

**Key rule:** Don't fake data. If a metric isn't tracked, mark it "Not tracked."

---

### Operational Skills (venture extension)

#### `/morning` — Daily Operational Check

**Purpose:** Stage-aware daily review that produces a focus card for the day.

**When to use:**
- Start of every work session on a venture project
- When you need to reorient after a break

**What it does:**
1. Detects stage from project docs
2. Pulls last `/growth-check` snapshot for current metrics
3. Shows blockers from task list
4. Surfaces Now priorities from portfolio
5. Checks calendar (if Google Workspace MCP configured)
6. Outputs today's focus card

**Output:** Focus card — 3 priorities, top blocker, key metric to watch.

**Stage-dependent:**
- Discovery: Light card — priorities + interview count
- Validation: Metrics + priorities + experiments status
- Growth/Scale: Full dashboard with team items

---

#### `/weekly-review` — Weekly Cadence

**Purpose:** The non-negotiable weekly practice. Updates portfolio, kills zombies, plans next week.

**When to use:**
- Friday or Monday (pick one, be consistent)
- Weekly — this is the highest-leverage meta-practice

**What it does:**
1. Portfolio update — green/yellow/red across all ventures
2. Kill zombies — flag initiatives untouched for 2+ weeks
3. Metrics delta — this week vs last week
4. Ship log — what was shipped this week
5. Plan next week's Now — 3-5 items max
6. Store trends in ReasoningBank

**Output:** Weekly review report at `docs/metrics/weekly-YYYY-MM-DD.md` + updated portfolio.

**Key rule:** 30 minutes, non-negotiable. Even a bad weekly review is better than no weekly review.

---

#### `/pipeline` — Sales/CRM Tracking

**Purpose:** Track leads, deals, conversions, and follow-ups. Stage-aware CRM.

**When to use:**
- New lead or contact to track
- Deal progresses to a new stage
- Reviewing pipeline health
- Preparing for sales-focused meetings

**What it does:**
1. Detects stage for appropriate pipeline complexity
2. Loads existing pipeline from `docs/pipeline/`
3. Updates lead/deal records
4. Calculates conversion rates between stages
5. Shows pipeline snapshot with follow-ups due

**Stage-dependent:**
- Discovery: Simple contact list
- Validation: Basic funnel (lead → trial → paid)
- Growth+: Full pipeline (lead → qualified → demo → proposal → negotiation → closed)

**Optional integrations:** Airtable MCP, HubSpot MCP for external CRM sync.

---

#### `/experiment` — Growth Testing Loop

**Purpose:** Structured experimentation with auto-incrementing records and ICE scoring.

**When to use:**
- `/growth-check` identifies a bottleneck to address
- Testing a new growth channel, feature, or pricing
- Any time you have a hypothesis to validate

**What it does:**
1. Reads `/growth-check` for bottleneck context
2. Interviews you: hypothesis, evidence, what would disprove it
3. Designs the test with ICE scoring (Impact x Confidence x Ease)
4. Sets measurable success criteria BEFORE running
5. Creates `docs/experiments/EXP-NNN-slug.md`
6. When returning to measure: records results, decides (scale/kill/iterate)
7. Stores learning in ReasoningBank

**The experiment loop:**
```
Hypothesis → Design → Success Criteria → Run → Measure → Learn → Decide
                                                              ↓
                                                   Scale / Kill / Iterate
```

**Key rule:** Define success criteria before running. Post-hoc criteria are meaningless.

---

#### `/financial-model` — Revenue Projections

**Purpose:** 3-scenario revenue projection, P&L template, unit economics, cash flow analysis.

**When to use:**
- Fundraise preparation
- Monthly or quarterly planning
- When investors ask for projections
- Building a business case for expansion

**What it does:**
1. Detects business model type (SaaS, marketplace, service, e-commerce)
2. Builds 3-scenario revenue projection (base/upside/downside)
3. P&L template with stage-appropriate line items
4. Unit economics: CAC, LTV, LTV:CAC, payback period
5. Cash flow analysis: burn rate, runway, break-even
6. Outputs to `docs/financial/model-YYYY-MM.md`

**Key rule:** Use actual data where available. Mark assumptions explicitly.

---

#### `/content-plan` — Marketing Cadence

**Purpose:** Quarterly content strategy aligned to growth goals.

**When to use:**
- Quarterly content planning
- Launching a new content channel
- When `/growth-check` shows acquisition as the bottleneck

**What it does:**
1. Reads `/growth-check` for acquisition metrics
2. Defines content themes and pillars
3. Selects stage-appropriate channels
4. Builds quarterly calendar with weekly cadence
5. Creates distribution checklist per content piece
6. Sets up performance tracking
7. Outputs to `docs/content/plan-YYYY-QN.md`

**Stage-dependent channels:**
- Discovery: Founder's blog, social, community
- Validation: + newsletter, guest posts, partnerships
- Growth: + paid content, SEO, video
- Scale: + PR, analyst relations, thought leadership

---

#### `/monthly-close` — Monthly Financial Close

**Purpose:** The monthly heartbeat of business health. P&L summary, actuals vs projections, trend analysis.

**When to use:**
- End of each month
- Preparing for board or investor updates
- When you need a comprehensive financial picture

**What it does:**
1. Pulls `/growth-check` snapshots for the full month
2. Compares actuals vs `/financial-model` projections
3. P&L summary (revenue, COGS, expenses, net income)
4. Metrics vs targets with variance analysis
5. MoM trend analysis across key metrics
6. Cash flow update: burn rate, runway, break-even
7. Outputs to `docs/financial/close-YYYY-MM.md`
8. Stores snapshot in ReasoningBank for historical tracking

**Key rule:** Run this even if you don't have perfect data. Partial closes build the habit.

---

#### `/monthly-plan` — Forward-Looking Monthly Plan

**Purpose:** Synthesize accumulated data into next month's action plan — revenue targets, priorities, experiments, pipeline actions, budget.

**When to use:**
- End of month (after `/monthly-close`)
- Start of a new month when planning
- Before board meetings or quarterly planning

**What it does:**
1. Gathers data from 6 sources: `/monthly-close`, `/growth-check`, `/pipeline`, `/experiment`, `/financial-model`, `/weekly-review`
2. Sets revenue target (3 scenarios: conservative/base/stretch)
3. Derives 3-5 priorities tied to bottleneck data
4. Lists running experiments + proposes 1-2 new ones
5. Identifies pipeline actions (overdue follow-ups, stalled deals)
6. Allocates budget by category with runway impact
7. Compiles key dates for the month
8. Outputs to `docs/planning/plan-YYYY-MM.md`
9. Stores snapshot in ReasoningBank

**Key rule:** The plan is a proposal — every priority references a data source. Run `/monthly-close` first if no close exists for the prior month.

**GitHub Issues:** Optionally, venture skills can create GitHub Issues for action items (`/weekly-review`), experiments (`/experiment`), and blockers (`/morning`). Issues are a secondary queryable index — markdown stays primary.

---

## 4. Universal Skills That Transfer

Seven skills designed for code projects work identically for business projects:

| Skill | Purpose | Business Use |
|-------|---------|-------------|
| `/decide [title]` | Record decisions as ADRs | "Why did we pick this market?" — ADRs answer it in 6 months |
| `/retrospective` | Store a single learning | "Referrals convert 3x better than Instagram leads" |
| `/debrief` | End-of-session extraction | Extracts errata, learnings, issues from current session |
| `/challenge` | Stress-test a plan | "Should we expand to 3 cities?" — adversarial review |
| `/pattern-recall` | Query past learnings | Starting work on any topic, encountering a familiar problem |
| `/cross-pollinate` | Pull from other projects | CI/CD patterns → operational workflows |
| `/knowledge-review` | Memory health check | Monthly review of ReasoningBank health |

Business decisions are harder to reverse than code decisions. ADRs, challenges, and debriefs are even more valuable in the business domain.

---

## 5. How Skills Interact

```
                    ┌──────────────────────┐
                    │  /venture-onboard    │── Diagnoses stage and gaps
                    └──────────┬───────────┘
                               │ feeds into
                               ▼
                    ┌──────────────────────┐
                    │  /venture-align      │── Creates structure to fill gaps
                    └──────────┬───────────┘
                               │ produces
                               ▼
          ┌────────────────────────────────────────┐
          │            docs/ structure              │
          │  decisions, metrics, SOPs, meetings,    │
          │  experiments, financial, pipeline,      │
          │  content, OKRs                          │
          └───┬────────┬────────┬────────┬────────┬┘
              │        │        │        │        │
     ┌────────▼──┐ ┌───▼────┐ ┌▼─────┐ ┌▼─────┐ ┌▼──────────┐
     │/venture-  │ │/growth-│ │/sop  │ │/pipe-│ │/experiment│
     │  phase    │ │  check │ │      │ │ line │ │           │
     │ Executes  │ │Monitors│ │Docs  │ │Tracks│ │ Tests     │
     │milestones │ │ health │ │procs │ │sales │ │ growth    │
     └─────┬─────┘ └───┬────┘ └──┬───┘ └──┬───┘ └─────┬────┘
           │           │         │        │            │
           │    ┌──────▼──────────────────▼────────────▼──┐
           │    │  /morning (daily) ← reads snapshots     │
           │    │  /weekly-review   ← reads all outputs   │
           │    │  /monthly-close   ← reads month data    │
           │    │  /monthly-plan    ← reads all 6 sources │
           │    │  /financial-model ← reads actuals       │
           │    │  /content-plan    ← reads metrics       │
           │    └─────────────────────────────────────────┘
           │
           ▼
     ┌──────────────────────────────────────────────┐
     │             ReasoningBank                     │
     │   (cross-project patterns and learnings)      │
     │                                               │
     │   /retrospective  → stores learnings          │
     │   /debrief        → extracts from session     │
     │   /pattern-recall → retrieves patterns        │
     │   /cross-pollinate→ pulls from elsewhere      │
     │   /decide         → records decisions         │
     │   /challenge      → stress-tests plans        │
     └──────────────────────────────────────────────┘
```

**Key data flows:**
- `/venture-onboard` reads existing docs → produces diagnostic
- `/venture-align` reads diagnostic → creates docs structure
- `/growth-check` reads metrics → stores snapshots → feeds `/morning`, `/weekly-review`, `/monthly-close`
- `/pipeline` tracks deals → feeds `/growth-check` and `/monthly-close`
- `/experiment` reads bottleneck from `/growth-check` → stores results → feeds `/weekly-review`
- `/financial-model` builds projections → `/monthly-close` compares actuals vs plan
- `/content-plan` reads `/growth-check` acquisition data and `/experiment` results
- `/morning` aggregates snapshots → daily focus card
- `/weekly-review` aggregates the week → portfolio + plan
- `/monthly-close` aggregates the month → financial summary
- `/monthly-plan` reads all 6 sources → forward-looking action plan (revenue targets, priorities, experiments, pipeline actions, budget)

---

## 6. The Document Structure

The venture skills create and maintain this structure inside your project:

```
my-venture/
├── CLAUDE.md                          ← Project identity and business context
├── docs/
│   ├── decisions/                     ← /decide creates ADRs here
│   │   └── ADR-001-*.md              (auto-incrementing)
│   ├── metrics/                       ← /growth-check, /morning, /weekly-review
│   │   ├── README.md                  (current metrics table)
│   │   ├── health-YYYY-MM-DD.md       (growth-check snapshots)
│   │   └── weekly-YYYY-MM-DD.md       (weekly review reports)
│   ├── meetings/                      ← /venture-align creates cadence
│   │   ├── cadence.md                 (meeting schedule)
│   │   └── YYYY-MM-DD-topic.md        (meeting notes)
│   ├── experiments/                   ← /experiment tracks hypotheses
│   │   ├── README.md                  (experiment index)
│   │   └── EXP-NNN-slug.md           (auto-incrementing)
│   ├── financial/                     ← /financial-model, /monthly-close
│   │   ├── model-YYYY-MM.md           (revenue projections)
│   │   └── close-YYYY-MM.md           (monthly close reports)
│   ├── pipeline/                      ← /pipeline tracks deals
│   │   └── README.md                  (current pipeline state)
│   ├── content/                       ← /content-plan tracks marketing
│   │   └── plan-YYYY-QN.md           (quarterly content plans)
│   ├── sops/                          ← /sop creates SOPs here
│   │   ├── README.md                  (index of all SOPs)
│   │   └── SOP-NNN-slug.md           (auto-incrementing)
│   ├── okrs/                          ← Growth stage+
│   │   └── QN-YYYY.md                (quarterly OKRs)
│   ├── customer-hypothesis.md         ← Validation stage+
│   └── mvp-definition.md              ← Validation stage+
└── csv/                               ← Reference data (optional)
```

---

## 7. The Stage Model

The entire system adapts based on the business stage. Stage classification happens in `/venture-onboard` and drives everything downstream.

### The four stages

```
DISCOVERY ──────→ VALIDATION ──────→ GROWTH ──────→ SCALE
 "Do we have      "Do we have        "Can we         "Can we sustain
  a problem        product-market     scale this      growth without
  worth            fit?"              repeatably?"    the founder in
  solving?"                                           every decision?"
```

### What changes at each stage

| | Discovery | Validation | Growth | Scale |
|--|-----------|------------|--------|-------|
| **Framework** | Lean Startup | Lean + light OKRs | EOS/Scaling Up + OKRs | EOS + cascading OKRs |
| **Metrics** | Qualitative | MRR, retention, burn | CAC, LTV, LTV:CAC, churn | Rule of 40, NRR, burn multiple |
| **Meetings** | Weekly sync | Weekly + monthly | Daily + weekly + monthly + quarterly | Full cadence stack |
| **SOPs** | None | Only if 3x repeated | All core processes | Everything + automation |
| **OKRs** | No | Light (1-2 max) | Full quarterly | Cascading |
| **Pipeline** | Contact list | Basic funnel | Full CRM | Multi-segment |
| **Financial** | Burn tracking | Basic P&L | Full model + unit economics | Departmental P&L |
| **Content** | Founder's voice | Newsletter + social | Multi-channel | Full content org |

### Stage transition signals

| From → To | Signals |
|-----------|---------|
| Discovery → Validation | First paying customers, repeatable interest |
| Validation → Growth | Repeatable revenue, product-market fit, $1M+ ARR |
| Growth → Scale | $10M+ ARR, 50+ people, multiple product lines |

**Key principle:** Don't adopt frameworks above your stage.

---

## 8. Daily / Weekly / Monthly Cadences

### The Daily Rhythm

```
1. Open session → /morning
   ← Focus card: 3 priorities, top blocker, key metric

2. Work on priorities
   ← Use /pipeline for sales, /experiment for testing,
     /decide for decisions, /retrospective for learnings

3. End of session → /debrief
   ← Extracts learnings, stores in memory
```

The `/morning` skill adapts to stage:
- **Discovery:** Light — priorities + interview count. No standup to yourself.
- **Validation:** Metrics snapshot + priorities + experiment status.
- **Growth/Scale:** Full dashboard with team items and calendar.

### The Weekly Rhythm

```
Every [Friday/Monday]:

/weekly-review
├── Portfolio: green/yellow/red for each venture
├── Zombie check: anything untouched 2+ weeks?
├── Metrics delta: this week vs last
├── Ship log: what got done
├── Plan: 3-5 Now items for next week
└── Store: trends saved for future recall
```

This is the non-negotiable meta-practice. 30 minutes. Even a bad weekly review beats no weekly review.

### The Monthly Rhythm

```
Week 1:  /growth-check — health dashboard, identify bottleneck
Week 2:  Work on bottleneck — /experiment if testing, /venture-phase if milestone
Week 3:  Continue execution, /sop for any new repeatable process
Week 4:  /monthly-close → /monthly-plan → /debrief the month → /knowledge-review

Monthly touchpoints:
├── /growth-check (health baseline)
├── /monthly-close (financial summary — backward-looking)
├── /monthly-plan (action plan — forward-looking)
├── /financial-model update (if projections changed)
└── /content-plan review (is content on track?)
```

### The Quarterly Rhythm

```
Start of quarter:
├── /venture-onboard — reassess stage (has it changed?)
├── Update OKRs in docs/okrs/
├── /venture-phase to plan the quarter's milestone
├── /financial-model for the quarter's projections
└── /content-plan for the quarter's content strategy

During quarter:
├── Monthly growth-checks + monthly-closes
├── Weekly reviews (non-negotiable)
├── /sop as processes stabilize
├── /experiment for growth testing
└── /decide for major decisions

End of quarter:
├── /debrief the quarter
├── /venture-onboard to measure progress
└── /growth-check → compare to quarter start
```

---

## 9. Growth and Experiments

### The Growth Experiment Loop

Every growth initiative should follow the experiment loop:

```
Identify bottleneck (/growth-check)
    ↓
Form hypothesis
    ↓
Design test (/experiment)
    ↓
Set success criteria (BEFORE running)
    ↓
Run test → track results
    ↓
Measure → compare to criteria
    ↓
Decide: Scale / Kill / Iterate
    ↓
Record learning (ReasoningBank)
```

### ICE Scoring

Prioritize experiments with ICE scores:

| Factor | 1 (Low) | 5 (Medium) | 10 (High) |
|--------|---------|-----------|-----------|
| **Impact** | Marginal improvement | Noticeable improvement | Game-changing |
| **Confidence** | Pure speculation | Some evidence | Strong evidence |
| **Ease** | Months of work | Weeks | Days or hours |

Score = (Impact + Confidence + Ease) / 3. Run experiments with highest ICE scores first.

### Experiment Discipline

- **One variable at a time.** Testing price AND channel simultaneously means you can't attribute results.
- **Time-bound.** Every experiment has a deadline. No indefinite "let's see what happens."
- **Kill quickly.** If results are clearly negative at 50% of the timeline, kill it.
- **Document everything.** Future-you (or your team) will ask "did we try X?" The experiment log answers it.

---

## 10. Financial Management

### The Financial Skill Stack

```
/financial-model   — Build projections (forward-looking)
/monthly-close     — Summarize actuals (backward-looking)
/growth-check      — Track key metrics (ongoing)
/pipeline          — Track revenue attribution (deals → revenue)
```

### Financial Model Types

| Business Model | Key Revenue Drivers | Key Metrics |
|----------------|-------------------|-------------|
| SaaS | MRR × customer count | MRR, ARR, churn, LTV:CAC |
| Marketplace | GMV × take rate | GMV, take rate, liquidity |
| Service/Consulting | Rate × hours/projects | Utilization, project margin |
| E-commerce | Orders × AOV | AOV, repeat rate, COGS |

### The Monthly Close Habit

Even pre-revenue companies benefit from a monthly close:
- **Discovery:** Track burn rate and runway. That's it.
- **Validation:** Add MRR, basic P&L.
- **Growth:** Full P&L, unit economics, variance analysis.
- **Scale:** Departmental P&L, cash flow forecasting, board-ready metrics.

The `/monthly-close` skill adapts the template to your stage.

### Unit Economics

```
CAC = Total acquisition spend / New customers acquired
LTV = Average revenue per customer × Average customer lifetime
LTV:CAC = Should be ≥ 3:1 for healthy business
Payback = CAC / Monthly revenue per customer (in months)
Gross Margin = (Revenue - COGS) / Revenue
```

Track these monthly. The trend matters more than any single number.

---

## 11. Sales Pipeline

### Pipeline Stages

The `/pipeline` skill uses stage-appropriate pipeline complexity:

**Discovery:**
```
Contact List: Name | Company | Notes | Status (interested/not interested)
```

**Validation:**
```
Lead → Trial → Paid
```

**Growth+:**
```
Lead → Qualified → Demo → Proposal → Negotiation → Closed Won / Closed Lost
```

### Pipeline Metrics

| Metric | What | Why It Matters |
|--------|------|---------------|
| Conversion rate per stage | % that advance to next stage | Identifies where deals stall |
| Average deal size | Revenue per closed deal | Revenue forecasting |
| Sales cycle length | Days from lead to close | Forecasting + resource planning |
| Pipeline value | Sum of all active deals × probability | Revenue forecast |
| Follow-ups due | Deals requiring action | Prevents leads going cold |

### CRM Integration

The `/pipeline` skill works in two modes:
1. **Markdown mode** (default) — all data in `docs/pipeline/`. Simple, version-controlled, no external dependencies.
2. **MCP mode** (optional) — syncs with Airtable or HubSpot via MCP servers. External CRM is the source of truth, `/pipeline` reads and writes through MCP tools.

---

## 12. The Learning System

Every venture skill feeds a persistent learning system. This is what makes brana more than a template generator — it accumulates knowledge that gets smarter over time.

### How it works

```
SESSION ACTIVITY
     │
     ├── /retrospective  → stores individual learnings
     ├── /debrief        → extracts session-wide findings
     ├── /venture-phase   → mini-debriefs after each work item
     ├── /growth-check    → stores health snapshots
     ├── /experiment      → stores experiment results + learnings
     ├── /monthly-close   → stores financial snapshots
     ├── /sop            → stores process patterns
     │
     ▼
REASONINGBANK (cross-project memory)
     │
     ├── confidence scoring (0.0 to 1.0)
     ├── quarantine period (new patterns start at 0.5)
     ├── promotion (3 successful recalls → higher confidence)
     ├── demotion (contradicted by evidence → lower confidence)
     │
     ▼
FUTURE SESSIONS
     │
     ├── /pattern-recall  → surfaces relevant patterns
     ├── /cross-pollinate → pulls from other projects
     ├── /morning         → auto-recalls context
     └── session-start hook → auto-recalls context
```

### Business-specific tags

ReasoningBank entries are tagged for retrieval:

```
stage:      discovery, validation, growth, scale
domain:     saas, marketplace, service, ecommerce, consulting
framework:  eos, okrs, scaling-up, shape-up, lean-startup
milestone:  launch, hiring, fundraise, expansion, process
metric:     mrr, cac, ltv, churn, arr, nrr
```

### Cross-project learning

Patterns from code projects inform business projects and vice versa:

| Code Pattern | Business Application |
|-------------|---------------------|
| CI/CD pipeline design | Operational workflow with automated gates |
| Spec-driven development | Decision-before-action discipline |
| Technical debt tracking | Process debt — same compounding dynamics |
| Feature flags / gradual rollout | Pilot programs — test one market first |
| Code review culture | Decision review — ADR before executing |
| Test coverage | Metric coverage — what % of AARRR is measured? |

---

## 13. Good Practices

### Do

- **Record every sale from day one.** Financial data is the foundation. Without it, everything is blind.
- **Run `/growth-check` consistently.** Monthly minimum. The trend matters more than any single number.
- **End sessions with `/debrief`.** Even a 2-minute debrief is worth it.
- **Use `/morning` to start sessions.** 5 minutes of orientation prevents hours of wandering.
- **Run `/weekly-review` non-negotiably.** This is the single highest-leverage practice.
- **Use `/decide` for hard-to-reverse decisions.** Future-you will ask "why?"
- **Let the stage drive the framework.** Don't over-engineer. Don't under-engineer.
- **Fill data gaps before adding structure.** Templates with "No data" in every cell is theater.
- **Use `/challenge` before committing.** Stress-test when you can still change.
- **Keep SOPs current.** Review every 6 months. Stale SOPs give false confidence.

### Don't

- **Don't systematize too early.** Wait for 3+ repetitions before writing an SOP.
- **Don't skip the diagnostic.** `/venture-onboard` before `/venture-align`. Always.
- **Don't run multiple milestones at once.** One `/venture-phase` at a time.
- **Don't fake metrics.** "Not tracked" is better than an estimate.
- **Don't adopt frameworks above your stage.** EOS for 2 people is cosplay.
- **Don't skip mini-debriefs.** 30 seconds per work item prevents losing learnings.
- **Don't overwrite existing docs.** All skills read first, then merge.
- **Don't define success criteria after the experiment.** That's confirmation bias.

---

## 14. Common Scenarios

### "I have a new business idea"

```
1. mkdir ~/projects/my-idea && cd ~/projects/my-idea
2. /venture-onboard → probably Discovery stage
3. /venture-align   → creates lightweight structure
4. Don't write SOPs. Don't set OKRs. Focus on customer interviews.
5. /decide for the 2-3 big bets (market, channel, pricing)
6. /growth-check when you have first customers
```

### "I have customers but no structure"

```
1. /venture-onboard → probably Validation stage
2. /venture-align   → creates Validation structure
3. /pipeline to start tracking every sale
4. Contact ex-customers to understand retention
5. /growth-check after 30 days of data
6. /experiment for your first growth test
```

### "We're growing but things are breaking"

```
1. /venture-onboard → probably Growth stage
2. /venture-align   → creates Growth structure (OKRs, SOPs, hiring plan)
3. /venture-phase process → process overhaul milestone
4. /sop for every core process
5. /financial-model for projections
6. /growth-check quarterly, /monthly-close monthly
```

### "I need to raise money"

```
1. /growth-check → baseline metrics
2. /financial-model → 3-scenario projections
3. /venture-phase fundraise → pitch prep milestone
4. /monthly-close → clean financials
5. /challenge → stress-test the pitch
```

### "I want to grow faster"

```
1. /growth-check → identify the AARRR bottleneck
2. /experiment → design a test for the bottleneck
3. /content-plan → if acquisition is the bottleneck
4. /pipeline → if conversion is the bottleneck
5. /weekly-review → track experiment progress
```

### "End of month"

```
1. /monthly-close → financial summary (backward-looking)
2. /monthly-plan  → action plan for next month (forward-looking)
3. /growth-check → health dashboard
4. Review: actuals vs projections → adjust /financial-model if needed
5. /debrief → extract month's learnings
```

### "End of quarter"

```
1. /venture-onboard → has the stage changed?
2. /monthly-close for Q's last month
3. Compare Q's OKRs to actuals
4. /venture-phase to plan next quarter
5. Update /financial-model for next quarter
6. /content-plan for next quarter
```

### "I want to check business health"

```
1. /growth-check → GREEN/YELLOW/RED dashboard
2. Look at AARRR funnel → where's the bottleneck?
3. Compare to previous check → what's trending?
4. /challenge if something looks concerning
5. Act on the top recommendation
```

---

## 15. Quick Reference

See `quick-reference.md` for the condensed one-page version.

### All skill invocations

| Skill | Invocation | Creates Files? |
|-------|-----------|---------------|
| `/venture-onboard` | `/venture-onboard` | No |
| `/venture-align` | `/venture-align` | Yes |
| `/venture-phase` | `/venture-phase [type]` | Yes |
| `/sop` | `/sop [process name]` | Yes |
| `/growth-check` | `/growth-check` | Yes |
| `/morning` | `/morning` | No |
| `/weekly-review` | `/weekly-review` | Yes |
| `/pipeline` | `/pipeline` | Yes |
| `/experiment` | `/experiment` | Yes |
| `/financial-model` | `/financial-model` | Yes |
| `/content-plan` | `/content-plan` | Yes |
| `/monthly-close` | `/monthly-close` | Yes |
| `/monthly-plan` | `/monthly-plan` | Yes |
| `/decide` | `/decide [title]` | Yes |
| `/retrospective` | `/retrospective` | No |
| `/debrief` | `/debrief` | No |
| `/challenge` | `/challenge` | No |
| `/pattern-recall` | `/pattern-recall` | No |
| `/cross-pollinate` | `/cross-pollinate` | No |
| `/knowledge-review` | `/knowledge-review` | No |
