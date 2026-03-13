# 29 - Venture Management: From Code Projects to Any Project

Reflection on [28-startup-smb-management.md](../../../brana-knowledge/dimensions/28-startup-smb-management.md). Synthesizes what transfers, what doesn't, what the system needs to support non-code projects, and how the skill architecture should evolve.

---

## The Core Insight: One Loop, Different Artifacts

The brana system's learning loop is already domain-agnostic:

```
research → synthesize → plan precisely → execute → debrief → maintain
```

This is identical to:
- **Lean Startup:** Build → Measure → Learn
- **EOS:** Vision → Execute → Review → Adjust
- **Shape Up:** Shape → Bet → Build → Cool down
- **Customer Development:** Hypothesize → Test → Learn → Pivot/Persevere

The loop doesn't change. The **artifacts** change:

| Code Projects | Business Projects |
|---------------|-------------------|
| Tests (unit, integration, e2e) | Experiments (customer interviews, A/B tests, MVPs) |
| Code review / PR | Decision review / ADR |
| CI/CD pipeline | Continuous improvement cycle |
| Technical debt | Process debt / organizational debt |
| Spec → implement → test | Plan → execute → measure |
| `package.json`, `Cargo.toml` | Business Model Canvas, pitch deck, financial model |
| Test coverage | Metric coverage (AARRR, Rule of 40, LTV:CAC) |
| SOPs for deployment | SOPs for operations, hiring, sales |
| Sprint retrospective | Business retrospective |
| Version control (git) | Decision/process versioning |
| Feature branch | Initiative branch (a focused effort with clear scope) |

---

## What Transfers Directly (Keep As-Is)

These existing skills work for business projects without modification:

| Skill | Why It Works As-Is |
|-------|-------------------|
| `/brana:retrospective` | "Store a learning" is universal. Problem → solution → confidence → tags. Same for "customer churn spike" as for "race condition in auth." |
| `/brana:memory recall` | Querying past learnings works identically. Tag vocabulary expands (add `stage:`, `domain:`) but the mechanism is unchanged. |
| `/brana:memory pollinate` | Cross-project pattern transfer is actually *more* valuable when spanning code + business — patterns from building CI/CD pipelines inform how to build operational workflows. |
| `/brana:memory review` | ReasoningBank health check is domain-agnostic. Confidence levels, staleness, promotion — all apply. |
| `/brana:challenge` | Adversarial review of a business plan is at least as valuable as challenging a technical architecture. Same four flavors (pre-mortem, simplicity, assumption, adversarial). |
| `/brana:close` | Session close — extracting errata/learnings/issues, writing handoff notes, storing patterns. The classification (spec mismatch, process learning, issue) applies to business findings too. ADR-style decisions are captured via the build loop. |

**Implication:** 6 of the current skills need zero changes for venture work. The knowledge system (ReasoningBank, auto memory, confidence-weighted recall, promotion/demotion) is fully domain-agnostic.

---

## What Doesn't Transfer (Needs New Skills)

### Gap 1: Stage-Aware Framework Selection

Code projects don't have "stages" in the startup sense. A React app doesn't go through Discovery → Validation → Growth → Scale. But a business does, and the *entire management approach* changes at each stage.

**The problem:** A pre-PMF startup using EOS (designed for $2-50M companies) is over-engineering. A $20M company using Lean Startup (designed for hypothesis testing) is under-engineering. Wrong framework for the stage is as harmful as no framework.

**What's needed:** A diagnostic that identifies the stage and recommends stage-appropriate frameworks, metrics, meeting cadences, and organizational patterns. This is `/venture-onboard`.

### Gap 2: Operational Structure Creation

Code projects have `package.json`, `tsconfig.json`, `Dockerfile` — structure files that `project-align` can detect and create. Business projects need their own structure files:

- **SOPs** — the business equivalent of code specs. Repeatable processes documented with steps, decision points, exit criteria.
- **OKR templates** — quarterly goal-setting with measurable key results.
- **Meeting cadence docs** — which meetings happen when, with whom, about what.
- **Metric frameworks** — which numbers matter at this stage, how to track them.
- **Decision log** — ADR creation (via `/brana:build` SDD step or manual) covers code decisions; needs a business-context template for venture decisions.

**What's needed:** An active alignment skill that creates this structure. This is `/venture-align`.

### Gap 3: Business Phase Execution

`/build-phase` is tightly coupled to the brana roadmap — it reads [doc 17](../17-implementation-roadmap.md)/18, detects git tags, creates phase branches in the thebrana repo. Business milestones are different:

- **Product launch** — market research → positioning → channel strategy → launch → post-launch review
- **Hiring round** — role definition → sourcing → interviews → offer → onboarding SOP
- **Fundraise** — pitch deck → financial model → investor outreach → term negotiation
- **Market expansion** — new market research → positioning adaptation → channel testing → measure
- **Process overhaul** — audit current state → identify process debt → prioritize → implement SOPs → verify

Each is a "phase" with work items, exit criteria, and debrief loops — but the work items are business actions, not code commits.

**What's needed:** A phase execution engine that works for any milestone type. This is `/brana:venture-phase`.

### Gap 4: Process Documentation

Code has specs, tests, and inline documentation. Business has SOPs — and most businesses don't write them until it's too late (process debt compounds). Creating SOPs should be as easy as creating an ADR.

**What's needed:** A skill that interviews the user about a process and produces a structured, versioned SOP. This is `/sop`.

### Gap 5: Health Monitoring

Code projects have test suites and CI/CD. Business projects have metrics — but most founders don't systematically track them. The AARRR funnel (Acquisition → Activation → Retention → Referral → Revenue) and stage-appropriate financial metrics (MRR, CAC, LTV, Rule of 40) are the business equivalent of test coverage.

**What's needed:** A periodic health check that audits metrics against stage-appropriate benchmarks. This is `/growth-check`.

