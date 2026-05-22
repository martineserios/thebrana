---
title: Claude-Gemini Orchestrator-Worker Integration
status: idea
created: 2026-05-22
---

# Claude-Gemini Orchestrator-Worker Integration

> Brainstormed 2026-05-22. Status: idea.

## Problem

Claude's token pool is the sole compute source. Gemini subscription tokens go unused.
Parallel, bulk, and speed-sensitive tasks block Claude's context instead of running
alongside it.

## Solution

A three-layer stack — Bash for quick/scheduled calls, an MCP server as the typed
invocation contract, and a `/brana:gemini` skill as the full lifecycle orchestrator.
Claude plans and routes; Gemini executes as a stateless worker. Every result flows
back through Claude into the brana system.

## Architecture

```
LAYER A — Bash (today, always)
  agy -p "..." > /tmp/agy-output-{ts}.md
  Used for: quick tests, scheduled sweeps, spike validation

LAYER C — MCP server mcp__agy__delegate() (build first)
  Typed contract: task + context + output_format + background
  Handles: prompt file, timeout, error detection, job tracking, audit
  Used for: all skill-driven delegations

LAYER B — /brana:gemini skill (builds on C)
  ROUTE → ENRICH (ruflo) → DELEGATE (mcp__agy) → APPLY → EXTRACT → PERSIST
  Used for: explicit orchestrated delegations with full lifecycle
```

```
Claude (orchestrator)
  │
  ├── Quick/scheduled → Bash: agy -p "..."
  │
  └── Skill-driven   → mcp__agy__delegate()
                              │
                              └── agy (stateless worker)
                                    input:  /tmp/agy-prompt-{ts}.md
                                    output: /tmp/agy-output-{ts}.md
                                    never touches: system/ .claude/ tasks.json git
```

## Routing Heuristic

Three questions before delegating to agy:

1. **Atomic?** — completable in one `agy -p` call, no mid-task state
2. **brana-agnostic?** — no system/, no tasks.json, no hooks, no memory writes
3. **Speed/token benefit?** — repetitive, fast, or token-heavy for Claude

All three yes → agy. Any no → Claude.

## Task Type Taxonomy

### agy-eligible

| Task type | Why | Example |
|-----------|-----|---------|
| Research sweep | Atomic, read-only, Flash speed | "Summarize TrackingMore webhook docs — capabilities, rate limits, event types." |
| Boilerplate generation | Repetitive patterns, deterministic | "Generate Rust structs for this JSON schema: {schema}" |
| Doc first draft | Fast iteration, Claude polishes | "Write a first draft of this ADR from context: {context}" |
| Conversion/translation | Deterministic, speed matters | "Convert these TypeScript types to Python dataclasses" |
| Batch summarization | Parallel, repetitive | "Summarize each of these 10 items. One bullet per item." |
| Test scaffolding | Formulaic, Claude reviews | "Write unit test signatures (no impl) for these function specs" |
| Competitive/market analysis | Research-heavy, brana-agnostic | "Compare X and Y on speed, pricing, reliability. Return scorecard." |

### Claude-native (never delegate)

| Task type | Why |
|-----------|-----|
| brana `system/` changes | Hook enforcement required |
| Git operations | Bypasses branch-guard, main-guard |
| Task management (tasks.json) | Race condition risk (t-1507) |
| Architectural decisions | Full project context required |
| Multi-step stateful refactors | agy is stateless in headless mode |
| Memory/session writes | brana system boundary |

## Full System Integration Map

| Component | Integration | Rule |
|-----------|-------------|------|
| **Skills** | research, build, brainstorm, docs, fix, reconcile can delegate sub-tasks | close, ship, backlog, memory — never |
| **Agents** | scout overlaps for web research — route by brana-context need | all other agents Claude-only |
| **Hooks** | agy bypasses all CC hooks | mitigation: agy → /tmp/ only, Claude applies to repo |
| **Rules** | `delegation-routing.md` gets 3-question heuristic | `git-discipline.md`, `cwd-discipline.md` get agy constraints |
| **brana CLI** | Claude calls after reading agy output | agy never calls brana CLI |
| **tasks.json** | Never touched by agy | t-1507 must ship before any parallel sessions |
| **Scheduler** | brana-scheduler fires agy sweeps via shell script | Layer A only |
| **Scripts** | feed-ruflo, index-knowledge, sweep-feedback can call agy for enrichment | output always /tmp/ first |
| **ruflo/memory** | Claude mediates: extract from agy output → store via MCP tools | agy never writes to ruflo directly |
| **Plugin** | `/brana:gemini` registered in plugin.json when built | |

## /brana:gemini Skill Design

**Usage:**
```
/brana:gemini "task description"       # inline task
/brana:gemini t-XXXX                   # pull task from backlog
/brana:gemini --bg "task description"  # fire-and-continue (background)
```

