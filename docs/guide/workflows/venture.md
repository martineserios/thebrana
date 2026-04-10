# Venture Management

> Design rationale, gap analysis, and challenge history: [venture-playbook-product-management.md](../../ideas/venture-playbook-product-management.md)

Brana includes tools for managing business projects -- stage-appropriate frameworks, metrics, and reviews.

## What's available today

### Deployed skills (available in every session)

| Skill | Job | What it does |
|-------|-----|-------------|
| `/brana:brainstorm` | DECIDE | Explore and shape business ideas interactively |
| `/brana:research` | UNDERSTAND | Desk research, competitive evaluation, deep dives |
| `/brana:onboard` | UNDERSTAND | Scan and diagnose a project (auto-detects venture type) |
| `/brana:review` | GROW | Weekly/monthly health check with metrics |
| `/brana:review check` | GROW | Ad-hoc AARRR funnel audit with traffic-light metrics |
| `/brana:harvest` | GROW | Extract content/post ideas from recent work (scoped to `ventures/linkedin/.claude/skills/harvest` as of 2026-04-06 — only available when operating inside that venture) |
| `/brana:client-retire` | GROW | Archive a client's patterns when retiring |
| `/brana:backlog` | DECIDE | Task management, phases, priorities (works for business tasks) |
| `/brana:log` | CAPTURE | Quick event capture (calls, meetings, ideas, links) |
| `/brana:gsheets` | CAPTURE | Google Sheets integration for metrics/data |
| `/brana:challenge` | DECIDE | Adversarial review of business decisions |
| `/brana:close` | CAPTURE | Session learnings captured, patterns persisted |
| `/brana:export-pdf` | SHIP | Convert markdown to PDF (proposals, SOPs) |

### Deployed agents

| Agent | When it fires | What it does |
|-------|--------------|-------------|
| `venture-scanner` | New business project, health audit | Classify stage, recommend frameworks, identify gaps |
| `daily-ops` | Session start on venture project | Daily focus card, health snapshot, pending actions |
| `metrics-collector` | `/brana:review` runs | Gather data from docs/metrics/, experiments/, pipeline/ |
| `pipeline-tracker` | Pipeline or deal events | Pipeline status, overdue follow-ups, conversion trends |

### Planned skills (not yet deployed)

These skills are designed in the [Venture Playbook idea doc](../../ideas/venture-playbook-product-management.md) but not yet built:

| Skill | Job | Purpose | Status |
|-------|-----|---------|--------|
| `/brana:experiment` | GROW | Lean Startup loop: hypothesis → MVP → measure → pivot/persevere | Designed |
| `/brana:gtm` | GROW | Go-to-market: positioning, channels, pricing, launch | Designed |
| `/brana:venture-assess` | DECIDE | Stage detection + playbook routing | Designed |

### Client-local skills (not yet available)

These were designed as client-local skills but are not yet implemented. They are documented in dimension docs (28, 34) as future work:

| Skill | Purpose | Status |
|-------|---------|--------|
| `pipeline` | Lead/deal/follow-up management | Designed (doc 34). Deferred — requires MCP + external tool setup. |
| `financial-model` | Revenue projections, P&L, unit economics | Designed (doc 34). Deferred — requires MCP + external tool setup. |
| `venture-phase` | Business milestones (launch, fundraise, expansion, hiring) | Designed (doc 28). Not yet built. |
| `proposal` | Client proposal generation (interview-driven, Spanish) | Designed. Not yet built. |

## Getting started with a business project

```
/brana:onboard              -- scan and diagnose (auto-detects venture clients)
/brana:align                -- implement stage-appropriate structure
```

Brana detects venture clients by looking for `docs/sops/`, `docs/okrs/`, `docs/metrics/`, or business keywords in CLAUDE.md. The `session-start.sh` hook auto-detects venture projects and nudges the daily-ops agent.

> **Gap:** No `init-venture` command exists yet. You manually create the directory and CLAUDE.md. Add `stage: discovery` to your venture's CLAUDE.md frontmatter for stage-aware routing.

### Voice-first intake (when you only have audio)

If the venture dir has audio files in `inbox/` but no CLAUDE.md — common when a founder describes their idea in WhatsApp voice notes — use `brana transcribe` before running `/brana:onboard`:

```bash
# Transcribe all inbox audio
for f in inbox/*.{ogg,mp3,m4a,wav}; do
  [ -f "$f" ] && LD_LIBRARY_PATH=/home/martineserios/.local/lib brana transcribe "$f"
done
# Consolidate → use as source for CLAUDE.md + ADR-001
```

`/brana:onboard` detects this case and offers to transcribe automatically (see Field Notes in `system/procedures/onboard.md`). Every claim derived from audio must trace to a specific recording.

## Business stages

Every recommendation is stage-aware. Never over-systematize for the current stage.

