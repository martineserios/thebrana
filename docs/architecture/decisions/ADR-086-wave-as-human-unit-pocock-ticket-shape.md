---
status: proposed
---

# ADR-086: The Wave Is the Human's Unit — Backlog Speaks the Pocock Ticket Shape
 · **Renumbered 085→086** (2026-08-23, t-3030, board D2 — t-2490 holds ADR-085 skills-as-stations)
**Status:** Proposed (2026-08-18) — pending `/brana:challenge`
**Date:** 2026-08-18
**Deciders:** Martín Rios
**Tags:** backlog, waves, mattpocock-mining, adr, skills, drain-loop
**Tasks:** t-2980 (this ADR) · t-2828 (plan-time wave graphs — several of its brainstorm items land here as decisions) · t-2838 (skill map — consumer) · t-2837/ADR-084 (Pocock vendoring pilot — the skills this ADR makes usable) · t-2830 (source research)
**Relates:** [ADR-065](ADR-065-epic-as-hierarchy-top.md) (epics own tasks, waves select them — D3) ·
[ADR-078](ADR-078-stale-task-park-via-tag.md) (derive a state signal, never store a parallel one) ·
[ADR-079](ADR-079-backlog-drain-loop-handoff.md) (§2 eligibility filter — amended here) ·
[ADR-080](ADR-080-plan-time-wave-graphs-epic-runner.md) (wave graphs, epic runner) ·
[ADR-084](ADR-084-upstream-skill-band-vendored-pocock-skills.md) (§3 name-remap contract — this ADR supplies its tracker half) ·
[backlog-v3-schema.md](../features/backlog-v3-schema.md) (D2 contract prompt, D3 wave object, D5 `context` conventions) ·
[wave-pipeline.md](../../ideas/drained/wave-pipeline.md) (§The spectrum — human as low-pass filter; §Four primitives) ·
[drain-loop.md](../../guide/workflows/drain-loop.md) (runbook to update) ·
Upstream: [mattpocock/skills](https://github.com/mattpocock/skills) `v1.2.3` — `to-tickets`, `setup-matt-pocock-skills` (`issue-tracker-{github,gitlab,local}.md`), `triage`, `wayfinder`, `CONTEXT.md`

---

## The framing

**A task is the agent's unit. A wave is the human's unit.**

- A **task** is sized to one fresh context window — a vertical slice an agent can build end-to-end without losing the thread — and it is tested by its **acceptance criteria**.
- A **wave** is sized to one human attention cycle — what you can hand off, walk away from, and verify at the next sitting — and it is tested by its **contract**.

`task : AC :: wave : contract`. Same shape one level up: a testable promise, approved before work starts, graded when it ends. The wave is the AC of the batch, and the batch is the thing you can delegate as a whole and stop thinking about — wave-pipeline.md's "human as low-pass filter" made concrete: couple to the wave (slow), sample the tasks (fast), stay out of the beats.

This is also the exact gap in Matt Pocock's model that brana fills. His AFK loop *is* "put it to work and focus elsewhere" — but unnamed and unbounded: it drains everything `ready-for-agent`, and "did it work?" has no unit to attach to except each ticket. The wave gives the delegation a boundary and a test. Everything below follows from taking his ticket as the agent's unit verbatim, and keeping the wave as the human's unit above it.

## Context

ADR-084 (2026-08-17) decided to vendor Pocock's artifact-shaped skills (`diagnosing-bugs` first, `code-review` and `wizard` gated on the pilot) behind thin brana adapters. Its §3 name-remap contract requires a mapping from his tracker vocabulary onto brana primitives. Reading his tracker seam at `v1.2.3` this session established the facts this ADR builds on:

- His skills are **tracker-agnostic**. `to-tickets`, `to-spec`, `triage`, `wayfinder`, `code-review` read a per-repo `docs/agents/issue-tracker.md` written once by `/setup-matt-pocock-skills`. Four backends ship: GitHub (`gh`), GitLab (`glab`), local markdown (`.scratch/<feature>/issues/NN-<slug>.md`), and **"Other" — the user describes the workflow in prose and the skill records it verbatim.** brana backlog fits the "Other" slot with no upstream change.
- His **ticket** is five things: title · *what to build* (end-to-end behaviour, user's perspective, no file paths — "they go stale") · AC checkboxes · `Blocked by` · `Status`. Nothing else.
- His **readiness** is one label, `ready-for-agent`, applied by a human at triage; five roles total (`needs-triage / needs-info / ready-for-agent / ready-for-human / wontfix`).
- His **frontier** is open ∧ **unblocked** ∧ unclaimed; claim is the first write; resolve appends a *gist + link* to the map, never the body.
- His **comments** are the append-only history of a ticket — the same job brana's `context` dated appends do.
- His skills read a repo-root **`CONTEXT.md`** glossary on entry.

brana's side, measured the same day:

- Pull eligibility is a four-way conjunction — `status:pending ∧ ac_state:approved ∧ ¬tag:parked ∧ wave selector` — for the single concept "an agent may take this."
- `wave_pull_decision` (`brana-core/src/tasks/wave.rs`) **does not check `blocked_by`** — a task with an open blocker is pull-eligible. ADR-079 §2 never said it would; it just didn't say it wouldn't. This becomes load-bearing the moment his `to-tickets` output (which relies on the frontier excluding blocked tickets) feeds our pump.
- Wave contracts are prose ("merged to dev with all build gates passed"); "contract met?" is re-derived by hand at every ship valve. D2 chose "prompt on empty; contract met?" — the prompt is not currently answerable by the tool.
- 16 waves exist; 5 shipped; most shipped waves ran `wip_limit: 1`; wave-6 sat `draining` with nothing eligible for three days by design. For a single task the wave is pure ceremony, so singletons bypass the pipeline entirely and never get drained.
- Four grouping constructs coexist (epic, phase, milestone, wave); backlog-v3-schema already says "stop creating new phases/milestones."
- ~30 task fields; 22% lack `kind`; ADR-078's audit found 52% of pending tasks stale >30 days. Cheap to file, hard to finish.
- `context` is the field that makes "do t-NNN" a complete instruction (the work-start protocol reads it first). It is *not* schema weight — it is the ticket body plus its comment history — but big contexts (t-2837's is ~4 KB, others larger) are re-read on every load.

## Decision

Storage does not move. Every item below is a convention, a derived view, or a small code change inside the existing `tasks.json` + brana-core + wave machinery.

### 1. Two units, two sizing rules

- **Task = one fresh context window.** A vertical slice (schema → API → UI → tests, or the equivalent for the domain) that is demoable or verifiable on its own. Pocock's rule, adopted verbatim as the *cut* rule; `effort` keeps meaning as cost. Wide mechanical refactors are the exception and use expand–contract (his rule too; brana had no name for it).
- **Wave = one AFK cycle.** If you can't say what you'll check when you come back, it isn't a wave yet; if it's more than one sitting's worth of review, split it. Empirical band from shipped waves: 1–7 tasks, about a day. Written into `drain-loop.md` as the sizing rule.

### 2. The Pocock ticket body is the brana ticket discipline

Fields already exist; the change is that they stop being optional for anything that will be drained:

| Pocock ticket | brana field | Discipline |
|---|---|---|
| Title | `subject` | as today |
| What to build | `description` | end-to-end behaviour, user's perspective, **no file paths or snippets** (exception: a prototype-derived snippet that encodes a decision) |
| AC checkboxes | `acceptance_criteria` (authored as `AC:` lines in `context`) | required before `ready-for-agent` |
| Blocked by | `blocked_by` | honest — the frontier will enforce it (§4) |
| Status | derived triage role (§3) | — |
| Comments | `context` dated appends | pointer discipline (§7) |

### 3. His five triage roles become the canonical readiness vocabulary — derived, never stored

ADR-078's lesson stands: two stored signals for one state drift. The roles are a **derived view** over fields we already keep, and `ready-for-agent` is the single bit the pump reads:

| Role | Derived from |
|---|---|
| `needs-triage` | `status:pending ∧ ac_state:none` |
| `needs-info` | `status:pending ∧ ac_state:proposed` (contract drafted, not approved) |
| `ready-for-agent` | `status:pending ∧ ac_state:approved ∧ ¬tag:parked ∧ execution ≠ manual` — **the pull-eligibility bit** |
| `ready-for-human` | `status:pending ∧ ac_state:approved ∧ (execution:manual ∨ tag:human)` |
| `wontfix` | `status:cancelled` |
| *(claimed)* | `status:in_progress` |
| *(resolved)* | `status:completed` |

Exposed as `brana backlog query --role ready-for-agent`, in `brana backlog get` output, and as the selector term `role:<name>` for waves (§5). No new stored field; `backlog_set(field: "role")` is rejected like `epic` was.

### 4. Frontier = ready ∧ unblocked ∧ unclaimed (amends ADR-079 §2)

`wave_pull_decision`'s filter becomes `role:ready-for-agent ∧ every blocked_by completed-or-cancelled`, then the WIP bound. `NoneEligible` grows a `blocked` count beside `unapproved` and `parked` so the stall reason stays visible. This is Pocock's frontier rule and it closes the gap named in ADR-079's own follow-up notes.

### 5. One standing wave; bespoke waves only for release units

- A **standing wave** — selector `role:ready-for-agent`, no contract, no gate, `wip_limit` set from t-2782's telemetry — is always `draining`. It *is* Pocock's AFK loop expressed as a wave. Singletons never need a bespoke wave again, and stop bypassing the pipeline.
- **Bespoke waves** are release units: ≥3 tasks that ship together, or anything gated on another batch. They keep contract, gate, and their own `wip_limit`. A task matched by a bespoke draining wave is pulled by that wave first (bespoke selectors take precedence over the standing selector; overlap is otherwise still accepted per wave-4's precedent).

### 6. Contract as `CHECK:` lines — testable, like AC

The wave `contract` field keeps its prose, and gains machine-readable lines using the `CHECK:` convention D5 already reserved for `context`:

```
CHECK: all selector tasks completed
CHECK: merged to dev
CHECK: cargo test -p brana-core green
```

`brana backlog wave ship <id>` evaluates the checks it can (task states, merge-base, a named command) and **shows** the result — it never sets `shipped` on its own (ADR-079: no auto-ship). D2's "epic empty → contract met?" prompt becomes answerable, and a wave-level grader (build-evaluator's shape, one level up) becomes possible later without another schema change. Item (e) of t-2828's list, landed as a convention rather than a schema.

### 7. Comments = `context` appends, with the pointer discipline

`context` is protected — it is the ticket body and its comment history, the field that makes "do t-NNN" complete. Two conventions, both from Pocock's `writing-for-agents` / wayfinder practice, and both already half-present in `tactical-context.md`:

- **Dated appends** (`YYYY-MM-DD: …`) are the comment stream. Unchanged.
- **Pointer, not paste.** An append names the *home of record* and a one-line gist; it does not restate the content. Home-of-record table (the "third kind of doc" does not exist — content goes where it already lives):

| Content | Home (pointer target) | Inline in `context` |
|---|---|---|
| decision + rationale | ADR §n | one line + pointer |
| requirements / design | feature spec `docs/architecture/features/<slug>.md` | "spec: … §n" |
| evidence / findings | `docs/research/<date>-<topic>.md` | gist |
| shaping in flux | `docs/ideas/<topic>.md` | pointer to section |
| learning / gotcha | auto-memory pattern / field note | gist |
| code state | commit / branch / PR / `file:line` | ref only |
| sibling task history | `t-NNN` | "see t-NNN context <date>" |
| **task-local tactics** (next step, parking reason, "test with X not Y") | **nowhere else — this is what `context` is for** | inline, in full, short |

If an inline append grows past a paragraph, that is the signal it is really a spec/idea/ADR that should exist and be pointed at.

### 8. Interop seam: the tracker doc and `CONTEXT.md`

- **`docs/agents/issue-tracker.md`** (his "Other" backend) is written for thebrana and generated by `/brana:align` for other repos. Half of it is the operations table (create → `brana backlog add`, read → `get`, list → `query --role`, comment → `set context --append`, label → `ac approve` / `tags`, close → `set status completed`, blocked_by → `set blocked_by +t-N`, claim → the atomic pull, wayfinder map → an epic node, decision ticket → `kind:research` child, frontier → `role:ready-for-agent ∧ unblocked`); the other half is the home-of-record table from §7. This file *is* ADR-084 §3's tracker vocabulary map, so the adapter no longer has to carry it.
- **`CONTEXT.md`** at repo root, generated by `/brana:reconcile` from `docs/domain/` + the ubiquitous-language glossary (his Language / Relationships / Flagged-ambiguities layout). Cheap, and every one of his skills reads it on entry. Not hand-maintained — regenerated, so it cannot drift from the domain docs.

### 9. Waves are the only process grouping

Phase and milestone creation is frozen (backlog-v3-schema already says so; this ADR makes it a rule the CLI warns on). Existing nodes stay. Epics own (subject), waves select (process), tasks are the beats — three constructs, each with one job.

## Non-decisions

- **Storage stays `tasks.json`.** GitHub Issues as the canonical store is rejected for brana (his default, not his requirement): no waves/contracts/receipts/telemetry there, polling latency and rate limits for a per-minute pump, no atomic claim across concurrent sessions, no offline. A *client* repo that needs the GitHub UI flips its own tracker doc to the GitHub backend — the seam allows it per repo without touching brana.
- **No field renames.** His vocabulary is met at the derived-view and tracker-doc layer (§3, §8), not by renaming stored fields.
- **No new `role` field, no new status value.** Derived only (ADR-078).
- **Wave-level autonomy, promotion-by-rule, shadow drains, dead-letter wave** — t-2828 items (c), (d), (g) — remain deferred; this ADR arranges the existing primitives, it does not add mechanisms.
- **Field diet** is *not* decided here — the structured-field usage audit (candidate task below) produces the evidence first; `context`, `notes`, `description`, `acceptance_criteria` are out of scope for any diet by construction.

## Consequences

- **Positive:** Pocock's `to-tickets`, `triage`, `to-spec`, `wayfinder` write straight into brana backlog through his own sanctioned seam; the vendored organs of ADR-084 get their tracker map for free.
- **Positive:** one readiness bit instead of four signals; frontier semantics match the upstream tickets that will feed it; singletons stop bypassing the pipeline; "contract met?" becomes a tool answer, not a re-derivation.
- **Positive:** the wave gets a stated purpose and a sizing rule; the ceremony objection is answered by the standing wave, not by removing waves.
- **Negative (accepted):** the derived-role view is one more thing brana-core computes and must keep consistent with the pull filter — mitigated by making the pull filter *call* the same derivation (single owner, the ADR-079 principle).
- **Negative (accepted):** the standing wave changes what "draining" means for the whole backlog — any approved, unparked, unblocked task is now agent-eligible by default. That is the intended semantics of `ready-for-agent`; the human valve moves fully to `ac approve`, which is where ADR-079 already put it. If that proves too eager, the standing wave's `wip_limit` and `status` are the knobs — no rollback needed.
- **Negative (accepted):** `CONTEXT.md` and `docs/agents/issue-tracker.md` are two more generated files that can go stale if the generator isn't run; both are reconcile outputs, so drift shows in the same gauge as every other doc.

## Candidate tasks (each S/M, one wave slot; to be created on acceptance)

| # | Task | Effort | Amends |
|---|---|---|---|
| T1 | Derived triage roles + `role:` selector term + `--role` query; `role` rejected as a write field | M | brana-core query, wave selector parser (ADR-080 §1 single parse point) |
| T2 | `blocked_by` in `wave_pull_decision`; `NoneEligible.blocked` count; ADR-079 §2 text | S | ADR-079 §2 |
| T3 | Standing wave: create `wave-standing` (selector `role:ready-for-agent`), precedence rule for bespoke selectors, drain-loop.md | S | drain-loop.md, ADR-080 §3 |
| T4 | `CHECK:` lines in wave contract; `wave ship` shows check status; D2 prompt wiring | M | backlog-v3-schema D2/D5 |
| T5 | `docs/agents/issue-tracker.md` for thebrana + `/brana:align` generator; `CONTEXT.md` generator in `/brana:reconcile` | M | ADR-084 §3 (supplies its tracker half) |
| T6 | Structured-field usage audit (`brana backlog query --output json`, fill rate per field, `context`/`notes`/`description`/AC excluded); report only, diet decided after | S | backlog-v3-schema §Relationship |
| T7 | Sizing rules + pointer discipline written into `drain-loop.md`, `tactical-context.md`, `task-convention.md`; phase/milestone-creation warning in the CLI | S | task-convention.md, tactical-context.md |

`brana merge <task-id>` (the merge-valve tool) is not listed — it is already t-2838's top friction item and stays there.

## References

- Pocock, `to-tickets` SKILL.md and `setup-matt-pocock-skills/issue-tracker-{github,local}.md` at `v1.2.3` (read 2026-08-18) — frontier, claim, resolve, "Other" backend, ticket template
- Pocock, `CONTEXT.md` (repo root) — Language / Relationships / Flagged ambiguities layout
- [t-2830 research](../research/2026-08-13-matt-pocock-skill-system.md) §1 (`wayfinder`/waves cousins), §2, §7
- [ADR-084](ADR-084-upstream-skill-band-vendored-pocock-skills.md) §3 — the adapter contract this ADR's §8 completes
- `brana-core/src/tasks/wave.rs` — `wave_pull_decision` (current filter, no `blocked_by`)
- t-2828 context — brainstorm items (b) standing waves, (e) machine-checkable contracts, (f) wave board, landed here as §5, §6; others deferred