**Steps:**

```
ROUTE → ENRICH → DELEGATE → APPLY → EXTRACT → PERSIST
```

- **ROUTE:** validate 3-question heuristic. Abort with reason if not eligible.
- **ENRICH:** query ruflo (knowledge, limit=3), construct `/tmp/agy-prompt-{ts}.md` with task + context + output format + constraints.
- **DELEGATE:** call `mcp__agy__delegate(task, context, output_format, background)`. Background mode uses CC `run_in_background` notification.
- **APPLY:** Claude reads `/tmp/agy-output-{ts}.md`, uses result for task. Never writes agy output directly to repo.
- **EXTRACT:** scope + novelty scoring (same rules as build/brainstorm). SMALL: auto-persist. MEDIUM: prompt. LARGE: prompt + challenger.
- **PERSIST:** `brana backlog set t-XXXX context "agy findings: {summary}"` + ruflo pattern store (`tags: ["source:agy-delegation"]`) + session log at close.

## MCP Server Design (mcp-agy)

Minimal Python server, ~80 lines:

```python
@tool
def delegate(task: str, context: str, output_format: str = "markdown",
             background: bool = False) -> dict:
    ts = datetime.now().strftime("%Y%m%d-%H%M%S")
    prompt_file = f"/tmp/agy-prompt-{ts}.md"
    output_file = f"/tmp/agy-output-{ts}.md"
    # write prompt, call agy -p, validate output contract
    # return {output, output_file, status} or {job_id, status: "running"}

@tool
def status(job_id: str) -> dict:
    # check output file existence + content validity
```

The server hardcodes `/tmp/` output — callers cannot override. Validates output contract
before returning. Structured error on timeout or malformed output.

## Risks and Mitigations

| Risk | Mitigation |
|------|-----------|
| agy bypasses all brana hooks | Invariant: agy output → /tmp/ only. Claude applies to repo. |
| tasks.json race (t-1507 unresolved) | agy never touches tasks.json. Claude does all brana writes. |
| Bad agy output applied without review | MCP server validates output contract. APPLY step is always Claude. |
| extract/persist skipped under pressure | Mandatory steps in skill — not optional. |
| Prompt injection from raw user content | Claude constructs all prompts. No raw user string interpolation. |
| agy writes directly to repo paths | MCP server hardcodes /tmp/ output — callers can't override. |

## Research Findings

- `agy` installed at `~/.local/bin/agy` v1.0.1. `agy -p "PROMPT"` works today, returns
  stdout, exit 0.
- `--print-timeout` defaults to 5 minutes. No session ID surfaced in headless mode —
  tasks must be atomic (no mid-task resume).
- Bash `run_in_background` enables true parallel execution — CC notifies on completion.
- Antigravity = Gemini CLI replacement (announced Google I/O 2026-05-19). Powered by
  Gemini 3.5 Flash at 289 tokens/sec. Closed-source.
- Existing `docs/ideas/agent-interaction-architecture.md` established Planner→Generator
  pattern with Claude Agent SDK. This extends that: Gemini replaces the SDK-based generator
  for brana-agnostic tasks.

## Build Order

```
1. Spike          — validate agy output quality on 3 task types (Bash, ~4h)
2. t-1507         — ship atomic tasks.json write (unblock parallel safety)
3. mcp-agy server — Layer C, typed contract, error handling, audit (~1 day)
4. /brana:gemini  — Layer B skill, full lifecycle on top of MCP (~1 day)
5. Rules update   — delegation-routing.md + git-discipline.md + cwd-discipline.md
6. Scheduler hook — agy sweep template for overnight runs
```

## Engineering Disciplines

- **DDD:** ADR — "agy invocation contract and routing criteria." Decisions: Layer A vs C
  per context, routing heuristic, output file convention, /tmp/ invariant.
- **TDD:** Tests for MCP server (delegate + status + error cases), skill ROUTE check,
  PERSIST step.
- **SDD:** `docs/architecture/features/claude-gemini-orchestration.md` + update
  `docs/ideas/agent-interaction-architecture.md`.
- **Docs:** Tech doc only (internal system feature). Update `delegation-routing.md` rule.

## Next Steps

1. Run spike: test `agy -p` on 3 task types (research, boilerplate, doc draft). Measure output quality.
2. If spike passes: build mcp-agy server via `/brana:mcp-builder`.
3. Build `/brana:gemini` skill using MCP server.
4. Update rules: `delegation-routing.md`, `git-discipline.md`, `cwd-discipline.md`.
5. Add agy sweep template to `system/scheduler/templates/`.

## Related

- `docs/ideas/agent-interaction-architecture.md` — Planner→Generator→Evaluator pattern
- `system/rules/delegation-routing.md` — routing criteria (update target)
- t-1507 — atomic tasks.json write (prerequisite for parallel safety)
