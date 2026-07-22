---
title: Brana v3 — The Graduated Self-Evolving Process Loop
status: draft
created: 2026-07-19
---

# Brana v3 — The Graduated Self-Evolving Process Loop

> Brainstormed + adversarially challenged 2026-07-19; second-pass challenged 2026-07-21. Status: draft v3.3 (integrated).
> Foundation: [agentic-primitives.md](../architecture/agentic-primitives.md) · [2026 gap analysis](../research/agentic-engineering-2026-gap-analysis.md) · [loop-engineering + Pi](../research/loop-engineering-and-pi.md) · [gentle-ai extraction](../research/gentle-ai-productization-extraction.md) · challenges: [2026-07-19](../reviews/brana-v3-challenge-2026-07-19.md) · [2026-07-21](../reviews/brana-v3-challenge-2026-07-21.md)
> Elaborations (2026-07-20): [backlog-v3 schema](../architecture/features/backlog-v3-schema.md) + [ADR-065](../architecture/decisions/ADR-065-epic-as-hierarchy-top.md) (the task-contract backbone) · [skills-as-loops](skills-as-loops.md) (waves 4–5 elaboration + deferred pipeline north star, → t-2278)

## Problem

Brana's primitives are individually strong (40 hooks, 35 skills, backlog, memory, workflows) but predate the 2026 native wave (Workflows, Teams, native subagent memory) and mature loop engineering. The system is powerful but scattered: loops without independent verification or encoded stop conditions, routing as prose, autonomy attempted once as a sidecar system that daily work never fed. The human operates the middle layers by hand instead of designing the loop that operates them.

## Direction

- **Approach:** spec the v3 target, migrate in gated waves. No clean slate.
- **North star:** the self-evolving process loop — the system runs designed processes, parallelizes, judges/challenges, verifies independently, and improves its own process each iteration.
- **Demoted deliberately:** efficiency = hard constraint · simplification = method (net-negative surface per wave) · platform/public path = byproduct of the core/packs cut.
- **Scale:** weeks+ epic, wave-gated.

## Design principles

