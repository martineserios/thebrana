# ADR-085: Skills as stations — composition via loops and graphs, no atom schema

**Status:** Proposed (2026-08-18) — pending `/brana:challenge --deep` (user-invoked; see Challenge record)
**Task:** t-2490 (epic `brana-v3-redesign`, t-2337) — closes the scope challenge t-2490 filed against t-2278 (2026-07-27)
**Source:** [docs/ideas/skills-loops-graphs.md](../../ideas/skills-loops-graphs.md) (brainstorm 2026-08-17/18) · [Pocock skill-system research](../../research/2026-08-13-matt-pocock-skill-system.md) (t-2830) · [skills-as-loops (drained)](../../ideas/drained/skills-as-loops.md) (t-2278 audit)
**Related:** [ADR-069](ADR-069-lane-identity-and-miss-semantics.md) (graph-engineering verdict lineage, t-2488) · [ADR-079](ADR-079-backlog-drain-loop-handoff.md) / [ADR-080](ADR-080-plan-time-wave-graphs-epic-runner.md) (loops walk wave graphs) · [ADR-084](ADR-084-upstream-skill-band-vendored-pocock-skills.md) (vendored Pocock primitives, pilot t-2834) · [ADR-062](ADR-062-runner-executor-sandbox.md) (unattended runner) · [ADR-060](ADR-060-branch-strategy-autonomous-agents.md) (runner `claude -p` per worktree) · [loops-library](../features/loops-library.md) (t-2826)

## Context

t-2490 proposed making skills **atomic** — one job, typed input/output — and composing them into procedures via loops and graphs, so one atom is reusable across graphs ("design for graph engineering"). It was gated on t-2488 and explicitly forbidden from papering over t-2278's evidence-based de-risking: t-2278's real audit of 34 first-party skills right-sized skills-as-loops to a focused L refactor (22 skills untouched; the pipeline/assembly-line model deferred as a north-star that must be *earned* by evidence that single-station loops hand off cleanly).

Between t-2490's filing (2026-07-27) and this decision, the ground moved:

1. **The outer graph layer shipped without touching skill internals.** Waves + `gate:` (ADR-080) are a graph as data; `system/loops/` (loops-library, 2026-08-17) is a typed, committed loop catalog (`autonomy`, `drains:`/`fills:`/`spawns:`, `records:`); `epic-drain` topo-sorts and walks the wave graph, invoking `/brana:build` **whole** as a station. Skills became graph nodes with zero decomposition.
2. **A code-graph runtime already exists**: the `Workflow` tool (`agent()` nodes, `pipeline()`/`parallel()` edges, `schema` for typed returns) with three committed graphs (`sweep.js`, `verify-findings.js`, `hive-mind.js`) — used only for judgment fan-out, never for the main procedure.
3. **An untyped primitive layer is already in production**: `system/skills/_shared/*.md` (epic-ancestor-walk, branch-prefix, guided-execution, adversarial-hive-mind, smart-router…) and `system/agents/`.
4. **Pocock's two-tier pattern is entering brana via ADR-084** (thin user-invoked wrapper → model-invoked primitive; pilot t-2834 vendors `diagnosing-bugs` inside `/brana:fix`'s shell). Read structurally, his repo's stance is: *a skill is a node, never the graph; the graph lives in tracker data and router prose; the loop is the walker (a human or `claude --bg`), not a skill; in-skill fan-out only for verdicts.* Brana converged on the same architecture independently — and added the loop runtime and code graphs Pocock lacks.

The one precise gap the brainstorm surfaced: two disjoint invocation surfaces — **human-supervised, one-at-a-time** (skills, `AskUserQuestion`-native, callable whole as a loop station) and **headless fan-out** (Workflow `agent()`, no human) — with no shared unit that runs both ways. `/brana:build` can be a whole station for a supervised loop but cannot be a `Workflow` node. This is not a missing contract; it is a monolith *by design* — the phase files internalize the graph precisely to carry enforcement (spec-gate, checkpoints, evaluator, docs-before-close), which Pocock has none of.

