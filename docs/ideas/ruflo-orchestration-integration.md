# Ruflo Orchestration Integration Map

> Brainstormed 2026-05-30. Status: idea.
> Extends: [ruflo-v36-integration.md](ruflo-v36-integration.md) Track C · [ruflo-native-integration.md](ruflo-native-integration.md)
> ADR foundation: [ADR-040](../architecture/decisions/ADR-040-compute-hierarchy-claude-ruflo-gemini.md)

## Problem

Ruflo exposes ~95 orchestration tools but in practice **none are firing**. Two compounding
causes: (1) procedures call deferred tool schemas without loading them first — every ruflo
MCP call throws `InputValidationError` because no `ToolSearch` preamble runs, (2) the
systematic tool-group map (which to use, how, with what fallback) was never written.
The architecture is settled (ADR-040). The plumbing and the map are the gap.

## Root Cause

All `mcp__ruflo__*` tools are in the **deferred tools list** — schemas are not loaded at
session start. A procedure that says `mcp__ruflo__swarm_init(...)` triggers an
`InputValidationError` unless a `ToolSearch` call precedes it. Claude falls back silently.
The fix is a per-procedure `<!-- ruflo preamble -->` block that loads exactly the schemas
the procedure needs.

## Architecture Constraints (ADR-040 — locked)

1. Claude is the only system writer. Git, tasks.json, hooks, ruflo stores → Claude only.
2. Ruflo coordinates Claude sub-agents only. `agent_spawn`, `claims`, `hive-mind` = Claude-to-Claude primitives.
3. Gemini (agy) is dispatched, never coordinated. No session ID, no claims, no hive-mind participation.
4. Hive-mind quorum workers are Claude only.
5. /tmp/ invariant: all Gemini output → `/tmp/`. Never direct repo writes.

---

## Tool-Group Integration Map

Schema: **Tier** (1=Claude-only / 2=ruflo-enhanced+fallback / 3=ruflo-only optional) ·
**Verdict** · **CC Fallback** · **Status**

| Group | Tools (n) | Tier | Verdict | CC Fallback | Status |
|---|---|---|---|---|---|
| **memory_search** | 1 | 2 | COMPLEMENT | grep / `brana skills suggest` | Wired in LOAD steps. Use `smart: false` — 9× faster, better precision than `smart: true`. |
| **agent_spawn + mgmt** | 9 | 2 | COMPLEMENT | CC `Task` tool | Designed in `backlog.md` step 7b. **ToolSearch preamble missing.** |
| **swarm** | 4 | 2 | COMPLEMENT | skip (no coordination shell) | Designed in `backlog.md` step 7a. **ToolSearch preamble missing.** |
| **claims** | 12 | 2 | COMPLEMENT | skip silently | Designed in `backlog.md` start/done/execute. **ToolSearch preamble missing.** |
| **coordination** (orchestrate + load_balance) | 2 of 7 | 2 | COMPLEMENT | sequential wave execution | Designed in `backlog.md` step 7b. Remaining 5 coordination tools → SKIP. **ToolSearch preamble missing.** |
| **hive-mind** (spawn + consensus + memory) | 3 of 10 | 2 | COMPLEMENT | CC `challenger` skill | Partially wired in `brainstorm.md` Phase 5b. **Expand to 4 gates** (see below). ToolSearch preamble missing in challenger, backlog plan, ship, close. |
| **progress** | 4 | 2 | COMPLEMENT | CC `Monitor` tool | **Not yet designed.** Add to `backlog.md` execute after `agent_spawn` — stream completion events instead of void. |
| **task/job** | 9 | 1 | **SKIP** | `brana backlog` CLI | tasks.json is authoritative. Parallel task system creates sync complexity. ADR-040 §1. |
| **workflow** | 12 | 3 | SKIP (now) | CC Workflow harness | Potential for persistent/resumable jobs surviving session death. Revisit when a concrete cross-session job scenario emerges. Needs ADR. |
| **managed agents** | 6 | 3 | SKIP | — | No persistent agent scenarios in current brana model. |
| **WASM agents** | 14 | 3 | SKIP | — | No untrusted skill execution scenario. Future: sandboxed skill testing. |
| **DAA** | 8 | 3 | SKIP | — | Dynamic adaptation requires a fundamentally different agent model. Not compatible with static agent definitions. |
| **ruvllm + agentdb (non-core)** | ~25 | 3 | SKIP | — | Likely stubs. `hierarchical-store` / `pattern-search` covered by `memory_search`. |

---

## ToolSearch Preamble Spec

Every procedure containing `mcp__ruflo__` calls needs this block **before the first ruflo
step**. The `<!-- ruflo preamble -->` comment is greppable — `validate.sh` Check 36
asserts preamble exists in any procedure with ruflo calls.

**backlog.md** (steps 1a, 5b/f, 7a–7c):
```
<!-- ruflo preamble -->
ToolSearch("select:mcp__ruflo__memory_search,mcp__ruflo__agent_spawn,mcp__ruflo__swarm_init,mcp__ruflo__claims_claim,mcp__ruflo__claims_release,mcp__ruflo__claims_mark-stealable,mcp__ruflo__coordination_orchestrate,mcp__ruflo__agent_pool")
```

**brainstorm.md** (Step 0 LOAD, Phase 5b M+ gate):
```
<!-- ruflo preamble -->
ToolSearch("select:mcp__ruflo__memory_search,mcp__ruflo__agent_spawn,mcp__ruflo__hive-mind_spawn,mcp__ruflo__hive-mind_consensus")
```

