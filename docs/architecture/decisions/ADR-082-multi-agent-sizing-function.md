# ADR-082: Graded Multi-Agent Sizing — Judge Panels and Build-Team Role Separation (extends ADR-080)

- Status: proposed
- Date: 2026-08-14
- Task: t-2894 (epic t-2811 backlog-drain)
- Extends: ADR-080 (epic runner JUDGE beats), ADR-079 (drain-loop contract)
- Relates: ADR-059 (multi-agent substrate selection), ADR-060 (merge valve)
- Evidence: docs/research/2026-08-14-judge-panel-probe.md (t-2887 probe),
  docs/research/2026-08-14-multiagent-orchestration-lessons.md,
  docs/research/2026-08-14-llm-judge-panels.md,
  docs/ideas/loop-task-multiagent.md (design thread, Rounds 1–6)

## Context

The wave-drain and epic-runner loops (ADR-079/080) judge each build beat with a single
fresh-context challenger. The t-2887 retrospective probe ran a diverse blind judge panel
against 6 diffs that had **all passed** a single challenger and found **4 verified
unrecorded misses (3 at severity 4)** at ~2.5–3.5× per-invocation cost. The concept
works — but a standing per-beat panel is the wrong shape: multi-agent costs 3–10× tokens
for equivalent tasks, and under equal budgets single agents win most comparisons. The
field's consensus and this repo's own design thread (idea doc Rounds 2–5b) converge on
*start single, escalate on measured signal* — for which no shipping implementation
exists in the field (2026 gap); brana's ungameable-signal loop discipline supplies the
missing ingredient.

Two prior framings are explicitly rejected and stay rejected:

- **ACT-step execution panels** — a panel to execute an already-atomic task is a
  planning defect surfacing as execution cost (idea doc Round 2; sequential handoffs
  measure 39–70% worse; "needs a panel to execute" = under-decomposition).
- **Fixed panel shapes behind a binary valve** — the user's operating requirement
  (2026-08-14) is that the panel *grows as a function of* task size, task nature, the
  loop it runs in, and the beat step judging. Prior art: adaptive topology selection
  (+22.9% over static baseline, router keyed on real-time task properties).

**Hard constraint (user, 2026-08-14): Claude-only.** agy/Gemini runs on a free-tier
account and always fails — the probe's Gemini lane produced ~zero verified signal and
one silent Claude fallback. No cross-vendor lane anywhere in this design. This
supersedes the probe report's "cross-model verify lane" consequence and the idea doc's
Round 5 "must include a non-Claude judge" constraint.

## Definitions (domain vocabulary)

- **Sizing function** — the deterministic table mapping machine-readable inputs to a
  panel/team shape. A lookup, never model judgment.
- **Rung** — one row of the sizing ladder; a named shape at a named trigger.
- **Hard signal** — an ungameable arming event recorded by the pipeline itself (a
  verdict, a diff property, a log entry) — never self-assessed confidence.
- **Escalation valve** — the mechanism that arms a higher rung when a hard signal
  fires. Cost governor: panels are triggered, never standing.
- **Judge panel** — parallel, blind, independent finders + filter + verify funnel
  applied at a JUDGE step (build-beat challenger gate, runner JUDGE beat).
- **Build-team role separation** — orchestrated distinct roles *during* building
  (blind test-author, builder, in-loop critic) — Anthropic's evaluator-optimizer
  pattern; NOT the rejected ACT-step execution panel.
- **Escaped-defect log** — merge-valve records of defects the single challenger
  passed; the evidence base rung decisions and planning feedback run on.

## Decisions

### 1. The sizing function is a deterministic table

Inputs — all machine-readable at arming time, none model-assessed:

| Input | Source |
|---|---|
| `effort` | task field (XS/S/M/L/XL) |
| `nature` | task `kind` + diff file classes (code / procedure-doc / docs) |
| `criticality` | diff paths ∩ critical-section list (lock/pull code, `system/hooks/`, runner beat procedures; list maintained in the wiring task, seeded from ADR-080 §5 lease/pull sections) |
| `loop` | which loop invokes judgment (build beat / drain-loop / epic runner / plan-decompose) |
| `beat step` | which step is judging (JUDGE gate, CLOSE, PLAN/DECOMPOSE) |
| `signals` | hard signals fired this beat (§3) |

