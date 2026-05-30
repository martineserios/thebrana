---
title: Ruflo Integration Map — Tool Groups, Preambles, Quorum Gates
status: active
created: 2026-05-30
depends_on: ADR-040
see_also: brana-v2-compute-model.md, claude-gemini-orchestration.md
---

# Ruflo Integration Map

> ADR-040 locked the architecture. This doc is the operational map: which tool groups to
> use, how to load them, where they fire, and what falls back when ruflo is unavailable.

## Root Constraint

All `mcp__ruflo__*` tools are in the **deferred tools list** — schemas are not loaded at
session start. Any procedure that calls `mcp__ruflo__foo(...)` without a preceding
`ToolSearch` will throw `InputValidationError` and fall back silently.

The fix is a per-procedure `<!-- ruflo preamble -->` block that loads exactly the schemas
the procedure needs. `validate.sh` Check 36 asserts this preamble exists in any procedure
containing `mcp__ruflo__` calls.

---

## Tool-Group Integration Map

**Tiers:** 1 = Claude-only (never delegate) · 2 = ruflo-enhanced with CC fallback · 3 = optional / skip for now

| Group | Tools (n) | Tier | Verdict | CC Fallback | Status |
|---|---|---|---|---|---|
| **memory_search** | 1 | 2 | COMPLEMENT | grep / `brana skills suggest` | Wired in LOAD steps. Use `smart: false` — 9× faster, better precision than `smart: true`. |
| **agent_spawn + mgmt** | 9 | 2 | COMPLEMENT | CC `Task` tool | Designed in `backlog.md` step 7b. ToolSearch preamble missing — see below. |
| **swarm** | 4 | 2 | COMPLEMENT | skip (no coordination shell) | Designed in `backlog.md` step 7a. ToolSearch preamble missing. |
| **claims** | 12 | 2 | COMPLEMENT | skip silently | Designed in `backlog.md` start/done/execute. ToolSearch preamble missing. |
| **coordination** (orchestrate + load_balance) | 2 of 7 | 2 | COMPLEMENT | sequential wave execution | Designed in `backlog.md` step 7b. Remaining 5 coordination tools → SKIP. ToolSearch preamble missing. |
| **hive-mind** (spawn + consensus + memory) | 3 of 10 | 2 | COMPLEMENT | `Skill("brana:challenge")` | Partially wired in `brainstorm.md` Phase 5b. Expand to 4 gates (see below). ToolSearch preamble missing in challenger, backlog plan, ship, close. |
| **progress** | 4 | 2 | COMPLEMENT | CC `Monitor` tool | Not yet designed. Add to `backlog.md` execute after `agent_spawn` — stream completion events. |
| **task/job** | 9 | 1 | **SKIP** | `brana backlog` CLI | tasks.json is authoritative. Parallel task system creates sync complexity. ADR-040 §1. |
| **workflow** | 12 | 3 | SKIP (now) | CC Workflow harness | Potential for persistent/resumable jobs surviving session death. Revisit when a concrete cross-session scenario emerges. Needs ADR. |
| **managed agents** | 6 | 3 | SKIP | — | No persistent agent scenarios in current brana model. |
| **WASM agents** | 14 | 3 | SKIP | — | No untrusted skill execution scenario. Future: sandboxed skill testing. |
| **DAA** | 8 | 3 | SKIP | — | Dynamic adaptation incompatible with static agent definitions. |
| **ruvllm + agentdb (non-core)** | ~25 | 3 | SKIP | — | Likely stubs. `hierarchical-store` / `pattern-search` covered by `memory_search`. |

### memory_search — smart:false decision

`smart: true` was tested post-ControllerRegistry fix (ruflo 3.10.3). Results: cold-start
3.3s (7× the 500ms threshold), MMR too aggressive (top-2/3 collapse to <0.1 similarity).
**Use `smart: false` on all LOAD calls.** Re-evaluate only if ruflo exposes tunable
`mmr_lambda` + warmup. See t-1697 (closed).