**build.md** (LOAD step):
```
<!-- ruflo preamble -->
ToolSearch("select:mcp__ruflo__memory_search,mcp__ruflo__agent_spawn,mcp__ruflo__claims_claim,mcp__ruflo__claims_release")
```

**challenger.md** (entry):
```
<!-- ruflo preamble -->
ToolSearch("select:mcp__ruflo__hive-mind_spawn,mcp__ruflo__hive-mind_consensus,mcp__ruflo__hive-mind_shutdown")
```

**research.md** (LOAD step):
```
<!-- ruflo preamble -->
ToolSearch("select:mcp__ruflo__memory_search,mcp__ruflo__agent_spawn")
```

**close.md** (coverage gate — new):
```
<!-- ruflo preamble -->
ToolSearch("select:mcp__ruflo__hive-mind_spawn,mcp__ruflo__hive-mind_consensus,mcp__ruflo__hive-mind_shutdown")
```

**ship.md** (pre-merge gate — new):
```
<!-- ruflo preamble -->
ToolSearch("select:mcp__ruflo__hive-mind_spawn,mcp__ruflo__hive-mind_consensus,mcp__ruflo__hive-mind_shutdown")
```

---

## Hive-mind Quorum Gate Spec

3 workers per gate. Quorum threshold: **majority (2/3)**. ≥2 workers confirm = HIGH
confidence finding (blocking). 1 worker only = LOW (informational, not blocking).
All workers are Claude instances (ADR-040 §4).

### Gate 1 — challenger (per ADR review)

Replaces the current single-perspective challenger invocation with a 3-worker quorum.

| Worker | Role | Prompt focus |
|---|---|---|
| Correctness | What is logically flawed or internally inconsistent? Focus on what breaks given the stated constraints. |
| Alternatives | Name at least 2 alternatives not considered. Specific trade-offs required — no abstract hand-waving. |
| Blast-radius | Top 3 second-order effects on other system components. Name the components. |

Invoke:
```
mcp__ruflo__hive-mind_spawn(count: 3, role: "specialist", prefix: "challenger-quorum")
mcp__ruflo__hive-mind_consensus(action: "propose", strategy: "quorum", quorumPreset: "majority",
  type: "adr-challenge", value: "{ADR/decision summary}")
```

### Gate 2 — backlog plan (L+ phases, before write)

Replaces/extends step 12 challenge gate in backlog.md plan.

| Worker | Role | Prompt focus |
|---|---|---|
| Feasibility | Where is effort most likely underestimated? Identify the task most likely to blow up scope. |
| Completeness | What is missing? Name tasks or dependencies not captured, including DDD/TDD/SDD. |
| Sequencing | Is the dependency order correct? Where will blocking dependencies create bottlenecks? |

### Gate 3 — ship (pre-merge)

Fires before merge-to-main in ship.md.

| Worker | Role | Prompt focus |
|---|---|---|
| Regression | What existing functionality is most at risk? Name specific files or behaviors. |
| Security | What security concerns does this change introduce or expose? |
| Completeness | Is the implementation done? What was intended but not finished? |

### Gate 4 — close (session coverage)

Fires at close before writing the handoff.

| Worker | Role | Prompt focus |
|---|---|---|
| Drift | What was intended but not completed? What drifted from the original plan? |
| Learnings | What patterns or findings should be stored as knowledge? Name them. |
| Next-actions | What follow-up tasks should be filed but haven't been? Name them with context. |

---

## 3 Ranked Implementation Proposals

### Proposal 1 — ToolSearch Preamble Fix
**Effort:** XS · **Impact:** HIGH · **Prerequisite for everything**

Add `<!-- ruflo preamble -->` + `ToolSearch(...)` block to 7 procedures. This
immediately unblocks all existing ruflo calls that are already designed in.

Add `validate.sh` Check 36: assert `<!-- ruflo preamble -->` exists in any procedure
file containing `mcp__ruflo__` calls. Grep pattern:
```bash
# Files with ruflo calls but no preamble = lint error
```

### Proposal 2 — Hive-mind Quorum Gates
**Effort:** M · **Impact:** HIGH · **Blocked by:** Proposal 1 + t-1638 (threshold calibration)

Wire the 4 gates specified above into challenger.md, backlog.md plan, ship.md, close.md.
Worker role prompts are defined above — no further design needed.

### Proposal 3 — progress_watch Integration
**Effort:** S · **Impact:** MEDIUM · **Blocked by:** Proposal 1

Add `mcp__ruflo__progress_watch` call in `backlog.md` execute after each `agent_spawn`.
Streams task completion events. Replaces the current void between "spawned" and "result written."
CC fallback: `Monitor` tool on the spawned task's output file.

---

## Risks

- **ToolSearch adds latency** — loading 8 schemas per skill adds ~200ms. Acceptable for human-facing skills; may need optimization for hooks.
- **Hive-mind in subscription mode** — agent_execute blocked; quorum workers may fail (t-1598/t-1599). Gate must fall back to `Skill(skill="brana:challenge")` if hive-mind_spawn fails.
- **Quorum threshold calibration** — t-1638 sets the thresholds after t-1599 calibration. Proposal 2 is blocked until that task completes.

## Next Steps

1. File implementation tasks for Proposals 1–3 (this doc = spike output)
2. Implement Proposal 1 first — no blockers, unlocks everything
3. Complete t-1638 calibration, then Proposal 2
4. Proposal 3 can run in parallel with 2
