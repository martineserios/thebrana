---
title: "verify-docs.sh — Spec"
status: draft
created: 2026-05-05
informs:
  - system/scripts/verify-docs.sh
  - system/skills/verify-docs/SKILL.md
  - docs/architecture/features/doc-frontmatter-spec.md
---

# verify-docs.sh — Specification

Surface for periodic doc verification. Wraps `validate.sh --assumptions-only` and adds an assumption-sampling pass for manual semantic review. **Does not call an LLM** — that scope is reserved for t-441, which is gated on this skill collecting trigger evidence first.

## Why this script exists

`validate.sh` Check 15 detects **structural staleness** (last_verified date older than the tier threshold). It does not detect **semantic drift** — a doc that says "X behaves like Y" while the code now does Z, with `last_verified` recently bumped, passes Check 15 but is still wrong.

t-441 (deferred) wants an LLM check for semantic drift, but only if the manual drift rate exceeds 20%. To measure that rate, we need a tool that hands an operator a small random sample of live assumptions. This script is that tool.

## Inputs

- No required arguments.
- `--sample N` — number of assumption rows to surface for manual review (default: 5).
- `--json` — emit JSON instead of human-readable output. Used by future automation (e.g., quarterly report).
- `--seed N` — RNG seed for reproducible sampling (default: time-based).

## Outputs

### Human-readable (default)

```
=== verify-docs ===

Structural (validate.sh Check 15): PASS — 8 assumptions checked, 0 stale

Sample of 5 assumptions for manual semantic review:

  [1] docs/reflections/14-mastermind-architecture.md
      tier: architecture (doc)
      verified: 2026-04-12
      claim: "Three-layer separation is the right decomposition"
      action: read claim, check current code, mark drift y/n

  [2] ...

Run quarterly. If >20% (>1 of 5) drift, file follow-up to unblock t-441.
```

### JSON (`--json`)

```json
{
  "timestamp": "2026-05-05T12:00:00Z",
  "structural": {
    "checked": 8,
    "stale": 0,
    "exit": 0
  },
  "sample": [
    {
      "doc": "docs/reflections/14-mastermind-architecture.md",
      "tier": "architecture",
      "tier_source": "doc",
      "last_verified": "2026-04-12",
      "claim": "Three-layer separation is the right decomposition"
    }
  ]
}
```

## Exit codes

- `0` — structural pass, sample emitted.
- `1` — structural fail (validate.sh found stale assumptions), sample still emitted.
- `2` — script error (missing dependencies, validate.sh missing, etc.).

## Behavior contract

1. **Always emit a sample** — even when structural check fails. The sample is the artifact regardless of staleness.
2. **Sample is uniform across all assumption rows** — every doc with assumptions contributes proportionally; one doc shouldn't dominate.
3. **Reproducible with `--seed`** — same seed + same docs = same sample.
4. **No mutation** — read-only. Never writes to docs.
5. **Tier resolution matches validate.sh** — row > doc > tech default. The display string makes the source explicit (`architecture (doc)`, `tech (per-row)`, `tech (default)`).
6. **Claim text** — first non-empty cell of the row that isn't the row number, the date, or the tier. Truncated to 100 chars.

## Assumption extraction

Reuses the same Perl pattern as `validate.sh` `check_assumption_freshness` (around line 739). Future refactor: extract to `system/scripts/lib/assumption-extract.sh` and source from both. **Out of scope for the spec stub** — duplicate inline first, factor when the duplication has settled.

## Tests

`tests/scripts/test-verify-docs.sh`:
1. Script exists and is executable.
2. Default invocation exits 0 or 1, never 2.
3. Output contains `Structural` line.
4. Output contains `Sample of N assumptions`.
5. `--sample 3` produces exactly 3 sample entries.
6. `--json` emits valid JSON parseable by `jq`.
7. `--seed 42` is reproducible — same seed twice → identical sample order.
8. Exits 2 if `validate.sh` is missing.

## Out of scope

- LLM-assisted semantic check (t-441).
- Automated drift-rate accumulation across runs.
- CI integration / scheduler wiring.
- Cross-repo verification (only scans the current repo's `docs/` tree).
