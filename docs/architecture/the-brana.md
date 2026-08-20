# The Brana

**Status:** draft (cover locked; body fills in as [the-brana-guide.md](../ideas/the-brana-guide.md) walk L1–L6 settles) · **Owner:** Martín Rios
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

Full chapter content and the component map fill in as [the-brana-guide.md](../ideas/the-brana-guide.md)'s walk (L1 → L6) settles, one node at a time. The vocabulary table below is this page's canonical copy — [glossary.md](glossary.md) points here rather than duplicating it (see L0's one-owner-per-concept rule).

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

| Primitive | What it is | Home chapter |
|---|---|---|
| **Task** (Agent tool) | One subagent, in-session, dies with session. | Cycle — one ACT |
| **Workflow** | Deterministic JS fan-out; a graph, as code, run once. | Cycle — open string |
| **/loop** + `claude -p` | Detached iteration over a queue; a graph, as data, walked over time. | Cycle — closed string |
| **/goal** | Iterates within one gate-free span until a done-signal (ADR-061's third motion — ITERATE, distinct from `/loop`'s POLL and `Workflow`'s FAN-OUT). | Cycle |
| **ruflo memory / recall** | Persistent, cross-session shared store. | Cycle — what a loop carries (gravity-leak) |
| **Skills** | Playbooks a station loads. | Space — sits above this stack, not in it |

Composed blocks (Layer 1, `.claude/workflows/`) — each a `Workflow` script combining Layer-0 primitives: **hive-mind** (diverse answers → verify → synthesize), **sweep** (diverse finders → dedup → verify), **verify-findings** (the canonical judge panel, called by both). Invoked by Layer-2 skills (`/brana:challenge --deep`, `/code-review ultra`, brainstorm evaluate) — an agent deciding on its own a task "would benefit" does not count as invocation.

**Open:** where hooks (PreToolUse, SessionStart, …) belong isn't resolved — not in `substrate-primitives.md`'s set at all, and it doesn't cleanly fit Cycle's motion-primitives. Reads more like Gate (an automatic, non-human check) or connective tissue spanning all four chapters. Tracked at [the-brana-guide.md](../ideas/the-brana-guide.md) L2.1.

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
| **Ring** | One level of the Scale axis: micro / beat / epic / knowledge. | this page |
| **Seven-step skeleton** | A ring's loop shape: ORIENT→SELECT→ACT→MEASURE→JUDGE→ASSIMILATE→RESTART; plain gloss = context→action→feedback. | [60-agent-loop-architecture.md](../../../brana-knowledge/dimensions/60-agent-loop-architecture.md) |
| **Wave** | The human's unit of work — a batch of tasks pulled and shipped together. | [ADR-079](decisions/ADR-079-backlog-drain-loop-handoff.md), [ADR-080](decisions/ADR-080-plan-time-wave-graphs-epic-runner.md) |
| **Task** | The agent's unit of work. | [ADR-002](decisions/ADR-002-tasks-as-data-layer.md) |
| **Beat** | One pass through a ring's loop; produces a beat record. | [features/loops-library.md](features/loops-library.md) |

**Gate**

| Term | One-line | Owner |
|---|---|---|
| **Valve** | A human gate, placed by reversibility. | this page (absorbing [drained/wave-pipeline.md](../ideas/drained/wave-pipeline.md)) |
| **Studio** | The room for slow, high-thinking design work. | [drained/wave-pipeline.md](../ideas/drained/wave-pipeline.md) §two rooms |
| **Cockpit** | The room for fast, low-thinking approvals. | [drained/wave-pipeline.md](../ideas/drained/wave-pipeline.md) §two rooms |
| **Judge** | The machine or panel that owns a reversible-outcome decision. | [ADR-082](decisions/ADR-082-multi-agent-sizing-function.md) |
| **Autonomy rung** | L1 report-only / L2 assisted / L3 unattended — gated by AC coverage ("Non-AC fallback: stays L2"). *Not* this guide's L0–L6 walk levels — same letter, different axis. | [drained/brana-v3-redesign.md](../ideas/drained/brana-v3-redesign.md) §graduated autonomy ladder |
| **AC** | Machine-checkable definition of done; gates `/goal` and L3 eligibility. | [ADR-047](decisions/ADR-047-acceptance-criteria-schema.md), [ac-grammar.md](ac-grammar.md) |

**Scale**

| Term | One-line | Owner |
|---|---|---|
| **KK tower** | One brane-concept, instantiated differently at each ring. | [brana-etymology-naming.md](../../../brana-knowledge/dimensions/brana-etymology-naming.md) |
| **Compactification radius** | A ring's "size" — small = fast, large = slow. | [60-agent-loop-architecture.md](../../../brana-knowledge/dimensions/60-agent-loop-architecture.md) |
| **Low-pass filter** | The human's relationship to ring frequency — only slow rings reach them directly. | [drained/wave-pipeline.md](../ideas/drained/wave-pipeline.md) §Spectrum |
| **Inhabitant** | The human's role: lives in Cycle, decides at Gate, senses via memory. | memory `user_creative-vs-operative-modes` |
| **Orbit / Orbit** | Plain word inside Cycle now; capital-O = a future satellite component, on evidence. | [ADR-068](decisions/ADR-068-v3-supersession.md), [features/autonomous-runner.md](features/autonomous-runner.md) |

## Reading map

Read this page first. For how work actually flows through the system day to day, go to [Idea → Ship: The Skill Flow](idea-to-ship.md). For the studio's living, in-progress draft of everything below this line — including every open question and its refs — see [the-brana-guide.md](../ideas/the-brana-guide.md).
