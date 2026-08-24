---
title: Multi-agent judgment panels with dynamic escalation — JUDGE step diversity + PLAN-time decomposition
status: draft
created: 2026-08-14
task: t-2887
related: t-2889 (wave-level parallelism follow-on), t-2826 (loops library), ADR-059, ADR-079, ADR-080
---
# Multi-agent orchestration in the loop/wave pipeline

> **Component of The Brana** · owns: judgment panels at JUDGE/PLAN, diversity axes, probe GO · see [the-brana.md](../architecture/the-brana.md) §Gate

> Brainstormed 2026-08-14. Work in progress. Retargeted mid-session (Round 2) — see
> Discussion below. Original framing (task-execution/ACT-step panels) is preserved in
> git history for this file; it was explicitly rejected, not the current scope.

## Problem

The wave-drain loop (ADR-079, ADR-080) pulls one task per `wip_limit` slot and runs it
through a single `/brana:build` executor, serially. Multiple wave-4 tasks this session
(t-2842, t-2843, t-2845) went through a challenger RECONSIDER → fix → PROCEED cycle —
real, valid findings caught by a single fresh-context reviewer, after a single executor
had already produced a full implementation. The original question (2026-08-14, during
wave-4 drain supervision): should the loop's *execution* step use role-specialized
multi-agent orchestration, the way `hive-mind` already does for question-answering?

**That framing was rejected in discussion (see Round 2).** The real opportunity is
narrower and in a different place: multi-agent judgment where genuine ambiguity/open-
endedness actually lives in this pipeline — the JUDGE step of a build beat, and PLAN-time
decomposition — not the ACT step of an already-atomic task.

## Research findings

(These findings shaped the *mechanism* answer and still hold; they don't specifically
argue for the ACT step — see Round 2 for why the target moved.)

- The mechanism already exists and is exactly the right shape: Anthropic's Claude Code
  "Dynamic Workflows" product docs explicitly describe orchestrator-workers /
  parallel-review patterns — "independent agents adversarially review each other's
  findings... or draft a plan from several angles and weigh them against each other" —
  as a flagship `Workflow` use case. Anthropic's own bundled `/deep-research` workflow
  does fan-out → cross-check → vote → synthesize in production.
- Conceptual taxonomy (Anthropic, "Building Effective Agents"): *Workflows* = predefined
  code paths, for **fixed/predictable subtasks needing consistency**; *Agents* =
  dynamically self-directing, for **open-ended problems needing trust in
  decision-making**. This distinction is what drove Round 2's retarget — an atomic,
  approved, pulled task is by definition the fixed/predictable case.
- `hive-mind.js` (Convene → Verify → Synthesize) classifies as a composition of two named
  workflow patterns (parallelization/voting + evaluator-style critique) — correctly
  placed as a `Workflow`, not misused.
- `orchestrator-workers` is one of Anthropic's five canonical workflow patterns — "a
  central LLM dynamically breaks down tasks and delegates to worker LLMs." Direct
  precedent for fan-out at decision points, wherever those actually are in our pipeline.
- `docs/architecture/decisions/ADR-059-multi-agent-substrate-selection.md` already routes
  "in-session, deterministic find→verify→synthesize" work to native `Workflow` and names
  `hive-mind`/`verify-findings`/`sweep` as the three reusable blocks.
- Earlier attempt at "multi-agent" in this project (`brana-v2-compute-model`, ~83 days
  old) planned a Ruflo-based hive-mind/swarm/quorum layer (t-1595–t-1607); its quorum-ADR
  task (t-1638) was cancelled. In hindsight this tracks: ruflo's `hive-mind_*`/`swarm_*`
  MCP tools turned out to be subscription-gated theater (records + self-votes, nothing
  actually thinks) — exactly why the native `hive-mind` skill + `Workflow` tool exist as
  the real replacement. Build on the native substrate, not ruflo.

## Discussion

### Round 1 (resolved) — wip_limit vs. task-level orchestration are independent levers

**Assumption challenged:** that "add parallelism" is one dial, and `wip_limit` is just
in the way of it.

**Resolution:**
- **Wave-level parallelism** (raising/removing `wip_limit`) = multiple *different* tasks
  each getting their own worktree/branch/build-framework instance concurrently. Tied to
  the documented `tasks.json`/worktree race incidents (t-2216/t-2206) and to how much
  concurrent build-CLOSE review load the human merge valve can absorb.
