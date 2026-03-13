# Investigation: Brana OS — Process-Powered Framework for Claude Systems

> **Task:** t-407 | **Strategy:** investigation | **Date:** 2026-03-13
> **Branch:** experiment/t-407-claude-systems-marketplace

## The Idea (revised after challenge)

**Original framing (rejected):** A marketplace for individual Claude Code components (skills, hooks). Challenged as: no demand signal, unenforceable trust kernel, solo dev can't build marketplace infrastructure, platform dependency risk.

**Revised framing:** Brana is already an OS for Claude-powered processes. The work is formalizing that pattern — defining the "shape" so process systems can be built as integrated plugins on top of brana's OS layer. Not a marketplace of skills, but a **framework for designing process-powered AI systems**.

### The Shift

| Marketplace thinking (rejected) | Framework thinking (current) |
|---|---|
| Sell individual skills | Define **processes** and get integrated systems |
| Users pick components | Users pick a **process area** (PM, content, sales...) |
| Trust = sandboxing | Trust = framework guarantees coherent behavior |
| Target: developers | Target: semi-technical users who understand their process |
| Product: a store | Product: a **methodology + tooling model** |

### Core Insight

Brana doesn't work because of 28 individual skills. It works because those skills are integrated around **processes**: `/brana:build` connects to `/brana:backlog` connects to `/brana:close` connects to git discipline rules connects to memory. The value is the process design, not the individual tools.

The productizable thing: **a framework for designing Claude-powered process systems**. Define your process (areas, activities, triggers, artifacts), the framework provides the integrated skill/hook/rule/agent layer. Like Rails for web apps, but for Claude-powered workflows.

### Problems Addressed

1. **Accessibility gap** — semi-technical users can't leverage Claude Code without understanding the component model
2. **Fragmentation** — everyone builds from scratch; no reusable process patterns exist
3. **Coherence** — individual skills don't compose reliably; processes need integrated behavior
4. **Productization** — brana's consulting value can scale beyond 1:1 engagements

---

## Architecture: Brana as OS

```
┌─────────────────────────────────────────────────┐
│  Process Plugins (capabilities)                  │
│  ┌───────────┐ ┌───────────┐ ┌───────────────┐  │
│  │ Project   │ │ Content   │ │ Client        │  │
│  │ Mgmt      │ │ Pipeline  │ │ Delivery      │  │
│  └───────────┘ └───────────┘ └───────────────┘  │
│  Each = skills + hooks + rules + agents          │
│  integrated around a PROCESS, not features       │
├─────────────────────────────────────────────────┤
│  Brana OS (the framework)                        │
│  - Process definition model (areas, activities)  │
│  - Component connection patterns                 │
│  - Memory & learning system                      │
│  - Trigger & lifecycle management                │
│  - Quality enforcement (hooks, validation)       │
│  - Session lifecycle                             │
├─────────────────────────────────────────────────┤
│  Claude Code Runtime                             │
│  Plugin loader, tool executor, context window    │
└─────────────────────────────────────────────────┘
```

### What the OS Layer Provides

These are things brana already does — the framework makes them explicit and replicable:

| OS Capability | What Brana Does Today | Framework Formalization |
|---|---|---|
| **Process definition** | Skills grouped by purpose (execution, learning, venture) | Formal process model: areas → activities → triggers → artifacts |
| **Component integration** | Skills call each other (build→backlog→close) | Declared connections: "after X completes, trigger Y" |
| **Memory & learning** | MEMORY.md, ruflo, session handoffs | Memory contract: what a process stores, recalls, and forgets |
| **Quality gates** | PreToolUse hooks, validate.sh | Gate pattern: "before X, check Y" — reusable across processes |
| **Session lifecycle** | session-start → work → session-end hooks | Lifecycle contract: onStart, onComplete, onError per process |
| **Context management** | 28KB budget, rules loading | Budget allocation: how much context each process plugin gets |
| **Agent delegation** | 11 agents with auto-triggers | Agent pattern: when to spawn, what model, what scope |

### What a Process Plugin Contains

