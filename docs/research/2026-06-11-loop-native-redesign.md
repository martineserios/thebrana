# Loop-Native Redesign of thebrana

> Date: 2026-06-11 · Status: research + vision, pre-decision · Origin: `/loop` feature adoption session
> Sources: ADR-050, ADR-052, ARCHITECTURE.md, 32-lifecycle.md, build-loop-redesign.md, skill survey (build/close/sitrep/ship/reconcile), 3 web scouts, challenger pre-mortem on async-close loop
> Follow-ups live in: t-1973/t-1974 context (challenger dispositions), this doc (architecture direction)

## Question

How should thebrana be redesigned so its pipelines (build, close→sitrep, challenger, the DECIDE→BUILD→SHIP→MAINTAIN wheel) exploit the Claude Code `/loop` and `Workflow` primitives?

---

## Part 1 — Research findings

### Finding 0 — Prior art is internal: ADR-050 already governs loops

[ADR-050](../architecture/decisions/ADR-050-loop-request-protocol.md) "loop-request-protocol" (proposed 2026-06-10, accepted 2026-06-11 after challenger review of this doc) constrains any redesign:

- **Suggest-and-confirm, never auto-spawn.** Skills may suggest a loop (BUILD start for L/XL, CLOSE of multi-session tasks) via one AskUserQuestion max.
- **Cache-aware intervals:** ≤4 min (inside 5-min prompt-cache TTL) or ≥20 min. Never 5–19 min.
- **Auto-advance guardrails (t-517):** machine-verifiable checkpoint required; never cross a human gate; max 3 consecutive auto-advances; `validate.sh` must pass.
- **Rejected:** auto-spawned test/drift watchers (cache economics, redundancy, LoopTrap surface — arXiv 2605.05846 P5 sunk-cost / P7 recursive decomposition).

### Finding 1 — Current pipeline state

- Build = SPECIFY→DECOMPOSE→BUILD→CLOSE with **5 hard human gates** (CLASSIFY, M/L approval, SPECIFY→DECOMPOSE artifact gate, per-subtask TDD gate, state-commit). Not unattended-loopable as-is.
- `/brana:reconcile` and `/brana:sitrep` have **zero gates** — loop-ready today.
- close→sitrep is a state handoff (close writes session state, sitrep reads) — an informal state machine.
- ADR-052 close-queue (t-1972 done) is already producer/queue/drainer — the loop-native template. Drainer (t-1974) pending.

### Finding 2 — External convergence

Industry pattern (LangGraph, CrewAI Flows, AutoResearch): **skills as pipeline stages reading/writing shared serialized state, explicit checkpoints, first-class termination.** Brana's tasks.json + session-state + close-queue already are that shared state; the missing piece is a formal step-state contract.

Guardrails consensus: max iterations + budget caps + no-progress detection on *observable state* (git diff, test exit codes), never self-asserted progress. Brana's checkpoint rules already comply.

Gaps in the literature: no published prior art for suggest-and-confirm loop protocol, cache-aware polling intervals, or loop-as-pipeline-router. Brana is ahead on all three.

### Finding 3 — Two orchestration primitives, not one

| Primitive | Shape | Strengths | Weaknesses |
|---|---|---|---|
| `/loop` (+ ScheduleWakeup dynamic mode) | Recurring, in-session, context-bound | Interactive, reacts to session state, cheap per beat | Non-deterministic, not resumable, dies with session |
| `Workflow` tool (deterministic JS orchestration; opt-in via "ultracode" or explicit request) | One-shot fan-out/pipeline of subagents in clean contexts | Deterministic, resumable (journal), scales past one context window, schema-validated outputs, saveable to `.claude/workflows/` | Not recurring; heavyweight; explicit opt-in required |

**Verified 2026-06-11 (resolves challenger C3):** smoke test `wf_859926e3-bd2` confirmed `parallel()`, schema-validated `agent()` output, and `isolation: 'worktree'` (auto-created under `.claude/worktrees/`, auto-cleaned). Full API surface + opt-in rule documented in [workflow-primitive.md](../architecture/workflow-primitive.md). The skill-instructions opt-in path makes a user-started foreman a legitimate Workflow dispatcher.