- **Task-level parallelism** (`Workflow`-based orchestrator-workers *inside* one pulled
  task) = one worktree, one branch, one CLOSE. Compatible with `wip_limit:1` unchanged.

Split off as its own follow-on: **t-2889** ("Explore wave-level parallelism"),
`blocked_by` this task — sequenced after, not dropped.

### Round 2 (resolved) — task-level ACT-step panels are the wrong target

**User's challenge (2026-08-14):** a task pulled by the drain loop is supposed to be
atomic — small, well-scoped enough to use *simpler* models, not more agents. Spawning a
multi-agent panel to execute an already-atomic task is a token-cost mismatch. Multi-agent
is probably more useful somewhere else in the pipeline — a different loop, or a different
step of this loop.

**This holds up against the research, not just intuition.** Anthropic's own framing
(fixed/predictable → workflow/single-agent; open-ended/judgment → multi-agent) says the
ACT step of an atomic, already-approved task is exactly the *wrong* place for a panel —
if a pulled task still needs multiple perspectives to execute correctly, that's a signal
it wasn't decomposed narrowly enough, which is a **planning** defect surfacing as an
**execution**-time cost, not a reason to add execution-time machinery.

**Where the real ambiguity lives, with existing precedent:**

1. **The JUDGE step, not the ACT step.** t-2826 (loops-library) already sketches this:
   *"judge: strongest + DIVERSE (different model or agy challenger-lane — uncorrelated
   blind spots; same-model self-review is the weakest judge even fresh-context)."*
   Challenger + evaluator are already two distinct roles, but each a *single* instance.
   A small diverse panel (e.g. security lens / scope-creep lens / reuse lens) is cheap —
   review work, not re-implementation — and it's exactly where wave-4's real
   RECONSIDER→fix cycles (t-2842, t-2843, t-2845) actually happened this session.
2. **PLAN/DECOMPOSE, a different loop entirely.** Genuinely open-ended scope-cutting —
   comparing decomposition strategies for an epic before tasks become atomic — is where
   a judge-panel (N attempts from different angles, scored, synthesized — Workflow's own
   documented pattern) earns its cost. This brainstorm is itself a live example of the
   pattern working where it belongs: `/brana:brainstorm`'s own M+ path already spawns a
   hive-mind challenger panel on *shaped ideas*, not on atomic execution.

**Decision (user, 2026-08-14): retarget entirely.** Drop the ACT-step/task-execution
framing. t-2887 now covers both (1) JUDGE-step diversity and (2) PLAN-time decomposition
panels — subject/context to be rewritten accordingly.

## Constraints

- **Non-negotiable:** never weakens the human merge valve (ADR-060/079) — the loop still
  never merges to `dev`.
- **Cost/token usage must be actively managed**, not open-ended — user flagged this
  explicitly, and it's part of *why* Round 2's retarget happened (a panel on every atomic
  ACT step doesn't pay for itself; a small diverse panel at JUDGE time, or a panel at
  PLAN time which runs far less often, both have a much better cost/value ratio). Should
  respect the loops-library "model per beat component" design already sketched in t-2826
  (haiku for mechanical/classify steps, sonnet/opus for judgment steps).

### Round 3 (resolved) — no new mechanism needed; two existing skills map onto the two targets

- **JUDGE-step diversity** = judging *one artifact* (a build diff) against multiple
  concern-lenses with a majority-confirm verdict → exactly the `verify-findings` skill's
  shape ("N diverse-lens skeptics per finding; holds only with strict majority").
- **PLAN-time decomposition panels** = generating *multiple candidate strategies* for an
  open question and synthesizing the winner → exactly the `hive-mind` skill's shape
  (N lens-locked workers → adversarial verify → synthesize).