A process plugin is NOT a single skill. It's an integrated system for a process area:

```
process-plugins/project-management/
├── PROCESS.md              ← Process definition (areas, activities, flow)
├── skills/
│   ├── backlog/SKILL.md    ← Task management
│   ├── build/SKILL.md      ← Development workflow
│   ├── close/SKILL.md      ← Session completion
│   └── review/SKILL.md     ← Progress review
├── hooks/
│   ├── pre-tool-use.sh     ← Spec-first gate
│   ├── post-tool-use.sh    ← Learning capture
│   └── session-start.sh    ← Context loading
├── rules/
│   ├── git-discipline.md   ← Branch conventions
│   ├── sdd-tdd.md          ← Test-first workflow
│   └── task-convention.md  ← Task lifecycle
├── agents/
│   ├── pr-reviewer.md      ← Auto-triggered on PRs
│   └── debrief-analyst.md  ← End-of-session extraction
└── memory/
    └── patterns.md         ← Process-specific learnings
```

The key file is `PROCESS.md` — a new concept that doesn't exist in brana yet. It defines:

```yaml
name: Project Management
description: End-to-end software project lifecycle
areas:
  - name: Planning
    activities: [backlog-plan, backlog-triage, backlog-replan]
    triggers: [session-start, phase-complete]
    artifacts: [tasks.json, ADRs]
  - name: Building
    activities: [build-specify, build-plan, build-implement, build-close]
    triggers: [backlog-start]
    artifacts: [code, tests, commits]
  - name: Learning
    activities: [close, retrospective, memory-recall]
    triggers: [session-end, phase-complete, correction-detected]
    artifacts: [MEMORY.md, handoff notes]
integration:
  memory: ruflo
  lifecycle: session-based
  quality: [pre-tool-use-gate, validate.sh]
```

---

## Process Areas at Different Scales

Examples of what process plugins would look like:

### Small: Content Creation Pipeline
- **Areas:** Draft → Review → Publish → Measure
- **Skills:** /content-draft, /content-review, /content-schedule
- **Hooks:** Post-publish analytics check, draft quality gate
- **Rules:** Brand voice guide, platform conventions
- **Memory:** What performed well, audience patterns

### Medium: Client Project Management (what brana does today)
- **Areas:** Onboard → Scope → Build → Deliver → Close
- **Skills:** /onboard, /build, /backlog, /close, /proposal
- **Hooks:** Spec-first gate, learning capture, session lifecycle
- **Rules:** Git discipline, TDD, task convention
- **Memory:** Client patterns, cross-project learnings

### Large: Solo Consulting Business (also what brana does)
- **Areas:** Pipeline → Proposal → Delivery → Invoicing → Learning
- **Skills:** /pipeline, /proposal, /review, /financial-model, /venture-phase
- **Hooks:** Deal-close detection, revenue tracking
- **Rules:** PM awareness, research discipline
- **Memory:** Client history, engagement patterns, market insights

### The meta-realization
Brana already IS all three of these — just not formalized as separate process plugins. The framework would let someone install just "Content Pipeline" without needing the full consulting stack.

---

## Challenge Findings (incorporated)

The Opus pre-mortem raised 4 critical and 7 warning/observation findings. Here's how the reframing addresses them:

| Challenge Finding | Status After Reframing |
|---|---|
| **No demand validation** | Still valid. But reframing changes the ask: "do people want process systems?" vs "do people want individual skills?" Process systems are closer to consulting deliverables — demand is proven by consulting revenue. |
| **Platform dependency on CC** | Still valid but reduced. A process model (PROCESS.md) is runtime-agnostic. The framework defines processes; the implementation targets CC today but could target others. |
| **Solo dev capacity** | Significantly reduced. Not building marketplace infrastructure. Formalizing what already exists. First deliverable: document the process model, extract brana's implicit patterns. |
| **Trust kernel unenforceable** | Dissolved. Framework doesn't promise sandboxing. Trust comes from process coherence (things connect correctly) not capability isolation. |
| **No revenue model** | Reframed. Revenue = consulting packages around process areas. "I'll set up your content pipeline on Claude Code" is a sellable service. Framework is the methodology behind it. |
| **Prerequisites not started** | Still valid. t-283 (personalization layers) maps directly to this. |
| **"OS" naming overscopes** | Partially addressed. "Framework" is more honest than "OS," but "Brana OS" as a brand could work if expectations are managed. |
| **Composability premature** | Dissolved. Process plugins define integration points declaratively in PROCESS.md, not via type contracts. |
| **No competitive moat** | Reframed. Moat = process design expertise + proven process implementations + consulting. Not technology. |

