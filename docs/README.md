# Documentation Index

Complete index of all brana documentation. Three sections: reference (specs), guide (how-to), architecture (design + research).

## docs/reference/ -- Complete specs

Source of truth for every component. Read these when you need exact behavior.

| File | Contents |
|------|----------|
| [skills.md](reference/skills.md) | All skills with subcommands, triggers, allowed tools, examples |
| [hooks.md](reference/hooks.md) | All 10 hooks with I/O JSON specs, event types, matcher patterns |
| [agents.md](reference/agents.md) | All 11 agents with models, tools, auto-fire triggers, behavior specs |
| [rules.md](reference/rules.md) | All 12 rules with full content |
| [commands.md](reference/commands.md) | Agent commands (maintain-specs, apply-errata, etc.) |
| [scripts.md](reference/scripts.md) | Shell scripts (bootstrap.sh, validate.sh, etc.) |
| [configuration.md](reference/configuration.md) | Config files: plugin.json, hooks.json, settings.json, scheduler.json |
| [brana-cli.md](reference/brana-cli.md) | brana CLI — backlog triage-stale, stale, burndown subcommands |
| [skill-validation-checklist.md](reference/skill-validation-checklist.md) | 12-point checklist for validating brana skills (derived from 12-Factor Agents) |

## docs/guide/ -- How-to guides

User-facing documentation. Start here.

| File | Contents |
|------|----------|
| [getting-started.md](guide/getting-started.md) | Install, first session, core workflow |
| [configuration.md](guide/configuration.md) | Configuring brana for your workflow |
| [scheduler.md](guide/scheduler.md) | Setting up scheduled jobs |
| [troubleshooting.md](guide/troubleshooting.md) | Common issues and fixes |
| [upgrading.md](guide/upgrading.md) | Version upgrade procedures |
| [concepts.md](guide/concepts.md) | Key terms: skills, rules, hooks, agents, identity layer |
| [commands/index.md](guide/commands/index.md) | Quick command reference |
| [python-to-rust-migration.md](guide/python-to-rust-migration.md) | Python→Rust migration guide: 10 concept comparisons with brana examples |
| [try-new-features.md](guide/try-new-features.md) | Copy-paste prompts to exercise ADR-059/060 features (runner, secret-gate, workflows, branch flow) — t-2167 |

### Workflow guides (docs/guide/workflows/)

| File | Contents |
|------|----------|
| [build.md](guide/workflows/build.md) | The build loop -- 7 strategies, task integration |
| [research.md](guide/workflows/research.md) | 3-phase research with scout agents |
| [hive-mind.md](guide/workflows/hive-mind.md) | Multi-agent collective intelligence -- find/verify/synthesize on the subscription |
| [session.md](guide/workflows/session.md) | Session lifecycle -- start hooks, close, handoffs |
| [capture.md](guide/workflows/capture.md) | Event logging with /brana:log |
| [learn.md](guide/workflows/learn.md) | Learning loop -- confidence, recall, cross-project transfer |
| [venture.md](guide/workflows/venture.md) | Business projects -- reviews, pipeline, milestones, proposals |
| [spec-graph.md](guide/workflows/spec-graph.md) | Spec dependency graph -- generation, querying, consumer integration |
| [decision-log.md](guide/workflows/decision-log.md) | JSONL decision log -- log, read, archive, hook integration |
| [model-routing.md](guide/workflows/model-routing.md) | Dynamic model routing -- complexity scoring, overrides, calibration |

## docs/architecture/ -- Design and research

Contributor-facing docs. System design, decisions, and feature briefs.

### System design