---

## The Skill Architecture: `venture-*` Namespace

### Naming Decision

`venture-*` prefix, not `biz-*` or `business-*`. Rationale:
- "Venture" implies both startups and established businesses taking on new initiatives
- Parallel to `project-*` (code) — clear namespace separation
- Short enough for command invocation (`/venture-onboard` vs `/business-project-onboard`)
- Avoids confusion with existing `project-*` skills (which remain code-focused)

### Location Decision

Same `~/.claude/skills/` directory as code skills. Rationale:
- Claude Code discovers skills by scanning one directory — separate directories require custom loader logic
- Cross-pollination between code and business skills is a feature (a pattern from CI/CD pipeline design informs operational workflow design)
- ReasoningBank is already shared across all skills — namespace separation happens via tags, not directories
- The user switches between code and business projects in the same Claude Code session

### Memory Architecture Extension

Current namespaces: `patterns`, `decisions`, `alignment`

**Add:** `business` namespace for business-specific patterns (stage transitions, framework effectiveness, milestone outcomes, metric trends). The tagging system below extends the architecture defined in [14-mastermind-architecture.md](./14-mastermind-architecture.md) (R2) — same ReasoningBank, same confidence model, different tag vocabulary.

**Tag vocabulary extension:**

| Tag | Values | Example |
|-----|--------|---------|
| `stage:` | discovery, validation, growth, scale | `stage:validation` |
| `domain:` | saas, marketplace, service, ecommerce, consulting | `domain:saas` |
| `framework:` | eos, okrs, scaling-up, shape-up, lean-startup | `framework:eos` |
| `milestone:` | launch, hiring, fundraise, expansion, process | `milestone:hiring` |
| `metric:` | mrr, cac, ltv, churn, arr, nrr | `metric:ltv-cac-ratio` |

Existing tags (`project:`, `tech:`, `type:`, `outcome:`) continue to work. Business tags layer on top.

### State Transfer and Recovery

Venture skills produce distributed artifacts across sessions: growth-check snapshots, monthly financials, pipeline deals, event logs, and task portfolios. These live in project repos and ruflo memory — losing either means losing operational continuity.

`sync-state.sh` ([ADR-015](../architecture/decisions/ADR-015-state-sync.md)) handles transfer:
- `push` persists session state (MEMORY.md, tasks.json, ReasoningBank entries) to project repos
- `pull` restores state on a new machine
- `export`/`import` handles ruflo patterns separately (embedding-dependent)

New machine recovery: `sync-state.sh pull && sync-state.sh import`. Team onboarding uses `sync-state.sh snapshot [project-dir]` for selective MEMORY.md sharing without exposing full session history.

---

## The Five New Skills

### 1. `/venture-onboard` — Diagnostic Entry Point

**Analog of:** `/project-onboard`
**Mode:** Read-only diagnostic (no file creation)
**When to use:** First session on a new business project, or periodic health check

**Core logic:**
1. Discovery interview → stage classification
2. Scan existing structure (docs, SOPs, metrics, decisions)
3. Data completeness audit — if external data stores exist (Google Sheets, CRMs, databases), assess each table for row count, missing columns, empty fields. Empty tables with correct headers are "partial" not "present." Common gaps: client acquisition channel, cash flow reconstruction, COGS for internal production, referrer attribution, stock reconciliation.
4. Pattern recall (ReasoningBank query for stage + domain)
5. Framework recommendation based on stage (from [doc 28](../dimensions/28-startup-smb-management.md) research)
6. Gap report with prioritized next steps (includes data completeness matrix alongside structural gaps)

