# 08 - Diagnosis: Keep, Drop, Defer

What to preserve, eliminate, and postpone for brana v2. R1 in the reflection DAG — the triage operation that feeds all downstream reflections.

### Reflection DAG Orientation

```
R1: Triage (this doc)  →  R2: Architecture (14)
  "What matters?"            "How does it compose?"
                                   ↓              ↓
                             R3: Assurance (31)  R4: Lifecycle (32)
                             "Does it work?"     "How does it evolve?"

R5: Transfer (29) — semi-independent, cross-references R2-R4
  "What generalizes?"
```

R1 triages every dimension doc → R2 composes the architecture → R3 validates it works → R4 tracks how it evolves → R5 identifies what transfers beyond code projects.

---

## Proven Patterns Worth Preserving

### 1. CLAUDE.md as Lightweight Orchestrator
**Why keep:** The pattern of CLAUDE.md as an index (~12 KB) rather than a monolithic doc is effective. It keeps context overhead manageable while pointing to detailed modules. Vercel's evaluations confirm this empirically: static markdown in context (AGENTS.md/CLAUDE.md) achieves **100% pass rate** vs **79%** for skills with explicit "Use when..." descriptions, vs **53%** for skills with default descriptions. Always-in-context knowledge beats lazy-loaded retrieval for anything the agent always needs.

**For v2:** Continue this pattern. CLAUDE.md should be a concise control center, not a dumping ground. Reserve it for knowledge that must be 100% available; use skills for explicit workflows.

### 2. PM Separation (Code + PM Repos)
**Why keep:** Clean separation of concerns. Code stays lean for deployment, decisions are preserved for context. The symlink bridge is lightweight and breaks gracefully.

**For v2:** ~~Preserve the pattern.~~ **Superseded by [39-architecture-redesign.md](../39-architecture-redesign.md).** [Doc 39](../39-architecture-redesign.md)'s analysis concludes the repo boundary adds overhead without contributing to spec quality. The cognitive separation (design vs build) is preserved by directory structure and branch conventions (`docs/*` vs `feat/*`), not by repo boundaries. The merge is planned (see [doc 39](../39-architecture-redesign.md) migration phases).

### 3. Concurrent Execution Golden Rule
**Why keep:** "1 MESSAGE = ALL RELATED OPERATIONS" is a genuine performance win. Batching parallel tool calls reduces round-trips and token waste.

**For v2:** This should be a core principle, enforced through instructions rather than hooks.

### 4. Work Journal & Crash Recovery
**Why keep:** Long sessions crash. Having automatic session state persistence and recovery options is valuable.

**For v2:** Simplify the file structure (fewer, larger journal files instead of hundreds of small ones). Consider using ruflo memory for state persistence instead of custom JSON.

### 5. Hook Lifecycle
**Why keep:** SessionStart, PreToolUse, PostToolUse, SessionEnd - the event model is sound. Hooks enable extensibility without modifying core instructions.

**For v2:** Use native Claude Code hooks. Strip down to essential hooks only: PreToolUse (spec/test gate = development discipline enforcement), SessionStart (session tracking, context loading), SessionEnd (learnings capture, state sync). *(Crash recovery and branch protection were originally listed but never implemented — branch protection is handled via CLAUDE.md instructions, crash recovery deferred.)*

### 6. Feature Lifecycle (SPARC Phases)
**Why keep:** Specification -> Pseudocode -> Architecture -> Refinement -> Completion forces structured thinking. Features tracked through phases prevent skipping important steps.

**For v2:** Keep the phases. Simplify the tracking (checkboxes in BACKLOG.md, not separate files for small features).

### 7. Progressive Disclosure
**Why keep:** Backlog (summary) -> Feature README (overview) -> Requirements (detail) -> Architecture (deep dive). Right level of detail when you need it.

