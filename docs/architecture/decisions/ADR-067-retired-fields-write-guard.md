# ADR-067: Write-Time RETIRED_FIELDS Guard in brana-core

- **Status:** Accepted
- **Date:** 2026-07-24
- **Evidence:** t-2325/t-2381 (3× manual cleanup after retired-field regression), t-2378 (decision writeup), t-2310 (existing whitelist precedent)
- **Related:** t-2385 (implementation), t-2386 (fast-track ship exception), t-2382 (epic accumulator triage)

## Context

`tasks.json` write paths (shared by the `brana` CLI and `brana-mcp` binaries,
both linking `brana-core`) have regressed retired fields back into task
records three times (t-2325, t-2381 and predecessors). Root cause: a stale
live binary/process — still running from before a schema-sealing commit
landed — writes a field its own compiled schema no longer recognizes as
valid, because nothing at the write path rejects it.

t-2310 already added a whitelist check to `set_field()`/`add_task()` that
hard-rejects *unknown* fields. It does not reject fields that were
*previously* valid and have since been retired — that's a different set,
and the existing check has no way to distinguish "never valid" from
"used to be valid, now sealed."

The existing backstop (`validate.sh` check 63) only warns *after* corruption
has already been written, and only when someone happens to run it.

## Decision

Add a `RETIRED_FIELDS: &[&str]` compiled-in constant in `brana-core`, plus a
`reject_retired_fields()` helper, and wire it into the **one** write surface
that actually needs it.

A codebase audit of the three tasks.json write surfaces found they already
use three different mechanisms, of uneven strength:

| Write path | Mechanism | Covers future retirements automatically? |
|---|---|---|
| `brana-mcp` `backlog_add` | Typed `Input` struct, `#[serde(deny_unknown_fields)]` | Yes — allowlist by construction |
| `set_field()` (`brana-core/src/tasks.rs:1147`) | Exhaustive `match`, `_ => Err("unknown field")` catch-all | Yes — allowlist by construction |
| CLI `cmd_add` `--json` path (`brana-cli/src/commands/backlog.rs`) | Raw JSON merged onto the task, guarded by hand-written `contains_key()` checks | **No** — a new retirement needs a new hand-written block; this already happened twice (t-2310, then t-2325) |

The MCP path and `set_field()` are already structurally safe: omitting a
field's match arm/struct field is *itself* the rejection, so a `RETIRED_FIELDS`
check there would be redundant, not defense-in-depth. The CLI `--json` add
path is the one genuine gap — it merges an arbitrary JSON object, so it needs
an explicit denylist, and that denylist has already drifted once.

- **Where:** `RETIRED_FIELDS` + `reject_retired_fields()` live in
  `brana-core::tasks`, wired only into CLI `cmd_add`'s raw-JSON merge. Still
  binary-version-agnostic (both `brana` and `brana-mcp` link `brana-core`),
  scoped to the surface that actually needs a denylist.
- **What it checks:** a field *name* list, not a schema version number. A
  version number only tells you "old" vs "new," not *which* fields are
  retired.
- **On mismatch:** hard-refuse, return an error to the caller — matching
  `set_field()`'s existing precedent (t-2310) of hard-rejecting unknown
  fields. This is a data-corruption bug class (3 prior incidents: t-2325,
  t-2381 required manual cleanup), not a warn-and-continue case.

## Alternatives considered

- **General schema-version marker/skew-detection system** (embed a semver
  the binary checks against a source-of-truth file) — rejected. Adds a
  second thing to keep in sync (the marker itself) without preventing more
  than the simpler constant does. The observed failure mode is always "old
  binary still knows about a since-retired field," never "old binary
  doesn't understand a field format change it should warn about."
- **Warn instead of hard-refuse** — rejected. The warn-after-the-fact
  backstop (validate.sh check 63) already exists and has not prevented 3
  incidents; only a caller-visible error at write time closes the gap.

## Consequences

- Closes the regression path for *already-sealed* fields, for any binary
  built after the RETIRED_FIELDS entry ships.
- Does **not** close the exposure window during the sealing work itself:
  a binary built *before* a field is added to RETIRED_FIELDS still can't
  reject it — it doesn't know yet. This is why t-2386 (fast-track ship
  exception) exists as a complementary process fix: schema-sealing commits
  should reach `main` faster than the normal ADR-060 batch cadence, since
  the failure mode here is corruption, not just missing behavior.
- Scope is deliberately narrow: field-name rejection only. No new
  marker file, no version-skew system.