1. **One system, no sidecar.** Autonomy machinery lives inside the daily build/close/backlog flow — never as a parallel architecture with its own vocabulary. A capability daily work doesn't feed is a capability that starves.
2. **Contract-driven loops.** The task is the machine-readable interface: `execution:` marker (default-deny eligibility), `AC:` lines (mechanical verification), `blocked_by`/priority/effort (sequencing + shape features). A loop is only as verifiable as its contract is authored — so the cockpit helps write ACs at task creation, and AC adoption is tracked work (measured 2026-07-20: only 38 of 2,156 tasks carry non-empty `acceptance_criteria`, ≈1.8% — earlier ~11–13% estimates did not survive measurement).
3. **The worktree is the sandbox.** Isolation is git-topological: ephemeral worktree per task with explicit base resolution, PR-only output, human merge gate, hooks on every commit. No syscall-level sandboxing as a precondition — it fought the OS (PID-namespace hangs, executor kills, AppArmor blocks) while the git layers did the real protecting. Heavy sandboxing returns only if v3 ever runs genuinely untrusted code.
4. **Defer, don't guess or halt.** When a loop hits a human-only decision it parks a NEEDSHUMAN question (via `brana remind`) and continues with other work. Escalation is a lane, not a stop.
5. **Autonomy is earned from evidence, per task shape.** Graduation applies to *shapes* — (kind, effort, tags, file-surface, AC-presence) — never to individual tasks or whole processes. Thresholds are a transparent, auditable rule table (≥K live runs ∧ ≥95% merged-clean ∧ 0 rejected-as-harmful ∧ never P0), continuously evaluated: shapes auto-demote when they start failing. No learning before the soak (≥50 real outcomes / ≥2 weeks) — learning from a thin ledger is learning from noise.
6. **Every loop starts observable — two tiers.** **Tier A (pure observe):** read + ledger-write only; the test suite proves zero task/git/reminder/memory mutation. Default for report-only loops. **Tier B (scoped-mutation):** for loops whose entire job is to write somewhere (LEARN → memory/patterns) — writes are permitted at L1 only if a test proves them *inert*: they gate nothing (no ranking, no downstream action, no auto-apply) until an explicit human promotion step. Generalizes the `ac_state:proposed` real-but-inert pattern (t-2283). LEARN ships Tier B, not Tier A (resolved 2026-07-21 challenge finding #3, t-2287).
7. **Explicit compute chain, bounded.** agy/Gemini first while its (small, fast-exhausting) quota lasts → automatic engine-switch to Claude (included SDK credit pool, then `claude -p` Haiku/Sonnet), governed by a **hard per-run token ceiling**. On ceiling hit: checkpoint the queue cursor and stop cleanly — no defer-to-reset. The next scheduled run resumes from the checkpoint. Queues drain within a bounded number of nights, never stall indefinitely; the original "always drain" claim overstated an unbounded-Claude assumption the fallback pool doesn't actually have (resolved 2026-07-21 challenge finding #2, t-2286).
8. **Adopt, don't build; delete as you go.** Prefer native primitives and shipped brana machinery (validate.sh, build-evaluator, hooks, remind, worktrees); every wave removes more surface than it adds.

## The graduated autonomy ladder

Every loop climbs: **L1 report-only → L2 assisted (cockpit) → L3 unattended.**

- **L1** — the loop watches and reports. Enforced by the observe invariant (principle 6). Zero risk; builds the habit and the ledger.
- **L2 — the cockpit, v3's center of gravity.** The system prepares everything (parallel candidates, judged, challenged, verified, diffed); your decision takes seconds. Each review writes an **outcome-ledger row** (merged-clean / merged-with-edits / rejected — an explicit verdict, never a raw approve click). For a solo operator this is where most work lives, permanently — that's a feature, not a failure.
- **L3 — earned, per shape** (principle 5). Requires: objective verifier + encoded stop conditions + the shape clearing the rule table on real ledger evidence. Judgment-heavy work is capped at L2 by design. "Merge without a human" exists in v3 — but only here, and ADR-060's "agent never merges" invariant is formally amended (not silently violated) to admit it.

**Verification gate stack** (independent of the worker, in order): NEEDSHUMAN check → **non-empty diff** (empty diff = nothing done → abort; catches silent no-ops AC checks miss) → `validate.sh` → AC check (build-evaluator vs the task's `AC:` lines). **Blast-radius constants:** consecutive-failure kill at 3 · per-task timeout · batch cap · per-loop cost ceiling.

## Async learning (L6 decoupled)

**Requirement: ASYNC.** Learning extraction runs outside interactive sessions (queue written at close in ~30s; a worker drains it). Budget separation is a free bonus, not a requirement.

**Worker compute chain (per run, per entry):** agy/Gemini first (free) → on quota exhaustion, **switch engine to Claude and keep processing** (Agent SDK worker on the included SDK credit pool — $100–200/mo already in the subscription — or `claude -p` Haiku/Sonnet) — **up to a hard per-run token ceiling**. On ceiling hit, checkpoint the queue cursor (last-processed entry ID) and stop; the next scheduled run resumes from there. The prior skip-and-defer-until-reset behavior was the bug (daily exhaustion → deferral → deadlock, the prime suspect for the stalled queue) — the fix isn't unbounded Claude spend, it's bounded spend + guaranteed resume (resolved 2026-07-21 challenge finding #2, t-2286). Requires a curation gate — extraction volume (~48/night) without scaled DECAY becomes memory noise.

## Wave plan (v3.2)

Ordering principle: *each wave proves the ladder's next rung while paying for the one after it.* ADRs, tests, and docs ride inside the wave they gate. Task unit = one backlog task; discipline tasks count toward the cap.

| Wave | Delivers | Deletes |
|---|---|---|
| **1 · GROUND TRUTH + SUPERSESSION** | Diagnose the two claimed failures (stalled extraction queue — check agy-quota deferral first; stale CALIBRATION.md read path). Superseding ADR that retires the prior autonomous-runner doc cluster (the-orbit.md, substrate-end-state.md, substrate-primitives.md index entries) while folding its mechanics into this design; scope the ADR-060 amendment; fix the ADR-062 filename collision; re-parent/cancel t-1994/t-1995. Native `memory:` frontmatter migration for challenger/build-evaluator/debrief-analyst. | Prior autonomous-runner doc cluster (superseded) · stale memory read paths · t-1994/1995 |
| **2 · LEARN AUTONOMOUS** | The async worker on the compute chain (agy-first → Claude engine-switch, never defer). Curation gate + run/token ceiling *inside this wave*. Observe-invariant test for the worker. Honest label: proves unattended execution on a low-risk loop. Resolve close-FULL scope per ADR-052 (escape hatch survives). | agy skip-and-defer stall path · close FULL sync-extraction weight |
| **3 · VERIFY** | Independent verifier extending build-evaluator + validate.sh, with the four-step gate stack (incl. empty-diff check); standalone ADR. goal-completion.sh migrated guard-by-guard (presence interlock, base_ref pin, Modified/Added split, allowlist, audit trail — each a named carry-forward); tests ported; its 10+ consumers migrated as explicit tasks. Blast-radius constants encoded per loop. Non-AC fallback: stays L2. AC-authoring adoption task (cockpit-assisted AC writing). | goal-completion.sh (only after consumer migration completes) |
| **4 · COCKPIT + ROUTER** | Cost-baseline spike first (3 real tasks; fallback N=1 judge-only). Fast-approve iteration: parallel candidate prep in ephemeral worktrees → judge via shipped verify-findings workflow → verified diff → approval as PR merge through the existing gate chain — no new bypass surface. NEEDSHUMAN park lane via `brana remind`. Every review writes an outcome-ledger row. Per-phase model/effort profiles built in. | Manual phase invocations · prose routing rules |
| **5 · GRADUATE + CUT** | Ships the graduation **machinery** — outcome ledger, transparent per-shape rule table, auto-demotion — not a graduation guarantee on a wave-5 timeline (resolved 2026-07-21 challenge finding #1, t-2285: at solo throughput ≥1 task/day, 2 weeks yields only 14 outcomes across ALL shapes, nowhere near ≥50 per-shape). Requires shape coarsening (**cap ≤10 shapes**, not a fine-grained (kind,effort,tags,file-surface,AC) combinatorial space) as the only path any shape becomes reachable at all; even then, a shape's first graduation is realistically **months** past wave-4 shipping, not a wave-5 checkbox. Core vs process-packs boundary (→ t-2090). Hook tier-model page. | v2 remnants retired against the v3 spec |

**Wave contract (non-negotiable):** ≤10 tasks/wave · ships into daily use · deletes ≥ adds · next wave gated on previous shipping · tests and docs ride inside waves · a stop-condition ceiling exists from wave 2's first unattended run.

**Elaborations (2026-07-20).** Two docs extend this plan rather than fork it:
- **[backlog-v3 schema](../architecture/features/backlog-v3-schema.md) + [ADR-065](../architecture/decisions/ADR-065-epic-as-hierarchy-top.md)** — the task-contract backbone: the three-axis task (subject · tags · waves) is the *drainable queue* every wave here needs, and the self-contained packet (spec · AC · `ac_state` · `log`) is the contract loops verify + the graduation ledger wave 5 reads. Lands in the backlog-cli wave; challenged deep 2026-07-20 (all findings applied).
- **[skills-as-loops](skills-as-loops.md)** — elaborates **wave 4's router** (behaviors re-derived against the primitive palette — skill · workflow · loop · goal; each process ends in a router, not a prose handoff) and **wave 5's core/packs cut** (the audit that finds which behaviors become loops vs stay skills; a real 34-skill pass right-sized it — most stay skills). Its **task-as-workpiece pipeline** is the explicit *final-wave north star*, deferred until single loops prove clean handoffs. Graduation tracked by **t-2278** (blocked on the schema landing).

**Rejected:** clean slate · spec-only wave · cockpit-before-verifier · Routines for stateful jobs (no local state access; same billing pool) · syscall sandboxing as autonomy precondition · deleting goal-completion.sh atomically · "L3 day one" labeling.

## Success metric

Daily development runs through the cockpit (≥1 loop-driven task/day) · LEARN drains its queue unattended within a bounded per-night token ceiling, resuming from checkpoint across nights if needed · total system surface (hooks+skills+rules) smaller than the 2026-07-19 baseline.

**This metric governs L2 adoption, not an L3 timeline.** L3 graduation is evidence-gated per shape (principle 5) and may take months past wave 5's shipping; wave 5 delivers the graduation machinery, not a guaranteed graduation date (resolved 2026-07-21 challenge finding #1, t-2285).

## Lessons encoded from the first autonomous-runner attempt (2026-06, ADR-059/060 line)

The prior attempt had the right engineering rigor (locked decision tables, tested invariants, explicit interfaces — a bar v3.1 adopted after the challenge) attached to the wrong integration model. Its failure modes, now design principles: it was a **sidecar** daily work never fed (→ principle 1); its **learning gate was circular** — graduation needed outcomes that manual whitelisting never produced (→ cockpit outcomes as a side effect of daily work); its **autonomy was binary** with no fast-supervised middle (→ L2 as center of gravity); it made **full worker isolation a precondition** (→ principle 3); and its **compute assumptions were naive** about agy quota (→ principle 7). Its mechanics that v3 absorbs natively: the task contract, the staged observe→act rollout with tested observe invariant, shape-based rule-table graduation with auto-demotion, the ledger + soak gate, defer-don't-halt, the verification gate stack, ephemeral-worktree isolation, and the ADR-050 blast-radius constants.

## Challenge verdict (3-lens adversarial quorum, 2026-07-19)

Unanimous RECONSIDER on the v3.0 draft; all findings addressed in v3.1/v3.2. Full reports + corroboration matrix: [brana-v3-challenge-2026-07-19.md](../reviews/brana-v3-challenge-2026-07-19.md). Highlights: unreconciled prior architecture (→ wave-1 supersession + this integration); Routines factually unusable for stateful learning (→ local worker, verified); "2 live failures" motivation corrected to diagnoses; goal-completion.sh deletion replaced by guard-by-guard migration; verifier scope limited by ~11% AC coverage (→ AC-authoring work); wave-1 task cap overflow (→ split waves); "L3 day one" mislabeling (→ honest labels + early ceilings).

## Second challenge disposition (2026-07-21, findings #1–#3)

Fresh adversarial pass on v3.2 ([brana-v3-challenge-2026-07-21.md](../reviews/brana-v3-challenge-2026-07-21.md)) found three HIGH-severity load-bearing contradictions, all resolved in this revision (v3.3):

- **#1 soak gate unreachable at solo throughput** (t-2285) → wave 5 ships graduation *machinery*, not a graduation *guarantee*; shape coarsening (≤10 shapes) is now an explicit precondition. See wave plan + success metric.
- **#2 compute chain moves, doesn't remove, the bottleneck** (t-2286) → principle 7 now specifies a hard per-run token ceiling + checkpoint/resume, replacing the unbounded-Claude-fallback assumption. See principle 7 + async learning section.
- **#3 observe-invariant contradicts LEARN's actual job** (t-2287) → principle 6 now specifies two tiers (pure-observe vs scoped-mutation), generalizing the `ac_state:proposed` inert-write pattern (t-2283) so LEARN can ship at L1 without violating the invariant's intent.

Not resolved here (tracked separately): #4 (deletes≥adds unit — folded into t-2283's demand-driven field adds), #5 (v3-done definition — open question for the epic plan), #6 (ADR-065 sequencing — captured as t-2284, `blocked_by t-2281`; t-2281 has since closed).

## Risks

| Risk | Mitigation |
|---|---|
| Spec sprawl — waves never finish | Wave contract: ≤10 tasks, ships to daily use, gated progression |
| Cost blowout — loops disabled to save quota | Per-loop ceilings from wave 2; compute chain spends free quota first; routed cheap models for prep |
| Comprehension debt | Ladder + outcome ledger: graduation only from explicit review verdicts; judgment work capped at L2 |
| Verifier weaker than it looks | Shape graduation needs real merged-clean history, not verifier claims; auto-demotion on failure |
| Learning loop becomes noise generator | Curation gate + DECAY scaled with extraction volume (wave 2) |
| Contract under-authoring starves verification | AC-authoring as tracked work; cockpit-assisted AC writing (waves 3–4) |
| CC-native obsoletes custom infra mid-migration | Adopt native primitives; build only thin deltas |

## Second-order effects

- **The v3 spec as forcing function:** every one of the 58 idea docs gets re-read against it — most retire; sprawl shrinks as a side effect of wave 1.
- **Async learning on a drained queue:** extraction volume grows unchecked → memory bloat unless curation scales — hence the curation gate inside wave 2.

## Next steps

1. Plan the epic in the backlog (5 waves, wave contract as AC lines).
2. Wave 1 kickoff: the two diagnoses + superseding ADR + memory migration.
3. Visual explainer: [brana-v3-design.html](brana-v3-design.html) — the canonical copy, versioned next to this doc (open directly in a browser). A published artifact copy may also exist but is account-bound; the repo file is the source of truth.
