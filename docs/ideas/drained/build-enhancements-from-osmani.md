# Build Command Enhancements — Inspired by addyosmani/agent-skills

> Analysis date: 2026-04-13. Source: github.com/addyosmani/agent-skills skills: incremental-implementation, spec-driven-development, test-driven-development.
> Challenger review: 2026-04-13. Status: **3 approved, 2 rejected (already exist), 1 rerouted**.
>
> **Approved:** Testing Strategy in spec (narrowed), Boundaries in spec (low priority), Assumptions rule (needs rule file companion)
> **Rejected:** Prove-It Pattern (already in build.md lines 719-761 + tdd-gate.sh), Slicing strategies (already in DECOMPOSE gate lines 563-573)
> **Rerouted:** Living Spec / Change Log conflicts with frozen Decision Record — route to task notes + CLOSE step 4c instead

## Architectural Comparison

| Dimension | Osmani | Brana |
|---|---|---|
| Entry point | 7 slash commands (`/spec`, `/plan`, `/build`, `/test`, `/review`, `/code-simplify`, `/ship`) | `/brana:build` unified + `/brana:backlog start` |
| Strategy detection | Manual (`/spec` then `/build`) | Auto-classify: 7 strategies (feature, bug-fix, greenfield, refactor, spike, migration, investigation) |
| Phase structure | Specify → Plan → Tasks → Implement (sequential, human-reviewed gates) | LOAD → CLASSIFY → APPROVE → SPECIFY → DECOMPOSE → BUILD → CLOSE |
| Spec content | 6 areas: Objective, Commands, Project Structure, Code Style, Testing Strategy, Boundaries | Problem, Decision Record, Constraints, Scope, Research, Design, Documentation Plan, Challenger findings |
| Slicing | Explicit: Vertical (preferred), Contract-First, Risk-First | Implicit: task tree via DECOMPOSE, no slicing guidance within tasks |
| TDD | RED → GREEN → REFACTOR + "Prove-It Pattern" | Red-green-refactor enforced by lifecycle gate |
| Memory | Stateless — no cross-session carry-over | ruflo MCP, knowledge pipeline, checkpointing, resume-from-state |
| Challenger | None | `challenger` agent reviews every feature spec |
| Enforcement | Prose (rationalizations + verification checklists) | Hooks (stop gates), rules, lifecycle gate |

**Brana's structural advantages:** auto-classification, challenger review, cross-session checkpointing, task-tree decomposition, ruflo memory across sessions.  
**Osmani's prose advantages:** explicit slicing strategies, stronger per-step behavioral discipline, named bug-fix TDD pattern, Testing Strategy as a first-class spec section.

---

## Enhancement 1: Explicit Slicing Strategies in BUILD

### What Osmani has

`incremental-implementation` names three slicing strategies:
- **Vertical slices** (preferred) — one complete path through the stack. Frontend → API → DB → test → commit. System always works after each slice.
- **Contract-First slicing** — define the interface first, implement both sides to the contract. For integrations, API design, protocol work.
- **Risk-First slicing** — implement the riskiest/most uncertain part first. Proves feasibility early, avoids discovering blockers late.

The increment cycle is explicit:
```
Implement → Test → Verify → Commit → Next slice
```

Each commit: tests pass, build succeeds, type checking passes, linting passes, descriptive message.

### The gap in brana

Brana's DECOMPOSE step creates a task tree (phase/milestone/task/subtask). But within each task, there is **no guidance on how to slice the work**. The BUILD step goes directly to code with TDD, but doesn't teach the agent how to choose a slicing approach for the task.

This means agents may default to horizontal slicing (implement all DB, then all API, then all frontend) — which delays the first working state.

### Proposal

Add a **SLICE** sub-step to BUILD (between DECOMPOSE and the first Edit call):

```markdown
## SLICE sub-step (runs before first code edit)

For any task with more than one file to change, choose a slicing strategy:

| Strategy | Use when |
|---|---|
| **Vertical** (default) | New feature, unclear path, want to stay shippable throughout |
| **Contract-First** | Integration work, API design, two sides of a protocol |
| **Risk-First** | Uncertain feasibility, new tech, architectural risk |

State the chosen strategy and the first slice explicitly:
"Slicing strategy: Vertical. First slice: {description of smallest working unit}."

Commit after each slice passes its tests. Never accumulate uncommitted working code.
```

### Effort / Value
- Effort: **S** (prose addition to BUILD step in `system/procedures/build.md`)
- Value: **HIGH** — prevents horizontal slicing anti-pattern, keeps system working throughout
- Complements existing TDD enforcement (now also guides *what* to implement in which order)

---

## Enhancement 2: "Prove-It Pattern" for Bug Fix TDD

### What Osmani has

`test-driven-development` names this explicitly:

> **The Prove-It Pattern:** Before fixing any bug, write a failing test that reproduces it. The test is your proof that (a) the bug existed and (b) the fix works. Fix the bug. Watch the test turn green. Then refactor if needed.

This is standard TDD for bugs, but naming it and requiring it as a **first step** before touching production code makes it non-skippable.

### The gap in brana

Brana's bug-fix strategy has: REPRODUCE → DIAGNOSE → FIX → CLOSE. The REPRODUCE step involves manual verification steps but doesn't **require an automated failing test** before moving to DIAGNOSE. An agent can claim "reproduced it" via logs or observation, then jump to FIX without a test.

### Proposal

Add the Prove-It Pattern as a named, mandatory step in the BUG FIX strategy:

```markdown
### PROVE-IT (mandatory — runs before DIAGNOSE)

Write a failing test that reproduces the bug before touching production code.
This is not optional even for "obvious" fixes.

1. Identify the smallest reproducible case
2. Write the test — it must fail on the current code
3. Run it — confirm it fails with the expected error (not a different error)
4. Only then proceed to DIAGNOSE

Anti-rationalization: "The fix is obvious, I don't need a test."
→ If the fix is obvious, the test takes 2 minutes. If you skip the test and the bug returns, you have no detector.
```

### Effort / Value
- Effort: **S** (addition to bug-fix strategy section in `build.md`)
- Value: **HIGH** — closes the most common TDD compliance gap (manual REPRODUCE that never becomes a test)

---

## Enhancement 3: Testing Strategy as First-Class Spec Section

### What Osmani has

