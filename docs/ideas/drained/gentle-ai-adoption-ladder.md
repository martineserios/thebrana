---
title: gentle-ai adoption ladder — cheap rungs, each validating the next
status: draft
created: 2026-08-01
revised: 2026-08-01 (six-hats challenge — verdict RECONSIDER; corrections applied)
---
# gentle-ai adoption ladder

> Companion to [enforced-delegation.md](enforced-delegation.md), which shaped the *full*
> orchestrator/executor design and had it broken by adversarial review. This doc is the
> corrected approach: small rungs, each useful alone, each producing the evidence that
> justifies or kills the next.
>
> **Revised after a six-hats challenge returned RECONSIDER.** Findings verified against the
> repo and applied below; what changed is listed in [Corrections](#corrections-applied).

## What the earlier review killed

It killed **enforcement** — hooks, run-state, hard gates — for concrete reasons (a gate armed
by the party it constrains enforces nothing; Bash bypasses Edit/Write matchers; background
`claude -p` carries no `agent_id`). It did **not** touch orchestration. Bundling the two and
discarding both was an overcorrection.

But one killed finding **survives into this ladder and must be honoured**: *quota, not
main-session context, may be the scarce resource* (HIGH-5, echoing ADR-059's
hollow-under-subscription result). Every rung below therefore carries a **compute** cost, not
just an authoring cost.

## The precondition, stated honestly

`enforced-delegation.md` sets an explicit gate: *"Delegation returns only if Phase 0 shows
churn-tokens dominate and quota is slack — before any further code."* That task (**t-2591**) is
`pending` and has never run. The first draft of this ladder proposed starting Rung 1 the same
day without acknowledging it.

**Resolution — partial override, with reasons:**

- HIGH-5 concerns **parallel** executors. Rungs 1–3 introduce no parallelism, so Phase 0 does
  not gate them.
- **Rung 4 is `blocked_by` t-2591** — it is the first rung that spins background compute, and
  it is where the quota question becomes real.
- Rung 2 still spends a model call per run; its cost line says so.

## Why orchestration is cheap here

thebrana already has the pieces:

- `system/agents/` — 13 agents. (Frontmatter is **14–19 lines**, not the "5" the first draft
  claimed; the extra fields — `tools`, `disallowedTools`, `permissionMode`, `memory` — are
  exactly the capability-scoping surface a read-only-executor argument depends on.)
- `system/skills/_shared/` — composable procedure blocks are an established idiom
  (`branch-prefix.md`, `model-routing.md`, `challenger-gate.md`).
- `system/skills/_shared/delegation-tdd-checklist.md` — **already the gentle-ai pattern**: its
  header reads "Include this checklist in every agent delegation prompt." It carries only TDD
  criteria — no scope binding, no return contract.
- `verify-gates.md` already spawns `build-evaluator` and inlines `challenger-gate.md`, so
  Rung 2 formalizes a partly-working delegation, not delegation from zero.

**Constraints — both ADRs, not one:**
- **ADR-060** — in-session Task agents cannot write to worktrees (compose in agent, write in
  main). Worktree isolation for runners is built (t-2146 completed).
- **ADR-062** — governs the background-`claude -p`-in-worktree mechanism Rungs 4–5 need.
  Network egress is **not yet restricted**; its hardening task **t-2173 is `in_progress`**, and
  the ADR says do not run unattended batches on untrusted tasks until it lands. **Rung 4 is
  blocked on t-2173 or explicitly scoped to trusted tasks only.**

---

## The ladder

### Rung 1 — Thicken the delegation brief
**Authoring cost:** one markdown file + one populated instance · **Compute cost:** none

Extend `delegation-tdd-checklist.md` into `_shared/executor-brief.md` — gentle-ai's binding
idea minus the cryptography. Fields: task ID · branch · **scope boundary** (paths that may be
touched) · the task's `AC:` lines · **return contract** (exactly what the agent must return,
with a worked example) · the existing TDD checklist.

