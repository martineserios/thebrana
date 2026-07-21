---
title: ac_state forward-only slice (v3 schema MVP, wave-0)
status: implemented
task: t-2283
created: 2026-07-21
related:
  - docs/architecture/features/backlog-v3-schema.md   # destination map (full schema)
  - docs/ideas/brana-v3-redesign.md                   # the process-loop north star
  - docs/reviews/backlog-v3-schema-challenge-2026-07-20.md  # write-path sealing = surviving CRITICAL
  - docs/architecture/decisions/ADR-047-*             # ac_state is an amendment to ADR-047
---

# ac_state forward-only slice — v3 schema MVP (wave-0)

> The smallest real slice of `backlog-v3-schema.md` that a running loop exercises.
> Not the full schema, not the 2,100-task migration. One field, shipped safely, pulled by one consumer.

## Problem

The backlog is a write-only log. It fails the loop story (**nothing to drain** — only 38/2,156 tasks
carry non-empty acceptance criteria, ≈1.8%) and it has no per-task *contract state* a verifier can read.
The full v3 schema fixes this but is a big-bang: nine new fields, deletes, epic-as-top, a version gate,
tags normalization, and a ~2,100-task backfill. Shipping all of that before anything moves is itself the
"aim full" failure the v3 redesign warns against.

This slice ships the **one field a running loop actually needs** — `ac_state` — and nothing else.

## Decision

Add a single per-task field, `ac_state`, forward-only, with **key-presence as the v3-management marker**.

- **Absent key** → legacy v2 task. Loops ignore it. No migration, no rewrite.
- **Present key** (`none` | `proposed` | `approved`) → task is under v3 AC management.
- `none` = managed, no AC proposed yet · `proposed` = loop wrote a candidate AC (inert) · `approved` = human accepted (live).

This single bit implements the operator's rule (confirmed 2026-07-21): *"v3 applies to tasks from now on,
plus tasks I specifically backfill — but not the 2,100."* No mass migration; the default (absent) IS the
non-migration.

### MVP boundary

| In this slice | Deferred (pulled later by a real consumer) |
|---|---|
| `ac_state` field: absent=legacy, `none`/`proposed`/`approved`=managed | epic-as-top / ADR-065 tree change |
| `version: 2` file stamp + gated load | delete `level` / `initiative` / `stream` |
| **Write-path sealing** (CLI + MCP must not clobber the new field) | wave object (general queue primitive) |
| `backlog add` stamps `ac_state: none` on new tasks | key:value tags + tags-normalization |
| `backlog query --ac-state <state>` selector | `spec` / `log` / `wip_limit` / `shape` |
| `backlog set <id> ac_state none` (opt-in a legacy task) | 2,100-task backfill |

## Design

### The field

- Rust: `ac_state: Option<AcState>` where `enum AcState { None, Proposed, Approved }`.
  - `#[serde(skip_serializing_if = "Option::is_none")]` — legacy tasks never gain the key on rewrite (preserves absent=legacy).
  - Serde `Option::None` (key absent) is distinct from `Some(AcState::None)` (key present, value "none"). This distinction *is* the v3-managed marker — do not collapse them.
- `backlog add` sets `ac_state: Some(AcState::None)` at creation.
- `backlog set <id> ac_state none` promotes a legacy task into management (adds the key).

### Write-path sealing (the load-bearing precondition)

Surviving CRITICAL from the schema challenge: CLI (`brana backlog set`) and MCP (`mcp__brana__backlog_set`)
both rewrite `tasks.json`. If either does a full-object (de)serialize that drops unknown fields, it clobbers
`ac_state` written by the other path. **This is a precondition of the slice, not deferrable** — the moment the
field is real, both writers must preserve it.

First build task is a *verification*, not an assumption: does the current serde model round-trip unknown/new
fields across both paths? Two outcomes:
- **Already preserves** (e.g. typed field flows through both, or `#[serde(flatten)]` extras) → "sealing" shrinks to a regression test.
- **Does not** → add one owner function in `brana-core` that both CLI and MCP call for task writes; the round-trip test guards it.

### Version gate

Stamp `version: 2` on `tasks.json`; gate load on it (settled wave-1 requirement — `version:1` was never
value-gated). Additive and cheap; we're already touching the write path.

## Consumer: the `ac-propose` loop (out of scope to build here; this slice unblocks it)

- **Drain queue** = tasks where `ac_state == none` **minus** `work_type ∈ {research, review}` /
  research-audit kinds. (Step-1 dry run 2026-07-21: research/audit tasks yield only thin disjunctive ACs
  and stay L2 — don't spend proposals where the ceiling is low.)
- Loop writes `ac_state: proposed` + a candidate AC. **Proposed ACs are inert** — they gate nothing until a
  human promotes to `approved`. This is how the loop mutates *safely* and resolves v3-review finding #3
  (observe-invariant vs. a loop whose output is writes): the mutation is real but non-live, provable by a
  scoped test asserting the loop touches only `ac_state` + proposed-AC.

## Migration

None required. Existing ~2,100 tasks read as absent → untouched. Opt-in is per-task and explicit
(`backlog set <id> ac_state none`). Reversible: drop the field, keys serialize away.
Composes cleanly with the operator's separate v2-backlog cleanup — no coordination needed.

## Testing (TDD — tests precede implementation)

1. **Clobber round-trip** (the headline AC): set `ac_state` on a task, rewrite via CLI `backlog set` **and** via
   `mcp__brana__backlog_set`, assert `ac_state` survives both. Red first.
2. **add stamps none**: `backlog add` → new task has `ac_state: none`; a pre-existing task (key absent) is unchanged after an unrelated `set`.
3. **query filter**: `backlog query --ac-state none|proposed|approved` returns only key-present matches; legacy (absent) never appears.
4. **opt-in**: `backlog set <id> ac_state none` on a legacy task adds the key.
5. **version gate**: load rejects/upgrades a `version:1` file; `version:2` loads.
6. **work_type skip**: the drain query excludes research/review work_type.

## Risks

| Risk | Mitigation |
|---|---|
| Sealing missed → silent field loss across paths | Sealing is a precondition; round-trip test (both paths) is AC #2 and gates the slice |
| absent vs `none` collapsed in serde | `skip_serializing_if` + explicit test that legacy tasks stay key-less |
| Scope creep into full schema | Boundary table above; each deferred field waits for a real consumer (keeps "deletes ≥ adds" honest) |
| `ac_state`↔`spec` coupling (schema open-question D7) | Decoupled for MVP (approve an AC without a spec); revisit if D7 resolves otherwise |

## Relation to ADR-047

`ac_state` is an amendment to ADR-047 (acceptance-criteria canonicalization): it adds a lifecycle state
(none→proposed→approved) to the criteria a task carries. The amendment is authored alongside this slice.
