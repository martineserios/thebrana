# Multi-Agent Orchestration — Investigation Report

**Task:** t-525 | **Date:** 2026-03-16 | **Strategy:** investigation
**Branch:** research/t-525-multi-agent-orchestration

## Executive Summary

Investigated 11 external sources + brana's current architecture to answer: should brana adopt an existing multi-agent orchestrator, build its own, or evolve incrementally?

**Recommendation: Incremental evolution leveraging Claude Code's native capabilities as the coordination backbone, with brana providing the intelligence layer (routing, security gates, task decomposition).** Don't build a daemon. Don't adopt a framework. Extend what CC already ships.

---

## 1. Landscape: What Exists

### Production-Grade Orchestrators

| Tool | Architecture | Scale Tested | Security | Maturity |
|------|-------------|-------------|----------|----------|
| **Composio** | Event-driven YAML reactions, 8 plugin slots, worktree isolation | 30 agents, 84.6% CI self-correction, 722 commits | Worktree + permission modes (reportedly broken in CC spawned agents) | 4.5K stars, 10 contributors, MIT, v0.2.0 |
| **delegate** | Turn-based async dispatch, persistent subprocess registry, SQLite state | Small teams (3-5 agents) | 6-layer defense (strongest model reviewed) | 107 stars, solo dev, Alpha v0.2.9 |
| **TurboFlow 4.0** | Built on Ruflo v3.5, Beads memory, GitNexus | Unknown | Unknown | Announcement only — no public repo |

### Lightweight Patterns

| Approach | Author | Architecture | Cost |
|----------|--------|-------------|------|
| **Multi-Swarm** | itsgaldoron | Swarm-lead + 4 specialists per worktree | 17 Opus agents = high token cost. Community skeptical |
| **Claudex Mode** | Richard Rizk | Generate (Claude) → Validate (Codex) via Blackbox CLI | Moderate. Separation of concerns prevents self-hallucination |
| **Bash+tmux+Docker** | Michael Tomcal | Minimal: loop + done-signal + Docker sandbox | Cheapest. Anti-orchestrator thesis: "harnesses absorb orchestration" |
| **Opus+Codex+TaskmasterAI** | Anurag Bhagsain | Cross-model validation + worktree parallelism | $300/mo ($100 Claude + $200 Codex) |
| **Agent-Deck + GSD** | Alan Helouani | Terminal + web monitoring, parallel 30min+ tasks | Focus on human bottleneck: spec quality > agent speed |

### Native Claude Code Capabilities

| Capability | Status | What It Does |
|-----------|--------|-------------|
| **Subagents** | Shipped | Spawn specialized agents with tool restrictions, model selection, worktree isolation |
| **Agent Teams** | Experimental (`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`) | Multiple CC sessions with shared task list, inter-agent messaging, task claiming |
| **Agent SDK** | Shipped | Subprocess-based programmatic CC access (Python/TypeScript) |
| **Worktree isolation** | Shipped | `isolation: worktree` on subagents for parallel file editing |

**Key limitations:** Subagents can't spawn subagents (no nesting). Subagents can't message each other (hub-and-spoke only). Agent Teams fixes both but is experimental.

---

## 2. Brana's Current State

### What Works Well (preserve)

- **Read-only agents** (11 agents, all analysis-only. Main context owns writes after approval)
- **Tool allowlist isolation** (per-agent `disallowedTools`. No "super-agent")
- **Context forking** (challenger/debrief get fresh context — prevents self-reinforcement)
- **Spec-driven orchestration** (agents specified in .md, tracked in spec-graph.json)
- **Hub-and-spoke coordination** (simple, debuggable, no infinite recursion risk)

### Critical Gaps (fix)

| Gap | Severity |
|-----|----------|
| No autonomous trigger system | High |
| No agent-to-agent messaging | High |
| No failure recovery beyond timeouts | Medium |
| No dynamic routing | Medium |
| No agent-scoped memory | Medium |
| No real-time health monitoring | Medium |

---

## 3. Security Analysis

### The Permission Inheritance Problem (imaxxs)

> "Sub-agents inherit parent permissions indiscriminately."

