---
title: Backlog v3 — Three-Axis Schema (Subject · Tags · Waves)
status: draft
created: 2026-07-20
relates-to:
  - "[brana-v3 redesign](../../ideas/brana-v3-redesign.md)"
  - "[brana-backlog-v2 schema](../../ideas/brana-backlog-v2-schema.md)"
  - "[ADR-002 tasks-as-data-layer](../decisions/ADR-002-tasks-as-data-layer.md)"
  - "[ADR-003 agent-driven task execution](../decisions/ADR-003-agent-driven-task-execution.md)"
  - "[ADR-047 acceptance-criteria schema](../decisions/ADR-047-acceptance-criteria-schema.md)"
  - "[ac-grammar](../ac-grammar.md)"
  - "[backlog-lint](backlog-lint.md)"
  - "[backlog project-scoping](backlog-project-scoping.md)"
  - "[agentic primitives](../agentic-primitives.md)"
amends: [ADR-047 (adds ac_state), v2 initiative-as-hierarchy-top (ADR-065)]
supersedes-fields: [epic-tag-flat, stream, level-OR-type-dup, initiative-node]
---

# Backlog v3 — Three-Axis Schema

> Designed 2026-07-20. The backlog reshaped to fit the [brana-v3 self-evolving loop](../../ideas/brana-v3-redesign.md): the task becomes both a **machine-readable contract** a loop can drain *and* a **self-contained handoff packet** any worker (loop, agent, human) can pick up cold.

## Problem

Two problems, one root.

1. **The human gets lost.** 43 epics — of which ~19 are already done but never marked, 1 dead, 7 duplicates of a family (`harness` → `harness-v2` → `harness-core`), and one (`dx-tooling`, 492 tasks) 89% drained. 491 "pending" tasks that are really three unrelated piles (mechanical, judgment, a reading list). The felt overwhelm is a **lifecycle failure**, not a volume or depth failure: epics have no status, no WIP cap, and never close.
2. **Loops have nothing to drain.** v3's autonomy needs the task to be a verifiable contract (`execution:` marker, `AC:` lines). Today AC coverage is ~13% (67 of ~500 pending). A loop is only as verifiable as its contract is authored.

Both are the **same** disease seen from two sides: a backlog that is a write-only log instead of a drainable, contract-bearing work surface fails the human (overwhelm) *and* the loop (nothing to verify). Fix one, fix both.

## Design goals

- **Fits two work-shapes with one schema.** Deep, quotable app/client plans (layers → components → tasks) *and* flat loop-drained system work — same primitives, depth chosen per work.
- **Three orthogonal axes.** Never conflate *what we're building* (subject) with *how we drain it* (process) with *cross-cutting attributes* (tags).
- **Resolve duplication before adding.** The v2 schema already carries redundancy — `level` *and* `type` both encode the hierarchy; `kind` *and* `work_type` both taxonomize; AC lives in *both* a structured `acceptance_criteria` field and an `AC:` context convention. The v3 job is to **pick survivors** first, then add the genuinely net-new (`spec`, `wip_limit`, `shape`, `log`, `ac_state`, key:value tags, wave object). Deletes ≥ adds (v3 wave contract) — and here the deletes are real (collapse two hierarchy fields to one, two taxonomies to one).
- **Adopt what already exists.** `execution: code|autonomous` is real (746/3 tasks) — reuse it. `active_epic` (in `tasks-config.json`) already names the single active epic — reuse it, don't reinvent "one active at a time." `acceptance_criteria` (ADR-047) is the canonical AC store — extend it, don't fork a third representation.
- **The task as self-contained handoff.** Anyone — a loop, an agent, a future session — picks up a task and has the contract, the reminders, the relevant docs, and the full attributed history inline.

## The three axes

```
WHAT (subject)  ─►  EPIC ─ layer ─ component ─ TASK ─ subtask     depth = as much as the work needs
                    the plan. quotable (effort rolls UP). one home per task. empty = feature done.

CROSS-CUTS      ─►  key:value tags on every task                  orthogonal. many per task.
                    client:acrelec  layer:backend  risk:high  theme:security  sprint:2026-w30

HOW (process)   ─►  WAVE = QUEUE ─ a named selector over tags + attributes    drainable. spans or scopes.
                    drained by:  loop (mechanical)  +  you (judgment, cockpit).  empty = batch shipped.
```

A task has **one home** (subject tree), **many tags** (orthogonal), and **flows through whatever waves select it** (process). The three are independent — a bug lives almost entirely on the tag+wave side and barely touches the tree; a client app-plan is a deep tree; a system chore is a flat leaf. All three fit.