Every feature spec includes a `Testing Strategy` section as one of six core areas. It answers:
- What test types apply (unit / integration / E2E)?
- What is the test pyramid proportion for this feature?
- Which behaviors are unit-testable vs require integration?
- What mocking strategy? (Osmani's order: Real > Fake > Stub > Mock)

This forces testing decisions to be made at **spec time**, not implementation time.

### The gap in brana

Brana's feature spec template has a `Documentation Plan` (which tests to write is part of the build, not the spec). The lifecycle gate at APPROVE checks *whether* TDD applies, but there's no structured space in the spec to decide *how* to test the feature.

Agents often delay testing decisions until they're mid-implementation, which leads to retrofitted tests and weaker coverage.

### Proposal

Add `## Testing Strategy` to brana's feature spec template in SPECIFY:

```markdown
## Testing Strategy

**Test pyramid for this feature:**
- Unit: {what to unit test — pure logic, transformations, edge cases}
- Integration: {what requires multiple components — CLI + DB, skill + hook}
- E2E: {what to test end-to-end — user-visible workflows}

**Mock policy:** prefer real implementations. Use fakes (lightweight in-memory) before stubs. Use mocks only when external systems are unavailable in CI.

**Test-first commitment:** list the test file(s) to write before implementation:
- `{test file path}` — tests `{what behavior}`
```

### Effort / Value
- Effort: **S** (spec template addition to SPECIFY in `build.md`)
- Value: **MEDIUM** — shifts testing decisions earlier, prevents retrofitting

---

## Enhancement 4: Boundaries Section in Feature Spec

### What Osmani has

Every spec includes a `Boundaries` section with three decision tiers:
- **Always do** — non-negotiable behaviors (security, data integrity, logging)
- **Ask first** — requires human approval before acting (destructive ops, external API calls, schema changes)
- **Never do** — hard limits (write to prod without a test, skip error handling, remove migrations)

This prevents scope creep and clarifies authority. The agent knows exactly when it can proceed autonomously vs. when it must pause.

### The gap in brana

Brana's feature spec has `Constraints` (a flat list) and relies on global rules + hooks for behavioral limits. There is no **per-feature authority map** — which specific operations for *this feature* are autonomous vs. need approval.

This matters especially for high-stakes work (CLI commands, hook changes, schema migrations) where the blast radius of an incorrect autonomous decision is large.

### Proposal

Add `## Boundaries` to brana's feature spec template:

```markdown
## Boundaries

**Always (autonomous):**
- {operations safe to execute without asking — read-only, reversible, test-only}

**Ask first (requires approval):**
- {operations that need confirmation — file deletes, schema changes, external API calls, main branch pushes}

**Never (hard limit):**
- {operations off-limits for this feature — e.g., "never modify unrelated files", "never skip the migration rollback plan"}
```

### Effort / Value
- Effort: **S** (spec template addition to SPECIFY in `build.md`)
- Value: **MEDIUM** — per-feature authority clarity, especially useful for M+ tasks

---

## Enhancement 5: "Don't silently fill in ambiguous requirements"

### What Osmani has

`spec-driven-development` makes this explicit as a critical practice:

> **Surface assumptions before drafting.** If the requirements are ambiguous, ask before writing code. Don't silently interpret ambiguity as permission to choose. Document every assumption in the spec as an explicit assumption.

### The gap in brana

Brana's SPECIFY step has a research → discuss → draft signal loop that invites discussion. But there is no **explicit rule** against silently resolving ambiguity. The lifecycle gate checks whether SDD applies but doesn't state the "no silent fill-in" constraint.

Agents under time pressure (or after a user says "draft it") will silently fill ambiguities to keep moving.

### Proposal

Add as a named rule in SPECIFY and as an anti-rationalization in BUILD:

**In SPECIFY header:**
```
Rule: Surface ambiguities before drafting. If a requirement can be interpreted two ways, ask — don't pick. 
Document every assumption in the spec under ## Assumptions.
```

**Add `## Assumptions` to spec template:**
```markdown
## Assumptions

Explicit decisions made due to ambiguity in the requirements:
- {assumption}: chose {decision} because {reason} — needs user confirmation
```

**Anti-rationalization:**
> "I can figure out what was meant."  
> → The user knows their intent. You don't. One question saves a full re-spec.

### Effort / Value
- Effort: **S** (rule in SPECIFY + Assumptions section in spec template)
- Value: **MEDIUM** — high leverage when requirements are inherently ambiguous (new features, client work)

---

## Enhancement 6: Living Spec Principle

### What Osmani has

> A spec is a **living document**. When decisions change, scope shifts, or new constraints appear — update the spec before updating the code. The spec is the source of truth, not the code.

Osmani commits the spec to version control and treats it as the canonical record.

### The gap in brana

Brana writes feature specs to `docs/architecture/features/{slug}.md` and has a Decision Record section marked "frozen." The frozen Decision Record captures the initial decision but there is no explicit protocol for **updating the living parts of the spec when scope changes mid-implementation**. Agents sometimes update code without updating the spec.

### Proposal

Add to the feature spec template:

```markdown
## Change Log

| Date | What changed | Why |
|------|-------------|-----|
| YYYY-MM-DD | Initial spec | — |
```

And add a rule to BUILD (in the mid-stream section):

```
When scope, constraints, or decisions change mid-build:
1. Update the spec first (Problem, Constraints, Scope, Design sections)
2. Log the change in ## Change Log
3. Then update the code
Never let the code run ahead of the spec.
```

### Effort / Value
- Effort: **S** (Change Log table in spec template + rule in BUILD)
- Value: **LOW–MEDIUM** — useful for multi-session M+ builds

---

## Post-Challenger Priority Order

| Enhancement | Status | Effort | Notes |
|---|---|---|---|
| Prove-It Pattern | **REJECTED — already exists** | — | build.md lines 719-761 + tdd-gate.sh already enforce this |
| Slicing strategies | **REJECTED — already exists** | — | DECOMPOSE gate (lines 563-573) already imposes slicing discipline; importing Osmani labels creates jargon drift |
| Testing Strategy in spec | **APPROVED (narrowed)** | S | Add pyramid layer + policy per layer only; NO filename list (filenames go in subtask descriptions, not spec) |
| Boundaries section | **APPROVED (low priority)** | S | Useful for greenfield/high-stakes; harmless elsewhere |
| Assumptions rule | **APPROVED (with companion)** | S | Must add to a rule file, not just procedure prose — prose-only compliance rate is poor |
| Living Spec / Change Log | **REROUTED** | — | Conflicts with frozen Decision Record; route to `brana backlog set {id} notes --append` + CLOSE step 4c |

### Implementation notes

- **Build.md is already 16,923 tokens** (exceeds read-limit threshold). New sections must go near the top of their strategy blocks, not appended — tail content is first to be dropped by context compression.
- **Assumptions rule companion:** create `system/rules/spec-assumptions.md` alongside the procedure addition. Rules load once and apply everywhere; procedures are only read at invocation.
- **Slicing jargon:** if slicing guidance is ever added, use brana's existing terms ("ordered tasks," "dependency graph," "acceptance criteria") — not "Vertical/Contract-First/Risk-First."

---

## What NOT to copy

- **Manual `/spec` → `/plan` → `/build` command sequence** — brana's unified `/brana:build` with auto-classification is strictly better. Don't fragment the entry point.
- **No memory design** — Osmani's stateless model is a constraint, not a feature. Brana's ruflo layer is the key differentiator for compounding improvement.
- **Skills-only enforcement** — brana's hooks provide mechanical stop-gate enforcement. Prose-only enforcement (Osmani's approach) is soft. Brana should keep hooks AND add prose as a second layer (defense in depth).

---

## Sources

- https://github.com/addyosmani/agent-skills/blob/main/skills/incremental-implementation/SKILL.md
- https://github.com/addyosmani/agent-skills/blob/main/skills/spec-driven-development/SKILL.md
- https://github.com/addyosmani/agent-skills/blob/main/skills/test-driven-development/SKILL.md
- Brana build procedure: `system/procedures/build.md`