---

## ToolSearch Preamble Spec

Add this block **before the first ruflo step** in each procedure. The comment is greppable
— `validate.sh` Check 36 asserts preamble exists in any procedure with ruflo calls.

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

**close.md** (coverage gate):
```
<!-- ruflo preamble -->
ToolSearch("select:mcp__ruflo__hive-mind_spawn,mcp__ruflo__hive-mind_consensus,mcp__ruflo__hive-mind_shutdown")
```

**ship.md** (pre-merge gate):
```
<!-- ruflo preamble -->
ToolSearch("select:mcp__ruflo__hive-mind_spawn,mcp__ruflo__hive-mind_consensus,mcp__ruflo__hive-mind_shutdown")
```

---

## Hive-mind Quorum Gate Spec

3 workers per gate. Quorum threshold: **majority (2/3)**. ≥2 confirm = HIGH confidence
(blocking). 1 only = LOW (informational). All workers are Claude instances (ADR-040 §4).

Fallback when ruflo unavailable: `Skill("brana:challenge")` for all gates.

Invoke pattern:
```
mcp__ruflo__hive-mind_spawn(count: 3, role: "specialist", prefix: "{gate-name}")
mcp__ruflo__hive-mind_consensus(action: "propose", strategy: "quorum",
  quorumPreset: "majority", type: "{gate-type}", value: "{summary}")
```

### Gate 1 — challenger (per ADR / plan review)

| Worker | Focus |
|---|---|
| Correctness | What is logically flawed or internally inconsistent? Focus on what breaks given the stated constraints. |
| Alternatives | Name ≥2 alternatives not considered. Specific trade-offs required — no abstract hand-waving. |
| Blast-radius | Top 3 second-order effects on other system components. Name the components. |

Fires in: `challenger.md`. Blocked by: t-1638 (quorum ADR after calibration).

### Gate 2 — backlog plan (L+ phases, before write)

| Worker | Focus |
|---|---|
| Feasibility | Where is effort most likely underestimated? Identify the task most likely to blow up scope. |
| Completeness | What is missing? Name tasks or dependencies not captured, including DDD/TDD/SDD gaps. |
| Sequencing | Is the dependency order correct? Where will blocking dependencies create bottlenecks? |

Fires in: `backlog.md` step 12 (plan challenge gate, L+ only).

### Gate 3 — ship (pre-merge)

| Worker | Focus |
|---|---|
| Regression | What existing functionality is most at risk? Name specific files or behaviors. |
| Security | What security concerns does this change introduce or expose? |
| Completeness | Is the implementation done? What was intended but not finished? |

Fires in: `ship.md` before merge-to-main.

### Gate 4 — close (session coverage)

| Worker | Focus |
|---|---|
| Drift | What was intended but not completed? What drifted from the original plan? |
| Learnings | What patterns or findings should be stored as knowledge? Name them. |
| Next-actions | What follow-up tasks should be filed but haven't been? Name them with context. |

Fires in: `close.md` before writing the handoff.

---

## Implementation Sequence

| Priority | Task | Effort | Blocked by |
|---|---|---|---|
| 1 | Add ToolSearch preamble to 7 procedures | XS | — |
| 2 | Wire `progress_watch` in `backlog.md` execute after `agent_spawn` | S | preamble |
| 3 | Hive-mind quorum Gates 1–4 | M | preamble + t-1638 |

---

## Risks

- **ToolSearch latency** — loading 8 schemas adds ~200ms. Acceptable for human-facing skills; avoid in hooks.
- **Hive-mind in subscription mode** — `agent_execute` requires `ANTHROPIC_API_KEY`; falls back to `Skill("brana:challenge")` if `hive-mind_spawn` fails.
- **Quorum thresholds** — t-1638 locks thresholds after t-1599 calibration. Gate 1 blocked until then.
