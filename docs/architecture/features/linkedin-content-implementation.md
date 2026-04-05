---
depends_on:
  - dimensions/28-startup-smb-management.md
---
# LinkedIn Content Pipeline — Implementation Design

**Date:** 2026-03-03
**Status:** designing
**Feature brief:** [brief.md](brief.md)
**Challenger review:** [challenge](challenge-2026-03-03.md)
**Positioning research:** [t-170 research](research-positioning-2026-03-03.md)

---

## 0. Overview

```
THE LINKEDIN CONTENT PIPELINE — OVERVIEW
═══════════════════════════════════════════

WHO YOU ARE:  AI Systems Designer
              LLMs write code. You design systems.
              Brana is the documented proof.

WHO CARES:    AI engineers, tech leads, CTOs
              $11-14B market, 26% CAGR, niche unoccupied


═══════════════════════════════════════════════════════════════════════


PHASE 0                PHASE A              PHASE B
Strategy               Foundation           Manual Validation
(weeks 0-1)            (weeks 1-3)          (weeks 3-7)
───────────            ──────────           ────────────────

┌──────────┐          ┌──────────┐         ┌────────────────┐
│ Position │          │ Templates│         │ Publish 12     │
│ research │──────→   │ Calendar │───→     │ posts yourself │
│ Voice    │          │ First 6  │         │ NO AI drafts   │
│ Profile  │          │ Metrics  │         │ Learn what     │
│ Pillars  │          │ setup    │         │ actually works │
└──────────┘          └──────────┘         └───────┬────────┘
                                                   │
                                          VALIDATE: which pillar?
                                                    what time?
                                                    how long to write?
                                                    sustainable?
                                                   │
               ┌───────────────────────────────────┘
               ▼
PHASE C                           PHASE D              PHASE E
Skill Build                       Launch               Scale
(week 8+)                         (week 8+)            (month 4+)
───────────                       ──────               ─────
┌──────────────────┐             ┌──────────┐         ┌──────────┐
│ Formalize        │             │ 3x/week  │         │ Analytics│
│ sessions.md      │             │ full     │         │ Recycling│
│ Build            │──────→      │ cadence  │───→     │ Newsletter
│ /content-draft   │             │ Buffer   │         │ Canva    │
│ Dir structure    │             │ engaged  │         │ Consult  │
└──────────────────┘             └──────────┘         └──────────┘


═══════════════════════════════════════════════════════════════════════


THE PIPELINE — WHAT RUNS EVERY WEEK
────────────────────────────────────

  YOUR DAILY WORK (happens whether you post or not)
  ─────────────────────────────────────────────────

  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌──────────┐  ┌──────────┐
  │sessions │  │git log  │  │errata   │  │ADRs     │  │9 named   │  │research  │
  │.md      │  │commits  │  │80+ bugs │  │decisions│  │frameworks│  │backlog   │
  │flywheel │  │features │  │doc 24   │  │         │  │evergreen │  │52 creators
  │metrics  │  │shipped  │  │         │  │         │  │carousel  │  │580 entries
  └────┬────┘  └────┬────┘  └────┬────┘  └────┬────┘  └─────┬────┘  └─────┬────┘
       │            │            │            │              │              │
       └────────────┴────────────┴─────┬──────┴──────────────┴──────────────┘
                                       │
                                       ▼
                              ┌────────────────┐
                              │    HARVEST     │  read 6 sources
                              │   (weekly)     │  last 7 days
                              └───────┬────────┘
                                      │
                                      ▼
                              ┌────────────────┐
                              │   CLASSIFY     │  map signal → pillar
                              │                │  filter duplicates
                              │                │  check pillar balance
                              └───────┬────────┘
                                      │
                                      ▼
                              ┌────────────────┐
                              │   PROPOSE      │  5 candidates
                              │                │  grouped by pillar
                              │                │  YOU pick 3
                              └───────┬────────┘
                                      │
                                      ▼
                              ┌────────────────┐
                              │    DRAFT       │  skeleton: structure + data
                              │                │  NOT finished copy
                              │                │  → docs/content/drafts/
                              └───────┬────────┘
                                      │
                                      ▼
                    ┌─────────────────────────────────────┐
                    │          THE QUALITY GATE           │
                    │                                     │
                    │   AI gave you:     YOU produce:     │
                    │   structure         voice           │
                    │   data points       narrative       │
                    │   creator tags      opinion         │
                    │   topic ideas       authenticity    │
                    │   skeleton          the writing     │
                    │                                     │
                    │   If anyone could've written it,    │
                    │   it's not ready to publish.        │
                    └────────────────┬────────────────────┘
                                    │
                                    ▼
                              ┌────────────┐
                              │  SCHEDULE  │  Buffer / LinkedIn native
                              │            │  post when YOU can respond
                              └─────┬──────┘
                                    │
                                    ▼
                              ┌────────────┐
                              │  PUBLISH   │  3x/week
                              │            │  → auto-update published.md
                              └─────┬──────┘
                                    │
                                    ▼
                              ┌────────────┐
                              │  ENGAGE    │  golden hour (60-90 min)
                              │            │  5-10 comments/day on peers
                              └─────┬──────┘
                                    │
                                    ▼
                              ┌────────────┐
                              │  MEASURE   │  comment rate, SSI,
                              │            │  profile views, DMs
                              └─────┬──────┘
                                    │
                                    ▼
                              ┌────────────┐
                              │  ADJUST    │  pillar weights, format mix,
                              │  (monthly) │  posting times, creator focus
                              └────────────┘


═══════════════════════════════════════════════════════════════════════


CONTENT PILLARS — WHAT YOU POST
───────────────────────────────

  ┌─────────────────────────────────────────────────────────────────┐
  │                                                                 │
  │  BUILD-IN-PUBLIC     HOW-TOS          CONTRARIAN     CASE       │
  │  40% (~5/mo)         30% (~4/mo)      20% (~2/mo)   STUDIES    │
  │                                                      10%(~1/mo)│
  │  ████████████████    ████████████      ████████      ████      │
  │                                                                 │
  │  "Here's what        "Here's how       "Here's why   "Here's   │
  │   happened"           to do it"         you're wrong"  proof"  │
  │                                                                 │
  │  Journey +           Teach from        Strong         Portfolio │
  │  metrics +           9 frameworks +    opinions +     wins +    │
  │  failures            real examples     real data      outcomes  │
  │                                                                 │
  │  TRUST               AUTHORITY         REACH          CONVERT   │
  │                                                                 │
  └─────────────────────────────────────────────────────────────────┘

  FORMAT: 50% text │ 30% carousel/PDF │ 20% polls
  LANGUAGE: 70% English │ 30% Spanish (original, not translated)


═══════════════════════════════════════════════════════════════════════


ENGAGEMENT ENGINE — HOW YOU GROW
─────────────────────────────────

  Weeks 1-4              Weeks 5-8              Month 3+
  COMMENT ONLY           SELECTIVE TAG          FULL ENGAGE

  5-10 comments/day      Tag 2-3 Tier 1         Response posts
  on peer posts          creators who've        DM outreach
  substance only         engaged back           (2-3/month)
  no tagging             response posts         Community active
  build recognition      start DMs              Cross-promote

  Tier 1: Reuven Cohen, Nathan Cavaglione
  Tier 2: DeAngelis, Phelps, Klishevich, Aftandilian (after month 2)
  Tier 3: 46 other creators (comment when relevant)

  Communities: Agentics Foundation (100K+), Claude Discord (65K),
              Hacker News, Reddit r/ClaudeAI


═══════════════════════════════════════════════════════════════════════


TIMELINE — WHEN YOU'LL SEE WHAT
────────────────────────────────

  Week 0-1     Week 1-3      Week 3-7       Week 8+       Month 4+
  ─────────    ─────────     ─────────      ─────────     ─────────
  Position     Build         Validate       Launch        Scale
  Profile      Templates     12 manual      /content-     v2 features
  Voice guide  Calendar      posts          draft skill   based on
  Decisions    6 drafts      Learn truth    3x/week       what works
               Metrics       Adjust         Full cadence

  ◄── no posting ──►◄── posting manually ──►◄── skill-assisted ──►

  Expect:              Expect:               Expect:
  0 followers          First engagement      Comment rate 0.3%+
  0 content            signals               Creator connections
  Just preparation     Real data on          SSI 60+
                       what works            First inbound DMs
                                             (month 6: consulting)


═══════════════════════════════════════════════════════════════════════


FILE MAP
────────

  docs/features/linkedin-content-pipeline/
  ├── brief.md                    ← what and why
  ├── implementation.md           ← how (this document)
  ├── challenge-2026-03-03.md     ← stress test results
  └── research-positioning-*.md   ← niche validation

  docs/content/                   ← created in Phase A
  ├── drafts/                     ← post files (1 per post)
  ├── templates/                  ← reusable post structures
  ├── calendar.md                 ← pillar rotation
  ├── published.md                ← what's been posted (dedup)
  ├── metrics.md                  ← engagement tracking
  └── voice-guide.md              ← your writing voice

  system/skills/content-draft/    ← built in Phase C
  └── SKILL.md                    ← /content-draft definition
```

