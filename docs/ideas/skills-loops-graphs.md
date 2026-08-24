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

## Studio session 2026-08-18 — decision, collision, evidence, reconciled verdict (thebrana-50 synthesis)

> Second session on t-2490, opened by the operator to merge this doc with session 64be2e25 (ADR-084 Pocock vendoring). Sources: this doc (f7c57a08); four reader digests over 11 prior docs (skills-as-loops, loop-first-redesign, loops-library spec, build-loop-redesign spec, agent-definition-gaps, runner-capability-isolation, loop-task-multiagent, goal-integration-three-primitive, dynamic-skill-routing, agent-interaction-architecture, wave-pipeline); direct exchange with both peer sessions; a duplicated-logic evidence test. Nothing above this heading was rewritten.

### Framing the operator brought

"My loops drain the backlog and the loop steps invoke skills — Pocock's skills invoke loops and graphs. Inverse." Resolution: **duals, not opposites — recursive.** brana already has both: `epic-drain` → `/brana:build` (loop ⊃ skill) and `/brana:challenge --deep` → `verify-findings.js` (skill ⊃ graph). Pocock's `to-tickets` emits a DAG that his Ralph loop walks = `/brana:backlog plan` + epic-drain rebuilt from the other end. So the atom is neither skill nor loop: it is the **station**, and skills/loops/graphs are three *arrangements* of stations. Pocock's contribution is the reading of *skill = playbook a station loads* (context), not procedure.

### Operator decision (2026-08-18)

**Human mode (`inside | valve | none`) is set by the CALLER, never the station. A station may only SUGGEST a default per named ask; the caller's grants policy decides.** Bounds attached by the reader findings and peer review:
- grants are **default-deny** (loop-first challenger, inbox-secrets finding);
- a suggested default is a **closed enum fixed by the station author**, never text flowing from task fields (runner-capability-isolation: lethal-trifecta leg 2); the vendored/upstream skill's own "if AFK, proceed" prose is *evidence* for the default, not the enum (thebrana-84);
- **presence interlock** (ADR-061 Inv.1): a headless caller cannot honor a default that crosses a gate; irreversible ops (approve / merge / ship) have no default — reversibility routes judgment (wave-pipeline);
- ambiguous asks carry no default → studio agenda (wave-pipeline: "when unsure, agenda").
- Pocock's practice matches this *undeclared*: `implement`/`tdd` run supervised in-session and headless under Ralph with zero skill change; `diagnosing-bugs` Phase 3 has a station-suggested non-gating default ("show ranked list… don't block, proceed if AFK"); wizard `confirm` before irreversible actions never proceeds (thebrana-84). `disable-model-invocation` is the *who may start it* axis — orthogonal to who owns human mode *during* execution; keep separate (t-2830 §3).

### The station-manifest sketch — drafted, then deferred (Non-Action evidence)