So the work is **integration, not mechanism design**: wire `verify-findings` into the
build beat's JUDGE/CLOSE gate, wire `hive-mind` into `plan.md`/`decompose-mode.md`.
Mechanism risk already retired by the research (ADR-059 + Anthropic's own docs).
Sizing (split into 2×S vs one M) deliberately deferred to SHAPE.

### Round 4 (resolved) — the motivating evidence was backwards; measurement first

**Devil's-advocate challenge:** the RECONSIDER→fix cycles cited as motivation
(t-2842/43/45) are the single challenger *succeeding*, not failing. Zero recorded
escaped defects exist to justify a panel — nobody measures what the single judge missed.
A panel might re-catch the same findings at 3× cost.

**Decision (user, 2026-08-14): both mitigations.** (1) The quick experiment is reframed
as a **measurement**: run panel and single judge side-by-side on the same real diffs,
count findings the single judge missed that survive verification — no measured delta →
no build. (2) **Start logging escaped-defect events at the merge valve** (things the
human catches that challenger passed), so the evidence base builds itself over time.

### Round 5 — community/research evidence (scout findings, 2026-08-14)

Full report: [docs/research/2026-08-14-llm-judge-panels.md](../research/2026-08-14-llm-judge-panels.md)
(sources are arXiv + industry, linked inline there). Three direct hits on this design:

- **Side-by-side single-vs-panel comparison on the same cases is the field's stated
  best practice** for validating a panel — the Round 4 experiment design is externally
  confirmed, not homegrown.
- **Correlated errors are the #1 documented failure mode** ("Nine Judges, Two Effective
  Votes", arXiv 2605.29800): panels whose members share training/architecture gain
  ~nothing — unanimous agreement from same-model judges is false confidence. Diverse
  *lenses* on the *same Claude model* is exactly this trap. What matters is
  **model/vendor diversity** — directly validating t-2826's already-sketched agy
  (Gemini) challenger-lane line ("uncorrelated blind spots"). A real panel here should
  include a non-Claude judge, not just three Claude lenses.
- **Strict-majority aggregation is warned against** — "disagreement is often the most
  actionable signal; synthesize divergent finds, don't suppress them." This challenges
  wiring `verify-findings` in unmodified: its tie→FALSE_POSITIVE rule would silently
  drop exactly the split verdicts that should surface to the human valve as their own
  signal class. The JUDGE wiring needs a disagreement-surfacing variant.
- Supporting numbers: multi-pass review measured +43.67% F1 / +118.83% recall over
  single-pass (Zylos, n=10 Gemini-Flash runs), plateau at n=5-10; heterogeneous
  specialized panels hit +13.5pp accuracy at 1.3× cost (arXiv 2604.13717). Panel size
  sweet spot: **3-5, parallel independent passes (never cascading), blind to each
  other's outputs**.

### Round 5b — orchestration lessons (second scout, 2026-08-14)

Full report: [docs/research/2026-08-14-multiagent-orchestration-lessons.md](../research/2026-08-14-multiagent-orchestration-lessons.md).
Sources: Anthropic's multi-agent guidance, Cornell equal-token-budget study (arXiv
2604.02460), multi-agent debate failure-mode studies, 2026 production surveys.

- **Round 2's retarget is confirmed almost verbatim by the literature:** "Planning
  *discovery* (exploring multiple candidate plans in parallel, judging each) benefits
  from specialization. Planning *execution* (following a known plan) does not."
  Sequential multi-agent handoffs perform 39–70% *worse* than a single agent
  (context loss per handover). Peer-to-peer agent collectives fail catastrophically
  (17× error amplification) — only orchestrated parallel + synthesis shapes shipped.
- **The user's cost instinct is the 2026 consensus:** multi-agent uses 3–10× tokens for
  equivalent tasks; under equal token budgets single agents win most comparisons
  (Cornell); Anthropic's own research system paid ~15× tokens for its gains. Consensus:
  *start single-agent, escalate only on measured evidence* — exactly Round 4's decision.
- **The escalation valve (equilibrio dinámico) is a named gap in the field:**
  "Failure-Based Escalation — start single, escalate on failure signal — proposed in
  theory; **no shipping implementation found**." Opportunity: genuinely novel, and
  brana's loop discipline already supplies what the research says is missing — robust
  *ungameable* triggers (challenger RECONSIDER verdicts, severity thresholds,
  judge-splits, escaped-defect log entries) instead of the under-explored learned
  confidence scores. Risk: no proven pattern to copy; we'd be first-mover on our own
  evidence.
- Multi-agent's three legitimate narrow wins per Anthropic: context isolation,
  independent parallelization, tool specialization (15+ tools). Our two targets (JUDGE
  panels = independent parallel verification; PLAN panels = parallel plan discovery)
  both fall inside the legitimate-win zone; the rejected ACT-step panel falls outside it.

## Risks (pre-mortem, 2026-08-14)

