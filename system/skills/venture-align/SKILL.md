---
name: venture-align
description: "Set up business management structure — stage-appropriate templates, SOPs, OKRs, metrics, meeting cadences. Use when setting up or restructuring a business project's management framework."
group: venture
depends_on:
  - venture-onboard
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Glob
  - Grep
---

# Venture Align

Active alignment pipeline for business projects: DISCOVER → ASSESS → PLAN → IMPLEMENT → VERIFY → DOCUMENT.

Unlike `/venture-onboard` (diagnostic, read-only), this skill creates files, directories, and templates. See [28-startup-smb-management.md](../../enter/28-startup-smb-management.md) for framework research and [29-venture-management-reflection.md](../../enter/29-venture-management-reflection.md) for the skill architecture rationale.

**Analog of:** `/project-align` (active, creates files/structure)

---

## Phase 0: DISCOVER

If `/venture-onboard` was run this session, use its output (stage, domain, gaps, framework recommendation). Otherwise, run a discovery interview:

1. **What's the business?** — one-sentence description.
2. **What stage?** — Discovery / Validation / Growth / Scale. Revenue? Team size?
3. **Current tools/processes?**
4. **Pain points?**
5. **What frameworks are you using (if any)?**

Classify the stage using the four-stage model from doc 28. **Confirm with the user before proceeding.**

**Framework discipline:** Stage-aware frameworks are powerful but easy to over-load. When setting up OKRs alongside other frameworks (EOS Rocks, Shape Up cycles), follow the stacking rule from [28-startup-smb-management.md](../../enter/28-startup-smb-management.md): **maximum 3 active layers** (operating system + goal system + cadence), and don't run EOS Rocks + OKRs as parallel goal systems — Rocks already ARE quarterly goals. If > 3 frameworks are detected during DISCOVER, warn the user and recommend dropping a layer before adding structure.

---

## Phase 1: ASSESS

Spawn the `venture-scanner` agent for the diagnostic. Pass it the project path and any context from DISCOVER. Use its stage classification, gap report, and framework recommendation as the assessment input.

If the agent is unavailable, run the assessment manually. Items are cumulative — each stage includes all items from previous stages.

### Foundation (all stages)

- [ ] **F1 — Project description** documented (CLAUDE.md or README)
- [ ] **F2 — Decision log** exists (docs/decisions/)
- [ ] **F3 — Key metrics** identified and tracked (docs/metrics/)
- [ ] **F4 — Communication cadence** defined (docs/meetings/ or documented somewhere)

### Validation Stage (adds to Foundation)

