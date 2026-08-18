---
title: Skills, loops, graphs — where each primitive lives (t-2490 brainstorm)
status: idea
created: 2026-08-18
task: t-2490
epic: brana-v3-redesign
relates-to:
  - "[skills-as-loops (drained)](drained/skills-as-loops.md) — t-2278's parked north-star"
  - "[loops-library feature](../architecture/features/loops-library.md) — shipped 2026-08-17"
  - "[idea-to-ship spine](../architecture/idea-to-ship.md) — brana's main flow (t-2831)"
  - "[Pocock skill-system research](../research/2026-08-13-matt-pocock-skill-system.md) — t-2830, ADR-084"
  - "[ADR-069](../architecture/decisions/ADR-069-lane-identity-and-miss-semantics.md) — graph-engineering verdict lineage (t-2488)"
---
# Skills, loops, graphs — where each primitive lives

> Brainstormed 2026-08-17/18 under t-2490 ("Rethink skills as atomic reusable units composed via loops and graphs"). Work in progress — persisted incrementally.

## Seed

t-2490 asked: make skills ATOMIC (one job, typed in/out) and compose them via loops and graphs, so the same atom is reusable across graphs. Gated on t-2488 (graph-engineering brainstorm → ADR-069). Explicitly must not paper over t-2278's evidence-based de-risking ("22 skills stay untouched; pipeline/assembly-line = deferred north-star").

## Loop vs graph — the plain-language distinction (operator asked, 2026-08-18)

- **Loop** = one process repeating until a stop condition: pick → do → check → repeat. One path that circles back. Achieved natively with `/loop` (or `ScheduleWakeup`); brana commits loop prompts to `system/loops/` so they outlive a session.
- **Graph** = the *organization* of many units with explicit routing (nodes = agents/skills/stations, edges = hand-offs, advance vs bounce). A loop is a graph whose path returns to an earlier node (Ksenia Se, via t-2488). CC has no `/graph` command because a graph is a *shape you build*, two ways in this repo:
  1. **As code, executed once per call** — the `Workflow` tool: `agent()` = node, `pipeline()` = chained edges without barrier, `parallel()` = fan-out with barrier. `sweep.js`, `verify-findings.js`, `hive-mind.js` are hand-written graphs.
  2. **As data, walked over time by a loop** — waves + `gate:` (and tasks + `blocked_by`) in `tasks.json`; `epic-drain` topo-sorts and walks it one wave at a time with humans between nodes.
- Rule of thumb: graph that must run to completion in one shot → `Workflow` script. Graph walked incrementally over days with human valves → data + a `/loop` walker. **A loop traverses a graph over time; a Workflow script *is* a graph that runs to completion in one call.**

## How a skill fits as a node — the narrowed gap

