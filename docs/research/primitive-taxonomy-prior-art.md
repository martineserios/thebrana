# Primitive Taxonomy Research: Agentic Framework Prior Art

**Research Date:** 2026-07-20  
**Scope:** How major agentic frameworks define and separate their core primitives (skills, workflows, loops, goals, agents). Focus: boundary-drawing discriminators.

---

## Executive Summary

All major frameworks converge on **three recurring discriminators** for deciding primitive type:

1. **Control Locus** — Who decides what happens next: developer (workflow) or model (agent/loop)?
2. **State Scope** — Single shared context (tool/skill) or isolated context window (subagent)?
3. **Invocation Mechanism** — Declarative instructions (skill) vs. callable function (tool) vs. autonomous loop (agent)?

The **sharpest discriminator quote** (canonical): Anthropic's "Building Effective Agents"—
> *"Workflows are systems where LLMs and tools are orchestrated through predefined code paths. Agents are systems where models dynamically direct their own processes and tool usage, maintaining control over how they accomplish tasks."*

---

## Framework-by-Framework Analysis

### 1. Anthropic's "Building Effective Agents" (CANONICAL REFERENCE)

**Status:** Official, December 2024 engineering post + expanded eBook. Most-cited taxonomy in agent-pattern literature.

**Core Primitives:**
- **Workflows** — 6 orchestrated patterns: Prompt Chaining, Routing, Parallelization, Orchestrator-Workers, Evaluator-Optimizer, Agents
- **Agents** — Autonomous systems with three capabilities: retrieval (self-directed search), tools (self-directed invocation), memory (self-directed state)
- **Tools/Capabilities** — Functions agents can invoke
- **LLM** — Base unit extended with capabilities

**Discriminator (Workflow vs. Agent):**
> *"Workflows are systems where LLMs and tools are orchestrated through predefined code paths. Agents are systems where models dynamically direct their own processes and tool usage, maintaining control over how they accomplish tasks."*

**Key Principle:**
> *"Success in the LLM space isn't about building the most sophisticated system. It's about building the **right** system for your needs."*  
Corollary: Add complexity only when it demonstrably improves outcomes. Start with workflows (simplest), escalate to agents only when model autonomy is necessary.

**On "Goal":** Not a distinct primitive. Folded into agent prompt/instructions or workflow routing logic.

---

### 2. Claude Agent SDK (Anthropic)

**Status:** Official production SDK for Claude Code + programmable agent access. Includes built-in tool loop automation.

**Core Primitives:**
- **Agents** — Entry point; autonomous loop orchestrator (handles tool invocation, error recovery, session management)
- **Subagents** — Specialized agents with isolated context, tool restrictions, custom instructions. Used for delegation.
- **Tools** — Executable capabilities (Read, Write, Edit, Bash, WebSearch, etc.)
- **Skills** — Capability packages (Markdown files with instructions + tools). Not executable; declarative instructions in system prompt.
- **Hooks** — Lifecycle callbacks (PreToolUse, PostToolUse, SessionStart, SessionEnd, etc.)

**Decision Heuristic (Official):**
> *"A useful heuristic: if you're writing instructions, it's a skill. If you're writing a function the model should call, it's a tool (or an MCP server). If the work needs its own context window, its own system prompt, or its own tool restrictions, it's a subagent."*

**Discriminators:**
- **Skill vs. Tool:** Knowledge (instructions) vs. action (callable function)
- **Tool vs. Subagent:** Shared context/permissions vs. isolated context/permissions
- **Subagent vs. Loop:** Needs own loop/context vs. participates in main agent loop

---

### 3. OpenAI Agents SDK

**Status:** Official; production agent orchestration library.

**Core Primitives:**
- **Agents** — LLM + system prompt + tools + optional runtime behaviors (handoffs, guardrails, structured outputs)
- **Tools** — Functions the agent invokes (Pydantic-powered schema generation + validation)
- **Handoffs** — Peer-to-peer agent delegation. Delegated agent receives full history and takes over conversation.
- **Guardrails** — Input/output validation
- **Runner** — Execution orchestrator (turns, tool execution, guardrails, handoffs, sessions)

**Multi-Agent Patterns:**
- **Manager Pattern** — Central agent invokes specialized sub-agents as tools (centralized control)
- **Handoff Pattern** — Agents delegate to peers that assume control (peer autonomy within frame)

**Discriminators:**
- **Tool vs. Handoff:** Agent invokes tool (retains control) vs. agent hands off (peer assumes control)
- **Manager vs. Handoff:** Hierarchical (control remains at top) vs. lateral (control transfers temporarily)