---

## 1. The Thesis

You design AI-powered systems for a living. You do it every day. Brana is one of those systems — documented, measured, battle-tested across 6 projects. The LinkedIn content pipeline turns that daily practice into a visible body of work.

The insight: **LLMs write code. Humans design systems.** The creative, valuable work is deciding what to build, how components connect, what feedback loops to install, and how to make the whole thing reliable. That's system design at a higher level of abstraction. Implementation is where tools like Claude help. But the architecture — the logic, the intent, the decisions — that's the human contribution.

This pipeline doesn't manufacture content. It extracts signal from work you're already doing and shapes it for an audience that needs it.

```
Your daily work                          Your audience
─────────────                            ─────────────

Design systems ──→ Document decisions    AI engineers who build with agents
Build brana     ──→ Track metrics         Tech leads evaluating AI workflows
Ship projects   ──→ Capture failures     CTOs deciding how to adopt AI
Solve problems  ──→ Formalize patterns   Developers who want depth, not tips

         │                                        │
         ▼                                        ▼
   Content fuel                            Content need
   (you produce this                       (they search for this
    whether or not                          whether or not
    you publish)                            they find you)
```

**Why this works:** The $11-14B AI consulting market is growing at 26% CAGR. 72% of professional developers reject vibe coding. 1,445% surge in multi-agent system inquiries. 8,000+ AI Architect jobs on LinkedIn. And no one on the platform is positioned specifically as an "AI systems designer." The niche is unoccupied. You have the production evidence to claim it.

---

## 2. The Positioning

### Who you are on LinkedIn

**Not** a prompt engineer. **Not** an AI tips creator. **Not** a tool reviewer.

You are an **AI systems designer** — someone who designs, builds, and operates intelligent systems using LLMs and agent frameworks as components. You think at the architecture level: what are the feedback loops, what are the failure modes, how do the pieces compose, how does the system learn from its own mistakes.

Brana is your documented case study. Your portfolio clients (Somos Mirada, NexEye, Proyecto Anita, Psilea, TinyHomes) are your proof. Your 80+ documented errors are your credibility.

### Positioning formula (Moore)

```
For:        AI engineers and tech leads building agent-based systems
Who:        Need architecture guidance beyond "just prompt it"
This is:    A practitioner's perspective on AI systems design
That:       Shows real metrics, real failures, real architectures from production
Unlike:     Vibe coding tutorials, generic AI tips, corporate thought leadership
Because:    Every claim is backed by documented sessions, measured flywheel
            metrics, and 6 production projects — not theory
```

### The counter-narrative

The dominant LinkedIn AI narrative is: "AI is easy, here's a shortcut, vibe code your way to success."

Your counter-narrative is: **"Systems are hard. Design them properly. Here's how I do it, including every mistake."**

This is not contrarian for the sake of controversy. It's contrarian because it's true — and 72% of professional developers already agree (UC San Diego/Cornell study).

---

