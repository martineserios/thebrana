# Loops Library — contract (stub)

**Status:** stub — records: schema only, distilled ahead of schedule to unblock
t-2845 (epic-drain entry)'s AC requirement that the beat-record schema be
"referenced from the loops-library contract, not duplicated" (ADR-080 §3).
**Owner:** t-2826 (Loops library — `system/loops/` catalog of committed loop
definitions) — full scope (entry-schema lint, `system/loops/` directory
structure, session-status gauge + drain-loop pump promoted to first two
catalog entries) is unbuilt. This file holds only what t-2826's own context
already named as needed elsewhere first: the `records:` beat-record schema.
Expand this file — don't replace it — when t-2826 starts.

**Source doc:** [loops-library.md (idea)](../../ideas/drained/loops-library.md)
— the full entry-schema draft (frontmatter: `name`, `cadence`, `pacing`,
`autonomy`, `drains:`/`fills:`, `spawns:`, `records:`; body: beat procedure +
preflight + STOP conditions + denied verbs). This stub distills only the
`records:` piece into a concrete shape.

## Beat record schema

Every committed loop entry emits one record per beat, always — verbosity is
a render toggle (inline vs quiet), never an emit toggle (t-2826 context,
2026-08-13). The record is the Pavlyshyn work-graph entry: what a beat did,
traceable through objective → plan → artifact → decision → execution record.

```json
{
  "loop": "epic-drain",
  "instance": "backlog-drain",
  "beat": 3,
  "timestamp": "2026-08-14T18:02:11Z",
  "state": "active",
  "what_happened": "pulled t-2847 from wave-adr080-consumers, build framework entered (SPECIFY)",
  "progress": {
    "kind": "bounded",
    "remaining": 4,
    "total": 7
  },
  "escalations": [],
  "next_wake": "PT20M"
}
```

Field notes:
- `loop` — the catalog entry name (matches its frontmatter `name`).
- `instance` — what this beat ran against (epic slug, wave id, or other
  queue-instance identifier — entry-specific).
- `beat` — 1-based sequence number, monotonic per running instance.
- `state` — the RESTART pacing state per beat: `active` (work found and
  pumped), `waiting` (blocked on a human valve or gate), `empty` (queue
  drained, nothing eligible), `stopped` (a real termination signal fired —
  cycle detected, all waves shipped, denied-verb attempted, etc.).
- `what_happened` — free-text summary of what the beat actually did (or
  found), one to two sentences.
- `progress.kind` — `bounded` (a known denominator exists — render a
  progress bar) or `unbounded` (no denominator — render a heartbeat: beat
  count + age since last state change). Declared once per entry, not
  re-derived per beat.
- `progress.remaining` / `progress.total` — bounded only; null when
  unbounded.
- `escalations` — zero or more `{room: "digest"|"agenda", note: "..."}`
  entries raised this beat (wave-pipeline.md's two-rooms split: digest =
  rubber-stamp items, agenda = anything needing judgment).
- `next_wake` — ISO-8601 duration (or absolute timestamp) the loop intends
  to sleep before its next beat, per its pacing rule.

This is the single source for the shape above — loop entries (this file's
consumers) and ADR-080 both reference it, never redefine their own copy.

## Model per beat component (deferred, named not solved)

t-2826's context (2026-08-14, studio) named a per-step model tier as
belonging in each entry's frozen contract — `model: {preflight, act, judge,
records}` — but no entry has adopted it yet and no default table exists.
Out of scope for this stub; a real decision needs t-2826's full pass across
more than one entry's beats to calibrate against, not a single proof entry.

**Partial resolution (2026-08-14, t-2895/ADR-082):** for the JUDGE component
specifically, the model-and-shape question is now decided and single-sourced in
`system/skills/_shared/judge-sizing.md` — the deterministic sizing ladder
(rungs 0–2: single challenger → +sibling-path finder → find/filter/verify funnel
with per-stage tiers) plus its hard-signal arming table. Entries declaring a
`model.judge` field should reference `resolve_judge_rung` from judge-sizing.md
rather than restating a tier — the t-2494 drift class applies to model tables
exactly as it does to prefix tables. The other components (preflight, act,
records) remain deferred as above.