---

## Open Questions

1. **What's the PROCESS.md spec?** This is the core intellectual property — a formal model for describing Claude-powered processes. Needs careful design.

2. **How modular can processes be?** Can someone install "Content Pipeline" without brana core? Or is brana core always required? (Probably: brana core = OS, processes = plugins that require the OS.)

3. **How does this relate to consulting?** Process plugins could be: (a) open-source reference implementations, (b) customized deliverables for clients, (c) both. The framework is open; the customization is the service.

4. **What's the first process to extract?** Brana's own "software project management" process is the obvious candidate — it's the most mature. But "content pipeline" might be simpler and more broadly appealing.

5. **Anthropic alignment?** Same question from the challenge: is Anthropic building something similar? The reframing reduces this risk (process models are runtime-agnostic) but doesn't eliminate it.

---

## Recommended Next Steps

Incorporating challenge feedback (validate before building):

1. **Define the PROCESS.md spec** — formalize how a process is described (areas, activities, triggers, artifacts, integration points). This is the core IP and costs nothing but thought.

2. **Extract brana's implicit process model** — document what brana already does as if it were a PROCESS.md. This tests the spec against reality.

3. **Complete t-291** (Claude official plugins) — understand the platform before building on it.

4. **Complete t-283** (personalization layer architecture) — the 7-layer model maps to the OS/plugin split.

5. **Package one process as a standalone** — extract "content pipeline" or "project management" as a process plugin that someone else could install. Test if the framework makes it portable.

6. **Test with one consulting client** — install a process plugin for a client. Did the framework help? Was it faster than ad-hoc setup?

---

## Landscape Research (preserved from v1)

### Existing AI Agent Marketplaces

| Platform | Model | Trust | Fails |
|----------|-------|-------|-------|
| Anthropic Marketplace (Mar 2026) | Enterprise, 6 curated partners | Hand-vetted, single MSA | Enterprise-only, tiny catalog |
| OpenAI GPT Store | Consumer, 30% rev-share | "Don't trust external APIs" | Opaque payouts, weak trust |
| LangChain Hub | Community templates | GitHub stars | No sandboxing |
| CrewAI | Reference implementations | Community | Clone-only, not pluggable |

### Interoperability Standards

| Standard | Scope | Relevance |
|----------|-------|-----------|
| MCP (Anthropic → Linux Foundation) | Agent-to-tool | Process plugins could expose MCP interfaces |
| A2A (Google) | Agent-to-agent | Process areas could communicate via A2A |
| NIST AI Agent Standards (Feb 2026) | Gov framework | Alignment opportunity for trust narrative |

### Security Lessons

- **ClawHub:** 12% malicious skills. Root cause: zero trust + dynamic loading + permanent credentials.
- **"Lethal Trifecta":** agents that access private data + communicate externally + ingest untrusted content.
- **2026 consensus:** "Assume all agent code is potentially malicious." Isolation-first.
- **Implication for framework:** Process plugins should declare their data/communication boundaries in PROCESS.md. Enforcement is advisory (hooks) not runtime (sandbox). Honest about limitations.

---

## Challenge Round 2: Assumption Buster (2026-03-13)

Second adversarial review after reframing from marketplace → framework.

### Critical Assumptions Busted

1. **"Process" is the builder's abstraction, not the user's.** People think in problems/goals/tasks, not areas-activities-triggers-artifacts. PROCESS.md requires process engineering vocabulary most users don't have. If users can't write PROCESS.md without guidance, the spec isn't the IP — consulting interpretation is.

