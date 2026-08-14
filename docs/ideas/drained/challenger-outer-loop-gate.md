---
title: Challenger as Mandatory Outer Loop Gate in /brana:build
status: implemented
created: 2026-06-08
task: t-1856
tags: [build, challenger, loop, reflexion, quality-gate]
---

# Challenger as Mandatory Outer Loop Gate in /brana:build

> Brainstormed 2026-06-08 from t-1856.

## Problem

The `/brana:build` BUILD→CLOSE transition has structural gates (tests exist, docs exist, ISC pass, Four Questions self-assessment) but no mandatory semantic evaluator. The same actor that built the implementation self-certifies completion. Per Reflexion (Shinn et al. NeurIPS 2023) and dim-60, this is the convergence failure mode: actor and evaluator must be architecturally separated.

Challenger is currently invoked optionally — manual or ad-hoc at SPECIFY and DECOMPOSE. It is never mandatory at BUILD exit.

## Proposed Solution

Add a `### Challenger Gate` section in `system/procedures/build.md` between docs generation and CLOSE. Challenger (Sonnet with effort:max) receives only trusted content (task spec + code diff + AC list) and reviews against the CALIBRATION.md rubric.

### Invocation rules

| Build type | Gate behavior | Can user skip? |
|---|---|---|
| M+ effort, any path | Mandatory, no prompt | No |
| S effort + touches `system/`, `hooks/`, `decisions/` | Mandatory, no prompt | No |
| S effort, regular paths | Prompted, default = "Run Challenger" | Yes, must explicitly choose Skip |

### Input contract (LoopTrap safety)

Challenger reads ONLY:
- Task spec text (trusted)
- `git diff HEAD` — committed code diff (trusted)
- Task context field / AC list (trusted)

Challenger NEVER reads:
- Raw web fetch responses
- External API outputs
- Anything not from the repo or task metadata

This constraint prevents P4 Authority Override (LoopTrap taxonomy) — adversarial content in external tool outputs cannot influence the gate verdict.

### Blocking rules

Derived from CALIBRATION.md (already defined in `system/agents/CALIBRATION.md`):
- Score >= 4 (WARNING/CRITICAL) → verdict RECONSIDER → CLOSE blocked
- Score <= 3 (OBSERVATION/LOW) → verdict PROCEED or PROCEED WITH CHANGES → CLOSE continues

### Repair loop (Reflexion ASSIMILATE step)

When Challenger returns RECONSIDER:

```
Challenger output: structured findings
  {severity, ac_violated, description, file, spec_says}
     ↓
User choice:
  "Fix now" → findings appended to task context (= sr_t in Reflexion terminology)
               re-enter BUILD with findings visible as context
               BUILD → validate.sh → Challenger iteration 2
               If pass → CLOSE
               If fail (iter 2) → unconditional user surface: [Override + reason | Abandon]
               Hard cap: no iteration 3 (prevents P7 Recursive Decomposition)

  "Override" → reason required, logged to task context, CLOSE proceeds with annotation
  "Abandon"  → task marked blocked, session ends
```

The `spec_says` field in findings is mandatory — Challenger must output what the spec says correct behavior should be, not just what was wrong. This gives the repair BUILD iteration a precise target.

### Placement in build.md

```
BUILD (all subtasks complete)
  ↓ Checkpoint — BUILD
  ↓ ISC Verify (existing)
  ↓ Gate: BUILD → CLOSE (tests + docs artifact check, existing)
  ↓ Four Questions Gate (actor self-assessment, existing)
  ↓ Docs generation (brana:docs, existing)
  ↓ [NEW: Challenger Gate]
  ↓ CLOSE
```

## Research Findings

- **Reflexion (NeurIPS 2023):** Actor and Evaluator must be different roles. Same model acting and critiquing repeats misconceptions. Verbal self-reflection (`sr_t`) injected at next iteration's context prevents repeating the same mistakes.
- **dim-60 (agent loop architecture):** Judge step is architecturally separated from BUILD (inner loop). validate.sh = MEASURE (structural). Challenger = JUDGE (semantic). Both required; neither substitutes for the other.
- **LoopTrap (arxiv 2605.05846):** P4 Authority Override and P7 Recursive Decomposition are the primary risks. Mitigated by: content isolation (only trusted sources), hard iteration cap (max 2), and unconditional user surface after cap.
- **Challenger agent (current):** Already Sonnet with effort:max — not Opus. CALIBRATION.md defines the rubric. Blocking at score >= 4. M+ discipline check already built in. Fast enough that two-tier (Haiku + Sonnet) is unnecessary.
- **CALIBRATION.md hard thresholds:** 6 conditions always CRITICAL (service unavailability, data loss, workflow breakage, security, untested assumptions, dependency conflict). 5 always WARNING (mitigable-unaddressed, edge cases, performance, unvalidated assumptions, partial coverage).

## Risks

| Risk | Mitigation |
|---|---|
| False positives erode trust | Bounded rubric (specific checklist, not open-ended) + severity-tiered blocking (only score >= 4 blocks) + always-available override path |
| P7 Recursive Decomposition (LoopTrap) | Hard cap: max 2 Challenger iterations before unconditional user surface |
| Haiku misses at potential Tier 1 | No Haiku tier needed — Challenger is already Sonnet, fast enough |
| Context contamination (P4 Authority Override) | Input contract enforced at procedure level: only trusted content allowed |
| Gate fatigue from S build prompts | Default is "Run Challenger" — user skips explicitly; the friction of skipping is intentional |

## Engineering Disciplines

- **DDD:** ADR documenting the mandatory gate decision — architectural change with cross-project impact. Must block all implementation tasks.
- **TDD:** Behavioral test — run a build session, verify Challenger is invoked with correct input (only trusted content), verify blocking and override paths work.
- **SDD:** Update `docs/architecture/features/build-loop-redesign.md` (new gate in architecture section) and `docs/guide/workflows/build.md` (user-facing explanation).
- **Docs:** `/brana:docs update t-1856` after implementation.

## Next Steps

1. Write ADR for mandatory Challenger gate (blocks all impl tasks)
2. Edit `system/procedures/build.md` — insert `### Challenger Gate` section
3. Update `docs/architecture/features/build-loop-redesign.md` — add gate to architecture diagram
4. Update `docs/guide/workflows/build.md` — explain gate to users
5. Behavioral verification — run a build, observe gate fires, test override path
