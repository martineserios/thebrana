# enter

> Part of [**enter_thebrana**](../) — two repos, one system. `enter` designs what [`thebrana`](../thebrana/) builds.

Discovery and specification documents for the brana orchestration system.

## What This Is

After deep research into brana's current `.claude/` system, nexeye's skill selection patterns, the PM framework, Claude 4.6 native capabilities, and claude-flow v3 internals, this repo captures those findings in structured documents. The goal is to have a clean starting point for discussing and building the new system.

## Documents

| File | What It Covers |
|------|---------------|
| `01-brana-system-analysis.md` | How brana works today: modules, routing, hooks, PM separation |
| `02-nexeye-skill-selection.md` | How nexeye routes skills to agents automatically |
| `03-pm-framework.md` | The PM approach: code/PM separation, feature lifecycle, priorities |
| `04-claude-4.6-capabilities.md` | What Claude 4.6 can do natively without external tooling |
| `05-claude-flow-v3-analysis.md` | claude-flow v3 architecture, agents, topologies, consensus |
| `06-claude-flow-internals.md` | Deep dive: RuVector, AgentDB, WASM Agent Booster, SONA |
| `07-claude-flow-plus-claude-4.6.md` | How claude-flow and Claude 4.6 work together |
| `08-diagnosis.md` | R1 Triage: what to keep, drop, defer — full coverage of all dimension docs, resolved questions, DAG orientation |
| `09-claude-code-native-features.md` | Deep dive into Claude Code 4.6 native features: skills, subagents, agent teams, hooks, memory, disaggregated CLAUDE.md |
| `10-statusline-research.md` | Community status line projects: visualization, interactivity, cost tracking |
| `11-ecosystem-skills-plugins.md` | Claude Code ecosystem: Vercel skills.sh, official plugins, community offerings, what to adopt |
| `12-skill-selector.md` | Dynamic skill selection: registry access, trust tiers, curated catalog, skill quarantine, earned automation |
| `13-challenger-agent.md` | Cross-model adversarial review: subscription-native, four challenge flavors, rate-limit-aware, earned automation |
| `14-mastermind-architecture.md` | Single-brain system architecture: three layers, directory tree, hooks, ReasoningBank, skills, portfolio, enforcement hierarchy, context engineering theory |
| `15-self-development-workflow.md` | Genome vs connectome separation, deploy pipeline, testing, versioning, self-healing, the system that maintains itself |
| `16-knowledge-health.md` | Knowledge poisoning vectors, immune system design: quarantine, decay, contradiction detection, anti-patterns, healing |
| `17-implementation-roadmap.md` | Phased build plan: claude-flow as foundation, 6 phases from skeleton to self-improving brain, risk mitigation, timeline |
| `18-lean-roadmap.md` | Stripped-down alternative: 3 phases, quarantine-only immune system, pain-driven additions, ships faster |
| `19-pm-system-design.md` | Project management plugin: research (Second Brain, GitHub Projects, Claude Code patterns), analysis, design decisions, branch strategy |
| `20-anthropic-blog-findings.md` | Research index: engineering blog reference table, safety research, Claude Code doc discoveries, agent teams vs subagents comparison, community PM tools, validation/new findings matrix |
| `21-anthropic-engineering-deep-dive.md` | Exhaustive deep dive into all 18 Anthropic engineering blog posts: exact architectures, code patterns, metrics, failure modes, cross-cutting patterns for orchestration |
| `22-testing.md` | Testing: 7-layer pyramid (static validation → unit → replay → behavioral → e2e → chaos → monitoring), CI/CD pipeline, record/playback pattern, tools (BATS, Promptfoo, ShellCheck), Obra pressure testing |
| `23-evaluation.md` | Evaluation: Anthropic eval methodology, pass@k vs pass^k, Vercel fixture evals, RAG metrics for memory, challenger quality assessment, eval-driven development, practitioner insights, benchmarks |
| `24-roadmap-corrections.md` | Errata: 7 errors found during Phase 2 planning — deploy.sh merge bug, Stop vs SessionEnd mismatch, missing hook format/events, async constraints, budget calc gap |
| `25-self-documentation.md` | Self-documentation: YAML frontmatter convention, staleness detection with layer-aware thresholds, CI/CD pipeline for docs, growth stages as trust signals, auto-generated indexes, cross-reference hygiene, documentation locality |
| `26-git-branching-strategies.md` | Git branching strategies: comprehensive comparison of GitHub Flow, GitFlow, Trunk-Based Development, GitLab Flow — who uses them, when they work, when they break, solo developer recommendations |
| `27-project-alignment-methodology.md` | Project alignment: 28-item checklist, 3 tiers, 5-phase pipeline, cross-client learning from alignment outcomes |
| `28-startup-smb-management.md` | Startup & SMB management: scaling non-coding projects — frameworks (EOS, OKRs, Scaling Up, Shape Up), books, phase-based models, software→business pattern transfer, operational systems, AI-augmented management, knowledge ecosystem |
| `29-venture-management-reflection.md` | Venture management reflection: what transfers from code to business, what doesn't, five new venture skills, cross-domain learning architecture, coding practice → business pattern mapping |
| `30-backlog.md` | Backlog: ideas to develop in the future — simple task list reviewed by `/brana:maintain-specs` each cycle |
| `31-assurance.md` | R3 Assurance: verification framework — structural checks, behavioral tests, outcome evaluation, RAG metrics, knowledge health, user feedback calibration |
| `32-lifecycle.md` | R4 Lifecycle: system evolution — DDD/SDD/TDD workflow, context management, self-describing config, maintenance cadences, graduation pathway, git workflow, build-phase cycle |
| `33-research-methodology.md` | Research methodology: recursive discovery, source registry, research archetypes, leads queue, evolution mechanics |
| `34-venture-operating-system.md` | Venture operating system: stage-aware business management, 5 venture skills, meeting cadences, financial modeling, experiment loops |
| `35-context-engineering-principles.md` | Context engineering: decision framework for information placement, budget architecture, progressive disclosure, sub-agent protocols, failure modes |
| `36-claw-ecosystem-chat-interface.md` | Claw ecosystem: chat interface research — OpenClaw (security issues), NanoClaw (WhatsApp + containers), ZeroClaw (Rust + performance), integration analysis for brana, API/subscription model, somos_mirada viability |
| `37-ruvnet-development-practices.md` | RuvNet development practices: three-tier maturity model, ADR patterns (MADR+SPARC), CLAUDE.md as dev contract, release strategy, CCEPL methodology, CompanyOS validation, agentic drift, transferable practices for brana |
| `38-design-thinking.md` | Design thinking: core frameworks (d.school, IDEO, Double Diamond), diverge-converge principle, brana workflow mapping, venture design integration, portable techniques, AI-augmented DT, coding project applications |
| `39-architecture-redesign.md` | Architecture redesign: merge enter into thebrana, evolve brana-knowledge into active knowledge base, wire retrieval via AgentDB/embeddings. Three decisions justified, migration plan, impact analysis |
| `00-user-practices.md` | User practices: field notes from building and using the brana system — the feedback loop that drives system evolution, graduated practices log |