2. **Brana is an opinionated application, not an OS.** Hooks hardcode `docs/decisions/`, `feat/*` branches, `tasks.json` schema. These are one application's conventions, not generic OS services. More accurate framing: "reference implementation and component model."

3. **PROCESS.md doesn't execute — it's documentation.** Claude interprets YAML non-deterministically. Two sessions may behave differently. Without code consuming it (validator, loader), it's a comment file. Needs `process-validate.sh` to become a real spec.

### Warnings

4. **Target user intersection too narrow** for self-service. Real user is the consultant setting up for clients.
5. **"Dissolved" challenge findings were scope-reduced, not resolved.** Trust kernel: hooks still run arbitrary bash. Composability: YAML declarations aren't enforced contracts.
6. **Process plugins aren't portable** — brana-specific conventions baked throughout.
7. **Framework vs. consulting tension unresolved** — good frameworks reduce consulting need. Must choose.

### Observation

8. **Generalization is a rewrite, not documentation.** Build first, spec second.

### Decision: PROCEED WITH CHANGES

Accepted recommendations:
- Drop "OS" branding — use "reference implementation and component model"
- Reorder: build a real process plugin FIRST → extract spec from evidence
- Split brana into framework vs. application layers (classify every file)
- Make PROCESS.md consumable by code (process-validate.sh)
- Choose business model before architecture

### Revised Next Steps (evidence-first)

1. ~~**Split brana into framework vs. app layers**~~ — DONE (see below)
2. **Build one process plugin for a real client** — extract from existing client work, see what's actually reusable
3. **Define PROCESS.md spec from evidence** — based on what the real plugin needed
4. **Write process-validate.sh** — make the spec enforceable, not just readable
5. **Complete t-291** (Claude official plugins) — platform alignment check
6. **Complete t-283** (personalization layers) — architectural foundation
7. **Choose business model** — open framework + paid customization vs. proprietary methodology

---

## Framework vs. Application Layer Split (2026-03-13)

Classification of all 75 files in `system/`:

| Classification | Count | % |
|---|---|---|
| **Framework-generic** | 18 | 24% |
| **Brana-specific** | 50 | 67% |
| **Partially generic** | 7 | 9% |

### What's framework-generic (24%)

The **infrastructure tier** — reusable by any process plugin:

- **Hook infrastructure:** PreToolUse deny pattern, JSON hook response format, cascade throttle, timeout handling
- **Memory contracts:** Pattern storage (key/value, namespace, tags, confidence), fallback to auto memory, MEMORY.md format
- **Plugin infrastructure:** plugin.json manifest, skill frontmatter schema (name/description/group/allowed-tools/depends_on), agent definition format
- **Session lifecycle:** Start/end hooks, context injection via additionalContext, parallel job scheduling
- **Patterns:** AskUserQuestion for confirmation, subagent spawning with model routing, research loop with confidence tiers

### What's brana-specific (67%)

The **workflow tier** — encodes brana's methodology:

- **All 28 skills** — tied to brana's task schema, git conventions, business methodology
- **All 11 agents** — tied to brana's portfolio, clients, knowledge base
- **11 of 13 rules** — git discipline, task convention, SDD-TDD, delegation routing, etc.
- **Business workflows** — venture phases, pipeline, review cadence, decision log

### What's partially generic (9%)

Could be made generic with config abstraction:

- PreToolUse spec gate (abstract branch prefix + doc location into config)
- Task schema (extract generic base: id, type, status, parent, priority)
- Venture stage model (parameterize thresholds)
- Hook library (parameterize paths)

### Key Insight

**The framework exists — it's the 24% infrastructure tier.** But it's not separated from the 67% brana-specific workflow tier. To make brana a platform for process plugins:

1. Extract the 24% into a clean "brana-core" layer
2. Make the 67% the first "process plugin" (software consulting)
3. The 9% partially-generic components are the extraction boundary — they show where config abstraction is needed

A new process plugin (e.g., "Sales Pipeline") would reuse the 24% infrastructure and build its own workflow tier: different skills, agents, rules — but same hook patterns, memory contracts, plugin schema.