Both named risks worry the user; the governing principle chosen: **equilibrio dinámico**
— the system must be able to adjust panel usage on demand, not freeze it into static
rules.

- **[A] The "atomic tasks never need multi-perspective help" assumption proves too
  absolute.** Some tasks will slip through planning under-decomposed and genuinely need
  panel help at execution time. *Mitigation — and the design consequence of equilibrio
  dinámico:* no static "panels never at ACT" rule. Instead an **escalation valve**: the
  single executor or single judge can flag "this needed more perspectives" and a panel
  is spawned on demand, per-instance. Same shape as t-2826's already-sketched
  escalation-on-uncertainty model routing (haiku → sonnet), applied one level up:
  escalation-on-signal for *agent count*, not just model tier. The flag also feeds back
  to planning ("this task arrived under-decomposed") so the root cause gets fixed, not
  just compensated.
- **[B] Never gets built** — sits in docs/ideas/ like the brana-v2-compute-model swarm
  phase, whose quorum-ADR task (t-1638) was cancelled unshipped. *Mitigation:* what's
  different this time — (1) real substrate: `hive-mind`/`verify-findings` exist and run
  today, vs t-1638's ruflo tools that turned out to be theater; (2) integration-sized
  scope, not new-mechanism scope; (3) a live precedent the same session the idea was
  born (wave-4's RECONSIDER cycles). Keep the build tasks S-sized and drain-eligible so
  the wave pipeline itself pumps them, rather than relying on someone remembering.

## Final shape (approved 2026-08-14)

**Core:** panels where ambiguity lives — JUDGE step + PLAN/DECOMPOSE — never the ACT
step; `wip_limit` untouched (wave-level parallelism = t-2889, sequenced after); human
merge valve untouched.

**Design constraints, each evidence-backed (Rounds 4–5b):**

1. **Measurement before build.** The experiment runs a panel vs. the single challenger
   side-by-side on the same real diffs; count findings the single judge missed that
   survive verification. No measured miss-delta → no build.
2. **Panel = 3–5, parallel, blind, model-diverse.** Must include a non-Claude judge
   (agy/Gemini challenger lane, per t-2826) — same-model lens-only panels are the
   documented correlated-error trap. Independent parallel passes, never cascading.
3. **Disagreement surfaces, never suppressed.** The JUDGE wiring needs a
   disagreement-surfacing variant of `verify-findings`: split verdicts go to the human
   valve as their own signal class instead of tie→FALSE_POSITIVE.
4. **Escalation valve on hard signals** (challenger RECONSIDER severity, judge-splits,
   escaped-defect log entries — never self-assessed confidence). Novel: the literature
   names failure-based escalation but found no shipping implementation; brana's
   ungameable-signal loop discipline supplies exactly what the field says is missing.
5. **Escaped-defect logging at the merge valve starts now** — cheap, and it is the
   evidence base every later graduation decision runs on.

### Engineering disciplines

- **DDD:** panel-escalation contract likely lands as an ADR-080 amendment or small
  standalone ADR (who decides escalation, on what signal, denied verbs for panel
  members). Decide in the research phase.
- **TDD:** skill-procedure edits verified via supervised proof-of-life beats (t-2845
  precedent); shared bash-block + test where real logic exists (t-2843 precedent).
- **SDD:** loops-library judge contract (t-2826 doc), epic-drain/drain-loop JUDGE step,
  ADR-059 reusable-blocks list.
- **Docs:** ride the impl commits per repo convention.

### Second-order effects

- Panel at JUDGE → more findings pre-merge → human valve reads longer stacked verdicts —
  verdict rendering (t-2857/t-2825) becomes more load-bearing; watch attention cost.
- Escalation-valve flags accumulate → an under-decomposition metric for planning emerges
  as a by-product — exactly the feedback signal PLAN-time panels would train on.

## Probe design (retrospective, zero new build work)

The measurement experiment can run **retrospectively against wave-4's own history** —
no new builds needed, because the ground truth is already recorded:

- **Corpus:** the 6 completed wave-3/4 diffs (t-2840–t-2845). Each has its single
  challenger's iteration-1 findings recorded verbatim in task notes, plus what the
  evaluator/fix commits later surfaced — a free answer key.
- **Method:** run a 3-judge panel — 2 Claude judges with distinct narrow briefs (e.g.
  security/injection, contract-drift/scope) + 1 agy (Gemini) judge for model diversity —
  **blind** on each historical diff, with the same challenger brief the original run used.
  Parallel independent passes; judges never see each other's output or the recorded
  findings.
- **Metric:** (a) verified real findings the panel surfaced that the recorded single
  challenger missed (each candidate miss gets an adversarial verification pass before
  counting); (b) total panel token cost vs. the original single-challenger cost.
- **Decision rule:** ≥1 verified real miss across the corpus at acceptable cost → go
  (build the two S tasks). Zero verified misses → no-build; keep the single judge and
  the escaped-defect log, revisit only when the log accumulates evidence.

## Probe outcome (2026-08-14): GO — and the sweet-spot levers

Probe ran same-day: [docs/research/2026-08-14-judge-panel-probe.md](../research/2026-08-14-judge-panel-probe.md).
**4 clean verified misses (3× sev-4) on 6 diffs that had all passed a single
challenger**, at ~2.5–3.5× cost. Decision rule met decisively.

Engineering levers derived from the probe's own data (the design input for the JUDGE
wiring task):