## 3. The Pipeline — Complete Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                    LINKEDIN CONTENT PIPELINE                        │
│                                                                     │
│  LAYER 1: DATA SOURCES (produced daily, automatically)              │
│  ─────────────────────────────────────────────────────              │
│                                                                     │
│  sessions.md ─────┐                                                 │
│  (flywheel metrics)│                                                │
│                    │                                                │
│  git log ─────────┤                                                 │
│  (commits, diffs)  │                                                │
│                    ├──→  CONTENT FUEL  ──→  HARVEST  ──→  CLASSIFY  │
│  errata (doc 24) ──┤    (raw signals)      (extract)     (pillar)   │
│  (80+ mistakes)    │                                                │
│                    │                                                │
│  ADRs ────────────┤                                                 │
│  (decisions)       │                                                │
│                    │                                                │
│  frameworks (9) ───┤                                                │
│  (evergreen)       │                                                │
│                    │                                                │
│  research backlog ─┘                                                │
│  (55 posts, 52 creators)                                            │
│                                                                     │
│                                                                     │
│  LAYER 2: CONTENT CREATION (weekly batch + daily engagement)        │
│  ───────────────────────────────────────────────────────            │
│                                                                     │
│       CLASSIFY                                                      │
│          │                                                          │
│          ▼                                                          │
│   ┌──────────────┐                                                  │
│   │  5 candidates │   grouped by pillar                             │
│   │  per week     │   filtered by novelty (published.md)            │
│   └──────┬───────┘   filtered by pillar balance                     │
│          │                                                          │
│          ▼                                                          │
│   ┌──────────────┐                                                  │
│   │  YOU PICK 3   │   human judgment is the ranker                  │
│   └──────┬───────┘   no opaque scoring formula                      │
│          │                                                          │
│          ▼                                                          │
│   ┌──────────────┐                                                  │
│   │  DRAFT        │   AI: structure + data points + creator tags    │
│   │  SKELETON     │   YOU: voice + narrative + opinion              │
│   └──────┬───────┘   output: docs/content/drafts/YYYY-MM-DD-slug.md│
│          │                                                          │
│          ▼                                                          │
│   ┌──────────────┐                                                  │
│   │  EDIT + WRITE │   rewrite in your voice                         │
│   │  (you, not AI)│   add personal anecdotes                        │
│   └──────┬───────┘   verify data points                             │
│          │                                                          │
│          ▼                                                          │
│   ┌──────────────┐                                                  │
│   │  SCHEDULE     │   Buffer or LinkedIn native                     │
│   │               │   post when YOU can respond                     │
│   └──────┬───────┘   (golden hour: first 60-90 min = reach)        │
│          │                                                          │
│          ▼                                                          │
│   ┌──────────────┐                                                  │
│   │  PUBLISH      │   3x/week                                       │
│   │               │   auto-update published.md                      │
│   └──────────────┘                                                  │
│                                                                     │
│                                                                     │
│  LAYER 3: FEEDBACK LOOP (continuous)                                │
│  ───────────────────────────────────                                │
│                                                                     │
│   LinkedIn analytics ──→ SSI, comment rate, profile views           │
│   published.md ─────────→ deduplication + topic history             │
│   engagement notes ─────→ what resonated, what didn't               │
│          │                                                          │
│          ▼                                                          │
│   Adjust: pillar weights, format mix, posting times, creator focus  │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 4. Content Architecture

### 4 Pillars — what you post about

Every post maps to exactly one pillar. Pillar weights determine how many posts per week come from each category. Weights are starting hypotheses — adjusted monthly from data.

```
                        CONTENT PILLARS

  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐
  │                 │  │                 │  │                 │  │                 │
  │  BUILD-IN-      │  │  TACTICAL       │  │  CONTRARIAN     │  │  CLIENT CASE    │
  │  PUBLIC         │  │  HOW-TOS        │  │  TAKES          │  │  STUDIES        │
  │                 │  │                 │  │                 │  │                 │
  │  40%            │  │  30%            │  │  20%            │  │  10%            │
  │  ~5 posts/mo    │  │  ~4 posts/mo    │  │  ~2 posts/mo    │  │  ~1 post/mo     │
  │                 │  │                 │  │                 │  │                 │
  │  Journey.       │  │  Teach.         │  │  Argue.         │  │  Prove.         │
  │  Show the       │  │  Specific       │  │  Opinionated    │  │  Anonymized     │
  │  process,       │  │  techniques     │  │  positions      │  │  wins from      │
  │  including      │  │  from real      │  │  that spark     │  │  portfolio      │
  │  what breaks.   │  │  architecture.  │  │  discussion.    │  │  projects.      │
  │                 │  │                 │  │                 │  │                 │
  └─────────────────┘  └─────────────────┘  └─────────────────┘  └─────────────────┘

  Trust builder        Authority builder    Reach amplifier      Conversion driver
  "I'm doing this"     "I know how"         "I think differently" "I deliver results"
```

### Pillar 1: Build-in-Public (40%) — "I'm doing this"

Source: your daily brana sessions. Every session produces data. That data is content.

| Data source | Content angle | Example hook |
|-------------|--------------|-------------|
| Flywheel metrics (sessions.md) | Trend stories — rates going up/down | "0.12 correction rate this week. Last month it was 0.22. Here's what changed." |
| ADRs (docs/decisions/) | Decision frameworks | "Why I merged 3 repos into 1 — the decision framework I used (ADR-006)" |
| Phase completions | Milestone summaries | "Phase 1 shipped: 37 skills, 10 agents, 9 hooks. What I learned building an AI brain." |
| Errata (doc 24) | Failure stories | "80+ documented mistakes my AI has made. That's a feature, not a bug." |
| Task completions | Shipping velocity | "12 tasks completed this month. Here's the system that keeps me on track." |
| Hook improvements | System evolution | "My AI now catches its own cascading failures. Here's how the detection works." |

**Voice:** Honest, specific, numbers-first. Never "I built something cool" — always "here's exactly what happened, including what went wrong."

### Pillar 2: Tactical How-Tos (30%) — "I know how"

Source: brana's 9 named frameworks. Each framework is a reusable teaching opportunity. These are evergreen — they don't depend on weekly activity.

| Framework | Format | Content idea |
|-----------|--------|-------------|
| DDD -> SDD -> TDD -> Code | Carousel (4 slides) | "The spec-first workflow: 4 steps from idea to working code" |
| Context Budget (55/70/85%) | Text post | "Your AI degrades before you notice. The budget system that prevents it." |
| Reflection DAG | Carousel (5 slides) | "How I organize knowledge so my AI never contradicts itself" |
| Graduation Pathway | Carousel (4 slides) | "Manual -> Convention -> Workflow -> Enforcement: when to automate" |
| Surgery Protocol | Text post | "When your AI edits its own brain: the safety protocol" |
| Four Arrows | Carousel (4 slides) | "Refresh -> Maintain -> Reconcile -> Back-propagate: the spec feedback loop" |
| Flywheel Metrics | Text post | "7 numbers that tell me if my AI is getting smarter or dumber" |
| Cascade Detection | Text post | "3 failures in a row on the same file = stop and rethink. Here's the hook." |
| Evergreen Mode | Text post | "580 knowledge entries my AI can draw from when there's nothing new to report" |