| File | Contents |
|------|----------|
| [overview.md](architecture/overview.md) | System architecture overview |
| [skills.md](architecture/skills.md) | Skills architecture -- 8 groups, design-level overview |
| [hooks.md](architecture/hooks.md) | Hooks architecture -- plugin/bootstrap split, design principles |
| [agents.md](architecture/agents.md) | Agents architecture -- groups, routing, hook triggers |
| [plugin-structure.md](architecture/plugin-structure.md) | Plugin packaging and manifest |
| [plugin-lifecycle.md](architecture/plugin-lifecycle.md) | Session startup sequence, skill invocation, hook execution flow |
| [bootstrap.md](architecture/bootstrap.md) | bootstrap.sh reference — steps, flags, troubleshooting |
| [testing-validation.md](architecture/testing-validation.md) | Testing and validation approach |
| [posttooluse-workaround.md](architecture/posttooluse-workaround.md) | CC bug #24529 workaround details |
| [building-methodology.md](architecture/building-methodology.md) | How brana is built (DDD/SDD/TDD) |
| [system-documentation-map.md](architecture/system-documentation-map.md) | Documentation structure map |
| [memory-backup.md](architecture/memory-backup.md) | Memory backup, recovery, and reindex procedures |
| [context-budget.md](architecture/context-budget.md) | CC context thresholds (autocompact constants, session memory) |
| [the-orbit.md](architecture/the-orbit.md) | **Index & reading map** for the Orbit/Substrate cluster — vocabulary, what to read in what order (start here) |
| [workflow-primitive.md](architecture/workflow-primitive.md) | Verified `Workflow` tool API surface, smoke-test evidence, opt-in rule |
| [substrate-end-state.md](architecture/substrate-end-state.md) | the Orbit capstone (operation) — tiers, runner stages, safety net, branch strategy |
| [substrate-primitives.md](architecture/substrate-primitives.md) | Agent substrate primitives & composition — primitive set, composed blocks, composition grammar, durability/trust, plug-points |
| [features/autonomous-runner.md](architecture/features/autonomous-runner.md) | Autonomous runner spec — observe/run-one/run-batch + worktree isolation |
| [features/learned-eligibility.md](architecture/features/learned-eligibility.md) | Stage 4 learned eligibility (design only — gated on soak) |
| [features/consensus-primitive.md](architecture/features/consensus-primitive.md) | Native cross-model consensus primitive (design only) |

### Extending brana

| File | Contents |
|------|----------|
| [developer-quickstart.md](architecture/developer-quickstart.md) | **Start here** — add your first skill/rule/hook in 10 minutes |
| [rules-design.md](architecture/rules-design.md) | Rules design — rules vs hooks, scoping, writing style, examples |
| [extending.md](architecture/extending.md) | General guide to extending the system |
| [extending-skills.md](architecture/extending-skills.md) | How to add a new skill |
| [extending-hooks.md](architecture/extending-hooks.md) | How to add a new hook |
| [extending-agents.md](architecture/extending-agents.md) | How to add a new agent |

### Architecture Decision Records (docs/architecture/decisions/)

