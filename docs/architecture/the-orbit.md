# The Orbit & the Substrate — Index & Reading Map

**Status:** Index / orientation (2026-06-21) · **Owner:** Martín Rios
**Type:** Index — the entry point for the autonomous-agent doc cluster.

This is the front door to brana's autonomous-agent system — the spine docs below,
in reading order. Read this first; peripheral notes link out from each.

## Vocabulary

Three words, one model:

- **the Substrate** — the capability/parts layer: primitives (`Workflow`, `Task`,
  `/loop`, ruflo-memory) + composed blocks (`hive-mind`, `sweep`, `verify-findings`).
  *What things ARE.*
- **the Orbit** — the autonomous operation that runs on the Substrate: the runner that
  works its own backlog (loop → build → verify → ship), in supervised and unattended
  tiers, behind a human-merge gate. *What it DOES.*
- **ground control** — you, the human at the merge gate. Nothing leaves the Orbit
  without ground control's sign-off. *Who DECIDES.*

> **Tagline:** *the Orbit runs on the Substrate.*

A quick disambiguation test: *"is this a Substrate thing or an Orbit thing?"*
`hive-mind` is a Substrate block (a part); the sandbox (t-2173) is what makes the Orbit
safe; "this task is eligible to enter the Orbit" = autonomous-eligible; a merged PR is
work cleared by ground control to leave the Orbit.

## Reading map

### The Substrate — capabilities (what things are)

| Doc | Role |
|-----|------|
| [substrate-primitives.md](substrate-primitives.md) | **Substrate capstone** — primitives, composed blocks, composition grammar, Definition-of-Done, the two autonomy architectures (§2b) |
| [workflow-primitive.md](workflow-primitive.md) | The `Workflow` tool's verified API surface (reference) |
| [features/consensus-primitive.md](features/consensus-primitive.md) | A Substrate block — cross-model quorum voting (design-only, t-2143) |
| [decisions/ADR-059-multi-agent-substrate-selection.md](decisions/ADR-059-multi-agent-substrate-selection.md) | Which substrate for which job (the foundational decision) |

### The Orbit — operation (what it does)

| Doc | Role |
|-----|------|
| [substrate-end-state.md](substrate-end-state.md) | **Orbit capstone** — autonomy tiers, staged rollout, safety net, branch strategy. *(The filename predates this vocabulary; this doc IS the Orbit.)* |
| [substrate-end-state.md#operating-the-orbit](substrate-end-state.md#operating-the-orbit) | **Operating the Orbit** — the two tiers (supervised / unattended): arm / observe / stop |
| [features/autonomous-runner.md](features/autonomous-runner.md) | The Orbit runner — observe / run-one / run-batch (Stages 1–3 built, t-2140) |
| [features/learned-eligibility.md](features/learned-eligibility.md) | Orbit Stage 4 — learned/adaptive eligibility (design-only, t-2142) |
| [decisions/ADR-060-branch-strategy-autonomous-agents.md](decisions/ADR-060-branch-strategy-autonomous-agents.md) | Branch strategy — agent PRs to `dev`, human promotes to `main` |
| [decisions/ADR-050-loop-request-protocol.md](decisions/ADR-050-loop-request-protocol.md) | Loop-request protocol / autonomy caps |

### Calibration & research (the evidence)

| Doc | Role |
|-----|------|
| [../research/substrate-leverage-audit.md](../research/substrate-leverage-audit.md) | Empirical calibration — native vs ruflo vs `/loop`, token costs, the loop→Workflow→memory triad |
| [../research/2026-06-11-loop-native-redesign.md](../research/2026-06-11-loop-native-redesign.md) | Loop-native redesign probe (pre-decision research) |

### Pre-decision ideas (not yet committed)

| Doc | Status |
|-----|--------|
| [../ideas/runner-capability-isolation.md](../ideas/runner-capability-isolation.md) | Sandbox the Orbit's executor — bwrap capability isolation (idea, t-2173; HARD precondition for unattended runs) |

## How the spine fits together

```
  ADR-059 (which substrate)          ← the decision
      │
      ├─► substrate-primitives.md  ← the Substrate (parts + composition)
      │
      └─► substrate-end-state.md   ← the Orbit (operation + safety net)
              │
              ├─► autonomous-runner.md + ADR-060 + ADR-050   ← the runner
              │       └─ hardening: runner-capability-isolation.md (t-2173)
              └─► learned-eligibility.md (Stage 4, t-2142)
```