**Voice:** Teacher mode. Step-by-step. "Here's the technique, here's why it works, here's how to implement it."

### Pillar 3: Contrarian Takes (20%) — "I think differently"

Source: strong opinions formed through building brana. These drive engagement through debate.

| Take | Hook | Supporting evidence |
|------|------|-------------------|
| Spec-first > prompt-first | "Stop writing prompts. Start writing specifications." | Martin Fowler's SDD analysis validates the methodology |
| Failure as data | "My AI has 80+ documented failures. That's a feature, not a bug." | Errata doc with real entries |
| Anti-vibe-coding | "Vibe coding is technical debt with extra steps." | 72% of devs reject it (UC San Diego/Cornell) |
| Cross-project memory | "Your AI starts from zero every session. Mine doesn't." | ruflo integration with persistent memory |
| Systems > tools | "Everyone's reviewing AI tools. Nobody's designing AI systems." | Unoccupied niche finding from research |
| Design discipline | "The code is the easy part. The architecture is the hard part." | Production evidence from 6 projects |

**Voice:** Direct, opinionated, backed by data. Never trolling — always "here's what I've seen, here's why I disagree."

### Pillar 4: Client Case Studies (10%) — "I deliver results"

Source: anonymized wins from your portfolio. This is the only "hire me" pillar.

| Project | Angle | Outcome to highlight |
|---------|-------|---------------------|
| Somos Mirada | "How I automated a surgical practice's patient flow with AI" | Operational efficiency gain |
| NexEye | "Deploying computer vision on Docker Swarm — what broke" | Infrastructure resilience |
| Proyecto Anita | "Multi-tenant WhatsApp campaigns: the architecture" | Multi-tenant system design |
| Psilea | "Running a microdosing venture with the same system I use for code" | Cross-domain system reuse |
| TinyHomes | "Building a marketplace from zero — the AI-assisted approach" | Full-stack product delivery |

**Voice:** Professional, outcome-focused. "Client had X problem. Here's the system I designed. Here's what happened."

**Note (t-175 decision pending):** If consulting is a v1 goal, increase to 20% and reduce Build-in-Public to 30%. The challenger warned this is the only conversion pillar.

---

## 5. Format Mix

Adjusted after challenger review — no carousel tooling exists for v1.

```
FORMAT MIX (v1)

  ┌───────────────────────────────────────────────────────────────┐
  │                                                               │
  │  ████████████████████████████████████████████████░░░░░░░░░░░  │
  │  │          50% TEXT          │  30% CAROUSEL │ 20% POLLS  │  │
  │  │                           │   /PDF        │ /QUESTIONS  │  │
  │  └───────────────────────────┴───────────────┴─────────────┘  │
  │                                                               │
  │  TEXT (50%):           Contrarian takes, reflections,          │
  │  ~6 posts/month        build-in-public updates, case studies  │
  │                                                               │
  │  CAROUSEL/PDF (30%):   How-tos, frameworks, step-by-step      │
  │  ~4 posts/month        guides. Plain PDF via /brana:export-pdf.     │
  │                        Visual upgrade in v2 (t-176).          │
  │                                                               │
  │  POLLS/QUESTIONS (20%):Community engagement, topic validation, │
  │  ~2 posts/month        pillar weight testing, audience signal. │
  │                                                               │
  └───────────────────────────────────────────────────────────────┘
```

### Text post structure

```markdown
[HOOK — 1-2 lines that stop the scroll]

[CONTEXT — why this matters, 2-3 lines]

[BODY — the insight, the story, the data. 5-15 lines.]

[TAKEAWAY — what the reader walks away with]

[CTA — question that invites comments]

---
First comment: relevant link + hashtags
```

### Carousel structure (markdown -> PDF via /brana:export-pdf)

```markdown
## Slide 1: Title + hook
[One sentence that makes them swipe]

## Slide 2: The problem
[What most people get wrong]

## Slide 3-5: The solution
[Step by step, one concept per slide]

## Slide 6: Summary / takeaway
[The single thing to remember]

## Slide 7: CTA
[Follow for more / comment your experience]
```

---

## 6. Bilingual Strategy

```
LANGUAGE SPLIT

  English (70%)                          Spanish (30%)
  ────────────                           ────────────
  ~9 posts/month                         ~3 posts/month

  Pillars 1-3:                           Pillar 4 + selected from 1-3:
  Build-in-public                        Case studies with Argentine context
  How-tos                                Venture insights (Psilea, TinyHomes)
  Contrarian takes                       LATAM tech commentary

  Audience:                              Audience:
  Global AI engineers                    LATAM tech community
  Tech leads worldwide                   Argentine entrepreneurs
  Consulting prospects (EN)              Consulting prospects (ES)
```

Spanish content is **original**, not translated. Argentine voice, local examples, local pain points.

At ~1 Spanish post/week, this won't build a standalone LATAM audience fast. It serves dual purpose: LATAM visibility + demonstrates range to bilingual followers. If Spanish posts outperform English, increase allocation.

---

## 7. Implementation Phases

### Phase 0: Strategy & Positioning (weeks 0-1)

**Goal:** Nail the positioning before posting anything. Get the house in order.

| Step | Deliverable | Task |
|------|------------|------|
| 1. Research positioning | Validate "AI systems designer" niche | t-170 (done) |
| 2. Write voice/tone guide | 3-5 example posts in your natural voice | t-174 |
| 3. Decide pillar weights | Case Studies at 10% or 20%? | t-175 |
| 4. Decide carousel tooling | /brana:export-pdf, Canva templates, or defer? | t-176 |
| 5. Optimize LinkedIn profile | Headline, about section, banner, featured | t-162 |

**LinkedIn profile spec (t-162):**

```
HEADLINE (120 chars max):
  AI Systems Designer | Building intelligent systems with LLMs and agent frameworks
  — or —
  I design AI-powered systems. Brana is the documented proof.

ABOUT (2,600 chars max):
  - Opening hook: what you do and why it matters
  - The counter-narrative: systems > vibe coding
  - What brana is (briefly)
  - Portfolio proof points (2-3 projects)
  - What you post about (the 4 pillars)
  - CTA: follow for systems design content / DM for consulting

FEATURED SECTION:
  - Pin 3-5 best-performing posts (rotate monthly)
  - One carousel showing a framework
  - One case study

BANNER:
  - Simple: "AI Systems Designer" + one visual element
  - Not cluttered, not corporate
```

**Voice/tone guide (t-174):**