- **Skill as a station in a loop-walked wave graph — works today.** `epic-drain` step 4 runs `/brana:backlog start <id>` → the full, unmodified `/brana:build` (AskUserQuestions and all). Works because the loop is *supervised*: a human answers the skill's questions live. Skill = opaque black-box station; nothing decomposed.
- **Skill as a node in a Workflow-authored graph — does NOT work today.** `agent()` spawns a fresh headless subagent with no path to a human; a skill built from `AskUserQuestion` calls cannot be dropped into `pipeline()`/`parallel()`. The three Workflow graphs only ever call `agent("do X, return Y")`, never `Skill(...)`.
- **So the precise gap:** two disjoint invocation surfaces — *human-supervised, one-at-a-time* (skills, callable as a loop's whole station) and *headless fan-out* (Workflow `agent()`, callable as a graph node) — and no shared unit runs both ways without writing the logic twice. Sharper than t-2490's original "atom contract" framing, and not answered by loops-library or the existing Workflow graphs.

## What already exists that t-2490 assumed was empty

1. **Outer composition solved by loops-library** (shipped 2026-08-17): `system/loops/` entries carry a typed frontmatter contract (`autonomy`, `drains:`/`fills:`/`spawns:`, `records:`) + a single-sourced beat-record schema. Human-invocable (`/loop`) and loop-invocable (`spawns:`). The unit it wraps is a *whole skill*.
2. **Ephemeral agent-level atoms** already exist: `agent(prompt, {schema})` gives typed I/O per node — scoped to one Workflow run, not reusable across skills.
3. **Untyped cross-skill reuse already in production**: `system/skills/_shared/*.md` (epic-ancestor-walk, branch-prefix, guided-execution, adversarial-hive-mind, smart-router…) — small single-purpose procedures Read-and-followed by several skills. A de-facto atom pattern with no schema.

## Pocock's approach — what he says and what we can infer

Source: `ask-matt` SKILL.md fetched live 2026-08-18 + t-2830 research + ADR-084.

He never uses the words "skills vs loops/graphs", but his repo takes a clear structural stance:

1. **A skill is a node, never the graph.** No skill contains a multi-phase state machine. `implement` is 12 lines: drive `/tdd`, then `/code-review`, commit — a tiny *linear graph written as prose in a wrapper* over single-job primitives. Two tiers, split by the native `disable-model-invocation` flag: user-invoked wrappers vs model-invoked primitives.
2. **The graph lives in data, outside skills.** `to-tickets` writes tickets with blocking edges; `wayfinder` charts decision tickets and defines the *frontier* (unblocked + unclaimed) plus "fog of war". Structurally the same object as brana's waves + `gate` + `blocked_by` (wayfinder ↔ drain-loop are cousins; but waves drain shipped code, wayfinder drains decisions).
3. **The loop is the walker, and it's not a skill either.** No loop runtime. The frontier is walked by a human ("grab any ticket whose blockers are done, `/implement`, `/clear`, repeat") or by `claude-handoff`'s background `claude --bg`. `loop-me` produces workflow *specs* for a walker to follow.
4. **The one in-skill graph is headless fan-out for judgment**: `code-review` spawns parallel, non-reranked sub-agents — the same instinct as brana's `verify-findings.js`. Fan-out is used for verdicts, never for the main procedure.
5. His atoms don't solve the dual-mode gap either: `tdd`/`writing-for-agents`/`codebase-design` are reference-style and headless-safe; `grilling` interviews a human and cannot run inside a Workflow `agent()`. He never needs headless fan-out, so the question never arises for him.

Inference: Pocock's implicit answer to "atomic skills composed via graphs" is *keep skills small enough to be stations; put the graph in the tracker and the loop in the walker.* Brana converged on the same architecture independently (waves + `system/loops/` + Workflow scripts) — which argues *against* inventing a new atom schema — and it names brana's real structural difference: brana's daily-driver skills (`build`, `close`) *internalize* the graph (phase files = an internal state machine), which is why they are whole stations for a loop but cannot be nodes in a Workflow graph. Not a missing contract; a monolith by design (enforcement gates, which Pocock has none of).

## Pocock's ideal workflow vs brana's — stage by stage (S = skill, L = loop, G = graph)

### Main flow: idea → ship

| Stage | Pocock's ideal (`ask-matt`) | Brana's (`idea-to-ship.md` + wiring) | Where S/L/G differ |
|---|---|---|---|
| 1. Sharpen the idea | `/grill-with-docs` (S wrapper) → `/grilling` (S primitive): a **loop of rounds** over a frontier of unblocked questions, human-stop. Output `CONTEXT.md` + ADRs. | `/brana:brainstorm` (S monolith, 9 internal steps, own step registry). DISCUSS = **loop of challenge rounds**, human-stop. M+ fans out a hive-mind challenger (`_shared/adversarial-hive-mind.md`) — **G in code**. Output `docs/ideas/{slug}.md`. | Same L shape. Pocock: two thin skills over one primitive; brana: one monolith. Brana already inserts a code-graph inside the sharpening stage; Pocock never fans out here. |
| 2. Runnable question? | `/handoff` (S) → new session → `/prototype` (S) → `/handoff` back. Edge between sessions = a markdown file carried by a human. | `/brana:build` `spike` strategy inside the monolith; ANSWER creates a linked feature task. Edge = a task packet. | One edge out and back in both; Pocock's is doc+human, brana's is data. |
| 3. Multi-session? | `/to-spec` → `/to-tickets` emits tickets **with blocking edges — his GRAPH, as tracker data**. Then `/implement` per ticket, `/clear` between — **his LOOP: a human (or `claude --bg`) grabs any unblocked ticket, runs it, clears, repeats.** No runtime; the person is the conveyor. | `/brana:backlog plan` emits tasks with `blocked_by` **and** waves with `gate:` (ADR-080) — **G as data, two layers**. A **runtime loop** walks it: `/loop` + `system/loops/epic-drain` (topo-sort, arm as gates ship, `wave pull`, `/brana:backlog start` → `/brana:build` in a worktree, wait at merge valve). `BRANA_RUNNER=1` denied verbs; autonomy ladder L0–L3. | **Biggest divergence.** Same graph (claim-before-work frontier over blocking edges), but Pocock has *no loop primitive* — the loop is a human habit. Brana turned it into a committed, gated runtime with valves. |
| 3b. Build one unit | `/implement` (S, 12-line wrapper): `/tdd` (S primitive, **micro-loop** red-green) → `/code-review` (S primitive, **fan-out G**, Standards vs Spec) → commit. | `/brana:build` (S monolith: LOAD→CLASSIFY→SPECIFY→DECOMPOSE→BUILD→gates→learning→CLOSE; phase files, checkpoints, `build_step`). BUILD = TDD **micro-loop**; gates spawn challenger + evaluator (**fan-out G**, judgment only); challenge is Workflow-shaped (`verify-findings.js`, `sweep.js`). CLOSE merges to `dev`. | Same L and same use of G (fan-out only for verdicts). Pocock's build = *thin wrapper over stations*; brana's build *is* the station graph, internalized — deliberately, since spec-gate/checkpoints/evaluator/docs-before-close live there. |
| Ship | Commit per ticket; nothing beyond. | CLOSE → `dev` → human-gated `/brana:ship` (`dev`→`main` + bootstrap). | Brana adds an explicit ship valve. |

### On-ramps, upkeep, vocabulary

| | Pocock | Brana |
|---|---|---|
| Incoming raw issues | `/triage` (S): **5-role state machine** on labels — a tiny **G as tracker state**, human-walked; runs `/grilling`. | `/brana:backlog triage` (S); brana's state machine = `status` + `ac_state` (`none→proposed→approved`) — `approved` is what makes a task loop-drainable. |
| Something broken | `/diagnosing-bugs` (S primitive): build a **tight red-capable feedback loop first** (an L with an explicit stop), ranked hypotheses, fix + regression test; hands off to `/improve-codebase-architecture`. | `/brana:fix` (S); ADR-084 pilot (t-2834) vendors `diagnosing-bugs` inside `/brana:fix`'s shell — first instance of *his* primitive as *brana's* station. |
| Huge foggy effort | `/wayfinder` (S): **decision tickets** on the tracker (**G as data**), resolved one at a time (**L**, human-walked) until fog clears, then hands off to `/to-spec` — never builds. | brainstorm-deep → `/brana:challenge` ×2 → plan with lifecycle tasks → waves/drain. Waves drain shipped code, not decisions. |
| Upkeep | `/improve-codebase-architecture` (S) → ideas → **feedback edge back to step 1**. | `/brana:reconcile`, `/brana:verify-docs` (S today; t-2278 audit says both want to be a standalone **L**). |
| Vocabulary underneath | `/domain-modeling`, `/codebase-design` — model-invoked references. | `/brana:domain-driven-design` + `docs/domain/MODEL-001`. |
| Between phases | **Five human choices** at every boundary: continue / `/clear` / `/handoff` / subagent / `/compact` — the edges of his graph are context-management decisions a person makes. | Worktree per task + task packet (AC+context) + `close --continue` + context-budget thresholds. Same purpose, more mechanized. |

### Where each primitive lives

| | Pocock | Brana |
|---|---|---|
| **Skills** | ~35, two tiers: thin user-invoked wrappers (5–15 lines, linear prose graphs) + model-invoked single-job primitives. No skill holds a multi-phase state machine. | ~40, mostly monoliths with internal state machines (`build`, `close`, `backlog`, `brainstorm`) + an *untyped* primitive layer already live: `system/skills/_shared/*.md` + `system/agents/`. |
| **Loops** | Zero runtime. Loops are prose inside skills (grilling rounds, tdd, diagnosing-bugs feedback loop) or **the human** walking the ticket frontier. | Native `/loop` + `ScheduleWakeup`; committed `system/loops/` catalog (drain-loop, epic-drain, pipeline-digest) with autonomy level, denied verbs, beat records; plus in-skill loops (BUILD TDD, brainstorm rounds). |
| **Graphs** | Two homes: **tracker data** (blocking edges, wayfinder map, triage labels) and **prose routing** (`ask-matt`). One in-skill fan-out (`code-review`). No graph runtime. | Three homes: **data** (`blocked_by`, waves + `gate`), **code** (`Workflow` scripts, `pipeline()`/`parallel()`), and **inside monolith skills** (phase files). Plus hooks as deterministic edges. |
| **Human gates** | Everywhere, implicit: every phase boundary, every ticket grab. | Explicit valves: AC approve, wave ship, merge, ship. Supervised runner; unattended hard-gated on ADR-062. |

**Plainly:** on loops and graphs brana is *ahead* of Pocock's ideal (he has no loop runtime and no code graphs; his conveyor is a person). Where his ideal is *cleaner* is one place: **skill granularity** — his build stage is a thin wrapper over stations (`implement` → `tdd` → `code-review`); brana's build *is* the station graph, folded inside one skill. That fold carries brana's enforcement — and is also exactly why `/brana:build` can be a whole station for a loop yet not a node in a `Workflow` graph. The question t-2490 is really circling: **should brana's monolith skills become `implement`-shaped (thin wrapper over stations that already exist as phase files), keeping the gates but making the stations separately callable?** — word for word, t-2278's parked north-star.

## Opinion, criteria, recommendation per stage (Claude, 2026-08-18 — operator asked; not yet accepted)

**Criteria (a unit earns extraction only if it clears one):** (1) **Enforcement** — holds a gate someone could skip → keep inside the monolith; (2) **Reuse pressure** — ≥2 callers → primitive; (3) **Headless viability** — must run in a Workflow `agent()` or unattended runner → needs an AskUserQuestion-free path; (4) **Judgment locus** — human judgment → human-stop loop; verdict → fan-out judges; mechanical → code; (5) **Cost per hop** — every extraction is a context re-entry.

| Stage | Opinion | Deciding criteria | Recommendation |
|---|---|---|---|
| 1. Sharpen | Brainstorm monolith is fine (human-stop rounds are the design). Interview mechanic reused by brainstorm/decide/triage/challenge → real reuse pressure; `grilling` already on ADR-084 DEPEND list. | 4, 2 | Keep brainstorm as wrapper; adopt `grilling` primitive via ADR-084. Don't split brainstorm's 9 steps; hive-mind challenge is already the one right extraction. |
| 2. Runnable question | Brana's task-packet edge > Pocock's markdown handoff; his artifact discipline (prototype kept as primary source on `prototype/<name>`, linked from the task) is better. | 5 | Keep spike; borrow the branch/link convention into `strategies.md` ANSWER. Low priority. |
| 3. Multi-session | Brana ahead — never regress to human-as-conveyor. Pocock's one lesson: `/clear` per ticket. epic-drain builds inline in the loop session (context accumulates); ADR-060 already says runner spawns `claude -p` per worktree. | 3, 5 | State fresh-context-per-pull as epic-drain step-4 default when unattended lands. Wayfinder decision-tickets: no adoption (`kind:design` under an epic covers it). |
| 3b. Build one unit — crux | Keep `build` as supervised wrapper (CLASSIFY/SPECIFY/DECOMPOSE = judgment; gates = enforcement). Two stations clear 2+3: the **TDD loop** (build+fix; must run headless) and **verify-gates' judgment fan-out** (Workflow-shaped; called from build/close/challenge) — Pocock's `tdd` and `code-review`; `tdd` is DEPEND-listed. | 1 keeps wrapper; 2+3 extract two | No 9-station rewrite. Bounded second pilot after t-2834: vendor `tdd` per ADR-084, `build-loop.md` calls it — same seam t-2834 proves. Two-axis review = t-2835 (parked). |
| Ship | Explicit valve is right. | 1 | Nothing. |
| Triage | `ac_state` is the machine that matters (drainability). | — | Nothing. |
| Fix / diagnosing-bugs | **t-2834 is the evidence beat.** Read the atom contract off its adapter (inputs mapped, output homes, denied verbs), don't design it abstractly. | 2, 3 | Proceed t-2834 first; its adapter = reference implementation of "brana's atom contract." |
| Huge foggy effort | brainstorm-deep → challenge ×2 → plan → waves covers wayfinder; different output. | — | Nothing. |
| Upkeep | reconcile/verify-docs want to be a loop; t-2278's blocker (v3 schema) has landed. | 3 | Unblock t-2278 as the focused L it already is; no scope change. |
| Vocabulary | Agree with P8 reject. | — | Nothing now. |
| Phase boundaries | Pocock's five-option tree is crisper than brana's scattered guidance. | 5 | Fold the ordered tree into `context-budget.md`. Docs-only, S. |

**Primitive-level calls:**
- **Atom contract (skills):** no new schema. Atom = a model-invoked skill (or `_shared/` block) with one job, no AskUserQuestion on its main path, schema'd return when called from a Workflow node. Mechanism = t-2832 `disable-model-invocation` taxonomy + ADR-084 DEPEND wrappers. **Granularity floor: a phase file becomes a station only when it has ≥2 callers or must run headless.** By that floor `build` yields ~2 stations, not 9.
- **Loops:** keep all; adopt only fresh-context-per-pull.
- **Graphs:** keep the three homes; prose routing (`idea-to-ship.md`, `delegation-routing.md`) stays prose — Pocock validates a router doc need not be code.
- **Dual-mode gap:** don't build a dual-mode unit. Headless nodes = agents/Workflow prompts; supervised stations = skills. Where one station must run both ways, the fix is at the **runner layer** (`claude -p` running the skill with questions answered by policy — ADR-062), not the skill-schema layer. The gap dissolves rather than needing an abstraction.

**Net verdict recommendation:** leave t-2278 as planned; adopt no new atom schema; atom contract = Pocock two-tier via ADR-084/t-2832 + the ≥2-callers-or-headless floor; dual-mode gap resolves at the runner layer. Follow-ups (all small): t-2834 evidence beat → `tdd`-into-build second pilot → epic-drain fresh-context note → phase-boundary tree in context-budget.md → unblock t-2278. Load-bearing enough for a **short ADR** recording Non-Actions (9-station rewrite, typed atom schema, dual-mode abstraction).

## Open (not yet converged — operator still debating, 2026-08-18)

- Is the dual-mode (supervised + headless) gap causing pain *today*, or theoretical? No duplicated-logic evidence gathered yet.
- Does adopting Pocock's two-tier for *adapted/new* skills (already entering via ADR-084 + t-2832's `disable-model-invocation` taxonomy) settle the "atom contract" AC without touching monoliths?
- Verdict on t-2278 scope: leave as planned / narrow to typed `_shared/` / reopen north-star — undecided.

## Risks

- Over-decomposition: atoms too small = graph plumbing costlier than the monolith, every hop a context re-entry. Granularity floor must be stated (t-2490 AC).
- Churn on daily drivers: `build`/`close` work; t-2278's audit de-risked by leaving 22 skills untouched. Reopening needs evidence, not vocabulary (skills-as-loops.md load-bearing lesson: test hypotheses against a behavior's *shape*).
