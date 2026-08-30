# Model/Effort Routing Criteria — per skeleton step, per ring

**Date:** 2026-08-30
**Task:** [t-3157](../../.claude/tasks.json) — "B. Model/effort routing criteria" (parent t-2337, tag `trigger:L4.6`)
**Trigger for:** [the-brana-guide.md](../ideas/the-brana-guide.md) L4.6 (parked 2026-08-23, L7 #6) — "which capability tier a chosen [compute-routing] primitive runs at."
**Scope note (from L4.6):** compute routing (*which primitive* — native Task fan-out vs. haiku `-p` vs. agy vs. Workflow) is already decided by `delegation-routing.md`. This doc answers the narrower, still-open question: *which model/effort tier* does each step of the seven-step skeleton run at, at each ring. It does not re-litigate compute routing.

## Verdicts (read this first)

1. **L4.6 should flip ⏸ → ✅.** The standing defaults it parked (ACT inherits session model · mechanical retrieval → haiku · JUDGE → `judge-sizing.md` ladder · Workflow inherits unless confident) are not just "not yet reopened" — they are **complete** once one correction is made: three of the seven steps (SELECT, MEASURE, RESTART) never carry a model/effort decision at any ring; they are deterministic control-flow, not routing gaps. See §3. Two genuine gaps remain (Knowledge-ring ACT and Epic-ring ACT's headless-runner tier), but both are gaps in an *unbuilt* mechanism (t-2851 distiller, t-3019 Orbit), not gaps in the *rule* — the rule for when they do get built is already implied by the existing pattern (§4) and doesn't need a new ADR to say so.
2. **`the-brana.md` §Gate: defaults stand — no new rule to land.** The four standing defaults already read as prose in L4.6 and are consistent with every piece of shipped evidence checked (`delegation-routing.md`, `judge-sizing.md`/ADR-082, `system/agents/*.md` frontmatter, `docs/architecture/agents.md` routing table). Landing them in `the-brana.md` §Gate would be restating, not deciding — the guide's own rule is "closes into the owner doc," and none of these four defaults currently lack an owner (delegation-routing.md and judge-sizing.md already are the owners). The one thing worth landing is the **three-step exemption** (§3) — a one-line addition to §Gate's Seven-step skeleton definition, not a new rule.
3. **The matrix.** See §2.

---

## 1. What "tier" means here

Two independent axes get conflated in casual talk about "model routing" — this doc keeps them separate, per ADR-018's own postmortem and ADR-082 §Alternatives (`Model-judgment sizing` rejected: a model must never choose its own shape):

- **Model tier** — which model runs the step: `haiku` (mechanical), `sonnet` (standard reasoning), `opus`/`fable` (deep reasoning / adversarial verify), or **inherit** (session model, no separate call).
- **Effort tier** — how much of that model to spend: single-pass vs. escalation ladder (rung 0/1/2, ADR-082) vs. full panel.

Neither axis is ever set *by* the step itself at runtime — every real routing mechanism found in the repo is a **lookup against machine-readable inputs** (effort, nature-class, criticality, hard signals), never a model self-assessing its own confidence (ADR-082 §"Model-judgment sizing" explicitly rejected; ruflo's `hooks_model-route`/`agentdb_route` are flagged untrustworthy in `~/.claude/rules/ruflo-stub-guard.md` for the same failure mode — silently degrading to a hardcoded `confidence:0.5` instead of a real lookup). This is the one principle that should generalize from JUDGE (where it's already law) to every other step.

## 2. The matrix

| Skeleton step | Micro (`/goal`, seconds) | Beat (`/loop`, minutes) | Epic (waves, days) | Knowledge (weeks) |
|---|---|---|---|---|
| **ORIENT** (memory read-on-entry) | inline session read, no separate call | LOAD phase: mechanical query (`backlog_get`/`session_read`) → **inherit**; a spawned research read → **haiku** (rule 4) | `backlog_focus`/`wave_get` query → **N/A, deterministic**; a synthesis read ("what's blocking this epic") → **haiku**, escalate to **sonnet** only if the synthesis itself requires judgment | `mcp__brana__recall` (hybrid FTS5+semantic) → **N/A, deterministic retrieval**; distillation of many hits into a summary is design-only (t-2851) — see §4 |
| **SELECT** (queue, atomic pull) | task frontier already resolved by ORIENT | atomic wave/backlog pull (`wave_drain`, `backlog_focus`) | atomic wave pull, gate check (`check_wave_gate`) | knowledge-staging queue pull (design, t-2851) |
| **ACT** (pump, the work) | **inherit session model** (standing default; matches Agent-tool `fork` semantics: forks always inherit the parent model) | skill/`Workflow` execution → **inherit unless the agent's own frontmatter overrides** (`system/agents/*.md`: `build-evaluator`/`pr-reviewer` pinned **sonnet**, `debrief-analyst` pinned **opus**, everything else **haiku** or inherit — `docs/architecture/agents.md` routing table) | headless `epic-drain` runner (ADR-060, `claude -p`) → **inherit the runner's configured session model**; no per-epic override exists or is proposed — same rule as Beat, one level up | distiller pump (t-2851, **not built**) — gap; provisional read in §4 |
| **MEASURE** (gauge, objective readout) | test result / `validate.sh` check → **N/A, deterministic** | build receipt / beat gauges (`statusline-pipeline-awareness.md`, pipeline-digest) → **N/A, deterministic**; never self-assessment (gauge law) | wave `CHECK:` lines (ADR-086 §6, allowlisted vocabulary, evaluated by `wave ship`) → **N/A, deterministic** | hygiene gauges for staleness (design, t-2853) → **N/A, deterministic** (date/count arithmetic) |
| **JUDGE** (valve, Actor≠Evaluator) | test pass/fail is the floor judge (mechanical); if a beat arms rung ≥ 1, `judge-sizing.md`/ADR-082's ladder governs: finders = **sonnet**, filter = **haiku**, verify = **strongest available (opus/fable)**, in-loop critic = **fresh-context sonnet** | same ladder, evaluated once per beat (this is where JUDGE actually fires in practice — a "Micro-ring" event folded into the Beat's report) | wave `ship`/AC-approve → **human** (irreversible, tier N/A by the reversibility split — machine judges reversible outcomes, human judges irreversible ones) | curation valve as cockpit digest (design, t-2852) → **human**, with a mechanical (haiku-formatted) digest feeding it |
| **ASSIMILATE** (memory write-on-exit) | `backlog_set context --append`, task-local — **N/A, mechanical write** | beat record write (markdown doc) — **N/A, mechanical write**; content was already composed by ACT/JUDGE at whatever tier those ran | `memory_write`/ADR write — **N/A, mechanical write** for the call itself | same — **N/A, mechanical write** (rule 4's "mechanical retrieval → haiku" extends symmetrically to mechanical *writes*: no reasoning tier applies to the write call) |
| **RESTART** (pacing) | n/a (task-scoped, no pacing state) | `{active, waiting, empty}` from queue depth — **N/A, deterministic** state machine | same, at wave granularity — **N/A, deterministic** | same, at reservoir/cap granularity (design) — **N/A, deterministic** |

## 3. The finding that actually resolves L4.6: three steps are not a routing question at all

L4.6 was parked because "which capability tier a chosen primitive runs at is not [decided], beyond the narrow defaults already in place." Walking every cell above shows the narrow defaults were narrow because **most of the matrix has no model tier to assign**:

- **SELECT** is always an atomic CLI/DB pull (`wave_drain`, `backlog_focus`, `check_wave_gate`) — by design, so "a loop cannot game its own priorities" (the-brana.md §Cycle). A model choosing what to pull next would reintroduce exactly the self-judged-priority failure mode the queue primitive exists to prevent.
- **MEASURE** is always deterministic by the gauge law ("objective readout, never self-assessment, never acts"). `ruflo-stub-guard.md`'s catalogue of untrustworthy tools is almost entirely gauges that quietly became model-flavored (`analyze_diff-risk`'s ungrounded heuristic, `performance_metrics` self-labeled `"_real": false`) — independent, negative confirmation that a "smart" gauge is where this class of system already broke.
- **RESTART** is a pure state-machine decision off queue depth / gate status (`{active, waiting, empty}`) — never a model call in any ring, built or designed.

So the real shape of "model/effort routing criteria" is: **ORIENT, ACT, JUDGE, ASSIMILATE are the only steps that ever touch a model**, and all four already have a rule:

- ORIENT/ASSIMILATE, when mechanical (the common case): **haiku** (delegation-routing.md rule 4), or **N/A** when it's a plain CLI/DB call with no LLM in the loop at all.
- ACT: **inherit session model**, unless the acting unit is a named agent with its own frontmatter override (`docs/architecture/agents.md` routing table — the exceptions are enumerable and already shipped: build-evaluator/pr-reviewer=sonnet, debrief-analyst=opus).
- JUDGE: the ADR-082 ladder (`judge-sizing.md`), which already assigns finder/filter/verify tiers per rung, plus the reversibility split (machine for reversible, human for irreversible) for anything above the per-beat build ladder.

## 4. Genuine open gaps (not routing-rule gaps — mechanism gaps)

Two matrix cells are real "TBD," but both are TBD because the mechanism they'd route doesn't exist yet, not because the routing *rule* is undecided:

- **Knowledge-ring ACT** (the distiller pump, t-2851): once built, the existing pattern predicts **sonnet** — it's synthesis over multiple memory entries (more than mechanical retrieval, which stays haiku by rule 4) but not an architectural decision (which would earn opus under the debrief-analyst precedent). This is a provisional read to hand to whoever builds t-2851, not a new binding rule — recorded here so it isn't invented from scratch, per the guide's own "operator will bring more knowledge to this later — do not force a general rule before then."
- **Epic-ring ACT's headless-runner tier** (Orbit / t-3019, blocked_by t-2982): the runner spec (`docs/architecture/features/autonomous-runner.md`) does not name a model at all — it inherits whatever the invoking `claude -p` session is configured with, same as Beat-ring ACT one level up. No gap in the *rule* (inherit), only in whether anyone has actually pinned a specific model for unattended headless runs — worth a one-line note in `autonomous-runner.md` when t-3019 ships, not a new ADR.

Both gaps are already "gated on evidence" exactly the way L4.6 asked for — they don't block flipping L4.6 itself, which was never scoped to cover unbuilt mechanisms.

## 5. Evidence trail

- `~/.claude/rules/delegation-routing.md` §Compute Routing rule 4 — mechanical retrieval → haiku, the only cross-ring rule that already existed pre-this-doc.
- `system/skills/_shared/judge-sizing.md` + [ADR-082](../architecture/decisions/ADR-082-multi-agent-sizing-function.md) — the JUDGE ladder: rung 0/1/2, finder=sonnet, filter=haiku, verify=strongest-model, all keyed off machine-readable signals, never model self-assessment (ADR-082 §Alternatives explicitly rejects "model-judgment sizing").
- `docs/architecture/agents.md` §Routing Table + `system/agents/*.md` frontmatter — the only place per-agent model overrides are actually pinned (`build-evaluator`/`pr-reviewer`=sonnet, `debrief-analyst`=opus, rest=haiku/inherit); confirms ACT's "inherit unless confident otherwise" default is already how the shipped agents behave, not aspirational.
- [ADR-018](../architecture/decisions/ADR-018-dynamic-model-routing.md) (2026-03-11, accepted but never re-touched) — the earlier attempt at a general complexity-scoring function (0.0–1.0, three thresholds). Superseded in practice: it predates the ring/skeleton vocabulary entirely, was never wired past its own ADR, and its `blast_radius` input was already dropped for a circularity ADR-018 itself flags. Treated here as historical evidence that a *general* scoring formula was tried and abandoned in favor of the narrower, per-step rules that now exist (rule 4, the JUDGE ladder, agent frontmatter) — reinforces verdict 2 (don't reintroduce a general rule where narrow ones already work).
- `~/.claude/rules/ruflo-stub-guard.md` — ruflo's own model-routing tools (`hooks_model-route`, `agentdb_route`, `agentdb_pattern-search`) are confirmed untrustworthy (silent degrade to hardcoded confidence, contradictory rankings). Used here only as negative evidence: it's independent confirmation that letting a soft/heuristic layer pick the tier is where this class of system has already failed once.
- `docs/architecture/the-brana.md` §Cycle/§Scale — the seven-step skeleton definition (ORIENT→SELECT→ACT→MEASURE→JUDGE→ASSIMILATE→RESTART) and the four-ring table (Micro/Beat/Epic/Knowledge), sourced from `60-agent-loop-architecture.md`; the gauge law ("never self-assessment, never acts") is what grounds the MEASURE-is-always-deterministic finding.
- `docs/ideas/the-brana-guide.md` L4.6, L4.4 (valve/tier inventory), L3.1 (per-ring instrument table) — the parked node itself and its sibling nodes (L4.4's three-tier *environment* hardening is a different axis — tier-0/1/2 = workbench/buffer/production — not to be confused with the model tiers in this doc; both use the word "tier" for unrelated things, worth flagging so a future reader doesn't conflate them).

## 6. Terminology flag (SEAM, not a decision)

`the-brana-guide.md` L4.4 already uses "tier" for the workbench/buffer/production environment ladder (tier 0/1/2). This doc uses "tier" for model/effort (haiku/sonnet/opus, rung 0/1/2). Both are real, both are called "tier," and they answer different questions ("where can this run" vs. "how much model does this step get"). Recorded as a SEAM per the guide's own convention rather than silently renaming either — a future reader who greps "tier" needs to know both exist.