**Key architectural decision:** Stage classification drives everything downstream. The four stages (Discovery → Validation → Growth → Scale) from the Startup Genome research are the branching point. Each stage has different:
- Framework recommendations (Lean Startup vs EOS vs Scaling Up)
- Metric priorities (feedback quality vs MRR vs Rule of 40)
- Organizational patterns (flat vs functional vs divisional)
- Meeting cadences (all-hands only vs full cadence stack)
- Risk profiles (premature scaling is the #1 killer — detect and warn)

### 2. `/venture-align` — Active Structure Setup

**Analog of:** `/project-align`
**Mode:** Active (creates files, directories, templates)
**When to use:** After `/venture-onboard` identifies gaps, or when setting up a new business project

**Core logic:** Phase pipeline (DISCOVER → ASSESS → PLAN → IMPLEMENT → VERIFY → DOCUMENT) adapted for business:

**Stage-aware checklist** (not a flat 28-item list — items depend on stage):

*Foundation (all stages):*
- Business description in CLAUDE.md
- Decision log (docs/decisions/)
- Key metrics identified
- Communication cadence defined

*Adds per stage (cumulative):*
- Validation: customer hypothesis doc, experiment tracking, burn rate tracking, referrer/partner tracking (acquisition channel attribution per client, referrer performance)
- Growth: OKRs, SOPs for repeatable processes, meeting cadence, hiring plan, decision frameworks (RACI/RAPID)
- Scale: org chart, cascading OKRs, process automation docs, financial dashboard, onboarding playbook

**Framework discipline:** Stage-aware frameworks are powerful but easy to over-load. When setting up OKRs alongside other frameworks (EOS Rocks, Shape Up cycles), follow the stacking rule from [28-startup-smb-management.md](../../../brana-knowledge/dimensions/28-startup-smb-management.md): **maximum 3 active layers** (operating system + goal system + cadence), and don't run EOS Rocks + OKRs as parallel goal systems — Rocks already ARE quarterly goals. If a framework is consuming more maintenance time than the value it produces, drop a layer. `/venture-align` should warn when > 3 frameworks are active and `/growth-check` should flag framework bloat as a health issue.

### 3. `/brana:venture-phase` — Business Milestone Execution

**Analog of:** `/build-phase`
**Mode:** Active (plans, creates docs, debriefs)
**When to use:** When executing a specific business milestone (launch, hire, fundraise, expand, overhaul)

**Key difference from `/build-phase`:** Not coupled to a specific roadmap doc. Instead, milestone types are templates:
- Product launch → pre-launch gates (timing, IP/moat, security/trust, partnerships, distribution vector) + production readiness gates (pipeline isolation, observability, rollback, cost controls, governance) + work items for go-to-market
- Hiring round → work items for recruiting
- Fundraise → work items for capital raising
- Market expansion → work items for new market entry
- Process overhaul → work items for operational improvement
- Custom → user defines work items

**Pre-launch gates** validate structural readiness before work items begin. The distribution vector gate asks "where do target users already spend time, and how do we embed there?" — building a product nobody can find is the #1 AI startup failure mode (distribution beats novelty). **Production readiness gates** apply when the launch involves deployed systems — pipeline isolation, observability, rollback capability, cost controls, and governance review. Skip for non-technical milestones.

Each follows the same loop: plan → recall → execute (with mini-debriefs) → validate → full debrief → report.

### 4. `/sop` — Standard Operating Procedure Creator

**No code analog** — business-specific
**Mode:** Active (creates docs/sops/SOP-NNN-slug.md)
**When to use:** Whenever a repeatable process needs documenting

**Design:** Mirrors ADR creation in structure — auto-increment numbering, slug generation, template application, ReasoningBank storage. But the template is SOP-specific:

```
Purpose → Owner → Trigger → Prerequisites → Steps (with decision points)
→ Exit Criteria → Common Issues → Resilience (restartability, data isolation,
degradation modes) → Metrics → Version → Review Date
```

**Key principle from [doc 28](../dimensions/28-startup-smb-management.md):** Don't systematize too early. Wait until a process repeats 3+ times. But when you do systematize, do it well — a good SOP prevents process debt the way a good spec prevents technical debt.

### 5. `/growth-check` — Business Health Audit

**No code analog** — business-specific
**Mode:** Read-only diagnostic
**When to use:** Periodically (monthly/quarterly) or when something feels wrong

**Core logic:**
1. Detect stage AND business model type (subscription, cycle/project, marketplace, consulting, service) — from existing docs or ask. Business model type is a prerequisite for metric selection: standard SaaS metrics misdiagnose non-subscription businesses (see Business model adaptation below)
2. Route to appropriate metric tables: subscription/SaaS → standard tables (MRR, churn, DAU/MAU, net retention); cycle-project/product/service → non-SaaS tables (recompra rate, AOV, channel attribution, concentration risk); marketplace → both; hybrid → combine
3. Check stage-appropriate AND model-appropriate metrics against benchmarks
4. AARRR funnel analysis — standard funnel for SaaS, adapted funnel for cycle businesses (Acquisition → First Sale → Recompra → Referral → Revenue Growth). Identify bottleneck stage
5. Channel attribution analysis — attribute each client to acquisition channel (first-touch), revenue by channel, flag concentration (>40% single channel)
6. Revenue risk signals — whale client concentration (>15%), channel dependency (>60%), outstanding AR/AP, declining recompra rate
7. Founder leverage check (teams ≤10) — what % of founder time is on unique, high-leverage work vs repeatable work? <40% = red (founder IS the bottleneck, often more impactful than any AARRR metric). Fulfills the insight from the Cardone→Sullivan/Hardy transition below: a bottlenecked founder can't fix the funnel
8. Compare current metrics to previous `/growth-check` snapshots (trend analysis)
9. Output health report: green/yellow/red per metric, bottleneck identified, recommended actions

**Business model adaptation:** Metric frameworks must adapt to the business model type, not just the stage. Standard SaaS metrics (MRR, churn rate, DAU/MAU, net revenue retention) misdiagnose non-subscription businesses — a cycle-based service with 95% "churn" may be healthy if recompra (repeat purchase) rate is strong. Non-SaaS metrics include: recompra rate (clients with 2+ purchases / total), average order value, revenue per client, channel attribution, top-client concentration, referrer contribution. See lesson #20 in [24-roadmap-corrections.md](../24-roadmap-corrections.md).

**ReasoningBank integration:** Store each check as a snapshot. Over time, build a metrics trajectory that surfaces trends across sessions.

---

## Cross-Domain Learning: The Differentiator

The most powerful aspect of this architecture is that business and code patterns live in the **same ReasoningBank**. This enables:

| From Code | To Business | Example |
|-----------|-------------|---------|
| CI/CD pipeline design | Operational workflow design | "Automated gates with rollback" → "SOP decision points with fallback procedures" |
| Spec-driven development | Spec-driven business planning | "Write the ADR before the code" → "Write the SOP before the process" |
| Technical debt management | Process debt management | "Pay it down incrementally, prioritize by blast radius" → same principle |
| Test coverage tracking | Metric coverage tracking | "What % of code paths are tested?" → "What % of AARRR stages are measured?" |
| Feature flags / gradual rollout | Pilot programs / gradual expansion | "Roll out to 10% of users first" → "Test in one market before expanding" |
| Code review culture | Decision review culture | "No PR merges without review" → "No major decision without ADR" |

And vice versa:

| From Business | To Code | Example |
|---------------|---------|---------|
| Customer development interviews | User research for features | "What job is the customer hiring this for?" → "What job is the user hiring this feature for?" |
| OKR goal-setting | Sprint goal clarity | "Measurable key results, not activity metrics" → "Don't measure velocity; measure outcomes" |
| Meeting cadence discipline | Async communication discipline | "Not every sync needs a meeting; some need a doc" → handbook-first culture |
| Hiring for Unique Ability | Team composition for complementary skills | "Hire specialists for your gaps" → "Assign tasks to the right agent type" |

This cross-pollination is what `/brana:memory pollinate` already does — but with business patterns in the ReasoningBank, it becomes dramatically more valuable. The pattern transfer architecture relies on R2's tagging system ([14-mastermind-architecture.md](./14-mastermind-architecture.md)) — `transferable: true` + technology-agnostic tags enable cross-domain recall.

---

## Cross-References: Coding Practice Docs → Business Patterns

The brana system's coding practice docs contain patterns that transfer directly to business project management. These aren't vague analogies — they're structural parallels where the same mental model applies to different artifacts.

### [Doc 03](../dimensions/03-pm-framework.md) (PM Framework) → Business Operations

The PM framework separates **code work from PM work** — dedicated repos, different cadences, different tools. The same separation applies to business: **strategy work** (vision, positioning, market research) is not **operations work** (SOPs, hiring, metrics tracking). Conflating them leads to the same failure mode as mixing features and project management in one stream: strategic thinking gets crowded out by operational urgency.

Specific transfers:
- **Feature lifecycle (SPARC phases)** → **Business initiative lifecycle.** Scope → Plan → Approve → Run → Close maps directly to business initiatives. A product launch has the same phases as a feature — it starts with scoping, needs a plan, requires approval (from stakeholders, not a PR reviewer), executes, and needs a retrospective.
- **BACKLOG.md as prioritized intake** → **Business backlog.** The same Now/Next/Later pattern from [doc 19](../19-pm-system-design.md) works for business priorities. A venture needs a single prioritized list of initiatives, not scattered ideas across Slack threads and notes apps.
- **Progressive disclosure in documentation** → **Handbook layering.** Just as CLAUDE.md shouldn't dump everything on the AI at once, business handbooks should layer: summary → detail → reference. New hires read the summary. Specialists dive into detail. Nobody reads the whole thing.

### [Doc 08](08-diagnosis.md) (Diagnosis) → Business Process Evaluation

[Doc 08](08-diagnosis.md)'s **keep/drop/defer** analysis is a general-purpose evaluation framework. Applied to business:

- **Keep** — processes that demonstrably contribute to outcomes (the sales process that closes deals, the standup that surfaces blockers)
- **Drop** — processes that exist from habit, not value ("we've always done a Monday all-hands" — has it ever surfaced a real decision?)
- **Defer** — processes that would help but aren't worth the setup cost yet (automated financial reporting when you have 3 customers)

The anti-pattern "over-engineered components to eliminate" maps directly: businesses accumulate **over-complicated processes** the same way codebases accumulate over-engineered abstractions. The weekly 2-hour planning meeting that could be a 15-minute async check-in. The 12-field CRM entry when 3 fields matter. The 40-page business plan when a 2-page canvas would suffice.

### [Doc 14](14-mastermind-architecture.md) (Mastermind Architecture) → Business Intelligence Structure

[Doc 14](14-mastermind-architecture.md)'s three-layer model maps to business organizations:

| Mastermind Layer | Business Equivalent | What It Contains |
|-----------------|---------------------|------------------|
| **Identity** (genome — who you are) | **Mission & Purpose** | Vision, values, positioning, competitive moat — the things that don't change quarter to quarter |
| **Intelligence** (connectome — what you've learned) | **Institutional Knowledge** | Market intelligence, customer patterns, pricing learnings, hiring lessons — the things you accumulate |
| **Context** (current state — what you're doing now) | **Current Initiative** | This quarter's OKRs, active clients, in-flight experiments — the things that change constantly |

The **genome vs connectome** distinction is critical for businesses too:
- **Genome** = your documented systems (SOPs, playbooks, org chart, compensation philosophy). These are stable, version-controlled, and deploy-able to new hires.
- **Connectome** = your institutional memory (why that pricing model failed, which investor actually adds value, what customers really mean when they say "it's too expensive"). This lives in people's heads — and is lost when they leave unless you capture it.

### [Doc 15](../15-self-development-workflow.md) (Self-Development) → Operational Maturity

[Doc 15](../15-self-development-workflow.md)'s genome/connectome separation maps to business operational maturity:

- **Genome (business systems):** SOPs, playbooks, job descriptions, onboarding checklists, interview rubrics — the documented, repeatable parts. These are the business equivalent of config files and deploy scripts. They can be "deployed" to any new hire or team.
- **Connectome (learned knowledge):** Market intelligence, customer behavior patterns, competitive landscape insights, supplier relationships — the accumulated wisdom. This is the business equivalent of the ReasoningBank.

Additional transfers:
- **Deploy pipeline** → **Process rollout.** New SOPs should roll out like code deploys: test in a small team first, verify it works, then expand. Don't deploy a new sales process to the entire team on Monday morning.
- **Testing** → **Process validation.** Before formalizing a process as an SOP, validate it works. Run it 3 times manually. Check that the output is consistent. The "wait until it repeats 3 times" principle from [doc 28](../dimensions/28-startup-smb-management.md).
- **Self-healing** → **Process improvement loops.** The system that detects when a hook fails and adjusts → the business that detects when an SOP isn't followed and asks "why not?" Maybe the process is wrong, not the person.

### [Doc 16](../dimensions/16-knowledge-health.md) (Knowledge Health) → Business Knowledge Poisoning

[Doc 16](../dimensions/16-knowledge-health.md)'s eight infection vectors apply directly to business knowledge. These are the ways a business's institutional memory gets corrupted:

| Knowledge Infection | Business Example |
|-------------------|-----------------|
| **Hack that works** (short-term fix becomes standard practice) | The "temporary" discount structure that becomes the default pricing. The manual export that becomes the monthly reporting process. |
| **Context-specific solution stored as universal** | What worked in Market A applied blindly to Market B. The sales script that crushed it in SMB used on enterprise prospects. |
| **Stale solution** (outdated but still trusted) | The pricing strategy from 2 years ago, pre-competitor. The hiring rubric designed for a 5-person team applied at 50. |
| **Survivorship bias** (celebrating wins without analyzing failures) | Only tracking closed deals, not lost ones. Only post-morteming failures, not studying why wins happened. |
| **Telephone game** (degraded through retelling) | The founder's pricing rationale, passed through 3 managers, now "we charge $X because we always have." |
| **Contradictory patterns** (both stored, neither flagged) | "Move fast and break things" coexisting with "zero-defect quality standards." Both are in the handbook. |
| **Confidence inflation** (assumed true because repeated) | "Our customers won't pay more than $X" — said so often it's treated as fact, never tested. |
| **Orphaned pattern** (stored but never recalled, never pruned) | The competitor analysis from 2 years ago still in the shared drive, never updated, occasionally cited. |

The **immune system** concepts transfer too: quarantine new business patterns (test them before making them standard), decay patterns that haven't been recalled (review and retire stale SOPs), run contradiction detection (audit your handbook for conflicting guidance).

### [Doc 19](../19-pm-system-design.md) (PM System Design) → Solo Founder PM

[Doc 19](../19-pm-system-design.md)'s solo PM best practices are directly applicable to solo founders and small teams:

- **Now/Next/Later** → **Business prioritization.** Three buckets, not 20-item Gantt charts. What are we doing this week? What's queued for next? What's on the horizon?
- **Weekly review** → **Business review cadence.** The weekly review from PM ("what shipped, what's blocked, what's next") maps to the business review ("what moved metrics, what's stuck, what's the next experiment").
- **Portfolio file** → **Multi-venture portfolio.** If managing multiple ventures or product lines, the portfolio pattern (one file tracking state across clients) prevents context-switching blindness.
- **Kill zombie projects** → **Kill zombie initiatives.** The initiative nobody's working on but nobody's willing to kill. The partnership "in progress" for 6 months. The feature idea that keeps getting discussed but never scoped. Apply the same rule: if it hasn't moved in 2 weeks, it's either dead or needs explicit commitment.
- **Second Brain / PARA overlap** → Business knowledge organization follows the same pattern: Projects (active initiatives), Areas (ongoing responsibilities), Resources (reference material), Archive (completed/retired).

### [Doc 22](../dimensions/22-testing.md) (Testing) → Business Process Validation

[Doc 22](../dimensions/22-testing.md)'s testing pyramid maps to a **validation pyramid for business processes:**

| Testing Layer | Business Validation Equivalent |
|--------------|-------------------------------|
| **Static validation** (linting, type-checking) | **Template compliance** — does the SOP have all required sections? Does the OKR have measurable key results? |
| **Unit tests** (single function) | **Step validation** — does each individual step in a process produce the expected output? |
| **Integration tests** (components together) | **Handoff validation** — does the output of one process feed correctly into the next? (Marketing qualified lead → sales follow-up) |
| **E2E tests** (full user journey) | **Customer journey validation** — does the full path from awareness → purchase → onboarding → value work? |
| **Chaos testing** (break things on purpose) | **Stress testing** — what happens when the process is overwhelmed? (Black Friday traffic, viral moment, key person leaves) |
| **Monitoring** (ongoing health checks) | **Metrics dashboards** — ongoing measurement of process health via KPIs, AARRR metrics, financial ratios |

The **deterministic vs non-deterministic** distinction also transfers:
- **Deterministic (process compliance):** Did the SOP get followed? Did the meeting happen on schedule? Was the report filed? These are binary — testable with checklists.
- **Non-deterministic (market response):** Did the marketing campaign convert? Did the hire work out? Did the pricing change retain customers? These require statistical thinking, not pass/fail tests.

**Headless testing** → **Metrics-based health checks.** Just as headless tests validate behavior without a UI, metrics-based process health checks validate business operations without manually reviewing every instance. If MRR is growing, churn is stable, and NPS is above threshold — the process is working, even if you didn't observe every customer interaction.

---

## The Expanded Skill Set: From 5 to 12

The initial five skills (`/venture-onboard`, `/venture-align`, `/brana:venture-phase`, `/sop`, `/growth-check`) addressed structural gaps. Research (doc 34) identified 7 additional skills for daily operations:

| Skill | Gap Addressed | Frequency |
|-------|---------------|-----------|
| `/morning` | No daily operational routine | Daily |
| `/weekly-review` | No weekly cadence enforcement | Weekly |
| `/brana:pipeline` | Gap #4 (sales/growth layer) | As needed |
| `/brana:financial-model` | Gap #2 (financial layer) | Monthly / fundraise |
| `/experiment` | Gap #4 (growth layer) | Per growth cycle |
| `/content-plan` | Gap #4 (marketing) | Per content cycle |
| `/monthly-close` | Gap #2 (financial layer) | Monthly |

`/monthly-close` now detects external data sources (Google Sheets, spreadsheets) alongside project docs. When transaction-level data is available (PAGOS, bank statements), it reconstructs cash flow with running balance, checks AR/AP with overdue flagging (>30 days), and performs a COGS reality check — verifying that reported COGS captures internal production costs, not just external purchases. This was added after real-world usage revealed that early-stage ventures often track financials in Google Sheets, not project docs, and that COGS understatement is a common blind spot (external purchases only → artificially high gross margin).

The forward-looking planning gap — no skill synthesized accumulated data into next month's action plan — is addressed by `/monthly-plan`, designed as the complement to `/monthly-close`. Where `/monthly-close` looks backward (what happened), `/monthly-plan` looks forward (what to do next), consuming growth-check snapshots, pipeline state, experiment results, financial model projections, and weekly review velocity data.

These 7 skills (plus `/monthly-plan`) connect to the existing 5: `/morning` reads `/growth-check` snapshots, `/weekly-review` aggregates `/morning` outputs, `/monthly-close` combines `/brana:financial-model` projections with `/brana:pipeline` actuals. `/monthly-plan` reads all six data sources (`/monthly-close`, `/growth-check`, `/brana:pipeline`, `/experiment`, `/brana:financial-model`, `/weekly-review`) to produce a forward-looking action plan — revenue targets, bottleneck-driven priorities, experiment proposals, pipeline actions, and budget allocation. The full interaction graph is documented in [doc 34](../dimensions/34-venture-operating-system.md), section 8.

**Supporting infrastructure:**
- 3 new agents: `daily-ops` (Haiku), `metrics-collector` (Haiku), `pipeline-tracker` (Haiku)
- MCP integrations: Google Workspace, Airtable, Mixpanel/PostHog, Stripe, QuickBooks (prioritized by stage)
- Hooks: `session-start-venture` (auto `/morning`), `post-sale` (update sheets), `weekly-reminder`

---

## Evolution Path

This reflection doc will be enriched over time as the venture skills are used and learnings accumulate.

> **Reconcile note (2026-03-09):** The t-214 build loop redesign (Mar 2026) consolidated venture skills from 12+ to 5: `/brana:venture-phase`, `/brana:review` (absorbed `/weekly-review`, `/monthly-close`, `/growth-check`, `/morning`), `/brana:pipeline`, `/brana:financial-model`, `/brana:proposal`. Skills like `/venture-onboard` and `/venture-align` merged into `/brana:onboard` and `/brana:align`. `/sop`, `/experiment`, `/content-plan`, `/monthly-plan` were retired. The phase history below reflects original skill names at time of implementation.

### Phase 1: Foundation (Complete)
- Created the five venture skills
- Extended tag vocabulary for business patterns
- Deployed alongside existing code skills

### Phase 1.5: Daily Operations (Complete)
- Built 7 new daily/weekly/monthly skills (`/morning`, `/weekly-review`, `/brana:pipeline`, `/brana:financial-model`, `/experiment`, `/content-plan`, `/monthly-close`) plus `/monthly-plan` for forward-looking synthesis
- Google Sheets MCP integration guide published, `/brana:gsheets` skill deployed for direct Sheets operations
- Deployed 3 agents: `daily-ops` (Haiku), `metrics-collector` (Haiku), `pipeline-tracker` (Haiku)
- Deployed 2 hooks: `session-start-venture` (venture detection + daily-ops nudge + weekly-review staleness), `post-sale` (deal closure detection + ReasoningBank snapshot)
- `weekly-reminder` absorbed into `session-start-venture` (Claude Code hooks don't support cron)
- GitHub Issues integration added to `/weekly-review`, `/experiment`, `/morning`

### Phase 2: Learning Accumulation
- Artifact lifecycle follows [32-lifecycle.md](./32-lifecycle.md) (R4) patterns — SOPs have review dates, OKRs have quarterly cycles, metric snapshots accumulate into trend data
- Use venture skills on real business projects
- Accumulate patterns in ReasoningBank
- Run `/debrief` and `/brana:retrospective` after business sessions
- Identify which frameworks actually work at which stages (evidence-based, not theoretical)
- **First fieldwork (2026-02-15):** psilea (cycle-product, validation stage) revealed 10 generic patterns. Four skills updated: `/growth-check` (non-SaaS metrics, adapted AARRR, channel attribution, revenue risk signals), `/monthly-close` (external data sources, cash flow reconstruction, AR/AP, COGS check), `/venture-onboard` (data completeness audit), `/venture-align` (V5 referrer tracking). Key learning: one real-project session improved skills more than three spec-driven reconcile passes (lesson #42 in [doc 24](../24-roadmap-corrections.md))

### Phase 3: Cross-Pollination
- Patterns flow between code and business projects via ReasoningBank
- `/brana:memory pollinate` surfaces insights like "your CI/CD rollback pattern maps to your SOP fallback procedure"
- Document which cross-domain transfers are high-confidence (proven) vs quarantined (unproven)

### Phase 4: Framework Refinement
- [Doc 28](../dimensions/28-startup-smb-management.md)'s framework recommendations are research-based. After real usage, update with evidence:
  - Which frameworks actually helped at which stages?
  - Which metrics actually predicted outcomes?
  - Which SOP templates were most useful?
  - Where did the stage classification model break down?
- Update this reflection doc and [doc 28](../dimensions/28-startup-smb-management.md) via `/brana:maintain-specs`

### Phase 5: Unified Project Management (Complete)
- `/project-onboard` and `/venture-onboard` merged into `/brana:onboard` — auto-detects project type (code, venture, hybrid)
- `/project-align` and `/venture-align` merged into `/brana:align`
- `/brana:review` absorbed weekly, monthly, and growth-check into one skill with subcommands
- The unified model works: one skill detects context and adapts, rather than requiring the user to pick the right variant

### Phase 6: Channel-Agnostic Access (In Progress)
[ADR-019](../architecture/decisions/ADR-019-brana-chat-sessions.md) (accepted 2026-03-13) extends brana beyond the CLI. A 3-tier access model (End User / Client / Operator) with Kapso as the WhatsApp adapter and a custom Session Manager enables venture clients (Tier 2) to interact with brana-powered agents via WhatsApp — making skills like `/brana:pipeline`, `/brana:financial-model`, and `/brana:review` potentially accessible from a client's phone. The session layer is channel-agnostic: WhatsApp first (via [Kapso](../../../brana-knowledge/dimensions/39-kapso-ai-platform.md)), then web widget, CLI chat. Implementation: ph-013, ms-048 (t-413–t-422).

---

## Resolved Questions

Originally open questions "to be resolved through usage." Resolved February 2026 through research synthesis (Startup Genome data, Sean Ellis/Superhuman PMF methodology, SOP management best practices, solopreneur tooling landscape, Cardone vs Sullivan/Hardy comparative analysis).

### 1. Stage Transition Detection

**Answer:** Multi-signal, not single metric. Each transition has a primary signal and confirming signals.

| Transition | Primary Signal | Confirming Signals | Anti-Signal (Not There Yet) |
|------------|---------------|-------------------|-----------------------------------|
| Discovery → Validation | First paying customer (or strong intent-to-pay) | Sean Ellis score trending up; retention curve not zeroing out | "People love it!" but nobody pays — enthusiasm ≠ validation |
| Validation → Growth | **Sean Ellis ≥ 40%** + LTV:CAC ≥ 3:1 + retention curve flattened | MRR growing month-over-month; organic referrals; repeatable acquisition channel found | Revenue from one-off deals or founder-led sales only — still Validation |
| Growth → Scale | **$10M+ ARR** + Rule of 40 met + processes breaking under volume | Team > 50; departments forming; founder < 40% on unique work | Revenue is there but everything runs through founder — Growth with org debt, not Scale |

**Why not a single metric?** Startup Genome found premature scaling happens when one dimension is far ahead while others lag. Revenue can hit $1M with a broken team structure — that's Validation with a revenue spike, not Growth. The test is **dimensional consistency**: product maturity, team maturity, financial maturity, and process maturity all advancing together.

**System implication:** `/growth-check` should assess all four dimensions, not just revenue. If 3 of 4 point to next stage, recommend transitioning. If 1-2 do, flag the imbalance as premature scaling risk.

**Key references:** Sean Ellis 40% test (benchmarked across ~100 startups), Superhuman's PMF engine (score rose from 22% to 58% using this methodology), Startup Genome premature scaling research (n=3,200+).

### 2. Framework Stacking

**Answer:** Layer, don't stack. Maximum 3 active layers. One operating system, one goal system, one cadence. Customer Development is always on but it's a habit, not a framework.

```
Layer 1: Operating System (pick ONE)
  - Pre-PMF: nothing formal — just the learning loop
  - $2-50M: EOS
  - $10-200M: Scaling Up

Layer 2: Goal Setting (pick ONE, optional pre-PMF)
  - OKRs (lightweight, layers on any OS)
  - EOS Rocks count as this layer — don't add OKRs on top of Rocks
    unless Rocks aren't working

Layer 3: Product Cadence (pick ONE, optional pre-Growth)
  - Shape Up (6-week cycles)
  - Scrum/Kanban (if engineering-heavy)

Always-on (not a framework, a habit):
  - Customer Development — talk to customers, test hypotheses, never stop
```

**The overload rule:** If you're spending more time maintaining the framework than doing the work, drop a layer. The framework serves the business, not the other way around.

**EOS + OKRs specifically:** EOS Rocks ARE quarterly goals. If Rocks work, you don't need OKRs. If Rocks feel too coarse, replace Rocks with OKRs inside the EOS structure. Don't run both as parallel goal systems — EOS Rocks can be reshaped into Objectives combined with measurable Key Results.

**System implication:** `/venture-align` should recommend layers based on stage and warn when > 3 active. `/growth-check` should flag framework bloat as a health issue.

### 3. SOP Maintenance Cadence

**Answer:** Event-triggered primary, calendar-triggered secondary. The calendar is a safety net, not the driver.

**Primary trigger: process change.** When the process changes (new tool, team member, regulation, pricing), update the SOP immediately. Same principle as updating tests when code changes.

**Secondary trigger: scheduled review based on velocity:**

| Business Velocity | Core SOPs | Technical/Operational SOPs | Administrative SOPs |
|-------------------|-----------|---------------------------|---------------------|
| Fast (pre-PMF, rapid iteration) | Every 3 months | Every release/sprint | Every 6 months |
| Moderate (post-PMF, growing) | Every 6 months | Every quarter | Annually |
| Stable (scaled, established) | Annually | Every 6 months | Annually |

**The real insight:** SOPs that nobody reads are already dead. The maintenance problem isn't cadence — it's **ownership**. Every SOP needs a single owner who is the person who actually does the process. If the person doing the process didn't write the SOP and doesn't maintain it, it will rot regardless of cadence.

**System implication:** `/sop` already has Owner and Review Date fields. `/growth-check` should flag SOPs past their review date. Default review date set based on velocity detected during `/venture-onboard`.

### 4. Metrics Data Source

**Answer:** Start with manual input. Graduate to tools when manual tracking hurts. Never build infrastructure before knowing which metrics matter.

| Stage | Data Source | Why |
|-------|-----------|-----|
| Discovery | **Notebook/doc** — qualitative notes from interviews | No quantitative data yet. "Number of interviews" and "recurring themes" is enough |
| Validation | **Spreadsheet** (Google Sheets) — manual monthly update, 3-5 metrics | Data is small enough to track by hand. 67% of early-stage teams do this |
| Growth | **Lightweight dashboard** (Notion, payment processor dashboard + Sheets) | Volume makes manual entry painful. Automate pulls from payment/analytics/CRM |
| Scale | **Dedicated tools** (ChartMogul, Baremetrics, or full BI stack) | Need real-time dashboards, team-visible metrics, historical trends |

**For `/growth-check`:** Manual input through conversation. Ask the user for current values during each check. Store snapshots in ReasoningBank. Over time, stored snapshots create trend data. No integrations needed — the conversation IS the data entry. The graduation from manual tracking to tooling mirrors the lifecycle progression in [32-lifecycle.md](./32-lifecycle.md) (R4) — start manual, graduate when manual hurts.

**The anti-pattern:** Don't spend 2 weeks building a metrics dashboard before having 10 customers. That's premature scaling of tooling. Track 3-5 numbers in a spreadsheet. When the update feels like a chore (not a 2-minute task), upgrade.

### 5. Adapting for Teams

**Answer:** Skills produce artifacts that humans consume. AI drafts, human edits and owns. Three design principles.

**Principle 1: Consumable format.** Every artifact should be readable by someone who has never seen the brana system:
- SOPs: step-by-step, plain language, no jargon, decision points called out, printable
- OKRs: objective + measurable key results + owner + timeline, one page max
- Meeting agendas: fixed structure, time-boxed items, clear expected output per item
- Decision records: context → decision → consequences, readable in 2 minutes
- Health reports: green/yellow/red, one paragraph per metric, recommended actions

**Artifact validation:** Each skill's output should be verifiable — [31-assurance.md](./31-assurance.md) (R3) defines the structural and behavioral assurance framework. For venture skills, "structural" means template compliance (does the SOP have all required sections?), "behavioral" means round-trip verification (is the artifact stored and recallable from ReasoningBank?).

**Principle 2: Explicit handoff.** Skill output should end with who needs to do what with this artifact:
- "Share this SOP with [team member] for review"
- "Present these OKRs at the next team meeting for alignment"
- "This decision record needs sign-off from [stakeholder]"

**Principle 3: Don't over-automate.** Skills never replace human judgment on business decisions. They draft, structure, and suggest — the human decides, approves, and acts. Same philosophy as code review: the AI writes the PR, the human merges it.

**System implication:** Template/formatting concern, not architecture change. Each skill's output template should pass the test: "would a non-technical team member understand this?" Always yes.

### 6. Cardone (Hustle) vs Sullivan/Hardy (Eliminate)

**Answer:** Sequential, not competing. Cardone for inertia. Sullivan/Hardy for chaos. The transition point is repeatable revenue.

| Situation | Use | Why |
|-----------|-----|-----|
| Pre-revenue, stuck in planning | **Cardone** — massive action, break inertia | Nothing to eliminate. The problem is too little action. "Normal Action" (Cardone's most dangerous level) feels productive but produces mediocre results |
| Pre-PMF, searching | **Cardone** — more experiments, more conversations, more MVPs | Need volume of attempts. Don't know what works yet, so bet wide |
| Post-PMF, founder drowning | **Sullivan/Hardy** — eliminate 80%, focus on the 20% | Now know what works. Problem shifted from "not enough" to "too much of the wrong things" |
| Scaling, team growing | **Sullivan/Hardy** — Who Not How, delegate, systematize | Every hour the founder spends on delegatable work is an hour NOT on their unique 20% |
| Crisis, market shift | **Cardone burst** — massive short-term action | Even in Sullivan/Hardy mode, crises demand Cardone intensity. Sprint, not lifestyle |

**The transition signal:** When you have **repeatable revenue** (not a one-off sale but a process that reliably converts), switch from Cardone to Sullivan/Hardy. Repeatable revenue means you found the 20% that works. Protect it and cut the rest.

**The trap:** Staying in Cardone mode after PMF. The hustle that found the market becomes the chaos that prevents scaling. The founder who does everything becomes the bottleneck for everything.

**System implication:** `/venture-onboard` should detect current mode from stage + founder behavior. Post-PMF founder still doing everything (< 40% time on unique problems) → recommend Sullivan/Hardy shift explicitly. `/growth-check` now implements this as Step 3b (founder leverage check).

**Leading vs lagging indicators:** OKR templates should track both. Lagging indicators (MRR, users, churn) tell you what happened. Leading indicators (experiments run, customer interviews conducted, processes automated) tell you what's about to happen. Pre-PMF, leading indicators matter more — revenue is zero for everyone, but the team running 10 experiments/month will find PMF faster than the one running 2. `/venture-align`'s OKR template now includes an input metrics section for this purpose.

---

## Sources

- [28-startup-smb-management.md](../../../brana-knowledge/dimensions/28-startup-smb-management.md) — The dimension doc this reflects on
- [08-diagnosis.md](./08-diagnosis.md) — Keep/drop/defer analysis (pattern for reflection docs)
- [14-mastermind-architecture.md](./14-mastermind-architecture.md) — Three-layer architecture (Identity, Intelligence, Context)
- [27-project-alignment-methodology.md](../../../brana-knowledge/dimensions/27-project-alignment-methodology.md) — Alignment pipeline pattern (DISCOVER → ASSESS → PLAN → IMPLEMENT → VERIFY → DOCUMENT)

### Research Sources (Question Resolution)

- [Sean Ellis PMF Survey](https://pmfsurvey.com/) — 40% "very disappointed" benchmark, ~100 startups benchmarked
- [Superhuman PMF Engine (First Round Review)](https://review.firstround.com/how-superhuman-built-an-engine-to-find-product-market-fit/) — Four-step process, score rose 22% → 58%
- [Startup Genome: Premature Scaling](https://startupgenome.com/library/a-deep-dive-into-the-anatomy-of-premature-scaling) — n=3,200+, 70% failed from premature scaling
- [EOS and OKR: Complete Guide (Mooncamp)](https://mooncamp.com/blog/eos-and-okr) — Rocks as OKR-compatible quarterly goals
- [Scaling Up vs EOS vs OKRs (Align Today)](https://aligntoday.com/blog/scaling-up-vs-eos-vs-okrs/) — Framework selection by company stage
- [SOP Review Cadence (WorkFlawless)](https://workflawless.com/articles/business-process-management/sop-updates-how-often/) — Velocity-based review recommendations
- [SOP Management Best Practices (Rostone)](https://www.rostoneopex.com/resources/managing-and-updating-standard-operating-procedures-(sops)) — Event-triggered + scheduled review
- [Solo Founders Report 2025 (Carta)](https://carta.com/data/solo-founders-report/) — Solo founder metrics and tooling patterns
- [Solopreneur Tech Stack 2026 (PrometAI)](https://prometai.app/blog/solopreneur-tech-stack-2026) — $3-12K/year stack replacing teams
