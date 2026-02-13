# Venture Management Guide

How to use brana to manage a business project — from first diagnostic to ongoing operations.

Brana was designed for software projects, but its learning loop is domain-agnostic: research, synthesize, plan, execute, debrief, maintain. The venture skills extend this loop to business management, using the same memory system, the same learning patterns, and the same session discipline.

---

## Table of Contents

1. [Overview](#1-overview)
2. [Getting Started](#2-getting-started)
3. [The Five Venture Skills](#3-the-five-venture-skills)
4. [Universal Skills That Transfer](#4-universal-skills-that-transfer)
5. [How Skills Interact](#5-how-skills-interact)
6. [The Document Structure](#6-the-document-structure)
7. [The Stage Model](#7-the-stage-model)
8. [Session Workflows](#8-session-workflows)
9. [The Learning System](#9-the-learning-system)
10. [Good Practices](#10-good-practices)
11. [Common Scenarios](#11-common-scenarios)
12. [Quick Reference](#12-quick-reference)

---

## 1. Overview

Brana gives you **5 venture-specific skills**, **1 venture agent**, and **7 universal skills** that transfer from code projects. Together they form a complete business management system.

```
VENTURE SKILLS                    UNIVERSAL SKILLS (transfer as-is)
──────────────                    ─────────────────────────────────
/venture-onboard  (diagnose)      /decide          (record decisions)
/venture-align    (build)         /retrospective   (store learnings)
/venture-phase    (execute)       /debrief         (end-of-session extraction)
/growth-check     (monitor)       /challenge       (stress-test plans)
/sop              (document)      /pattern-recall  (query past learnings)
                                  /cross-pollinate (pull from other projects)
                                  /knowledge-review(memory health check)
```

The venture skills create and maintain a `docs/` structure inside your project. The universal skills feed a cross-project memory system (ReasoningBank) that accumulates learnings over time.

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
- A project directory for your venture (can be empty or existing)
- Optionally: claude-flow for cross-project memory (works without it, just no persistent patterns)

---

## 3. The Five Venture Skills

### `/venture-onboard` — The Diagnostic

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

**What it produces:** A diagnostic report. No files created.

**Key rule:** This is read-only. It observes, it doesn't change. To act on its findings, use `/venture-align`.

**Example output:**
```
Stage: Validation
Framework: Lean Startup + light OKRs
Gaps:
  Critical: No revenue tracking, unknown retention
  Important: No OKRs, experiment log empty
  Nice-to-have: Financial dashboard
```

---

### `/venture-align` — The Builder

**Purpose:** Take the diagnostic and build the management structure.

**When to use:**
- After `/venture-onboard` identifies gaps
- Setting up a new venture from scratch
- When the stage changes and structure needs to evolve

**What it does (6 phases):**

```
DISCOVER ──→ ASSESS ──→ PLAN ──→ IMPLEMENT ──→ VERIFY ──→ DOCUMENT
    │           │         │          │             │           │
Interview   Checklist   Action    Create        Before/    Store in
or reuse    scored by   list you  files (asks   after      memory
onboard     stage       approve   permission)   score
```

**What it creates (depends on stage):**

| Stage | What gets created |
|-------|-------------------|
| All | CLAUDE.md, docs/decisions/, docs/metrics/, docs/meetings/cadence.md |
| + Validation | customer-hypothesis.md, mvp-definition.md, docs/experiments/ |
| + Growth | docs/okrs/, docs/sops/ (with index), hiring plan, decision framework |
| + Scale | Org chart, cascading OKRs, process automation docs, onboarding playbook |

**Key rule:** Asks for confirmation before every file. Never overwrites existing files — reads first, merges, or asks.

**Tip:** You don't need to create everything at once. `/venture-align` is pain-driven: fill the critical gaps first, come back for the rest when it hurts.

---

### `/venture-phase` — The Executor

**Purpose:** Plan and execute a specific business milestone with learning loops.

**When to use:** When you have a concrete milestone to execute — a product launch, hiring round, fundraise, expansion, process overhaul, or any custom milestone.

**Invocation:**
```
/venture-phase                    ← asks what milestone
/venture-phase product launch     ← plans a product launch
/venture-phase hiring             ← plans a hiring round
/venture-phase fundraise          ← plans a fundraise
/venture-phase expansion          ← plans market expansion
/venture-phase process            ← plans process overhaul
/venture-phase custom             ← you define the milestone
```

**The execution loop:**

```
┌─────────────────────────────────────────────────────┐
│  ORIENT                                              │
│  Identify milestone, detect stage, read context      │
│                                                      │
│  PLAN                                                │
│  Generate work items from template                   │
│  Present for approval — WAITS for your OK            │
│                                                      │
│  RECALL                                              │
│  Search memory for relevant patterns                 │
│                                                      │
│  EXECUTE (for each work item)                        │
│  ┌────────────────────────────────────┐              │
│  │ 1. State what's being done         │              │
│  │ 2. Create/update docs              │  repeats     │
│  │ 3. Verify exit criteria            │  for each    │
│  │ 4. Mini-debrief:                   │  work item   │
│  │    - Anything surprising?          │              │
│  │    - Anything reusable?            │              │
│  │    - Should the plan change?       │              │
│  │ 5. Store learning in memory        │              │
│  └────────────────────────────────────┘              │
│                                                      │
│  VALIDATE                                            │
│  Check all exit criteria are met                     │
│                                                      │
│  DEBRIEF                                             │
│  Full milestone debrief — errata + learnings         │
│                                                      │
│  REPORT                                              │
│  Summary: what was done, learned, next steps         │
└─────────────────────────────────────────────────────┘
```

**Pre-built milestone templates:**

| Milestone | Work Items |
|-----------|-----------|
| Product launch | Market research, positioning, channel strategy, launch checklist, go-to-market plan, post-launch metrics |
| Hiring | Role definition, job description, sourcing strategy, interview process (creates SOP), onboarding SOP |
| Fundraise | Pitch deck, financial model, investor list, outreach plan, term sheet prep |
| Expansion | Market research, positioning adaptation, channel testing, metrics framework, scale/pivot decision |
| Process overhaul | Current state audit, process debt inventory, prioritize, implement SOPs, verify |
| Custom | You define: name, work items, exit criteria, timeline |

**Key rule:** The plan in Step 1 is a proposal. You approve it. Exit criteria are non-negotiable — the milestone isn't complete if criteria aren't met.

**Tip:** One milestone per invocation. Don't try to run two milestones in one session. Finish one, debrief, then start the next.

---

### `/sop` — The Process Documenter

**Purpose:** Interview you about a repeatable process and produce a structured, versioned SOP.

**When to use:** When a process has repeated 3+ times and needs documenting.

**Invocation:**
```
/sop                          ← asks what process
/sop customer onboarding      ← documents the onboarding process
/sop weekly sync              ← documents the meeting process
```

**What it does:**
1. Interviews you (8 questions: what, who, trigger, frequency, steps, output, failure modes, success criteria)
2. Auto-increments the SOP number (SOP-001, SOP-002, ...)
3. Creates `docs/sops/SOP-NNN-slug.md` with full template
4. Updates `docs/sops/README.md` (index)
5. Stores pattern in ReasoningBank

**SOP template structure:**
```
Purpose → Owner → Trigger → Prerequisites
→ Steps (with decision points)
→ Exit Criteria → Common Issues → Metrics
→ Version → Last Updated → Next Review (6 months)
```

**Key rule:** Don't systematize too early. If you've only done a process once, it's too early for an SOP. Wait for 3+ repetitions. But when you do systematize, do it thoroughly — a vague SOP is worse than no SOP.

**Tip:** Decision points are the most valuable part. Real processes branch: "If the customer says X, do A. If they say Y, do B." An SOP without decision points only works for the happy path.

---

### `/growth-check` — The Health Monitor

**Purpose:** AARRR funnel analysis + stage-appropriate metrics audit. Identifies the bottleneck and recommends where to focus.

**When to use:**
- Monthly or quarterly (set a cadence and stick to it)
- Before major decisions (fundraise, expansion, hiring) to baseline health
- When something feels wrong and you need data

**What it does:**
1. Detects the business stage from existing docs
2. Collects stage-appropriate metrics (from docs or asks you)
3. Runs AARRR funnel analysis (Acquisition → Activation → Retention → Referral → Revenue)
4. Benchmarks each metric (GREEN / YELLOW / RED)
5. Identifies the bottleneck (worst conversion = where effort should focus)
6. Compares against previous checks for trend tracking
7. Saves report to `docs/metrics/health-YYYY-MM-DD.md`

**AARRR Funnel:**
```
Acquisition → Activation → Retention → Referral → Revenue
   How do      Do they      Do they     Do they    Do they
   users       get value    come        tell       pay?
   find you?   quickly?     back?       others?
```

The bottleneck is the stage with the worst conversion. Improving stages downstream of the bottleneck is wasted work — you're optimizing revenue when nobody activates.

**Benchmark thresholds (adapt for your domain):**

| Metric | GREEN | YELLOW | RED |
|--------|-------|--------|-----|
| LTV:CAC | ≥3:1 | 2:1-3:1 | <2:1 |
| Monthly churn | <3% | 3-7% | >7% |
| Gross margin | >70% | 50-70% | <50% |
| Net retention | >110% | 100-110% | <100% |
| Runway | >18 months | 12-18 months | <12 months |
| Activation rate | >30% | 15-30% | <15% |

**Key rule:** Don't fake data. If a metric isn't tracked, mark it "Not tracked" and recommend tracking it. Never estimate.

**Tip:** A single health check is useful. A series over time is powerful. The trend matters more than any single snapshot. Run it consistently and the comparisons become the most valuable output.

---

## 4. Universal Skills That Transfer

Seven skills designed for code projects work identically for business projects:

### `/decide [title]` — Record business decisions

Creates an Architecture Decision Record (ADR) in `docs/decisions/`. The format (Context, Decision, Consequences) works for "use JWT for auth" and "hire a COO before a CTO" equally.

**When to use:** Before any consequential, hard-to-reverse decision.

**Tip:** Business decisions are less reversible than code decisions — they benefit even more from structured records. "Why did we choose this market?" is a question you'll ask in 6 months. The ADR answers it.

### `/retrospective` — Store a single learning

Stores a pattern in ReasoningBank with confidence metadata. Use after notable discoveries, unexpected issues, or successful workarounds.

**When to use:** When something worth remembering happens mid-session. Not at the end (that's `/debrief`) — during.

**Example:** "Discovered that terapeuta referrals convert 3x better than Instagram leads."

### `/debrief` — End-of-session extraction

Extracts errata, learnings, and issues from the current session. Classifies them and stores in memory.

**When to use:** End of every significant work session.

**Tip:** This is the learning muscle. Skip it and learnings evaporate. Run it and they compound. Even a short session produces something worth storing.

### `/challenge` — Stress-test a plan

Spawns an adversarial review. Four flavors: pre-mortem, simplicity audit, assumption challenge, adversarial critique.

**When to use:** Before committing to a major decision. "Should we expand to 3 cities?" "Should we take this investment?" "Is our pricing right?"

**Tip:** Run this BEFORE you're emotionally committed. Once you've decided, confirmation bias makes the challenge less useful.

### `/pattern-recall` — Query past learnings

Searches ReasoningBank for patterns relevant to your current context.

**When to use:** Starting work on any topic, before deep planning, or when encountering a familiar problem.

**Tip:** This gets more valuable over time. Early on, there are few patterns. After 6 months of debriefs and retrospectives, the recall surface is rich.

### `/cross-pollinate` — Pull from other projects

Searches for transferable patterns from other projects in your portfolio.

**When to use:** When stuck on a problem, starting work in a new domain, or when you suspect another project solved a similar problem.

**Example cross-pollinations:**
- CI/CD rollback patterns → SOP fallback procedures
- Spec-driven development → Decision-before-action discipline
- Technical debt tracking → Process debt tracking
- Feature flag rollouts → Pilot program design

### `/knowledge-review` — Memory health check

Monthly review of ReasoningBank health: pattern count, confidence distribution, staleness, promotion candidates.

**When to use:** Monthly, or when the system feels stale.

---

## 5. How Skills Interact

```
                    ┌──────────────┐
                    │/venture-     │
                    │  onboard     │── Diagnoses stage and gaps
                    └──────┬───────┘
                           │ feeds into
                           ▼
                    ┌──────────────┐
                    │/venture-     │
                    │  align       │── Creates structure to fill gaps
                    └──────┬───────┘
                           │ produces
                           ▼
          ┌────────────────────────────────┐
          │        docs/ structure          │
          │  decisions, metrics, SOPs,      │
          │  meetings, experiments, etc.    │
          └──────┬──────────┬──────────┬───┘
                 │          │          │
        ┌────────▼──┐  ┌───▼──────┐  ┌▼──────────┐
        │/venture-  │  │/growth-  │  │  /sop     │
        │  phase    │  │  check   │  │           │
        │           │  │          │  │           │
        │ Executes  │  │ Monitors │  │ Documents │
        │milestones │  │ health   │  │ processes │
        └─────┬─────┘  └────┬─────┘  └─────┬────┘
              │             │               │
              │    all read and write docs/ │
              │             │               │
              ▼             ▼               ▼
        ┌─────────────────────────────────────────┐
        │            ReasoningBank                 │
        │  (cross-project patterns and learnings)  │
        │                                          │
        │  /retrospective  → stores learnings      │
        │  /debrief        → extracts from session │
        │  /pattern-recall → retrieves patterns    │
        │  /cross-pollinate→ pulls from elsewhere  │
        │  /decide         → records decisions     │
        │  /challenge      → stress-tests plans    │
        └─────────────────────────────────────────┘
```

**The key data flows:**
- `/venture-onboard` reads existing docs → produces diagnostic
- `/venture-align` reads diagnostic → creates docs
- `/venture-phase` reads docs (decisions, SOPs, metrics, OKRs) → creates new docs → debriefs after each work item
- `/growth-check` reads metrics → produces health report → stores snapshot for trend tracking
- `/sop` interviews you → creates SOP → updates index
- `/decide` interviews you → creates ADR
- `/debrief` reads session context → classifies learnings → stores in ReasoningBank
- `/pattern-recall` reads ReasoningBank → surfaces relevant past learnings

---

## 6. The Document Structure

The venture skills create and maintain this structure inside your project:

```
my-venture/
├── CLAUDE.md                          ← Project identity and business context
├── docs/
│   ├── decisions/                     ← /decide creates ADRs here
│   │   └── ADR-001-*.md              (auto-incrementing)
│   ├── metrics/                       ← /growth-check writes here
│   │   ├── README.md                  (current metrics table)
│   │   └── health-YYYY-MM-DD.md       (snapshots over time)
│   ├── meetings/                      ← /venture-align creates cadence
│   │   ├── cadence.md                 (meeting schedule)
│   │   └── YYYY-MM-DD-topic.md        (meeting notes)
│   ├── experiments/                   ← Track hypotheses
│   │   └── README.md                  (experiment log)
│   ├── sops/                          ← /sop creates SOPs here
│   │   ├── README.md                  (index of all SOPs)
│   │   ├── SOP-001-*.md
│   │   ├── SOP-002-*.md
│   │   └── SOP-NNN-*.md              (auto-incrementing)
│   ├── okrs/                          ← Growth stage+
│   │   └── Q1-2026.md                (quarterly OKRs)
│   ├── customer-hypothesis.md         ← Validation stage+
│   ├── mvp-definition.md              ← Validation stage+
│   ├── planning/                      ← Strategy and planning docs
│   ├── strategy/                      ← Go-to-market, customer journey
│   └── operations/                    ← Safety protocols, ops docs
└── csv/                               ← Reference data (optional)
```

**What goes where:**
- Permanent decisions → `docs/decisions/` (ADR format)
- Repeatable processes → `docs/sops/` (SOP format)
- Numbers and health → `docs/metrics/` (tables + snapshots)
- Meeting structure → `docs/meetings/` (cadence + notes)
- Experiments → `docs/experiments/` (hypothesis → result)
- Goals → `docs/okrs/` (quarterly objectives)
- Everything else → organize by topic (`planning/`, `strategy/`, `operations/`)

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
| **Framework** | Lean Startup / Customer Dev | Lean + light OKRs | EOS or Scaling Up + OKRs | EOS + cascading OKRs |
| **Metrics** | Interview count, hypothesis validation | MRR, retention, burn, runway | CAC, LTV, LTV:CAC, churn, margin | Rule of 40, NRR, burn multiple |
| **Meetings** | Weekly founder sync | Weekly team + monthly metrics | Daily + weekly L10 + monthly + quarterly | Full cadence stack |
| **SOPs** | None — too early | Only if process repeats 3x | All core processes | Everything + automation |
| **OKRs** | No | Light (1-2 objectives max) | Full quarterly (per team) | Cascading (company → department) |
| **Org design** | Flat, founder decides all | Functional leads emerge | Departments, RACI/RAPID | Divisions, two-pizza teams |

### Stage transition signals

| From → To | Signals | What to do |
|-----------|---------|------------|
| Discovery → Validation | First paying customers, repeatable interest | Run `/venture-onboard`, upgrade `/venture-align` |
| Validation → Growth | Repeatable revenue, product-market fit, $1M+ ARR | Run `/venture-onboard`, `/venture-align` for Growth structure, start formal OKRs |
| Growth → Scale | $10M+ ARR, 50+ people, multiple product lines | Run `/venture-onboard`, `/venture-align` for Scale structure |

**Key principle:** Don't adopt frameworks above your stage. EOS for a pre-PMF startup is harmful overengineering. Lean Startup for a scaling company is insufficient underengineering.

---

## 8. Session Workflows

### Starting a session

```
1. Open session in your venture project directory
   (system auto-recalls relevant patterns via session-start hook)

2. What are you doing today?

   Executing a milestone ──────→ /venture-phase [type]
   Documenting a process ──────→ /sop [name]
   Making a decision ──────────→ /decide [title]
   Checking business health ───→ /growth-check
   Reviewing a plan ───────────→ /challenge
   Looking for past learnings ─→ /pattern-recall
   Working on general tasks ───→ just work, use /decide and
                                  /retrospective as they come up

3. Work...

4. End of session
   └── /debrief (extracts learnings, stores in memory)
```

### Monthly cadence

```
Week 1:  /growth-check — health dashboard, identify bottleneck
Week 2:  Work on bottleneck — use /venture-phase if it's a milestone
Week 3:  Continue execution, /sop for any new repeatable process
Week 4:  /debrief the month, /knowledge-review for memory health
```

### Quarterly cadence

```
Start:   /venture-onboard — reassess stage (has it changed?)
         Update OKRs in docs/okrs/
         /venture-phase to plan the quarter's milestone

During:  Monthly growth-checks
         SOPs as processes stabilize
         /decide for any major decision

End:     /debrief the quarter
         /venture-onboard to measure progress
```

---

## 9. The Learning System

Every venture skill feeds a persistent learning system. This is what makes brana more than a template generator — it accumulates knowledge that gets smarter over time.

### How it works

```
SESSION ACTIVITY
     │
     ├── /retrospective ──→ stores individual learnings
     ├── /debrief ─────────→ extracts session-wide findings
     ├── /venture-phase ───→ mini-debriefs after each work item
     ├── /growth-check ────→ stores health snapshots
     ├── /sop ─────────────→ stores process patterns
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
     ├── /pattern-recall ──→ surfaces relevant patterns
     ├── /cross-pollinate ─→ pulls from other projects
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

Patterns from code projects can inform business projects and vice versa:

| Code Pattern | Business Application |
|-------------|---------------------|
| CI/CD pipeline design | Operational workflow — automated gates with rollback |
| Spec-driven development | Decision-before-action — write ADR before executing |
| Technical debt tracking | Process debt — same compounding dynamics |
| Feature flags / gradual rollout | Pilot programs — test in one market before expanding |
| Code review culture | Decision review — no major decision without ADR |
| Test coverage | Metric coverage — what % of AARRR stages are measured? |

---

## 10. Good Practices

### Do

- **Record every sale from day one.** Financial data is the foundation of every metric. Without it, `/growth-check` is blind.
- **Run `/growth-check` consistently.** Monthly minimum. The trend matters more than any single number.
- **End sessions with `/debrief`.** Learnings evaporate if not captured. Even a 2-minute debrief is worth it.
- **Use `/decide` for any hard-to-reverse decision.** "Why did we choose this?" is a question future-you will ask.
- **Let the stage drive the framework.** Don't adopt heavy processes before you need them. Don't stay informal when things are breaking.
- **Fill the data gaps before adding new structure.** A metrics template with "No data" in every cell is theater. Fill the cells first.
- **Use `/challenge` before committing.** Stress-test plans when you can still change them, not after.
- **Keep SOPs current.** A stale SOP is worse than no SOP — it gives false confidence. Review every 6 months.

### Don't

- **Don't systematize too early.** Wait until a process repeats 3+ times before writing an SOP. Premature systematization creates bureaucracy, not efficiency.
- **Don't skip the diagnostic.** `/venture-onboard` before `/venture-align`. Diagnosis before treatment. Always.
- **Don't run multiple milestones at once.** One `/venture-phase` at a time. Finish it, debrief it, then start the next one.
- **Don't fake metrics.** If you don't have the data, say "Not tracked." Estimates create false confidence.
- **Don't adopt frameworks above your stage.** EOS for a 2-person startup is cosplay. Lean Startup for a 50-person company is negligence.
- **Don't skip mini-debriefs.** Each work item in `/venture-phase` gets a mini-debrief. It takes 30 seconds and prevents losing learnings.
- **Don't overwrite existing docs.** All skills read first, then merge. If there's a conflict, they ask you.

### Tips

- **The bottleneck is the highest-leverage output of `/growth-check`.** You can read a dashboard. What you need is "here's where your effort should go and why."
- **ADRs work better for business decisions than code decisions** because business decisions are harder to reverse. "We hired a COO" can't be `git revert`ed.
- **SOPs should include decision points.** "If the customer says X, do A. If they say Y, do B." A linear SOP only covers the happy path.
- **Review meeting cadence every quarter.** Too many meetings kills deep work. Too few creates misalignment. Adjust based on pain, not theory.
- **Your KNOWLEDGE_EXTRACTION.md (or equivalent) is the founder brain dump.** Do it once, do it thoroughly. Every skill reads it for context.
- **The venture-scanner agent fires automatically** during `/venture-align`. You don't need to invoke it manually — it runs as part of the assessment phase.

---

## 11. Common Scenarios

### "I have a new business idea"

```
1. Create a project directory
2. /venture-onboard → probably Discovery stage
3. /venture-align   → creates lightweight Foundation structure
4. Don't write SOPs. Don't set OKRs. Focus on customer interviews.
5. /decide for the 2-3 big bets (market, channel, pricing)
6. /growth-check when you have first customers
```

### "I have customers but no structure"

```
1. /venture-onboard → probably Validation stage
2. /venture-align   → creates Validation structure (hypothesis, MVP, experiments)
3. Start recording every sale (SOP-003 pattern)
4. Contact ex-customers to understand retention
5. /growth-check after 30 days of data
6. /venture-phase custom → plan the operational sprint
```

### "We're growing but things are breaking"

```
1. /venture-onboard → probably Growth stage
2. /venture-align   → creates Growth structure (OKRs, SOPs, hiring plan)
3. /venture-phase process → process overhaul milestone
4. /sop for every core process (production, onboarding, sales, support)
5. /growth-check quarterly
6. /decide for org structure, framework selection, hiring priorities
```

### "I need to execute a specific milestone"

```
1. /venture-phase [type]
2. Review the generated work items
3. Approve or modify the plan
4. Execute work items one by one (each gets a mini-debrief)
5. Validate exit criteria
6. Full debrief → learnings stored
```

### "We're switching stages"

```
1. /venture-onboard → confirms new stage
2. /venture-align   → upgrades structure for new stage
3. /decide for framework transition (e.g., "Adopt EOS")
4. Review all existing SOPs — do they still apply?
5. Update meeting cadence — growth stage needs more structure
```

### "I want to check if the business is healthy"

```
1. /growth-check
2. Review the dashboard (GREEN/YELLOW/RED)
3. Look at the AARRR funnel — where's the bottleneck?
4. Compare against the previous check — what's trending?
5. Act on the top recommendation
```

### "End of a work session"

```
1. /debrief → extracts errata, learnings, issues
2. Review what was classified
3. Approve storage to ReasoningBank
4. Check if any findings warrant an ADR or SOP update
```

---

## 12. Quick Reference

### Skill invocations

| Skill | Invocation | Creates files? |
|-------|-----------|---------------|
| `/venture-onboard` | `/venture-onboard` | No (diagnostic only) |
| `/venture-align` | `/venture-align` | Yes (structure + templates) |
| `/venture-phase` | `/venture-phase [type]` | Yes (milestone docs) |
| `/sop` | `/sop [process name]` | Yes (SOP + index update) |
| `/growth-check` | `/growth-check` | Yes (health snapshot) |
| `/decide` | `/decide [title]` | Yes (ADR) |
| `/retrospective` | `/retrospective` | No (stores in memory) |
| `/debrief` | `/debrief` | No (stores in memory) |
| `/challenge` | `/challenge` | No (analysis only) |
| `/pattern-recall` | `/pattern-recall` | No (retrieves from memory) |
| `/cross-pollinate` | `/cross-pollinate` | No (retrieves from memory) |

### When to use what

| Situation | Skill |
|-----------|-------|
| First time on a project | `/venture-onboard` → `/venture-align` |
| Executing a business milestone | `/venture-phase [type]` |
| Process repeated 3+ times | `/sop [name]` |
| Monthly/quarterly health check | `/growth-check` |
| Important business decision | `/decide [title]` |
| Something surprising happened | `/retrospective` |
| End of work session | `/debrief` |
| About to commit to a big plan | `/challenge` |
| Starting work on any topic | `/pattern-recall` |
| Stuck or looking for prior art | `/cross-pollinate` |
| Memory feels stale | `/knowledge-review` |
| Stage may have changed | `/venture-onboard` (reassess) |

### Stage-appropriate frameworks

| Stage | Framework | Metrics Focus | Meeting Cadence |
|-------|-----------|---------------|-----------------|
| Discovery | Lean Startup | Qualitative (interviews, hypotheses) | Weekly sync (informal) |
| Validation | Lean + light OKRs | MRR, retention, burn, runway | Weekly + monthly |
| Growth | EOS/Scaling Up + OKRs | CAC, LTV, LTV:CAC, churn, margin | Daily + weekly + monthly + quarterly |
| Scale | EOS + cascading OKRs | Rule of 40, NRR, burn multiple | Full cadence stack |

### File locations

| What | Where |
|------|-------|
| Business decisions | `docs/decisions/ADR-NNN-*.md` |
| Standard operating procedures | `docs/sops/SOP-NNN-*.md` |
| Metrics + health snapshots | `docs/metrics/` |
| Meeting cadence + notes | `docs/meetings/` |
| Experiments | `docs/experiments/` |
| OKRs (Growth+) | `docs/okrs/` |
| Project identity | `CLAUDE.md` |