Build it **by induction from what already works** — `challenger-gate.md`'s scope-boundary and
return-contract shape, `build-evaluator`'s spawn call, `scout.md`'s tools allowlist — not from
a blank draft. Validate by regenerating `challenger-gate.md`'s own spawn call from the new
block (refactor-with-tests, not greenfield).

- **Falsifier — corrected.** Authoring a *template* is a guaranteed pass and tests nothing.
  The rung is only complete when a **populated instance for one real pending phase** exists,
  with its cost recorded in tokens/wall-clock. The information-conservation objection is
  confirmed if composing that instance costs what doing the phase costs.
- **Worth it alone:** four already-running delegation surfaces (challenger, scout, research,
  gemini) gain a scope boundary and return contract they lack today.

### Rung 2 — One real executor agent
**Authoring cost:** one agent file · **Compute cost:** one model call per run (name the model;
this is reasoning-load synthesis, outside `delegation-routing.md`'s haiku carve-out)

**Target corrected.** `verify-gates.md` (167 lines) is *not* read-mostly: it invokes
`/brana:docs` and, on evaluator FAIL, loops back into BUILD implementation writes
(`verify-gates.md:126`). Scope Rung 2 to its genuinely read-only checks only — the gate
evaluation sub-block — leaving the write path out.

- **Validates:** does a phase run cleanly on the brief alone? Can the orchestrator use the
  result without re-deriving the phase's context? (This is the real integration-point test of
  information conservation — a well-placed backstop for Rung 1.)
- **Open question the doc must answer before building:** does the new agent wrap
  `verify-gates.md`, replace it, or coexist? `system/skills/build/SKILL.md` — the orchestrator
  that must change routing for any rung to matter — is a touched file.

### Rung 3 — Mark the roles
**Authoring cost:** a labelling pass · **Compute cost:** none

Add a role marker to the extracted procedure. **Use a distinct key — `mode: execute-only` —
not `disable-model-invocation`**, which already has a live use in **`system/skills/`**
(`challenge/SKILL.md`, meaning "deliberate-invocation-only"; a claim that
`system/skills/domain-driven-design/SKILL.md` also carried it was stale as of 2026-08-13 —
grep found zero matches there — and has been corrected here, per
[t-2830 research](../../research/2026-08-13-matt-pocock-skill-system.md) §3. Note the
scope qualifier: a *different*, vendor-managed `.agents/skills/domain-driven-design/SKILL.md`
tree — 15 skills, symlinked live at `.claude/skills/`, tracked separately in
`skills-lock.json` — does carry the field; it's a distinct surface from `system/skills/`
and was not what the original claim, or this correction, is about). Overloading the
existing field leaves a future reader unable to tell the two apart. `role:` is net-new
vocabulary under `system/` and needs an ADR.

> **Correction (2026-08-17, t-2832):** this rung's proposal (`mode: execute-only`) was killed
> at t-2591's Phase 0 measurement (`churn_share=0.342` against a 0.35 threshold, 2026-08-01) —
> see [ADR-076](../../architecture/decisions/ADR-076-build-receipts-as-executed-evidence.md). Left in place as historical record
> of the reasoning, not an active proposal. `disable-model-invocation` itself (the
> invocation-mode axis, not the executor-role axis this rung proposed) is now documented and
> audited in [testing-validation.md](../../architecture/testing-validation.md) and
> [Skills Architecture](../../architecture/skills.md).

Classification, **not** enforcement — and note it does not resolve the killed finding that
Bash and inline-Read bypass a Skill-tool-only block. Relabeling fixes nothing there.

- **Validates:** whether the role split is coherent across the other nine phases. If they
  can't be classified cleanly, the system-wide version was never viable.

### Rung 4 — A writing executor
**Authoring cost:** one procedure extraction · **Compute cost:** background `claude -p` —
a full session's quota, cold-loading repo context
**Blocked by:** t-2591 (Phase 0 go/no-go) and t-2173 (ADR-062 egress hardening)