**Mapping:** wheel-turning, babysitting, queue-watching → `/loop`. Heavy bounded phases (audit sweeps, batch queue drains, challenger panels, migration fan-outs) → `Workflow`. **Composed:** a loop iteration is the trigger ("queue has 14 entries"), a workflow is the muscle ("process all 14 with adversarial verify"), and the loop returns to watching.

Cost cautions:
- CC issue #54086: wakeup prompts containing full slash commands re-execute the entire command. Loop bodies must be narrow status-check prompts unless re-running the skill is the intent.
- CC auto-compacts near context ceiling; long-lived loops must recover from state files (sitrep pattern), never accumulated history.
- CC's master loop has 10 exit paths, 1 success; loop recipes must state termination explicitly.

---

## Part 2 — Vision: the factory model

Backlog as the source of work; the workflow-loop pair as the engine. A curated, granular backlog optimized for autonomous pickup: the system picks tasks, works until done, raises its hand when problems arise.

```
   ARCHITECT (human)                  FACTORY (system)
   ─────────────────                  ──────────────────────────────
   curate backlog ──────────▶  /loop (foreman, in-session heartbeat)
   answer raised hands  ◀────────┐      │ picks next agent-ready task
   review merges                 │      ▼
                                 │   Workflow (crew, per task)
                                 │      plan → implement (worktree) → verify AC
                                 │      │
                                 │      ├─ AC verified → mark done, pick next
                                 └────── ✋ gate / ambiguity / failed verify
```

**Foreman lifetime (decided 2026-06-11, resolves challenger W1):** the foreman is per-session — it dies with the session, per [ADR-050](../architecture/decisions/ADR-050-loop-request-protocol.md)'s durability rule. The "always-on factory" feel comes from a SessionStart hook line that suggests starting the foreman when agent-ready tasks exist (suggestion is persistent; loop is not). A `durable: true` foreman stays available via ADR-050's explicit-user-request exception, but nothing is designed or built for unattended operation until supervised runs produce evidence — an unattended foreman would stall on human-only gates (merges, raised hands) anyway.

### Load-bearing existing assets

1. **`AC:` lines** — the machine-readable acceptance criteria convention is the contract an autonomous workflow verifies against. Nothing matters more.
2. **`blocked_by` DAG + `brana backlog focus`** — dispatch is a CLI call, not model judgment.
3. **Branch convention + worktrees** — each task workflow runs isolated on `{epic}/{type}/t-NNN-{slug}`; merges stay human (never looped, per ADR-050 gate rule).

### Definition of ready (the hard part)

The failure mode is a vague task producing confident garbage that passes its own vague criteria. Curation IS the job — work shifts upstream to task authoring. A task is agent-ready only if:

- ≥1 `AC:` line that is machine-verifiable (command, test, file condition — never "works well")
- rich `context` (existing tasks-need-rich-context rule)
- effort S or M — L/XL decomposed first, human-reviewed
- no pending design ambiguity (no-silent-ambiguity rule, mechanized)

Mechanism: `execution: autonomous` marker (field exists in schema; `autonomous` value validation = t-1982) + `brana backlog lint <id>` check the foreman runs before dispatch (does not exist yet = t-1981). Not ready → skip and flag, never "do your best." Sequencing per challenger C2 (2026-06-11): both gate the foreman (step 5) only — the step-1 rehearsal uses human curation, and its evidence refines the lint heuristics before t-1981 is built.

### Hand-raising protocol

Background workflows can't ask interactive questions. On gate / unverifiable AC / failed verify after retry / ambiguity, the workflow:

