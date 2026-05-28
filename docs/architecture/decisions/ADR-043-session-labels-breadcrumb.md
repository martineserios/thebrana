---
status: accepted
---
# ADR-043 — session_labels: structured breadcrumb for same-day merges

**Status:** Accepted  
**Date:** 2026-05-25  
**Task:** t-1461

## Context

`write_state()` implements same-day merge semantics: when two sessions close on the same project+branch on the same calendar day, their `accomplished`/`next`/`learnings`/`blockers` arrays are unioned and `session_label` is concatenated with ` | `.

The concatenated string works for display but is lossy: once two labels are joined into `"Session A | Session B"`, there is no way to know how many sessions contributed, what each label was individually, or whether the ` | ` separator appeared inside an original label.

## Decision

Add `session_labels: Vec<String>` (optional array, `serde(default)`) alongside the existing `session_label: Option<String>`.

`merge_states()` populates it as follows:
1. Seed from `existing.session_labels` (empty for old entries).
2. Backfill `existing.session_label` into the array if not already present (backward compat).
3. Append `new.session_label` if not already present (dedup by value).

`session_label` is unchanged — it remains the human-readable concatenated string for display surfaces that read a single field.

## Schema

```json
{
  "session_label": "Session A | Session B",
  "session_labels": ["Session A", "Session B"]
}
```

Both fields are omitted when empty (`skip_serializing_if`). Old JSON without `session_labels` deserializes to an empty `Vec` via `serde(default)` — no migration needed.

## Consequences

- **Structured multi-session audit:** `session_labels.len()` gives the exact session count for a given day.
- **Initiative accumulator (Fix C):** `session-initiatives/{slug}.json` can carry `session_labels` directly, enabling per-initiative session count and label tracking across days.
- **Zero breaking change:** old `session-state.json` files round-trip without modification.
- **No CLI surface change:** `brana session write` and `brana session read` require no flag changes.