---

### 4. Google ADK (Agent Development Kit)

**Status:** Official; open-source Python toolkit for multi-agent systems.

**Core Primitives:**
- **Agents** (two forms):
  - `LlmAgent` — Uses language model for reasoning and decision-making
  - Workflow Agents — Deterministic controllers: `SequentialAgent`, `ParallelAgent`, `LoopAgent`
- **Tools** — External capabilities (APIs, search, code execution, other services)
- **Callbacks** — Custom code snippets for logging, validation, or behavior adjustment (lifecycle hooks)
- **Session** — Single conversation context (history)
- **State** — Working memory within a session
- **Memory** — Recall across multiple sessions (long-term context)
- **Workflows** — Hierarchical coordination of multiple agents (task delegation, complex orchestration)

**Discriminators:**
- **LlmAgent vs. Workflow Agent** — Reasoning-driven (model decides) vs. deterministic routing (developer decides)
- **Tool vs. Workflow** — Single capability vs. orchestrated multi-agent composition
- **Session vs. Memory** — Conversation-scoped state vs. cross-conversation recall

---

### 5. LangGraph (LangChain)

**Status:** Official; "very low-level" graph-based agent orchestration library.

**Core Primitives:**
- **StateGraph** — Directed graph container for workflow state and edges
- **Nodes** — Python functions that process state (LLM calls, tool invocations, logic)
- **Edges** — Transitions between nodes, either fixed (`add_edge`) or conditional (`add_conditional_edges`)
- **State** — Shared data structure passed between nodes

**Philosophy (Implied from Architecture):**
Developer-driven routing. The LLM might influence which edge is taken (via node output), but edges are predefined by the developer. The graph structure encodes control flow, not the model.

**Discriminator (Workflow vs. Autonomy):**
LangGraph represents workflows, not true agent autonomy. Nodes are developer-defined; edges are developer-routed. The model can't create new execution paths or redefine the graph at runtime.

**On Goals:** Not explicitly modeled. Goals are implicit in node logic and edge conditions.

---

### 6. badlogic/Pi (Agent Framework)

**Status:** Open-source; extensible coding agent. "Primitives, not features" philosophy.

**Core Primitives:**
- **Skills** — Capability packages (Markdown instruction blocks + tools). Progressive disclosure: only name/description in prompt until agent reads full SKILL.md. Saves context tokens.
- **Tools** — Underlying executable capabilities
- **Extensions** — TypeScript modules that customize agent behavior (inject messages, filter history, implement RAG, build memory)
- **Agent Loop** — Customizable via extensions (not fixed)
- **Packages** — Bundles of extensions, skills, prompts, themes (npm or git installable)

**Extensibility Philosophy:**
> *"Aggressively extensible so it doesn't have to dictate your workflow. Features other tools bake in (sub-agents, plan mode, permission gates) become optional, installable components."*

**Discriminators:**
- **Skill vs. Tool:** Capability package with instructions (name/description only initially, full content fetched on-demand) vs. raw executable function
- **Extension vs. Tool:** Lifecycle customization (filters, injections, RAG) vs. agent-invoked action
- **Package vs. Individual Skill/Tool:** Composable bundled set vs. single primitive

---

## Cross-Framework Discriminator Synthesis

### Three Recurring Discriminators (Consensus)

| Discriminator | Definition | Examples |
|---|---|---|
| **1. Control Locus** | Who decides what happens next? | Developer (workflow edge conditions) vs. Model (agent autonomous routing) |
| **2. State Scope** | Shared context or isolated? | Same context window (tool/skill) vs. Isolated context (subagent/specialized agent) |
| **3. Invocation Mechanism** | How is it invoked? | Declarative/passive (skill in system prompt) vs. Callable function (tool) vs. Autonomous entry point (agent/loop) |

### Secondary Discriminators (Frequent)

- **Complexity Gate:** Is this the simplest solution, or is added complexity justified?
- **Persistence:** Single turn (tool) vs. multi-turn with memory (agent/loop)
- **Routing:** Fixed edges (workflow) vs. conditional edges (LLM-informed but developer-defined) vs. fully autonomous (agent)

---

## The Anthropic "Building Effective Agents" Worldview

Anthropic's taxonomy is the sharpest and most prescriptive. It prioritizes **simplicity as a starting point**:

1. **Start with Workflows** (deterministic, orchestrated, predictable, cheap):
   - Prompt Chaining
   - Routing (classification → specialized handler)
   - Parallelization (fan-out for diversity/robustness)
   - Orchestrator-Workers (central model tasks → specialized workers)
   - Evaluator-Optimizer (generate → evaluate → refine loop)

2. **Escalate to Agents Only When Necessary** (autonomous, complex, expensive):
   - Model decides what to do next
   - Model decides which tools to invoke
   - Model maintains working memory
   - Essential for: open-ended exploration, dynamic adaptation, long horizons

3. **Core Capability Categories (for any primitive)**:
   - Retrieval: Model writes search queries, reads results
   - Tools: Model picks and runs tools, reads results
   - Memory: Model decides what to retain across turns

**Implication for Brana:** Start every task with a workflow (prompt chain or routing), and only spawn an agent loop if the task has unpredictable decision trees or requires persistent reasoning across many turns.

---

## Sharpest Quotes (Ranked by Discriminative Power)

### Tier 1 (Canonical)

**Anthropic "Building Effective Agents":**
> *"Workflows are systems where LLMs and tools are orchestrated through predefined code paths. Agents are systems where models dynamically direct their own processes and tool usage, maintaining control over how they accomplish tasks."*

### Tier 2 (Operational)

**Claude Agent SDK:**
> *"If you're writing instructions, it's a skill. If you're writing a function the model should call, it's a tool. If the work needs its own context window, its own system prompt, or its own tool restrictions, it's a subagent."*

**Anthropic (Simplicity Principle):**
> *"Success in the LLM space isn't about building the most sophisticated system. It's about building the right system for your needs."*

### Tier 3 (Architectural)

**OpenAI Agents SDK (on Handoffs):**
> *"When a handoff occurs, it's as though the new agent takes over the conversation, and gets to see the entire previous conversation history."*

**Pi Framework (on Extensibility):**
> *"Aggressively extensible so it doesn't have to dictate your workflow."*

---

## Implications for Brana's Routing Heuristic

**Proposed Rule Set (Derived from Prior Art):**

1. **If the task has a predetermined control flow** (all branches known upfront) → **Workflow**
   - Discriminator: Developer can enumerate all possible paths before execution
   - Example: "classify input then apply specialized handler"

2. **If the task needs a reusable capability without its own reasoning loop** → **Tool or Skill**
   - Discriminator: Model invokes it but doesn't own its control flow
   - Tool: Executable function (if callable)
   - Skill: Instruction block (if knowledge-only)

3. **If the task needs isolated reasoning with separate context/permissions** → **Subagent**
   - Discriminator: Work needs `own context window, own system prompt, own tool restrictions`
   - Example: Delegate code review to a specialized reviewer with read-only tools

4. **If the task has unpredictable decision trees requiring persistent autonomous reasoning** → **Agent/Loop**
   - Discriminator: Model must decide what to do *and* how to do it, across multiple turns
   - Example: Open-ended research, exploration, or adaptive problem-solving

5. **Default to simplest primitive**; escalate only when necessary.

---

## Sources

- [Anthropic's Building Effective Agents](https://www.anthropic.com/research/building-effective-agents)
- [Mervin Praison's "When Not to Build AI Agents"](https://mer.vin/2026/05/when-not-to-build-ai-agents-anthropics-workflow-vs-agent-playbook/)
- [Claude Agent SDK Documentation](https://code.claude.com/docs/en/agent-sdk/overview)
- [OpenAI Agents SDK Documentation](https://openai.github.io/openai-agents-python/)
- [Google ADK (Agent Development Kit) Documentation](https://adk.dev/get-started/about/)
- [LangGraph Documentation](https://docs.langchain.com/oss/python/langgraph/overview)
- [badlogic/Pi Framework (GitHub)](https://github.com/badlogic/pi-mono)

---

## Research Notes

- **Most Prescriptive:** Anthropic (clear simplicity-first principle, six patterns)
- **Most Modular:** Pi (extensions + packages allow workflow customization)
- **Most Control-Oriented:** OpenAI (explicit manager vs. handoff patterns)
- **Most Low-Level:** LangGraph (nodes/edges; developer builds control flow)
- **Most Comprehensive:** Google ADK (LLM agents + workflow agents + sessions + memory)
- **Most Production-Ready:** Claude Agent SDK (integrated with Claude Code, built-in tool loop, hooks)

**Consensus Observation:** All frameworks agree that **control locus** (who decides what happens next) is the primary discriminator. Secondary discriminators are state scope and invocation mechanism.
