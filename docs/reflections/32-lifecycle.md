# 32 - Lifecycle: How Does It Evolve?

How the mastermind system develops, maintains itself, and evolves over time. Covers the development workflow (DDD → SDD → TDD → Code), maintenance cadences, context management, configuration as documentation, and the feedback loops that keep the system alive. R4 in the reflection DAG: the temporal dimension of what [R2 (Architecture)](./14-mastermind-architecture.md) defines.

---

## The Development Workflow

Three disciplines form concentric layers. The natural order goes from domain understanding to working code:

```
Domain Model  →  Architecture Spec  →  Tests  →  Code
    DDD              SDD                TDD      impl
```

1. **DDD (Domain-Driven Design):** Model the problem space — ubiquitous language, bounded contexts, aggregates, domain events. Answers: "what are we building?"
2. **SDD (Spec-Driven Development):** Decide the approach — ADRs, architectural decisions, API contracts. Answers: "how are we building it?"
3. **TDD (Test-Driven Development):** Specify behavior — failing tests before implementation, red-green-refactor. Answers: "does it work correctly?"

Each discipline builds on the one before it. Domain understanding informs architectural decisions. Architectural decisions shape test scenarios. Tests gate implementation.

**DDD is strategic, SDD is tactical, TDD is mechanical.** DDD requires judgment (what are the bounded contexts?). SDD requires decisions (which approach? what trade-offs?). TDD is algorithmic (red-green-refactor). Enforcement difficulty follows the same gradient — TDD is easiest to enforce deterministically, DDD is hardest.

### Domain-Before-Spec (DDD)

**The impact:** Research shows that structuring code around bounded contexts improves LLM code accuracy from ~55% to ~88% (+60% relative improvement) and reduces boundary violations from 35% to 3%. Bounded contexts also cut context loading by 75-85% — the LLM only needs 15-25% of the codebase for any given task.

DDD enforcement has three aspects:

**Ubiquitous language.** A domain glossary (`docs/domain/glossary.md`) documenting key terms. When loaded into context, LLMs use documented terminology consistently. Cheapest, highest-impact DDD integration — convention-level (~80%).

**Bounded context boundaries.** Architecture linters (ArchUnit, dependency-cruiser, import-linter) validate at CI/CD time. Path-scoped rules (`src/domain/**` → domain layer rules) provide convention-level enforcement.

**Domain model artifacts.** A `/domain-model` skill (future) creates markdown domain specs in `docs/domain/MODEL-NNN-context-name.md`, similar to how `/decide` creates ADRs.

**Opt-in:** Enforcement activates when `docs/domain/` exists alongside `docs/decisions/`. Same pattern as SDD opt-in.

### Spec-Before-Code (SDD)

**The rule:** On `feat/*` branches, implementation code cannot be written until a spec (ADR or test) exists.

**Opt-in:** Enforcement activates when `docs/decisions/` exists. No directory = no enforcement.

**The `/decide` skill** creates ADRs using Michael Nygard's lightweight format (Context, Decision, Consequences) in `docs/decisions/ADR-NNN-title.md`. Auto-increments, stores in ReasoningBank.

**The PreToolUse hook** intercepts `Write|Edit` calls on `feat/*` branches. See [14-mastermind-architecture.md](./14-mastermind-architecture.md) for the enforcement gate design; [31-assurance.md](./31-assurance.md) for how to verify it works.

### Test-Before-Code (TDD)

**Adopted tool:** TDD-Guard — PreToolUse hooks that block implementation writes without failing tests. Covers Jest, Vitest, pytest, Go, Rust. Increased compliance from ~20% (CLAUDE.md alone) to ~84%.

External dependency — installed per-project, not built by brana. Recommended during `/project-onboard`.

### Multi-Agent Context Isolation (Future)

When using Agent Teams: isolate agents by discipline.

**For TDD:** Separate test-writing agent from implementation agent. The test writer works from the spec; the implementer works from tests. Prevents tests that verify implementation details. See [22-testing.md](../../../brana-knowledge/dimensions/22-testing.md) "Multi-Agent TDD".