### Feature Briefs

Feature briefs live in `docs/architecture/features/`. Key briefs:

| File | What It Covers |
|------|---------------|
| `docs/architecture/features/build-loop-redesign.md` | Build loop redesign: 42→25 skills, 4-step loop, 7 strategies, /tasks+/brana:build integration |
| `docs/architecture/features/task-management-system.md` | Task management system: JSON data layer, NL interface, hierarchical planning, branch integration |
| `docs/architecture/features/event-log.md` | Event log: /brana:log skill for capturing links, calls, meetings, ideas |
| `docs/architecture/features/smart-tasks-add.md` | Smart /brana:backlog add: suggest-only pattern, dependency scan, build-trap check (ADR-008) |
| `docs/architecture/features/research-stream.md` | Research as first-class task stream: URL auto-detection, tag-based cross-reference |

### Architecture Decision Records

ADRs live in `docs/architecture/decisions/`. Key decisions:

| File | What It Covers |
|------|---------------|
| `docs/architecture/decisions/ADR-001-reconcile-command-for-spec-implementation-drift.md` | Reconcile command for spec-to-implementation drift |
| `docs/architecture/decisions/ADR-002-tasks-as-data-layer.md` | Tasks as JSON data layer — schema, convention rule, hook validation |
| `docs/architecture/decisions/ADR-006-merge-enter-into-thebrana.md` | Merge enter into thebrana — unified repo |
| `docs/architecture/decisions/ADR-013-event-log.md` | Event log — /brana:log skill, append-only JSONL, inline tags |

