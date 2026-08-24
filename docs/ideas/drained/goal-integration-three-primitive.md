---
title: /goal integration — three-primitive composition — merged
status: superseded
superseded_by: docs/architecture/the-brana.md
created: 2026-06-21
merged: 2026-08-24
task: t-2194
---

# /goal integration — three-primitive composition → The Brana

Redirect stub (t-3027 MERGE-INTO). Shaped into **ADR-061** (Accepted) on 2026-06-21; the POLL/ITERATE/FAN-OUT split is now live doctrine, not a proposal.

| What this doc owned | Now lives at |
|---|---|
| POLL (`/loop`) / ITERATE (`/goal`) / FAN-OUT (`Workflow`) split | [the-brana.md §Space — the primitive table](../../architecture/the-brana.md#space--the-primitive-table) |
| `/goal` eligibility criteria, security invariants (presence interlock, done-signal immutability, bounded span) | [ADR-061](../../architecture/decisions/ADR-061-goal-integration-three-primitive.md) |
| `/goal` placement at the Micro→Beat seam | [the-brana.md §Cycle → Decided (L3.2)](../../architecture/the-brana.md#decided) |
| Per-skill `/goal` rollout status | each skill's own `SKILL.md` (the 2026-05-24 audit in [goal-adoption-brana-skills.md](goal-adoption-brana-skills.md) is a historical snapshot, also superseded) |

Full original text: `git log --all --oneline -- docs/ideas/drained/goal-integration-three-primitive.md` (pre-2026-08-24 revisions).
