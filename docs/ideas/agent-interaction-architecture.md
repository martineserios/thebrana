# Agent Interaction Architecture

> Brainstormed 2026-03-26. Status: spike approved.

## Problem

Brana has 11 agents but no agent-to-agent communication. Each agent is a solo actor
that returns results to the main context. The Anthropic harness design article shows
that multi-agent workflows (Planner -> Generator -> Evaluator with feedback loops)
produce substantially higher quality output than single-agent approaches.

Key finding: **generators cannot reliably self-evaluate** (self-evaluation bias).
Separating generation from evaluation is more tractable than making generators
self-critical.

## Proposed Solution

**Spike: build a minimal evaluator loop using the Claude Agent SDK.**

Architecture: Planner (CC-native) -> Generator (CC-native) -> Evaluator (SDK with
session resume + custom spec-check tool). The evaluator runs as a Python process
that can iterate 3-5 rounds against the generator's output.

### Why SDK for the evaluator (not CC-native)

| Feature | CC-native | Agent SDK |
|---------|-----------|-----------|
| Session continuity between rounds | No (fresh context each spawn) | Yes (`resume=session_id`) |
| File checkpointing (revert failed attempts) | No (manual `git stash`) | Yes (built-in) |
| Custom verification tools | No (external MCP or shell) | Yes (`@tool` decorator, in-process) |
| Programmatic hooks | Shell scripts only | Python async callbacks |
| Per-query tool restrictions | Advisory (disallowedTools) | Enforced (`allowed_tools`) |

### What CC-native keeps doing better

- Interactive planning (user <-> Claude conversation, AskUserQuestion)
- Task tracking and skill flows
- CLAUDE.md / rules / hooks ecosystem
- Daily interactive development

## Research Findings

### Agent SDK maturity (2026-03-26)

- **Version:** 0.1.x (pre-1.0). Python + TypeScript. 5.8k stars, 394 commits.
- **Subagents:** Same Agent tool mechanism as CC. Defines `AgentDefinition(description, prompt, tools, model)`.
- **Sessions:** Resume by ID, fork to branch, `ClaudeSDKClient` for multi-turn.
- **Subagent transcripts:** Persist independently of parent compaction. Resumable by agent ID.
- **Custom tools:** `@tool` decorator + `create_sdk_mcp_server()` — in-process, no subprocess.
- **Hooks:** Python async for PreToolUse, PostToolUse, Stop, SessionStart, SessionEnd.
- **No nested subagents** — subagents cannot spawn their own subagents.
- **Session files are local** — can't resume across machines without copying `.jsonl` files.

### Anthropic harness design article findings

- **Cost anatomy (DAW build):** Planner $0.46 (4.7min), Build $113/3.3hr, QA $10.39/3 rounds.
  QA is 8.3% of cost but prevents $36-71 wasted iterations per round.
- **Self-evaluation bias:** Even separate evaluators "talk themselves into approving" unless
  prompt is tuned from log analysis. Hard thresholds + feedback loop required.
- **Sprint removal in v2:** Opus 4.6 handles longer coherent sequences. Decomposition may be
  over-engineering for medium builds.
- **Iteration dynamics:** 5-15 iterations, non-linear. Generator must choose refine vs pivot.
  Best output sometimes mid-sequence.
- **File-based communication:** Agents write/read files. Simpler, debuggable, crash-resilient.

### Brana's current agent state

- 11 agents, all read-only (Write/Edit disallowed).
- No agent-to-agent communication — all flows through main context.
- Two spawn patterns: hook-triggered auto-delegation, skill-based explicit spawning.
- Compose-then-write pattern for code tasks (agents write to `/tmp/`, main context applies).
- Challenger has calibrated thresholds (CALIBRATION.md) but no feedback loop from outcomes.

## Risks and Mitigations

| Risk | Mitigation |
|------|-----------|
| SDK v0.1.x breaking changes | Spike isolates exposure. Thin wrapper abstracts SDK calls. |
| Python runtime dependency | Only evaluator uses SDK. CC-native for everything else. |
| Session resume reliability | Spike validates this before any architecture commitment. |
| Evaluator "talks itself into approving" | Hard pass/fail thresholds per criterion. Log-based calibration. |
| Cost explosion from iteration loops | Cap at 5 rounds. Log cost per round. Kill switch. |

## Spike Scope

**Goal:** Validate that SDK session resume + custom tools produce a working
evaluator loop that catches bugs a single-agent build misses.

**Deliverables:**
1. Python script: `system/scripts/evaluator-spike.py`
2. Custom `@tool` for spec compliance checking
3. Run against a real `/brana:build` output (pick a recent M-effort task)
4. Compare: bugs found by evaluator vs bugs found by single-agent review
5. Log: cost per round, time per round, session resume reliability

**Not in scope:** Production integration, CC-native changes, agent protocol design.

## Next Steps

1. t-649: Agent SDK spike (this idea -> implementation)
2. If spike validates: design agent interaction protocol (roles, contracts, communication)
3. If spike fails: fall back to file-contract pattern (no SDK dependency)

## Sources

- [Anthropic: Harness design for long-running apps](https://www.anthropic.com/engineering/harness-design-long-running-apps)
- [Agent SDK overview](https://platform.claude.com/docs/en/agent-sdk/overview)
- [Agent SDK subagents](https://platform.claude.com/docs/en/agent-sdk/subagents)
- [Agent SDK sessions](https://platform.claude.com/docs/en/agent-sdk/sessions)
- [Agent SDK Python repo](https://github.com/anthropics/claude-agent-sdk-python) (5.8k stars, v0.1.x)