Output — a shape tuple: `{finders: N, briefs: [...], filter: none|haiku-dedup,
verify: none|strongest-model, team: {blind_test_author: bool, in_loop_critic: bool}}`.

The function is versioned prose-plus-table in this ADR; the wiring tasks (t-2895/96)
implement it as data, not code branching on vibes. Changing a rung is an ADR amendment.

### 2. The sizing ladder

| Rung | Trigger (highest matching row wins; rung 0 is the residual floor; signals can only raise, never lower) | Judge shape | Build-team shape |
|---|---|---|---|
| **0** | *Floor:* any input matching no higher row — including XS/S of any nature with no signals | single fresh-context challenger (today's default — unchanged) | builder-authored tests (today's default) |
| **1** | effort ≥ M, OR nature=code with criticality hit | challenger **+ 1 sibling-path/second-variant finder** (inferred highest-yield brief: 3 of 4 probe misses were second-variant blindness; validated by the §6 control-arm window) | **+ blind test-author** — nature=code only; docs/procedure tasks have no test framework (sdd-tdd.md exception) and get the judge-side shape alone (§5) |
| **2** | any hard signal fired (§3) | **2 narrow-brief finders** (brief router by diff type, §4) → haiku filter/dedup → strongest-model default-refute verify | + **in-loop fresh-context critic** beating with the builder (§5) |
| **3** | epic-scale decomposition, PLAN-time strategy choice | full hive-mind panel (N lens-locked workers → adversarial verify → synthesize; ADR-059 block) | n/a (no build yet) |

Rung 2's funnel is the probe's measured 29→6→6 shape mechanized: find (mid-tier,
narrow briefs) → filter (haiku) → verify (strongest model, default-refute). Rung
escalation *within* a beat is one-way: signals raise the rung for that beat only;
nothing lowers a rung below its trigger row, and no rung persists past the beat that
armed it (triggered, not standing). **Timing:** a signal fired *by* a beat's own
judge pass arms the raised rung for the re-judgment of that beat's post-fix
artifact — the already-delivered verdict stands; the next judge pass on that beat
runs at the raised rung. Every beat record states the shape armed and, when a rung's
precondition failed (e.g. §5's approval gate), that it did NOT arm and why — an
unarmed mechanism must be observable, never silent.

### 3. Hard signals (the arming list)

The valve arms on these and only these — each is recorded by the pipeline, none is
self-assessed:

1. Challenger verdict **RECONSIDER with severity ≥ 4**.
2. Evaluator verdict **PASS-WITH-GAPS**.
3. Diff touches a **lock/pull-lease code path** — the NARROW subset of the §1
   critical list (wave pull, lease, approve sections in `brana-core`), not the
   whole list. *(Amended 2026-08-14, t-2895 wiring: as originally written this
   signal covered the entire §1 list, which made §2's rung-1
   "code with criticality hit" row unreachable — any critical hit jumped
   straight to rung 2 via this signal. The broad §1 list feeds rung 1 through
   the criticality input; only the lock/pull-lease subset is a rung-2 signal.
   Implementation: `JUDGE_LOCK_PULL_PATHS` / `lock_pull_hit` vs
   `JUDGE_CRITICAL_PATHS` / `criticality_hit` in judge-sizing.md.)*
4. **Fix-commit-next-to-unaudited-sibling** shape: the diff fixes one variant of a
   pattern that has ≥1 structural sibling not in the diff (the probe's dominant
   miss class). **Detection mechanism:** this is NOT a standalone static diff scan —
   recognizing an unaudited sibling is semantic work. It fires off a *recorded
   structured verdict field*: the rung-0/1 judge's brief requires it to answer
   "does this fix have structural siblings outside the diff? (yes/no/paths)" as
   part of its verdict, and a recorded `yes` IS the signal. Like signal 1, a
   model's recorded verdict is a hard signal; only *self-assessed confidence*
   is banned.
5. **Escaped-defect log entry** matching the task's area (same crate/skill/path
   prefix) within the log's rolling window. This is a stigmergy signal (see
   §Inspiration): each escaped defect deposits weight on its area; the rolling
   window is the evaporation term. Areas with fresh deposits arm at lower rungs;
   quiet areas decay back to rung-0 sensitivity — no one curates the list.

