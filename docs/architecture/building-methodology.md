# Building Methodology: First-Principles Development for AI Tooling

How brana builds things. A combined top-down + bottom-up approach that produces systems grounded in research and validated by real usage.

---

## Core Premise

AI tooling changes faster than documentation can track. Frameworks shift monthly. Best practices from six months ago become anti-patterns. Building on tutorials and borrowed patterns means building on sand.

First-principles development inverts this: start from the problem, research deeply, synthesize across domains, then build. The result is architecture derived from understanding, not imitation.

---

## The Brana Cycle

Four phases form a continuous loop. Each phase produces artifacts that feed the next:

```
Dimension → Reflection → Roadmap → Execution
(research)   (synthesis)   (plan)     (build)
    ↑                                    │
    └────────────────────────────────────┘
                 (feedback)
```

### 1. Dimension — Research in Depth

A dimension doc explores one topic exhaustively. It reads primary sources, compares approaches, extracts principles, and documents trade-offs. No opinions about what to build — just what exists and why.

**Output:** `brana-knowledge/dimensions/NN-topic.md`
**Staleness:** 180 days (research is durable)

### 2. Reflection — Cross-Cutting Synthesis

A reflection reads multiple dimensions and synthesizes them into architectural insight. It connects dots that individual dimensions can't see alone. Reflections are opinionated — they take positions.

**Output:** `docs/reflections/NN-topic.md`
**Staleness:** 90 days (architecture decisions are moderately stable)

The reflection DAG ensures synthesis builds on synthesis:
```
R1(Triage) → R2(Architecture) → R3(Assurance) / R4(Lifecycle) → R5(Venture)
```

### 3. Roadmap — Actionable Plan

Roadmap docs translate reflections into sequenced work items. Precise enough to execute, scoped enough to complete. Each item traces back to the reflection that justified it.

**Output:** `docs/NN-roadmap.md`
**Staleness:** 30 days (implementation details change fast)

### 4. Execution — Build and Test

Implementation follows the DDD → SDD → TDD workflow (see [32-lifecycle.md](../reflections/32-lifecycle.md)):

1. **DDD** — Model the domain. Bounded contexts, ubiquitous language. "What are we building?"
2. **SDD** — Decide the approach. ADRs, contracts. "How are we building it?"
3. **TDD** — Specify behavior. Failing tests before code. "Does it work?"

**Output:** Working code, tests, updated specs

---

## Two Directions

### Top-Down: Principles → Architecture

Start with research. Derive constraints. Design the system. Then build.

**When to use:**
- New capability with no existing precedent in the codebase
- Architectural decisions that affect multiple components
- The problem space is unfamiliar

**The sequence:**
1. Research the domain (dimension doc or `/brana:research`)
2. Synthesize with existing architecture (reflection update)
3. Plan the work (roadmap item)
4. Implement with spec-first discipline (ADR → test → code)

**Strength:** Avoids building the wrong thing. Decisions have documented rationale.
**Risk:** Analysis paralysis. Mitigated by timeboxing research to one session.

### Bottom-Up: Usage → Patterns

Start with real usage. Notice what works. Extract the pattern. Formalize it.

**When to use:**
- Improving something that already exists
- The user keeps doing something manually (graduation candidate)
- A bug or friction point reveals a missing abstraction

**The sequence:**
1. Observe the pattern in practice (field notes in [00-user-practices.md](../00-user-practices.md))
2. Confirm it recurs (3+ occurrences)
3. Extract and formalize (convention → skill → hook)
4. Update specs to reflect the new reality

**Strength:** Grounded in real need. No speculative architecture.
**Risk:** Local optimization. Mitigated by checking against reflections before formalizing.

### The Graduation Pathway

Bottom-up patterns follow a reliability gradient:

```
Manual practice → Convention (rules/) → Workflow (skill) → Enforcement (hook)
```

Each level is harder to set up but more reliable. Start manual, graduate upward based on pain signals.

---

## The Feedback Loop

Execution findings flow back to dimensions. This is what keeps the system alive.

```
Build something → discover a gap → update dimension → re-synthesize reflection → adjust roadmap
```

Concretely:
- `/brana:close` extracts session learnings
- `/brana:maintain-specs` cascades changes: dimension → reflection → roadmap
- Implementation that changes behavior updates docs in the same commit

Without feedback, specs drift from reality with every session. The debrief → maintain-specs loop is the immune system against spec rot.

---

## Practical Workflow

A typical feature from start to finish:

```bash
# 1. Research (if domain is unfamiliar)
/brana:research [topic]              # produces/updates dimension doc

# 2. Plan
/brana:backlog add                   # create task with strategy classification
/brana:backlog pick                  # enters /brana:build automatically

# 3. Build (inside /brana:build)
# SPECIFY: ADR via /decide, domain model if needed
# PLAN: break into steps, identify risks
# BUILD: TDD — failing test → implementation → green
# CLOSE: debrief, update specs, merge

# 4. Maintain
/brana:maintain-specs                # cascade any spec changes
```

For bug fixes and small improvements, skip research — go straight to `/brana:build` with strategy `bug-fix` or `refactor`.

---

## Anti-Patterns

### Building Without Research

Jumping to code without understanding the domain. Symptoms:
- Reimplementing what a library already does
- Architecture that fights the problem instead of modeling it
- Repeated rework as assumptions prove wrong

**Fix:** One dimension doc (even brief) before architectural decisions. Timebox to one session if urgency demands it.

### Research Without Building

Endless dimension docs that never become code. Symptoms:
- Reflections that reference each other but produce no roadmap items
- Research that answers questions nobody asked
- Specs that are always "not quite ready"

**Fix:** Every reflection must produce at least one actionable roadmap item. Research without a build target is a hobby, not engineering.

### Skipping the Feedback Loop

Building correctly but never updating specs. Symptoms:
- Dimension docs that describe a system from three months ago
- ADRs whose "consequences" section never got validated
- New team members reading specs that don't match the code

**Fix:** Run `/brana:maintain-specs` after every implementation session that changed behavior. Make it part of the merge checklist.

### Over-Graduating

Turning every observation into a hook or enforcement gate. Symptoms:
- Hooks that fire on every tool call for edge cases
- Rules that constrain without justification
- Convention fatigue — too many rules to remember

**Fix:** The 3+ recurrence threshold exists for a reason. Not everything deserves enforcement. Some things are fine as conventions.

---

## Cross-References

- [32-lifecycle.md](../reflections/32-lifecycle.md) — DDD → SDD → TDD workflow, maintenance cadences, graduation pathway
- [14-mastermind-architecture.md](../reflections/14-mastermind-architecture.md) — three-layer architecture, enforcement hierarchy
- [31-assurance.md](../reflections/31-assurance.md) — how to verify the methodology produces results
- [00-user-practices.md](../00-user-practices.md) — field notes that feed bottom-up pattern extraction