**The gap is causing pain today** (duplicated-logic test, thebrana-50 synthesis session, 2026-08-18 — three pairs, all *drifted* duplication): (A) `verify-gates.md:101-102` ↔ `system/agents/build-evaluator.md:55-67` restate the MET/PARTIAL/MISSED rubric; `verify-gates.md:120-154` ↔ `_shared/challenger-gate.md:187-229` restate the repair loop near-verbatim; and a live **contradiction** — challenger `CALIBRATION.md:25-28` ("SPLIT never counted FALSE_POSITIVE") vs `verify-findings.js:27-28,110` ("ties drop to FALSE_POSITIVE"), plus the JS emitting `UNVERIFIED` (`:111`) absent from its own enum (`:66`). (B) `_shared/adversarial-hive-mind.md` ↔ `hive-mind.js`: lens sets share only "systems"; the ≥2-worker corroboration rule is prose-only; the md routes through `verify-findings.js`, the js forbids it. (C) `build-loop.md` ↔ `_shared/delegation-tdd-checklist.md`: delegated agents get a materially weaker TDD contract (no red-commit / `tests_required`, no TEST→IMPLEMENT gate); **no headless TDD prompt exists anywhere** in workflows or loops — runners inherit TDD only by invoking the skill whole. The observed fix direction is not a typed schema: it is **single-sourcing each organ as a file both paths `Read`** — `agent()` nodes can Read files; Workflow JS itself cannot import (`verify-findings.js:82`).

## Decision

**D1 — Verdict on t-2278: leave as planned.** Its de-risked scope (routing heuristic + ADR, ~2 standalone loops, ~2 workflows formalized, ~4 loop-bodies wired to drain waves, 2 retires, 22 skills untouched) stands unchanged. Its blocker (backlog-v3 schema / waves) has landed; it is unblocked, not reopened. The pipeline north-star stays deferred; nothing here earns it.

**D2 — No new atom schema.** Brana does not introduce a typed atom/station manifest, a new primitive type, or a per-phase I/O schema. Composition uses what exists: skills (nodes), waves + `blocked_by` (graph as data), `Workflow` scripts (graph as code), `system/loops/` (loops), `_shared/` blocks + agents (primitives), hooks (deterministic edges), router docs (prose routing — `idea-to-ship.md`, `delegation-routing.md` stay prose; a router need not be code).

**D3 — The atom contract is Pocock's two-tier, applied to new and adapted skills.** An atom is a *model-invoked* skill or `_shared/` block with (a) one job, (b) no `AskUserQuestion` on its main path, (c) a schema'd return when called as a Workflow node. Wrappers are thin, user-invoked, and own orchestration + gates. Mechanism: t-2832's `disable-model-invocation` taxonomy + ADR-084's DEPEND wrappers. No existing monolith is rewritten to satisfy this; it governs what is added or adapted.

**D4 — Granularity floor.** A phase file becomes a separately-invocable station **only when it has ≥2 callers or must run headless.** Otherwise it stays a phase file inside its skill. Applied to `/brana:build` this yields **one extraction and one wiring**, not nine stations: the **TDD loop** (`build-loop.md`; needed by build and fix, must run under a runner — and today has no headless counterpart, pair C above) and the **judgment organs** (verdict rubric, repair loop, corroboration rule) that pairs A/B show restated across `verify-gates.md`, `_shared/challenger-gate.md`, `_shared/adversarial-hive-mind.md`, `system/agents/build-evaluator.md`, `hive-mind.js`, `verify-findings.js` — **single-source each as one file that both the skill phase and the `agent()` prompt `Read`**, then delete the restatements. That is the mechanism of "wiring": a shared organ file, not a schema. CLASSIFY/SPECIFY/DECOMPOSE (human judgment) and the gates (enforcement) stay in the wrapper.

**D5 — The dual-mode gap resolves at the runner layer, not the skill layer.** Headless nodes are agents/Workflow prompts (verdicts, mechanical work); supervised stations are skills. Where one station must run both ways, the runner (`claude -p` per worktree, ADR-060) runs the *skill* with its questions answered by policy — ADR-062 territory. **Human mode (`inside | valve | none`) is set by the caller, never by the station**; a station may only *suggest* a default per named ask (operator decision, thebrana-50 synthesis session, 2026-08-18 — a typed reading of ADR-062, not a skill-schema change). No dual-mode unit abstraction is built.

**D6 — Evidence before generalization.** t-2834 (vendor `diagnosing-bugs` into `/brana:fix`) is the evidence beat: brana's station contract is *read off its adapter* (inputs mapped, output homes, denied verbs), not designed abstractly. A second bounded pilot (vendor `tdd` per ADR-084, `build-loop.md` calls it) follows only if t-2834's seam holds. Any station-admission checklist (queue · stop · packet in/out · dead-letter · judge policy · rooms · assimilate · restart) is applied to *bindings that become stations*, starting with t-2834 — never as a gate on all ~40 skills. A manifest file is written only if a third binding shows the same fields repeating (the "generalize after 2–3 bindings" rule three prior docs state independently).

## Consequences