| ADR | Decision |
|-----|----------|
| [ADR-001](architecture/decisions/ADR-001-reconcile-command-for-spec-implementation-drift.md) | Reconcile command for spec-to-implementation drift |
| [ADR-002](architecture/decisions/ADR-002-tasks-as-data-layer.md) | Tasks as JSON data layer |
| [ADR-002 (scheduler)](architecture/decisions/ADR-002-scheduler-thin-layer-over-systemd.md) | Scheduler as thin layer over systemd |
| [ADR-003](architecture/decisions/ADR-003-agent-driven-task-execution.md) | Agent-driven task execution |
| [ADR-004](architecture/decisions/ADR-004-session-handoff-self-learning-loop.md) | Session handoff and self-learning loop |
| [ADR-005](architecture/decisions/ADR-005-agentdb-v3-unified-knowledge-backend.md) | AgentDB v3 as unified knowledge backend |
| [ADR-006](architecture/decisions/ADR-006-merge-enter-into-thebrana.md) | Merge enter into thebrana |
| [ADR-007](architecture/decisions/ADR-007-verify-counts-deploy-hook.md) | Verify counts deploy hook |
| [ADR-008](architecture/decisions/ADR-008-smart-tasks-add-suggest-only.md) | Smart tasks add -- suggest-only pattern |
| [ADR-009](architecture/decisions/ADR-009-test-lint-feedback-hook.md) | Test/lint feedback hook |
| [ADR-010](architecture/decisions/ADR-010-pr-review-agent.md) | PR review agent |
| [ADR-011](architecture/decisions/ADR-011-skills-bundling.md) | Skills bundling |
| [ADR-012](architecture/decisions/ADR-012-acquire-skills.md) | Acquire skills from marketplaces |
| [ADR-013](architecture/decisions/ADR-013-event-log.md) | Event log (/brana:log) |
| [ADR-014](architecture/decisions/ADR-014-plugin-management-skill.md) | Plugin management skill |
| [ADR-015](architecture/decisions/ADR-015-state-consolidation-plugin-first.md) | State consolidation and plugin-first architecture |
| [ADR-016](architecture/decisions/ADR-016-spec-dependency-graph.md) | Spec dependency graph |
| [ADR-017](architecture/decisions/ADR-017-decision-log.md) | JSONL decision log |
| [ADR-018](architecture/decisions/ADR-018-dynamic-model-routing.md) | Dynamic model routing |
| [ADR-019](architecture/decisions/ADR-019-brana-chat-sessions.md) | Brana chat sessions |
| [ADR-021](architecture/decisions/ADR-021-knowledge-architecture-v2.md) | Knowledge architecture v2 |
| [ADR-022](architecture/decisions/ADR-022-brana-cli.md) | Brana CLI (Rust) |
| [ADR-023](architecture/decisions/ADR-023-rust-cli-dispatcher.md) | Rust CLI dispatcher |
| [ADR-024](architecture/decisions/ADR-024-content-polling-keyring-credentials.md) | Content polling with keyring credentials |
| [ADR-025](architecture/decisions/ADR-025-skill-lifecycle-manager.md) | Skill lifecycle manager |
| [ADR-026](architecture/decisions/ADR-026-ruflo-mcp-backbone.md) | Ruflo MCP as backbone (CLI fallback) |
| [ADR-026b](architecture/decisions/ADR-026-full-rust-mcp-architecture.md) | **Full Rust + MCP architecture** (Cargo workspace, pmcp, Python elimination) |
| [ADR-027](architecture/decisions/ADR-027-auto-learning-loop.md) | Auto-learning loop |
| [ADR-028](architecture/decisions/ADR-028-ontology-v2.md) | Ontology v2 |
| [ADR-029](architecture/decisions/ADR-029-six-job-taxonomy.md) | 6-job taxonomy |
| [ADR-030](architecture/decisions/ADR-030-maintenance-unification.md) | Maintenance unification |
| [ADR-031](architecture/decisions/ADR-031-doc-enforcement-hook.md) | Doc-enforcement hook |
| [ADR-032](architecture/decisions/ADR-032-smart-router.md) | Smart router |
| [ADR-033](architecture/decisions/ADR-033-pin-mcp-servers.md) | MCP server pinning (wrapper scripts) |
| [ADR-034](architecture/decisions/ADR-034-skill-tiering.md) | Skill tiering — core full + extended stubs |
| [ADR-035](architecture/decisions/ADR-035-skill-usage-telemetry.md) | Skill usage telemetry |
| [ADR-036](architecture/decisions/ADR-036-mcp-or-cli-decision-rule.md) | MCP-or-CLI decision rule |
| [ADR-037](architecture/decisions/ADR-037-memory-enforcement-and-migration.md) | Memory enforcement and migration |
| [ADR-038](architecture/decisions/ADR-038-memory-write-gateway.md) | Memory write gateway |
| [ADR-039](architecture/decisions/ADR-039-pattern-quality-filter-and-per-pattern-files.md) | Pattern quality filter and per-pattern files |
| [ADR-040](architecture/decisions/ADR-040-compute-hierarchy-claude-ruflo-gemini.md) | brana compute hierarchy — Claude / Ruflo / Gemini |
| [ADR-041](architecture/decisions/ADR-041-agy-invocation-contract.md) | agy invocation contract |
| [ADR-042](architecture/decisions/ADR-042-knowledge-ingest-canonical-entry-point-gemini-routing.md) | Knowledge pipeline — `ingest` as canonical URL entry point + Gemini routing for Tier 1/2 |
| [ADR-043](architecture/decisions/ADR-043-session-labels-breadcrumb.md) | session_labels breadcrumb array for same-day multi-session merges |
| [ADR-044](architecture/decisions/ADR-044-initiative-accumulator.md) | Initiative accumulator — cross-day session continuity per initiative |

