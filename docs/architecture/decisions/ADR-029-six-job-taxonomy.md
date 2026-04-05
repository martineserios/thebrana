---
depends_on:
  - docs/architecture/features/operating-model.md
informs:
  - docs/architecture/decisions/ADR-032-smart-router.md
  - docs/architecture/decisions/ADR-030-maintenance-unification.md
---

# ADR-029: 6-Job Taxonomy

**Date:** 2026-04-04
**Status:** accepted
**Tasks:** t-898
**Source:** Operating model §1

## Context

Brana has 35 skills and growing. Users (and the system itself) struggle to answer "what skill do I need?" because skills are organized by implementation, not by intent. There's no organizational model mapping operator activities to higher-level jobs.

The operating model research found that everything a solo operator does falls into 6 jobs. This taxonomy provides the missing organizational layer: skills implement jobs, not the other way around.

## Decision

Adopt a 6-job taxonomy as the organizational model for all brana activities. Auto-learning is a **property** embedded in thinking-jobs, not a separate job.

### The 6 Jobs

| Job | Question | Key Skills |
|-----|----------|-----------|
| **DECIDE** | "What should I work on?" | `/brana:backlog`, `/brana:brainstorm` |
| **UNDERSTAND** | "What do I need to know?" | `/brana:research`, `/brana:onboard` |
| **BUILD** | "Make the thing" | `/brana:build` |
| **SHIP** | "Get it to users" | (proposed: `/brana:ship`) |
| **MAINTAIN** | "Keep it healthy" | `/brana:reconcile` (expanded) |
| **GROW** | "Build the business" | `/brana:review`, `/brana:harvest` |

Plus two utilities that aren't jobs:
- **CAPTURE** — `/brana:log` (lightweight, anytime)
- **KNOWLEDGE HEALTH** — weekly DECAY cycle (automated)

### Job Composability

Jobs nest — they're not sequential:

```
BUILD can trigger UNDERSTAND (diagnosis needed for a bug)
UNDERSTAND can trigger BUILD (spike helps understanding)
GROW can trigger UNDERSTAND (market research)
DECIDE can trigger UNDERSTAND (triage needs investigation)
SHIP triggers DECIDE (task completion)
SHIP triggers GROW (client notification)
```

The auto-learning loop runs at every level — outer job and inner sub-flows both produce knowledge.

### CLAUDE.md Reorganization

Phase A3 reorganizes CLAUDE.md's command table by job instead of by implementation category. This is a 1-hour documentation change, not a code change. The taxonomy becomes the primary navigation model for users finding the right skill.

### Thinking-Jobs vs Execution-Jobs

4 skills are "thinking-jobs" that get the full auto-learning loop: brainstorm (DECIDE), research (UNDERSTAND), build (BUILD), review (GROW). The remaining skills are execution — they produce outputs but don't generate reusable knowledge that needs capture.

## Consequences

- CLAUDE.md command tables reorganize around 6 jobs
- Smart router (ADR-032) uses job context for strategy detection
- New skills must declare which job they belong to
- `/brana:ship` becomes a natural gap to fill (SHIP has no skill today)
- UNDERSTAND gains 4 strategies under `/brana:research` (research, evaluate, learn, investigate)
- Taxonomy is descriptive, not prescriptive — no enforcement mechanism needed