Write 3-5 example posts in your natural voice — before you ever publish. These become the reference for what "authentic" sounds like. Include:
- One build-in-public post (showing metrics, being honest about failures)
- One how-to post (teaching a specific technique)
- One contrarian take (arguing a position)
- One in Spanish (demonstrating the Argentine voice)

The guide answers: What does your writing sound like when it's genuinely yours? What phrases do you naturally use? What do you avoid? How do you handle technical depth — ELI5 or peer-to-peer?

### Phase A: Foundation (weeks 1-3)

**Goal:** Build the content infrastructure. Templates, calendar, first drafts.

| Step | Deliverable | Task |
|------|------------|------|
| 1. Write post templates | 1 template per pillar x format | t-163 |
| 2. Create content calendar | Markdown with pillar rotation | t-164 |
| 3. Draft first 6 posts | 2 per pillars 1-3 (EN) | t-165 |
| 4. Set up metrics tracking | Spreadsheet or markdown | t-169 |

**Post templates (t-163):**

Create one reusable template for each combination:

| Pillar | Text template | Carousel template |
|--------|--------------|------------------|
| Build-in-Public | `templates/build-text.md` | `templates/build-carousel.md` |
| How-To | `templates/howto-text.md` | `templates/howto-carousel.md` |
| Contrarian | `templates/contrarian-text.md` | n/a (text-only pillar) |
| Case Study | `templates/casestudy-text.md` | `templates/casestudy-carousel.md` |

Each template contains: structure skeleton, hook patterns, CTA options, hashtag suggestions, and one completed example.

**Content calendar (t-164):**

```
docs/content/calendar.md

## Week 1 (YYYY-MM-DD)
| Day | Pillar | Format | Topic | Status |
|-----|--------|--------|-------|--------|
| Tue | Build-in-Public | Text | [topic] | draft / scheduled / published |
| Thu | How-To | Carousel | [topic] | draft / scheduled / published |
| Sat | Contrarian | Text | [topic] | draft / scheduled / published |

## Week 2 ...
```

Pillar rotation ensures balance across 12 posts/month:
- 5x Build-in-Public, 4x How-To, 2x Contrarian, 1x Case Study

**First 6 posts (t-165):**

Draft queue that doubles as the 3-post buffer. These should be your strongest material — first impressions set the tone.

Suggested first 6:
1. [Build] "I built an AI system that tracks its own mistakes. Here's what 80+ errors taught me."
2. [How-To] "The spec-first workflow: stop prompting, start specifying" (carousel)
3. [Contrarian] "Vibe coding is technical debt with extra steps."
4. [Build] "37 skills, 10 agents, 9 hooks — what Phase 1 of building an AI brain looks like"
5. [How-To] "Your AI degrades before you notice. The context budget system." (carousel)
6. [Contrarian] "Everyone's reviewing AI tools. Nobody's designing AI systems."

### Phase B: Manual Validation (weeks 3-7)

**Goal:** Publish 12 posts manually. Learn what works before automating anything.

```
MANUAL VALIDATION LOOP (repeat 4 weeks)

  Week start                              Week end
  ──────────                              ────────

  Pick 3 topics from drafts/calendar      After each post:
           │                                │
           ▼                                ▼
  Write the post yourself                 Record in published.md:
  (no AI draft — your voice)                - Topic, pillar, format
           │                                - Engagement (comments, views)
           ▼                                - Time to write
  Edit until it sounds like you             - What worked / what didn't
           │                                - Golden hour response count
           ▼                                │
  Schedule for when you CAN respond         ▼
  (not fixed time — YOUR availability)    At month end:
           │                                - Which pillar resonated most?
           ▼                                - How long does editing take?
  Post + respond in golden hour             - What's your natural posting time?
  (first 60-90 min = reach)                 - Did the format mix work?
           │                                - Any surprise topics?
           ▼                                │
  5-10 substantive comments on              ▼
  peer posts (daily)                      Adjust: pillar weights, format mix,
                                          posting times, engagement approach
```

**What you're validating:**

| Question | How you'll know |
|----------|----------------|
| Do people care about AI systems design content? | Comment rate on first 4 posts |
| Which pillar gets the most engagement? | Compare by pillar after 12 posts |
| How long does writing a post actually take? | Track time per post in published.md |
| What's your natural posting time? | When did you actually respond during golden hour? |
| Does the 3x/week cadence feel sustainable? | Honest self-assessment after 4 weeks |
| Do carousels outperform text? | Compare format engagement after 12 posts |
| Does Spanish content find its audience? | Track Spanish post metrics separately |

**Creator engagement warm-up (t-173):**

During Phase B, you're comments-only. No tagging. No response posts. Just genuine engagement on peer content.

```
ENGAGEMENT RAMP

  Weeks 1-4: COMMENT ONLY
  ────────────────────────
  - 5-10 substantive comments per day on peer posts
  - Add your perspective from brana experience
  - Never "great post!" — always substance
  - Focus on Tier 1 creators first (Reuven Cohen, Nathan Cavaglione)
  - Track which creators respond to your comments

  Weeks 5-8: SELECTIVE TAGGING
  ────────────────────────────
  - Tag 2-3 Tier 1 creators in response posts
  - Only those who've seen your comments and engaged back
  - Create "response posts" — your take on their content
  - Start DM conversations (genuine, not salesy)

  Month 3+: FULL ENGAGEMENT
  ─────────────────────────
  - Response posts, comment threads
  - DM outreach (2-3 new creators/month)
  - Cross-promote with build-in-public peers
  - Community participation (Agentics Foundation, Claude Discord)
```

**Creator tiers:**

| Tier | Who | Engagement approach |
|------|-----|-------------------|
| Tier 1 (2-3 creators) | Reuven Cohen (Ruflo foundation), Nathan Cavaglione (build-in-public peer) | Comment daily, response posts after week 4, DM by week 6 |
| Tier 2 (4-6 creators) | Julian DeAngelis (context engineering), Steve Phelps (shared memory), Yauhen Klishevich (CLAUDE.md), Eddie Aftandilian (agentic CI/CD) | Comment 2-3x/week, tag after month 2 |
| Tier 3 (46 creators) | Remaining from research backlog | Comment when their content is relevant to yours |

**Metrics tracking (t-169):**

