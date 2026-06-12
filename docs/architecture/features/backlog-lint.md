---
depends_on:
  - docs/research/2026-06-11-loop-native-redesign.md
informs:
  - docs/architecture/features/lint-heal-deterministic.md
---
# Feature: `brana backlog lint` — Definition-of-Ready Checker

**Date:** 2026-06-12
**Status:** shipped
**Tasks:** t-1981
**Branch:** loop-native/feat/t-1981-brana-backlog-lint

## Problem

The loop-native factory model ([research doc](../../research/2026-06-11-loop-native-redesign.md) Part 2) dispatches backlog tasks to autonomous workflows. The t-1991 rehearsal showed curation is the bottleneck: a DoR scan found only ~2 of ~390 pending tasks agent-ready. The foreman needs a deterministic, machine-checkable gate — not judgment — to decide whether a task is safe to dispatch.

## Decision Record

**Decision:** A read-only lint with four hard checks, exit-code contract (0 ready / 1 not), and a non-gating `warnings[]` channel. Logic lives in `brana-core::lint`; the CLI is a thin wrapper.

The four checks:

| Check | Name | Passes when |
|-------|------|-------------|
| 1 | `machine-verifiable-ac` | ≥1 `AC:` line in context matches the v1 verifiability token heuristic |
| 2 | `rich-context` | context has ≥1 non-empty line beyond `AC:` lines |
| 3 | `effort-s-or-m` | effort is exactly `S` or `M` (L/XL must be decomposed first) |
| 4 | `no-open-ambiguity` | no `Q:`/`open Q:` lines and no unresolved `blocked_by` |

**Rehearsal evidence folded in (t-1991):**
- Finding 1 → check 1's token heuristic rewards ACs naming the verification *shape* (commands, exit codes, flags, test/assert/coverage keywords, output verbs, file paths), not just outcomes. `AC: works well` fails.
- Finding 2 → non-gating warning when an AC implies an interface change (surface word + change verb co-occurrence).
- Finding 3 → non-gating warning when tags/description indicate a compiled-language task (`rust`, `cargo`, `compile`) — code-size effort ≠ wall-clock effort.
- Finding 4 (machine build-env preflight) → deliberately deferred to t-1994 dispatch.

**Semantics pins:**
- Blocker resolution: `completed` or `cancelled` count as resolved; a blocker ID not found in tasks.json counts as **unresolved** (conservative). Challenger note: cancelled means "dependency no longer exists", not "dependency shipped" — foreman should weigh that at scale.
- Warnings never affect `ready`. JSON mode serializes them inline (`warnings[]`); human mode prints them to stderr.

## Code Flow

```
brana backlog lint <id> [--json] [--file <tasks.json>]
  main.rs            → exit-code mapping (Ok(true)→0, Ok(false)→1, Err→1)
  commands/backlog.rs → cmd_lint: load tasks, find task, format output
  brana-core/lint.rs  → lint_task(task, all_tasks) -> LintReport
```

## Key Files

| File | Role |
|------|------|
| `system/cli/rust/crates/brana-core/src/lint.rs` | `lint_task`, `LintReport`, `LintCheck`, heuristics + 17 unit tests |
| `system/cli/rust/crates/brana-cli/src/commands/backlog.rs` | `cmd_lint` thin wrapper |
| `system/cli/rust/crates/brana-cli/src/cli.rs` | `BacklogCmd::Lint` clap variant |
| `system/cli/rust/crates/brana-cli/src/main.rs` | exit-code dispatch |
| `system/cli/rust/crates/brana-cli/tests/cli_smoke.rs` | 4 integration tests (exit codes, line naming, JSON schema, unknown task) |

## API Surface

- CLI: `brana backlog lint <task-id> [--json] [--file <path>]`
- Library: `brana_core::lint::lint_task(&Value, &[Value]) -> LintReport`
- JSON contract: `{ready: bool, checks: [{name, pass, reason}], warnings: [string]}`

## Testing

```bash
cd system/cli/rust
cargo test -p brana-core lint        # unit tests
cargo test -p brana-cli --test cli_smoke backlog_lint   # integration
```

## Known Limitations

- **v1 token heuristic has a false-positive surface** — the file-extension matcher also matches abbreviations like `e.g.`/`i.e.` (challenger sev-3). Acceptable for v1; refine from foreman-loop evidence.
- **`rich-context` bar is intentionally low** — any single non-AC line passes. Quality of context is not assessed, only presence.
- **No machine build-env preflight** — deferred to t-1994 (dispatch attaches machine-specific build-env notes).
- Lint never mutates tasks. There is no `--fix`.
