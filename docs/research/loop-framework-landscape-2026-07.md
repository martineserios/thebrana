# Loop Engineering Similar Repos & Frameworks — Research Catalog

**Date:** 2026-07-20  
**Task:** Find GitHub repos and frameworks similar to github.com/cobusgreyling/loop-engineering (production agent loop toolkits with scheduling, verification, cost control, and L1→L3 autonomy patterns).

---

## CLOSEST ANALOGUES — Same "Framework for Production Agent Loops" Space

### 1. **ralph-loop-agent** (Vercel Labs)
- **GitHub:** [vercel-labs/ralph-loop-agent](https://github.com/vercel-labs/ralph-loop-agent)
- **What it is:** Experimental autonomous agent framework layering an outer verification loop over AI SDK's generateText to keep agents working until a task verifies as done (named after Ralph Wiggum's iterative persistence).
- **Comparison to loop-engineering:** Same space—iterative verification loops, L1-style autonomy with stop conditions, feedback injection on failure. Distinctive: TypeScript-native, tightly coupled to Vercel's AI SDK, focuses on continuous autonomy without external scheduler.
- **Distinctive primitive:** Outer verification loop wrapping single-model tool calls; persistent context summarization for long-running loops; built-in cost/token/iteration limits matching loop-engineering's budget concept.
- **Maturity:** 822 ⭐, 86 forks, TypeScript, Apache-2.0, experimental API stability (labels may change). Active as of Jan 2026.
- **Key difference from loop-engineering:** Ralph targets code migrations (Jest→Vitest, CJS→ESM, React upgrades) with single-shot verification; loop-engineering frames 7 production patterns + 4-file anatomy + maker/checker split. Ralph is more LLM-centric, loop-engineering is more systems-oriented.

---