**For v2:** Preserve this layering. Essential for navigating large projects without drowning in docs. But per [25-self-documentation.md](../25-self-documentation.md) Mechanism 7 (documentation locality), each layer must be generated or linked — not manually duplicated. If the same fact lives in both a spec doc and MEMORY.md, changes to one silently break the other. Progressive disclosure works only when the summary layers are generated views of the source docs.

---

## Over-Engineered Components to Eliminate

### 1. 5-Phase Skill Routing Pipeline
**Why drop:** Context Detection -> FACT Fast Match -> ruvector Semantic -> dspy Validation -> Agent Coordination is 5 phases with 3 external dependencies for what Claude 4.6 can reason about directly.

**Replace with:** Put skill descriptions in `system/skills/` (loaded via plugin) and trust the model to read and apply them. Use rules directory for path-scoped guidance. If routing is needed, a single keyword-match phase is sufficient.

### 2. registry.yaml + context-loader.sh
**Why drop:** The module registry and loader were needed when CLAUDE.md couldn't handle dynamic context. Claude Code's rules directory and native skill loading handle this now.

**Replace with:** `.claude/rules/` for path-scoped rules (auto-loaded by Claude Code), CLAUDE.md for global instructions, skills directory for specialized behaviors.

### 3. Custom Agent Activation Matrices
**Why drop:** Keyword-triggered agent activation ("audit" -> verification-quality + code-analyzer) adds a brittle indirection layer. The user or the model can decide which agent type to use.

**Replace with:** Document agent capabilities in CLAUDE.md. Let the model or user choose based on task description. The Task tool's `subagent_type` parameter already handles this.

### 4. 76 Agent Configurations
**Why drop:** 76 agents with inconsistent metadata (mixed priority formats, incomplete descriptions) creates confusion. Most sessions use 3-5 agents.

**Replace with:** A curated set of 10-15 well-defined agent types. Each with clear purpose, capabilities, and use cases. Quality over quantity.

### 5. Complex Topology Auto-Selection
**Why drop:** Adaptive topology switching between hierarchical, mesh, star, and ring is engineering for engineering's sake. Most tasks work fine with a simple lead + workers pattern.

**Replace with:** Native Agent Teams with a team lead and specialized workers. Only add topology complexity for specific use cases that demonstrate need. **Caveat (Feb 2026):** Agent Teams remain experimental — disabled by default (`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`), 2x token cost (~800k vs ~440k for 3-worker subagent team), no file locking (last-write-wins), no resumption for in-process teammates. Use subagents for production patterns; escalate to Teams only for genuinely parallel multi-file work where coordination benefits outweigh the experimental status.

### 6. Multiple Consensus Protocols
**Why drop:** Raft, Byzantine, Gossip, CRDT, Quorum - development tooling doesn't need Byzantine fault tolerance. Agents aren't adversarial.

**Replace with:** Simple task assignment via shared task list (native Agent Teams). If verification is needed, add a single reviewer agent. **Same Agent Teams caveat applies** — use subagent-based task assignment until Teams exit experimental status.

---

## Things Claude 4.6 Makes Obsolete

### 1. Custom Skill Routing
Claude 4.6 can read skill definitions and apply them through reasoning. The multi-phase pipeline that routes tasks to skills is unnecessary when the model can do this natively.

**Exception:** If you have 100+ skills and can't fit them all in context, you still need a loading strategy. But this should be simple (rules directory + path scoping), not a 5-phase pipeline.

### 2. Module Load Strategy Management
The always/contextual/on-demand loading system was designed for context window limitations. With 200K context (1M via API beta), loading ~26 KB of always-on rules is trivial. The overhead of managing load strategies may exceed the overhead of just loading everything.

**Nuance:** For very large module sets, loading strategy still matters. But for 8-10 core modules, just load them all.

### 3. Keyword-Based Agent Spawning
"When user says 'performance', spawn perf-analyzer" is a brittle pattern. Claude 4.6 can understand intent from natural language and choose appropriate agent types without keyword matching.

### 4. Pre-computed Routing Decisions
The routing system pre-computes skill selections before the model sees the task. Claude 4.6's reasoning is fast enough to make these decisions inline, without a preprocessing step.

