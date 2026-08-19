---
title: The Brana — studio guide (top-down living draft of docs/architecture/the-brana.md)
status: idea (studio in progress — walk L0 → L6, one node per exchange)
created: 2026-08-18
task: t-2490
epic: brana-v3-redesign
relates-to:
  - "[the-brana-consolidation-board](the-brana-consolidation-board.md) — per-file tidy actions + five operator decisions D1–D5"
  - "[skills-loops-graphs](skills-loops-graphs.md) — the skills-layer component (t-2490 brainstorm + 2026-08-18 synthesis)"
  - "[wave-pipeline (drained)](drained/wave-pipeline.md) — philosophy hub to be absorbed (D3)"
  - "[ADR-068](../architecture/decisions/ADR-068-v3-supersession.md) — retirement of Substrate/Orbit vocabulary; Accepted 2026-08-19; Q1 closed (front door = the-brana.md), Q2 routed to L2.1"
  - "[brana-etymology-naming](../../../brana-knowledge/dimensions/brana-etymology-naming.md) — brane physics = the one lens"
---
> **START HERE (next session):** L0 is fully ✅ (L0.1 cover, L0.2 brane-as-KK-tower, L0.3 board decisions D1–D5). We are at **L1 — three chapters + the Scale axis**. Do not descend below a node until it is ✅. Persisted here 2026-08-18 by session thebrana-50; updated 2026-08-19 resolving L0.1–L0.3; scratchpad copies are dead.

# The Brana — studio guide (top-down, living draft of `docs/architecture/the-brana.md`)

> How to use: we descend one level at a time. Each node has **IS** (one line) · **DECIDED** ✅ · **OPEN** ▢ (we discuss and define) · **DOCS** (owner first, then supporting). Every ✅/▢ line carries `[refs]` — the docs/ADRs/ideas/specs/memory it touches, so any later refactor can trace it. Marks: ✅ decided · ▢ open · ⏸ parked (later, on evidence). Full reference index in **Appendix A** (every doc in the cluster: role · status · action · chapter). Paths relative to `thebrana/` unless prefixed; `WT:` = exists only in a worktree.

---

## L0 · The Brana — the whole

**IS.** How brana turns intent into shipped work: a human living inside a space of self-contained units (branes) that loops carry through gates. One name for the whole; three chapters (Space · Cycle · Gate) and one axis (Scale) across them.

