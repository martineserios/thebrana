---
status: proposed
---
# ADR-059: Multi-Agent Substrate Selection (native CC vs ruflo vs agy)

**Status:** Proposed
**Date:** 2026-06-19
**Deciders:** Martín Rios
**Tags:** agents, orchestration, ruflo, workflow, subscription, architecture
**Tasks:** t-2137 (hive-mind workflow template), t-2139 (challenge wiring), t-2140 (autonomous-tier spike)
**Evidence:** session probe 2026-06-19; `field-note_ruflo-agentic-layer-subscription-theater`

---

## Context

brana needs multi-agent capabilities — parallel review, "hive-mind" collective intelligence, and autonomous/overnight work. ruflo (claude-flow) advertises a large agentic surface (hive-mind, swarm, consensus, neural, daa, autopilot). A **hard constraint** is that all LLM execution must run on the **Claude subscription**, not a metered API key.

A live probe on 2026-06-19 (ruflo v3.10.40) clarified what is real under that constraint and corrected an initial wrong assumption ("ruflo's agentic features are theater"). The truth is a split between two ruflo surfaces, plus the native Claude Code primitives and agy:

| Substrate | Subscription? | Nature | Cost to run |
|-----------|---------------|--------|-------------|
| **Native Task** (subagents) | ✅ | in-session, inherits parent setup | light |
| **Native Workflow** | ✅ | in-session, deterministic orchestration (pipeline/parallel + schemas) | light |
| **ruflo CLI `--claude` / autopilot** | ✅ (proven) | autonomous *full* CC sessions + shared memory wiring | **heavy** |
| **ruflo memory / recall** | ✅ | shared persistent store (embeddings) | light |
| **ruflo MCP `agent_execute` / `hive-mind_*`** | ❌ | API-key gated; records / non-executing under subscription | — |
| **agy (Gemini)** | separate (Gemini quota) | cheap bulk text | very light |

**Key evidence:**
- `ruflo hive-mind spawn --claude --non-interactive -o "compute 1234*5678"` returned the correct answer with `apiKeySource:none`, `model:claude-opus-4-8`, and a `five_hour` (subscription) rate-limit event. The CLI path is genuinely subscription-native. Each worker boots a *full* CC session (SessionStart hooks, memory recall, MCP) — that trivial call cost ~$0.19-equivalent / ~40k tokens.
- The ruflo **MCP** tools are a different code path: `agent_execute` returns `"No LLM provider configured"` without an API key; `hive-mind_spawn`'s source comment is `"Create agent record"` (writes metadata, does not execute a worker); `coordination_consensus` runs with `totalNodes:1` (a self-vote). These are hollow under subscription.
- Genuinely fabricated regardless of auth: `agent_health` returns 1.0 for a 0%-success agent; `neural_train` sets `accuracy = stored>0?1.0:0` (it stores embeddings, it does not train).

The decision is **division of labor**, not "pick the one real tool."

---

## Decision

Select the multi-agent substrate by two axes: **in-session-and-structured** vs **autonomous-and-persistent**.

```
Need multiple agents?
├─ Results back in THIS session, structured, human/Claude in the loop?
│    ├─ deterministic find→verify→synthesize   → Native WORKFLOW
│    └─ quick parallel investigation            → Native TASK
├─ Fire-and-forget / overnight / "keep working till ALL done"?
│    └─ autonomous Claude workers + shared memory → ruflo --claude / AUTOPILOT  (pending validation — see Open Questions)
├─ Agents need shared memory / cross-session learning / cost attribution?
│    └─ ruflo MEMORY substrate (any executor reads/writes it)
└─ Atomic task / detail retrieval — ZERO reasoning?
     └─ claude -p --model haiku  (subscription — robust default, no quota to manage)

(agy/Gemini appears in exactly one place: the challenger's cross-model second opinion — see rule 4.)
```

### Settled rules