**Kill signal — written now, before Rung 1, deliberately** (the killed design's anchoring
mistake was writing the falsifier after the architecture): abandon the writing-executor rung
if Phase 0 shows understanding-tokens dominate churn-tokens, **or** if a single background
executor's quota burn exceeds the same phase run inline by more than the throughput gain.

Candidate note: `specify.md` self-describes as interactive and user-paced — it is a poor
Rung 4 target, since a background `claude -p` cannot pause or ask anything mid-run.
`build-loop` is the honest candidate.

### Rung 5 — Enforcement, only if drift is real
If the model doesn't actually skip delegation when it's easy and useful, enforcement solves
nothing. If it does, the constraint stands: anchor to something **involuntary** (the commit,
the merge, CI) — never to state the constrained party opts into writing.

---

## Off-ladder, independently cheap

No rung, no blockers:

| Idea | Cost | Value |
|---|---|---|
| **Read-only reviewer discipline** for `challenger` / `pr-reviewer` — review an immutable tree, never the worktree | prompt + tools allowlist | reviewers stop drifting into fixing what they review |
| **Honesty contracts** — each gate states what it does *not* prove | one section per gate | stops `validate.sh` / `spec-gate.sh` implying more than they check |
| **Ratchet baseline** — baseline may only shrink, keyed by content not line number | one script | converts fix-or-tolerate warnings into a one-way trend |
| **Machine-token handoff** — closed-vocabulary `nextRecommended` instead of prose routing | small CLI change | removes routing ambiguity between skills |

Note the tension: Rung 2 needs Bash (for `./validate.sh`), which would make it the first
Bash-granted review-side agent — directly against the read-only reviewer discipline above.
Resolve before building Rung 2.

## Engineering disciplines

- **DDD:** ADR required for the `mode: execute-only` frontmatter convention and the
  brief/return-contract schema — both interface contracts. Rung 3 cannot start without it.
- **TDD:** Rung 1's validation *is* its test — regenerate `challenger-gate.md`'s spawn call
  from the new block and diff against the current one. Rung 2 needs a golden-fixture test of
  the agent's returned shape. (Markdown procedure files have no test framework; the
  regeneration diff is the substitute, stated explicitly per the TDD rule.)
- **SDD:** the spec-gate triggers on **task effort** (M/L/XL writing to `system/`), not on rung
  number — `system/hooks/spec-gate.sh`. Rung 1 (t-2597) is effort S, so it did not apply. Any
  rung whose task is M+ needs `docs/architecture/features/executor-delegation.md` first,
  regardless of which rung it is. (Corrected after the challenger gate flagged the original
  rung-based phrasing.)
- **Docs:** new frontmatter convention documented in `docs/architecture/` (never
  `docs/reference/` — generated); `docs/README.md` updated.

## Touched files (named, per challenge finding)

`system/skills/_shared/delegation-tdd-checklist.md` → `_shared/executor-brief.md` ·
`system/skills/_shared/challenger-gate.md` (regeneration target) ·
`system/skills/build/phases/verify-gates.md` · `system/skills/build/SKILL.md` (routing) ·
`system/agents/<new-executor>.md` · `docs/architecture/decisions/ADR-0NN` (role convention).

## Relationship to the receipt track

Receipts (`t-2591`–`t-2595`) are **independent of Rungs 1–3** and neither blocks the other;
**Rung 4 is blocked by t-2591**. Receipts prove *what was done*; orchestration decides *who
does it*. Task `context`/`effort` fields on all five were repaired 2026-08-01 (the `AC:` lines
had been stranded in `description`, invisible to the AC parser).

## Corrections applied

From the six-hats challenge (White/Yellow/Green + a late Black Hat; verdict RECONSIDER),
each verified against the repo before applying:

1. Quota/compute cost added to every rung — it appeared zero times in the first draft.
2. The skipped t-2591 precondition named and resolved as a scoped partial override.
3. Rung 1's falsifier corrected: template alone is a guaranteed pass; a populated instance
   measured in tokens is the real test.