### Domain model (docs/domain/)

| File | Contents |
|------|----------|
| [MODEL-001-brana-core.md](domain/MODEL-001-brana-core.md) | 9 bounded contexts, ubiquitous language, domain events for brana-core |

### Feature briefs (docs/architecture/features/)

| File | Contents |
|------|----------|
| [t-2001-feed-tech-stack.md](architecture/features/t-2001-feed-tech-stack.md) | Intelligence feed: staleness detection, tech-stack changelogs, Kapso scraper, adoption step |
| [build-loop-redesign.md](architecture/features/build-loop-redesign.md) | Build loop: 42->25 skills, 4-step loop, 7 strategies |
| [reminder-system.md](architecture/features/reminder-system.md) | Reminder store: Rust-owned writes, two-layer sources, session-start surfacing |
| [async-close.md](architecture/features/async-close.md) | Async close: instant close, snapshot queue, nightly extraction cron |
| [task-management-system.md](architecture/features/task-management-system.md) | Task management: JSON data layer, NL interface |
| [event-log.md](architecture/features/event-log.md) | Event log: /brana:log skill |
| [smart-tasks-add.md](architecture/features/smart-tasks-add.md) | Smart /brana:backlog add: suggest-only pattern |
| [research-stream.md](architecture/features/research-stream.md) | Research as first-class task stream |
| [acquire-skills.md](architecture/features/acquire-skills.md) | Acquire skills from external marketplaces |
| [cascade-throttle.md](architecture/features/cascade-throttle.md) | Cascade throttle for failure detection |
| [scheduler.md](architecture/features/scheduler.md) | Scheduled jobs system |
| [scheduler-hardening.md](architecture/features/scheduler-hardening.md) | Scheduler hardening and reliability |
| [brana-v2-compute-model.md](architecture/features/brana-v2-compute-model.md) | Compute hierarchy: Claude/Ruflo/Gemini stack, routing rules, phase map |
| [claude-gemini-orchestration.md](architecture/features/claude-gemini-orchestration.md) | Gemini layer A/B/C, ENRICH+PERSIST lifecycle, compounding loop |
| [ruflo-integration-map.md](architecture/features/ruflo-integration-map.md) | Ruflo tool-group map, ToolSearch preambles, hive-mind quorum gate specs |
| [plugin-packaging.md](architecture/features/plugin-packaging.md) | Plugin packaging for marketplace |
| [test-lint-feedback-hook.md](architecture/features/test-lint-feedback-hook.md) | Test/lint feedback hook |
| [tasks-portfolio.md](architecture/features/tasks-portfolio.md) | Cross-project portfolio view |
| [tasks-wide-mode.md](architecture/features/tasks-wide-mode.md) | Wide display mode for tasks |
| [tasks-theme-system.md](architecture/features/tasks-theme-system.md) | Task display themes |
| [project-metadata.md](architecture/features/project-metadata.md) | Project metadata system |
| [skill-utilization-tracking.md](architecture/features/skill-utilization-tracking.md) | Skill utilization tracking |
| [staleness-and-memory-pipeline.md](architecture/features/staleness-and-memory-pipeline.md) | Staleness detection and memory pipeline |
| [context-budget-real-limits.md](architecture/features/context-budget-real-limits.md) | Context budget real-world limits |
| [acquire-skills-guide.md](architecture/features/acquire-skills-guide.md) | Acquire skills implementation guide |
| [agentdb-v3-upgrade-evaluation.md](architecture/features/agentdb-v3-upgrade-evaluation.md) | AgentDB v3 upgrade evaluation |
| [skill-routing-in-backlog-start.md](architecture/features/skill-routing-in-backlog-start.md) | Semantic skill suggestion at task start (ADR-026, t-833) |
| [operating-model.md](architecture/features/operating-model.md) | Operating model: auto-learning loop, 6-job taxonomy, unified maintenance, knowledge graph |

## Conventions (docs/conventions/)

Authoring guides for brana-specific syntax and patterns.