### 2. **Loop Engineering** (Cobus Greyling — reference project)
- **Web:** [loopengineering.run](https://loopengineering.run/)
- **What it is:** Framework + npm CLI (loop-init, loop-audit, loop-cost, loop-context circuit-breaker, loop-worktree) for running production autonomous agent loops on a schedule with 7 patterns (daily-triage, PR-babysitter, CI-sweeper, dependency-sweeper, changelog-drafter, post-merge-cleanup, issue-triage), L1→L2→L3 autonomy levels, maker/checker verifier split, 4-file loop anatomy (LOOP.md/STATE.md/loop-budget.md/loop-run-log.md).
- **Companion projects (same author, not focus here):** memory-engineering, harness-foundry, outerloop, fleet-engineering, goal-engineering.
- **Distinctive:** Systems engineering focus on production safety (budget circuits, maker/checker architectural constraint, file-based state machine, scheduled entry points). Treats loop as deployable artifact with governance.

---

### 3. **Temporal** (Temporal Technologies)
- **Web:** [temporal.io](https://temporal.io/solutions/ai)
- **What it is:** Durable execution platform for long-running workflows; recently integrated with OpenAI Agent SDK to orchestrate reliable agent interactions with automatic retry, state persistence, and scheduling.
- **Comparison to loop-engineering:** Overlaps on scheduling, state persistence, and failure recovery. Positioned as enterprise workflow orchestration (handles any stateful workflow); loop-engineering is agent-loop-specific with verification/safety gate patterns.
- **Distinctive primitive:** Event sourcing + deterministic replay for durable execution; decouples scheduling from agent code; automatic history-based retry on failure. No notion of "verifier" or "maker/checker" split—focuses on orchestration infrastructure.
- **Maturity:** Enterprise-grade, used in production by Fortune 500 companies. AI+Agent SDKs integrations released 2026. No GitHub repo to star (SaaS + open-source SDKs).
- **Key difference:** Temporal is orchestration layer (where loops live); loop-engineering is loop anatomy + patterns (how to design them).

---

## ADJACENT FRAMEWORKS — Agent Scheduling + Loop Support (But Not Loop-Focused)

### 4. **LangGraph** (LangChain)
- **GitHub:** [langchain-ai/langgraph](https://github.com/langchain-ai/langgraph)
- **What it is:** Low-level orchestration framework for long-running, stateful agent workflows with durable execution, checkpoints, human-in-the-loop, and persistent memory.
- **Comparison to loop-engineering:** Broader scope—durable execution foundation vs. loop-specific patterns. LangGraph handles any stateful workflow; loop-engineering targets autonomous agent loops with verification and cost control.
- **Distinctive primitive:** Graph-based state machines (nodes, edges, cycles explicit); checkpoint-based persistence; separates working memory from cross-session memory; streaming support.
- **Maturity:** 37.7k ⭐, 6.3k forks, Python, MIT, 553 releases. V1.0 shipped 2025. Widely adopted foundation for agentic workflows.
- **Key difference:** LangGraph is general-purpose (any long-running task); loop-engineering is domain-specific (autonomous loops with schedule + verifier).

---

### 5. **OpenAI Agent SDK + Temporal Integration**
- **GitHub:** [openai/openai-agents-python](https://openai.github.io/openai-agents-python/) + Temporal integration (public preview)
- **What it is:** Lightweight Python SDK for agents with sessions (persistent memory across turns) + Temporal integration for durable execution, automatic retry on rate limit/crash, resume on failure.
- **Comparison to loop-engineering:** Provides agent loop infrastructure (session store, tool execution, durable execution); loop-engineering provides loop anatomy + production patterns. OpenAI SDK is agent-centric; loop-engineering is loop-centric.
- **Distinctive primitive:** Session interface abstraction (SQLite, Redis, DynamoDB backends); automatic Temporal workflow wrapping; resumption from exact failure point.
- **Maturity:** OpenAI SDK in GA; Temporal integration in Public Preview (2026). Session stores shipped with multiple implementations.
- **Key difference:** OpenAI SDK is framework for building a single agent loop; loop-engineering is toolkit for deploying multiple agent loops on schedule with verifier + budget guards.

---

### 6. **Claude Agent SDK** (Anthropic)
- **Docs:** [Claude Agent SDK Overview](https://code.claude.com/docs/en/agent-sdk/overview)
- **What it is:** Python/TypeScript SDK giving agents autonomous access to tools (file read/write, shell, web), with session persistence, structured outputs, cost tracking, and resumption.
- **Comparison to loop-engineering:** Covers single-agent loop infrastructure; loop-engineering adds scheduling, verification, budget, and multi-pattern deployment. Claude SDK is agent capability layer; loop-engineering is operational deployment layer.
- **Distinctive primitive:** Direct agent autonomy (agent picks tools, executes, loops until done); SessionStore protocol for cross-session state; cost tracking built-in; streaming support.
- **Maturity:** Anthropic-supported, available in Claude Code via /loop command. Production-ready.
- **Key difference:** Claude SDK is "how to build an autonomous agent"; loop-engineering is "how to deploy autonomous agents at scale with governance".

---

### 7. **Claude Code /loop + /schedule Commands**
- **What it is:** Native loop support in Claude Code harness: `/loop` for recurring execution of prompts/slash commands on interval; `/schedule` for cloud-hosted agents on cron.
- **Comparison to loop-engineering:** Covers scheduling + execution; loop-engineering adds verification, state anatomy, multi-pattern library, cost budgeting, and maker/checker split.
- **Distinctive primitive:** Direct loop injection into Claude Code session; native slash-command re-execution; native cron via cloud agent.
- **Maturity:** Shipped in Claude Code; cloud agents in beta.
- **Key difference:** Native harness primitives vs. toolkit/framework for designing loops.

---

### 8. **Nx Self-Healing CI**
- **GitHub:** [nrwl/nx](https://github.com/nrwl/nx)
- **What it is:** Built-in CI fixer for Nx monorepos—when CI runs fail (nx format:check, nx sync:check, nx conformance:check), AI agent analyzes failure, proposes fix, applies and re-runs within same pipeline, surfaces decision trace in PR comments.
- **Comparison to loop-engineering:** Autonomous loop for CI fixing with verification (test re-run = verification); loop-engineering is general-purpose loop patterns + budget/schedule control.
- **Distinctive primitive:** Failure-driven entry point (CI failure triggers agent); workspace-aware via project graph; built-in verifier (re-run after fix).
- **Maturity:** Shipped in Nx 19+. Auto-apply suggestions in recent versions.
- **Key difference:** Single-purpose agent loop (CI fixing) vs. general toolkit for designing loops.

---

### 9. **Dagger CI Self-Healing Pipelines**
- **Web:** [dagger.io/blog/automate-your-ci-fixes](https://dagger.io/blog/automate-your-ci-fixes-self-healing-pipelines-with-ai-agents/)
- **What it is:** AI agent system for Dagger pipelines that detects failures, generates patches, submits via normal review process, surfaces rationale diff of changes.
- **Comparison to loop-engineering:** Event-driven loop (failure triggers agent); loop-engineering is schedule-driven + event-driven. Dagger focuses on CI safety (human review before apply); loop-engineering includes maker/checker architectural patterns.
- **Distinctive primitive:** Patch + rationale output (explainability); normal code review gate (not autonomous apply by default).
- **Maturity:** Announced 2026, documentation-stage maturity.
- **Key difference:** CI-specific vs. general production loops.

---

## AUTONOMOUS BOT FRAMEWORKS — Specific Domain Focus (PR/Issue/Refactoring)

### 10. **Sweep AI**
- **GitHub:** [sweepai/sweep](https://github.com/sweepai/sweep)
- **What it is:** Autonomous junior developer bot—tag a GitHub issue with 'sweep' and the agent reads codebase, plans changes, writes code, submits PR with tests. Includes self-healing: bot runs test suite in sandbox, detects failures, attempts fixes before you see the PR.
- **Comparison to loop-engineering:** Bot-centric (runs on issue trigger, not scheduled); loop-engineering is loop-centric (schedule-driven with verifier). Sweep's self-healing is verification loop; loop-engineering frames it as maker/checker split + budget + 4-file state.
- **Distinctive primitive:** GitHub issue → PR pipeline; self-recovery via test sandbox; Python codebase analysis.
- **Maturity:** 7.7k ⭐, 465 forks, 10k+ commits, Python/Jupyter. Active. Transitioning toward JetBrains IDE plugin.
- **Key difference:** Single-purpose bot (issue→PR) vs. framework for designing loops.

---

### 11. **OpenHands** (All-Hands-AI)
- **GitHub:** [OpenHands/OpenHands](https://github.com/OpenHands/OpenHands)
- **What it is:** Self-hosted AI agent platform for development—agents can modify code, run commands, browse web, call APIs. Supports multiple agents (OpenHands, Claude Code, Codex, Gemini) via Agent-Client Protocol (ACP), workflow automation with Slack/GitHub/Linear integrations, scheduled or webhook-triggered execution.
- **Comparison to loop-engineering:** Broader scope—full developer agent platform. Covers scheduling + webhooks + multi-agent + workflow automation. Loop-engineering is narrower (how to design a single agent loop safely).
- **Distinctive primitive:** Multi-agent compatibility (ACP standard); self-hosted flexibility; distributed backend (multiple Agent Servers); bring-your-own-model.
- **Maturity:** GitHub org with multiple repos (OpenHands, software-agent-sdk, openhands-aci), active development.
- **Key difference:** Full platform vs. loop design framework.

---

### 12. **Continue.dev** (Agents & Cloud Agents)
- **GitHub:** [continuedev/continue](https://github.com/continuedev/continue)
- **What it is:** Open-source AI coding assistant (IDE extensions + CLI) with Cloud Agents for autonomous background work (refactoring, docs, security patching). Agents run asynchronously, event-driven, integrate with CI/CD (GitHub Actions, Sentry, Snyk, GitHub issues).
- **Comparison to loop-engineering:** Agent scheduling + CI/CD integration; loop-engineering is general framework. Continue targets IDE + CI-driven entry points; loop-engineering is schedule/event agnostic.
- **Distinctive primitive:** IDE extension + cloud agent split; multi-file refactoring with consistency; CI/CD integration out-of-box.
- **Maturity:** Active development, IDE plugin widely used.
- **Key difference:** IDE-centric + event-triggered vs. schedule-centric + pattern library.

---

### 13. **Aider** (with Architect Mode)
- **GitHub:** [paul-gauthier/aider](https://github.com/paul-gauthier/aider)
- **What it is:** Terminal AI coding agent with architect mode (two-model workflow: expensive planner + cheaper editor). Inner loop: LLM edits → lint/test → feedback on failure → retry (up to max_reflections). Lightweight, headless, format-based (not tool-call).
- **Comparison to loop-engineering:** Architect mode is maker/checker split (planner + implementer); reflection loop is verification. Loop-engineering frames these as architectural constraint + verifier; Aider is prompt pattern.
- **Distinctive primitive:** Two-model (architect/editor) cost optimization; text-format edits (not tools); inner reflection loop on test failure.
- **Maturity:** Widely used, active. Not designed for scheduling (user-driven outer loop).
- **Key difference:** Single-session inner loop vs. scheduled autonomous loops.

---

## MULTI-AGENT ORCHESTRATION FRAMEWORKS — General Agent Teams (Not Loop-Specific)

### 14. **CrewAI** (crewAIInc)
- **GitHub:** [crewaiinc/crewai](https://github.com/crewaiinc/crewai)
- **What it is:** Python framework for orchestrating role-based AI agent teams. Two primitives: Crews (autonomous agents with roles/goals, dynamic task delegation) and Flows (event-driven workflows with precise control, branching, state mgmt). Supports tools, memory, checkpointing, async execution, structured outputs.
- **Comparison to loop-engineering:** Broader—multi-agent orchestration vs. single-loop patterns. CrewAI is agent-centric; loop-engineering is loop-centric.
- **Distinctive primitive:** Dual Crews (autonomy) + Flows (precision) design; role-based team structure; dynamic inter-agent delegation.
- **Maturity:** Active, widely used for production multi-agent systems.
- **Key difference:** Horizontal coordination (team of agents) vs. vertical governance (loop safety + patterns).

---

### 15. **AutoGen** (Microsoft)
- **GitHub:** [microsoft/autogen](https://github.com/microsoft/autogen)
- **What it is:** Microsoft's open-source multi-agent framework using conversational, event-driven architecture. Agents, tools, and humans collaborate through structured dialogues. Supports custom agent types, tool integration, nested conversations.
- **Comparison to loop-engineering:** General multi-agent orchestration; loop-engineering is single-loop patterns + scheduling.
- **Distinctive primitive:** Conversational interface between agents; nested agent hierarchies; human-in-loop via conversation.
- **Maturity:** Research/production-used, active.
- **Key difference:** Conversation-driven agent coordination vs. scheduled autonomous loops.

---

### 16. **Marvin** (Prefect/Pydantic)
- **GitHub:** [PrefectHQ/marvin](https://github.com/PrefectHQ/marvin)
- **What it is:** Ambient intelligence library from Prefect (workflow orchestration platform). Marvin provides task-centric agent framework (discrete observable tasks, specialized agents per task, thread-based orchestration) + Prefect integration for durable execution (PrefectAgent auto-wraps Agent.run as flow, model requests as tasks).
- **Comparison to loop-engineering:** Orchestration layer (Prefect durable execution) + task-centric agent design; loop-engineering is loop pattern library + verification.
- **Distinctive primitive:** Task-centric abstraction (not agent-centric); Prefect integration for automatic durability; type-safe results bridge AI/software.
- **Maturity:** Prefect is established workflow platform; Marvin is newer library layer.
- **Key difference:** Task-driven orchestration vs. loop-driven autonomous patterns.

---

## FOUNDATIONAL AGENT TASK LOOPS — Early Patterns (Educational/Legacy)

### 17. **BabyAGI**
- **GitHub:** [yohei-nakajima/babyagi](https://github.com/yohei-nakajima/babyagi)
- **What it is:** Educational autonomous agent that manages a task queue: execute task → create new tasks based on result → reprioritize. Loop-based task management with LLM (GPT-4), vector DB (Pinecone/Weaviate/Chroma) for memory, LangChain for structure. ~140 lines of Python.
- **Comparison to loop-engineering:** Historical predecessor to loop engineering concept. BabyAGI is proof-of-concept task loop; loop-engineering is production framework with safety, patterns, and scheduling.
- **Distinctive primitive:** Task creation from outcomes; reprioritization; vector memory for semantic task lookup.
- **Maturity:** 2023 release, educational/sandbox status (not production-ready). Historical significance.
- **Key difference:** Minimal PoC vs. production framework with governance.

---

### 18. **AutoGPT**
- **GitHub:** [Significant-Gravitas/AutoGPT](https://github.com/Significant-Gravitas/AutoGPT)
- **What it is:** Early autonomous agent framework (2023) with goal decomposition, tool integration, memory. Launched as "AGI" response but evolved to practical agent toolkit. More feature-rich than BabyAGI; comparable complexity to modern frameworks.
- **Comparison to loop-engineering:** Concurrent with BabyAGI but more ambitious scope. Both are predecessors to loop engineering concept.
- **Distinctive primitive:** Goal decomposition tree; long-term memory + short-term context; plugin system for tools.
- **Maturity:** 2023 release, active but partially superseded by modern frameworks (CrewAI, AutoGen).
- **Key difference:** Feature-rich experimental framework vs. production loop patterns.

---

## SPECIALIZED/NICHE AGENTS

### 19. **Gitpod Ona** (formerly Gitpod Agent)
- **Web:** [gitpod.io/docs/ides/agent-ide](https://www.gitpod.io/docs/ides/agent-ide)
- **What it is:** Agent IDE built on Gitpod—AI agent can modify code in cloud dev environment with file tree, terminal, browser. Integrated with VS Code.
- **Comparison to loop-engineering:** Cloud-based agent execution environment; loop-engineering is loop design framework. Ona is where-to-run; loop-engineering is what-loop-to-design.
- **Distinctive primitive:** Cloud IDE environment + agent execution; live file tree + terminal integration.
- **Maturity:** Gitpod product, active.
- **Key difference:** Execution environment vs. loop design framework.

---

## ORCHESTRATION INFRASTRUCTURE (Broader Than Agents)

### 20. **Inngest** (Durable Execution for Functions)
- **Web:** [inngest.com](https://www.inngest.com/)
- **What it is:** Durable function orchestration platform (queuing, scheduling, retries, state). Functions-as-code with serverless execution. Not agent-specific but used for agent orchestration.
- **Comparison to loop-engineering:** Infrastructure layer (where loops run); loop-engineering is loop design layer.
- **Distinctive primitive:** Functions as primitives, not agents; serverless queueing; automatic retries/backoff.
- **Maturity:** Production SaaS, active.
- **Key difference:** General function orchestration vs. agent-specific loop patterns.

---

### 21. **Restate** (Durable Workflows)
- **Web:** [restate.dev](https://restate.dev/)
- **What it is:** Durable workflow platform (distributed state machine as code). Handles failures, retries, timeouts. Language-agnostic (Java, Python, TypeScript, Rust, Go, C#).
- **Comparison to loop-engineering:** Infrastructure for any durable workflow; loop-engineering is agent-loop-specific patterns.
- **Distinctive primitive:** Distributed state machine; implicit retries on crash; distributed Durable Execution with logging.
- **Maturity:** Production-ready, active.
- **Key difference:** General workflow infrastructure vs. agent-loop library.

---

## KNOWLEDGE & REFERENCE

### "Awesome" Lists & Catalogs

- **[awesome-harness-engineering](https://github.com/ai-boost/awesome-harness-engineering)** — Curated list for AI agent harness engineering: tools, patterns, evals, memory, MCP, permissions, observability, orchestration. Broader than loop-engineering but includes loop frameworks.
- **[Agentic Engineering Pattern Catalog](https://www.agentpatternscatalog.org/)** — Comprehensive pattern taxonomy including maker-checker, reflection loops, etc.

### Academic & Analysis

- **Zylos Research:** "[Agentic CI/CD: AI-Driven Delivery Pipelines](https://zylos.ai/research/2026-05-12-agentic-cicd-ai-driven-delivery-pipelines/)" — Analysis of agent-driven CI/CD (Nx Self-Healing CI, Dagger, etc.). Overlaps with loop-engineering domain.
- **Black Matter VC:** "[Loop Engineering: An Honest Verdict](https://blackmatter.vc/lab/loop-engineering-an-honest-verdict-from-someone-who-actually-runs-agent-loops/)" — Production experience with loop-engineering framework.

---

## SYNTHESIS: Where Loop-Engineering Fits in the Landscape

### Positioning

**Loop-engineering occupies a unique middle ground:**

1. **Lower layer than multi-agent orchestration** (CrewAI, AutoGen, Marvin) — focuses on a *single* autonomous agent loop, not team coordination.

2. **Higher layer than durable execution infrastructure** (Temporal, LangGraph, Inngest) — assumes reliable execution layer exists, adds agent-specific patterns (verification, maker/checker, cost budgeting, scheduled entry points).

3. **More production-hardened than early agent task loops** (BabyAGI, AutoGPT) — includes safety gates (verifier, budget, state anatomy), patterns library (7 production use cases), and deployment toolkit (loop-init, loop-audit, loop-cost, loop-context).

4. **Complementary to bot/domain frameworks** (Sweep, Aider, Nx Self-Healing, Continue) — while those optimize for specific tasks (PR generation, CI fixing, refactoring), loop-engineering provides the *scheduling + governance layer* that allows bots to be deployed autonomously.

### Closest Analogues (Same Space)

- **ralph-loop-agent** (Vercel Labs, 822 ⭐) — Only near-peer in "framework for production agent loops." Ralph is more LLM-centric (outer verification loop); loop-engineering is more systems-centric (4-file state machine, maker/checker split, budget circuit-breaker).

- **Temporal** (enterprise durable execution) — Provides foundation that loop-engineering assumes. Temporal handles *where* loops run; loop-engineering designs *how* they run safely.

### What Makes Loop-Engineering Distinctive

- **4-file anatomy** (LOOP.md, STATE.md, loop-budget.md, loop-run-log.md) as governance artifact, not just prompt pattern.
- **Maker/checker architectural constraint** (separate verifier, not just reflection prompt).
- **Cost/context circuit-breaker** (explicit budget guards, not just log warnings).
- **7 production patterns** as reference library (daily-triage, PR-babysitter, CI-sweeper, dependency-sweeper, changelog-drafter, post-merge-cleanup, issue-triage).
- **L1→L3 autonomy levels** framing (not one-size-fits-all).
- **npm CLI toolkit** for init, audit, cost tracking, context inspection (not just library).

### Verdict

Loop-engineering is **not unique**, but it **fills a distinct niche** that rivals like ralph-loop-agent also occupy. The landscape has:
- Multiple durable execution layers (Temporal, LangGraph, Inngest, Restate).
- Multiple multi-agent orchestrators (CrewAI, AutoGen, Marvin).
- Multiple domain-specific bots (Sweep, Aider, Continue, Nx Self-Healing).
- **Few frameworks explicitly for "design + deploy a single autonomous agent loop safely"** — ralph-loop-agent and loop-engineering are the clear contenders.

Ralph is experimental, more LLM-procedural; loop-engineering is more systems-oriented. They could be complementary (ralph's verification loop inside loop-engineering's maker/checker framework).

---

## References & Sources

### GitHub Repositories
- [vercel-labs/ralph-loop-agent](https://github.com/vercel-labs/ralph-loop-agent) — 822 ⭐
- [langchain-ai/langgraph](https://github.com/langchain-ai/langgraph) — 37.7k ⭐
- [sweepai/sweep](https://github.com/sweepai/sweep) — 7.7k ⭐
- [OpenHands/OpenHands](https://github.com/OpenHands/OpenHands) — ~7k ⭐
- [crewaiinc/crewai](https://github.com/crewaiinc/crewai) — ~14k ⭐
- [microsoft/autogen](https://github.com/microsoft/autogen) — ~24k ⭐
- [PrefectHQ/marvin](https://github.com/PrefectHQ/marvin)
- [continuedev/continue](https://github.com/continuedev/continue) — ~15k ⭐
- [paul-gauthier/aider](https://github.com/paul-gauthier/aider) — ~16k ⭐
- [yohei-nakajima/babyagi](https://github.com/yohei-nakajima/babyagi)
- [Significant-Gravitas/AutoGPT](https://github.com/Significant-Gravitas/AutoGPT) — ~166k ⭐

### Websites & Docs
- [loopengineering.run](https://loopengineering.run/)
- [temporal.io/solutions/ai](https://temporal.io/solutions/ai)
- [docs.langchain.com/langgraph](https://docs.langchain.com/oss/python/langgraph/overview)
- [openai.github.io/openai-agents-python](https://openai.github.io/openai-agents-python/)
- [code.claude.com/docs/agent-sdk](https://code.claude.com/docs/en/agent-sdk/overview)
- [nx.dev/docs/features/ci-features/self-healing-ci](https://nx.dev/docs/features/ci-features/self-healing-ci)

### Research & Analysis
- [Zylos: Agentic CI/CD Research](https://zylos.ai/research/2026-05-12-agentic-cicd-ai-driven-delivery-pipelines/)
- [Black Matter VC: Loop Engineering Verdict](https://blackmatter.vc/lab/loop-engineering-an-honest-verdict-from-someone-who-actually-runs-agent-loops/)
- [Agent Pattern Catalog: Maker-Checker Pattern](https://www.agentpatternscatalog.org/compositions/maker-checker/)