### 5. Custom Branch Protection Hooks
CLAUDE.md instructions ("never push to main") combined with git hooks handle branch protection. Custom PreToolUse hooks for git commands add latency without adding safety.

**Note:** This applies to branch protection only. PreToolUse hooks are essential for development discipline enforcement (spec-before-code, test-before-code) — see [14-mastermind-architecture.md](./14-mastermind-architecture.md) "Project Enforcement" section and [11-ecosystem-skills-plugins.md](../../../brana-knowledge/dimensions/11-ecosystem-skills-plugins.md) section 5 for the enforcement tools landscape.

---

## Claude-Flow Features Worth Adopting

### 1. ruflo memory (Persistent Pattern Memory)
**Why adopt:** Cross-session learning is the single biggest gap in native Claude Code. Patterns stored in SQLite with all-MiniLM-L6-v2 384-dim embeddings (local ONNX, no API cost) enable the system to remember what worked.

**Implementation priority:** High. This is the #1 value-add over native capabilities.

**When to use:** Any project where similar problems are solved repeatedly. Architecture patterns, debugging approaches, test strategies, code review standards.

### 2. WASM Agent Booster (When Stable)
**Why adopt:** Bypassing LLM calls for deterministic transforms (rename variables, add types, remove console.log) saves real money and time.

**Implementation priority:** Medium. Wait for alpha stability to improve.

**When to use:** High-volume workloads with many simple, repetitive operations.

### 3. Token Routing (Haiku -> Sonnet -> Opus)
**Why adopt:** Using the cheapest capable model for each task reduces costs by 30-50%. Opus for decisions, Sonnet for implementation, Haiku for scouts.

**Implementation priority:** ~~Medium.~~ **Implemented.** [ADR-018](../architecture/decisions/ADR-018-dynamic-model-routing.md) (accepted 2026-03-11) defines per-message complexity scoring (0.0–1.0) that overrides static agent assignments. WASM tier deferred. Static agent model assignments (Haiku/Sonnet/Opus) remain as defaults; ADR-018 governs runtime routing for Tier 3 operator sessions. Extended to chat sessions via [ADR-019](../architecture/decisions/ADR-019-brana-chat-sessions.md) tiered model routing (Tier 1 = Haiku locked, Tier 2 = Sonnet default, Tier 3 = dynamic).

**When to use:** Any project running multiple agents or long sessions.

### 4. Background Workers (Audit, TestGaps, Optimize)
**Why adopt:** Having workers that continuously scan for quality issues, test gaps, and optimization opportunities adds value without interrupting main work.

**Implementation priority:** Low. Nice to have, not essential for v2 launch.

**When to use:** Mature projects with established codebases.

---

## Claude-Flow Features to Skip

### 1. Full Swarm Topologies
**Why skip:** Hierarchical, mesh, star, ring with adaptive switching is over-engineered for development tooling. Native Agent Teams with a lead + workers pattern covers 95% of cases.

### 2. Byzantine Fault Tolerance
**Why skip:** Agents aren't adversarial. If an agent produces bad output, a reviewer agent catches it. You don't need 2/3 consensus for code generation.

### 3. SONA Self-Learning (For Now)
**Why skip initially:** Promising but unproven at scale. Requires 100+ task executions before providing value. The learning curve is steep and failure modes are poorly documented.

**Revisit when:** ruflo memory is established and you want automated pattern optimization.

### 4. Full 170+ MCP Tool Surface
**Why skip:** Most tools are unused in any given session. Adding all of them creates noise and increases complexity. Use only what's needed.

### 5. Daemon System
**Why skip:** Background workers with priorities and scheduling require reliability guarantees that alpha software can't provide. Run workers manually or on-demand instead.

---

## Validation from Testing & Evaluation Research

Findings from docs [22-testing.md](../../../brana-knowledge/dimensions/22-testing.md) and [23-evaluation.md](../../../brana-knowledge/dimensions/23-evaluation.md) that validate, refine, or inform the decisions above.

