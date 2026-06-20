# Adversarial Hive-Mind Pattern (native)

Shared procedure for a 3-worker adversarial quorum using **native Claude Code subagents** (Agent/Task tool — runs on the subscription). Used by `brainstorm` (Phase 5b M+ challenger review) and `challenge` (step 4a standard mode).

> History: this pattern previously spawned workers via ruflo `hive-mind_init/spawn/consensus`. Those MCP tools are theater under subscription-only — `hive-mind_spawn` writes metadata records that never execute, and `hive-mind_consensus` is a 1-node self-vote (verified 2026-06-19, see `field-note_ruflo-agentic-layer-subscription-theater`). The native fan-out below does what they only claimed to.

## Spawn the quorum (parallel, native)

Spawn **3 agents in one message** using the Agent tool with `subagent_type: "brana:challenger"`. No agent sees another's output — synthesis is the caller's job. Each gets a distinct cognitive lens:

| Worker | Role | Brief |
|--------|------|-------|
| Worker 1 | **convergent** | Synthesize constraints — what is definitely true, what rules must hold? |
| Worker 2 | **systems** | Map second-order effects — what else breaks, what cascades? |
| Worker 3 | **critical** | Adversarial — what are the failure modes, hidden debt, worst-case paths? |

Provide every worker: the target being evaluated + relevant code/files + the chosen flavor. Instruction for all: "Be specific and actionable. Don't nitpick — focus on things that would actually cause problems or wasted effort. Suggest concrete alternatives for each concern. Rate each finding CRITICAL / WARNING / OBSERVATION."

## Collect (caller synthesizes)

Await all 3 agents. The caller (Claude, main context) merges and dedups — there is no separate consensus tool. A concern raised by ≥2 workers is the high-confidence signal.

## Confidence tiers

| Source | Confidence |
|--------|-----------|
| ≥2 of 3 workers agree | **HIGH** |
| Single-worker finding | **OBSERVATION** |

## Optional: adversarial verification (deep mode)

To kill plausible-but-wrong findings before presenting, pass the merged findings through the verify stage:

```
Workflow({ scriptPath: ".claude/workflows/verify-findings.js",
           args: { target: "{what was evaluated}", findings: [{severity, text, source}, ...] } })
```

It returns each finding with `holds` / `adjusted_severity` / `reason`. Drop FALSE_POSITIVEs; present survivors at their calibrated severity. This is what `/brana:challenge --deep` uses.

## Fallback (no Agent/Task available)

If subagents cannot be spawned, run inline — Claude performs all three cognitive roles (convergent, systems, critical) sequentially in main context, then self-assesses which findings two roles would have agreed on (**HIGH**) vs single-role only (**OBSERVATION**).
