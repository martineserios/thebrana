---
title: "Doc Frontmatter Specification — SemVerDoc + Confidence Tiers"
status: accepted
date: 2026-05-04
informs:
  - validate.sh
  - docs/architecture/decisions/ADR-021-knowledge-architecture-v2.md
---

# Doc Frontmatter Specification

Self-reporting temporal metadata for reasoning docs (reflections, ADRs, dimension docs, feature briefs). Implements the SemVerDoc + confidence-tier portion of [ADR-021](../decisions/ADR-021-knowledge-architecture-v2.md) §"Self-reporting temporal metadata".

## Required fields

```yaml
---
last_verified: YYYY-MM-DD     # ISO date, last time content was checked against reality
status: active | deprecated | draft
maturity: seedling | budding | evergreen
---
```

## Optional fields (added by t-439)

```yaml
version: MAJOR.MINOR.PATCH    # SemVerDoc — see semantics below
confidence_tier: tech | architecture | methodology
```

### `version` — SemVerDoc semantics

| Bump | When |
|---|---|
| **MAJOR** (X.0.0) | Breaking change to the doc's premise, scope, or central claim. Anyone relying on the prior version needs to re-read. |
| **MINOR** (X.Y.0) | Added section, new fact, expanded coverage. Backward-compatible — prior reading is still correct, just incomplete. |
| **PATCH** (X.Y.Z) | Correction, typo, clarification, link fix. No semantic change. |

Default for new docs: `1.0.0`. Older docs without `version` are treated as `1.0.0` until edited.

`/brana:close` Step 6 (field-notes lifecycle) bumps MINOR on the **Promote** action automatically — see procedure for details.

### `confidence_tier` — staleness threshold

| Tier | Threshold | Use for |
|---|---|---|
| **tech** | 6 months | API behavior, framework versions, tool flags, hook event names, library APIs — anything that changes with upstream releases |
| **architecture** | 18 months | Data flow, system boundaries, integration patterns, ADR rationale — slow-moving structural decisions |
| **methodology** | 36 months | First-principles reasoning, ontology, lifecycle phases, testing philosophy — durable epistemic claims |

Default for docs without `confidence_tier`: 6 months (most conservative — same as today's hardcoded validate.sh threshold).

## Enforcement

`validate.sh` Check 15 (assumption freshness) reads `confidence_tier` per-doc when present and applies the tier-specific threshold. Without the field, the legacy 6-month threshold applies. Per-assumption tiers (overriding the doc-level default) are tracked separately in t-434.

## Rules

- **Bump version when content changes.** Trivial commits (formatting only) don't need a bump.
- **Pick the tier that matches the slowest-moving fact in the doc.** A doc mixing "OAuth2 flow" (architecture, 18mo) with "Bigin API rate limit" (tech, 6mo) should be tagged `tech` — the most volatile claim governs.
- **Reset `last_verified` on every MAJOR bump.** A breaking change invalidates prior verification.
- **Don't backfill mass-update.** Add the fields when a doc is next edited. validate.sh tolerates absence.

## Examples

```yaml
---
title: "Bigin CRM platform"
last_verified: 2026-04-21
status: active
maturity: budding
version: 1.2.0
confidence_tier: tech       # API behavior dominates
---
```

```yaml
---
title: "Reflection 32 — Lifecycle"
last_verified: 2026-03-14
status: active
maturity: evergreen
version: 2.0.0
confidence_tier: methodology  # DDD/SDD/TDD philosophy is decade-stable
---
```
