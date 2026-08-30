# The Brana

**Status:** draft (cover locked; §Space/§Cycle/§Gate/§Components landed from [the-brana-guide.md](../ideas/the-brana-guide.md) L0–L5; open items ride inside their chapters) · **Owner:** Martín Rios
**Type:** Index — the front door to the whole system. Companion to [Idea → Ship: The Skill Flow](idea-to-ship.md) (how work flows through it); the two mutually point at each other. Supersedes [the-orbit.md](the-orbit.md) (retired vocabulary — see [ADR-068](decisions/ADR-068-v3-supersession.md)).

## Cover

> The Brana is how brana turns intent into shipped work. It lives in a bulk — the shared portfolio, the laws everything obeys — where self-contained branes sit at every scale: a project, a station, a grain, each with its own fields, confined to itself. Nothing crosses between them except memory, carried by loops that return; a workflow runs once and stays pinned to the brane it started in. Gates sit where that motion turns irreversible. And the human lives inside it, an inhabitant not an operator — working one brane's fields up close, sensing the rest only through what memory brings across.

Brane physics is the one lens here — no braña/brána wordplay, no competing metaphor on this page. **Brane** is not a single term: it is a Kaluza-Klein tower, one family instantiated at every scale — a *project* (epic ring), a *station* (beat ring), a *grain* (micro ring) — each a differently-scaled harmonic of the same shape. The **bulk** is the ambient container the tower sits in (the portfolio, the `~/.claude/` identity layer, the laws every brane obeys) — it is not itself a brane. The one thing that crosses between branes is memory, carried by **loops** — closed strings, unpinned, free to leave the brane they started on; a **workflow** is an open string, its endpoints stuck to the brane it started in, and it runs once. **Gates** are where that motion becomes irreversible and a human decision is required.

The rest of the physics vocabulary — open/closed strings in detail, the KK frequency tower, Randall-Sundrum warped scales, compactification — earns its place in the chapter pictures below (Scale, Space, Cycle), not on this cover. (Non-cover corroborating analogy: a trading chart's timeframe zoom — 1s/1m/1h/1D — is the same continuous data windowed at an arbitrary size on one dimension; same tower, same "small dimension = fast.")

## Three chapters, one axis

- **Space** — what things are: the bulk and the branes in it.
- **Cycle** — what it does: loops carrying work through queues, returning.
- **Gate** — who decides: human decisions and where they're placed.
- **Scale** — the axis across all three: the same skeleton at every ring, warped.

Each chapter below is the index of its decisions — one line per decided point, with refs; the component docs own the detail. Open items ride inside their chapter and are tracked in [the-brana-guide.md](../ideas/the-brana-guide.md). The vocabulary table below is this page's canonical copy — [glossary.md](glossary.md) points here rather than duplicating it (see L0's one-owner-per-concept rule).

## Space — the primitive table

Closes [ADR-068](decisions/ADR-068-v3-supersession.md)'s open Q2: this is the extraction of [substrate-primitives.md](substrate-primitives.md) §1's still-accurate primitive set into a live doc, not a re-derivation. [agentic-primitives.md](agentic-primitives.md) and [workflow-primitive.md](workflow-primitive.md) remain the detailed references this table points to, not duplicates of it.

```
                        GRAPH
        the shape: nodes = agents/skills/stations,
             edges = hand-offs / routing
                          │
          ┌───────────────┴────────────────┐
          ▼                                  ▼
   AS CODE (Workflow)                AS DATA (tasks.json)
   runs to completion,               walked incrementally,
   in one call                       over days, by /loop
          │                                  │
   agent()      = node               blocked_by / gate:  = edges
   pipeline()   = edges, no barrier  epic-drain topo-sorts + walks
   parallel()   = edges, barrier       one wave at a time,
                                       human valves between nodes
```

A **loop is a graph whose path returns to an earlier node** — which is the same fact as "Loop = closed string, returns" stated in a different vocabulary, not a second fact. `Workflow` *is* a graph that runs to completion in one call; `/loop` *traverses* a graph over time.

**Precision, not just cycles:** the code/data split isn't "has repetition vs. doesn't." A `Workflow` script's `pipeline()`/`parallel()` composition is always a DAG (no back-edges in the declared structure) — its `while`-loop accumulation patterns (loop-until-count, loop-until-dry) are bounded JS repetition *inside one continuous execution*, not a graph cycle, and not what this vocabulary calls "Loop." "Loop" names specifically the **data-realized** case: a graph with a genuine back-edge (a blocked task re-entering the frontier, a wave gate reopening) that persists and gets re-walked across separate invocations, days apart. `/goal` sits outside the Graph family entirely, not a smaller instance of it — it repeats *within one span*, one node, no hand-off between agents/skills to route. Loop ⊂ Graph (a topology, realized as data); Workflow ⊂ Graph (any DAG, realized as code); `/goal` isn't a routing structure at all.