Sketched in-session for `build-loop`: `input:/output:` JSON schema, `context:` (files/rules/recall), `skills:` as playbooks, `tools:` allow/never, `judge:`, `model:`, `asks:` {question, suggested_default, room}, with an `ask()` that compiles per caller mode (inside → `AskUserQuestion`; valve → return `needs_judgment` + escalation; none → default only if granted). Kept here as evidence for Non-Actions #2/#3, not as pending design, because the readers showed:
- **Not a fifth primitive.** wave-pipeline (ADR-079) closes the vocabulary at queue/pump/valve/gauge — a station is the *body of a pump*; `asks:` are valves; `judge:` splits into gauge (readout) + valve (decision) by reversibility. Coordinate already named: **skeleton-step × band**.
- **Fields already have owners.** `skills:/tools:/model:/isolation:/maxTurns:/memory:/permissionMode:` = native CC agent frontmatter (agent-definition-gaps; native `skills:` is *unconditional preload*, the opposite of "may pick up"). `stop_condition:/verifier:/queue:` = skills-as-loops L169 (the sketch dropped two of the three). `model: {preflight, act, judge, records}` = loops-library (slot claimed, empty; `judge` must reference `resolve_judge_rung`, ADR-082). Typed I/O = **packet** (skills-as-loops). Two rooms incl. the routing default = wave-pipeline. `judge:` policy = **t-2894** (live) — a policy that arms on hard signals, never a name, never same-model.
- **Missing organs** the sketch had no slot for: ASSIMILATE (memory write-on-exit), RESTART (`{active|waiting|empty}`), **dead-letter output** (wave-pipeline law 2: "queueless rejects rot — the 160-day-stale root cause"). These are loops-library gaps (t-2826 out-of-scope) — cross-referenced, not absorbed here (thebrana-1b).
- **`tools: never` is a tripwire, not a boundary** (t-2173: sandbox = bwrap; denylists bypassable; advisory in CC-native).
- **Chains are the anti-pattern** (loop-task-multiagent: sequential handoffs 39–70% worse; only orchestrated fan-out + synthesis); `context:` must be able to express *deliberate starvation* (blind test-author from AC alone), not just loading.
- **Three docs independently forbid the big-bang schema**: skills-as-loops L55 ("earned by evidence… single loops one at a time → then compose"), goal-integration Stage 4 ("premature abstraction — generalized contract designed before evidence"), wave-pipeline ("loop first, redesign after — never big-bang, the t-1994 lesson").

### Evidence — the §Open L118 question is answered: the dual-mode pain is REAL today

Duplicated-logic test over the three pairs thebrana-1b scoped. Verdict: **drifted duplication in all three** — the copies already contradict each other on load-bearing rules.

| Pair | Duplicated | Diverged / contradicted | One-sided |
|---|---|---|---|
| **A** gates | `verify-gates.md:101-102` ↔ `system/agents/build-evaluator.md:55-67` (MET/PARTIAL/MISSED restated); `verify-gates.md:120-154` ↔ `_shared/challenger-gate.md:187-229` (repair loop near-verbatim) | `system/agents/CALIBRATION.md:25-28` "SPLIT… never counted as FALSE_POSITIVE" **vs** `verify-findings.js:27-28,110` "ties drop to FALSE_POSITIVE" (t-2887 already ruled splits are their own signal class → the JS is wrong); `verify-findings.js:111` emits `UNVERIFIED` absent from its own enum `:66`; voter default `:23` "2" vs `:29/:54` "3" | prose-only: `challenger.md:104-115` discipline check; headless-only: all-verifiers-failed degradation `verify-findings.js:108-127` |
| **B** hive-mind | `_shared/adversarial-hive-mind.md:9,30-32` ↔ `hive-mind.js:4-7,100` (3 lensed workers, skeptic framing) | lens sets share only "systems" (`md:11-15` vs `js:51-57`); ≥2-worker corroboration rule prose-only (`md:20-28`); md routes through verify-findings (`md:35-39`), js forbids it (`js:9-13`) | prose-only inline fallback; headless-only synthesize stage `js:106-126` |
| **C** TDD | `build-loop.md:102,133,139` ↔ `_shared/delegation-tdd-checklist.md:11-14` | delegated agents get a **materially weaker** contract: no red-commit/`tests_required` (`build-loop.md:101-112`), no TEST→IMPLEMENT hard gate (`:113-131`) | **no headless TDD prompt exists** in any workflow or loop — runners inherit it only by invoking the whole skill |