Self-assessed model confidence is explicitly rejected as a signal — it is gameable,
under-explored in the field, and contradicts the loop's hard-signal discipline.

### 4. Claude-only diversity axes and the brief library

Vendor diversity is unavailable (hard constraint) and its measured yield was ~zero in
the probe. Correlated-error mitigation rests on five within-subscription axes — all
probe-validated (the probe's same-model panel still produced 4 verified misses on
challenger-passed diffs):

- **(a) Role/brief diversity** — narrow adversarial briefs found all 4 misses.
  Brief library (seeded from the probe): *second-variant/sibling-path auditor*,
  *concurrency/lock-discipline*, *read-only-claims auditor*, *denied-verb
  completeness*. A router selects briefs by diff type (Rust/code vs procedure doc).
- **(b) Stance asymmetry** — finders hunt (adversarial), verifiers refute
  (default-refute). The probe's verify stage corrected severity inflation and is
  **not optional** at rung 2.
- **(c) Context diversity** — finders are blind (diff-only, no task notes/backlog/git
  history); verifiers get full repo access.
- **(d) Model-tier diversity** — haiku/sonnet/opus/fable are different models with
  different blind spots; the funnel assigns tiers per stage (find mid-tier, filter
  haiku, verify strongest).
- **(e) Tool diversity** — each judge's tool allowlist is part of its brief.
  Allowlists are **subset-only**: every panel role (finder, verifier, critic,
  test-author) inherits the runner's denied-verb manifest (ADR-079/080 — no
  `ac approve`, no wave status writes, no batch approve, no merges) and a brief
  may only narrow further, never widen. AC for the wiring: no panel-role
  manifest contains a verb the runner manifest denies.

Contract-level prompt requirements (load-bearing, from the probe): **blinding** and
**"empty findings are a respectable answer"** — 3 defended clean verdicts on the
strongest diff, zero invented findings. Panels run **parallel, never cascading**, and
**disagreement surfaces**: split verdicts go to the human valve as their own signal
class — the tie→FALSE_POSITIVE suppression in stock `verify-findings` is explicitly
NOT wired here (idea doc Round 5).

### 5. Build-team role separation (evaluator-optimizer, not ACT panels)

Two mechanisms, armed by the same ladder:

- **Blind test-author (rung ≥ 1):** a separate agent writes failing tests from the
  task's acceptance criteria alone — it never sees the implementation plan or diff.
  The builder implements until green. The sequential-handoff context-loss warning
  (39–70%) does not apply: the test-author's blindness IS the feature — an independent
  executable statement of the contract.

  *Immutability — what today's machinery actually enforces, and the gap:* the
  existing gates (`system/hooks/goal-completion.sh`, `red-verification.sh`) block
  Modified pre-existing grader paths against `base_ref` and unregistered Added
  grader paths — but a path already in `tests_required[]` is skipped on later
  commits and stores no content hash, so an Added blind test can be weakened
  after its red commit undetected. This ADR names that residual gap explicitly
  rather than claiming coverage: **the wiring task must pin a content hash of
  each blind-authored test at registration and re-verify it on every subsequent
  commit touching that path.** Until that ships, blind authorship adds
  independence, not enforcement.

  *Arming precondition:* requires approved acceptance criteria — blind authorship
  from an unsigned contract formalizes a contract nobody signed. For loop-invoked
  builds this is free (`ac_state: approved` is already the drain/runner pull gate,
  ADR-079). For interactive builds it is today almost never true (~2.6% of the
  backlog carries `ac_state: approved`, and the build readiness check never reads
  it) — so the wiring must extend the M+ readiness check (build load.md Step 0d)
  to surface AC approval as a first-class precondition, and until then the beat
  record's "did not arm: AC unapproved" line (§2 Timing) keeps the gap visible
  instead of silent.
