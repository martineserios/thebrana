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

## Per-assumption tier override (t-434)

The frontmatter `confidence_tier` is a doc-level **default**. Individual assumptions can override it by adding a `Tier` column to the assumption table:

```markdown
## Assumptions

| # | Claim | If Wrong | Tier | Last Verified |
|---|---|---|---|---|
| 1 | Three-layer separation is the right decomposition | Layers leak, redesign needed | architecture | 2026-03-14 |
| 2 | Tracy API rate limit is 60 req/min | Burst patterns hit 429, retry logic needed | tech | 2026-04-21 |
| 3 | TDD is the right discipline for this codebase | Refactor velocity drops, methodology wrong | methodology | 2026-03-14 |
```

When a row's `Tier` cell is non-empty, validate.sh applies that threshold to the row's `Last Verified` date. When absent or empty, the doc-level `confidence_tier` (or the global `tech` default) applies.

**Why per-assumption matters:** an architecture doc may legitimately mix slow-moving structural claims (architecture tier) with fast-moving API claims (tech tier). A single doc-level tier is too coarse — either the architecture claim fires staleness too often, or the tech claim escapes detection.

## Enforcement

`validate.sh` Check 15 (assumption freshness):
1. Reads doc-level `confidence_tier:` from frontmatter (default: `tech`).
2. Per assumption row, reads the `Tier` column when present and uses it instead of the doc-level value.
3. Applies the tier-specific threshold against `Last Verified`.

Backwards-compatible: existing assumption tables without a Tier column inherit the doc-level tier (or the global `tech` default).

## Rules

- **Bump version when content changes.** Trivial commits (formatting only) don't need a bump.
- **Doc-level `confidence_tier` should match the slowest-moving claim** — let per-assumption Tier handle the volatile rows. (This is the opposite of the t-439 advice; per-assumption tiers reverse it.)
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