| Stage | Revenue | Team | Focus |
|-------|---------|------|-------|
| **Discovery** | None | 1-3 | Problem validation |
| **Validation** | Some | 2-10 | Product-market fit |
| **Growth** | Repeatable | 10-50 | Scaling processes |
| **Scale** | Established | 50+ | Sustaining growth |

## Periodic reviews

```
/brana:review                -- weekly health check (default)
/brana:review monthly        -- monthly close + forward plan (P&L, actuals vs projections)
/brana:review check          -- ad-hoc AARRR funnel audit with traffic-light metrics
```

The metrics-collector agent gathers data from `docs/metrics/`, `docs/experiments/`, `docs/pipeline/`, and `docs/financial/` before the review skill analyzes it.

> **Gap:** Review is not yet stage-aware — it doesn't pull OMTM recommendations based on your venture's stage or business model archetype (Lean Analytics). Planned for venture-assess integration.

## Venture Playbook — Mapping to the Brana OS

> Designed 2026-04-07. Based on idea doc `docs/ideas/venture-playbook-product-management.md`.
> Research base: dimension docs 28, 34, 38, 40, 41, 42 + SMB marketing + client retention.

### Brana = Strategy Layer

Brana handles **thinking, research, evaluation, and decisions**. Operations (data entry, payments, lead management, ad execution) happen in external tools. Brana reads from them for strategic analysis.

```
BRANA (strategy)                     EXTERNAL (operations)
├── Think: brainstorm, challenge     ├── Sheets / Airtable (data)
├── Research: market, competitive    ├── CRM / pipeline tool
├── Evaluate: experiments, metrics   ├── Ad platforms
├── Decide: pivot/persevere          ├── Accounting tools
├── Learn: extract, persist          └── Content publishing
│
├── INPUT: /brana:log captures       ← real-world events flow in
│          what happened
├── CONTEXT: LOAD pulls prior        ← logged events inform
│            events into skills        future decisions
└── OUTPUT: decisions, plans         → persisted in ruflo + docs
```

The venture playbook operationalizes 7+ research docs into the brana OS — connecting business best practices to the 6 Jobs, auto-learning loop, memory hierarchy, and smart router.

### How New Skills Fit the 6 Jobs

```
┌──────────────────────────────────────────────────────────────┐
│                  THE SOLO OPERATOR'S 6 JOBS                  │
│                                                              │
│  AUTO-LEARNING LOOP (embedded in all thinking-jobs)          │
│  LOAD → WORK → EXTRACT → EVALUATE → PERSIST  (+weekly DECAY)│
│                                                              │
├──────────────────────────────────────────────────────────────┤
│  1. DECIDE        + /brana:venture-assess                    │
│                     stage detection → playbook routing        │
│                                                              │
│  2. UNDERSTAND    (unchanged — /research covers              │
│                    market research via "evaluate" strategy)   │
│                                                              │
│  3. BUILD         (unchanged — MVPs are /build greenfield)   │
│                                                              │
│  4. SHIP          (unchanged — launches are /ship)           │
│                                                              │
│  5. MAINTAIN      (unchanged)                                │
│                                                              │
│  6. GROW          + /brana:experiment                         │
│                     hypothesis → MVP → measure → learn       │
│                   + /brana:gtm                                │
│                     positioning → channels → pricing → launch│
│                   existing: review, harvest, client-retire    │
│                                                              │
│  + CAPTURE        /brana:log (unchanged)                     │
└──────────────────────────────────────────────────────────────┘
```

### Job Composability — How Venture Skills Chain

```
DECIDE ─── venture-assess detects stage ──→ routes to GROW skills
  │
  ├──→ GROW: experiment (Validation stage)
  │      ├──→ UNDERSTAND: research (market/competitor analysis)
  │      ├──→ BUILD: build greenfield (MVP construction)
  │      └──→ SHIP: ship (launch MVP to users)
  │
  ├──→ GROW: gtm (Growth stage)
  │      ├──→ UNDERSTAND: research evaluate (channel comparison)
  │      ├──→ BUILD: build feature (landing pages, integrations)
  │      └──→ GROW: review venture (measure GTM metrics)
  │
  └──→ GROW: review venture (any stage — health check)
         └──→ DECIDE: backlog plan (reprioritize based on metrics)
```

### Memory Hierarchy — Where the Playbook Lives

```
┌─────────────────────────────────────────────────────────────┐
│  CORE MEMORY (always in context)                            │
│  CLAUDE.md — updated GROW section references playbook       │
│  venture CLAUDE.md — stage: discovery|validation|growth     │
├─────────────────────────────────────────────────────────────┤
│  ARCHIVAL MEMORY (searched on demand via LOAD)              │
│  docs/guide/venture-playbook.md       ← the playbook       │
│  brana-knowledge/dimensions/                                │
│    28-startup-smb-management.md       ← source research     │
│    34-venture-operating-system.md                           │
│    38-design-thinking.md                                    │
│    40-product-discovery-literature.md                       │
│    41-growth-metrics-market-strategy-literature.md          │
│    42-product-operations-literature.md                      │
│    smb-marketing-channels.md                                │
│    client-retention-engagement.md                           │
│  ruflo: namespace "pattern" (experiment results, GTM data)  │
├─────────────────────────────────────────────────────────────┤
│  EXTERNAL (fetched when needed)                             │
│  Google Sheets (metrics), MCP tools                         │
└─────────────────────────────────────────────────────────────┘
```