```
docs/content/metrics.md

## Weekly Metrics
| Week | Posts | Avg comments | Avg views | Best post | SSI |
|------|-------|-------------|-----------|-----------|-----|
| W1   |       |             |           |           |     |
| W2   |       |             |           |           |     |

## Per-Post Tracking
| Date | Title | Pillar | Format | Lang | Comments | Views | Saves | Time to write |
|------|-------|--------|--------|------|----------|-------|-------|--------------|
|      |       |        |        |      |          |       |       |              |

## Monthly Review
- Best performing pillar:
- Best performing format:
- Posting time that works:
- Adjustment for next month:
```

Track from day 1. Even manual tracking beats no tracking.

### Phase C: Skill Build (week 8+)

**Goal:** After 12+ manual posts, build `/content-draft` informed by real experience.

**Prerequisite:** Complete Phase B. You must have published at least 12 posts manually and have real data about what works.

**Step 1: Formalize sessions.md schema (t-171)**

sessions.md lives at `~/.claude/projects/.../memory/sessions.md`, auto-generated by `session-end.sh`. Before building a skill that parses it, define the contract:

```
SESSION ENTRY SCHEMA (from session-end.sh)

### Session {id} ({ISO-timestamp})
- Events: {total} ({ok} ok, {fail} fail)
- Corrections: {n} | Test writes: {n} | Cascades: {n}
- Tests: {pass} pass, {fail} fail (rate={rate}) | Lint: {pass} pass, {fail} fail (rate={rate})
- Flywheel: corr={rate} fix={rate} test={rate} casc={rate} deleg={n}
- Tools: {comma-separated tool names}
- Files: {comma-separated file paths}
```

Also specify: ruflo `memory_search` as the richer structured source (JSON, tagged, searchable). sessions.md is the fallback when ruflo is unavailable.

**Step 2: Build /content-draft skill (t-166)**

```
system/skills/content-draft/SKILL.md

SKILL PROCESS — 4 PHASES:

  Phase 1: HARVEST
  ────────────────
  Read 6 data sources:
  1. sessions.md (last 7 days) — flywheel metrics, notable sessions
  2. git log --since="7 days ago" — commits, features shipped
  3. errata (doc 24) — recent corrections, patterns
  4. completed tasks — what was shipped
  5. ADRs — recent decisions
  6. frameworks — evergreen content (when sources 1-5 are sparse)

  Also query: ruflo memory_search for cross-client patterns


  Phase 2: CLASSIFY
  ─────────────────
  Map each signal to a pillar:

  Signal type         →  Pillar
  ──────────────────────────────
  Flywheel metrics    →  Build-in-Public (P1)
  Phase completion    →  Build-in-Public (P1)
  Framework usage     →  How-To (P2)
  Hook improvement    →  How-To (P2)
  Strong opinion      →  Contrarian (P3)
  Client project      →  Case Study (P4)
  Error/failure       →  P1 or P3 (depends on angle)


  Phase 3: PROPOSE
  ────────────────
  Present 5 candidates grouped by pillar:

  Build-in-Public:
    1. "Correction rate dropped from 0.22 to 0.12 — the change"
    2. "Phase 2 shipped: what's in 47 commits"

  How-To:
    3. "The graduation pathway: when to automate"

  Contrarian:
    4. "Context rot is a gradient, not a cliff"

  Case Study:
    5. "NexEye: computer vision on Docker Swarm"

  Filter: check published.md for duplicates.
  Filter: check pillar balance (don't propose 3 from same pillar).

  Present via AskUserQuestion → user picks 3.


  Phase 4: DRAFT
  ──────────────
  For each selected topic, produce a skeleton:

  - Hook options (2-3 alternatives)
  - Key data points to include
  - Structure (intro, body sections, takeaway, CTA)
  - Suggested creator tags (from doc 43 registry)
  - Suggested hashtags
  - Pillar and format label

  Write to: docs/content/drafts/YYYY-MM-DD-slug.md

  IMPORTANT: The draft is a SKELETON. Structure + data.
  The human writes the voice, the narrative, the opinion.

  After user confirms a post was scheduled:
  → auto-append to published.md (eliminates manual SPOF)
```

**Step 3: Create directory structure (t-167)**

```
docs/content/
├── drafts/                    ← /content-draft output goes here
│   ├── 2026-03-15-correction-rate.md
│   ├── 2026-03-15-spec-first.md
│   └── 2026-03-15-nexeye-swarm.md
├── templates/                 ← reusable post templates
│   ├── build-text.md
│   ├── build-carousel.md
│   ├── howto-text.md
│   ├── howto-carousel.md
│   ├── contrarian-text.md
│   ├── casestudy-text.md
│   └── casestudy-carousel.md
├── calendar.md                ← weekly pillar rotation
├── published.md               ← deduplication state (auto-updated)
├── metrics.md                 ← engagement tracking
└── voice-guide.md             ← your writing voice reference
```

### Phase D: Launch (week 8+)

**Goal:** Full-cadence publishing with skill assistance.

| Activity | Frequency | Time |
|----------|-----------|------|
| `/content-draft` batch | Weekly (flexible day) | ~1 hour |
| Edit + rewrite drafts | Same session | ~1 hour |
| Schedule in Buffer/native | Same session | ~10 min |
| Respond during golden hour | Per post (3x/week) | ~30 min each |
| Comment on peer posts | Daily | ~20 min |
| Monthly metrics review | Monthly | ~30 min |

**3-post buffer rule:** Always maintain 3 scheduled posts ahead. If the buffer drops below 3, the next batch session is mandatory. One missed week doesn't mean zero posts.

### Phase E: Scale (month 4+)

Deferred features, activated based on what's working:

| Feature | Trigger to activate | Task |
|---------|-------------------|------|
| `/content-report` skill | Monthly review feels tedious | v2 |
| Google Sheets metrics | Markdown tracking becomes unwieldy | v2 |
| Content recycling | Top posts identified (6+ weeks old) | v2 |
| Canva carousel templates | Carousels outperform text significantly | t-176 |
| LinkedIn Newsletter | 1,000+ followers achieved | v2 |
| Consulting offer page | First inbound consultation request | v2 |
| `/session-handoff` integration | Content-worthy moments missed regularly | v2 |

---

## 8. The Quality Gate

The single most important rule in this entire pipeline:

```
┌─────────────────────────────────────────────────────────────────┐
│                                                                 │
│   AI PRODUCES:                    HUMAN PRODUCES:               │
│   ───────────                     ───────────────               │
│   Structure                       Voice                         │
│   Data points                     Narrative                     │
│   Creator tags                    Opinion                       │
│   Topic candidates                Judgment                      │
│   Skeleton drafts                 Authenticity                   │
│   Deduplication                   Personal anecdotes            │
│   Pillar classification           The actual writing            │
│                                                                 │
│   ─────────────────────────────────────────────────────────────  │
│                                                                 │
│   THE LINE:  AI provides raw material.                          │
│              You provide the finished product.                   │
│              If a post could have been written by anyone,       │
│              it's not ready to publish.                          │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

**Why this matters:** LinkedIn 360 Brew penalizes AI-generated content — -30% reach, -55% engagement. But beyond the algorithm penalty, authentic content performs better because readers can tell the difference. Your documented failures, your specific numbers, your Argentine perspective — no AI can produce that.

---

## 9. Data Sources — The 6 Fuel Lines

Each source feeds the pipeline independently. Even if some are empty in a given week, others produce.

```
SOURCE 1: sessions.md
─────────────────────
Location: ~/.claude/projects/.../memory/sessions.md
Updated:  Every session (by session-end.sh)
Contains: Flywheel metrics (7 rates), event counts, tools used, files changed
Content:  Trend stories ("correction rate dropped"), milestone summaries
Fallback: ruflo memory_search (richer JSON, tagged)

SOURCE 2: git log
──────────────────
Command:  git log --since="7 days ago" --oneline
Contains: Commits, features shipped, files changed
Content:  "Here's what I shipped this week" posts

SOURCE 3: Errata (doc 24)
──────────────────────────
Location: docs/24-roadmap-corrections.md
Updated:  After each /debrief session
Contains: Documented mistakes, corrections, patterns
Content:  Failure stories, "what I learned" posts

SOURCE 4: ADRs
───────────────
Location: docs/decisions/ADR-*.md
Updated:  Before each major feature
Contains: Context, decision, consequences
Content:  Decision framework posts, "why I chose X over Y"

SOURCE 5: Frameworks (9 named)
──────────────────────────────
Location: docs/reflections/, system/
Contains: Reusable concepts: DDD->SDD->TDD, Context Budget, Graduation, etc.
Content:  Evergreen how-to carousels and explainers
Note:     These NEVER run out — 9 frameworks = months of carousel content

SOURCE 6: Research backlog
──────────────────────────
Location: brana-knowledge/dimensions/, research-sources.yaml
Contains: 55 posts from 52 creators, 580+ knowledge entries, 33 dimension docs
Content:  Response posts, "here's my take on [creator]'s idea"
Note:     Evergreen mode fallback when other sources are quiet
```

---

## 10. Engagement Engine

### Daily rhythm (20 min/day)

```
MORNING (10 min):
  Open LinkedIn → check notifications
  Respond to comments on your posts (golden hour priority)

MIDDAY OR EVENING (10 min):
  Find 5-10 posts from your creator list
  Write substantive comments (2-4 sentences each)
  Add your perspective from brana experience
  Never: "great post!", "thanks for sharing", empty agreement
  Always: specific insight, personal experience, or respectful disagreement
```

### Community engagement (weekly)

| Community | Activity | Time |
|-----------|----------|------|
| Agentics Foundation Discord | Share relevant findings, respond to questions | 15 min/week |
| Anthropic Claude Discord | Share brana approaches, help with Claude Code questions | 15 min/week |
| Hacker News | Submit one strong technical post per month | When appropriate |
| Reddit r/ClaudeAI | Cross-post key content, engage in threads | 10 min/week |

### Creator DM strategy (month 2+)

```
TEMPLATE (adapt to each creator):