**DECIDED** ✅
- Name **The Brana**; brane physics the only lens on the cover; braña/brána discarded. `[brana-knowledge/dimensions/brana-etymology-naming.md · memory project_brana-naming]`
- "Wave pipeline" retired as umbrella; waves + queue/pump/valve/gauge survive as mechanics vocabulary. `[docs/ideas/drained/wave-pipeline.md · memory project_wave-pipeline-vocabulary · pattern_pipeline-primitives-queues-pumps-valves-gauges]`
- Human = **inhabitant** — lives in the cycle (studio), stands at the gate (cockpit), observes from the brane. `[memory user_creative-vs-operative-modes · wave-pipeline.md §two rooms, §Spectrum "low-pass filter"]`
- Front door: `the-brana.md` = what it is · `idea-to-ship.md` = how work flows (mutual pointers). Closes ADR-068 open Q1. `[docs/architecture/idea-to-ship.md · ADR-068 §Open questions #1 · docs/architecture/the-orbit.md (the vacated front door)]`
- One owner per concept; index + component docs; superseded docs → pointers. `[consolidation board §1–3 · graphify island map]`
- "orbit" plain word in Cycle now; **Orbit** = satellite component later, on evidence. `[ADR-068 §2 (vocabulary retired) · features/autonomous-runner.md · brana orbit CLI · ideas/drained/orbit-evidence-first.md]`
- Hold ADRs until this guide settles: ADR-085 (t-2490) Proposed; ADR-084 Accepted-pilot; t-2980's ADR pending renumber. `[WT ../thebrana-t-2490 ADR-085-skills-as-stations-no-atom-schema.md · WT ../thebrana-t-2837 ADR-084-upstream-skill-band-vendored-pocock-skills.md · WT ../thebrana-t-2980 ADR-085-wave-as-human-unit-pocock-ticket-shape.md]`
- ✅ L0.1 Cover paragraph locked: *"The Brana is how brana turns intent into shipped work. It lives in a bulk — the shared portfolio, the laws everything obeys — where self-contained branes sit at every scale: a project, a station, an organ, each with its own fields, confined to itself. Nothing crosses between them except memory, carried by loops that return; a workflow runs once and stays pinned to the brane it started in. Gates sit where that motion turns irreversible. And the human lives inside it, an inhabitant not an operator — working one brane's fields up close, sensing the rest only through what memory brings across."* `[the-brana.md §cover · session 9a26bc54 draft + studio resolution]`
- ✅ L0.2 Brane mapping resolved as a Kaluza-Klein tower, not a single term: **brane** = the family name for a self-contained unit; **project / station / organ** are its ring-scaled harmonics (epic/beat/micro); **bulk** is the ambient container, not itself a brane (matches the knowledge-ring's Space cell already reading "bulk / portfolio," not "knowledge brane"). This also merges two previously-separate decided bullets into one mechanism: gravity-leak (L2, "memory crosses branes") *is* the loop-as-closed-string bullet (L3) — a loop is a closed string, unpinned, free to leave its brane, and memory is what it carries; a workflow is an open string, endpoints pinned to the brane it started in. Cover carries **bulk / brane / gravity-leak** only (containment, confinement, the one thing that crosses); **open/closed strings, KK⇄frequency, RS warp, compactification** stay as chapter-level pictures (L1 Scale, L2 Space, L3 Cycle) — mechanics, not cover claims. Corroborating (non-cover) analogy filed for chapter-picture use: trading-chart timeframe zoom (1s/1m/1h/1D) = same continuous data, different arbitrary window on the same dimension — same KK tower, same "small dimension = fast." `[brana-etymology-naming.md · wave-pipeline.md §rings · 60-agent-loop-architecture.md · session 9a26bc54 + studio resolution]`

- ✅ L0.3 Board decisions D1–D5, all settled: **D1** ADR-068 accepted (status flipped 2026-08-19; its open Q1 closed → the-brana.md is the front door, Q2 routed → L2.1 primitive table). **D2** t-2980's ADR-085 → renumber to ADR-086 decided; rename itself deferred to landing time (board §3: "land the worktree ADRs — NOT now"), so `../thebrana-t-2980` is untouched. **D3** absorb `wave-pipeline.md`'s philosophy (four primitives, seven laws, two rooms, four rings) into the-brana.md's Cycle/Gate chapters + Scale axis, leave a redirect stub, tag-sweep `wave-pipeline`→`the-brana` — decision locked, execution deferred to board's task C (after the full index doc, task A, is shaped — i.e. after this guide's L1–L4 walk settles). **D4** already satisfied by L0.1/L0.2's own work: the-brana.md = what it is (front door), idea-to-ship.md = how work flows (mutual pointer added). **D5** tidy scope = this cluster now; the repo-wide `docs/README.md` sweep (19 missing ADR rows + 41 missing feature rows + 2 dead rows) is its own later chore (board task F), not part of this walk. `[the-brana-consolidation-board.md §1, §6 · ADR-068 (accepted) · WT ../thebrana-t-2980 ADR-085-wave-as-human-unit-pocock-ticket-shape.md · drained/wave-pipeline.md · docs/README.md]`

**OPEN** ▢
- (none — L0 fully resolved: L0.1, L0.2, L0.3 all ✅. Next: descend to L1.)

**DOCS.** owner `docs/architecture/the-brana.md` (new) · `brana-etymology-naming.md` · `idea-to-ship.md` · ADR-068 · `the-orbit.md` (superseded index — the model for this doc's *reading map* section) · memory `project_brana-naming` · board (scratchpad).

---

## L1 · Three chapters + the Scale axis

```
             SPACE (what things are)   CYCLE (what it does)      GATE (who decides)
knowledge    bulk / portfolio          LEARN loop, slowest        studio — you live here
epic         project brane             epic-drain                 wave ship valve
beat         station                   drain beat                 merge valve, cockpit
micro        organ                     TDD red-green              a test — no human
                                 ← SCALE axis: ring = dimension = frequency →
```

**IS.** Space = units and boundaries · Cycle = motion (loops carrying work through queues, returning) · Gate = human decisions and their placement · Scale = the same skeleton at every ring, warped; each ring a whole system with its own memory and judge.

**DECIDED** ✅
- The three-chapter split (ex-Substrate / Orbit / ground-control, one level up). `[the-orbit.md §Vocabulary · ADR-068 §2]`
- Four rings micro / beat / epic / knowledge; KK: small dimension = fast. `[wave-pipeline.md §four rings · memory project_loop-operating-laws]`
- Seven-step skeleton at every ring (ORIENT→SELECT→ACT→MEASURE→JUDGE→ASSIMILATE→RESTART). `[brana-knowledge/dimensions/60-agent-loop-architecture.md · wave-pipeline.md §skeleton]`
- Human = low-pass filter across rings. `[wave-pipeline.md §Spectrum]`

**OPEN** ▢
- ▢ L1.1 Settle the four concept collisions with one owner each: (1) loop/queue semantics — philosophy `the-brana.md` · contract `features/loops-library.md` · skill-shaped loops `skills-as-loops.md` (cite, don't re-derive); (2) autonomy rungs — `brana-v3-redesign.md` owns the ladder; `orbit-evidence-first.md`, `gentle-ai-adoption-ladder.md` cite; (3) proof-of-done — beat record (`loops-library`) owns; `build-receipts.md` = an instance; (4) skill routing — `skills-as-loops.md` classification · `skill-tiering.md` packaging · `skill-semantic-validation.md` validation. `[all named]`
- ▢ L1.2 Scale = axis (table across chapters) or fourth chapter. Rec: axis.
- ▢ L1.3 Vocabulary table (term → one-line → owner doc) — fills the gap in `docs/architecture/glossary.md` (no wave/loop/station terms). `[glossary.md · loops-library.md §vocabulary · wave-pipeline.md · skills-as-loops.md §vocabulary · memory project_wave-pipeline-vocabulary]`

**DOCS.** owner `the-brana.md` §L1 · `wave-pipeline.md` (to absorb) · `60-agent-loop-architecture.md` · `glossary.md` · `loop-first-redesign.md` §framings ledger (keep-all-lenses rule).

---

## L2 · SPACE — what things are

**IS.** The bulk (portfolio, `~/.claude/` identity layer, global rules = laws every brane obeys) and the branes in it — projects, stations, organs — each with its own fields (context, tools, contract). Skills are playbooks a station loads. Gravity leaks: memory crosses branes; tasks/tools/rules do not.

**DECIDED** ✅
- Atom = **organ file + station-admission checklist**; no typed atom schema now; manifest sketch = Non-Action evidence. `[WT skills-loops-graphs.md §Opinion + §Studio 2026-08-18 · WT ADR-085 D2/D6 · t-2490 context]`
- Station = body of a pump, not a fifth primitive; coordinate skeleton-step × band. `[wave-pipeline.md §four primitives, §lived-practice diagnosis · skills-as-loops.md §station/conveyor]`
- Skills two-tier: `disable-model-invocation` = who may *start* (invocation axis), orthogonal to human-mode. `[docs/research/2026-08-13-matt-pocock-skill-system.md §3 · t-2832 · WT ADR-084 §3]`
- Granularity floor ≥2 callers or headless need → `build` = 1 extraction (TDD loop) + 1 wiring (verify-gates fan-out). `[skills-loops-graphs.md §Opinion · skills-as-loops.md L71 boundary test · WT ADR-085 D4]`
- t-2278 stays as planned; t-2834 = evidence beat. `[skills-as-loops.md L55 · t-2278 · t-2834 · WT ADR-084]`
- Dual-mode duplication real today (3 drifted pairs) → organ files both paths Read. `[skills-loops-graphs.md §Evidence — verify-gates.md:101-154 ↔ system/agents/build-evaluator.md:55-67 ↔ _shared/challenger-gate.md:187-229; system/agents/CALIBRATION.md:25-28 vs .claude/workflows/verify-findings.js:27-28,110; _shared/adversarial-hive-mind.md ↔ hive-mind.js; build-loop.md ↔ _shared/delegation-tdd-checklist.md · t-2985]`
- Native CC agent frontmatter already owns skills:/tools:/model:/isolation:/maxTurns:/memory:/permissionMode:. `[ideas/drained/agent-definition-gaps.md · system/agents/*.md]`
- `tools:` deny = tripwire; boundary = sandbox. `[ideas/drained/runner-capability-isolation.md · ADR-062 · t-2173]`

**OPEN** ▢
- ▢ L2.1 Primitive table (closes ADR-068 open Q2; single owner replacing two re-derivations): primitives (`/loop`, `Workflow`, `/goal`, `Agent`, skills, hooks, memory) · composed blocks (hive-mind, sweep, verify-findings) · chapter each lives in. `[docs/architecture/substrate-primitives.md §1–3 · docs/architecture/agentic-primitives.md · docs/architecture/workflow-primitive.md · ADR-059 · ADR-061 · .claude/workflows/*.js · docs/guide/workflows/hive-mind.md]`
- ▢ L2.2 Station-admission checklist final: queue · stop_condition · packet in/out · dead-letter · judge policy · rooms · assimilate · restart · denied verbs; frozen after t-2834's adapter. `[skills-as-loops.md L169 trio · loops-library.md §entry frontmatter · wave-pipeline.md §layer test · WT ADR-084 §3 adapter · t-2834]`
- ▢ L2.3 Organ files: home (`system/skills/_shared/`? new `system/organs/`?), naming, rule "both paths Read, neither restates"; first three organs = the drifted pairs. `[system/skills/_shared/*.md · system/agents/CALIBRATION.md · .claude/workflows/verify-findings.js:82 (no shared imports) · t-2985]`
- ▢ L2.4 The packet (handoff): spec + AC + log + refs — typed? on disk? `[skills-as-loops.md §packet · ideas/drained/agent-interaction-architecture.md (file-contract) · ADR-047 + docs/architecture/ac-grammar.md (AC:) · ADR-081 (notes contract)]`
- ▢ L2.5 Context economy as compactification; `context:` expressing deliberate starvation. `[t-2484 · ideas/loop-task-multiagent.md (blind test-author) · memory pattern_context-engineering-2026-findings]`
- ⏸ L2.6 Manifest file — only if the 3rd binding repeats fields. `[skills-loops-graphs.md §manifest sketch]`

**DOCS.** owner `WT skills-loops-graphs.md` (t-2490 → skills-layer component) · `skills-as-loops.md` (t-2278) · `agent-definition-gaps.md` · Pocock research + `WT ADR-084` · `agentic-primitives.md` + `substrate-primitives.md` §1–3 (re-home) · `workflow-primitive.md` · `runner-capability-isolation.md` · `skill-tiering.md` / `skill-semantic-validation.md` / `agent-skills-brana-enhancements.md` · ADR-059 · `WT ADR-085` · code: `system/skills/build/{SKILL.md,phases/*}`, `system/skills/_shared/*`, `system/agents/*`, `.claude/workflows/*.js`.

---

## L3 · CYCLE — what it does

**IS.** Work moves through queues by pumps and returns. Loop = closed string (returns; the only thing that crosses branes). Workflow = open string (runs once, pinned). Graph-as-data (waves + `gate:`, tasks + `blocked_by`) walked over days by a loop; graph-as-code (Workflow scripts) runs to completion in one call. Rings micro → beat → epic → knowledge.

**DECIDED** ✅
- Rule: runs once → Workflow script; walked with humans between nodes → data + `/loop`. `[skills-loops-graphs.md §Loop vs graph · memory pattern_loop-traverses-graph-workflow-is-graph]`
- Loop contract = `features/loops-library.md` + `system/loops/` (frontmatter, beat record, denied verbs, pull interface). `[features/loops-library.md · system/loops/{README,drain-loop,epic-drain,pipeline-digest}.md · system/scripts/loops-lint.py · ideas/drained/loops-library.md (idea → pointer)]`
- Wave mechanics: ac_state approval, wave pull, gate graph, epic runner, leases; epic-drain supersedes drain-loop for epics. `[ADR-079 · ADR-080 · ADR-065 · features/plan-time-wave-graph.md, wave-board.md, wave-gate-enforcement.md, ac-state-forward-slice.md · guide/workflows/epic-drain.md, drain-loop.md · guide/features/plan-time-wave-graph.md, wave-board.md · features/backlog-v3-schema.md]`
- Seven laws. `[memory project_loop-operating-laws · wave-pipeline.md §seven laws]`
- Four mechanics primitives queue/pump/valve/gauge (+backpressure, dead-letter), closed set. `[wave-pipeline.md · loop-first-redesign.md L188–203 · pattern_pipeline-primitives-*]`
- Task = agent's unit; wave = human's unit. `[WT t-2980 ADR (→086) · memory project_pocock-adoption-ideas-2026-08-18]`
- Chains anti-pattern; orchestrated fan-out + synthesis only. `[ideas/loop-task-multiagent.md · docs/research/2026-08-14-multiagent-orchestration-lessons.md · pattern_multiagent-belongs-at-judgment-not-execution]`

**OPEN** ▢
- ▢ L3.1 Ring table — per ring: queue · pump · beat unit · record · judge · memory read/write ("layer test"). `[wave-pipeline.md §layer test · loops-library.md §beat record · system/state/decisions/*.jsonl (decision log = beat-ring record store) · features/build-receipts / ideas/drained/build-receipts.md · ADR-083 + ideas/task-time-tracking.md]`
- ▢ L3.2 `/goal` placement — iterate within a gate-free span, external done-signal; presence interlock. `[ADR-061 · ideas/drained/goal-integration-three-primitive.md · features/goal-binding-build-tdd.md (stale) · ac-grammar.md · t-2981]`
- ▢ L3.3 `blocked_by` in the frontier — amend ADR-079 §2? `[ADR-079 §2 · WT t-2980 ADR · memory pattern_wave-pull-ignores-blocked-by-ordering · Pocock research §wayfinder]`
- ▢ L3.4 Two runners: ADR-080 epic runner (current supervised pump) vs `features/autonomous-runner.md` (future Orbit satellite) — name the seam. `[ADR-080 · features/autonomous-runner.md · features/learned-eligibility.md · ADR-060 · ideas/drained/orbit-evidence-first.md]`
- ▢ L3.5 Beat record owns; receipt = instance. `[loops-library.md · build-receipts.md · ADR-076]`
- ▢ L3.6 Fresh-context-per-pull default when unattended lands. `[t-2982 · guide/workflows/epic-drain.md step 4 · ADR-060]`

**DOCS.** as listed per line; plus `.claude/workflows/{sweep,verify-findings,hive-mind}.js` (graph-as-code) · `loop-first-redesign.md` (historical, pointer) · `backlog-v3-lane-identity.md` · memory `reference_loop-command-mechanics` (canonical /loop semantics), `G/pattern_cc-loop-command-deep-dive` (merge into it), `G/pattern_wave-gate-field-must-be-wave-id-not-name`, `G/pattern_spike-investigation-strategy-vs-wave-tracked-deliverable`, `G/pattern_per-run-cap-backlog-draining`.

---

## L4 · GATE — who decides

**IS.** Valves = human gates placed by reversibility: machine judges own reversible outcomes; the human valve is mandatory for irreversible ones (approve · merge · ship). Two rooms: studio (needs thinking → agenda) and cockpit (rubber-stamps → digest). Autonomy = altitude L0→L3; L3 hard-gated on the sandbox.

**DECIDED** ✅
- Caller owns human mode; station suggests a closed-enum default; grants default-deny; presence interlock; ambiguous → agenda; irreversible → no default. `[t-2490 context · skills-loops-graphs.md §Operator decision · ADR-061 Inv.1 · loop-first-redesign.md challenger #1 (inbox secrets → default-deny) · runner-capability-isolation.md (lethal trifecta) · Pocock research (diagnosing-bugs Ph3 default; wizard confirm) · memory pattern_dual-mode-gap-resolves-at-runner-layer]`
- Panels at JUDGE/PLAN only; judge = policy arming on hard signals (t-2894); same-model self-review weakest; split verdicts own signal. `[ideas/loop-task-multiagent.md · research 2026-08-14-judge-panel-probe.md, 2026-08-14-llm-judge-panels.md · ADR-082 · features/judge-escalation-valve.md · system/agents/CALIBRATION.md · t-2894 · memory pattern_llm-judge-panel-design-rules]`
- Autonomy = routing not smarter agents; promotion by evidence, auto-demotion by shape. `[loop-first-redesign.md L200 · brana-v3-redesign.md principles 5–6 · ADR-068 §3 (shape graduation, ledger)]`
- Gate armed by an actor external to the loop. `[wave-pipeline.md · memory pattern_gate-armed-by-the-party-it-constrains · guide/workflows/epic-drain.md (3)]`
- L3 hard-gated on ADR-062; `tools:` deny = tripwire. `[ADR-062 · t-2173 · runner-capability-isolation.md]`

**OPEN** ▢
- ▢ L4.1 Rooms as queues (studio agenda · cockpit digest): peek/pull/ack; valve-feeders classify. `[wave-pipeline.md §two rooms · ADR-063 pending-questions store · features/pipeline-digest.md + system/loops/pipeline-digest.md · ideas/statusline-pipeline-awareness.md · t-2825 TUI]`
- ▢ L4.2 `ask()` compile table (inside/valve/none) — prose contract at the runner layer. `[skills-loops-graphs.md §manifest sketch · ADR-062 · guide/workflows/epic-drain.md (8) escalation routing]`
- ▢ L4.3 Judge policy shape: triggers, size 3–5, blind, diversity axes (Claude-only), cost governor. `[t-2894 · ADR-082 · loop-task-multiagent.md · features/stacked-verdict-at-the-valve.md + ADR-081]`
- ▢ L4.4 Valve inventory: AC approve · wave ship · merge · ship-to-main · re-arm — who / where surfaced / reversibility / default. `[ADR-079 (ac approve) · ADR-080 (wave ship, arm) · ADR-060 (merge, promote) · guide/workflows/branching.md · CLAUDE.md §Integration model · G/pattern_challenge-wave-pipeline-valve-order-2026-08-14 (review-budget bottleneck)]`
- ⏸ L4.5 Orbit satellite: what, when, own component doc. `[features/autonomous-runner.md · ADR-068 · orbit-evidence-first.md]`

**DOCS.** owner `the-brana.md` §Gate (absorbs wave-pipeline §two rooms + §Spectrum) · `brana-v3-redesign.md` · ADR-060/061/062/063 · `loop-task-multiagent.md` + judge research + ADR-081/082 + `judge-escalation-valve.md`, `stacked-verdict-at-the-valve.md` · `orbit-evidence-first.md`, `gentle-ai-adoption-ladder.md` · `runner-capability-isolation.md` · gauges: `statusline-pipeline-awareness.md`, `pipeline-digest` · memory `user_creative-vs-operative-modes`, `pattern_llm-judge-panel-design-rules`, `pattern_multiagent-belongs-at-judgment-not-execution`, `G/pattern_loop-exit-gate-discipline`, `G/pattern_loop-termination-three-mechanism-rule`, `pattern_looptrap-autonomy-findings`.

---

## L5 · Components — the doc map
Filled as L1–L4 settle: concept → owner doc → status → chapter. Seed = Appendix A + board §2–3.

## L6 · Hygiene — the tidy tasks
Board §6: A index · B doc hygiene · C wave-pipeline absorb + stub + tag sweep · D memory tidy · E ADR housekeeping · F README sweep. Created after L0–L4 settle.

## Walk order
L0 (cover · lens · D1–D5) → L1 → L2 → L3 → L4 → L5 → L6. One node per exchange; each ✅ written back here.

---

## Appendix A · Reference index (the whole cluster — role · status · action · chapter)

### ADRs (`docs/architecture/decisions/`)
| ADR | role | status | action | chapter |
|---|---|---|---|---|
| ADR-002 tasks-as-data-layer | tasks.json is the store | Accepted | cite | Cycle |
| ADR-047 acceptance-criteria-schema | AC: grammar | Accepted | cite (ac-grammar.md is SSOT) | Space/Cycle |
| ADR-049 mandatory-challenger-gate | challenger before CLOSE | Accepted | cite; organ owner for repair loop | Gate |
| ADR-050 loop-request-protocol | blast-radius constants, loop prompts | Accepted | cite | Cycle |
| ADR-059 multi-agent-substrate-selection | native CC vs ruflo vs agy | Accepted | cite (note: "substrate" here ≠ retired chapter word) | Space |
| ADR-060 branch-strategy-autonomous-agents | dev→main, worktrees, human merges | Accepted; amendment scoped in ADR-068 never landed | cite; track amendment | Gate |
| ADR-061 goal-integration-three-primitive | /loop /goal Workflow split; presence interlock | Accepted | cite; L3.2 | Cycle/Gate |
| ADR-062 runner-executor-sandbox | bwrap boundary | Accepted | cite | Gate |
| ADR-063 pending-questions-store | durable NEEDSHUMAN | Accepted | cite; L4.1 | Gate |
| ADR-065 epic-as-hierarchy-top | epic membership | Accepted; missing "amended by ADR-079" | add back-pointer | Cycle |
| ADR-068 v3-supersession | retires Orbit/Substrate vocabulary; 8 mechanics carried | **Proposed** | **D1 accept**; Q1→the-brana.md; Q2→L2.1 | L0 |
| ADR-069 lane-identity-miss-semantics | lanes; 2/6 refuted by t-2516 | Proposed | amend / partial-supersede | Cycle |
| ADR-074 step-state-contract | build_step | Accepted | cite | Cycle |
| ADR-076 build-receipts | receipts as evidence | Accepted | cite; L3.5 | Cycle |
| ADR-078 stale-task-park-via-tag | +parked | Accepted | cite | Cycle |
| ADR-079 backlog-drain-loop-handoff | ac_state, wave pull, WIP | Accepted (hub, deg 36) | cite; L3.3 amend? | Cycle |
| ADR-080 plan-time-wave-graphs-epic-runner | gate graph, epic runner, leases | Accepted (date mismatch) | fix header; cite | Cycle |
| ADR-081 stacked-verdict-evidence-composition | notes contract | Accepted | cite | Gate |
| ADR-082 multi-agent-sizing-function | judge rungs, panels | accepted (no YAML) | add frontmatter | Gate |
| ADR-083 time-tracking-mechanism | effort vs cycle time | Accepted | add "supersedes build-cost-tracking" pointer | Cycle |
| WT ADR-084 upstream-skill-band-vendored-pocock-skills (t-2837) | vendoring + adapter | Accepted pilot-only | land after guide | Space |
| WT ADR-085 skills-as-stations-no-atom-schema (t-2490) | verdict | Proposed | hold; land after | Space |
| WT ADR-085→086 wave-as-human-unit (t-2980) | sizing rule, frontier | Proposed | **D2 renumber**; hold | Cycle |

### Architecture (top-level `docs/architecture/`)
| doc | role | status | action | chapter |
|---|---|---|---|---|
| the-brana.md | index / front door | NEW | write (this guide) | L0 |
| idea-to-ship.md | flow view (deg 32) | live | mutual pointer with the-brana | L0 |
| the-orbit.md | old index | superseded → ADR-068 | pointer-only; model for reading-map | L0 |
| substrate-end-state.md | Orbit capstone | superseded | pointer-only | Gate |
| substrate-primitives.md | primitive set §1–3 still-live | superseded; Q2 open | re-home §1–3 into L2.1 | Space |
| agentic-primitives.md | primitive taxonomy | no status | reconcile with L2.1 (detailed ref under it) | Space |
| workflow-primitive.md | Workflow API | no status (field note) | add status; cite | Space |
| ac-grammar.md | AC SSOT | live | cite | Space/Cycle |
| glossary.md | job vocabulary | no wave/loop terms | point to L1.3 table | L1 |

### Feature specs (`docs/architecture/features/`)
| spec | role | status | action | chapter |
|---|---|---|---|---|
| loops-library.md | loop contract | shipped | **owner** | Cycle |
| plan-time-wave-graph.md · wave-board.md · wave-gate-enforcement.md | wave mechanics | shipped; no status headers | add headers; cite | Cycle |
| ac-state-forward-slice.md | wave-0 ac_state | implemented; approval flow superseded by ADR-079 | mark | Cycle |
| backlog-v3-schema.md | v3 schema | live | cite | Cycle |
| build-loop-redesign.md | build steps/strategies/gates vocab | no status | add header; cite (Challenger Gate matrix) | Space/Gate |
| autonomous-runner.md | runner stages 1–3 | live | L3.4 seam; future Orbit satellite | Cycle/Gate |
| learned-eligibility.md | runner stage 4 | design-only | cite | Gate |
| judge-escalation-valve.md · stacked-verdict-at-the-valve.md | judge rungs; verdict | shipped | cite | Gate |
| pipeline-digest.md | L0 gauge | shipped | cite | Gate |
| goal-binding-build-tdd.md | /goal→TDD | specifying, stale | tie to t-2981 or park | Cycle |
| consensus-primitive.md | cross-model quorum | design-only; superseded by hive-mind+ADR-082 | mark | Gate |
| brana-v2-compute-model.md | v2 | "active" but v3 governs | mark superseded (ADR-068) | L0 |
| build-cost-tracking.md | old cost tracking | superseded by ADR-083 (no pointer) | add pointer | Cycle |
| checkpoint-resume.md · mission-control-cli.md · operating-model.md | misc | no status | add headers | — |

### Guides & loop entries
| doc | role | status | action | chapter |
|---|---|---|---|---|
| guide/workflows/epic-drain.md | graph-walking runner | active | say "supersedes drain-loop for epics" | Cycle |
| guide/workflows/drain-loop.md | drain runner | active | say superseded-for-epics | Cycle |
| guide/workflows/branching.md | two-tier | live | cite | Gate |
| guide/workflows/hive-mind.md | native hive-mind | live | cite | Space |
| guide/workflows/challenge.md | two-model challenge | superseded by ADR-082 | mark | Gate |
| guide/features/plan-time-wave-graph.md · wave-board.md | user guides | live | cite | Cycle |
| system/loops/README.md | catalog index | dual authority w/ spec | pointer to spec | Cycle |
| system/loops/{drain-loop,epic-drain,pipeline-digest}.md | catalog entries | frontmatter only | keep | Cycle |
| system/scripts/loops-lint.py | validate.sh check 71 | live | cite | Cycle |

### Idea docs (`docs/ideas/`, `drained/`)
| doc | role | status | action | chapter |
|---|---|---|---|---|
| WT ../thebrana-t-2490/docs/ideas/skills-loops-graphs.md | skills/loops/graphs + Pocock + evidence + verdict | wip (dec648e6) | **owner** skills layer; later → drained/ | Space |
| ideas/loop-task-multiagent.md | judgment panels | draft (t-2887) | keep-as-component | Gate |
| ideas/statusline-pipeline-awareness.md | statusline gauge | draft | keep | Gate |
| ideas/task-time-tracking.md | beat timing | draft | keep | Cycle |
| drained/wave-pipeline.md (+design.html, infographic-prompt) | philosophy hub | **active in drained/** | **D3 absorb → the-brana; redirect stub** | L1 |
| drained/loops-library.md | idea → spec | drained | pointer → features/loops-library.md | Cycle |
| drained/loop-first-redesign.md | lineage ledger + framings | historical | pointer-only | L1 |
| drained/skills-as-loops.md | t-2278 plan; station/packet/conveyor; trio | draft (deg 3!) | keep-as-component; wire from index | Space |
| drained/brana-v3-redesign.md | ladder, ledger, shapes | governing per ADR-068 | keep | Gate |
| drained/brana-v3-design.html | v3 visual | — | keep, header | Gate |
| drained/goal-integration-three-primitive.md | goal×loop×wave | draft | merge → the-brana Cycle + ADR-061 | Cycle |
| drained/goal-adoption-brana-skills.md · goal-completion-heuristics-h5-h8.md · loop-goal-native-planning.md | goal adoption / heuristics / AC grammar | idea / idea / implemented | merge / pointer / pointer(ac-grammar) | Cycle |
| drained/orbit-evidence-first.md | start smaller | idea | keep | Gate |
| drained/runner-capability-isolation.md | sandbox | idea (t-2173) | keep | Gate |
| drained/build-receipts.md | receipts | draft | keep; receipt = beat-record instance | Cycle |
| drained/backlog-v3-lane-identity.md | lanes | idea | keep | Cycle |
| drained/gentle-ai-adoption-ladder.md | rungs, Pocock mining | draft | keep; cite ladder owner | Gate |
| drained/agent-definition-gaps.md | native agent frontmatter | inventory | keep; add header | Space |
| drained/agent-skills-brana-enhancements.md · skill-tiering.md · skill-semantic-validation.md | skill packaging/validation | idea | keep | Space |
| drained/skill-lifecycle-manager.md · mission-control.md | lifecycle / dashboard | old | merge → skills-as-loops / statusline-pipeline-awareness | Space/Gate |
| drained/brana-operating-model.md | legacy hub (supersedes 4) | idea | keep as pointer-hub | L0 |
| drained/universal-doc-graph.md | doc graph | idea | keep (meta) | — |
| drained/challenger-outer-loop-gate.md · build-skill-gate-hardening.md | implemented gates | implemented | pointer → ADR-049 / build phases | Gate |
| drained/enforced-delegation.md · phase0-preregistration.md · claude-gemini-orchestration.md | killed / method / Gemini split | killed | pointer → ADR-059 routing | Space |
| drained/skill-auto-router.md · dynamic-skill-routing.md · agent-interaction-architecture.md · agent-observability-learning.md · enforcement-vs-injection.md · statusline-v2-backlog-intelligence.md | superseded | dead | archive → docs/archive/ | — |

### Research (`docs/research/`)
`2026-08-13-matt-pocock-skill-system.md` (t-2830; Space) · `2026-08-14-judge-panel-probe.md`, `2026-08-14-llm-judge-panels.md`, `2026-08-14-multiagent-orchestration-lessons.md` (Gate) · `2026-06-11-loop-native-redesign.md` (Cycle, historical) · `substrate-leverage-audit.md` (Space, calibration) · `loop-engineering-*.md`, `loop-examples-wild-2026-07.md`, `loop-framework-landscape-2026-07.md` (Cycle, external landscape) · `docs/reviews/brana-v3-challenge-2026-07-19.md`, `-07-21.md` (Gate).

### Knowledge (`brana-knowledge/dimensions/`)
`brana-etymology-naming.md` (L0) · `60-agent-loop-architecture.md` (L1 skeleton) · `cc-native-orchestration-2026` (Space) · `49-agent-era-systems-patterns.md`, `50-auto-learning-patterns.md` (Cycle/knowledge ring).

### Code (owners of behaviour the guide describes)
`system/skills/build/{SKILL.md,phases/*.md}` · `system/skills/_shared/{challenger-gate,adversarial-hive-mind,delegation-tdd-checklist,guided-execution,epic-ancestor-walk,branch-prefix}.md` · `system/agents/{challenger,build-evaluator,CALIBRATION}.md` · `.claude/workflows/{sweep,verify-findings,hive-mind}.js` · `system/loops/*` · `system/scripts/loops-lint.py` · `system/cli/rust/crates/brana-cli/src/commands/{wave,queue,stacked_verdict}.rs` · `.claude/tasks.json` (graph-as-data).

### Memory (project `P/`, global `G/`)
KEEP: `P/project_brana-naming` · `P/project_loop-operating-laws` · `P/project_pocock-adoption-ideas-2026-08-18` · `P/reference_loop-command-mechanics` (canonical) · `P/pattern_pipeline-primitives-queues-pumps-valves-gauges` · `P/pattern_looptrap-autonomy-findings` · `P/pattern_llm-judge-panel-design-rules` · `P/pattern_multiagent-belongs-at-judgment-not-execution` · `P/pattern_dual-mode-gap-resolves-at-runner-layer_2026-08-18`, `P/pattern_loop-traverses-graph-workflow-is-graph_2026-08-18`, `P/pattern_station-extraction-floor-two-tier-atom_2026-08-18` (add to MEMORY.md) · `P/topic_challenger-review` · `P/user_creative-vs-operative-modes` · `G/pattern_loop-exit-gate-discipline` · `G/pattern_loop-termination-three-mechanism-rule` · `G/pattern_per-run-cap-backlog-draining` · `G/pattern_wave-gate-field-must-be-wave-id-not-name` · `G/pattern_wave-pull-ignores-blocked-by-ordering` · `G/pattern_spike-investigation-strategy-vs-wave-tracked-deliverable` · `G/pattern_primitive-routing-test-shape-not-vocabulary` · `G/pattern_factory-crew-rehearsal-n1`.
UPDATE: `P/project_loop-native-redesign` (chain → The Brana) · `P/project_wave-pipeline-vocabulary` (demote to mechanics) · `P/project_brana-v2-compute-model` (ruflo closed) · `P/project_system-architecture-current` (re-verify) · `G/pattern_challenge-wave-pipeline-valve-order-2026-08-14` (keep bottleneck) · `G/pattern_native-workflow-substrate-calibration` (disambiguate "substrate").
MERGE: `G/pattern_cc-loop-command-deep-dive` → `P/reference_loop-command-mechanics`. DELETE: `G/pattern_challenge-loop-native-redesign-2026-06-11`.

### Decision stores (two, distinct)
| store | what it is | cluster relevance | action | chapter |
|---|---|---|---|---|
| `docs/architecture/decisions/ADR-*.md` | architecture decision records (82 files; index in `docs/README.md`) | the ~23 ADRs tabled above | header fixes; README rows; land the 3 worktree ADRs after the guide | all |
| `system/state/decisions/*.jsonl` (+ `archive/`) | **decision log** — per-beat records written by build/close (`type: decision`, "Built/Completed t-NNN …") and challenger `type: concern` entries with `target`/`refs`; 1,166 entries 2026-03 → 2026-08 | 50 entries (45 decisions, 5 concerns; e.g. 2 concerns on `wave-pipeline-valve-order`, records for t-2827/2895/2904/2908/2909/2831/2833) | cite as the **beat-ring record store** (L3.1 ring table: "record" column) and as evidence base for the outcome ledger (ADR-068 §3, brana-v3-redesign); no tidy — append-only | Cycle / Gate |

### Tasks (live)
t-2490 design (on hold, worktree) · t-2278 (stays) · t-2834 (evidence beat, unstarted) · t-2837 (ADR-084 branch) · t-2980 (ADR→086 branch) · t-2981 tdd pilot · t-2982 fresh-context · t-2983 phase-boundary tree · t-2984 prototype branch · t-2985 organ single-sourcing A/B (+ Pair C to file) · t-2887/2889/2894–2896 judge panels · t-2173 sandbox · t-2484 context economy · t-2828 (done) · t-2831–2836 Pocock batch · t-2838 skill-system rethink map · t-2851–2853 knowledge band · t-2825 TUI · epic t-2337 brana-v3-redesign · epic t-2811 backlog-drain (delivered) · epic t-2820 loop-first.