Fix direction the evidence points to: **not a typed schema** — *shared organs extracted once* (wave-pipeline's own refactor direction) as **files both paths Read**. `agent()` nodes can Read; only the Workflow JS itself cannot import (`verify-findings.js:82`). Pocock's "skill = context pack" lands as the minimum atom: an **organ file**, loaded by the prose skill and by the headless prompt alike.

### Reconciled verdict (both sessions, both peers)

- **t-2278 stays as planned.** No typed atom schema; the manifest sketch is Non-Action evidence.
- **Atom = organ file + station-admission checklist.** Checklist (queue · stop_condition · packet in/out · dead-letter · judge policy · rooms · assimilate · restart · denied verbs) is applied **only to bindings that become stations** — first at t-2834 — never as a gate on all ~40 skills (thebrana-1b: 8 questions × 40 skills is the cost-per-hop failure in a new dress). Per-ask `suggested_default + room` table only if t-2834's adapter shows named asks repeating across ≥2 bindings — the 2-3-bindings rule applied to our own manifest.
- **`build` yields 1 extraction + 1 wiring**, not "~2 stations": TDD loop (extraction, headless-viable); verify-gates fan-out (wiring — the block already exists as `verify-findings.js` / `_shared/adversarial-hive-mind.md`; the work is making build/close/challenge call *one* copy). State it that way or the ADR overclaims (thebrana-1b).
- **t-2834 = evidence beat, not started** (unparked 2026-08-17). ADR-084 §3 already specifies what the wrapper owns — inputs mapped (tracker→tasks.json, ticket→t-NNN, triage→status+ac_state), redirect table for cross-skill slash-refs, output homes, and denied verbs *not yet enumerated* (from his skills: never `gh issue create`, never write `.scratch/`, never modify the parent issue, never bump upstream — valve-only). Read the atom contract off it. Related gap surfaced: his frontier excludes blocked tickets; brana `wave_pull_decision` ignores `blocked_by` (thebrana-84).
- **Independent-agents goal** (operator: "run independent agents with just the right context, skills, tools") is real and stays gated: supervised `claude -p` runner today (ADR-060); `human: none` waits on t-2173 sandbox + ADR-062.
- **Concrete follow-ups the evidence demands** (file as tasks; none needs t-2490's ADR to land first): (1) resolve tie/SPLIT toward `CALIBRATION.md` in `verify-findings.js`; (2) `UNVERIFIED` into the enum + one voter default; (3) single-source the challenger/evaluator rubric between `verify-gates.md`, `challenger-gate.md`, `build-evaluator.md`; (4) reconcile hive-mind lens set + corroboration rule, one direction, and decide the verify-findings routing; (5) `delegation-tdd-checklist.md` inherits the red-commit gate or records why not.
- ADR-084's two challenger findings still open (tie-break rule; `skills-lock.json` dir hash + pinnedRef, t-2834 AC to cover `agents/` + `scripts/`) — thebrana-84 landing them on the t-2837 branch.

### Doc hygiene the operator raised (2026-08-18)

Too many overlapping idea docs on this one machine (loop-first-redesign, wave-pipeline, loops-library, skills-as-loops, goal-integration, loop-task-multiagent, this doc…) — same concepts owned in 3–4 places, two core docs never cite each other. Requested: **one index doc with clearly referenced component docs**, one owner per concept, superseded docs pointing at the index; and a **rename** — "wave pipeline" no longer names the whole (waves are one mechanism inside it). Tracked as a separate docs task, not folded into t-2490's ADR.

## Open (not yet converged — operator still debating, 2026-08-18)

- Is the dual-mode (supervised + headless) gap causing pain *today*, or theoretical? No duplicated-logic evidence gathered yet.
- Does adopting Pocock's two-tier for *adapted/new* skills (already entering via ADR-084 + t-2832's `disable-model-invocation` taxonomy) settle the "atom contract" AC without touching monoliths?
- Verdict on t-2278 scope: leave as planned / narrow to typed `_shared/` / reopen north-star — undecided.

## Risks

- Over-decomposition: atoms too small = graph plumbing costlier than the monolith, every hop a context re-entry. Granularity floor must be stated (t-2490 AC).
- Churn on daily drivers: `build`/`close` work; t-2278's audit de-risked by leaving 22 skills untouched. Reopening needs evidence, not vocabulary (skills-as-loops.md load-bearing lesson: test hypotheses against a behavior's *shape*).