"Hey [name], I've been following your work on [specific topic].
I'm building an AI development system called brana —
[one sentence about what's relevant to their work].
Your post about [specific post] resonated because [specific reason].
Would love to connect and share notes."

RULES:
- Only after 4+ weeks of commenting on their content
- Reference a SPECIFIC post of theirs
- Mention something SPECIFIC you're building
- Ask nothing. Offer connection.
- 2-3 new DMs per month maximum
```

---

## 11. Metrics & Success Criteria

### What to track

| Metric | Target (90 days) | Target (6 months) | Tool |
|--------|------------------|--------------------|------|
| Posts published | 36 (3/week x 12 weeks) | 78 | published.md |
| Comment rate | 0.3%+ | 0.5%+ | LinkedIn analytics |
| Profile views (target audience) | Trending up | 2x baseline | LinkedIn analytics |
| SSI score | 60+ | 70+ | LinkedIn dashboard |
| Inbound DMs | Any | 2-3/month | Manual count |
| Consultation requests | 0 (too early) | 1/month | Manual count |
| Creator responses | 3-5 meaningful connections | 10+ active connections | Manual count |
| Content buffer | 3 posts always | 3 posts always | Draft queue |

### Leading indicators (check weekly)

- **Comments > reactions:** People engaging deeply, not just liking
- **Profile views from target titles:** AI Engineer, CTO, Tech Lead — not random
- **Save rate:** People bookmarking for later = high-value content
- **Comment quality:** Are people adding substance or just agreeing?
- **Follower quality:** Are new followers in your target audience?

### Monthly review checklist

```
1. Which pillar got the most engagement this month?
   → Adjust weights if data supports it

2. Which format performed best?
   → Shift format mix toward what works

3. What posting time got the best golden hour response?
   → Lock in the time that works for YOUR schedule

4. Which creators engaged back?
   → Double down on those relationships

5. Any topic that unexpectedly resonated?
   → Create a follow-up series

6. Any topic that bombed?
   → Understand why. Wrong audience? Wrong angle? Wrong timing?

7. Is the cadence sustainable?
   → If 3x/week is burning you out, drop to 2x. Consistency > volume.

8. Buffer status: do you have 3 posts ready?
   → If not, next batch session is priority #1
```

### What success looks like at each phase

| Phase | Success = | Failure = |
|-------|-----------|-----------|
| Phase 0 (positioning) | Clear headline, profile optimized, voice guide written | Can't articulate what makes you different |
| Phase A (foundation) | 6 strong drafts ready, templates working | Templates feel forced, can't fill the calendar |
| Phase B (manual) | 12 posts published, engagement trend visible, cadence sustainable | Stopped posting after week 2, no engagement signal |
| Phase C (skill build) | /content-draft produces useful candidates, saves time vs manual | Skill output is irrelevant, slower than manual |
| Phase D (launch) | 3x/week sustained, comment rate 0.3%+, creator connections forming | Engagement flat, no inbound signals, burnout |
| Phase E (scale) | Inbound DMs, consultation inquiries, audience growth visible | Plateau with no clear lever to pull |

---

## 12. Risk Mitigations (from challenger review)

| Risk | Mitigation | Status |
|------|-----------|--------|
| AI content penalty (-30% reach) | Quality gate: AI provides structure, human writes voice | Built into process |
| No carousel tooling | Format mix 30-50-20 (was 60-30-10). Plain PDFs for v1. | Resolved (t-176 pending for v2) |
| Sunday batch SPOF | Flexible day + 3-post buffer | Built into process |
| published.md manual SPOF | /content-draft auto-updates published.md | Built into skill design |
| Creator spam risk | 4-week comment-only period before any tagging | Built into engagement plan |
| Golden hour conflict | Schedule for times when YOU can respond, not fixed window | Built into process |
| Quiet weeks (no brana activity) | Evergreen mode: 9 frameworks + 580 knowledge entries | Built into skill design |
| Consulting not converting | Case Studies pillar weight decision (t-175) | Pending |
| sessions.md schema fragility | Formalize contract before building skill (t-171) | Pending |

---

## 13. File Map — Where Everything Lives

```
thebrana/
├── docs/
│   ├── features/
│   │   └── linkedin-content-pipeline/
│   │       ├── brief.md                          ← feature brief
│   │       ├── implementation.md                 ← THIS DOCUMENT
│   │       ├── challenge-2026-03-03.md           ← challenger report
│   │       └── research-positioning-2026-03-03.md ← t-170 research
│   │
│   └── content/                                  ← created in Phase A
│       ├── drafts/                               ← post drafts (one .md per post)
│       ├── templates/                            ← reusable post templates
│       ├── calendar.md                           ← weekly pillar rotation
│       ├── published.md                          ← deduplication state
│       ├── metrics.md                            ← engagement tracking
│       └── voice-guide.md                        ← your writing voice reference
│
├── system/
│   └── skills/
│       └── content-draft/                        ← built in Phase C
│           └── SKILL.md                          ← /content-draft skill definition
│
└── .claude/
    └── tasks.json                                ← task tracking (ph-005)
```

---

## 14. Task Execution Order

```
DEPENDENCY GRAPH

  t-170 Research positioning ─────────────────────────────────────┐
  t-174 Voice/tone guide ─────────────────────────────────────────┤
  t-176 Carousel tooling decision ────────────────────────────────┤
        │                                                         │
        ▼                                                         │
  t-175 Case Studies weight decision (blocked by t-170) ──────────┤
                                                                  │
                                                                  ▼
                                                           ms-016 DONE
                                                                  │
                    ┌─────────────────────────────────────────────┘
                    ▼
  t-162 Optimize LinkedIn profile (blocked by t-170) ─────────────┐
  t-163 Write post templates ─────────────────────────────────────┤
        │                                                         │
        ├──→ t-164 Content calendar (blocked by t-163)            │
        └──→ t-165 Draft first 6 posts (blocked by t-163)         │
                                                                  │
                                                                  ▼
                                                           ms-013 DONE
                                                                  │
                    ┌─────────────────────────────────────────────┘
                    ▼
  t-169 Set up metrics tracking ──────────────────────────────────┐
  t-173 Creator engagement warm-up plan ──────────────────────────┤
  t-172 Publish 12 posts manually (blocked by t-163, t-165) ──────┤
                                                                  │
                                                                  ▼
                                                           ms-017 DONE
                                                                  │
                    ┌─────────────────────────────────────────────┘
                    ▼
  t-171 Formalize sessions.md schema ─────────────────────────────┐
  t-166 Build /content-draft (blocked by t-163, t-171, t-172) ────┤
        │                                                         │
        └──→ t-167 Create docs/content/ structure (blocked t-166) ┤
                                                                  │
                                                                  ▼
                                                           ms-014 DONE
                                                                  │
                    ┌─────────────────────────────────────────────┘
                    ▼
  t-168 Publish first week at full cadence (blocked by t-172) ────┤
                                                                  │
                                                                  ▼
                                                           ms-015 DONE
                                                                  │
                                                                  ▼
                                                           ph-005 DONE
```

**What's unblocked right now:**
- t-170: Research positioning (done -- research complete)
- t-174: Write voice/tone guide
- t-176: Decide carousel tooling
- t-163: Write post templates


## 15. Product Literature Amendments (2026-03-03)

Cross-insights from [docs 40-42](product-insights.md) produced 5 amendments to this implementation:

1. **Stage classification:** Phase A is Empathy stage (Lean Analytics). OMTM = problem validation, not engagement rate. Each post is a micro-experiment in the Build-Measure-Learn loop.

2. **Mom Test gate:** Added t-177 — 5-10 CTO/tech lead conversations needed before Phase C. Market validated, customers not yet validated. Seek commitment currencies: time, reputation, money.

3. **Consulting whole product:** Added t-178 — define service offering (menu, pricing, process) before inbound arrives. Content is core product; whole product includes services definition. Blocked by t-177 (conversations inform offering).

4. **OST tracking structure:** Each weekly batch maps to Torres's Opportunity Solution Tree. Track which opportunity branches move, not just which posts performed. Replace gut-feel pillar adjustment with structured learning.

5. **Build trap warning:** If 12 manual posts produce zero advancement signals from the target audience, the answer is pivot — not "build the skill." The /content-draft gate (t-166 blocked by t-172) is the escape valve.

---

## 15. The Bigger Picture

This pipeline isn't just about LinkedIn posts. It's about making visible the work you're already doing.

```
SYSTEMS YOU DESIGN                    CONTENT YOU PRODUCE
────────────────────                  ────────────────────

  Brana (AI dev system)        ──→    Build-in-public, how-tos
  Somos Mirada (CRM + AI)     ──→    Case studies
  NexEye (computer vision)    ──→    Case studies
  Proyecto Anita (WhatsApp)   ──→    Case studies
  Psilea (venture ops)        ──→    Case studies
  TinyHomes (marketplace)     ──→    Case studies

         │                                   │
         ▼                                   ▼
  PROOF THAT YOU                      AUDIENCE THAT
  DESIGN SYSTEMS                      NEEDS SYSTEMS
         │                                   │
         └──────────────┬────────────────────┘
                        ▼
                   CONSULTING
              (month 6+ outcome)
```

The content is the bridge between what you do and who needs it. Brana is the documented case. Your portfolio is the proof. The pipeline makes it visible.

No shortcuts. No AI-generated fluff. Real work, documented honestly, shared with people who need it.