1. **Claude-only panels (user constraint, 2026-08-14)** — agy/Gemini runs on a
   free-tier account and always fails (explains the probe's silent Claude fallback);
   no cross-vendor lane anywhere. Correlated-error mitigation comes from
   within-subscription diversity instead, all probe-validated: role/brief diversity,
   stance asymmetry (adversarial finder vs default-refute verifier), context diversity
   (blind diff-only finders vs full-repo verifiers), model-tier diversity
   (haiku/sonnet/opus/fable), and tool diversity.
2. **Narrow-brief library + router by diff type** — 3/4 misses from the two narrow
   Claude briefs; misses cluster in second-variant/parallel-path blindness. Briefs:
   second-variant auditor, concurrency/lock-discipline, read-only-claims, denied-verb
   completeness. Route by diff type (Rust vs procedure doc).
3. **Test the one-lens control arm first** — a lone "sibling-path auditor" (the
   existing pattern_second-variant-audit-every-raw-consumer as an agent brief) might
   capture most panel value at ~1/5 cost. Measure before committing to full panels.
4. **Three-stage funnel with per-stage models** — find (mid-tier, narrow briefs) →
   filter/dedup-vs-recorded (haiku) → verify (strongest + cross-model). The probe's
   29→6→6 funnel, mechanized; t-2826's "model per beat component" with data.
5. **Escalation valve as cost governor** — panel never per-beat; arms on hard signals
   (RECONSIDER sev≥4, PASS-WITH-GAPS, lock/pull-critical-section diffs, fix-next-to-
   unaudited-sibling shapes). 2.5–3.5× is cheap triggered, expensive standing.
6. **2 finders to start**; escalate finder count as the valve's second rung.
7. **"Empty findings are respectable" + blinding are load-bearing** — 3 defended clean
   verdicts on the strongest diff, zero invented findings there.

## Round 6 (2026-08-14, post-close) — build-team role separation joins the ADR scope

User reopened the execution side with a shape DISTINCT from the rejected ACT-panel:
an orchestrated **team with different jobs** during building — builder + independent
tester/validator + iteration. That's Anthropic's evaluator-optimizer pattern, and the
build framework already has the roles serialized (TDD → builder → evaluator →
challenger); the open design questions are **independence** (a blind test-author
writing failing tests from AC alone — the sequential-handoff context-loss warning
doesn't apply because the blindness is the feature) and **iteration timing** (in-loop
fresh-context critic vs today's expensive at-CLOSE RECONSIDER cycles). Folded into
t-2894's ADR as part of the same graded sizing function. Pilot corpus pre-identified:
t-2890/t-2891/t-2893.

## Next steps

1. ~~t-2887: run the retrospective probe~~ **DONE — GO.** Defects filed
   (t-2890–t-2893, t-2175 note), ADR task t-2894 (now covering judge panels + build
   teams, Claude-only), wiring tasks t-2895/t-2896 gated on it.
2. Start escaped-defect logging at the merge valve immediately (no build dependency —
   can begin as a manual habit: any valve catch the challenger passed gets recorded).
3. If go: two S drain-eligible build tasks — (a) JUDGE wiring (disagreement-surfacing
   verify-findings variant + agy lane), (b) PLAN/DECOMPOSE wiring (hive-mind panel at
   decomposition time) — plus the escalation-valve design note/ADR.