**For DDD:** Separate domain-modeler from implementer. The modeler reads requirements and produces domain models; the implementer reads the domain model and implements without modifying it.

### Connection to the Learning Loop

ADRs created by `/decide` are pattern-worthy — `/brana:retrospective` extracts "decision X was made because Y" and stores it in ReasoningBank. Domain models (future) would feed the same loop. The enforcement hooks themselves are pure git-based, no claude-flow dependency. Learning happens through the skill layer (`/brana:retrospective`, `/brana:memory recall`).

---

## Context Management

How to keep the finite attention budget useful as sessions grow and the system accumulates knowledge.

### Context Rot

Context engineering = optimizing token allocation within finite attention budgets. As context length increases, model ability to capture pairwise token relationships diminishes. This is a **performance gradient, not a hard cliff** — caused by transformer architecture's n-squared complexity. Source: [21-anthropic-engineering-deep-dive.md](../../../brana-knowledge/dimensions/21-anthropic-engineering-deep-dive.md).

**Implication:** The ~26KB context budget isn't arbitrary. Every KB of always-loaded instructions competes with working context. The SessionStart hook should inject a brief summary (not a dump) of relevant patterns. The mastermind CLAUDE.md should be as lean as possible — "for each line ask: would removing this cause mistakes?"

### Just-In-Time Context

Instead of pre-loading all patterns at session start, maintain lightweight identifiers and dynamically load data during execution. Mirrors human cognition: external organization systems rather than memorization.

**Implication:** This validates the skill architecture (descriptions only until invoked) and the two-layer memory design (MEMORY.md index + topic files on demand). The SessionStart hook should inject a digest, not everything. Skills like `/brana:memory recall` and `/brana:memory pollinate` do the heavy loading when actually needed.

### Keeping Sessions Healthy

Three strategies from Anthropic's research, all applicable:

| Strategy | Best For | Brana Mapping |
|----------|----------|---------------|
| **Compaction** | Long back-and-forth sessions | `/compact` command + PreCompact hook |
| **Structured Note-Taking** | Iterative development with milestones | SessionEnd hook + auto memory + CONTEXT.md |
| **Sub-Agent Architectures** | Parallel exploration | Scout agent + `context: fork` skills |

All three should be available. The SessionStart hook reads notes. The SessionEnd hook writes them. Sub-agents keep exploration noise out of the main context.