## Object model

### Epic — the top subject node ("what we're building")

**Reconciliation first (this reverses a shipped v2 decision — call it out).** Today the hierarchy is a *type/level tree* topped by `initiative` (v2 schema), while `epic` is a **separate flat string field** orthogonal to that tree. That's the two-grouping-systems problem in the schema itself. v3 resolves it: **collapse `level` and `type` into one hierarchy field, and make `epic` the top node of that one tree** — so the flat `epic` tag stops being orthogonal and becomes the top of the (now single) hierarchy, absorbing `initiative`'s role. This **supersedes v2's initiative-as-top**; it is a deliberate reversal, not an oversight. Below the epic, grouping nodes (`layer`/`component`, or the retained `milestone`/`phase` — D6) are **optional depth**: an app build goes 4–5 deep for decomposition and quoting; a system chore stays `epic → task`.

| Property | Storage | Notes |
|---|---|---|
| status | reuse `status`, +2 values | `active` · `next` · `parked` · `done` · `archived`. "One active at a time" reuses the existing `active_epic` pointer in `tasks-config.json` (project-scoping) — not a new mechanism |
| WIP cap | **new** `wip_limit` (default 10) | only meaningful on the active epic |
| gate | reuse `blocked_by` | epic N blocked on epic N−1 shipping |
| contract | reuse `context` `AC:` lines | definition of "feature done" beyond "no tasks left" |
| children | reuse `parent` | tasks/nodes parent to the epic — replaces the flat tag |
| auto-close | computed | last child done → epic done (the *empty = feature done* signal) |

- **Effort roll-up (quoting):** task `effort` sums up the tree → component → layer → epic gives an estimate. This is why app decomposition uses tree nodes, not tags.
- **WIP cap** is the anti-sprawl mechanism: the active epic holds ≤10 open tasks. Can't add #11 without closing or parking. At any moment "what's live" is one epic, ≤10 tasks.

### Task — the work unit + the contract + the handoff packet

Reuses all existing fields (`subject`, `description`, `status`, `priority`, `effort`, `kind`, `blocked_by`, `branch`, `created`/`started`/`completed`). Adds a **contract lifecycle** and a **communication log**:

