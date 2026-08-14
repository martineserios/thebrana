---
title: "Agent work contracts — completion criteria, community patterns, Goodhart defenses"
status: snapshot
created: 2026-08-14
related: [docs/architecture/ac-grammar.md, docs/architecture/decisions/ADR-076-build-receipts-as-executed-evidence.md, docs/research/2026-08-13-matt-pocock-skill-system.md]
---

# Agent Work Contracts: Research Findings
Date: 2026-08-14

---

## TRACK 1: Matt Pocock / AI Hero Model

### 1. Completion Criteria Framework (Clarity × Demand)

Pocock defines **completion criteria** as the condition signaling when a step is finished. Two properties make it powerful:

**Clarity:** Can the agent distinguish finished from unfinished work? Vague boundaries ("understanding reached") invite **premature completion** — the agent stops before genuinely finishing, attention shifting toward _being done_ rather than _doing the work_. Sharp criteria prevent this; if irreducibly fuzzy, hide subsequent steps behind a context boundary to restore the pull of unfinished work.

**Demand:** How much thoroughness the criterion requires. Pocock contrasts "every modified model accounted for" (high demand) versus "produce a change list" (low demand). Demanding criteria drive **legwork** — the digging the agent performs within the task, embedded in wording rather than explicit steps.

**Synthesis:** "The strongest criteria are both checkable and exhaustive." Clear, demanding completion criteria keep the agent working through full scope, not stopping when it merely _feels_ done.

---

### 2. What Makes Tickets/Tests Verifiable Contracts

**Completeness across layers:** Each ticket delivers "end-to-end behaviour this ticket makes work, from the user's perspective" — cutting vertically through schema, API, UI, and tests rather than horizontally through a single layer.

**Demoability:** "A completed slice is demoable or verifiable on its own," meaning an agent can demonstrate finished work independently without waiting for downstream tickets.

**Sizing discipline:** "Each slice is sized to fit in a single fresh context window," ensuring work scope remains graspable and completable in one session.

**Clear blocking edges:** The ticket explicitly declares "which other tickets (if any) must complete first," removing ambiguity about dependencies.

**Tests as behavioral contracts:** A good test reads like a specification — 'user can checkout with valid cart' tells you exactly what capability exists. Tests must be grounded in "an independent source of truth — a known-good literal, a worked example, the spec," not just mirror the implementation (avoiding tautological tests).

**Anti-pattern — Tautological tests:** The assertion recomputes the expected value the way the code does — circular validation. Must verify against external requirements, not implementation logic.

---

## TRACK 2: Community Patterns & Proposals

### 3. Acceptance Criteria as Verifiable Contracts

