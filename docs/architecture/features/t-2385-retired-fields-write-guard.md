---
depends_on:
  - docs/architecture/decisions/ADR-067-retired-fields-write-guard.md
---
# t-2385: Write-Time RETIRED_FIELDS Guard

## Problem

Of the three `tasks.json` write surfaces, two are already structurally safe
against retired fields (allowlist by construction — omitting a match
arm/struct field is itself the rejection):

- `brana-core::tasks::set_field` (`tasks.rs:1147-1282`) — exhaustive `match`
  over valid field names, unmatched fields fall to `_ => Err(format!("unknown
  field: {field}"))` (`tasks.rs:1280`).
- `crates/brana-mcp/src/tools/backlog_add.rs` — typed `Input` struct with
  `#[serde(deny_unknown_fields)]`, rejects retired fields at deserialization.

The **one genuine gap** is `crates/brana-cli/src/commands/backlog.rs`
`cmd_add`'s `--json` path (~line 660-680): it merges a raw, untyped JSON
object onto the new task, guarded only by hand-written
`contains_key("level")/("epic")` and `contains_key("stream")` checks — a
denylist that does not automatically cover future retirements. This already
drifted once: t-2310 added the first check, t-2325 needed a second
hand-patch for `stream`.

## Solution

Add to `crates/brana-core/src/tasks.rs`, near `set_field()`:

```rust
pub const RETIRED_FIELDS: &[&str] = &["level", "epic", "stream"];

pub fn reject_retired_fields(obj: &serde_json::Map<String, serde_json::Value>) -> Result<(), String> {
    let found: Vec<&str> = RETIRED_FIELDS.iter().filter(|f| obj.contains_key(**f)).copied().collect();
    if found.is_empty() {
        Ok(())
    } else {
        Err(format!(
            "{} field(s) are retired (ADR-065) — level collapses into type, \
             epic/stream are now hierarchy/tag concerns; use --parent/tags instead",
            found.join(", ")
        ))
    }
}
```

Replace the two hand-written `contains_key` blocks in `cmd_add`
(`backlog.rs` ~660-674) with:

```rust
if let Some(obj) = new_task.as_object() {
    if let Err(e) = tasks::reject_retired_fields(obj) {
        eprintln!("{{\"ok\":false,\"error\":\"{e}\"}}");
        anyhow::bail!("{e}");
    }
}
```

## Non-goals

- No schema-version marker or skew-detection system (ADR-067 rejects this).
- **Do not touch `set_field()`** — its catch-all already rejects retired
  fields correctly; adding a `RETIRED_FIELDS` check there is redundant, not
  defense-in-depth, and risks touching well-tested dispatch code
  unnecessarily.
- **Do not touch `crates/brana-mcp/src/tools/backlog_add.rs`** —
  `deny_unknown_fields` already rejects retired fields at deserialization,
  which is stricter than `RETIRED_FIELDS` would be.
- Does not retroactively fix data already written by a stale binary before
  this guard existed — only prevents regression going forward.

## Tests (write first, per TDD)

- `reject_retired_fields()` unit tests: empty object passes; single retired
  field rejected and named; all three at once rejected and all named;
  fields with similar substrings (`"epics"`, `"streaming"`) pass — exact key
  match only, no substring matching.
- Existing `cmd_add_json_payload_rejects_level_key` / `_epic_key` /
  `_stream_key` integration tests in `backlog.rs` must continue passing
  unmodified — this is a behavior-preserving refactor of the CLI path, not a
  behavior change.
- New integration test: a payload combining `level` + `stream` in one
  request is rejected with both fields named (today's hand-written code only
  ever names one hardcoded pair; this generalizes to any combination).
- Do **not** modify `test_set_field_rejects_level/epic/stream`
  (`tasks.rs:2380-2407`) — out of scope, they already pass against
  unmodified `set_field()`.

## Consequences

- Single source of truth for retired field names, used where it's actually
  needed (the one raw-JSON merge surface), not spread redundantly across all
  three write paths.
- Adding a future retirement to the CLI `--json` path is a one-line addition
  to `RETIRED_FIELDS` instead of a new hand-written `contains_key` block.
- Residual gap (documented in ADR-067): a binary built *before* a field is
  added to `RETIRED_FIELDS` still can't reject it. Complementary fix is
  t-2386 (fast-track ship exception for schema-sealing commits).
