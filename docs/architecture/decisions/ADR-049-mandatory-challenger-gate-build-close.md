---
id: ADR-049
status: accepted
date: 2026-06-08
task: t-1867
tags: [build, challenger, loop, reflexion, quality-gate, looptrap]
informs:
  - docs/architecture/features/build-loop-redesign.md
  - system/procedures/build.md
---

# ADR-049: Mandatory Challenger Gate at BUILD→CLOSE Boundary

## Status

Accepted — 2026-06-08

## Context

The `/brana:build` BUILD→CLOSE transition has structural gates (ISC verify, artifact check, Four Questions self-assessment) but no mandatory semantic evaluator. The actor that builds the implementation self-certifies completion.

Reflexion (Shinn et al. NeurIPS 2023) and [dim-60](../../../brana-knowledge/dimensions/60-agent-loop-architecture.md) establish that **actor and evaluator must be architecturally separated**: if the same model generates both action and critique, it repeats the same misconceptions and convergence fails.

[LoopTrap research (arxiv 2605.05846)](../features/build-loop-redesign.md) identifies two attack vectors relevant to this gate:

- **P4 Authority Override** — adversarial content in external tool outputs (web fetch, API responses) injected into the evaluator's context can corrupt its verdict
- **P7 Recursive Decomposition** — uncapped verification loops cause subtask explosion and infinite regression

The Challenger agent (`system/agents/challenger.md`) currently runs optionally at SPECIFY (spec review) and DECOMPOSE (sprint contract review). It is never mandatory at BUILD exit. The gap: `validate.sh` covers structural correctness (tests pass, lint clean); no gate covers semantic alignment with spec.

## Decision Record (frozen 2026-06-08)

> Do not modify after acceptance.

**Decision:** Add a mandatory `### Challenger Gate` step between docs generation and CLOSE in `system/procedures/build.md`. Challenger receives only trusted content and blocks CLOSE on critical findings.

**Invocation rules:**

| Build type | Gate behavior | User can skip? |
|---|---|---|
| M+ effort, any path | Mandatory — runs automatically | No |
| S effort + touches `system/`, `hooks/`, `decisions/` | Mandatory — runs automatically | No |
| S effort, regular paths | Prompt at BUILD exit, default = "Run Challenger" | Yes — must explicitly choose Skip |

The "default-run, explicit-skip" stance for S regular-path builds is intentional. The friction of choosing "Skip" is load-bearing — it forces a conscious decision rather than passive omission.

**Input contract (LoopTrap P4 defense):**

Challenger reads ONLY:
- Task spec text (from task description + context field)
- `git diff HEAD` — committed code diff
- Task AC list (from task context `AC:` lines)

Challenger NEVER reads:
- Raw web fetch responses
- External API outputs
- Anything not from the repo or task metadata

This contract is enforced at the Challenger spawn call site in `build.md`, not merely documented.

**Blocking rules** (from `system/agents/CALIBRATION.md`):

- Score ≥ 4 (WARNING or CRITICAL) → verdict `RECONSIDER` → CLOSE blocked
- Score ≤ 3 (OBSERVATION or lower) → verdict `PROCEED` or `PROCEED WITH CHANGES` → CLOSE continues

**Repair loop (Reflexion ASSIMILATE step, LoopTrap P7 defense):**

When Challenger returns RECONSIDER, findings are structured as:
```
{severity, ac_violated, description, file, spec_says}
```

The `spec_says` field is mandatory — it gives the repair BUILD iteration a precise target rather than just "something was wrong."

User choice presented:
- **Fix now** — findings appended to task context as `sr_t` (Reflexion verbal self-reflection). Re-enter BUILD with findings visible. BUILD → validate.sh → Challenger iteration 2. If pass → CLOSE. If fail (iteration 2) → unconditional user surface.
- **Override** — reason required, logged to task context. CLOSE proceeds with annotation.
- **Abandon** — task marked blocked, session ends.

**Hard cap: max 2 Challenger iterations.** After iteration 2, regardless of verdict, the gate presents an unconditional user surface: `["Override + reason | Abandon"]`. No iteration 3. This prevents P7 Recursive Decomposition.

**Model tier:** Challenger runs as Sonnet with `effort: max` (current default in `challenger.md`). No two-tier (Haiku + Sonnet) design — Sonnet is fast and cheap enough that Haiku pre-screening adds complexity without meaningful savings. Effort-based and path-based routing replaces dynamic escalation.

**Placement in build loop:**

```
BUILD (all subtasks complete)
  ↓ Checkpoint — BUILD
  ↓ ISC Verify (existing)
  ↓ Gate: BUILD → CLOSE — artifact check (existing)
  ↓ Four Questions Gate (existing)
  ↓ Docs generation — /brana:docs (existing)
  ↓ [NEW] Challenger Gate
  ↓ CLOSE
```

Challenger runs after docs generation so it reviews the complete artifact set (code + docs in the diff).

**Strategies excluded:** Spike and investigation strategies skip this gate entirely (same as other BUILD→CLOSE gates).

## Rationale

**Why mandatory rather than optional?**
The gap between "optional and remembered" vs. "mandatory" is the difference between a convention and an architectural property. Optional gates degrade to noise over time; mandatory gates hold.

**Why default-run for S builds?**
Challenger is Sonnet/max. Typical invocation: ~5-10 seconds. The cost of a false-positive-free review on a clean S build is negligible. The cost of shipping a spec-misaligned S build is a follow-up fix task.

**Why CALIBRATION.md score ≥ 4 as the threshold?**
Score ≥ 4 maps to WARNING (known unmitigated risk affecting real workflows) or CRITICAL (blocks success, data loss, security). Score 3 and below includes "minor gaps or workarounds needed" which should surface as findings but not block shipping.

**Why max 2 iterations?**
Production numbers from RALPH (open-ralph-wiggum): average 1.4–1.8 outer iterations per task. Two iterations covers the realistic repair case. Uncapped iterations → P7 Recursive Decomposition risk from LoopTrap taxonomy.

## Consequences

- Easier: every M+ build exits BUILD with an independent semantic review, not just structural validation
- Easier: repair loop is structured — findings include `spec_says` for precise repair targeting
- Harder: S builds on regular paths see a prompt at BUILD exit (minor friction; intentional)
- Risk: false positives cause gate fatigue → mitigated by bounded rubric (3 specific checks for S builds, full CALIBRATION.md for M+) and always-available override path with reason logging

## Implementation

- `system/procedures/build.md` — add `### Challenger Gate` section (t-1870)
- `docs/architecture/features/build-loop-redesign.md` — update architecture diagram (t-1868)
- `docs/guide/workflows/build.md` — user-facing explanation (t-1871)
- Behavioral test — verify gate fires correctly (t-1873)

## Research Foundation

- Reflexion (Shinn et al. NeurIPS 2023) — actor/evaluator separation requirement
- [dim-60: Agent Loop Architecture](../../../brana-knowledge/dimensions/60-agent-loop-architecture.md) — JUDGE step must be architecturally separated from BUILD
- LoopTrap (arxiv 2605.05846) — P4 Authority Override and P7 Recursive Decomposition defenses
- `docs/ideas/challenger-outer-loop-gate.md` — brainstorm session 2026-06-08 (two rounds of adversarial challenge)
