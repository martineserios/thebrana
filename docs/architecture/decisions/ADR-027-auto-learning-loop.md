---
depends_on:
  - docs/architecture/features/operating-model.md
  - docs/architecture/decisions/ADR-028-ontology-v2.md
informs:
  - docs/architecture/decisions/ADR-030-maintenance-unification.md
  - docs/architecture/decisions/ADR-031-doc-enforcement-hook.md
  - docs/architecture/decisions/ADR-032-smart-router.md
status: accepted
---

# ADR-027: Auto-Learning Loop (6-Step Lifecycle)

**Date:** 2026-04-04
**Status:** accepted
**Tasks:** t-896
**Source:** Operating model §2, challenger review (2026-04-04)

## Context

Brana captures knowledge only when the user explicitly runs `/brana:close` + `/brana:retrospective`. Analysis shows 72% of behavioral commits (124/172) lack documentation updates. Knowledge capture depends on user discipline — and discipline fails at scale.

Research across 18 sources (Karpathy, Letta, AnimaWorks, Anthropic, 12-Factor Agents, and others) reveals a consistent pattern: systems that embed learning into the work loop outperform systems that rely on end-of-session capture. Karpathy's autoresearch and Letta OS both validate this.

The challenger review (2026-04-04) found the original full-loop proposal too ambitious for a system with 72% doc-failure rate. Verdict: PROCEED WITH CHANGES — graduated monthly rollout, start with EXTRACT-only.

## Decision

Embed a 6-step auto-learning loop into all thinking skills:

```
LOAD → WORK → EXTRACT → EVALUATE → PERSIST → DECAY
```

### The 6 Steps

| Step | What | When |
|------|------|------|
| **LOAD** | Pull relevant knowledge into context (ruflo search + graph edges) | Skill start |
| **WORK** | Execute the actual task (unchanged from today) | During skill |
| **EXTRACT** | Identify what was learned (facts, decisions, patterns) | Skill end |
| **EVALUATE** | Quality gate — tiered by significance (SMALL/MEDIUM/LARGE) | After EXTRACT |
| **PERSIST** | Store learnings in the right place (ruflo, docs, memory) | After EVALUATE |
| **DECAY** | Forget what's no longer valuable (staleness, noise, bloat) | Weekly schedule |

### Which Skills Get It

Only 4 thinking skills: `/brana:brainstorm`, `/brana:build`, `/brana:research`, `/brana:review`. All other skills stay untouched. `/brana:close` gets EXTRACT-only as Phase A stepping stone.

### Tiered Evaluation Gate

| Size | Criteria | Gate | Cost |
|------|----------|------|------|
| SMALL (0-1) | Single-task scope, already known | None — auto-persist | Zero |
| MEDIUM (2-4) | Project scope, new on existing topic | Inline eval (dedup, consistency) | ~2K tokens |
| LARGE (5+) | Multi-client, contradicts existing | Challenger review + human approval | ~10K tokens |

### Graduated Rollout

- **Phase A (Month 1):** EXTRACT-only in /close. Gate: doc-update rate >50%.
- **Phase B (Month 2):** Add LOAD to 4 skills. Gate: EXTRACT accuracy >60%.
- **Phase C (Month 3):** Full EXTRACT + EVALUATE + PERSIST in all 4 skills. Gate: accept rate >40%.
- **Phase D (Month 4+):** DECAY, graph CLI, router self-learning.

Each phase requires the previous gate to pass. No evidence = no expansion.

### Measurement

7 metrics tracked in session state JSON:

1. Doc-update rate (>50% month 1, >70% month 3)
2. EXTRACT precision (>70%)
3. EXTRACT recall (>60%)
4. Accept rate (>40%)
5. Skip rate (<60%)
6. Close duration (<2x current)
7. Ontology type/relationship usage (>0 in 30 days)

## Consequences

- Replaces manual `/close` + `/retrospective` as primary knowledge capture
- `/close` debrief-analyst agent becomes the prototype for EXTRACT
- Knowledge grows from use without user discipline
- Ratchet gates prevent premature expansion
- 4 thinking skills gain ~5s overhead (EXTRACT) growing to ~15s (full loop)
- DECAY prevents accumulation debt from automated persistence