The playbook is **archival memory** — pulled in by LOAD when venture skills run. The 7 dimension docs remain the source research; the playbook is the synthesis layer that routes to them.

### Auto-Learning Loop — Applied to Venture Skills

| Skill | LOAD scope | WRITE-BACK |
|-------|-----------|------------|
| `/brana:experiment` | Playbook (current stage) + dim 41 (Lean Analytics) + prior experiments | Auto: experiment results to ruflo. Prompt: pivot/persevere decisions as ADRs. |
| `/brana:gtm` | Playbook (Growth section) + SMB marketing doc + prior GTM plans | Auto: channel data to ruflo. Prompt: positioning decisions. |
| `/brana:venture-assess` | Playbook (all stages) + venture CLAUDE.md + project state | Auto: stage classification to ruflo. Prompt: stage transition decisions. |
| `/brana:review` (enhanced) | + stage-specific OMTM from playbook | Auto: metrics. Prompt: strategic findings. |

### Smart Router — Venture Context

| Level | Signal | Routes to |
|-------|--------|-----------|
| **1. Signal match** | `stage: discovery` in venture CLAUDE.md | venture-assess → Discovery playbook section |
| **1. Signal match** | `tags: [experiment, hypothesis]` in task | experiment skill |
| **1. Signal match** | `tags: [gtm, launch, channels]` in task | gtm skill |
| **2. LLM classify** | "How should I launch this?" | gtm skill |
| **2. LLM classify** | "Is my product working?" | experiment (validation) or review (metrics) |
| **3. Ask user** | Ambiguous growth context | AskUserQuestion with stage-aware options |

### Stage → Skill Routing Table

```
┌─────────────┬──────────────────────────────────────────────┐
│  DISCOVERY   │  brainstorm, research, onboard               │
│              │  venture-assess (detect + confirm stage)      │
│              │  Frameworks: Customer Dev, JTBD, Design       │
│              │  Thinking, Business Model Canvas              │
│              │  OMTM: problem-solution fit signal            │
├─────────────┼──────────────────────────────────────────────┤
│  VALIDATION  │  experiment, review, build                    │
│              │  research evaluate (channel/tool comparison)  │
│              │  Frameworks: Lean Startup, Mom Test,          │
│              │  Lean Analytics (OMTM, 5 stages)             │
│              │  OMTM: retention / willingness to pay         │
├─────────────┼──────────────────────────────────────────────┤
│  GROWTH      │  gtm, experiment, review, harvest             │
│              │  build feature (landing pages, integrations)  │
│              │  Frameworks: AARRR Pirate Metrics, Crossing   │
│              │  the Chasm, Hooked, SMB Marketing Channels    │
│              │  OMTM: growth rate / viral coefficient        │
├─────────────┼──────────────────────────────────────────────┤
│  SCALE       │  review, scheduler, reconcile, ship           │
│              │  Frameworks: EOS, OKRs, Scaling Up            │
│              │  OMTM: revenue / unit economics               │
└─────────────┴──────────────────────────────────────────────┘
```

### Component Model

| Component | Instance | Role |
|-----------|----------|------|
| **Skill** | `/brana:experiment` | Lean Startup workflow (interactive) |
| **Skill** | `/brana:gtm` | GTM planning workflow (interactive) |
| **Skill** | `/brana:venture-assess` | Stage assessment + routing (interactive) |
| **Agent** | `venture-scanner` (enhanced) | Auto-detect stage from project artifacts (Haiku) |
| **Doc** | `docs/guide/venture-playbook.md` | Stage-gated reference (the playbook) |
| **CLI** | `brana backlog` (existing) | Task management for experiments/GTM tasks |
| **MCP** | Google Sheets (existing) | Metrics tracking for experiments |

### Integration with OS Phased Rollout

The venture playbook ships independently — it doesn't depend on any OS phase. But it gets better as phases roll out:

| OS Phase | Venture Playbook Benefit |
|----------|------------------------|
| **Phase A** (EXTRACT in /close) | Experiment results auto-extracted at session end |
| **Phase B** (LOAD in thinking skills) | Playbook + prior experiments auto-loaded into context |
| **Phase C** (full loop) | Experiment learnings auto-persisted to ruflo |
| **Phase D** (graph + decay) | Experiment results connected via typed edges, stale experiments flagged |

## Key principle

Don't over-systematize. EOS for a pre-PMF startup is harmful. Wait until a process repeats 3+ times before writing an SOP.