| File | Contents |
|------|----------|
| [ac-criteria.md](conventions/ac-criteria.md) | AC: criteria authoring guide — supported heuristics H1–H8, H7 allowlist, sandbox rules, UNKNOWN fallback |

## Ideas (docs/ideas/)

Exploratory design notes and integration proposals. Not committed to the roadmap.

| File | Contents |
|------|----------|
| [ruflo-native-integration.md](ideas/ruflo-native-integration.md) | Ruflo native integration — controller status, upstream blockers, upgrade path |
| [skill-auto-router.md](ideas/skill-auto-router.md) | Skill auto-routing with ruflo HNSW + marketplace discovery |

## Content (docs/content/)

| File | Contents |
|------|----------|
| [lens.md](content/lens.md) | Positioning filter — pillars, dual test, anti-topics, components shelf |
| [ideas.md](content/ideas.md) | Content idea seeds (capped at 10 active) |

## Reviews (docs/reviews/)

| File | Contents |
|------|----------|
| [architecture-review-2026-06-10.md](reviews/architecture-review-2026-06-10.md) | Full-system architecture review — 4-axis layer audit, write-only memory diagnosis, strategic options (close loop → extract public core) |
| [knowledge-structure-audit-2026-06-11.md](reviews/knowledge-structure-audit-2026-06-11.md) | Ontology audit of knowledge structure — disjoint spec/memory TBoxes, missing typed relations, no lifecycle facet on memory; recommendations feed t-156 |
| [token-baseline.md](reviews/token-baseline.md) | Token cost baseline measurements |
| [weekly-2026-04-17.md](reviews/weekly-2026-04-17.md) | Weekly review 2026-04-17 |

## Research and spec docs (docs/ root)

Design specifications and research from the original enter repo, now part of thebrana.

### Reflections (docs/reflections/)

Cross-cutting synthesis documents. DAG: R1(08) -> R2(14) -> R3(31) / R4(32) -> R5(29) / R6(33).

| Doc | Reflection | Contents |
|-----|-----------|----------|
| 08 | R1 Triage | What to keep, drop, defer |
| 14 | R2 Architecture | Single-brain system architecture |
| 29 | R5 Venture | Venture management reflection |
| 31 | R3 Assurance | Verification framework |
| 32 | R4 Lifecycle | System evolution, DDD/SDD/TDD workflow |
| 33 | R6 Agent Loop | CC runtime execution model — hook and skill step mapping |

### Roadmap and operational docs

| Doc | Contents |
|-----|----------|
| 00 | User practices: field notes from real usage |
| 15 | Self-development workflow: genome vs connectome |
| 17 | Implementation roadmap (comprehensive, 6 phases) |
| 18 | Lean roadmap (3 phases, ships faster) |
| 19 | PM system design |
| 24 | Roadmap corrections and errata |
| 25 | Self-documentation practices |
| 30 | Backlog: future ideas |
| 39 | Architecture redesign: merge plan |

### Research docs (numbered, in docs/ root)

Original research and analysis from the enter phase. Documents 01-13, 16, 20-23, 26-28, 33-38 cover topics from system analysis through design thinking. See the full listing in the [research section](#research-topics) below.

<details>
<summary>Research topics (click to expand)</summary>

| Doc | Topic |
|-----|-------|
| 01 | Brana system analysis |
| 02 | Nexeye skill selection |
| 03 | PM framework |
| 04 | Claude 4.6 capabilities |
| 05 | ruflo v3 analysis |
| 06 | ruflo internals |
| 07 | ruflo + Claude 4.6 integration |
| 09 | Claude Code native features |
| 10 | Statusline research |
| 11 | Ecosystem skills and plugins |
| 12 | Skill selector design |
| 13 | Challenger agent design |
| 16 | Knowledge health |
| 20 | Anthropic blog findings |
| 21 | Anthropic engineering deep dive |
| 22 | Testing strategy |
| 23 | Evaluation methodology |
| 26 | Git branching strategies |
| 27 | Project alignment methodology |
| 28 | Startup and SMB management |
| 33 | Research methodology |
| 34 | Venture operating system |
| 35 | Context engineering principles |
| 36 | Claw ecosystem research |
| 37 | RuvNet development practices |
| 38 | Design thinking |

</details>