## How to Use

Read the documents in order for the full picture, or jump to specific topics:

- **Understanding the current system:** Start with `01` and `02`
- **PM approach:** Read `03`
- **What's possible now:** Read `04` for native capabilities, `05`-`06` for claude-flow, `09` for the full Claude Code 4.6 feature deep dive, `10` for statusline research, `11` for the skills/plugins ecosystem
- **Integration patterns:** Read `07`
- **Decision-making:** Read `08` for the keep/drop/defer triage (R1) — now covers all dimension docs
- **The vision:** Read `14` for the mastermind single-brain architecture (R2), `31` for verification framework (R3), `32` for lifecycle and evolution (R4), `15` for genome/connectome separation, `16` for knowledge health
- **Building it:** Read `12` for skill selection, `13` for the challenger agent, `17` for the comprehensive roadmap, `18` for the lean alternative (or start with `18` and use `17` as reference), `27` for the project alignment methodology (how to get projects aligned with brana practices)
- **Project management:** Read `19` for the PM plugin design (research, analysis, GitHub Issues + branch strategy integration). See `docs/features/task-management-system.md` for the active feature brief and `docs/decisions/ADR-002` for the architecture decision
- **Testing:** Read `22` for the testing strategy — CI/CD pipeline, static validation, unit tests, record/playback, chaos testing
- **Evaluation:** Read `23` for eval methodology — pass@k/pass^k, RAG metrics, LLM-as-judge, skill activation rates, benchmarks
- **Corrections:** Read `24` for errors found in [docs 14](reflections/14-mastermind-architecture.md), 17, 18 during Phase 2 planning — must-fix items before implementing hooks
- **Self-documentation:** Read `25` for how to keep this repo alive — frontmatter convention, staleness detection, CI/CD for docs, growth stages
- **Git workflow:** Read `26` for git branching strategy research — GitHub Flow, GitFlow, Trunk-Based Development, GitLab Flow comparison with solo developer recommendations
- **Non-coding projects:** Read `28` for startup and SMB management — scaling frameworks, books, phase-based models, software→business pattern transfer, operational systems, AI-augmented management. Read `29` for the reflection: what transfers, what doesn't, venture skill architecture, cross-references to coding practice docs
- **User practices:** Read `00` for field notes from real usage — the feedback loop that closes the system evolution cycle. Start here when onboarding.
- **Research methodology:** Read `33` for how brana discovers and maintains knowledge — research archetypes, source registry, recursive discovery, leads queue, evolution mechanics
- **Future research:** Read `20` for Anthropic blog findings to revisit later, `21` for the exhaustive technical deep dive into all Anthropic engineering posts

## Status

Started as discovery documents, now includes implementation roadmaps, system design, testing strategy, and self-documentation practices. Documents 01-16 capture research and architecture decisions. Documents 17-18 are implementation roadmaps (full and lean). Document 19 is the PM plugin design. Documents 20-21 cover Anthropic blog research. Documents 22-23 cover testing and evaluation. Document 24 captures roadmap corrections and errata. Document 25 covers self-documentation for the repo itself. Document 26 covers git branching strategies. Document 27 covers the project alignment methodology — the active pipeline for getting projects to the right structure. Document 28 covers startup and SMB management — scaling non-coding projects with patterns transferred from software engineering. Document 29 reflects on [doc 28](dimensions/28-startup-smb-management.md): what transfers from code to business, the venture skill architecture, and detailed cross-references to coding practice docs. Document 00 captures user-discovered practices from real usage. Documents 31-32 complete the reflection layer: assurance (R3) and lifecycle (R4). Document 33 formalizes the research methodology — archetypes, source registry, recursive discovery, and evolution mechanics.