| Primitive | What it is | Home chapter |
|---|---|---|
| **Task** (Agent tool) | One subagent, in-session, dies with session — the node graphs are built from, not a graph itself. | Cycle — one ACT |
| **Workflow** | Deterministic JS fan-out; a DAG, as code, run once (bounded internal repetition allowed, no structural cycle). | Cycle — open string |
| **/loop** + `claude -p` | Detached iteration over a queue; a graph, as data, genuinely cyclic, walked over time across sessions. | Cycle — closed string |
| **/goal** | Iterates within one gate-free span until a done-signal — one node, no routing (ADR-061's third motion — ITERATE, distinct from `/loop`'s POLL and `Workflow`'s FAN-OUT). Outside the Graph family. | Cycle |
| **ruflo memory / recall** | Persistent, cross-session shared store. | Cycle — what a loop carries (gravity-leak) |
| **Skills** | Playbooks a station loads. | Space — sits above this stack, not in it |

Composed blocks (Layer 1, `.claude/workflows/`) — each a `Workflow` script combining Layer-0 primitives: **hive-mind** (diverse answers → verify → synthesize), **sweep** (diverse finders → dedup → verify), **verify-findings** (the canonical judge panel, called by both). Invoked by Layer-2 skills (`/brana:challenge --deep`, `/code-review ultra`, brainstorm evaluate) — an agent deciding on its own a task "would benefit" does not count as invocation.

**Open:** where hooks (PreToolUse, SessionStart, …) belong isn't resolved — not in `substrate-primitives.md`'s set at all, and it doesn't cleanly fit Cycle's motion-primitives. Reads more like Gate (an automatic, non-human check) or connective tissue spanning all four chapters. Tracked at [the-brana-guide.md](../ideas/the-brana-guide.md) L2.1.

### Grain files — where they live

Closes [the-brana-guide.md](../ideas/the-brana-guide.md) L2.3. No new top-level directory — three homes, split by *who owns the grain*, not by file type:

| Home | For | Status |
|---|---|---|
| `system/skills/_shared/` | Logic multiple stations (skills/workflows) call | Already the de facto home — no change |
| `system/agents/<agent>/` | One agent's own owned judgment (a rubric, a calibration table) | New — `system/agents/` is flat `.md` today |
| `.agents/skills/<pocock-name>/` | Vendored upstream organs, pinned + tracked in `skills-lock.json` (never restated into the other two homes) | Mechanism from [ADR-084](decisions/ADR-084-upstream-skill-band-vendored-pocock-skills.md), pilot-accepted |

Rule: whichever home, the prose skill and the headless caller both **Read the same file** — no restating. The three drifted pairs found during this walk (verify-gates/build-evaluator/challenger-gate; adversarial-hive-mind/hive-mind.js; build-loop/delegation-tdd-checklist) already prove judgment silently diverges between a human-run skill and an unattended loop reading a stale second copy — one home per rule closes that class of bug.

### The handoff packet — what actually carries context between stations

Closes [the-brana-guide.md](../ideas/the-brana-guide.md) L2.4. [backlog-v3-schema.md](features/backlog-v3-schema.md)'s original packet design (spec + AC + log + refs, all typed) turned out mostly aspirational — checked against the live store, only **AC** (`acceptance_criteria`/`ac_state`) is real and load-bearing. `spec`, `log`, and `ref:` were designed but essentially unbuilt or unused.

| Piece | Status | Resolution |
|---|---|---|
| **AC** | Real — propose→approve→pull works end to end | Unchanged, the real contract |
| **spec** (provenance) | Designed, never populated | Adopt going-forward only, no backfill (t-3007) |
| **log** (attributed thread) | Never built; write-contention risk flagged in the original design | Not the tasks.json field — extend `/brana:log` (already append-only, tag-routed) with task-scoped read/write instead (t-3008) |
| **refs** | Designed, barely used | Broaden past specs/ADRs; require a context-pointer's what+when, not a bare link (t-3009) |

The `log` resolution is closer to Pocock's own model than the original design was: he has no per-task structured log either — decisions are their own markdown documents, referenced by a task, not schema fields embedded in it.

## Cycle — what it does

Closes [the-brana-guide.md](../ideas/the-brana-guide.md) L3. Work moves through queues by pumps and returns. Loop = closed string (returns; the only thing that crosses branes). Workflow = open string (runs once, pinned). Graph-as-data (waves + `gate:`, tasks + `blocked_by`) walked over days by a loop; graph-as-code (`Workflow` scripts) runs to completion in one call. Rings micro → beat → epic → knowledge. Every bullet below was scored against Pocock's cited practice before locking — verdicts and per-row rationale live in [2026-08-22-pocock-alignment-decision-matrix.md](../research/2026-08-22-pocock-alignment-decision-matrix.md); only rows #3 (JUDGE panel) and #4 (PLAN panel) remain genuinely undecided.

### The two-bucket lens (how v3 machinery is judged)

Standing direction: adapt toward Pocock's lighter structure, not the reverse default — but **don't judge a mechanism by raw field-usage counts** (low usage conflates "nobody wants this" with "nothing was ever built to feed it"; confirmed for `spec`/`log` — 0% usage, zero producer code, not zero demand). Judge each piece by the capability it unlocks, then weigh that against Pocock's equivalent. v3's machinery splits into two buckets, weighed separately:

- **Bucket 1 — unattended-loop safety** (`ac_state`/approval, dead-letter, leases, judge sizing): what Pocock's model doesn't need because nothing there runs unattended at volume. This is where "opt-in overlay, not universal schema" belongs — ~92% of tasks stay Pocock-lite (title/description/status/tags) and a task *earns* the heavy machinery only when a loop will touch it unattended. Test: capability-unlocked vs cost.
- **Bucket 2 — planning ergonomics** (epic hierarchy, `blocked_by`, waves-as-selectors, tags, effort roll-up for quoting): the operator's own planning/organizing/client-billing infrastructure, which Pocock's tool was never scoped to solve. Stays out of the "simplify toward Pocock" pressure. Test: planning value on its own terms.

`[the-brana-guide.md L3 standing direction · memory feedback_backlog-field-usage-vs-feed-mechanism · matrix]`

### Mechanics — four primitives, seven laws

Absorbed from `drained/wave-pipeline.md` (D3, 2026-08-23); this page is now the owner. The vocabulary for the machinery is **closed**: every capability — standing waves, shadow drains, dead-letter triage, graduated autonomy, the epic runner — is an *arrangement* of these four. The day an idea needs a fifth primitive is the day to be suspicious of it.

| Primitive | Definition | Instances |
|---|---|---|
| **Queue** | Durable state holding work between pumps — the loop's only memory | waves, `inbox/`, branches (`ready/*`), URL jsonl, ADR-063's hands store |
| **Pump** | A loop moving work exactly one stage forward; a *station* is the body of a pump | `wave pull`, drain loop, epic-drain, cleanup |
| **Valve** | A human gate between stages — never automated, never armed by the party it constrains | `ac approve`, merge→dev, ship→main, `wave … shipped` (full inventory: §Gate L4.4) |
| **Human mode** | The caller-set compile target for a station's asks: `inside` (AskUserQuestion) · `valve` (raise a hand, stop the beat) · `none` (granted default). "Presence" in §Gate's interlock bullet is the same axis. Set by the caller, never the station. | this page §Gate (L4.2) |
| **Gauge** | A readout on a queue or the pumps — never acts, makes the next decision cheap | wave board, watchdog, beat telemetry |

Every queue answers five verbs — `peek / pull / ack / dead-letter / depth` — with its store's native atomic primitive doing `pull` (lock+write for waves, `mv` for dirs, `update-ref` for git). Native stores stay authoritative; the abstraction lives only at the verb interface ([features/loops-library.md](features/loops-library.md) has the contract).

```
backlog ──▶ ac-propose ──▶ ac approve ──▶ wave drain ──▶ wave pull ──▶ build ──▶ merge · ship
 QUEUE        PUMP          VALVE·you      VALVE·you       PUMP         PUMP       VALVE·you
```

Ascent happens on the way back: green tests close a beat, beats close a wave, shipped waves close an epic, the epic's learnings close the knowledge loop. **Ascent is phase, not a return trip:** nothing travels back up the rings; the slow wave advances *because* the fast one oscillated — a wave is not closed by a separate closing activity, it closes as a side effect of its beats completing.

**The seven operating laws** (brana's own derivation, no Pocock analogue; memory `project_loop-operating-laws`):

1. **Loops never talk to each other — queues do.** Coordination is backpressure; the foreman fills a queue, it never calls workers.
   *Corollary (2026-08-23, guide L7 #8) — sessions are loops too:* a message between sessions or agents (CC `SendMessage`, Agent Teams mailboxes) may carry a **pointer or a gauge reading — never state, never a lock, never an approval**. Ownership of a worktree or task is a lease in `tasks.json` (law 4), *announced* by message, never *negotiated* by it. Messaging is ephemeral by construction (dropped on exit) — a queue nobody can watch (law 3) is not a queue.
2. **Every loop needs a dead-letter path** with its own closer pump — queueless rejects rot (the 160-day-stale root cause; t-2587).
3. **One external watchdog watches all loops** via last-beat records, outside the loops it guards. Session death is loop death; only the watchdog notices.
4. **Beats are idempotent.** A beat replayed twice must be safe (the atomic wave pull is the reference implementation).
5. **Cost per beat ≈ context size.** Lean dedicated sessions, cheap preflight first; a loop whose beats cost more than the work they move is net negative. (Applied to sessions: sessions are disposable read/write heads over durable state, never where state lives — see §Space L2.5.)
6. **Loops are testable.** Rehearse beats against fixture queues before arming (shadow drains are the wave-native form).
7. **Lifecycle needs a stance** — 7-day expiry, Esc-kill, no pause/resume: retirement and re-arming, not just birth.

**Knowledge band, instrumented (design, not yet built):** cross-session learning is a pipeline, not a feature — capture (every beat, free) → `knowledge-staging` queue (cap = WIP bound) → distiller pump (t-2851) → curation valve as a cockpit digest (t-2852) → reservoir, with hygiene gauges for staleness and a retirement path, law 7 applied to knowledge (t-2853). This is what fills the Knowledge ring's missing MEASURE/JUDGE (§Scale). Close then decomposes into *distributed* ASSIMILATE — every beat writes its record at exit; `/close` thins to a session-band valve.

### Decided

- **Workflow-vs-loop rule:** runs once → `Workflow` script; walked with humans between nodes → data + `/loop`. No Pocock analogue for either half — his system has no loop primitive ("the loop is a human habit") and no graph-as-code. `[skills-loops-graphs.md §Loop vs graph · memory pattern_loop-traverses-graph-workflow-is-graph · matrix row 1]`
- **Loop contract** = [features/loops-library.md](features/loops-library.md) + `system/loops/` (frontmatter, beat record, denied verbs, pull interface). KEEP brana (row 1): denied verbs / pull interface are unattended-safety scaffolding real production crons need. `[features/loops-library.md · system/loops/{README,drain-loop,epic-drain,pipeline-digest}.md · system/scripts/loops-lint.py · matrix rows 1, 8]`
- **Wave mechanics** — split by verdict, not one bloc: `ac_state` approval KEEP (row 5 — routes *and* gates, unlike Pocock's readiness state; 0.8% usage reads as early load-bearing infra under the corrected lens) · leases KEEP (row 6 — hard dependency the moment wave-level parallelism lands, to avoid re-running t-2216/t-2206) · gate graph / `blocked_by` in the pull frontier **ADOPT Pocock** (row 10, largest margin in the matrix — his `to-tickets` frontier rule open ∧ unblocked ∧ unclaimed fixes a confirmed live bug; amend [ADR-079](decisions/ADR-079-backlog-drain-loop-handoff.md) §2). Epic-drain supersedes drain-loop for epics. `[ADR-079 §2 · ADR-080 · ADR-065 · features/plan-time-wave-graph.md, wave-board.md, wave-gate-enforcement.md, ac-state-forward-slice.md · guide/workflows/epic-drain.md, drain-loop.md · features/backlog-v3-schema.md · memory pattern_wave-pull-ignores-blocked-by-ordering · matrix rows 5, 6, 10]`
- **Wave-level parallelism** (independent unblocked tickets → concurrent agents) — ADOPT Pocock (row 2). Not yet built; leases are a prerequisite, ship together. `[ideas/loop-task-multiagent.md Round 1 · t-2889 · matrix row 2]`
- **Seven laws** — brana's own derivation, no Pocock analogue, no matrix row. `[this page §Cycle → Mechanics · memory project_loop-operating-laws]`
- **Four mechanics primitives** queue / pump / valve / gauge (+ backpressure, dead-letter), closed set. Dead-letter KEEP (row 7): Pocock's `wontfix` is human-only classification; t-2587 (LinkedIn-miss starvation) is exactly what automatic dead-letter prevents. `[this page §Cycle → Mechanics · drained/loop-first-redesign.md L188–203 · memory pattern_pipeline-primitives-* · t-2587 · matrix row 7]`
- **Task = agent's unit; wave = human's unit** — KEEP brana by override (row 11): raw score slightly favors Pocock's unified ticket, but billing a client for a defined chunk of work is a must-have filter none of the six criteria capture (Bucket 2). `[WT t-2980 ADR (→086) · memory project_pocock-adoption-ideas-2026-08-18 · matrix row 11]`
- **Chains are an anti-pattern** (39–70% worse than single-agent; context loss per hop). Fan-out + synthesis only at JUDGE (leans KEEP, row 3 — 4 verified misses across 6 diffs, 2.5–3.5× cost, escalation-gated) — PLAN-step panels **not settled** (row 4; needs the same retrospective probe before t-2896). `[ideas/loop-task-multiagent.md · research/2026-08-14-multiagent-orchestration-lessons.md · memory pattern_multiagent-belongs-at-judgment-not-execution · matrix rows 3, 4]`
- **Ring table** (L3.1, locked after `/brana:challenge` deep) — per ring: queue · act · cycle unit · record · gauge · valve · memory read/write, with ✓ proven / ◇ design-only / ⚠ contested markers. Beat is the only fully-exercised ring; Epic's record and exit-write are design-only; the whole Knowledge row is design-only. Table lives in the guide, not restated here. `[the-brana-guide.md L3.1 · this page §Scale (layer test) · features/loops-library.md §beat record · ADR-080 §3, §7 · t-3018 · L3.7]`
- **`/goal` placement** (L3.2) — the Micro→Beat seam: owns the Micro ring's red→green cycle, stops at Beat's valve; lives *inside* Beat's Act cell, never across its valve. Bucket 1, KEEP — it is what lets a task auto-complete with nobody watching. `[ADR-061 §1, §2, §4 · features/goal-binding-build-tdd.md (stale → pointer, L6) · t-3018 · t-2981]`
- **Two runners, one seam: presence** (L3.4) — epic runner (`inside`/`valve`) and autonomous runner (`none`) walk the same beat; converge the autonomous runner onto `epic-drain` as its `presence: none` mode (t-3019, blocked_by t-2982). The satellite keeps the eligibility layer + headless executor. `[ADR-080 · features/autonomous-runner.md · drained/orbit-evidence-first.md · ADR-085 · t-3019 · t-2982]`
- **Beat record = markdown document** referenced by the task/beat, not a schema field (L3.5, row 8 — matches L2.4's `log` resolution, t-3008). A build receipt is one *instance* of that document type. `[features/loops-library.md · features/build-receipts.md · ADR-076 · matrix row 8]`
- **Fresh context per pull** is the default once unattended lands (L3.6, row 12, no tension). t-2982 proceeds as planned. `[t-2982 · guide/workflows/epic-drain.md step 4 · ADR-060 · matrix row 12]`

### Open, riding inside the chapter (not blocking)

- **L3.7 Epic-ring gauge** — a self-similar machine gauge per ring, Epic first; three rungs (observational → gate for reversible outcomes → earned auto-advance), promoted by clean runs; rung 1 only in scope, needs a retrospective probe against shipped waves; ships together with presence `none` (t-3019). No Pocock analogue. `[ADR-080 §7 · the-brana-guide.md L3.7]`
- **Cross-skill readiness state** ("what's next, and for whom") — ADOPT Pocock's single 5-role field (`needs-triage`→`needs-info`→`ready-for-agent`→`ready-for-human`→`wontfix`) decisively in principle (row 9, clearest win in the matrix); brana's `status`/`ac_state`/`build_step` trio can't hand off headless across time. **No owner yet** — intended home: [features/backlog-v3-schema.md](features/backlog-v3-schema.md) + an ADR amendment, resolved together with L2.2b once t-2834's evidence lands; don't design two fields for one problem. `[L2.2b · t-2834 · ADR-074 · system/skills/backlog/phases/triage-sync.md · matrix row 9]`
- t-3018 (refactor placement, inside L3.1) · PLAN-step panel probe (before t-2896).

## Gate — who decides

Closes [the-brana-guide.md](../ideas/the-brana-guide.md) L4; owns the two rooms and the valve-by-reversibility rule (absorbed 2026-08-23, D3); the spectrum/low-pass view is §Scale. Valves = human gates placed by reversibility: machine judges own reversible outcomes; the human valve is mandatory for irreversible ones (approve · merge · ship). Two rooms: **studio** (needs thinking → agenda) and **cockpit** (rubber-stamps → digest). Autonomy = altitude L0→L3; L3 hard-gated on the sandbox.

### Decided

- **Caller owns human mode**; station suggests a closed-enum default; grants default-deny; presence interlock; ambiguous → agenda; irreversible → no default. `[t-2490 context · skills-loops-graphs.md §Operator decision · ADR-061 Inv.1 · drained/loop-first-redesign.md challenger #1 · drained/runner-capability-isolation.md (lethal trifecta) · Pocock research (diagnosing-bugs Ph3 default; wizard confirm) · memory pattern_dual-mode-gap-resolves-at-runner-layer]`
- **Panels at JUDGE/PLAN only**; judge = policy arming on hard signals (t-2894); same-model self-review weakest; split verdicts are their own signal. `[ideas/loop-task-multiagent.md · research 2026-08-14-judge-panel-probe.md, 2026-08-14-llm-judge-panels.md · ADR-082 · features/judge-escalation-valve.md · system/agents/CALIBRATION.md · memory pattern_llm-judge-panel-design-rules]`
- **Autonomy = routing, not smarter agents**; promotion by evidence, auto-demotion by shape. `[drained/loop-first-redesign.md L200 · drained/brana-v3-redesign.md principles 5–6 · ADR-068 §3]`
- **Gate armed by an actor external to the loop.** `[this page §Cycle → Mechanics (valve) · memory pattern_gate-armed-by-the-party-it-constrains · guide/workflows/epic-drain.md (3)]`
- **L3 hard-gated on ADR-062**; `tools:` deny = tripwire. `[ADR-062 · t-2173 · drained/runner-capability-isolation.md]`
- **Two rooms as one store, two trays** (L4.1) — [ADR-063](decisions/ADR-063-pending-questions-store.md)'s `pending-questions.json` is the only queue; add `room ∈ cockpit | studio`, set by the valve-feeder at stop-time by a cheap rule (irreversible or ambiguous or unsure → studio; else cockpit), never an LLM classifier. Three verbs: `peek` (gauge) · `pull` (lease) · `ack` (the valve). KEEP two rooms, ADOPT Pocock's shape (state on the item, not a parallel queue). `brana hands` is Accepted, never built → t-3021, blocked_by t-2834. `[ADR-063 (amend §1 schema: room) · features/pipeline-digest.md · ideas/statusline-pipeline-awareness.md · t-2825 · t-3021 · t-2587]`
- **`ask()` compile table** (L4.2) — the station writes the question once; the caller compiles it: `inside` → `AskUserQuestion` · `valve` → raise a hand into ADR-063's store with `room`, stop the beat with `needs_judgment` · `none` → take `suggested_default` only if the grant covers it (closed enum, default-deny), logged as an assumption. **`none` degrades to `valve`, never to a guess.** Prose at the runner layer, single owner, no schema (ADR-085 D2) — owner to create: `system/loops/README.md` §ask (t-3021). Today `valve` is paper (`autonomous-runner.sh plan_task` up-front NEEDSHUMAN is the stopgap). `[ADR-062 · ADR-063 · ADR-085 D2 · guide/workflows/epic-drain.md (8) · system/scripts/autonomous-runner.sh · t-3021]`
- **Session messaging = gauge + doorbell, never a queue** (guide L7 #8, 2026-08-23) — CC cross-session messaging (`ListAgents`, `SendMessage`, idle notices) instruments the *session* band as a **gauge** (which session is on what, idle/busy/waiting — t-2825, pipeline-digest input; observational only) and serves as the **doorbell** for a raised hand: the question lives in ADR-063's store, the live cockpit session is *rung* via ADR-051's `--channels` (t-3021). The inhabitant may relay intent to peers ("what are you building / hold / go"); a peer message never counts as an approval — CC enforces this (permission-laundering rule) and it matches the valve law. **Agent Teams** (lead + teammates, shared team task list, interactive-only, not resumable) is an *open string* pinned to the lead's brane — a candidate in-room fan-out station for workers that need `inside` mode; its task list must map 1:1 to t-IDs or it becomes a shadow backlog (ADR-002/065) — evidence-first spike before use. Rule: §Cycle → Mechanics law 1 corollary. **PARK (t-3158, 2026-08-30):** the spike could not be executed — Agent Teams' interactive mode pauses a live session for human input, which a headless/background agent cannot exercise, and the operator's own session-state watch list independently flags t-3158 as "needs the operator, not agent-startable" (predates this spike attempt). All three questions (task-list binding to t-IDs vs shadow backlog, law-1-corollary message discipline, cost vs Workflow) stay open pending a real run. **Trigger to unpark:** the operator runs one live session with `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` (already set in `~/.claude/settings.json`), does one real fan-out where a teammate must ask the operator something mid-task, and reports back team-task-list shape, message contents, and wall-clock/token cost vs the equivalent Workflow run. Until that trigger fires, no station wrapper gets built on top of Agent Teams. `[the-brana-guide.md L7 #8 · ADR-063 · ADR-051 · ADR-059 · t-2825 · t-3021 · memory pattern_signed-off-peer-still-acts-assign-git-ownership · t-3158]`
- **Judge ladder** (L4.3) — shipped: [ADR-082](decisions/ADR-082-multi-agent-sizing-function.md) + [`_shared/judge-sizing.md`](../../system/skills/_shared/judge-sizing.md) (single live authority). Deterministic ladder on hard pipeline signals: rung 0 single fresh-context challenger → rung 1 + sibling-path finder → rung 2 full funnel. Signals only raise; no rung persists past its beat; Claude-only; triggered never standing. KEEP — the one mechanism here with measured evidence. `[ADR-082 · t-2894 · t-2895 · features/judge-escalation-valve.md · research 2026-08-14-judge-panel-probe.md · features/stacked-verdict-at-the-valve.md + ADR-081]`
- **Valve inventory + three-tier rule** (L4.4) — five human valves, strictness a function of the tier they write into, not of who asks:

  | valve | reversible | verb (today) | surfaced (today) |
  |---|---|---|---|
  | AC approve | yes | `backlog ac-approve` · `wave approve --confirm_ids ≤10` | nowhere |
  | Wave ship | mostly | `wave set status shipped` → `wave ship` (t-3022) | digest "contract likely met" |
  | Merge → dev | yes | `git merge --no-ff` by hand | digest unmerged list |
  | Ship → main | **no** (deploys `~/.claude/`) | `ff-only + bootstrap.sh + push` → PR + required CI (t-3023) | **nowhere** |
  | Re-arm runner | yes (Esc) | `/loop epic-drain` (launch = arm) | n/a |

  **Tiers:** tier 0 *workbench* = feature/worktree/runner branches, nothing live, fast · tier 1 *buffer* = `dev`, integrated not deployed, human merge valve, judge ladder arms by signal · tier 2 *production* = `main` → `~/.claude/`, human-only, recorded, never a runner, never a default. Every valve is already default-deny; all five are cockpit items and four are surfaced nowhere → `peek --room cockpit` (t-3021) is the single surfacing point. Ship→main was the one irreversible valve and the only one unsurfaced — that asymmetry is the defect. **GitHub is a mirror, not a gate today** (last PR merged 2026-03-16; no required checks). KEEP brana's five; ADOPT Pocock at **tier 2 only**: `dev→main` via PR + required CI + enforce_admins (t-3023), and greppable valve verbs (t-3022). NOT adopted: tickets→issues, PR per feature branch, a staging tier, machine defaults on any valve. `[ADR-079 · ADR-080 §3/§6 · ADR-060 · ADR-082 · CLAUDE.md §Integration model · guide/workflows/branching.md · system/hooks/spec-gate.sh · .github/workflows/ci.yml · memory G/pattern_challenge-wave-pipeline-valve-order-2026-08-14 (historical name) · t-3021 · t-3022 · t-3023 · research 2026-08-13-matt-pocock-skill-system.md]`

### Parked

- ⏸ **L4.5 Orbit satellite** — what, when, own component doc. `[features/autonomous-runner.md · ADR-068 · drained/orbit-evidence-first.md]`
- ⏸ **L4.6 Model/effort routing** — compute routing (which primitive) is decided in `delegation-routing.md`; which capability tier a primitive runs at is not, beyond JUDGE's `judge-sizing.md`. Operator brings more knowledge later; no forced rule. `[~/.claude/rules/delegation-routing.md · ruflo-stub-guard.md · judge-sizing.md · ADR-082]`

## Scale — the rings

The axis across the three chapters, absorbed from `drained/wave-pipeline.md` §four rings / §spectrum / §skeleton match (D3). Nested loops, each closing at its own timescale; zooming in changes timescale, never subject — one epic is a region of the knowledge plane, one beat a region of the epic plane, one task a region of the beat plane. The per-ring instrument table (queue · act · cycle unit · record · gauge · valve · memory, with proven/design-only markers) lives in [the-brana-guide.md](../ideas/the-brana-guide.md) L3.1 and is not restated here.

| Ring | Mechanism | Timescale | The human here |
|---|---|---|---|
| **Knowledge** | memory → recall → work → learnings → memory. No command — the harness itself | weeks | **Studio** — you bring the topic; we design side by side |
| **Epic** | plan emits wave graph → approve → drain → ship → next gate unlocks — waves + gates + valves ([ADR-080](decisions/ADR-080-plan-time-wave-graphs-epic-runner.md)) | days | Studio births the graph · **Cockpit** approves + ships |
| **Beat** | sleep → wake → preflight → pull → work → report — the `/loop` command | minutes | Cockpit — the merge valve; seconds per decision |
| **Micro** | red→green→refactor · challenger find→fix→re-verify, inside one task (`/goal`) | seconds | none — machines all the way down |

The deeper the ring, the less of you it needs. **Memory is the fourth dimension** — orthogonal to depth, touching every ring: each recalls on entry (LOAD, wave state, task context) and writes back on exit (learnings, ADRs, beat records). The spatial rings cycle and forget; memory accumulates — write-back is what turns each circle into a spiral. (Proven in the first live drain: beat 2 read its build map from the task's `context` field, not from the conversation.)

- **Rings are sample points, not an ontology.** They mark the frequencies where instruments happen to be installed; the spectrum underneath is continuous (KK tower: small dimension = fast). Bands already cycling uninstrumented: *session* (~hours), *season* (~months), *sub-second* (lint, type-check).
- **The layer test.** A proposed band is real iff you can name its queue, pump, valve placement, gauge, and memory read-on-entry / write-on-exit — and something has actually cycled in it with records emitted. Can't name the queue → not a layer. Installing the instruments on a chosen band *materializes* it: a new brane in the bulk, with its own fields, leaking learnings to the others only through memory.
- **The human is a low-pass filter.** Sustained coupling to the slow frequencies (studio), discrete sampling of the fast ones (cockpit valves), absent from the fastest. Tuning the system = sliding coupling toward lower frequencies as evidence accumulates — the graduated-autonomy ladder (§Gate), generalized. The target is **dynamic equilibrium** — most learning and enjoyment per unit of effort. Gauges are the sensors, the watchdog the homeostat, the human the setpoint.
- **The fundamental.** Every band runs the same loop at its own rate — **try → feedback → improve** — and that loop has one engineering-grade anatomy, [60-agent-loop-architecture.md](../../../brana-knowledge/dimensions/60-agent-loop-architecture.md)'s seven steps, derived independently and matching 1:1: ORIENT = memory read-on-entry · SELECT = **queue** (atomic pull — externalized, so a loop cannot game its own priorities) · ACT = **pump** · MEASURE = **gauge** (objective readout, never self-assessment, never acts — the *gauge law*) · JUDGE = **valve** (Actor≠Evaluator; split by reversibility — machine judges own reversible outcomes, the human valve the irreversible ones) · ASSIMILATE = memory write-on-exit · RESTART = pacing `{active, waiting, empty}`. The layer test is therefore an anatomy exam, run both ways: for any band, ask which step is missing (Knowledge has strong ORIENT/ACT/ASSIMILATE, weak MEASURE/JUDGE — why eval-rerunner and memory-hygiene surfaced as candidates before anyone could name why).
- **Where the metaphor stops.** Queues and valves are deliberately *not* wave-like: a queue decouples frequencies so they need not stay in phase (law 1), a valve is a discontinuity where flow may stop dead. Continuous wave as the medium; discrete instruments mounted in it. The frequency lens covers the timescale structure, never the parts catalog — the four primitives (§Cycle → Mechanics) remain the vocabulary for the machinery.

## Vocabulary

Term → one line → owner doc. Every term here traces back to a node in [the-brana-guide.md](../ideas/the-brana-guide.md) — check there for the full discussion, refs, and any flagged seams.

**Space**

| Term | One-line | Owner |
|---|---|---|
| **Bulk** | The shared portfolio; the laws every brane obeys. | this page |
| **Brane** | A self-contained unit at any scale — a KK-tower family, not one size. | this page |
| **Project** | The brane at the epic ring. | this page §L1 table |
| **Station** | The brane at the beat ring; loads skills as playbooks. | [drained/skills-as-loops.md](../ideas/drained/skills-as-loops.md) |
| **Grain** | The brane at the micro ring — a file, a function. Renamed from "organ" 2026-08-20 (see the-brana-guide.md L0.2) — organ imported anatomy's specialized-parts metaphor into a physics-only cover; grain matches "fine-grained" and ties to coarse-graining. | [skills-loops-graphs.md](../ideas/skills-loops-graphs.md) (worktree — not yet landed) |
| **Fields** | A brane's own context/tools/contract — confined to it, don't cross. | this page |
| **Skill** | A playbook a station loads. | [drained/skills-as-loops.md](../ideas/drained/skills-as-loops.md) |

**Cycle**

| Term | One-line | Owner |
|---|---|---|
| **Graph** | The shape: nodes = agents/skills/stations, edges = hand-offs. Built two ways — as code (Workflow) or as data (tasks.json), walked by a loop. | [skills-loops-graphs.md](../ideas/skills-loops-graphs.md) (worktree — not yet landed) |
| **Loop** | A closed string — unpinned, returns; the only thing that crosses branes. Equivalently: a graph whose path returns to an earlier node. | [features/loops-library.md](features/loops-library.md) |
| **Workflow** | An open string — pinned to the brane it started on, runs once. Equivalently: a graph, as code, that runs to completion in one call. | [workflow-primitive.md](workflow-primitive.md) |
| **Memory (gravity-leak)** | The one thing a loop carries across branes. | this page |
| **Ring** | One level of the Scale axis. The four named rings — micro / beat / epic / knowledge — are sample points on a continuous spectrum, not an ontology: other bands (sub-second lint/type-check · session, ~hours · season, ~months) are real and simply not yet instrumented. A band becomes a ring once something has actually cycled in it with records emitted (the layer test). | this page §Scale |
| **Seven-step skeleton** | A ring's loop shape: ORIENT→SELECT→ACT→MEASURE→JUDGE→ASSIMILATE→RESTART; plain gloss = context→action→feedback. | [60-agent-loop-architecture.md](../../../brana-knowledge/dimensions/60-agent-loop-architecture.md) |
| **Wave** | The human's unit of work — a batch of tasks pulled and shipped together. | [ADR-079](decisions/ADR-079-backlog-drain-loop-handoff.md), [ADR-080](decisions/ADR-080-plan-time-wave-graphs-epic-runner.md) |
| **Task** | The agent's unit of work. | [ADR-002](decisions/ADR-002-tasks-as-data-layer.md) |
| **Beat** | One pass through a ring's loop; produces a beat record. | [features/loops-library.md](features/loops-library.md) |

**Gate**

| Term | One-line | Owner |
|---|---|---|
| **Valve** | A human gate, placed by reversibility. | this page §Gate |
| **Studio** | The room for slow, high-thinking design work. | this page §Gate |
| **Cockpit** | The room for fast, low-thinking approvals. | this page §Gate |
| **Judge** | The machine or panel that owns a reversible-outcome decision. | [ADR-082](decisions/ADR-082-multi-agent-sizing-function.md) |
| **Autonomy rung** | L1 report-only / L2 assisted / L3 unattended — gated by AC coverage ("Non-AC fallback: stays L2"). *Not* this guide's L0–L6 walk levels — same letter, different axis. | [drained/brana-v3-redesign.md](../ideas/drained/brana-v3-redesign.md) §graduated autonomy ladder |
| **AC** | Machine-checkable definition of done; gates `/goal` and L3 eligibility. | [ADR-047](decisions/ADR-047-acceptance-criteria-schema.md), [ac-grammar.md](ac-grammar.md) |

**Scale**

| Term | One-line | Owner |
|---|---|---|
| **KK tower** | One brane-concept, instantiated differently at each ring. | [brana-etymology-naming.md](../../../brana-knowledge/dimensions/brana-etymology-naming.md) |
| **Compactification radius** | A ring's "size" — small = fast, large = slow. | [60-agent-loop-architecture.md](../../../brana-knowledge/dimensions/60-agent-loop-architecture.md) |
| **Low-pass filter** | The human's relationship to ring frequency — only slow rings reach them directly. | this page §Scale |
| **Inhabitant** | The human's role: lives in Cycle, decides at Gate, senses via memory. | memory `user_creative-vs-operative-modes` |
| **Orbit / Orbit** | Plain word inside Cycle now; capital-O = a future satellite component, on evidence. | [ADR-068](decisions/ADR-068-v3-supersession.md), [features/autonomous-runner.md](features/autonomous-runner.md) |

## Components — the doc map

Closes [the-brana-guide.md](../ideas/the-brana-guide.md) L5 (2026-08-23). Concept-level; the guide's Appendix A stays per-file. **One owner per concept.**

| concept | owner (single) | status | ch. |
|---|---|---|---|
| The whole / lens / chapters | this page §Cover, §Three chapters | landed | L0–L1 |
| Motion primitives (Task · Workflow · /loop · /goal · memory) | this page §Space | landed | Space |
| Mechanics primitives (queue·pump·valve·gauge), flow, seven laws | this page §Cycle → Mechanics | landed (D3) | Cycle |
| Rings, spectrum, layer test, skeleton match | this page §Scale | landed (D3) | Scale |
| Station (= pump body), grain files, three homes | this page §Space → Grain files | landed | Space |
| Handoff packet (AC real; spec/log/refs → t-3007/t-3008/t-3009) | this page §Space → Packet | landed | Space |
| Skills-layer verdict (no atom schema; t-2278 intact) | [ADR-085](decisions/ADR-085-skills-as-stations-no-atom-schema.md) (Proposed) ← [skills-loops-graphs.md](../ideas/skills-loops-graphs.md) | hold | Space |
| Vendored Pocock organs | ADR-084 (Accepted-pilot, WT t-2837 — not yet on this branch) | land after guide | Space |
| Context economy as compactification | this page §Space (L2.5) + [context-budget.md](context-budget.md) (t-3014) | landed | Space |
| Loop contract (7 laws, beat, ASSIMILATE/RESTART) | [features/loops-library.md](features/loops-library.md) | shipped | Cycle |
| Workflow-vs-loop rule | this page §Cycle | landed | Cycle |
| Wave mechanics (graph, gate, drain, pull, leases) | [ADR-079](decisions/ADR-079-backlog-drain-loop-handoff.md) + [ADR-080](decisions/ADR-080-plan-time-wave-graphs-epic-runner.md); spec [plan-time-wave-graph.md](features/plan-time-wave-graph.md) | shipped; ADR-079 amended 2026-08-23 (t-3030, L3.3) → impl t-3043 | Cycle |
| Wave = human unit / task = agent unit | [ADR-086](decisions/ADR-086-wave-as-human-unit-pocock-ticket-shape.md) — Accepted 2026-08-24 (challenged, 12 findings applied) | landed | Cycle |
| Beat record = markdown doc | [features/loops-library.md](features/loops-library.md) + t-3008 | decided | Cycle |
| Readiness state (cross-skill "next for whom") | **no owner yet** — resolves with t-2834; intended home: [backlog-v3-schema.md](features/backlog-v3-schema.md) + ADR amendment | gated | Cycle |
| Two-bucket backlog lens + usage-lens correction | this page §Cycle + memory `feedback_backlog-field-usage-vs-feed-mechanism` | landed | Cycle |
| Pocock alignment verdicts | [research/2026-08-22-pocock-alignment-decision-matrix.md](../research/2026-08-22-pocock-alignment-decision-matrix.md) | landed | Cycle/Gate |
| Two rooms + hands store (`room`) | [ADR-063](decisions/ADR-063-pending-questions-store.md) (amended 2026-08-23, t-3030 §Amendment: `room`); build t-3021 | decided | Gate |
| `ask()` compile table | runner-layer prose — **owner to create:** [`system/loops/README.md`](../../system/loops/README.md) §ask (t-3021) | decided | Gate |
| Judge ladder | [ADR-082](decisions/ADR-082-multi-agent-sizing-function.md) + [`_shared/judge-sizing.md`](../../system/skills/_shared/judge-sizing.md) | shipped | Gate |
| Valve inventory + three tiers; GitHub at tier 2 | this page §Gate; t-3022, t-3023 | landed | Gate |
| Sandbox / capability isolation | [ADR-062](decisions/ADR-062-runner-executor-sandbox.md) + [runner-capability-isolation.md](../ideas/drained/runner-capability-isolation.md) | shipped | Gate |
| Autonomy ladder / shape graduation | [brana-v3-redesign.md](../ideas/drained/brana-v3-redesign.md) + [ADR-068](decisions/ADR-068-v3-supersession.md) §3 | governing | Gate |
| Orbit satellite · model/effort routing | ⏸ none (L4.5 / L4.6) | parked | Gate |
| Vocabulary | this page §Vocabulary | landed | all |
| Skill packaging tiers (W/A/A?/C) | [research/2026-08-23-skill-tier-mapping.md](../research/2026-08-23-skill-tier-mapping.md) (ADR-085 D3) — corrected 2026-08-24, was misattributed to `drained/skill-tiering.md` (a cold-start-perf doc, unrelated) | measured | Space |

Two concepts have no owner by design (readiness state, `ask()` prose) — both gated; intended homes are recorded above so they aren't invented twice. `drained/wave-pipeline.md` is a redirect stub (D3, t-3028) — everything it owned is on this page.

## Reading map

Read this page first. For how work actually flows through the system day to day, go to [Idea → Ship: The Skill Flow](idea-to-ship.md). For the studio's living, in-progress draft of everything below this line — including every open question and its refs — see [the-brana-guide.md](../ideas/the-brana-guide.md).
