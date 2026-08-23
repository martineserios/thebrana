---
title: The Brana — consolidation board (per-file tidy actions, awaiting operator decisions D1–D5)
status: idea (draft for approval — nothing moved yet)
created: 2026-08-18
task: t-2490
epic: brana-v3-redesign
relates-to:
  - "[the-brana-guide](the-brana-guide.md) — the studio guide this board feeds (L5 doc map, L6 tidy tasks)"
---
# The Brana — consolidation board (2026-08-18, draft for approval)

Scope: the Brana cluster — loops, waves, skills/stations, graphs, runner, judgment. Four stores: idea docs · architecture docs + ADRs · guides/loop entries · memory. Nothing here has been moved yet. Sources: graphify island map (16,885-node graph, +609 doc edges), three read-only inventories (ideas / arch / memory), the two peer sessions, today's decisions.

## 0. Structural baseline (graphify)

Three islands that barely link:

| Island | Centre (degree) | Character |
|---|---|---|
| «backlog-v3-schema» — 19 docs: ADR-059/060/061/062/063/065/068/069/074, the-orbit, substrate-end-state, substrate-primitives, autonomous-runner, brana-v3-redesign, runner-capability-isolation, substrate-leverage-audit | ADR-068 (24), brana-v3-redesign (16), the-orbit (16), substrate-end-state (17) | v3 / runner / orbit lineage — retired vocabulary + its supersession ADR |
| «ADR-080» — 14 docs: ADR-078/079/080, loops-library (spec+idea), plan-time-wave-graph, wave-board, wave-gate-enforcement, drain-loop, epic-drain, loop-first-redesign, wave-pipeline (+infographic) | ADR-079 (36), ADR-080 (36) | wave / loop lineage — shipped, current |
| Orphans (degree ≤3 / own pocket): skills-as-loops (3), goal-integration idea (3), runner-capability-isolation (3), agent-definition-gaps, agent-interaction-architecture, dynamic-skill-routing (+brana-operating-model pocket), Pocock research (README pocket, NOT linked to skills-as-loops), loop-task-multiagent (own pocket with 3 judge-panel research docs, 8) | — | skills / judgment / agent-definition thread — never wired to either island |

Bridges island1↔2: ADR-079→ADR-059/060/062, wave-pipeline→ADR-062. Thin.
Other hubs: idea-to-ship.md (32) = the flow front door; ADR-079/080 (36) = centre of mass.

Implication: `docs/architecture/the-brana.md` is a BRIDGE NODE by design — Space ← island 3 + orphans; Cycle ← island 2 (+ADR-061); Gate ← island 1's ladder + wave-pipeline's rooms. Island 1 = retire-and-point (already decided by ADR-068; make it stick). Island 2 = keep-and-rename. Orphans = the real debt (t-2278's own plan at degree 3). idea-to-ship.md and the-brana.md: one must point at the other (no two front doors).

## 1. Decisions needed from the operator (blocking)

| # | Decision | Recommendation |
|---|---|---|
| D1 | ADR-068 (v3 supersession) is still **Proposed** while three docs already say "superseded by ADR-068" — accept it, or downgrade the pointers? | **Accept** (its decision is lived reality; the-brana.md cites it as the retirement of Substrate/Orbit vocabulary). Fold its open Q1 (front door) into the-brana.md; open Q2 (extract substrate-primitives §1–3) into ADR-085's Space chapter work. |
| D2 | Two ADR-085 files (t-2490 skills-as-stations; t-2980 wave-as-human-unit) | **t-2980's → ADR-086** (t-2490's took the number first). Both stay Proposed until the idea is consolidated. |
| D3 | `wave-pipeline.md` (the only `status: active` doc, living in `drained/`) — where does its philosophy go? | **Absorb** the four primitives / seven laws / two rooms / four rings into `the-brana.md` (Cycle + Gate chapters + Scale axis); leave `ideas/drained/wave-pipeline.md` as a **redirect stub** (keeps 18 inbound refs valid); tag sweep `wave-pipeline` → `the-brana` on tasks. |
| D4 | `idea-to-ship.md` (degree 32) vs `the-brana.md` — which is the front door? | **the-brana.md = what it is; idea-to-ship.md = how work flows through it.** the-brana.md links idea-to-ship as "the flow view"; idea-to-ship gets a one-line header pointing up. |
| D5 | Scope of the tidy: cluster only (this board) vs whole `docs/` (README has 19 missing ADRs + 41 missing feature docs repo-wide) | **Cluster now; README full sweep as its own chore task** (mechanical, could be `brana reference generate`-style script). |

## 2. Idea docs — actions (in-scope 38; out-of-scope listed by inventory)

