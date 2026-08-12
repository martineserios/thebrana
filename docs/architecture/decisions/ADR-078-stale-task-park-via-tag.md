---
status: accepted
---
# ADR-078: Park Stale Tasks via the Existing `parked` Tag, Not a New Status

**Status:** Accepted (2026-08-12)
**Date:** 2026-08-12
**Deciders:** Martín Rios
**Tags:** backlog, tasks-schema, lifecycle, adr-065-followup, audit-2026-08-12
**Tasks:** t-2773, t-2743, t-2774
**Relates:** [ADR-065](ADR-065-wave-process-objects.md) (Consequences section names this exact
drift class) · `docs/architecture/features/stale-task-lifecycle-policy.md` (originating
spec, §1) · `task-convention.md` (`stream`/`kind` drift history)

---

## Context

A 2026-08-12 backlog audit found 407 pending tasks stale >30 days (52% of all pending
items, including 1 P0 and 19 P1s), with intake outpacing drain roughly 2.7x. `stale_tasks()`
(`brana-core/src/tasks/query.rs`) already computes staleness; nothing consumes it. t-2743's
spec proposes a scheduled job that reversibly "parks" stale P2/P3 tasks so they stop
diluting active-work views, while escalating stale P0/P1s instead of parking them.

Parking needs a storage mechanism. Two were on the table:

1. **New `status: "parked"` enum value.**
2. **Reuse the existing `tags: [..., "parked"]` convention.** `classify()`
   (`brana-core/src/tasks/query.rs`) already derives a synthetic `"parked"` display state
   from this tag — it is not a `status` enum value today, and `by_state` in `compute_stats`
   already buckets tasks this way. This mechanism predates this ADR and is already tested
   (`stats["by_state"]["parked"]` assertions in `tasks/mod.rs`).

## Decision

**Reuse the existing tag convention. Do not introduce a new `status` value or a new
field.** Parking a task is:

```
brana backlog set <id> tags +parked
```

`status` is untouched (stays `pending`); `parked` is additive, reversible metadata.
Unparking is `tags -parked`. This requires zero changes to `validate_status`,
`classify()`, or the tag-vocabulary validators — the mechanism the scheduled job automates
already exists and is already load-bearing for `by_state` today.

## Rejected alternative: a new `status: "parked"` value

Would require `validate_status` changes, would require `classify()` to stop deriving
`"parked"` from the tag (or maintain two parallel signals for the same state), and repeats
the exact drift class [ADR-065](ADR-065-wave-process-objects.md)'s own Consequences
section already flags — the `stream`/`kind` field duplication documented in
`task-convention.md`, where two fields claimed to mean the same thing and drifted apart.
The tag mechanism is already the single source of truth for "this task is parked" —
extending it is strictly less risky than introducing a second one.

## Consequences

- **Positive:** no schema migration, no new enum, no new write-path validation. The
  automation in t-2774 (auto-park job) is the only new code — a pure consumer of a
  mechanism that already exists and is already tested.
- **Positive:** fully reversible by construction — parking can never destroy information
  the way a status transition or cancellation could.
- **Negative (accepted):** a task can now carry `status: pending` + `tags: [..., "parked"]`
  simultaneously with no automatic reconciliation between the two signals. If a parked
  task's `status` changes to `in_progress` (someone picks it back up) without an explicit
  `tags -parked`, the `parked` tag lingers and `by_state` would misreport it. t-2774's
  implementation must decide and test an unpark-on-activity behavior (or document why it's
  deliberately manual) — flagged as an open question during this ADR's review, not
  resolved here since it's an implementation-time behavior, not a storage-mechanism
  decision.
- **Scope boundary:** this ADR covers the storage mechanism only. Job cadence, thresholds,
  escalation surface, and the weekly intake/drain report are t-2743's spec, not repeated
  here — see `docs/architecture/features/stale-task-lifecycle-policy.md`.
