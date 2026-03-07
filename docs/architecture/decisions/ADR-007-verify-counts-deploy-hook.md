# ADR-007: Verify Counts Deploy Hook

## Status
Accepted

## Context
The `/memory review --audit` integration test (t-039) found 10 contradictions in docs — 7 of which were stale counts (skills, dimensions, hooks). These drift silently when components are added/removed but docs aren't updated.

The full audit is expensive (agent-driven, reads multiple docs). A lightweight bash check catches the most common drift type at near-zero cost.

## Decision
1. Add `system/scripts/verify-counts.sh` — pure bash, checks filesystem counts against doc claims (skills, dimensions, agents, hooks). Warns on mismatch, never blocks.
2. Wire into `deploy.sh` as Step 8 (post-deploy verification).
3. Add delegation-routing trigger: after `/maintain-specs` cascades → suggest `/memory review --audit` on touched docs.

Two tiers: cheap automated check on every deploy, expensive full audit only after spec cascades.

## Consequences
- Every deploy surfaces count drift immediately
- No false sense of security — ghost references and cross-doc contradictions still need the full audit
- One new script, one deploy.sh edit, one routing trigger