- [ ] **V1 — Customer hypothesis** documented (who, what problem, what solution)
- [ ] **V2 — MVP definition** exists (what we're testing, success criteria)
- [ ] **V3 — Experiment tracking** (what we're testing, results, conclusions)
- [ ] **V4 — Burn rate** tracked (monthly spend, months of runway)
- [ ] **V5 — Referrer/partner tracking** (acquisition channel attribution, referrer performance)

### Growth Stage (adds to Validation)

- [ ] **G1 — OKRs or Rocks** defined (quarterly objectives with measurable key results)
- [ ] **G2 — SOPs** for repeatable processes (docs/sops/)
- [ ] **G3 — Meeting cadence** implemented (daily, weekly, monthly, quarterly)
- [ ] **G4 — Hiring plan** exists (roles needed, timeline, budget)
- [ ] **G5 — Decision framework** for key decisions (RACI, RAPID, or documented in ADRs)

### Scale Stage (adds to Growth)

- [ ] **S1 — Org chart / team topology** documented
- [ ] **S2 — Department-level OKRs** cascading from company OKRs
- [ ] **S3 — Process automation** documented (Zapier/n8n workflows, integrations)
- [ ] **S4 — Financial dashboard** with stage-appropriate metrics (Rule of 40, LTV:CAC)
- [ ] **S5 — Onboarding playbook** for new hires

### Classify each item as:
- **present** — fully satisfied
- **partial** — exists but incomplete
- **missing** — not found

Output a gap report grouped by category with visual progress:

```
Foundation:  ■■□□    2/4
Validation:  □□□□    0/4
Growth:      □□□□□   0/5  (if applicable)
Scale:       □□□□□   0/5  (if applicable)
```

---

## Phase 2: PLAN

Generate an ordered implementation plan from the gaps.

### Dependency Order

Foundation must come first (need CLAUDE.md before referencing it). Then stage-specific items in order:

1. Foundation items (F1-F4)
2. Validation items (V1-V4) — if Validation+
3. Growth items (G1-G5) — if Growth+
4. Scale items (S1-S5) — if Scale

### Output

Numbered action list with what will be created/modified for each item. **Wait for user approval before proceeding.**

---

## Phase 3: IMPLEMENT

Execute the plan item by item. Ask for confirmation before each major step.

### Foundation Items

**F1 — Project description:**

If `.claude/CLAUDE.md` exists, read it and merge business context. If not, create:

```markdown
# {Business Name}

{One-sentence description from DISCOVER}

## Business Context

- **Stage:** {Discovery | Validation | Growth | Scale}
- **Domain:** {SaaS | Marketplace | Service | ...}
- **Team size:** {N}
- **Framework:** {EOS | OKRs | Lean Startup | ...}

## Key Decisions

See `docs/decisions/` for business ADRs.

## Conventions

{Any established conventions discovered during assessment}
```

For brownfield: never overwrite — read first, merge, ask if there's a conflict.

**F2 — Decision log:** `mkdir -p docs/decisions`. Create a first business ADR using the `/decide` pattern:

```markdown
# ADR-001: Business Management Framework Selection

**Date:** {today}
**Status:** proposed

## Context

{Why we're choosing this framework, based on stage and DISCOVER answers}

## Decision

{The framework recommendation from venture-onboard or DISCOVER}

## Consequences

{What this enables and what constraints it introduces}
```

**F3 — Key metrics:** `mkdir -p docs/metrics`. Create `docs/metrics/README.md`:

```markdown
# Key Metrics

Stage: {current stage}
Last updated: {today}

## Tracked Metrics

{Stage-appropriate metrics from doc 28:}

### Discovery Stage
| Metric | Current | Target | Notes |
|--------|---------|--------|-------|
| Customer interviews completed | | 20+ | |
| Hypotheses validated | | | |
| Problem-solution fit confidence | | High | |

### Validation Stage
| Metric | Current | Target | Notes |
|--------|---------|--------|-------|
| MRR | | | |
| Activation rate | | | |
| Retention (monthly) | | >80% | |
| Burn rate (monthly) | | | |
| Runway (months) | | 12+ | |

### Growth Stage
| Metric | Current | Target | Notes |
|--------|---------|--------|-------|
| MRR | | | |
| CAC | | | |
| LTV | | | |
| LTV:CAC ratio | | 3:1+ | |
| Churn (monthly) | | <5% | |
| Gross margin | | >70% (SaaS) | |

### Scale Stage
| Metric | Current | Target | Notes |
|--------|---------|--------|-------|
| ARR | | | |
| Net revenue retention | | >110% | |
| Burn multiple | | <2x | |
| Rule of 40 score | | 40+ | |
| Employee NPS | | >50 | |
```

Select the appropriate stage table. Remove stages that don't apply.

**F4 — Communication cadence:** `mkdir -p docs/meetings`. Create `docs/meetings/cadence.md`:

```markdown
# Meeting Cadence

Stage: {current stage}
Last updated: {today}

{Stage-appropriate cadence:}

## Discovery
| Meeting | Frequency | Duration | Attendees | Purpose |
|---------|-----------|----------|-----------|---------|
| Founder sync | Weekly | 30 min | Founders | Review learnings, plan experiments |

## Validation
| Meeting | Frequency | Duration | Attendees | Purpose |
|---------|-----------|----------|-----------|---------|
| Team sync | Weekly | 30 min | All | Status, blockers, priorities |
| Metrics review | Monthly | 60 min | Founders | Review metrics, adjust strategy |

## Growth (EOS L10 pattern)
| Meeting | Frequency | Duration | Attendees | Purpose |
|---------|-----------|----------|-----------|---------|
| Daily standup | Daily | 15 min | Team | Blockers, priorities |
| Weekly L10 | Weekly | 90 min | Leadership | Scorecard, rocks, issues |
| Monthly review | Monthly | 2 hours | All | Metrics, wins, learnings |
| Quarterly planning | Quarterly | Full day | Leadership | Set OKRs/Rocks |

## Scale (Full cadence)
| Meeting | Frequency | Duration | Attendees | Purpose |
|---------|-----------|----------|-----------|---------|
| Daily standup | Daily | 15 min | Teams | Blockers, priorities |
| Weekly L10 | Weekly | 90 min | Dept leads | Scorecard, rocks, issues |
| 1-on-1s | Weekly | 30 min | Manager + report | Development, blockers |
| Monthly all-hands | Monthly | 60 min | Everyone | Company update, wins |
| Quarterly planning | Quarterly | Full day | Leadership | OKRs, strategy |
| Annual planning | Yearly | 2 days | Leadership | Vision, 3-year picture |
```

Select the appropriate stage table.

### Validation Stage Items

**V1 — Customer hypothesis:** Create `docs/customer-hypothesis.md` with structured hypothesis template.

**V2 — MVP definition:** Create `docs/mvp-definition.md` with scope, success criteria, timeline.

**V3 — Experiment tracking:** Create `docs/experiments/README.md` with experiment log template.

**V4 — Burn rate:** Add burn rate row to `docs/metrics/README.md` if not present.

**V5 — Referrer/partner tracking:** Create `docs/referrer-tracking.md` if the business has referral partners, therapists, affiliates, or sales agents:

```markdown
# Referrer / Partner Tracking

Last updated: {today}

## Active Referrers

| ID | Name | Type | Clients Referred | Revenue Generated | Status |
|----|------|------|-----------------|-------------------|--------|
| {id} | {name} | {type} | {count} | ${amount} | Active / Inactive |

## Channel Attribution

Each client should have a `CANAL_ORIGEN` (acquisition channel) and `REFERIDO_POR` (specific referrer, if applicable).

| Channel | Clients | % of Total | Revenue | % of Revenue |
|---------|---------|-----------|---------|-------------|
| {channel} | {count} | {%} | ${amount} | {%} |

## Notes

- Attribution uses first-touch: the channel/person who brought the client in originally
- Track even if informal — "friend of founder" is a channel worth measuring
- Flag concentration: if any single channel or referrer represents >40% of clients, diversification is needed
```

For businesses without formal referral programs, still recommend tracking acquisition source per client — even a simple "how did you hear about us?" column is valuable.

### Growth Stage Items

**G1 — OKRs:** `mkdir -p docs/okrs`. Create `docs/okrs/TEMPLATE.md`:

```markdown
# OKRs — Q{N} {YEAR}

## Company Objective 1: {What we want to achieve}

| Key Result | Target | Current | Status |
|-----------|--------|---------|--------|
| KR1: {Measurable result} | {target} | | |
| KR2: {Measurable result} | {target} | | |
| KR3: {Measurable result} | {target} | | |

## Company Objective 2: {What we want to achieve}

| Key Result | Target | Current | Status |
|-----------|--------|---------|--------|
| KR1: {Measurable result} | {target} | | |
| KR2: {Measurable result} | {target} | | |

---

## Input Metrics (Leading Indicators)

Lagging indicators (MRR, users) tell you what happened. Input metrics tell you what's *about to* happen. Track both.

| Input Metric | Target | Current | Status |
|-------------|--------|---------|--------|
| Experiments run this quarter | {target} | | |
| Customer interviews conducted | {target} | | |
| Processes automated / SOPs created | {target} | | |
| {Custom leading indicator} | {target} | | |

---

**Review date:** {end of quarter}
**Grading:** 0.0 (no progress) → 1.0 (fully achieved). Target 0.7 (ambitious but achievable).
```

**G2 — SOPs:** `mkdir -p docs/sops`. Create `docs/sops/README.md` with index. Suggest running `/sop` to create individual SOPs.

**G3 — Meeting cadence:** Already covered by F4.

**G4 — Hiring plan:** Create `docs/hiring-plan.md` with role table template.

**G5 — Decision framework:** Document in CLAUDE.md — reference `docs/decisions/` and suggest RAPID for major decisions.

### Scale Stage Items

**S1-S5:** Create corresponding documents in `docs/` following the same pattern — templates with stage-appropriate content.

---

## Phase 4: VERIFY

Re-run the alignment checklist from Phase 1 and compare before/after:

```
VENTURE ALIGNMENT REPORT
========================
Stage: {Growth}

                Before    After
Foundation:     ■■□□      ■■■■    2/4 → 4/4
Validation:     ■■□□      ■■■■    2/4 → 4/4
Growth:         □□□□□     ■■■□□   0/5 → 3/5
                ──────    ──────
Total:          4/13      11/13

Remaining gaps:
  G4 — Hiring plan (not planning to hire yet)
  G5 — Decision framework (will build over time)
```

---

## Phase 5: DOCUMENT

### Store in ReasoningBank

```bash
source "$HOME/.claude/scripts/cf-env.sh"
```

If `$CF` is found:
```bash
cd "$HOME" && $CF memory store \
  -k "alignment:{PROJECT}:{date}" \
  -v '{"type": "venture-alignment", "stage": "...", "score_before": N, "score_after": N, "items_created": [...], "framework": "..."}' \
  --namespace business \
  --tags "project:{PROJECT},type:alignment,stage:{STAGE}"
```

Fallback: append to `~/.claude/projects/{project-hash}/memory/MEMORY.md`.

### Update portfolio.md

Add or update the business project entry in `~/.claude/memory/portfolio.md`.

### Suggest next steps

- "Run `/retrospective` after your first real business session to start building patterns"
- "Use `/sop` to document your first repeatable process"
- "Use `/venture-phase` when ready to execute a business milestone"
- "Run `/growth-check` periodically to monitor business health"

---

## Difference from `/venture-onboard`

| Aspect | `/venture-onboard` | `/venture-align` |
|--------|-------------------|-----------------|
| **Purpose** | Diagnostic (read-only) | Active (creates files, configures) |
| **Speed** | Minutes | Guided session (longer) |
| **Output** | Gap report | Implemented structure + report |
| **When** | Quick health check | Initial setup or major realignment |
| **Files modified** | None | Many: CLAUDE.md, docs/*, templates |
| **User interaction** | Discovery interview | Interview + confirmations per step |

Use `/venture-onboard` for a quick look. Use `/venture-align` when you want to fix what `/venture-onboard` finds.

---

## Rules

- **Ask for confirmation before each major step** (creating directories, writing files)
- **Never overwrite existing files** — read first, merge, or ask the user
- **Stage drives everything** — don't implement Growth items for a Discovery-stage business
- **Don't systematize too early** — doc 28 principle: wait until a process repeats 3+ times before writing an SOP
- **Store results in ReasoningBank when available, fall back to auto memory when not**
- **Ask for clarification whenever you need it.** If the stage is ambiguous, the business context is unclear, or you're unsure which items to prioritize — ask.
