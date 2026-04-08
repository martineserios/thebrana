# Venture Playbook & Product Management Layer

> Brainstormed 2026-04-07. Status: idea.
> User-facing reference: [docs/guide/workflows/venture.md](../guide/workflows/venture.md)

## Problem

Brana has 7+ deep research docs on product/business management (docs 28, 34, 38, 40, 41, 42, SMB marketing, client retention) but they're dead knowledge — not connected to daily workflow. Ventures lack a structured guide for stage-appropriate practices. The GROW job has only 3 skills (review, harvest, client-retire) while BUILD has a full toolkit.

## Core Principle: Brana = Strategy Layer

Brana handles **thinking, research, evaluation, and decisions**. Operations (data entry, payments, leads) stay in external tools. Brana reads from them for strategic analysis.

```
BRANA (strategy)                     EXTERNAL (operations)
├── Think: brainstorm, challenge     ├── Sheets / Airtable (data)
├── Research: market, competitive    ├── CRM / pipeline tool
├── Evaluate: experiments, metrics   ├── Ad platforms
├── Decide: pivot/persevere          ├── Accounting tools
├── Learn: extract, persist          └── Content publishing
│
├── INPUT: /brana:log captures       ← real-world events flow in
├── CONTEXT: LOAD pulls prior        ← events inform decisions
└── OUTPUT: decisions, plans         → persisted in ruflo + docs
```

## Architecture

