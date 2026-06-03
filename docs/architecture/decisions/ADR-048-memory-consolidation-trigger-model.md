---
id: ADR-048
status: Accepted
date: 2026-06-03
tags: [memory, consolidation, scheduler, kairos]
produced_by: [docs/ideas/memory-consolidation-autodream.md]
applies_to: thebrana
---

# ADR-048 — Memory Consolidation Trigger Model and Scope Split

## Status

Accepted

## Context

Brana accumulates memory files across sessions but had no automatic compaction. CC's
unreleased `autoDream` (inside the `Kairos` daemon, feature-flagged off as of v2.1.89)
would provide this — but it is not shipped and the trigger model is unknown (the 24h+5-session
model is from a third-party reimplementation, not the leaked code).

Two jobs already handle memory maintenance:
- `lint-heal.sh` — weekly deterministic L2 (dedup, contradiction grep, frontmatter imputation)
- `/brana:close` — session extraction layer

The gap: no threshold-triggered pass for debrief-analyst outputs and frontmatter date normalization.

## Decision

Add `memory-consolidation.sh` as a distinct, non-overlapping third layer.

**Scope split (hard boundary):**

| Layer | Script | Trigger | What it does |
|-------|--------|---------|--------------|
| L2 | `lint-heal.sh` | Weekly (Sun 15:00) | Dedup by name:, contradiction grep, imputation, surfacing |
| L3 | `memory-consolidation.sh` | Threshold (Mon–Sat 15:30) | Debrief-flag consumption, frontmatter date normalization |

`memory-consolidation.sh` does NOT call `lint-heal.sh` — separate locks, separate schedule,
separate state fields. Both read from `lint-heal-state.json` but write different fields.

**Trigger model — OR logic:**

```
fire when: (now - last_consolidation_ts > 86400) OR (session_count_since_run >= 5)
```

AND logic was rejected: if `/brana:close` is skipped (Ctrl+C exits), the session counter
never increments and the consolidation never fires. OR logic ensures the 24h arm always
covers drift.

**State file — shared, extended:**

`~/.swarm/lint-heal-state.json` gains one field:
```json
{ "last_consolidation_ts": 0 }
```

`lint-heal.sh` owns `last_run_ts`, `session_count_since_run`, `last_run_date` and resets
`session_count_since_run` on its Sunday run. `memory-consolidation.sh` owns only
`last_consolidation_ts`.

**Debrief-flag schema (`~/.swarm/debrief-flags.jsonl`):**

```json
{
  "timestamp": "2026-06-03T10:00:00Z",
  "type": "contradiction",
  "file": "feedback_X.md",
  "action": "archive",
  "acted_on": false,
  "confidence": "high",
  "session": "main",
  "source": "debrief-analyst"
}
```

Flags are written by `/brana:close` when the user approves an errata finding that names
a memory file. Consumption is idempotent: if the file was already archived by lint-heal
between flag write and consumption, the existence check skips it cleanly.

**Date normalization scope:**

Frontmatter `created:` / `updated:` fields ONLY — never body prose. Body prose normalized
would corrupt factual records ("the decision was made yesterday" → wrong absolute date).
URL tokens containing relative-looking strings are never touched (word-boundary guard
via Python regex, not sed).

## Consequences

- Consolidation fires within 24h of hitting threshold even if `/brana:close` was skipped.
- Debrief-analyst outputs that name a memory file are automatically archived within one
  consolidation cycle.
- lint-heal.sh and memory-consolidation.sh have no lock dependency on each other.
- Sunday is lint-heal day; the consolidation job skips Sunday (schedule: Mon–Sat).
- The `session_count_since_run` counter (owned by lint-heal) is reset to 0 on Sunday —
  after that reset, the 24h arm becomes the primary trigger until sessions accumulate again.

## Non-Actions

- No LLM calls — consolidation is deterministic shell + Python only.
- No call to lint-heal.sh from within the consolidation script (lock collision risk).
- No date normalization in body text (URL corruption risk, confirmed by challenger review).
- No always-on daemon (Kairos equivalent deferred — assess when CC ships theirs).