- **In-loop fresh-context critic (rung 2):** today adversarial critique lands only at
  CLOSE, producing expensive late RECONSIDER→fix cycles (probe-documented). At rung 2
  a fresh-context critic reviews at each beat boundary *during* the build loop
  (community-validated hybrid-loop pattern). At rungs 0–1 critique stays at CLOSE —
  per-beat criticism of small mechanical work is pure overhead.

### 6. Pilot and gating

- **Judge side — the one-lens control arm is a prerequisite for rung-2 STANDING
  wiring, not for the valve.** A lone sibling-path auditor (rung 1) may capture most
  panel value at ~1/5 cost (probe lever #3). Decision: t-2895 wires the valve + rung 1
  immediately — cheap, and *inferred* highest-yield: the probe's briefs were
  security/injection and contract/AC-fidelity; "second-variant blindness" is the
  miss *class* they surfaced, not a brief that was itself tested. The §6 control-arm
  window is therefore also rung 1's own validation, not just rung 2's cost check.
  Rung 2's full funnel ships wired but **arms only on hard
  signals**, and the first N (=6) rung-2 firings run the control arm alongside: rung-1
  finder vs full rung-2 panel on the same beat, verified-miss delta recorded. If the
  control arm captures ≥ the full panel's verified misses over that window, rung 2
  collapses into "rung 1 + verify stage" by amendment.
- **Build side — pilot before default.** Pilot corpus: t-2890/t-2891/t-2893 (crisp-AC
  S fixes; note these are S-effort, so the pilot deliberately runs rung-1 machinery
  below its trigger row — pilot overrides the ladder's *effort* trigger for
  measurement). **Prerequisite:** the pilot does NOT override §5's AC-approval
  precondition — all three tasks currently carry `ac_state: none` (informal `AC:`
  context lines only), so before the pilot runs, their criteria must be formalized
  and approved through the sanctioned path (propose → `brana backlog ac <id>
  approve`, ADR-079). Piloting blind authorship from unsigned AC would measure the
  wrong mechanism — the blindness contract only means something against a signed
  contract. Measurement:
  (1) do blind-authored tests catch anything builder-authored tests would not
  (diff the two test sets per task); (2) friction delta (wall-clock + token cost +
  human interventions). Blind test-author becomes the rung-1 default only if (1) > 0
  across the corpus at acceptable (2).
- **Wiring gates:** t-2895 (judge wiring) and t-2896 (plan wiring) are gated on this
  ADR only — NOT on the pilots. The pilots gate *defaults*, not mechanisms: both
  mechanisms ship opt-in/signal-armed, and pilot outcomes flip defaults by amendment.

### 7. Feedback loop: escalation events feed planning

Every valve firing appends to the escaped-defect log (which the probe seeded with 4
entries): the signal that fired, the rung armed, verified findings, cost. Minimum
record shape: `{date, area (path prefix), signal, rung_armed, verified_findings,
cost_tokens}`; rolling window defaults to 30 days pending calibration. Storage
location and full schema are t-2895 deliverables — the log is referenced as
load-bearing throughout this ADR and MUST be specified before any rung logic that
reads it ships. Rung-2
firings on a task are treated as evidence the task arrived under-decomposed — the
accumulating log IS the under-decomposition metric that PLAN-time panels (rung 3) and
`/brana:backlog plan` read back. The valve thus fixes root causes upstream instead of
compensating forever at execution time.

### 8. Cost anchor

Probe-measured: ~2.5–3.5× per invocation (~340K tokens/diff vs 100–150K single
challenger) — the cheap end of the literature's 3–10×. Affordable **triggered**,
unaffordable **standing**. The ladder's default posture is rung 0; the expected
steady-state is that most beats never arm past it. Rung-3 PLAN panels run rarely
(per-epic, not per-beat); their *output* still lands within ADR-080 §8's
sitting-based human review budget (that section governs review throughput, not
panel cost — this section owns cost).

## What this ADR does NOT change

- The human merge valve (ADR-060/079/080): no rung merges anything. Panels produce
  verdicts; humans merge.
- `wip_limit` and wave-level parallelism (t-2889, sequenced separately).
- The ACT step: no rung ever adds execution agents to an atomic task. Multi-agent
  lives at judgment (JUDGE/PLAN) and at build-team role separation only.
- ADR-059 substrate routing: panels run on native Workflow/Agent blocks
  (hive-mind / verify-findings-derived), never ruflo agentic tools.

## Inspiration: ruflo's coordination vocabulary (ideas adopted, substrate rejected)

ruflo's agentic layer is unusable here (subscription theater — ADR-059,
field-note_ruflo-agentic-layer-subscription-theater: MCP execution surfaces are
bookkeeping without a paid API key, and upstream's own docs say "MCP tools only
coordinate"). But its *coordination design vocabulary* is legitimate prior art, and
this ADR knowingly borrows from it:

- **Topology-per-task** (`swarm_init` mesh/hierarchical/ring/star + adaptive
  strategy) — the insight that agent-team *shape* should follow task properties is
  ruflo's framing and the adaptive-topology literature's (+22.9%). The sizing ladder
  (§2) is the deterministic, auditable version: a versioned table instead of a
  runtime router.
- **Stigmergy / pheromone trails** (`swarm_pheromone_update`/`_status`) — indirect
  coordination through environment markings that decay. Adopted as the escaped-defect
  log's area-weighting (§3 signal 5, §7): defects deposit, the rolling window
  evaporates, arming sensitivity is the trail strength. The log coordinates planner
  and valve without either talking to the other.
- **Queen/worker orchestration** (`hive-mind_spawn`) — orchestrator-workers with a
  synthesizing coordinator; already adopted natively as the `hive-mind` skill
  (ADR-059) and reused here as rung 3.
- **Cognitive-pattern diversity** (`daa_cognitive_pattern`: convergent / divergent /
  lateral / systems thinking per agent) — same idea as diversity axes (a)/(b) (§4):
  vary *how* judges think, not just what they look at. Our brief library + stance
  asymmetry is the probe-validated concrete form.
- **Consensus quorum voting** (`hive-mind_consensus`, `coordination_consensus`) —
  considered and deliberately inverted: quorum aggregation suppresses exactly the
  split verdicts this design surfaces to the valve (§4). Informed rejection, not
  omission.
- **Work-stealing claims** (`claims_steal`/`rebalance`) — noted as relevant prior art
  for wave-level parallelism (t-2889), out of scope here.

## Alternatives considered

- **ADR-080 amendment instead of a standalone ADR** — rejected: the sizing function
  spans build beats, both runners, and plan-time decomposition; 080 owns the epic
  runner only. Standalone with an "extends" edge mirrors 080's own relation to 079.
- **Standing per-beat panels** — rejected on cost (3–10× for equivalent tasks; probe
  2.5–3.5×) and on the field's equal-budget evidence.
- **Vendor-diverse panels** (the literature's own #1 recommendation) — unavailable
  under the Claude-only constraint; the probe measured ~zero yield from the Gemini
  lane anyway. The ADR accepts residual correlated-error risk, mitigated by axes
  (a)–(e), and cites the probe as evidence same-model panels still find verified
  misses. Revisit only if a second paid vendor lane ever exists.
- **Learned/self-assessed confidence as escalation trigger** — rejected: gameable,
  no shipping precedent, contradicts hard-signal discipline.
- **Model-judgment sizing** (ask a model how big the panel should be) — rejected:
  the *mapping* from inputs to shape is a table, auditable and reproducible.
  Precision (challenge round 2): one input, signal 4, is itself a recorded model
  verdict answering a fixed factual question ("structural siblings outside the
  diff?") — that is deliberate and consistent: verdicts-as-data are how every
  judge signal here works. What stays rejected is the model choosing the shape.

## Consequences

- The single challenger stays the per-beat default; nothing changes for XS/S
  mechanical work.
- t-2895 (judge wiring) and t-2896 (plan wiring) are unblocked by this ADR and
  implement the ladder as data. **Sizing caveat (challenge round 1):** t-2895's
  enumerated scope (table + router, 5 signals, brief library, funnel, blind
  test-author + approval gating, in-loop critic, control-arm counters, log schema)
  reads M, not S — expect DECOMPOSE to split it (valve + rung 1 first; funnel and
  build-team mechanisms as follow-on slices).
- The escaped-defect log becomes load-bearing (rung decisions + §7 metric) — its
  schema/storage is a named t-2895 deliverable (§7), not an afterthought.
- The M+ interactive readiness check (build load.md Step 0d) gains an AC-approval
  precondition surface (§5) — owned by the wiring, tracked so it cannot silently
  slip.
- The loops-library contract (t-2826) must reference this sizing function in its
  JUDGE-step / model-per-beat schema — assigned to t-2895 to append, not left
  ownerless.
- Verdict rendering (t-2857/t-2825) grows more load-bearing as stacked panel
  verdicts reach the valve — watch human attention cost (idea doc, second-order
  effects).
- First-mover risk accepted: no shipping failure-based-escalation implementation
  exists to copy; our evidence base is our own probe + log.

## Challenge record

- **Round 1 (2026-08-14, adversarial challenger, verdict RECONSIDER → repaired in
  place):** three code-verified sev-4 findings, all fixed by clarification not
  redesign. (1) §5's approval precondition was satisfied by ~2.6% of the live
  backlog and never checked by the interactive build path — resolved by scoping
  (free for loop-invoked builds, readiness-check extension + unarmed-visible beat
  records for interactive). (2) The grader-immutability claim overstated current
  enforcement — `tests_required[]` paths are skipped after registration with no
  content hash, so Added blind tests could be weakened undetected; restated as a
  named residual gap with a content-hash-pinning requirement on the wiring.
  (3) Signal 4 had no deterministic detection mechanism — resolved as a recorded
  structured verdict field from the sitting judge (verdicts are hard signals;
  only self-assessed confidence is banned). Warnings fixed: rung-0 floor clause;
  nature qualifier on the build-team column (M docs task no longer triggers a
  test-author); §6 "probe validated the brief" overclaim corrected (brief is
  inferred from miss class; control arm doubles as rung-1 validation);
  escaped-defect log minimum schema + ownership named; subset-only allowlist AC;
  ADR-080 §8 cross-reference corrected (review throughput ≠ panel cost);
  within-beat signal timing disambiguated; t-2895 resize caveat and
  loops-library contract ownership added.
- **Round 2 (2026-08-14, fresh challenger, verdict RECONSIDER → repaired in
  place):** verified all four round-1 repairs against the actual hooks and ADRs
  (grader-gap statement and arming-precondition scoping both confirmed accurate
  code-level). One new sev-4 the repairs introduced: the §6 pilot corpus
  (t-2890/91/93) all carried `ac_state: none`, violating §5's own arming
  precondition — resolved by an explicit §6 prerequisite (formalize + approve AC
  via the sanctioned verb before the pilot; the pilot overrides the effort
  trigger only, never the approval gate). Polish: ladder header rewritten
  (highest-matching-row + residual floor — the old "first match from the top"
  reading was incoherent with the floor clause); Alternatives §model-judgment
  bullet made precise (signal 4 is a recorded verdict as *input*; what stays
  rejected is the model choosing the *shape*).
- **Wiring amendment (2026-08-14, t-2895 rung-2 panel):** the implementation's
  own escalated review (this ADR's valve, run on the diff that built it) found
  §3 signal 3 as written swallowed §2's rung-1 criticality row — every §1-list
  hit armed rung 2, making the graded middle rung dead code. Signal 3 narrowed
  to the lock/pull-lease subset (see §3 item 3 inline note). Found by a blind
  second-variant finder; the same panel confirmed 4 more sev-4 implementation
  gaps (all repaired in t-2895) — first live evidence the rung-2 shape catches
  what a single reviewer misses, on its own code.