> OS mapping (6 Jobs, composability, memory hierarchy, router, stage routing) is in [venture.md](../guide/workflows/venture.md#venture-playbook--mapping-to-the-brana-os).

### 2 New Skills (Phase 1) + 1 Phase 2 Skill

| Skill | Job | Purpose | Gaps Covered | Phase |
|-------|-----|---------|-------------|-------|
| `/brana:venture-assess` | DECIDE | Stage detection + playbook routing + OMTM recommendations | G2, G13 | 1 |
| `/brana:gtm` | GROW | Go-to-market: positioning → channels → pricing → launch | G11, G12 | 2 (when a venture reaches Growth) |

> **Experiment merged into brainstorm** (Challenge #3): `/brana:brainstorm --strategy experiment` or auto-detected when seed contains hypothesis/validation language. Adds 5 MVP types template + explicit pivot/persevere decision. Keeps skill count at 29 instead of 30.

### 4 Extended Skills (procedure edits)

Each must have a backlog task with blocked_by chains.

| Skill | Change | Gaps Covered |
|-------|--------|-------------|
| `/brana:brainstorm` | Venture-aware LOAD (auto-load playbook + dims 40-42) + BMC template in SHAPE + **experiment strategy** (hypothesis → MVP type → measure → pivot/persevere, 5 MVP types) | G3, G4, G6, G7, G10 |
| `/brana:research` | "interview" strategy (Mom Test principles) + "competitive" output format | G5, G8 |
| `/brana:onboard` | Venture scaffold mode (creates CLAUDE.md with stage, docs structure, `docs/experiments/`, `docs/metrics/` dirs) | G1 |
| `/brana:review` | Stage-aware dashboard, reads from external data sources + log, OMTM per business model archetype, `goals` subcommand for OKR scoring | G13, G15 |

### Venture Playbook Document

`docs/guide/venture-playbook.md` — stage-gated guide (does not exist yet):

| Stage | Frameworks | Key Practices | OMTM Focus |
|-------|-----------|---------------|------------|
| **Discovery** | Customer Dev, JTBD, Design Thinking, BMC | Problem interviews, hypothesis mapping, empathy maps | Problem-solution fit signal |
| **Validation** | Lean Startup, Mom Test, Lean Analytics | MVPs (5 types), smoke tests, cohort analysis, OMTM | Retention / willingness to pay |
| **Growth** | AARRR, Crossing the Chasm, Hooked | Channel experiments, funnel optimization, habit loops | Growth rate / viral coefficient |
| **Scale** | EOS, OKRs, Scaling Up | Process documentation, delegation, L10 meetings | Revenue / unit economics |

Build order starts with a 1-page skeleton (stage names + checklists + OMTM). Full synthesis is iterative.

## Research Findings

All from existing dimension docs — no new research needed:

- **Stage determines everything** (doc 28): 70% of failed startups scaled prematurely. Startups that scale properly grow 20x faster.
- **Lean Analytics OMTM** (doc 41): One Metric That Matters changes per stage. 6 business model archetypes have distinct metrics.
- **5 MVP types** (doc 41): Smoke test, concierge, wizard of oz, sell before build, single-feature.
- **Dual-Track Agile** (doc 40, Cagan): Discovery validates cheaply, Delivery builds validated items.
- **3 Engines of Growth** (doc 41, Ries): Sticky (retention), Viral (word-of-mouth), Paid (CAC < LTV).
- **Design Thinking diverge-converge** (doc 38): Open up before narrowing down.
- **Retention flywheel** (retention doc): Not linear funnels — each touchpoint reinforces the next.
- **GEO as 2026 channel** (SMB marketing): First-mover advantage in niche markets.

## Gap Analysis

Honest walkthrough: "I have an idea" → "I'm running a business" — mapped to brana's actual deployed tools.

### What works well today

~9 tools genuinely help ventures: brainstorm, research, review, backlog, close, log, gsheets, onboard + venture-scanner, challenge. DECIDE, UNDERSTAND, MAINTAIN are well-covered. Gaps concentrate in **GROW** and **operational management**.

### Gap Map

| # | Gap | Severity | Solution | Status |
|---|-----|----------|----------|--------|
| G1 | No venture project template | **HIGH** | onboard venture mode | Procedure edit |
| G2 | No `stage:` declaration standard | **MEDIUM** | venture-assess writes to CLAUDE.md | New skill |
| G3 | Brainstorm doesn't detect venture context | **MEDIUM** | brainstorm venture-aware LOAD | Procedure edit |
| G4 | No hypothesis tracking | **CRITICAL** | brainstorm experiment strategy | Procedure edit |
| G5 | No customer interview support | **HIGH** | research "interview" strategy | Procedure edit |
| G6 | No experiment tracking system | **CRITICAL** | brainstorm experiment strategy | Procedure edit |
| G7 | No Business Model Canvas tool | **MEDIUM** | brainstorm BMC template | Procedure edit |
| G8 | No competitive analysis template | **LOW** | research competitive format | Procedure edit |
| G9 | Doc references undeployed skills | **HIGH** | **Fixed** — venture.md updated | Done |
| G10 | Non-code MVPs have no tooling | **HIGH** | brainstorm experiment strategy (5 MVP types) | Procedure edit |
| G11 | No growth engine identification | **MEDIUM** | gtm skill | Phase 2 skill |
| G12 | No channel/GTM strategy tool | **HIGH** | gtm skill | Phase 2 skill |
| G13 | OMTM not wired to review | **MEDIUM** | venture-assess + review enhancement | New skill + procedure edit |
| G14 | No financial tracking | **HIGH** | **Deferred** — needs MCP + external tool | MCP not configured |
| G15 | No OKR/Rocks system | **MEDIUM** | review `goals` subcommand, markdown in `docs/okrs/` | Procedure edit |
| G16 | No pipeline management | **HIGH** | **Deferred** — needs MCP + external tool | MCP not configured |
| G17 | Harvest → publish pipeline broken | **MEDIUM** | Per-project channel-specific skills | Per-project |

**15 of 17 gaps covered.** 2 new skills (Phase 1) + 1 Phase 2 skill + 4 procedure edits + 1 fixed. **2 deferred** (G14, G16).

### Core inconsistency (fixed)

Research docs described a complete business OS. Venture workflow doc referenced undeployed skills. Fixed: venture.md now honestly separates deployed vs planned vs not-yet-available.

## Validation Strategy

Before building skill #2, run the intended workflow **manually on LinkedIn** using existing tools:
1. `/brana:brainstorm` — form a hypothesis about LinkedIn content strategy
2. `/brana:research` — competitive analysis of similar profiles
3. `/brana:review` — check current metrics
4. Document where existing tools fall short → becomes the spec for new skills

## Build Order

1. **Skeleton playbook** — 1-page `docs/guide/venture-playbook.md` (stage names + checklists + OMTM). Iterate later.
2. **Validate on LinkedIn** — run workflow manually, document gaps
3. `/brana:venture-assess` (stage detection — everything depends on knowing your stage)
4. Procedure edits: brainstorm (experiment strategy + venture LOAD + BMC) → onboard (venture scaffold) → research (interview + competitive) → review (stage-aware + goals)
5. `/brana:gtm` (Phase 2 — when a venture reaches Growth)
6. Connect external data sources via MCP when needed
7. ADR: "Venture GROW architecture — strategy layer, 2+1 skills, log as context input"

Each step gets a backlog task with blocked_by chains when `/brana:backlog plan` runs.

## Challenge History

4 rounds of challenge/correction shaped this architecture:

1. **Challenge #1** (playbook proposal): RECONSIDER → **OVERRIDDEN**. Premature optimization + complexity budget. User: brana is a venture OS, skills are core.
2. **Challenge #2** (two-rhythm architecture): RECONSIDER → **ACCEPTED WITH CHANGES**. Log can't be mutated (design contract). Sheets MCP unvalidated. Led to strategy-layer reframing.
3. **User correction**: Brana = strategy layer, not operations. `/brana:track` dropped.
4. **Challenge #3** (final architecture): PROCEED WITH CHANGES. Experiment merged into brainstorm. Skeleton playbook first. G14/G16 deferred (honest). OKRs (G15) restored — pure strategy, no MCP needed. GTM to Phase 2. Validate on LinkedIn first.

### Key Decisions

- **Brana = strategy layer** — operations stay in external tools
- **Experiment is a brainstorm strategy**, not a separate skill (complexity budget)
- **Log stays as-is** — append-only inbox, not structured data entry
- **Markdown-first** — venture data in docs/, Sheets as optional view layer
- **Manual stage declaration** in CLAUDE.md — auto-detect as bonus
- **Playbook must be portfolio-specific** — not generic restatement of research
- **Validate before building** — manual LinkedIn test before skill #2

### Observations Addressed

- Pipeline-tracker and metrics-collector agents fire based on dirs (`docs/metrics/`, etc.) that may not exist → onboard venture scaffold creates them
- OMTM-per-archetype is a playbook lookup table, not a skill feature
- Venture-assess value = stage detection + routing, not the OMTM lookup itself
