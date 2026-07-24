---
depends_on:
  - docs/architecture/decisions/ADR-067-retired-fields-write-guard.md
---
# t-2385: Write-Time RETIRED_FIELDS Guard

## Problem

Retired task fields (`level`, `epic`, `stream`) are currently rejected only
by *omission* — `brana-core::tasks::set_field` (`tasks.rs:1147-1282`) is an
exhaustive `match` over valid field names; anything unmatched falls to the
catch-all `_ => Err(format!("unknown field: {field}"))` (`tasks.rs:1280`).
This is indistinguishable from a genuine typo, and two other write surfaces
duplicate the same retirement list independently:

- `crates/brana-cli/src/commands/backlog.rs` `cmd_add` (~line 660-680) —
  explicit `contains_key("level") / "epic" / "stream"` checks.
- `crates/brana-mcp/src/tools/backlog_add.rs` — `#[serde(deny_unknown_fields)]`
  on the typed `Input` struct.

Three retired fields, three independent enforcement mechanisms, no single
source of truth. A binary that ships a new retirement has to update all
three by hand, and there's no way to distinguish "field never existed" from
"field is retired" in the error message.

## Solution

Add `pub const RETIRED_FIELDS: &[&str] = &["level", "epic", "stream"];` to
`crates/brana-core/src/tasks.rs`, near the top of the file alongside the
existing field-handling code.

1. **`set_field`** (`tasks.rs:1147`): before/alongside the `match field`
   dispatch, check `RETIRED_FIELDS.contains(&field)` first. If matched,
   return a distinct error message (e.g. `format!("field '{field}' is
   retired and cannot be written — {reason}")`) rather than falling through
   to the generic `unknown field` catch-all. This makes retirement
   diagnosable at the call site instead of looking like a typo.
2. **`cmd_add`** (`backlog.rs` ~660): replace the three hand-written
   `contains_key` checks with a loop over `brana_core::tasks::RETIRED_FIELDS`
   checking the incoming JSON object's keys — same behavior, one source of
   truth.
3. **MCP `backlog_add`**: leave `deny_unknown_fields` as-is (it already
   rejects retired fields at deserialization, which is stricter than
   `RETIRED_FIELDS` would be) — no change needed there. Note in a comment
   that `RETIRED_FIELDS` is the canonical list this struct must stay a
   superset-rejecting subset of.

## Non-goals

- No schema-version marker or skew-detection system (ADR-067 rejects this).
- No change to the MCP path's `deny_unknown_fields` mechanism.
- Does not retroactively fix data already written by a stale binary before
  this guard existed — only prevents regression going forward.

## Tests (write first, per TDD)

- `set_field` on each of `"level"`, `"epic"`, `"stream"` returns the new
  distinct "retired" error string, not `"unknown field: ..."`. Existing
  tests `test_set_field_rejects_level/epic/stream` (`tasks.rs:2380-2407`)
  assert rejection already — extend them to assert the specific error text
  distinguishes retired-vs-unknown.
- A genuinely unknown field (e.g. `"bogus_field"`) still returns
  `"unknown field: bogus_field"` (regression guard — retirement check must
  not swallow the generic unknown-field case).
- `cmd_add` with a retired field in the JSON payload is rejected with the
  same message source (`RETIRED_FIELDS`), covering the CLI ingestion path.

## Consequences

- Single source of truth for retired field names in `brana-core`.
- Adding a future retirement is a one-line addition to `RETIRED_FIELDS`
  instead of touching three call sites.
- Residual gap (documented in ADR-067): a binary built *before* a field
  is added to `RETIRED_FIELDS` still can't reject it. Complementary fix is
  t-2386 (fast-track ship exception for schema-sealing commits).
