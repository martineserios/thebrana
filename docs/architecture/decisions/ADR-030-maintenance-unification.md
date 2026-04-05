# ADR-030: Maintenance Unification (Expand /reconcile)

**Date:** 2026-04-04
**Status:** accepted
**Tasks:** t-899
**Source:** Operating model §5

## Context

Brana has three overlapping maintenance skills:

| Skill | What it does |
|-------|-------------|
| `/brana:audit` | Security checks (secrets, hook permissions, MCP count) |
| `/brana:maintain-specs` | Spec correction cycle (errata → reflections → synthesis) |
| `/brana:reconcile` | Spec ↔ implementation drift detection |

These overlap in scope (all check consistency), fragment the maintenance workflow (user must remember which to run), and share no infrastructure. The operating model's MAINTAIN job needs a single entry point.

## Decision

**Expand `/brana:reconcile` to absorb audit and maintain-specs. Defer the unified `/brana:maintain` mega-skill.**

### Phase B3: Expanded /reconcile

Add 3 new domains to /reconcile's existing consistency checks:

| Domain | Checks | Source |
|--------|--------|--------|
| **Consistency** (existing) | Spec ↔ implementation drift, CLAUDE.md ↔ skills | ADR-001 |
| **Security** (from /audit) | Secrets in config, hook permissions, PreToolUse deny gates | /audit |
| **Propagation** (from /maintain-specs) | Pending errata cascade (dimension → reflection → roadmap) | /maintain-specs |
| **Knowledge** (new) | Stale dimensions, event log bloat, ruflo noise, orphan docs | DECAY integration |

### /close Auto-Trigger

When `/brana:close` detects brana system file changes (skills/, hooks/, agents/, rules/), it auto-triggers `/brana:reconcile --scope consistency,propagation`. This catches undocumented behavioral changes at session end.

### Retirement Plan

| Skill | Action | When |
|-------|--------|------|
| `/brana:audit` | Retire — security domain absorbed into /reconcile | Phase B3 |
| `/brana:maintain-specs` | Retire — propagation domain absorbed into /reconcile | Phase B3 |
| `/brana:maintain` (proposed) | Deferred — only build if expanded /reconcile proves insufficient | Phase D+ |

### Why Not Build /maintain Now

The operating model proposes `/brana:maintain` as a mega-skill unifying all 6 maintenance domains (security, infra, consistency, propagation, knowledge, code). This is deferred because:

1. Expanding /reconcile is a smaller change with immediate value
2. We don't know which domains will actually be used together
3. The mega-skill can be built later as a thin orchestrator over /reconcile domains

## Consequences

- `/brana:reconcile` gains `--scope` flag for selective domain execution
- `/brana:audit` and `/brana:maintain-specs` are retired (skill files removed)
- `/brana:close` gains auto-trigger for brana system changes
- DECAY (from ADR-027) is implemented as the knowledge domain of /reconcile
- One fewer skill for users to remember (35 → 33)
- Weekly maintenance becomes: `/brana:reconcile --scope all`