1. writes question + evidence to the task `context` and a pending-questions store (dedicated schema, designed in t-1993 — close-queue's ADR-052 schema is session-extraction-specific and does not map to questions; per challenger W3, 2026-06-11),
2. marks the task blocked (foreman skips it; one stuck task never stalls the factory),
3. pushes a notification.

Human answers in batch; answered tasks become dispatchable. ADR-050 caps apply on top (max 3 auto-advances, machine-verifiable checkpoints, interval rule).

### Foreman prompt contract (draft, pre-rehearsal — resolves challenger W2)

**Rule: foreman bodies contain CLI calls and named-workflow references only — never slash commands.** CC #54086 re-executes any slash command embedded in a wakeup prompt, gates and all. This is the design artifact the foreman recipe (t-1994) refines with rehearsal evidence:

```
Foreman beat (one iteration):
1. If a task-crew workflow from a previous beat is still running → do nothing this beat.
2. Run: brana backlog query --status pending --json
   → filter execution=="autonomous", order per brana backlog focus.
3. For the top candidate run: brana backlog lint <id> --json
   → not ready: skip, note failed checks in task context, try next candidate (max 3).
4. Ready task found → dispatch the saved workflow "task-crew" with args {task_id}.
   Never inline a script; never invoke a slash command.
5. Nothing dispatchable → report "factory idle: N pending, 0 agent-ready" and continue.
Termination: user stop, session end, or 2 consecutive idle beats with an empty
autonomous queue.
```

Every line is machine-verifiable (ADR-050 prompt-content rule); the named `task-crew` workflow in `.claude/workflows/` satisfies the Workflow opt-in via the recipe the user starts (see [workflow-primitive.md](../architecture/workflow-primitive.md)).

### Roadmap (dependency graph — replaces the numbered list per challenger W4, 2026-06-11)

Done prerequisites: **ADR-050 accepted** (2026-06-11) · **step 2** close-extraction drain shipped (t-1974, completed, live systemd timer) · **step 3** ADR-050 suggestion points wired in build/close (t-731, completed — the "specified, not yet built" note above is superseded).

The backlog `blocked_by` DAG is the source of truth (`brana backlog tree t-1994`); this graph mirrors it:

```
t-1991 rehearsal (unblocked) ──evidence──▶ t-1981 lint heuristics
                                                │
t-1981 backlog lint ────────────┐               │
t-1982 execution:autonomous ────┤  (refined by rehearsal evidence)
t-1992 step-state contract ADR ─┼──────▶ t-1994 foreman recipe
t-1993 questions-store ADR ─────┘               │
                                                ▼
                                  t-1995 generalized work queue
                                  (filed blocked-by-design; re-scope
                                   from t-1994 evidence before decomposing)
```

| Node | Task | Blockers |
|---|---|---|
| Manual rehearsal | t-1991 | none — can run anytime |
| Definition-of-ready lint | t-1981 | none (deliberately after t-1991 evidence) |
| `execution: autonomous` validation | t-1982 | none |
| Step-state contract ADR | t-1992 | none (verify vs ADR-050 §t-517 first — challenger O3) |
| Pending-questions store ADR | t-1993 | none |
| Foreman recipe | t-1994 | t-1981, t-1982, t-1992, t-1993 |
| Generalized work queue | t-1995 | t-1994 |

Zero-code loop recipes from old step 1 (report-only reconcile @≥20m, post-ship CI babysitter @≤4m, inbox sweep) remain available anytime — gateless tier, no task needed.

### Open questions

1. Step-state contract: lives in session-state.json or a new run-state file? (→ decided inside t-1992)
2. ~~Foreman: recipe first, promote to skill suggestion after evidence~~ — decided 2026-06-11, encoded in t-1994.
3. Per-loop/per-task budget caps — revisit with brana-v2 compute model.
4. AC-gaming: what stops a workflow satisfying the letter of an AC while violating intent? (challenger panel topic for the step-state ADR, t-1992)

---

## Part 3 — Challenger pre-mortem on the async-close loop (2026-06-11)

Verdict: PROCEED WITH CHANGES. No conceptual flaws — all findings were silent-failure plumbing ("make the failure observable", "make the lifecycle complete"). Full dispositions persisted in t-1973/t-1974 context. Highlights:

- **Dead-man switch:** stale-queue check belongs in session-start.sh as pure jq (covers dead cron, missing binary, unregistered job — all manifest as stale queue). Standalone safety commit candidate.
- **Dedup keys computed mechanically cron-side** — never trust the LLM worker to emit stable slugs.
- **Anchor session windows on durable state** (previous session-state `written_at`), not wall-clock windows or /tmp files.
- **Park-don't-block** queue processing; categorized failures.
- **Auto-routing to memory deferred** to ADR-052 §6 checkpoint — human review is the safety property while the worker is unproven.
- ADR amendments pending: ADR-052 schema dedup_key + §6 note; ADR-041 §4 exception note (/tmp correct for within-cron output — outputs/ would double-process via close batch-extract).
