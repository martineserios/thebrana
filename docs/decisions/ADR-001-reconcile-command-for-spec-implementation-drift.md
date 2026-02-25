# ADR-001: Reconcile command for spec-to-implementation drift remediation

**Date:** 2026-02-13
**Status:** implemented

## Context

The brana system has four maintenance commands that cover most of the spec-implementation lifecycle:

- `/build-phase` — specs → new implementation (greenfield builds from roadmap WIs)
- `/back-propagate` — implementation → specs (reverse sync when code diverges from docs)
- `/maintain-specs` — specs → specs (cascade changes within the doc layers: dimension → reflection → roadmap)

However, there is a missing arrow: **specs → existing implementation**. In practice, the `enter` specs are frequently updated (via `/maintain-specs`, `/refresh-knowledge`, manual edits), but these changes don't automatically flow into the already-built `thebrana`. The user currently applies these manually, which is error-prone and easy to forget.

The gap is:
1. Specs evolve (new capabilities, corrected conventions, updated skill metadata)
2. The built system (`thebrana`) doesn't know about the changes
3. Drift accumulates until the next `/build-phase` or until someone notices

This is analogous to infrastructure drift detection (e.g., `terraform plan`/`apply`). The system needs a reconciliation loop that compares what's built against what's specced and produces a targeted remediation plan.

### Design questions to resolve

1. **Scope per run** — full scan of all thebrana against all specs, or targetable by area (skills, hooks, rules, config)?
2. **Approval model** — show a plan then apply in batch, or per-change approval?
3. **What counts as "specs"?** — roadmap WIs, reflection docs, CLAUDE.md conventions, skill metadata, deploy script expectations?
4. **Drift report artifact** — should it produce an auditable log of what was found and applied?
5. **Trigger point** — should `/maintain-specs` automatically suggest `/reconcile` when it finds changes that affect thebrana?

## Decision

Create `/reconcile` as a skill in `thebrana`, deployed to `~/.claude/skills/reconcile.yml`.

### Design choices

1. **Scope: full scan always.** Every run compares all of thebrana against all specs. No area targeting — simplicity over granularity. If performance becomes an issue, revisit.

2. **Approval: plan then apply.** Show a complete drift report (what's out of sync, what changes are proposed), ask once for approval, then apply all changes. Mirrors `terraform plan` + `apply`.

3. **Spec surface: all enter docs + conventions.** The "source of truth" includes:
   - Dimension docs (01-07, 09-13, 20-23, 26-28, 33, 35-37)
   - Reflection docs (08, 14, 29, 31, 32)
   - Roadmap docs (15, 17-19, 24, 25, 30)
   - CLAUDE.md conventions (both enter and thebrana)
   - Skill metadata and instructions
   - Deploy script expectations (`deploy.sh`)

4. **Drift report: log to doc 24.** Append drift findings and applied changes to `24-roadmap-corrections.md` (the existing errata doc). Keeps the audit trail in one place.

5. **Trigger: suggest after /maintain-specs.** When `/maintain-specs` cascades changes that touch implementation-relevant specs, it suggests running `/reconcile` to push those changes into the built system. Completes the loop.

### Command flow

```
/reconcile
  1. Scan enter/ specs (all layers + CLAUDE.md + conventions)
  2. Scan thebrana/ implementation (skills, hooks, rules, config, deploy)
  3. Diff — identify drift per area
  4. Present drift report (grouped by area: skills, hooks, rules, config)
  5. Ask: "Apply all changes? [y/n]"
  6. Apply changes to thebrana/
  7. Log drift findings + applied changes to 24-roadmap-corrections.md
  8. Report summary
```

### Comparison strategy

For each area of thebrana, compare against the relevant spec surface:

| thebrana area | Compared against |
|---------------|-----------------|
| `system/skills/` | Skill descriptions in dimension/reflection docs, CLAUDE.md skill table |
| `system/hooks/` | Hook specs in reflection docs (08, 14), dimension docs (05, 06) |
| `system/rules/` | Rule definitions in reflection docs, CLAUDE.md rules section |
| `system/config/` | Config specs in dimension docs, deploy script expectations |
| `deploy.sh` | Deploy process described in roadmap docs, doc 25 self-docs |
| `CLAUDE.md` | Conventions defined across enter/ docs |

## Consequences

### Easier

- **Spec changes flow to implementation.** No more manual tracking of what changed in enter/ and whether thebrana reflects it.
- **Complete maintenance loop.** The four commands now cover all arrows: `/refresh-knowledge` (external → specs), `/maintain-specs` (specs → specs), `/reconcile` (specs → implementation), `/back-propagate` (implementation → specs).
- **Auditable drift history.** Doc 24 records what drifted and when, making it possible to spot recurring drift patterns.
- **Natural chaining.** `/maintain-specs` → suggests `/reconcile` → changes land in thebrana. One smooth flow.

### Harder

- **Full scan cost.** Every run compares everything, which may be slow as the system grows. Acceptable for now; add targeting later if needed.
- **Broad spec surface.** Comparing against all enter docs + conventions means more potential false positives. Will need the same materiality filtering proven in `/maintain-specs`.
- **Cross-repo changes.** `/reconcile` reads from enter/ but writes to thebrana/. Must handle the case where thebrana has uncommitted changes or is on a different branch.