- t-2490's own AC are met by verdict, not by build: skill audit = t-2278's 34-skill classification stands (re-verified against Pocock's tiers, no reclassification); atom contract = D3 + D4; t-2278 verdict = D1; ADR = this; follow-ups = below.
- `/brana:build` and `/brana:close` stay monoliths and stay the supervised entry. The cost accepted: they remain non-droppable into `Workflow` graphs. The benefit kept: enforcement lives in one place.
- Skill authors get a rule they didn't have: new/adapted units are two-tier (D3), and the floor (D4) says when a phase earns extraction. `disable-model-invocation` becomes load-bearing (t-2832 must ship).
- The loops-library keeps ownership of runtime organs (dead-letter, ASSIMILATE write-on-exit, RESTART state) — cross-referenced, not absorbed here (its own out-of-scope list, t-2826).
- Risk retained: churn on daily drivers if D6's pilots are skipped and generalization happens from vocabulary rather than a live adapter (the skills-as-loops load-bearing lesson: test hypotheses against a behavior's *shape*).

## Non-Actions (explicitly not adopted)

| Not adopted | Why |
|---|---|
| Decomposing `build`/`close`/`backlog`/`brainstorm` into a 9-station graph (t-2278's north-star, t-2490's original framing) | No evidence single-station loops hand off lossily *today*; the monoliths carry enforcement; over-decomposition = every hop a context re-entry. Deferred, not rejected — earned only via D6. |
| A typed atom / station manifest (`input/output schema, context:, skills:, tools:, judge:, model:, asks:`) — drafted 2026-08-18 in the thebrana-50 synthesis session | Overshoot: most fields are already owned (native CC agent frontmatter; skills-as-loops' stop/verifier/queue trio; loops-library `model:{preflight,act,judge,records}`; packet = typed I/O; two rooms). Kept as evidence of what a manifest *would* need; written only after a third binding repeats fields. |
| A dual-mode (supervised + headless) unit abstraction | Dissolves at the runner layer (D5). |
| `build.graph.json` (PHASES table as graph-as-data) with `load.md` dissolved into per-station `context:` blocks — proposed in the same 2026-08-18 studio sketch as "decomposition without churn" | Deferred under D6, not rejected: it is the manifest in another file format. Earns itself only if the t-2834 → t-2981 pilots plus the single-sourcing in D4 leave build's phase graph as the *remaining* duplication — today the duplication is in the organs, not the routing. |
| A per-ask `suggested_default + room` table on stations | Schema creep until ≥2 bindings show named asks repeating. Principle (caller owns human mode) adopted; table deferred. |
| Adopting Pocock's `wayfinder` decision-tickets, `triage` 5-role labels, `codebase-design` vocabulary | Covered by brainstorm-deep → challenge ×2 → plan; by `ac_state`; rejected in t-2830 P8 respectively. |
| Regressing the loop to a human conveyor (`/implement`, `/clear`, repeat) | Brana's committed, valved loop runtime is the correct evolution of that habit. |
| A `/graph` command | A graph is a shape built two ways already (Workflow script; data walked by a `/loop`). |

## Follow-ups (filed under t-2490 → t-2337)

1. Second ADR-084 pilot: vendor `tdd`, have `build-loop.md` call it — blocked_by t-2834 (D6).
2. `epic-drain` step 4: state fresh-context-per-pull (runner spawns `claude -p` per task, ADR-060) as the default once unattended lands — docs, S.
3. Fold Pocock's ordered phase-boundary tree (continue / `/clear` / `/handoff` / subagent / `/compact`) into `context-budget.md` — docs, S.
4. `strategies.md` spike ANSWER: keep the throwaway on `prototype/<name>`, link from the graduated task — docs, S, low.
5. Single-source the drifted judgment organs found by the duplicated-logic test (Context, pairs A/B) — verdict rubric, repair loop, corroboration rule — as files both the skill phase and the `agent()` prompt `Read`; fix the CALIBRATION.md ↔ verify-findings.js SPLIT/FALSE_POSITIVE contradiction and the `UNVERIFIED`-not-in-enum defect as part of it (D4's wiring item).
6. t-2278: context note — verdict D1, unblocked, scope unchanged.

## Challenge record

- 2026-08-18: `/brana:challenge --deep` is user-invoked (`disable-model-invocation: true`, same block t-2837 hit) — **pending the operator running it.** Status stays Proposed until then. Peer synthesis (thebrana-50, 2026-08-18) independently reached the same shape from 11 prior docs and 4 readers, and added D5's caller-owns-human-mode principle and D6's checklist scoping — recorded as corroboration, not as the challenge.