### Decisions Confirmed by Hard Data

**Drop custom skill routing — even stronger case.** Vercel's agent evals found CLAUDE.md achieves 100% pass rate vs 53% for skill invocation. Skills were never invoked in 56% of test cases. This isn't just "Claude 4.6 can reason about skills" — the data shows static instructions outperform dynamic skill routing for domain knowledge.

**Thin CLAUDE.md — now has a ceiling number.** Frontier models show linear instruction-following decay with a ceiling around ~150-200 instructions. Target 15-30 always-present instructions. This answers the "how thin?" question with empirical evidence: every instruction competes for attention, and the decay is measurable.

**Hook lifecycle — validated, but skill activation is fragile.** Skills activate at only ~20% rate with simple instructions. Scott Spence demonstrated 84% activation with forced eval hooks and 200+ tests. The hook lifecycle is the right pattern, but skills need explicit activation enforcement, not just availability.

### New Input for Open Questions

**ruflo memory from day one or later?** (question #7) — Eval-driven development methodology (Anthropic, Vercel, Obra) says: write the eval before the feature. Build a 20-task recall eval suite FIRST, then add ruflo memory. If recall precision < 50%, the feature isn't ready. This gives a concrete decision framework rather than debating timing.

**Infrastructure noise.** Anthropic found up to 6 percentage point score differences from infrastructure configuration alone (same model, same prompts). Any quality measurement of keep/drop decisions must account for this variance.

### Insights from Self-Documentation Research

Findings from [25-self-documentation.md](../25-self-documentation.md) that refine existing decisions and resolve open questions.

**Progressive disclosure — now has a machine-readable layer.** Keep pattern #7 says "right level of detail when you need it." [Doc 25](../25-self-documentation.md) adds frontmatter metadata (status, growth_stage, depends_on) that enables auto-generated indexes and dependency graphs. Progressive disclosure isn't just about document structure — it's about making the layers navigable by both humans and AI agents. Growth stages (seedling → budding → evergreen) tell AI agents how much to trust each doc.

**Open question #6 resolved: ADRs vs inline comments.** [Doc 25](../25-self-documentation.md) recommends neither in their pure form. Instead: keep decisions in existing documents but extract a **decision index** — a generated list of key decisions with links to the source sections. This is the ADR pattern without restructuring existing docs. No new files, just a navigable index.

### User Feedback Loop

Findings from [00-user-practices.md](../00-user-practices.md) that inform keep/drop/defer decisions.

**Manual practices are a signal for automation.** When the user repeatedly documents the same practice ("always run validate before deploy"), that's evidence the practice should graduate from a manual habit to a hook or validation check. The keep/drop decisions above assumed static system capabilities — [doc 00](../00-user-practices.md) adds a living feedback channel where usage patterns can promote deferred items to "keep" or demote kept items to "drop" based on real experience.

**Anti-patterns discovered in practice outweigh theoretical concerns.** The "over-engineered components to eliminate" section above is based on analysis. [Doc 00](../00-user-practices.md) captures what the user actually stumbles over. When a user-discovered anti-pattern contradicts a spec decision, the user's experience takes precedence — update the spec, not the practice.

---

## Dimension Doc Triage: Full Coverage

Every dimension doc triaged for brana v2. [Docs 01](../dimensions/01-brana-system-analysis.md)-07 covered above (Keep/Drop/Defer sections). Remaining docs triaged below.

### [Doc 09](../dimensions/09-claude-code-native-features.md) — Claude Code Native Features
**Verdict: Keep as reference.** The definitive catalog of Claude Code's 6 extension layers (CLAUDE.md, rules, skills, subagents, teams, hooks). Source of truth for hook event list, stdin/stdout contracts, async constraints. R2 depends on it heavily for hook design. Not directly actionable — it's infrastructure knowledge.

### [Doc 10](../dimensions/10-statusline-research.md) — Statusline Research
**Verdict: Defer.** Community status line projects (session monitoring, cost tracking, context visualization) are nice-to-have. No dimension doc depends on it, no reflection needs it. Revisit when brana is stable and the user wants observability.

### [Doc 11](../../../brana-knowledge/dimensions/11-ecosystem-skills-plugins.md) — Ecosystem: Skills, Plugins & Hooks
**Verdict: Keep — ecosystem intelligence.** The definitive catalog of Claude Code's 4 extension channels (skills.sh, Anthropic marketplace, bundled plugins, community hooks). Source for skill architecture decisions in R2 and enforcement tool selection. Referenced throughout this doc for multi-agent TDD patterns and marketplace integration.

### [Doc 12](../dimensions/12-skill-selector.md) — Skill Selector
**Verdict: Keep — three-tier trust model.** The local core / curated catalog / discovery tier model is the right framework for skill trust. The quarantine pattern (doc 16) extends this. R2 uses it for skill architecture, R4 for lifecycle (trust graduation).

### [Doc 13](../dimensions/13-challenger-agent.md) — Challenger Agent
**Verdict: Keep as capability.** Adversarial review (Opus challenger) is valuable for big decisions. Implemented as `/brana:challenge`. Subscription-native, rate-limit-aware. Low maintenance, high value when used. Model upgraded from Sonnet to Opus for deeper adversarial quality (see [13-challenger-agent.md](../../../brana-knowledge/dimensions/13-challenger-agent.md)).

### [Doc 15](../15-self-development-workflow.md) — Self-Development Workflow
**Verdict: Keep — genome/connectome separation is foundational.** The distinction between system code (genome, versioned in git) and learned knowledge (connectome, never rolled back) is a first-order architectural decision. R2 builds on it, R4 operationalizes it. The deploy pipeline, testing strategy, and rollback safety all flow from this separation.

### [Doc 16](../dimensions/16-knowledge-health.md) — Knowledge Health
**Verdict: Keep — immune system is critical.** Eight infection vectors + prevention/healing strategies. The quarantine-first approach is validated. R3 uses it for ongoing assurance, R4 for maintenance cadences. Without this, the learning loop is a liability, not a feature.

### [Doc 19](../19-pm-system-design.md) — PM System Design
**Verdict: Keep as reference for solo PM.** Now/Next/Later, weekly review, portfolio file, GitHub Issues + branch strategy. Applicable to both code projects and business projects (R5 cross-references it). Not yet implemented as a plugin — deferred to pain-driven additions.

### [Docs 20](../dimensions/20-anthropic-blog-findings.md)-21 — Anthropic Blog Findings & Engineering Deep Dive
**Verdict: Keep as informational.** [Doc 20](../dimensions/20-anthropic-blog-findings.md) is an index; [doc 21](../dimensions/21-anthropic-engineering-deep-dive.md) is the exhaustive analysis. Together they provide the empirical foundation for context engineering theory, sub-agent sizing, token budget constraints, and eval methodology. R2 cites them for architecture principles. Not directly actionable — they're the research backing.

### [Doc 22](../dimensions/22-testing.md) — Testing
**Verdict: Keep.** The 7-layer testing pyramid, record/playback pattern, and headless mode testing are the foundation for R3 (assurance). Deterministic vs non-deterministic distinction is essential for knowing what can be CI-gated vs what needs eval.

### [Doc 23](../dimensions/23-evaluation.md) — Evaluation
**Verdict: Keep.** pass@k vs pass^k, RAG metrics, LLM-as-judge, fixture evals. R3 uses this for outcome evaluation methodology. The "grade outcomes not paths" principle applies across all reflection docs.

### [Doc 26](../dimensions/26-git-branching-strategies.md) — Git Branching Strategies
**Verdict: Keep — decision made.** GitHub Flow validated as optimal for solo developer with spec-driven workflows. R4 operationalizes this as the lifecycle tool. The `--no-ff` always rule, branch naming convention, and short-lived branch discipline all stem from this research.

### [Doc 27](../dimensions/27-project-alignment-methodology.md) — Project Alignment Methodology
**Verdict: Keep.** 28-item checklist, 3 tiers, 6-phase pipeline (discover, assess, plan, implement, verify, document). Implemented as `/brana:align`. The bridge between R2's enforcement hierarchy and real projects that need the structure for enforcement to apply.

### [Doc 28](../dimensions/28-startup-smb-management.md) — Startup & SMB Management
**Verdict: Keep.** Source for R5 (transfer). Frameworks, books, phase-based models, software→business pattern transfer. Five venture skills emerged from this research.

### [Doc 33](../dimensions/33-research-methodology.md) — Research Methodology
**Verdict: Keep.** Formalizes the recursive discovery process that produced the other 32 docs. Source registry (trust tiers, cadence, version pinning), leads queue, 5 research archetypes, and the `/brana:research` skill as atomic primitive (`--refresh` flag replaces the former `/refresh-knowledge` command). Without this, research stays ad-hoc and unreproducible.

### [Doc 34](../dimensions/34-venture-operating-system.md) — Venture Operating System
**Verdict: Keep.** The business operations layer — MCP integrations (Google Sheets, Slack, QuickBooks, Stripe), daily/weekly/monthly skill cadences (`/morning`, `/weekly-review`, `/monthly-close`, `/monthly-plan`), growth experiments, pipeline tracking, financial modeling. Extends [doc 28](../dimensions/28-startup-smb-management.md)'s frameworks into a deployable operating system. R5 synthesizes the venture management pattern; [doc 34](../dimensions/34-venture-operating-system.md) provides the full implementation architecture.

### [Doc 35](../dimensions/35-context-engineering-principles.md) — Context Engineering Principles
**Verdict: Keep — decision framework for information placement.** Formalizes where new information belongs (always-loaded vs warm vs cold), the budget architecture (23KB hard limit with empirical growth history), progressive disclosure (hot/warm/cold tiers), sub-agent summary protocols, and context failure modes (saturation, attention rot, knowledge poisoning, budget creep). R2 uses it for architecture decisions, R3 validates against it, R4 operationalizes budget management. Without this, placement decisions are ad-hoc and budget grows unchecked.

### [Doc 36](../../../brana-knowledge/dimensions/36-claw-ecosystem-chat-interface.md) — Claw Ecosystem & Chat Interface
**Verdict: Keep.** Maps the agent runtime landscape (OpenClaw, NanoClaw, ZeroClaw) for building chat interfaces powered by brana. **Consumed by [ADR-019](../architecture/decisions/ADR-019-brana-chat-sessions.md)** (accepted 2026-03-13) as design input for the 3-layer channel-agnostic session architecture (channel adapters → session manager → brana agent runtime) with tiered access (Tier 1/2/3). OpenClaw CVE-2026-25253 is now a live disqualification decision in ADR-019. ZeroClaw deferred (complexity, Rust stack). Kapso ([doc 39](../../../brana-knowledge/dimensions/39-kapso-ai-platform.md)) is the WhatsApp channel adapter; claws are alternative multi-channel runtimes, not complementary infrastructure. Active implementation: ph-013, ms-048 (t-413–t-422).

### [Doc 37](../../../brana-knowledge/dimensions/37-ruvnet-development-practices.md) — ruvnet Development Practices
**Verdict: Keep.** Studies ruflo creator's development methodology — three-tier maturity model, MADR+SPARC ADRs, CCEPL failure taxonomy. Source for R4 lifecycle practices. 5 transferable practices identified for brana process improvement.

### [Doc 38](../dimensions/38-design-thinking.md) — Design Thinking
**Verdict: Keep.** Applies design thinking methodology (empathy mapping, HMW questions, divergent ideation) to brana's development process. Source for R5 creative methods, R2 skill design patterns.

### [Doc 39 — thebrana](../39-architecture-redesign.md) — Architecture Redesign
**Verdict: Keep — supersedes item 2 above (PM Separation).** Three decisions: (1) merge enter/ into thebrana/ as `docs/` workspace, (2) evolve brana-knowledge/ into an active indexed knowledge base, (3) wire retrieval via ruflo embeddings CLI. Spike validated (Phase 0.5 passed — 384-dim ONNX embeddings, semantic similarity confirmed). AgentDB stalled; fallback (embeddings + SQLite) is primary strategy. Migration phases: 0→0.5(done)→1(structural)→2(skill rewrites)→3(retrieval prototype)→4(scale content). R2 architecture directly affected; R3/R4/R5 will need updates when phases execute.

### [Doc 39 — Kapso](../../../brana-knowledge/dimensions/39-kapso-ai-platform.md) — Kapso AI Platform
**Verdict: Keep.** WhatsApp infrastructure for agent delivery — MCP server, webhooks, visual workflows, AI Fields, voice agents. Source for R5 (venture delivery). Concrete platform for proyecto_anita and somos_mirada WhatsApp services. Complements [doc 36](../../../brana-knowledge/dimensions/36-claw-ecosystem-chat-interface.md) (Kapso is delivery layer, claws are agent runtime).

### [Doc 40](../../../brana-knowledge/dimensions/40-product-discovery-literature.md) — Product Discovery Literature
**Verdict: Keep.** Frameworks for validating product ideas before building — Lean UX, Shape Up, Jobs to Be Done, continuous discovery habits. Source for R5 venture methodology. Grounds `/brana:venture-phase` launch milestone.

### [Doc 41](../../../brana-knowledge/dimensions/41-growth-metrics-market-strategy-literature.md) — Growth Metrics & Market Strategy
**Verdict: Keep.** AARRR funnel, LTV:CAC, Rule of 40, market sizing, competitive analysis frameworks. Source for R5 metrics and `/brana:review` financial checks.

### [Doc 42](../../../brana-knowledge/dimensions/42-product-operations-literature.md) — Product Operations
**Verdict: Keep.** SOPs, process design, operational scaling, team structure. Source for R5 operational maturity assessment in `/brana:onboard` venture mode.

### Doc 43 — LinkedIn Personal Brand Strategy
**Verdict: Moved.** Migrated to standalone linkedin project at `~/enter_thebrana/linkedin/research/linkedin-personal-brand-strategy.md`. Not a cross-client knowledge pattern — it's personal brand strategy.

### [Doc 44](../../../brana-knowledge/dimensions/44-systems-thinking-nature.md) — Systems Thinking & Nature
**Verdict: Keep.** Natural systems as models for engineered systems — feedback loops, emergence, resilience patterns, biomimicry. Deepest abstraction layer — grounds the "everything is a system" philosophy that brana is built on.

### [Doc 45](../../../brana-knowledge/dimensions/45-turboflow-agent-orchestration.md) — TurboFlow Agent Orchestration
**Verdict: Keep as reference.** TurboFlow v4.0 wraps Ruflo v3.5 with higher-level orchestration: Beads (git-native cross-session memory), GitNexus (codebase knowledge graphs), worktree isolation, and three-tier model routing. Validates brana's architectural choices from an external consumer perspective. Beads' JSONL-over-git approach is an alternative to brana's SQLite + embeddings strategy — worth watching for convergence patterns.

---

## Resolved Questions (from R2)

Architectural questions that were open during initial design but have been resolved through research and implementation.

2. **ruflo memory confidence decay?** → Yes. Monthly decay function: unused patterns lose 0.05/month, failed patterns lose 0.2, below 0.2 gets auto-archived. Decay is not deletion — archived patterns are restorable. See [16-knowledge-health.md](../../../brana-knowledge/dimensions/16-knowledge-health.md).

4. **How much of this can be native-only?** → ruflo (now Ruflo) is an enhancement layer, not a hard dependency. The plugin + bootstrap architecture functions independently; ruflo adds semantic memory search and cross-session pattern recall. Degrade gracefully: fall back to auto-memory (plain markdown) when ruflo is unavailable. See [17-implementation-roadmap.md](../17-implementation-roadmap.md).

5. **ruflo stability risk?** → Every ruflo call is wrapped in error handling. Degraded mode writes learnings to markdown fallback files. Each phase's dependency is additive — if a feature breaks, you lose that phase's enhancement but everything below still works. See [17-implementation-roadmap.md](../17-implementation-roadmap.md).

6. **ADRs vs inline comments?** → Neither in pure form. Keep decisions in existing documents but extract a decision index — a generated list of key decisions with links to source sections. See [25-self-documentation.md](../25-self-documentation.md).

12. **Native Agent Teams or ruflo swarms?** → Hybrid. Native Agent Teams for execution coordination, ruflo ruflo memory for cross-session memory. First concrete pattern: multi-agent TDD with context isolation (see [14-mastermind-architecture.md](./14-mastermind-architecture.md), [22-testing.md](../../../brana-knowledge/dimensions/22-testing.md), [11-ecosystem-skills-plugins.md](../../../brana-knowledge/dimensions/11-ecosystem-skills-plugins.md)).

---

## Open Questions for Discussion

### Architecture
1. **How thin should CLAUDE.md be?** Current: 12 KB index + 35 KB modules. Could we get to 5 KB index + rules directory + skills?
2. **Should we use rules directory instead of modules?** Claude Code's rules auto-load by path. This could replace the entire module loading system.
3. **One CLAUDE.md or multiple?** Monorepo patterns support nested CLAUDE.md files. Is this simpler than module loading?

### PM Framework
4. **Should PM automation exist?** Auto-creating feature folders, updating backlogs, syncing sprint status. Or keep it manual for simplicity?
5. **Is the full SPARC lifecycle necessary for all features?** Maybe P3/P4 features don't need the full specification-to-completion pipeline.
6. **ADRs vs inline comments?** Architecture decisions could be tracked in code comments or CLAUDE.md instead of separate files.

### Claude-Flow Integration
7. **ruflo memory from day one or add later?** Starting with it means learning the tooling upfront. Adding later means retrofitting.
8. **Which MCP tools are essential?** Of 170+ tools, which 10-15 provide 80% of the value?
9. **How to handle ruflo alpha instability?** Pin versions? Vendor specific modules? Wait for stable release?

### Agent Strategy
10. **How many agent types?** Current brana has 76 (too many). What's the right number? 10? 15? 20?
11. **Should agents have persistent identities?** Named agents with memory vs anonymous workers spawned per task.
12. ~~**Native Agent Teams or ruflo swarms for coordination?**~~ → Resolved: hybrid. Native Agent Teams for execution coordination, ruflo ruflo memory for cross-session memory. First concrete pattern: multi-agent TDD with context isolation (see [14-mastermind-architecture.md](./14-mastermind-architecture.md) "Project Enforcement", [22-testing.md](../../../brana-knowledge/dimensions/22-testing.md) "Multi-Agent TDD", [11-ecosystem-skills-plugins.md](../../../brana-knowledge/dimensions/11-ecosystem-skills-plugins.md) section 5).

### Cost Optimization
13. ~~**Is model routing worth the complexity?**~~ → Resolved: **yes — implemented via [ADR-018](../architecture/decisions/ADR-018-dynamic-model-routing.md).** Per-message complexity scoring (0.0–1.0) overrides static agent assignments at runtime. Static agent roster (Haiku for 8 fast agents, Sonnet for pr-reviewer, Opus for challenger/debrief-analyst) remains as the default; ADR-018 adds dynamic routing on top. Extended to multi-channel via [ADR-019](../architecture/decisions/ADR-019-brana-chat-sessions.md) tiered model routing.
14. **How much should we invest in WASM bypass?** If alpha stability improves, this could save significant cost. But it's a bet on external tooling.
15. **Token budget allocation?** How much of the session budget goes to learning vs execution?