4. Rung 2's target corrected — `verify-gates.md` is not read-mostly (`:126` loops to BUILD).
5. ADR-062 cited; Rung 4 blocked on t-2173 (egress unrestricted).
6. Agent frontmatter corrected: 14–19 lines, not 5.
7. `mode: execute-only` replaces overloaded `disable-model-invocation`.
8. Rung 4's kill signal written now, not after three rungs of sunk cost.
9. DDD/TDD/SDD/Docs sections restored; touched files named.

## Phase 0 has reported — Rungs 2–5 are dead

**t-2591 returned KILL** (2026-08-01). `churn_share = 0.342` against a pre-registered KILL
threshold of 0.35, robust across three measurement bases (0.285 fresh-token, 0.326 turn-count).
Full result and honesty contract: [enforced-delegation.md](enforced-delegation.md) §Phase 0 result.

The measurement found something neither side of the argument predicted: **orchestration is 59%
of build tokens, understanding only 6.8%**, and `cache_read` is **97%** of all tokens consumed
— cost is dominated by *carrying* context across turns, not by reading files or churning tests.

**Status of this ladder:**

| Rung | Status |
|---|---|
| **Rung 1** — thicken the brief | **Alive.** Burns no compute; improves four already-running delegation surfaces regardless. |
| Rungs 2–5 — executor agents, role marking, writing executor, enforcement | **Dead.** Gated on Phase 0; Phase 0 said no. |
| Off-ladder items (reviewer discipline, honesty contracts, ratchet, machine tokens) | **Alive.** Never depended on delegation. |

A post-hoc hypothesis survives (delegation may cut the *turns × context* product by moving
turns into smaller contexts — a different mechanism than exporting churn). It carries no
evidential weight and would need its own pre-registration. It is not a reason to revive
Rungs 2–5 now.

## Rung 1 result (t-2597, 2026-08-01) — **done, falsifier passed**

`system/skills/_shared/executor-brief.md` shipped. Six fields, each induced from a delegation
already running in production (`challenger-gate.md`, the build-evaluator spawn at
`verify-gates.md:93`, `agents/scout.md`) — not drafted blank, as the challenge required.

**Validation:** regenerating `challenger-gate.md`'s spawn call from the template reproduced
**4 of 6 fields verbatim**. The two gaps are in the original, not the template: its input trust
boundary is caller-side only and never told to the agent, and it has no "report what you could
not determine" instruction. Both logged for a future fix.

**Falsifier — PASSED.** The rung was only complete with a populated instance whose authoring
cost was recorded. Instance: a full brief for t-2593 (`brana receipt mint|validate`, M effort).

| | Cost |
|---|---|
| Composing the brief | ~2 min, no new file reads (reused task spec already in context) |
| Doing the work it briefs | M effort — hours |

Composing the brief costs roughly two orders of magnitude less than the work it scopes, so the
**information-conservation objection does not bite at the brief-authoring level**. Caveat: this
author already held t-2593's spec in context; a cold author must first read the task — seconds,
not hours.

**This independently agrees with Phase 0.** t-2591 measured understanding at just 6.8% of build
tokens. Writing a brief is an understanding-type activity, so it should be cheap — and it is.
Two different measurements, same conclusion, reached independently.

`delegation-tdd-checklist.md` was **retained, not absorbed** — one live call site
(`build/phases/build-loop.md:78`) plus documentation in `docs/architecture/extending-agents.md`.
The brief is the envelope; the checklist is the code-output done-criteria block.

**Challenger gate: PROCEED WITH CHANGES** (highest severity 3, none ≥4). Three findings fixed in
this task: the field-order inconsistency in the brief's own template (order is now explicitly not
part of the contract), a miscounted call-site claim, and the SDD scoping question — resolved
factually, since **t-2597 is effort S**, so the M+ spec-gate never applied. The gate correctly
flagged that its own scoping criterion in this doc was rung-based where the real hook
(`spec-gate.sh`) is effort-based; the criterion below is corrected to say so.

## Next step

The off-ladder items — reviewer discipline, honesty contracts, ratchet baselines, machine-token
handoff. Not the executor rungs; Phase 0 closed those.
