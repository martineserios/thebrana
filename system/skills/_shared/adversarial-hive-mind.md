# Adversarial Hive-Mind Pattern

Shared procedure for spawning a 3-worker adversarial quorum via ruflo. Used by `brainstorm` (Phase 5b M+ challenger review) and `challenge` (step 4a standard mode).

## Setup

```
mcp__ruflo__hive-mind_shutdown(force: true)
mcp__ruflo__hive-mind_init(consensus: "quorum", topology: "hierarchical")
mcp__ruflo__hive-mind_spawn(count: 3, role: "specialist", prefix: "{caller-prefix}")
```

Replace `{caller-prefix}` with the caller's identifier (e.g. `"challenger"`, `"brainstorm-challenger"`).

## Worker roles

Assign each spawned worker a distinct cognitive lens:

| Worker | Role | Brief |
|--------|------|-------|
| Worker 1 | **convergent** | Synthesize constraints — what is definitely true, what rules must hold? |
| Worker 2 | **systems** | Map second-order effects — what else breaks, what cascades? |
| Worker 3 | **critical** | Adversarial — what are the failure modes, hidden debt, worst-case paths? |

Instruction for all workers: "Be specific and actionable. Don't nitpick — focus on things that would actually cause problems or wasted effort. Suggest concrete alternatives for each concern."

## Collect via quorum consensus

After all 3 workers respond:

```
mcp__ruflo__hive-mind_consensus(
  action: "propose",
  strategy: "quorum",
  quorumPreset: "majority",
  type: "{consensus-type}",
  value: "{findings or target to evaluate}"
)
```

Replace `{consensus-type}` with the caller's type string (e.g. `"findings"`, `"brainstorm-findings"`).

## Confidence tiers

| Source | Confidence |
|--------|-----------|
| ≥2 of 3 workers agree | **HIGH** |
| Single-worker finding | **OBSERVATION** |

## Fallback (ruflo unavailable)

If ruflo is unavailable, run inline — Claude performs all three cognitive roles (convergent, systems, critical) sequentially in main context, then self-assesses which findings two roles would have agreed on (**HIGH**) vs single-role only (**OBSERVATION**).