### KEEP-AS-COMPONENT (get a "Component of The Brana · owns: …" header; wired from the index)
| doc | chapter | owns |
|---|---|---|
| ideas/loop-task-multiagent.md (t-2887) | Gate | judgment panels at JUDGE/PLAN, diversity axes, probe GO |
| ideas/statusline-pipeline-awareness.md | Gate (gauge) | pipeline visibility in statusline |
| ideas/task-time-tracking.md | Cycle | beat-level timing (ADR-083) |
| drained/loops-library.md (idea) → but the SPEC `features/loops-library.md` is the owner | Cycle | idea doc → POINTER to spec (see below) |
| drained/skills-as-loops.md (t-2278) | Space | station/packet/conveyor, stop_condition/verifier/queue trio, palette, boundary test |
| worktree t-2490 skills-loops-graphs.md (t-2490) | Space | where primitives live, Pocock reading, organ files, admission checklist, evidence |
| drained/brana-v3-redesign.md | Gate | ladder L1/L2/L3, outcome ledger, shapes (governing design per ADR-068) |
| drained/orbit-evidence-first.md | Gate | evidence-before-infrastructure |
| drained/runner-capability-isolation.md (t-2173) | Gate | sandbox, lethal trifecta, tripwire-not-boundary |
| drained/build-receipts.md | Cycle | proof-of-done receipts (reconcile with beat records — collision #3) |
| drained/backlog-v3-lane-identity.md | Cycle | lane identity, unbuilt v3 axes |
| drained/gentle-ai-adoption-ladder.md | Gate | cheap-rung adoption ladder (reconcile with autonomy rungs — collision #2) |
| drained/agent-definition-gaps.md | Space | native agent frontmatter fields (skills:/tools:/memory:/isolation:/maxTurns:) |
| drained/agent-skills-brana-enhancements.md, skill-tiering.md, skill-semantic-validation.md | Space | skill packaging/tiering/validation |
| drained/universal-doc-graph.md | (meta) | doc graph substrate — the tool this board used |
| drained/brana-operating-model.md | legacy hub | keep as pointer-hub for the 4 docs it supersedes |
| html: wave-pipeline-design.html, brana-v3-design.html | visual | keep, header-only |

### POINTER-ONLY (content absorbed; add one-line "see X" banner)
loop-first-redesign (→ the-brana.md + loops-library), loop-goal-native-planning (→ ac-grammar.md), goal-completion-heuristics-h5-h8 (→ ac-grammar), challenger-outer-loop-gate (→ ADR-049), build-skill-gate-hardening (→ build phases), enforced-delegation + phase0-preregistration (KILLED, → ADR-059 routing rule), claude-gemini-orchestration (→ delegation-routing rule), drained/loops-library.md idea (→ features/loops-library.md)

### MERGE-INTO
goal-integration-three-primitive → **Cycle chapter of the-brana.md + ADR-061** (not loops-library — inventory suggested loops-library; the primitive split is philosophy, belongs in the index); goal-adoption-brana-skills → goal-integration; skill-lifecycle-manager → skills-as-loops; mission-control → statusline-pipeline-awareness

### ARCHIVE (dead, superseded banners already present; move to docs/archive/)
skill-auto-router, dynamic-skill-routing, agent-interaction-architecture, agent-observability-learning, enforcement-vs-injection, statusline-v2-backlog-intelligence

### Fix flags
- No status header: agent-definition-gaps, agent-skills-brana-enhancements, both .html
- Contradictory headers (status:idea + superseded banner): skill-auto-router, dynamic-skill-routing, agent-observability-learning, enforcement-vs-injection → resolved by ARCHIVE
- Concept collisions to settle in the index (single owner): (1) loop/queue semantics: philosophy=the-brana.md, contract=features/loops-library.md, skill-shaped loops=skills-as-loops (cite, don't re-derive); (2) autonomy rungs: brana-v3-redesign owns the ladder; orbit-evidence-first + gentle-ai cite it; (3) proof-of-done: beat record (loops-library) owns; build-receipts = a beat-record instance; (4) skill routing: skills-as-loops owns classification; skill-tiering owns packaging; semantic-validation owns validation

## 3. Architecture docs + ADRs — actions

### Status-header fixes (mechanical)
ADR-082 (no YAML frontmatter — add status), ADR-080 (date mismatch 08-13 vs 08-14), ADR-065 (add "amended by ADR-079"), features/build-cost-tracking.md (add "superseded by ADR-083"), agentic-primitives.md, workflow-primitive.md, wave-gate-enforcement.md, wave-board.md, plan-time-wave-graph.md, build-loop-redesign.md, checkpoint-resume.md, mission-control-cli.md, operating-model.md (all: add status)

### Reconcile
- ADR-068 → accept (D1); its open Q1 → the-brana.md; open Q2 → substrate-primitives §1–3 extraction lands as the Space chapter's primitive table (agentic-primitives.md + ADR-085 currently re-derive it — pick ONE owner: the-brana.md Space table, with agentic-primitives.md as the detailed reference)
- ADR-069 (2 of 6 decisions refuted by t-2516) → amend or mark partially superseded
- features/autonomous-runner.md vs ADR-080 epic runner — two runner concepts coexist → autonomous-runner = the (future) "Orbit satellite component"; ADR-080 epic runner = the current supervised pump. State it in both.
- features/brana-v2-compute-model.md still "active" → mark superseded by v3 (ADR-068)
- features/consensus-primitive.md → superseded in practice by hive-mind + ADR-082 → mark
- features/goal-binding-build-tdd.md (specifying, stale) → tie to t-2981 tdd pilot or park
- features/ac-state-forward-slice.md → "approval flow superseded by ADR-079"
- guide/workflows/epic-drain.md supersedes drain-loop.md for epics — neither says so → say so
- guide/workflows/challenge.md → superseded by ADR-082 graded panels → mark
- glossary.md has no wave/loop/station terms → the-brana.md carries the vocabulary table; glossary points to it
- system/loops/README.md dual authority with features/loops-library.md → README = pointer

### Land the worktree ADRs (after the idea is consolidated — NOT now)
ADR-084 (t-2837, Accepted pilot-only) · ADR-085 (t-2490) · ADR-086 (t-2980, renumbered). ADR-085's relative link to ADR-084 doesn't resolve in its worktree — fix at landing.

### docs/README.md
Cluster rows to add: ADR-061/069/080/081(+045–058, 063, 064 repo-wide), features loops-library, wave-board, plan-time-wave-graph, stacked-verdict-at-the-valve, ac-state-forward-slice, mission-control-cli, goal-binding-build-tdd (+34 more repo-wide). Remove 2 dead rows (features/cc-changelog-check.md, features/knowledge-drain-links.md). → D5.

## 4. Memory — actions
- UPDATE: project_loop-native-redesign (drop "pending approval", add chain → wave-pipeline → The Brana), project_wave-pipeline-vocabulary (demote: mechanics under The Brana; refresh t-2828), project_brana-v2-compute-model (ruflo workstream closed, ADR-059), project_system-architecture-current (re-verify or archive), G/pattern_challenge-wave-pipeline-valve-order (keep review-budget bottleneck; drop dated valve order), G/pattern_native-workflow-substrate-calibration (one line: "substrate" here = ADR-059 native layer, not the retired chapter word)
- MERGE: G/pattern_cc-loop-command-deep-dive → P/reference_loop-command-mechanics
- DELETE: G/pattern_challenge-loop-native-redesign-2026-06-11
- INDEX: add 3 today-patterns to MEMORY.md (dual-mode-gap-runner-layer, loop-traverses-graph, station-extraction-floor); no dangling pointers
- Separate pass (out of scope): global patterns.md (51K) vs individual pattern_*.md duplication

## 5. The index doc — docs/architecture/the-brana.md (new)
Cover: one paragraph — what The Brana is; brane physics as the one lens (bulk, branes, fields, leakage, open/closed strings, KK dimensions⇄frequencies, warped scales = fractal, low-pass human); human = inhabitant.
Chapters: **Space** (what things are: bulk/portfolio, branes = projects/stations/organs, skills = playbooks, agent frontmatter, sandbox as boundary; primitive table replacing substrate-primitives §1–3) · **Cycle** (loops = closed strings, Workflow = open strings, graph-as-data vs graph-as-code, rings, beats, waves, dead-letter, the seven laws, four primitives as mechanics) · **Gate** (valves by reversibility, two rooms, caller-owns-human-mode, autonomy ladder = altitude, judge policy) · **Scale** axis (ring = dimension = frequency; each level a whole system with own memory + judge).
Components table: concept → single owner doc → status (from §2–3 above).
Front-door rule: the-brana.md = what it is; idea-to-ship.md = flow view; ADR-068 Q1 closed.
"orbit" = plain word in Cycle; "Orbit" satellite component = features/autonomous-runner.md, later.

## 6. Proposed work (tasks under epic t-2337 brana-v3-redesign; none created yet)
| Task | kind / effort | blocked_by |
|---|---|---|
| A. `the-brana.md` index — cover, 3 chapters + Scale, components table, front-door rule | docs · M | — |
| B. Cluster doc hygiene — headers/pointers/merges/archives per §2–3 (idea docs + arch + guides + loops README) | chore · M | A |
| C. ✅ wave-pipeline → the-brana: absorb philosophy, redirect stub, tag sweep, README rows (t-3028, 2026-08-23) | chore · S | A |
| D. Memory tidy per §4 (+ MEMORY.md index lines) | chore · S | — |
| E. ADR housekeeping: accept ADR-068, renumber t-2980's to 086, status headers (082/080/065/build-cost-tracking), ADR-069 amend | chore · S | D1/D2 |
| F. docs/README.md full coverage sweep (repo-wide, 19 ADRs + 41 features + 2 dead rows) | chore · S | — |
| (existing) t-2490 design → un-hold after A; t-2981–2985 follow-ups; t-2834 evidence beat; t-2985 organ single-sourcing (+ Pair C fix task to add) | | |

Sequence: D1–D5 → A (operator shapes) → C + B → E → un-hold t-2490 (premortem → challenge → ADRs land).