| Field | New? | Purpose |
|---|---|---|
| `execution` | exists | `code` (human, default-deny) · `autonomous` (a loop may take it) |
| `acceptance_criteria` | **exists** (ADR-047, `Option<Vec<String>>`, 233 tasks) | the canonical AC store — the contract a loop verifies. v3 does **not** fork a new representation; the `AC:` context convention (ac-grammar) remains a human-authoring shorthand that lints into this field |
| `ac_state` | **new — ADR-047 amendment** | `none` → `proposed` (a loop populated `acceptance_criteria`) → `approved` (human OK'd them). Gate for loop-eligibility. Net-new: ADR-047 defined no approval state |
| `spec` | **new, nullable, structured** | the governing spec/ADR that *authorizes* the task — gates start, drives drift-cascade, is the source its `AC:` lines derive from. `null` = untraced (legit for meta-work/bugs). Inherited from the epic; a task may add a finer ADR. See below. |
| `shape` | **computed, never stored** | `kind × work_type × effort × tags × ac-presence` — the join key that decides *which drainer* may take the task. `work_type` (implement/research/design/…) is a key eligibility signal: a loop drains `work_type:chore` far sooner than `work_type:design` |
| `tags` | exists, upgraded | **key:value** (`layer:backend`, `client:acrelec`, `risk:high`) — the orthogonal axis |
| `context` | exists, extended | already carries `AC:` (lints into `acceptance_criteria`) — v3 adds two net-new conventions: `CHECK:` (soft human reminders) · `ref:` (linked docs/ADRs — self-containment) |
| `log` | **new** | attributed, typed, append-only thread — see below |

`ac_state:proposed → approved` is exactly what makes **"the loop backfills its own contracts"** work: the first loop reads a mechanical `ac_state:none` task, **populates its `acceptance_criteria`** (ADR-047's field), sets `proposed`; you approve in the cockpit → `approved` → now it is loop-drainable. No new AC representation — just the missing approval state on the existing field.

### Spec provenance — the task gates to its spec/ADR

When a task is born from a spec doc (e.g. `/brana:backlog plan` over a feature spec), it **carries a link back to the doc that authorized it.** This is a **dedicated, structured, nullable field** — *not* a `context` convention line like `ref:`. `ref:` is informational (soft, many, free-text); `spec` is authoritative (typed, gate-bearing) and does three jobs.

```
spec:                                     ← nullable. null = no governing spec (legit for meta-work / ad-hoc bugs)
  doc:    docs/architecture/features/backlog-v3-schema.md
  anchor: #waves                          ← optional, anchor-precise
  adr:    ADR-060                          ← optional finer ADR for a local decision
  status: approved                        ← resolved from the target's frontmatter; drives the gate
```

**Nullable semantics.** A `null` `spec` is a valid, first-class state — the start-gate simply doesn't fire (you can't gate to a spec that doesn't exist). Only tasks *with* a `spec` get gated to it and cascaded on its drift. Whether a task may reach `ac_state:approved` (loop-eligibility) while `spec` is null is D7. Because it is a real field (not free text), it is queryable — `--spec <doc>` powers the drift-cascade, and `--spec null` surfaces orphan work that ought to be traced.

1. **Provenance (always).** Every task traces back to the decision that spawned it. "Why does this task exist?" is one link away — no archaeology.
2. **Start-gate.** An implementation task whose `spec:` target is missing or not `status: approved` is **blocked from starting** (advisory `warn` during pilot, matching `spec-gate.sh`; hard-block later — D7). This is the existing M+ spec-gate made *per-task and precise* — it knows exactly which spec is missing, not just "some spec."
3. **Drift-cascade.** When the spec doc changes in git, every task with `spec: <that doc>` is flagged for `/brana:reconcile`. The rule "spec changes push to implementation" stops being manual discipline and becomes a mechanical query: *which open tasks derive from a spec that moved?*

**Inheritance:** the **epic** carries the primary `spec:` (its governing feature spec); child tasks inherit it, and a task may add a finer ADR for a local decision. So the whole subtree of a feature is bound to its spec by default, without stamping every task by hand.

**Feeds the contract:** because `spec:` points at the doc that *defines done*, it is also where a loop reads to author `AC:` lines during backfill — provenance and contract-authoring share one link.

### Tags — the orthogonal index

Key-value, many per task. The rule for **node vs tag**:

- **Tree node** → the dimension you *decompose and quote on* (layer/component; effort rolls up). One home.
- **Tag** → every *cross-cut* you filter/slice/wave by (client, risk, theme, sprint, external-dep, surface). Many per task.

Same dimension is never both (no double-bookkeeping). **This is a net-new schema change, not adopt-don't-build:** tags are flat string arrays today (`["unknown"]`) and no existing doc proposes key:value. The migration can be gentle — a `key:value` string convention with query support for `--tag key` / `--tag key:value`, bare tags still valid — but it *is* a decision (see D8), not a free convention.

### Wave = Queue — the process overlay

A wave is **not** a tree level and **not** a subject. It is a named, drainable **selector** over `tree-scope ∧ tags ∧ computed-attributes`. Membership may be an **explicit tag** (`wave:v3-w1`) or a **live query** (`shape:mechanical ∧ ac_state:approved`). A loop runs `while wave.next(): work()` — drain-to-empty falls out.

```
Loop wave     :  shape:mechanical ∧ ac_state:approved      → the AC/bug-drain loop empties this
Delivery wave :  client:acrelec ∧ component:auth           → quote & ship one component
Cross-cut wave:  theme:security ∧ status:pending           → a security push across ALL epics
Bug-drain wave:  kind:fix ∧ ac_state:approved ∧ shape:mechanical   → standing, always-on
v3 wave 1     :  tag wave:v3-w1                            → the migration batch
```

**Stored as a thin process object** (assumption D3): `{ selector · contract (ship criteria) · gate (prev wave) · status: queued→draining→shipped }`. It *selects* tasks; it does not *own* them — epics own tasks (subject), waves select them (process). Rationale: v3's waves carry contract/gate/ordering that a pure live query cannot hold.

### The `log` — attributed handoff thread + outcome ledger

Not an overwritten `notes` blob. A thread; every entry stamped with **who** and **what kind**:

```
ts               by               type       body
2026-07-20 10:02 loop:ac-drain    status     claimed; repro test written, currently red
2026-07-20 10:04 loop:ac-drain    comment    fix applied in worktree; test green; validate.sh pass
2026-07-20 10:05 loop:ac-drain    handoff    PR #418 open — NEEDSHUMAN: touches auth RLS, wants human merge
2026-07-20 11:20 agent:challenger question   check the token-refresh path too? possible same root cause
2026-07-20 14:00 human            verdict     merged-clean          ← graduation counts THIS row
```

- **`by`** vocabulary: `human` · `loop:<name>` · `agent:<type>` · `claude`.
- **`type`** vocabulary: `status` · `comment` · `question` · `blocker` · `decision` · `verdict` · `handoff`.
- **Why attribution + type is load-bearing:** in a system where loops and agents write autonomously, a loop's `status: tests green` is a **claim**; a human/verifier `verdict` is **truth**. Attribution keeps the trust boundary visible — you can filter to *only human-confirmed decisions*.
- **Convergence with v3:** the `verdict` entries **are** v3's outcome-ledger (merged-clean / merged-with-edits / rejected). The communication thread and the graduation-evidence ledger are the same structure — one field, two jobs.
- **Bloat control:** loops read *recent N + all `decision`/`verdict` rows*. The wave-2 curation/DECAY pass compresses old `comment`/`status` chatter but keeps `verdict`/`decision` forever. (Comprehension debt is a listed v3 risk.)

### The fully-assembled self-contained packet

```
subject / description   → WHAT (the ask)
fields                  → status · priority · effort · execution · ac_state · parent · tags
spec                    → WHY it exists — the governing spec/ADR (gates start, cascades on drift)
context: AC / CHECK / ref → contract + reminders + the docs you need, inline (ref: can auto-populate
                            from the doc-graph overlay, t-2275)
log                     → live state + full attributed history + the verdict ledger
```

A loop reads it and knows what "done" means and what's been tried. An agent adds a question. You resume in seconds after two weeks. That is the self-contained handoff — one new field (`log`) + two conventions (`CHECK:`, `ref:`).

## How each work-shape fits

| Shape | Subject (tree) | Tags | Wave | Contract |
|---|---|---|---|---|
| **App / client build** | deep: epic → layer → component → task; effort rolls up → quote | `client:` `layer:` `component:` | delivery waves per component | AC authored during planning |
| **System / meta work** | flat: `epic → task` | `surface:` `theme:` | cross-cut or loop waves | AC backfilled by the loop |
| **Bug** | leaf; parents to affected component if the tree exists, else flat — *never decomposed* | `kind:fix` `severity:` `component:` `regression:` | **bug-drain wave** (background) + **express lane** for `severity:high`/`P0` (jumps WIP → cockpit now) | **the repro test IS the contract** — `ac_state:approved` comes free from TDD |
| **Reading list** (research-inbox) | flat, or its own bucket | `kind:research` `source:` | triage wave (archive-heavy) | n/a — not code work |

The bug case is the cleanest proof the axes are independent: a bug is subject-homeless yet fully process-organized, and TDD's "reproduce with a failing test before fixing" makes it *more* loop-ready than most features (verification is objective: red → green).

## CLI surface — intents, not columns

**Design principle:** commands map to the **questions people and agents actually ask**, and a flexible **query grammar + intent aliases** translate the many phrasings into schema queries. Field names (`ac_state`, `work_type`) are an implementation detail the user rarely types. A schema is only useful if the CLI lets you *ask it things the way you think.*

Two layers:

1. **A query grammar** — `backlog q <tokens>` where tokens are `key:value` (`layer:backend`, `severity:high`, `status:pending`, `epic:auth`) plus computed predicates (`drainable`, `blocked`, `mine`, `stale`, `untraced`). Composable, orthogonal — this is how the tag axis is reached.
2. **Intent aliases** — named shortcuts over common queries, so nobody memorizes the grammar for the frequent asks.

| The question someone asks | Command | Resolves to (schema) |
|---|---|---|
| *"What do I work on next?"* | `backlog next` | next unblocked task in the **active epic**, respecting WIP |
| *"What am I building — how's this feature?"* | `backlog epic <slug>` | epic node: tree, % done, contract, empty-progress |
| *"Which epics are live / on deck?"* | `backlog epic ls` | epics grouped by `status` (active·next·parked·done) |
| *"How big is this — quote it."* | `backlog estimate <epic>` | roll **effort up** the tree → a number |
| *"What can a loop drain right now?"* | `backlog drainable [--wave W]` | `shape:mechanical ∧ ac_state:approved ∧ execution:autonomous` |
| *"Plan a wave / define a queue."* | `backlog wave new --select "<q>"` | stores a wave (selector+contract+gate) |
| *"Drain this wave."* | `backlog wave drain <id>` | the loop entry point — `while queue.next(): work()` |
| *"Show me all backend high-sev bugs."* | `backlog q kind:fix layer:backend severity:high` | the orthogonal tag slice |
| *"What's on my plate / blocked / stale?"* | `backlog mine` · `backlog blocked` · `backlog stale` | aliases over `q` |
| *"Why does this task exist?"* | `backlog why <id>` | the `spec` chain + the `log` thread |
| *"What derives from this spec?"* (drift) | `backlog derives <spec>` | `q spec:<doc>` — the reconcile cascade |
| *"Leave a note / hand this off."* | `backlog log <id> --by <who> --type <t> "…"` | append to the `log` thread |
| *"Give me the whole self-contained packet."* | `backlog handoff <id>` | renders subject+contract+refs+log |
| *"What's parked for a human decision?"* | `backlog needs-human` | the NEEDSHUMAN park lane |
| *"Define/approve done for this task."* | `backlog ac <id> add\|approve` | `acceptance_criteria` + `ac_state` |
| *"Activate / park / close an epic."* | `backlog epic activate\|park\|done <slug>` | epic lifecycle (+ `active_epic`) |

**Stretch (not required):** an NL front — `backlog ask "what can I drain in auth?"` compiling to `q component:auth drainable`. The core deliverable is the **grammar + aliases**; NL is a thin layer on top if wanted.

This surface is its own build unit — it lands in the **backlog-cli wave** (the `cli-backlog-schema` epic), TDD per command, and every new verb ships with the schema field it exercises.

## Decisions (resolved 2026-07-20)

Per the no-silent-ambiguity rule, each is a documented pick, not a silent choice:

- **D1 — Epic model:** epic becomes the **sole top node** of the single tree; the `initiative` node is **removed**. **Resolved → [ADR-065](../decisions/ADR-065-epic-as-hierarchy-top.md) (Accepted).** Linear link kept possible via an `initiative:` tag → Linear Initiative (sync adopted/refactored later).
- **D2 — Auto-close:** chose *prompt on empty* ("epic empty; contract met? mark done") over silent auto-close, to avoid premature close when the contract carries criteria beyond "tasks done." **Decided per recommendation, 2026-07-20.**
- **D3 — Wave storage:** chose *thin stored process object* (selector + contract + gate + status) over pure live query, because v3 waves carry contract/gate/ordering a query can't hold. **Decided per recommendation, 2026-07-20.**
- **D4 — WIP breach:** chose *warn (advisory)* over hard-block during the pilot, matching the existing spec-gate posture; hard-block later. **Decided per recommendation, 2026-07-20.**
- **D5 — Log vs conventions:** chose *one new `log` field* + `context` conventions (`CHECK:`, `ref:`) over multiple new fields, for simplicity / adopt-don't-build. **Decided per recommendation, 2026-07-20.**
- **D6 — Node type names:** **Resolved** — reuse existing `milestone`/`phase` nodes as the layer/component grouping levels (no new node types, no renaming ~165 nodes); effort roll-up preserved.
- **D7 — Spec-gate strictness:** chose *inherited `spec:` from the epic* + *advisory `warn`* on a missing/unapproved governing spec during the pilot (matching `spec-gate.sh`), hard-block later. Also open: does a task *require* a `spec:` to reach `ac_state:approved` (loop-eligibility)? **Decided per recommendation, 2026-07-20.**
- **D8 — Duplication survivors:** **Resolved** — hierarchy: keep `type`, drop `level`. Taxonomy: **keep both `kind` and `work_type`** (different axes — change-type vs activity; `work_type` feeds loop `shape`). Tags: **adopt key:value** (net-new). The deletes that keep deletes ≥ adds: `level`, the flat `epic` field, the `initiative` node, `stream`.

## Relationship to the existing schema

| Today (real fields) | v3 | Migration |
|---|---|---|
| `level` **and** `type` both encode hierarchy (task/milestone/phase/subtask/initiative) | **one** hierarchy field | **collapse to one** — pick survivor, backfill, drop the other. The core cleanup. |
| `kind` **and** `work_type` — different axes (change-type vs activity) | **keep both** | document the distinction so they stop being used interchangeably; `work_type` feeds loop `shape` |
| `epic` — flat string field (43), orthogonal to the tree | epic = **top node of the single tree** (~10) | convert ~10 survivors to nodes; re-parent tasks via `parent`; retire the flat field |
| `initiative` (level/type value, 17) | **removed as a node**; Linear-Initiative grouping → `initiative:` tag | drop the level; tag-encode only if Linear is adopted (ADR-065) |
| `active_epic` pointer (`tasks-config.json`) | **reused** as "the one active epic" | none — adopt as-is |
| `milestone` (118) / `phase` (47) | optional depth nodes (D6) | keep; stop creating new unless decomposing an app |
| `acceptance_criteria` (ADR-047, 233 tasks) | **kept** as canonical AC store | add `ac_state` beside it (ADR-047 amendment) — no new AC field |
| `AC:` context convention (ac-grammar) | **kept** as authoring shorthand | lints into `acceptance_criteria` (unchanged) |
| `execution` (code/autonomous, real) | **reused** as loop-eligibility gate | none — already correct |
| `tags` (flat string array) | `tags` (key:value) — **net-new** (D8) | gentle: `key:value` convention, bare tags still valid |
| `notes` (freeform blob) | `log` (attributed thread) | migrate content into a `human`/`comment` seed entry |
| `context` (AC + tactical) | `context` (+ `CHECK:` + `ref:`) | additive — existing lines unaffected |
| `order`, `branch`, `github_issue`, `priority`, `blocked_by`, `status` | **unchanged** | none |
| `stream` (deprecated) | removed | drop |
| — | `spec`, `wip_limit`, `shape` (computed), `log`, `ac_state`, wave object | net-new (none exist today) |
| ADR-003 `spawn` / `agent_config` / `agent_result` | related autonomy surface, **distinct** from `execution` | reconcile separately — not folded here |

## Relationship to the v3 waves

This spec is **not** separate work from the [v3 epic](../../ideas/brana-v3-redesign.md) — it *is* its backbone:

- **Cleanup** (collapse 43 → ~10, mark done, re-home strays, retire `dx-tooling`) = v3 **wave 1** (re-parent/supersession).
- **This schema** (epic-as-node + tags + wave-as-selector + lifecycle + log) = fits the existing **backlog-cli** wave.
- **AC backfill** on the ~120 mechanical tasks = the prerequisite that unblocks…
- **The loop + cockpit** = v3 **waves 2–4**. The `log`'s `verdict` rows feed **wave 5** (shape graduation).

## Non-goals / rejected

- **A third grouping object** on top of tree + tags — would re-create the sprawl.
- **Mandatory depth** — depth is a menu, not a ladder; forcing 6 levels on a bug is the anti-pattern.
- **Wave = epic** — rejected: conflates process with subject (the correction that produced the three-axis model).
- **Silent auto-close / hard WIP block** during pilot — see D2/D4.

## Fetch-awareness audit outcomes (2026-07-20)

An audit verified whether consumers read *both* doc locations and follow spec→ADR links. **Verdict: the "one front door, follow the links" model holds end-to-end** — the hard SDD gate (`pre-tool-use.sh`) is dir-agnostic; build SPECIFY/LOAD, recall, `brana graph build`, and doc-graph-overlay all index both dirs and traverse `supersedes`/`depends_on`/`ADR-NNN` edges. No correctness hole, no wrongful gate. Three findings, folded into this epic as tasks:

- **F1 — spec-gate.sh (no change).** Flagged as blind to `decisions/`, but on review it is **correct**: it warns only on M+ *impl* edits lacking a *feature spec*, exactly the front-door contract. Adding `decisions/` would let an ADR substitute for the spec — a regression. **Task: none; record the rationale so it isn't "fixed" later.**
- **F2 — reconcile superseded-ADR check (build).** reconcile scans both dirs but never queries the `supersedes` edges the graph already extracts, so a doc still citing a superseded ADR (live case: ADR-065 supersedes v2 initiative-as-top) is undetected drift. **Task: add a deterministic `validate.sh` check — superseded-ADR set → grep referrers → report.** TDD: fixture doc referencing a superseded ADR must flag.
- **F3 — backlog plan reads spec + walks ADR links (build, in this epic).** `plan` currently derives tasks conversationally without reading a spec and following its linked ADRs. It is being reworked here anyway (intent-CLI + epic-node planning) — **fold the spec+ADR read into that rework**, don't patch the old flow.

## Next steps

1. Merge this branch (`docs/backlog-v3-schema`) to `dev` — land the verified shape (spec + ADR-065 + lifecycle note).
2. `/brana:backlog plan` → graduate into the epic node + tasks, sequenced: cleanup (collapse 43→~10, from the family map) → schema + intent-CLI build → AC backfill → loop/cockpit. Fold F2/F3 in as tasks; TDD field-migration tests first.
3. First epic through the new lifecycle is the backlog itself — dogfood the model on its own creation.