1. **In-session review/judgment skills use native** (Task or Workflow): `challenge`, `decide`, `brainstorm` (evaluate phase), `reconcile`, `code-review`. Spawning a full autonomous ruflo CC session per reviewer is overkill for in-session work; native subagents are lighter and return structured results.
2. **Never use ruflo MCP `agent_execute` / `hive-mind_*` / `coordination_*` for execution.** They are records/self-votes under subscription. Skills currently calling them (challenge standard mode, brainstorm Phase 5b, via `_shared/adversarial-hive-mind.md`) migrate to native fan-out.
3. **ruflo memory/recall stays** — it is real and load-bearing (see ADR-058 HybridProvider).
4. **agy has exactly one job: the challenger's cross-model second opinion.** Nothing else in brana depends on agy. Its only real value is architectural diversity — a non-Claude (Gemini) voice in adversarial review. The atomic/retrieval tier defaults to `claude -p --model haiku` (subscription), never agy. **Simple quota fallback:** when Gemini quota is exhausted, the second-opinion slot defaults to another model (a Claude challenger lens) — non-blocking, no failover chain, just default-and-continue. This is the only place Gemini quota is consumed.
5. **Reusable native blocks** live in `.claude/workflows/`: `hive-mind` (answer one question), `verify-findings` (the **canonical finding-verifier** / judge-panel), and `sweep` (parallel **read-only** finders → cluster → verify). `verify-findings` is the single source of truth for finding verification — `sweep` and `challenge --deep` call it via `workflow()`/`Workflow`. `hive-mind` deliberately keeps an *independent* answer-verifier (verifies a free answer against its claims, not a finding's severity — a different primitive; do not merge). `sweep` finders run as read-only `Explore` agents by construction, so a discovery sweep cannot mutate its target. Deterministic glue (clustering, coverage guard, confidence math, delegation, return shape) is covered by `.claude/workflows/tests/smoke.mjs`.

---

## Consequences

- The challenge skill's standard mode (and brainstorm Phase 5b) were silently hollow under subscription — they called the ruflo MCP hive-mind, which never executed workers; only the `--council`/`--hats` native modes worked. Migrating the shared pattern to native fan-out is a **bug fix**, not just a refactor.
- ruflo earns a defined, narrow home: **autonomous/persistent swarms** (its `autopilot` = "keep agents working until ALL tasks done") — a capability native in-session tools do not provide. This overlaps with brana's existing agy/cron autonomous tier (see Open Questions).
- Cost guardrail: ruflo `--claude` workers are heavyweight (full CC session boot). Reserve for tasks that justify a full autonomous agent; do not use for fan-out where native subagents suffice.
- **Downstream revisions required** by the agy demotion: `delegation-routing.md` §Compute Routing (currently Gemini-favoring, ENRICH-mandatory, "ruflo down → ABORT" logic) must be rewritten around the subscription-default tier; the `/brana:gemini` skill becomes optional-garnish; `challenge` step 4b (Gemini detail retriever, "runs by default") becomes opt-in non-blocking. The challenger Gemini-source confidence tiers stay (still useful when garnish runs).

---

## Open questions (not decided here)

1. **Autonomous tier: ruflo autopilot vs native `claude -p` background?** Partially resolved by a controlled probe (2026-06-19): ruflo autopilot's persistence loop is **real** — `enable`→`check` returns `CONTINUE: 95/234 tasks remaining (iteration 1/50)` (real counts), `predict` picks a real next task from the queue, `disable` restores `ALLOW STOP`. It works as a **Stop-hook re-engagement loop** (blocks a host CC session from ending, feeds the next queued task, up to max-iterations/timeout). Caveats: task *selection* is queue/heuristic, not ML (`predict` confidence is a hardcoded `0.5 — learning not available`); it requires a host CC session with the stop-hook wired plus tasks in its sources (team-tasks/swarm-tasks/file-checklist). **Lean recommendation:** for brana, a native loop over `tasks.json` (via `/loop` or cron + `claude -p`) is likely simpler and more controllable than wiring autopilot's stop-hook + syncing its task sources — but autopilot is a working fallback if we want "until done" persistence without building it. Decide when the autonomous tier is actually needed.
2. ~~Whether to expose a `sweep` reusable workflow block now or on first need.~~ **Resolved (2026-06-19):** built now — `sweep.js` ships with read-only finders, agreement-aware clustering, and verification delegated to `verify-findings`. Loop-until-dry `exhaustive` mode intentionally deferred (needs prior-round feedback to be real).

---

## Alternatives considered

- **Rip out ruflo entirely.** Rejected — memory substrate is load-bearing; the CLI autopilot path is real and fills an autonomous niche native CC lacks.
- **Use ruflo MCP hive-mind as the multi-agent layer.** Rejected — hollow under subscription (records + self-votes, no execution).
- **Use ruflo `--claude` for in-session review.** Rejected — heavyweight (full CC session per reviewer) for work native Task/Workflow does lighter and with structured output.