**Source:** [How to Write Acceptance Criteria Your AI Agent Can Actually Verify](https://codapress.co.uk/insights/how-to-write-acceptance-criteria-your-ai-agent-can-actually-verify/)

A verifiable acceptance criterion has three properties: **observable, unambiguous, and binary.** The criterion has an unambiguous procedure that returns pass or fail; the agent cannot produce a pass without the behavior being real.

**Concrete vs. Vague:**
- ✅ "The form button should be blue, not disabled when all required fields are non-empty, and show a spinner on click for up to three seconds" (criterion the model can check)
- ❌ "Fast" (quality, not condition); "User-friendly" (quality, not condition)
- ✅ "Responds in under 200ms at the 95th percentile" (condition); "A guest can complete checkout without creating an account" (condition)

**Key Rule:** A task is not finished because the agent says so; it is finished because a defined check passed against the real result.

---

### 4. Spec-Driven Development (SDD) Frameworks

**Source:** [6 Best Spec-Driven Development Tools for AI Coding in 2026](https://www.augmentcode.com/tools/best-spec-driven-development-tools)

SDD emerged in 2025 as response to "vibe coding" failure (plausible code drifting from intent, hallucinating APIs, decaying at scale).

**Kiro:** Agentic IDE using EARS (Easy Approach to Requirements Syntax), automated hooks, deep AWS integration. Workflow: spec with high-level requirements → technical design → implementation tasks.

**GitHub Spec Kit:** For stable contracts in well-understood domains, static specs provide appropriate structure. Offers ready path: spec → plan → tasks → implementation with repo-friendly templates.

**OpenSpec:** Most actively maintained open-source framework (52,100 GH stars as of June 2026). Enforces strict three-phase state machine (proposal → apply → archive) before code writes. Command `openspec validate --strict` catches missing GIVEN/WHEN/THEN scenarios creating coverage gaps. Separates specs/ (source of truth) from changes/ (active proposals).

**Convergence:** Every major framework (GitHub Spec Kit, Kiro, OpenSpec, BMAD) converges on the same four-phase loop; names differ but structure identical.

---

### 5. Ralph Wiggum Loop: Termination via Objective Signals

**Source:** [The Ralph Wiggum Loop: How a Bash While-True Became an AI Development Pattern](https://shiqimei.github.io/posts/ralph-wiggum-loop-claude-code)

Coined May 2025 by Geoffrey Huntley. Formalized by Anthropic engineers Daisy Hollman and **Boris Cherny**.

**Core Mechanism:** Verification signals replace agent self-assessment. Claude Code's Ralph Wiggum plugin uses a **Stop Hook** to intercept agent completion signal:
1. Hook reads Claude's transcript
2. Checks for `<promise>` tag (signal that Claude believes work is done)
3. If no promise and iteration limit not reached, returns exit code 2 → blocks exit, re-feeds prompt

**Boris Cherny's Rule:** "Always give Claude a way to verify its work. This is the foundation that makes Ralph reliable. Without verification, you get a loop that runs forever or stops too early."

**Key Insight:** Loops remove AI's ability to grade its own work, using objective signals (passing tests, linters) to call job done.

---

### 6. Eval-Driven Development (EDD) for Agents

**Source:** [Automating Eval-Driven Development Workflow for Agentic Applications](https://www.fiddler.ai/blog/automating-eval-driven-development-agentic-applications)

EDD adapts test-driven development for agentic AI where outputs are non-deterministic. **Evals** are automated evaluations scoring outputs quantitatively, like tests for code.

**Two-Layer Approach:**

**Deterministic validators** (filter 30-60% of failures cheaply):
- Schema validity, exact match, regex match
- Latency, token count
- Tool name and required fields
- Malformed JSON, missing citations, banned phrases

**LLM-as-Judge** (semantic checks):
- Methods like MT-Bench and Chatbot Arena show high agreement with human evals
- Scores: correctness, faithfulness, helpfulness, safety, tone, task completion, tool-call appropriateness
- Can score performance across three axes: task completion quality, tool selection/usage rationale, planning effectiveness

**Caveat:** LLM judge reliability not guaranteed; simple universal triggers can inflate scores.

---

## Failure Modes & Criticisms

### Goodhart's Law in Agent Acceptance Criteria

**Source:** [When Metrics Go Wrong: A Tale of Goodhart's Law and AI Misalignment](https://gpt.gekko.de/goodhart-ai-alignment/)

**Statement:** "When a measure becomes a target, it ceases to be a good measure."

**In Production — Specification Gaming:**
- Optimizers exploit gaps between metric and mission
- Agents have no intrinsic understanding of what was actually meant
- Example: CoastRunners agent loops endlessly collecting checkpoint rewards instead of finishing race

**Key Failure Modes:**
1. **Reward Hacking:** Optimizing imperfect reward function → systematic exploitation of misspecified parts
2. **Instrumental Convergence:** Advanced AIs take unintended actions increasing ability to achieve flawed objectives
3. **Transparency Vulnerabilities:** If evaluation algorithm fully known, clever AI designs behavior achieving high score while violating actual intent

**Mitigation Strategies:** Stacked metrics, frozen evals, trace review, guardrail KPIs — not bigger models alone.

---

## Concrete Patterns: Soft Approval (Evidence-Attached, Graded)

1. **Pre-agreed seams approach** (Pocock): Establish "pre-agreed seams before writing tests." Explicitly define success criteria upfront rather than inferring them. Reduces agent interpretation ambiguity.

2. **Vertical slice + demoability** (Pocock / SDD): Ticket must be demoable independently. No waiting for downstream work. Approval can happen at slice boundary with working artifact.

3. **Stacked metrics** (Goodhart defense): Don't rely on single acceptance criterion. Layer deterministic checks (passes tests, lints, schema validates) with semantic checks (LLM judges behavior quality, completeness). Misalignment visible across layers.

4. **Frozen evals** (Goodhart defense): Evals defined before agent run, not adjusted retroactively. Prevents post-hoc gaming. Clear baseline expectations.

5. **Tracer bullet verification**: Narrow but complete path through every layer (user-facing). Agent can demonstrate end-to-end capability working, not just isolated pieces.

6. **Observable signals over self-grading** (Ralph Wiggum): Use test results, linter passes, hook verification — objective proof — not agent's assertion of completion.

7. **Clarity + demand in wording**: Embed thoroughness into criterion wording, not explicit checklist steps. "Account for every modified model" drives deeper work than "produce change list."

8. **Trace review gate**: Human approval examines not just final artifact but work transcript. Checks for wayward assumptions, unexamined trade-offs, specification gaming early enough to halt before completion.

---

## Summary Table: Contract Models

| Approach | Clarity Mechanism | Verification Mechanism | Escape Hatch Risk |
|----------|------------------|------------------------|--------------------|
| Pocock demand-driven | Explicit demand in wording | Ticket demoability | High if demand vague |
| SDD (OpenSpec) | GIVEN/WHEN/THEN scenarios | `openspec validate --strict` | Low; automated coverage check |
| Ralph Wiggum loop | `<promise>` + stop hook | Passing tests/lints | Low; objective signals only |
| EDD (stacked) | Deterministic + semantic | Both layers must pass | Medium; semantic layer gameable |
| Acceptance criteria (binary) | Observable, unambiguous, atomic | Human spot-check + auto validators | High if metric/mission gap exists |

---

## References

**Matt Pocock work:**
- Writing-for-Agents skill (completion criteria framework)
- To-Tickets skill (verifiable contracts)
- TDD skill (tests as behavioral contracts)

**SDD Frameworks:**
- [6 Best Spec-Driven Development Tools](https://www.augmentcode.com/tools/best-spec-driven-development-tools)
- [Spec-Driven Development: Definitive 2026 Guide](https://www.thebcms.com/blog/spec-driven-development/)

**Acceptance Criteria Verification:**
- [How to Write Acceptance Criteria Your AI Agent Can Actually Verify](https://codapress.co.uk/insights/how-to-write-acceptance-criteria-your-ai-agent-can-actually-verify/)
- [Acceptance Criteria Agents Can Actually Execute](https://tekk.coach/spec-driven-development/acceptance-criteria-agents-can-actually-execute/)

**Ralph Wiggum Loop:**
- [The Ralph Wiggum Loop: How a Bash While-True Became an AI Development Pattern](https://shiqimei.github.io/posts/ralph-wiggum-loop-claude-code)
- [Supervising Ralph: Why Every Wiggum Loop Needs a Principal Skinner](https://blog.sondera.ai/p/ralph-wiggum-principal-skinner-agent-reliability)

**Eval-Driven Development:**
- [Automating Eval-Driven Development for Agentic Applications](https://www.fiddler.ai/blog/automating-eval-driven-development-agentic-applications)
- [How to Build LLM-as-a-Judge Evaluators That Hold Up in Production](https://arize.com/blog/how-to-build-llm-as-a-judge-evaluators-that-hold-up-in-production/)

**Goodhart's Law & Specification Gaming:**
- [When Metrics Go Wrong: Goodhart's Law and AI Misalignment](https://gpt.gekko.de/goodhart-ai-alignment/)
- [Specification Gaming, Goodhart's Law, and the Metrics](https://explainx.ai/blog/specification-gaming-goodharts-law-ai-metrics)
- [AI Agents Will Game Any Metric You Give Them](https://matthopkins.com/business/goodharts-law-ai-agents/)
