# Agentic Primitives — Taxonomy and the Target Process Loop

> **Date:** 2026-07-19 · Synthesis of the 2026 research sweep ([gap analysis](../research/agentic-engineering-2026-gap-analysis.md), [loop-engineering + Pi](../research/loop-engineering-and-pi.md), [gentle-ai extraction](../research/gentle-ai-productization-extraction.md)).
> **Objective:** one clear model of every primitive — what it is, when to use it — composing into a designed, self-evolving process loop that parallelizes, judges, challenges, and improves work on the go.

## 1. The primitives

| Primitive | What it is | Pros | Cons | Use for | brana today |
|---|---|---|---|---|---|
| **Rules** | Always-loaded prose constraints (CLAUDE.md, `rules/`) | Zero invocation cost; shape every decision | Token cost every session; **advisory** — model can ignore; cap ~200 lines effective | Conventions, invariants, vocabulary | 12+ rules (git-discipline, work-start…) |
| **Hooks** | Deterministic shell on lifecycle events (PreToolUse…) | **The only primitive that cannot be ignored**; can block, inject, gate | No intelligence; bash maintenance burden; brittle | Enforcement: gates, guards, secret scans, state sync | 40 hooks |
| **Skills** | On-demand procedures/knowledge loaded into current context | Progressive disclosure (no cost until invoked); encode the *way of working*; shareable | Same context, no isolation; depends on invocation discipline | Processes (build/close), domain knowledge | 35 skills |
| **Agents / subagents** | Isolated-context workers (`agents/*.md`: tools, model, effort, memory) | Context isolation; parallelism; per-agent model routing; native persistent memory | Handoff loss ("telephone game"); can't see conversation; ~15× token cost multi-agent | Exploration, review, focused deliverables | 14 agents (challenger, scout…) |
| **Forks** | Subagent that inherits full conversation context | No handoff loss; background execution | Same model as parent; still a new context after spawn | Side quests needing full session context | Used in research/challenge |
| **Teams** | Peer sessions with shared task list + SendMessage | Agents can *argue*, claim work, coordinate | Experimental; highest token cost | Competing hypotheses, cross-layer changes, persistent challenger | **Unused** |
| **Workflows** | Deterministic JS orchestration of many agents (pipeline/parallel/schema) | Deterministic control flow; scales to 1000 agents; state lives in script vars, not context | Upfront scripting; batch-shaped; no mid-flight steering | Fan-out, adversarial verify, judge panels, migrations, audits | challenge, hive-mind, sweep |
| **Loops** | Recurrence layer: `/loop`, ScheduleWakeup, cron, cloud Routines | Autonomy over time; heartbeat replaces manual prompting | Drifts without stop conditions + verifier; cost multiplies with cadence | Babysitting, overnight work, continuous processes | build-loop, `brana ops` (partially dead) |
| **Routers** | Decides *who/what* runs each unit: model tier, effort, agent, primitive | Cost/quality efficiency; right compute for the job | brana's is prose (advisory) — must be mechanized into config/profiles | Model-per-phase, delegation triage | delegation-routing.md, model-routing.md |
| **Memory** | Cross-session learning: native memory dir, agent `memory:` frontmatter, recall | The self-evolving property depends on it | Rots without curation; hand-rolled paths break (31 read fails) | Patterns, corrections, calibration | Layered but partly broken |
| **Orchestrator** | The composition layer: whoever decides which primitive to reach for | — | — | In target state this is **the loop itself**, not the human | Currently: the human + main session |

**Decision rubric** — first match wins:
must ALWAYS hold → **hook** (enforce) or **rule** (guide) · a way of working → **skill** · needs fresh context or parallelism → **agent** · many agents with structure → **workflow** · peers must argue → **team** · recurs over time → **loop/routine** · "which model/agent/effort?" → **router**.

## 2. The layer model

```
L6  ADAPTATION    memory · retrospective · pattern promotion   ← self-evolving
L5  TIME          loops · routines · wakeups                   ← autonomy
L4  ORCHESTRATION workflows (deterministic composition)        ← parallelize
L3  COMPUTE       agents · subagents · forks · teams           ← who thinks
L2  PROCESS       skills (the designed way of working)         ← on track
L1  ENFORCEMENT   hooks (cannot be ignored)                    ← rails
L0  CONSTITUTION  rules · CLAUDE.md                            ← invariants
──  cross-cutting: ROUTER (model/effort/primitive per unit of work)
```

Each layer leverages the ones below. The 2026 shift ("loop engineering", Cherny: *"loops prompt Claude now"*) is moving the human from operating L2–L4 by hand to designing L5–L6 and letting the loop operate the rest.

## 3. Target architecture: the self-evolving process loop

One iteration of the designed loop:

1. **HEARTBEAT** (L5) — `/loop` in-session or cloud Routine unattended fires the cycle.
2. **DECIDE** — `backlog next` picks the task from tasks.json (durable state keeps it on track across runs).
3. **ROUTE** (router) — classify: effort, strategy, model profile per phase (mechanized à la gentle-ai profiles, not prose).
4. **PROCESS** (L2) — the matching skill (build/fix/research) runs its phases; hooks (L1) gate every step (branch, TDD, secrets, spec-first).
5. **PARALLELIZE** (L4+L3) — phases fan out via Workflow: explore in parallel, candidate implementations, multi-lens review.
6. **JUDGE & CHALLENGE** — judge panel / challenger workflow scores candidates and improves the winner on the go; teams when reviewers must argue.
7. **VERIFY** (maker/checker) — an *independent small-model verifier* checks AC lines, not the worker. Encoded stop conditions: AC met · iteration cap · cost budget · non-recoverable error → escalate to human.
8. **CLOSE** — merge, state update, handoff.
9. **LEARN** (L6) — retrospective extracts patterns → memory writes → pattern promotion proposes rule/skill changes (human-gated) → **the process that runs the next iteration is better than the one that ran this one.**

### Gap between today and target (build order)

| # | Gap | Layer | Status today |
|---|---|---|---|
| 1 | Independent verifier + encoded stop conditions (iteration cap, cost budget) | L5/verify | Worker self-grades; goal-completion.sh checks goals only |
| 2 | Native subagent memory migration | L6 | Hand-rolled, failing (31 read errors) |
| 3 | Cloud Routines for the heartbeat + dead crons | L5 | Local cron, close-extraction dead |
| 4 | Router mechanization (per-phase model/effort profiles in build/fix) | router | Prose rules only |
| 5 | Feature-state JSON + session onboarding ritual for the runner | L5 | Handoff exists, no structured feature states |
| 6 | Learning loop wired INTO the loop (retrospective as a phase, not a manual skill) | L6 | Exists but human-invoked |
| 7 | Teams experiment: persistent challenger | L3 | Unused |

Items 1–3 make the loop *safe to run unattended*; 4–5 make it *efficient*; 6 makes it *self-evolving*; 7 makes judging *adversarial in real time*.
