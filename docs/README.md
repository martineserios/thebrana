# Documentation Index

Complete index of all brana documentation. Three sections: reference (specs), guide (how-to), architecture (design + research).

## docs/reference/ -- Complete specs

Source of truth for every component. Read these when you need exact behavior.

| File | Contents |
|------|----------|
| [skills.md](reference/skills.md) | All 25 skills with subcommands, triggers, allowed tools, examples |
| [hooks.md](reference/hooks.md) | All 10 hooks with I/O JSON specs, event types, matcher patterns |
| [agents.md](reference/agents.md) | All 11 agents with models, tools, auto-fire triggers, behavior specs |
| [rules.md](reference/rules.md) | All 12 rules with full content |
| [commands.md](reference/commands.md) | Agent commands (maintain-specs, apply-errata, etc.) |
| [scripts.md](reference/scripts.md) | Shell scripts (bootstrap.sh, validate.sh, etc.) |
| [configuration.md](reference/configuration.md) | Config files: plugin.json, hooks.json, settings.json, scheduler.json |

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

### Workflow guides (docs/guide/workflows/)

| File | Contents |
|------|----------|
| [build.md](guide/workflows/build.md) | The build loop -- 7 strategies, task integration |
| [research.md](guide/workflows/research.md) | 3-phase research with scout agents |
| [session.md](guide/workflows/session.md) | Session lifecycle -- start hooks, close, handoffs |
| [capture.md](guide/workflows/capture.md) | Event logging with /brana:log |
| [learn.md](guide/workflows/learn.md) | Learning loop -- confidence, recall, cross-project transfer |
| [venture.md](guide/workflows/venture.md) | Business projects -- reviews, pipeline, milestones, proposals |

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
| [testing-validation.md](architecture/testing-validation.md) | Testing and validation approach |
| [posttooluse-workaround.md](architecture/posttooluse-workaround.md) | CC bug #24529 workaround details |
| [building-methodology.md](architecture/building-methodology.md) | How brana is built (DDD/SDD/TDD) |
| [system-documentation-map.md](architecture/system-documentation-map.md) | Documentation structure map |

### Extending brana

| File | Contents |
|------|----------|
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

### Feature briefs (docs/architecture/features/)

| File | Contents |
|------|----------|
| [build-loop-redesign.md](architecture/features/build-loop-redesign.md) | Build loop: 42->25 skills, 4-step loop, 7 strategies |
| [task-management-system.md](architecture/features/task-management-system.md) | Task management: JSON data layer, NL interface |
| [event-log.md](architecture/features/event-log.md) | Event log: /brana:log skill |
| [smart-tasks-add.md](architecture/features/smart-tasks-add.md) | Smart /brana:backlog add: suggest-only pattern |
| [research-stream.md](architecture/features/research-stream.md) | Research as first-class task stream |
| [acquire-skills.md](architecture/features/acquire-skills.md) | Acquire skills from external marketplaces |
| [cascade-throttle.md](architecture/features/cascade-throttle.md) | Cascade throttle for failure detection |
| [scheduler.md](architecture/features/scheduler.md) | Scheduled jobs system |
| [scheduler-hardening.md](architecture/features/scheduler-hardening.md) | Scheduler hardening and reliability |
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

## Research and spec docs (docs/ root)

Design specifications and research from the original enter repo, now part of thebrana.

### Reflections (docs/reflections/)

Cross-cutting synthesis documents. DAG: R1(08) -> R2(14) -> R3(31) / R4(32) -> R5(29).

| Doc | Reflection | Contents |
|-----|-----------|----------|
| 08 | R1 Triage | What to keep, drop, defer |
| 14 | R2 Architecture | Single-brain system architecture |
| 29 | R5 Venture | Venture management reflection |
| 31 | R3 Assurance | Verification framework |
| 32 | R4 Lifecycle | System evolution, DDD/SDD/TDD workflow |

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
| 05 | claude-flow v3 analysis |
| 06 | claude-flow internals |
| 07 | claude-flow + Claude 4.6 integration |
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