| System | Approach | Strength |
|--------|----------|----------|
| **delegate** | 6-layer: write-path, tool restrict, OS sandbox, network allowlist, in-process MCP, daemon-gated git | Best reviewed |
| **Composio** | Worktree isolation + permission modes | Reportedly broken (#29110) |
| **CC subagents** | Tool allowlist + permission modes | Solid but no network isolation |
| **CC Agent Teams** | Separate session per teammate | Strongest native isolation |
| **brana** | Read-only agents + tool allowlist + main context write gate | Effective, inherently safe |

**Brana's advantage:** Read-only agents + write gate is the strongest security boundary reviewed. Don't weaken this.

---

## 4. Stability & Robustness

| Failure | delegate | Composio | CC Native | brana |
|---------|----------|----------|-----------|-------|
| Agent hangs | Turn timeout + escalation | 17-state machine | Configurable timeout | Timeout only |
| Merge conflict | All-or-nothing rebase + dual locking | Auto-retry YAML | Worktree prevents | Manual |
| Partial completion | Manager assigned | Retry 2x, escalate 30m | Error returned | Task stays failed |

**Key takeaway:** delegate's merge invariants are gold standard. Brana needs: escalation on timeout, retry classification, partial result handling.

---

## 5. Performance & ROI

| Scenario | Single Agent | Multi-Agent | Multiplier |
|----------|-------------|-------------|-----------|
| Linear code task | 1x | 1x (overhead wasted) | 0.8x (worse) |
| 5 independent files | 1x sequential | 5x parallel | 3-4x |
| Research + build + review | 1x sequential | 3x parallel pipelines | 2-3x |
| Cross-model validation | N/A | Generate → Validate | Quality++ |

---

## 6. Decision: Build vs Adopt vs Evolve

| Option | Risk |
|--------|------|
| **Adopt Composio** | High — permission model broken, 40K LOC TypeScript dependency |
| **Adopt delegate** | High — solo dev, Alpha, bus factor 1 |
| **Build custom daemon** | High — months of work, CC absorbs this quarterly |
| **Evolve incrementally** | Low — uses CC native capabilities, minimal code, adapts as CC matures |

**Chosen: Evolve incrementally.**

---

## 7. Patterns to Steal

| Pattern | Source | Apply To |
|---------|--------|----------|
| Generate → Validate separation | Rizk (Claudex) | Post-implementation validation agent |
| Event-driven reactions (YAML) | Composio | Extend hook system to agent spawning triggers |
| 6-layer security model | delegate | Add network allowlist + directory scoping |
| Turn-based dispatch with batching | delegate | Batch messages per agent turn |
| Reflection turns (5% of time) | delegate | "Are you still on track?" checks |
| Requirements quality > agent speed | Helouani | Validate specs before parallelizing |
| Anti-orchestrator minimalism | Tomcal | Don't over-engineer; CC evolves quarterly |

---

## 8. Implementation: Mission Control

See `docs/ideas/mission-control.md` for the full plan (post-challenge).

**Phases:**
- 0.5: `brana run` (print command) — S effort
- 1: `brana run --spawn` (PID tracking) — M
- 1.5: `brana run --tmux` (optional visual) — S
- 2: `brana agents` (live PID checks) — S
- 2.5: `brana agents kill` (graceful stop) — S
- 3: `brana queue` (auto-suggest + batch) — M

Future (evaluate separately): `brana cost`, `brana monitor` (Ratatui), `brana serve` (Axum).

---

## 9. Observability

### Recommended Stack

```
Hook Events → JSONL append → SQLite aggregation → Dashboard (CLI or TUI or web)
```

| Tool | License | Claude Support | Best For |
|------|---------|----------------|----------|
| Langfuse | MIT | SDK integration | Prompt management + eval |
| Arize Phoenix | Apache 2.0 | Out-of-box | Agent tracing |
| claude_telemetry | Open-source | Drop-in wrapper | OTel to Logfire/Sentry/Datadog |
| Laminar | Rust proxy | Transparent | No code changes |

### Key Metrics

Per-agent: tokens, cost, latency, error count, context %
Per-task: time to complete, retry count, agent assignments
System: total cost, active agents, failure rate

**Brana already has:** Session JSONL, hook event logging. **Gap:** No aggregation, no cost attribution, no real-time dashboard.

---

## 10. UI & Visualization

| Approach | Scale | Best For |
|----------|-------|----------|
| tmux panes | 5-8 agents | Dev/personal |
| Terminal TUI (Ratatui) | 10-20 agents | Ops, SSH |
| Web (Axum + HTMX) | 20-100+ | Distributed teams |
| CC Agent Teams native | 3-5 | In-process |

**Strategy:** CLI-first. TUI only if CLI snapshots insufficient. Web only if TUI insufficient.

---

## 11. Sources

1. [delegate](https://github.com/nikhilgarg28/delegate) — Nikhil Garg
2. [Composio agent-orchestrator](https://github.com/ComposioHQ/agent-orchestrator) — ComposioHQ
3. [Multi-Swarm](https://www.linkedin.com/posts/itsgaldoron_claudecode-ai-agentteams-share-7436761195719737344-JaiT) — Gal Doron
4. [TurboFlow 4.0](https://www.linkedin.com/posts/marcuspatman_after-a-long-wait-i-am-happy-to-announce-share-7436831084849483777-4AAE) — Marcus Patman
5. [LangChain Deep Agents](https://www.linkedin.com/posts/paoloperrone_langchain-just-open-sourced-their-answer-share-7436959827831967744-5tCs) — Paolo Perrone
6. [Multi-Agent Workflow](https://www.linkedin.com/posts/anurag-bhagsain_my-coding-workflow-with-ai-agents-total-share-7428668544512499712-cpLp) — Anurag Bhagsain
7. [Orchestration CLI](https://www.linkedin.com/posts/michael-a-tomcal-2186486a_i-built-a-custom-orchestration-cli-for-ai-share-7432079783460745217-qN7W) — Michael Tomcal
8. [Claude+Codex](https://www.linkedin.com/posts/richard-rizk-a09a70213_we-just-made-claude-code-and-codex-work-together-ugcPost-7432103995143311360-4JeU) — Richard Rizk
9. [Multi-Agent Architecture](https://www.linkedin.com/posts/alan-helouani_aiengineering-agenticai-multiagentsystems-ugcPost-7427344045565210624-yaHC) — Alan Helouani
10. [Agent Security Gaps](https://www.linkedin.com/posts/imaxxs_agenticai-aiagents-agentsecurity-share-7437155322999369728-etzy) — Mahendra Kutare
11. [Claude Code Subagents](https://code.claude.com/docs/en/sub-agents) — Anthropic
12. [Claude Code Agent Teams](https://code.claude.com/docs/en/agent-teams) — Anthropic
13. [Claude Agent SDK](https://platform.claude.com/docs/en/agent-sdk/overview) — Anthropic