**Context Autopilot (Feb 2026).** Claude Code now includes native context auto-management — the system automatically compacts and manages the context window without explicit user intervention. With Autopilot enabled, the three strategies above remain relevant but shift in priority: **Compaction** is partially automated (Autopilot handles routine compaction; PreCompact hooks still fire for custom summarization), **Structured Note-Taking** becomes more important (Autopilot can't preserve domain-specific structure — hooks must write notes before auto-compaction loses them), **Sub-Agent Architectures** remain unchanged (parallel exploration still benefits from context isolation regardless of Autopilot).

Additionally, the **Notification** hook type (`permission_prompt`, `idle_prompt`, `auth_success`) provides a new maintenance trigger — hooks can respond to permission prompts and idle states, enabling automated housekeeping during natural session pauses.

---

## Self-Describing Configuration

The mastermind's own `.claude/` files are simultaneously configuration and documentation (see [25-self-documentation.md](../25-self-documentation.md)). The system that runs is also the system that describes itself.

**Frontmatter for skills and rules.** Each SKILL.md already requires `name` and `description` in frontmatter. Extend with `status` (experimental/stable/deprecated) and `growth_stage` (seedling/budding/evergreen) to signal trust level. An experimental skill should be treated differently from a battle-tested one — same principle as [doc 25](../25-self-documentation.md)'s growth stages for spec documents.

**The `.claude/` directory IS the documentation.** Reading the directory tree tells you what the mastermind does. Each file is self-describing: CLAUDE.md is identity, rules/ is universal standards, skills/ is capabilities, agents/ is team composition. No separate "system docs" needed — Cyrille Martraire's principle: "store documentation on the documented thing itself."

**Staleness applies to configs too.** A skill that references claude-flow v3.1 commands when v3.3 changed the API is a stale config. The same layer-aware staleness thresholds (30/90/180 days) and dependency-triggered reviews from [25-self-documentation.md](../25-self-documentation.md) apply. When claude-flow releases a new version, review all skills that call its commands.

**Documentation locality applies to configs too.** Per [doc 25](../25-self-documentation.md) Mechanism 7: the ReasoningBank schema is the source of truth in [doc 14](14-mastermind-architecture.md). Implementation code references it by doc ID ("per spec 14"), never duplicates it. MEMORY.md summaries are a lossy cache — agents should follow links for the actual schema.

---

## Maintenance Cadences

How often different parts of the system need attention.

### The Genome (System Code)

From [15-self-development-workflow.md](../15-self-development-workflow.md) — the genome is what gets deployed to `~/.claude/`:

| Component | Review Trigger | Why |
|-----------|---------------|-----|
| Skills | After claude-flow version change | API commands may break (lesson #16 from [doc 24](../24-roadmap-corrections.md)) |
| Hooks | After Claude Code update | Hook events may change (error #2 from [doc 24](../24-roadmap-corrections.md)) |
| Rules | After adding a tool preference | New rules need propagation (doc 00 records these) |
| CLAUDE.md | Per phase milestone | Architecture may have shifted |
| Context budget | After adding skills/agents/rules | Budget creep is invisible until it degrades performance |

**The deploy pipeline:** All changes flow through the brana project repo. Never edit `~/.claude/` directly. `deploy.sh` handles the genome; the connectome (ReasoningBank) is never touched by deploys. The cardinal rule: a system rollback must NEVER touch the knowledge store.

### The Connectome (Learned Knowledge)

| Component | Review Trigger | How |
|-----------|---------------|-----|
| Pattern health | Monthly | `/brana:memory review` — staleness, contradictions, confidence distribution |
| Token usage | After each session or weekly | `/usage-stats` — model distribution, session patterns, activity trends, anomaly detection |
| Source registry | Per source cadence (weekly–quarterly) | `/brana:research registry` — trust tier health, overdue checks, yield tracking. See [33-research-methodology.md](../../../brana-knowledge/dimensions/33-research-methodology.md) |
| Pattern curation | After each session with notable learnings | `/brana:retrospective` — the engine that builds knowledge trust |
| Cross-project transfer | When starting work in a different project | `/brana:memory pollinate` — checks for applicable patterns |
| Knowledge backup | Before claude-flow upgrades | `backup-knowledge.sh` — snapshot ReasoningBank + auto memory |

### The Spec Repo

From [25-self-documentation.md](../25-self-documentation.md) — layer-aware staleness thresholds:

| Layer | Threshold | Why |
|-------|-----------|-----|
| Roadmap (17, 18, 19, 24) | 30 days | Implementation details change fast |
| Reflection (08, 14, 29, 31, 32) | 90 days | Architecture decisions are more stable |
| Dimension (01-07, 09-13, 15-16, 20-23, 25-28, 33-37) | 180 days | Research and analysis are the most durable |

**Tie reviews to implementation milestones**, not calendar dates. Review docs when you start implementing from them.

### Scheduled Automation

From [ADR-002](../decisions/ADR-002-scheduler-thin-layer-over-systemd.md) — brana-scheduler runs maintenance jobs on a cadence, bridging the gap between session-bound hooks and manual skill invocations:

| Job | Schedule | What it does |
|-----|----------|-------------|
| staleness-report | Weekly (Mon 08:00) | Layer-aware spec freshness check — flags STALE/WARN/DEP docs |

The runner stores summaries in claude-flow memory (`namespace: scheduler-runs`). `/morning` and session-start can surface overnight results via `memory search --query "sched:"`.

**Key design principle:** Scheduler jobs reserve exit code 1 for actual failures only. Informational findings (dep-stale, warnings) go into output and memory — never exit codes. This prevents false-positive OnFailure notifications (see learning #59 in [doc 24](../24-roadmap-corrections.md)).

---

## Evolution Path

How the system grows from manual practices to automated enforcement.

### The Graduation Pathway

From [00-user-practices.md](../00-user-practices.md) — the feedback loop that drives evolution:

```
Manual practice (user does it by hand, documents in doc 00)
    ↓ repeated 3+ times
Convention (encoded in rules/, referenced in CLAUDE.md)
    ↓ compliance matters
Workflow (encoded as a skill, invoked on demand)
    ↓ compliance is critical
Enforcement (encoded as a hook, runs automatically)
```

Each level is harder to set up but more reliable. The system should start manual and graduate upward based on pain signals from real usage.

**Evidence:** The Python tool preferences (uv + ruff, [doc 00](../00-user-practices.md) entry 2026-02-12) started as a manual practice. After confirming them across clients, they graduated to `~/.claude/rules/universal-quality.md` — now enforced by convention across all clients.

### Git Workflow as Lifecycle Tool

From [26-git-branching-strategies.md](../../../brana-knowledge/dimensions/26-git-branching-strategies.md) — GitHub Flow as the development lifecycle:

- **Every change starts on a branch.** Before the first edit, not after.
- **Branch prefixes map to work types:** `feat/`, `fix/`, `docs/`, `chore/`, `refactor/`, `test/`, `perf/`
- **`--no-ff` always.** Preserves branch grouping in `git log --graph`.
- **Test before merge.** Run `./test.sh` before merging to main.
- **Short-lived branches.** Features in days, fixes in hours, docs in one session.

The git history IS the lifecycle record. `git log --oneline --graph` tells the story of what was built and when.

### The Build-Phase Cycle

From the roadmap precision principle — the implementation loop that uses the lifecycle:

```
dimension docs → reflection docs → precise roadmap → implement → debrief → maintain-specs
```

Each cycle:
1. **Plan** — read the roadmap, verify specs are current
2. **Recall** — `/brana:memory recall` for relevant learned patterns
3. **Build** — implement work items with mini-debriefs after each
4. **Test** — run `./test.sh` before merging
5. **Debrief** — `/debrief` extracts errata and learnings
6. **Maintain** — `/brana:maintain-specs` propagates findings through spec layers
7. **Tag** — version the release, update portfolio

The debrief→maintain-specs loop is what keeps specs alive. Without it, specs drift from reality with every implementation session.

**Four feedback paths.** Findings from implementation don't all go to the same place — each path serves a different layer:

1. **Implementation findings → `/brana:maintain-specs`** — when building reveals a spec error or gap, maintain-specs cascades the fix through dimension → reflection → roadmap. This is the **document layer**: correcting what the system says.
2. **Event capture → `/brana:log`** — links, calls, meetings, ideas, observations are captured into a searchable append-only log. This is the **observation layer**: recording what happened so it can be triaged later (e.g. promoted to a task or referenced in a review).
3. **Tactical advice → task `context` field** — `system/rules/tactical-context.md` guides appending session advice to related tasks by keyword/tag matching. This is the **execution layer**: enriching the next session that picks up the same task.
4. **Reusable patterns → `/brana:retrospective`** — extracts durable patterns into claude-flow memory (ReasoningBank) with confidence tracking. This is the **knowledge layer**: building institutional memory that outlives any single task or spec.

---

## The User Feedback Loop

The mastermind architecture describes a system that learns from code sessions. But it has a blind spot: the user's subjective experience. Did the SessionStart recall feel useful or noisy? Did `/brana:memory pollinate` surface relevant patterns or junk? Did the deploy flow feel smooth or brittle?

[00-user-practices.md](../00-user-practices.md) closes this gap. It captures field notes from real usage — observations the user makes while living with the system. These observations feed back into the architecture:

- **Graduation path:** A manual practice the user keeps repeating signals a missing automation. That observation, recorded in [doc 00](../00-user-practices.md), becomes a hook or validation check in a future phase.
- **Anti-pattern discovery:** When the user notices something that consistently doesn't work, it gets recorded and eventually influences triage decisions in [08-diagnosis.md](./08-diagnosis.md).
- **Calibration signal:** The user's qualitative assessment of recall quality complements the quantitative RAG metrics defined in [31-assurance.md](./31-assurance.md).

---

## Open Questions

### Lifecycle
3. **When does the brain get too big?** 500 patterns is manageable. 5,000? At some point you need pruning, archival, or hierarchical summarization.

8. **Background learning ("the night shift")?** Background workers that re-analyze old sessions with new knowledge, extracting patterns you missed in real-time. **Note:** Blocked by claude-flow daemon stability — see [05-claude-flow-v3-analysis.md](../../../brana-knowledge/dimensions/05-claude-flow-v3-analysis.md). Revisit after daemon reliability is confirmed.

10. **Apprentice mode for new projects?** When starting a new project, aggressively query ReasoningBank for anything remotely relevant, building up project-specific knowledge fast. Then dial back as the project matures.

---

## Cross-References

- [14-mastermind-architecture.md](./14-mastermind-architecture.md) — R2: architecture that this reflection tracks through time
- [31-assurance.md](./31-assurance.md) — R3: validation at each lifecycle stage
- [15-self-development-workflow.md](../15-self-development-workflow.md) — genome/connectome separation, deploy pipeline, testing, versioning
- [25-self-documentation.md](../25-self-documentation.md) — staleness detection, growth stages, documentation locality
- [16-knowledge-health.md](../../../brana-knowledge/dimensions/16-knowledge-health.md) — immune system as ongoing maintenance
- [00-user-practices.md](../00-user-practices.md) — user feedback loop: graduation pathway from manual to automated
- [26-git-branching-strategies.md](../../../brana-knowledge/dimensions/26-git-branching-strategies.md) — GitHub Flow as lifecycle tool
- [22-testing.md](../../../brana-knowledge/dimensions/22-testing.md) — testing methodology integrated into the build cycle
- [08-diagnosis.md](./08-diagnosis.md) — R1: triage decisions that lifecycle implements

---

## Research Resources

| # | Author | Topic | Source | Takeaway |
|---|--------|-------|--------|----------|
| 1 | alexander-chiou | techcareergrowth softwareengineering ai | [LI](https://www.linkedin.com/posts/alexander-chiou_techcareergrowth-softwareengineering-ai-activity-7328811430877585409-_bLz?utm_source=share&utm_medium=member_android&rcm=ACoAAARWJLkBjqr70A1PjBg5r3-pHzy3QmyBYwc) | — |
| 2 | juanjosebehrend | moving away from agile whats next martin | [LI](https://www.linkedin.com/posts/juanjosebehrend_moving-away-from-agile-whats-next-martin-activity-7409571238437732352-bXb9?utm_source=share&utm_medium=member_android&rcm=ACoAAARWJLkBjqr70A1PjBg5r3-pHzy3QmyBYwc) | — |
| 3 | NirDiamant | agents-towards-production | [GH](https://github.com/NirDiamant/agents-towards-production?tab=readme-ov-file) | — |
| 4 | multi-modal-ai | multimodal-agents-course | [GH](https://github.com/multi-modal-ai/multimodal-agents-course?utm_source=substack&utm_medium=email) | — |
| 5 | agusvg | ia driven development lyfecicle | [article](https://agusvg.substack.com/p/ia-driven-development-lyfecicle?r=5bzedx) | — |
| 6 | lorenzopadoan | How I fixed autonomous coding | [article](https://open.substack.com/pub/lorenzopadoan/p/how-i-fixed-autonomous-coding) | Post-execution hook pattern: examine output for completion signals before session exit. Deterministic re-prompting with accumulated context. Completion signal vocabulary for stopping/starting loops. Instruction quality is the bottleneck, not tool capability. Fresh angle: post-session hook could complement brana's debrief-analyst. |

