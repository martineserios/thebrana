# session.rs — test fixture spec

Task: t-1343
Related: tasks.spec.md (rotation contract)

## Scope

Bug fix in tests, not in production behavior. The `write_state` /
`rotate_history` / `read_history` contract is unchanged.

## Problem

Three I/O tests (`test_write_archives_previous`, `test_history_limit`,
`test_rotate_drops_old_entries`) used hardcoded `written_at` timestamps from
2026-03-31. `rotate_history` drops entries older than 30 days; once the wall
clock advanced past 2026-04-30 those fixture timestamps started being treated
as old, so the archived entries were dropped before the assertions ran.

## Fix contract

Tests that exercise `write_state` (which calls `rotate_history`) MUST use
`written_at` timestamps inside the 30-day retention window. A `recent_ts(days)`
helper returns `Utc::now() - days` in RFC3339 — pass small positive offsets
to stay inside the window.

`sample_state()` keeps its fixed 2026-03-31 timestamp; it's the shared
fixture for render and validation tests where the literal value is asserted.
I/O tests build their state from `sample_state()` and overwrite `written_at`
with `recent_ts(...)`.

## Out of scope

- Changing `rotate_history`'s 30-day cutoff
- Changing the `write_state` archive contract
- Touching render/validate tests that depend on the fixed fixture timestamp
