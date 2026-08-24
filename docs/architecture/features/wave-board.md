---
status: shipped
---
# Wave board (t-2844)

> Implements [ADR-080](../decisions/ADR-080-plan-time-wave-graphs-epic-runner.md) §6f.
> Renders the [wave-gate-enforcement.md](wave-gate-enforcement.md) mechanics
> (`resolve_wave_selector`, `check_wave_gate`) that
> [plan-time-wave-graph.md](plan-time-wave-graph.md) waves populate — this
> feature adds no new wave semantics, only a read-only view over them.

Status: **implemented (t-2844, 2026-08-14).**

## Goal

Before this feature, understanding a multi-wave epic's shape (which wave
gates which, how many tasks each has matched/pending/in-flight/approved)
required manually cross-referencing `wave list` output against `wave get`
and task queries. `brana backlog wave board` is the L0 cockpit gauge that
renders the gate chain and per-wave counts in one read-only call.

## Design decisions

- **Strictly read-only.** Every function in the call path (`wave_board`,
  `wave_gate_topo_order`, `wave_counts`) takes `&[Value]`, never `&mut`, and
  the CLI command uses `load_tasks` (a plain read) — no `lock_tasks`, no
  `save_tasks`. This is a type-level guarantee, not just a convention;
  verified by a CLI-level test that asserts the tasks.json file is
  byte-identical before and after the command runs.
- **Zero direct selector parsing.** Counts route exclusively through the
  same `parse_wave_selector` single-parse-point and `WaveSelector::matches`
  status-agnostic matcher that `resolve_wave_selector` and the wip
  live-count use (ADR-080 §1) — never a hand-rolled prefix strip. This is
  the exact bug class ADR-080 §1 named and fixed for the wip live-count
  (`wave_pull_decision` used to hand-strip `tag:`, silently defeating
  `wip_limit` on `parent:` waves); a wave board built the same way would
  have reintroduced it.
- **Topo order via real DFS, not the bash bound-walk approximation.** A
  wave's `gate` names at most one predecessor, so the gate graph is a
  forest — depth-from-root ordering (computed by DFS with a `visiting`
  stack for cycle detection) is a valid topo sort. Unlike
  [`wave-graph-emit.md`](../../../system/skills/_shared/wave-graph-emit.md)'s
  bash primitive (which approximates cycle detection via a bounded
  chain-walk because bash has no natural recursion-with-visited-set), this
  is real code — so it uses the straightforward recursive form.
- **A broken gate reference degrades, it doesn't crash.** The board is a
  display, not the enforcement point (`check_wave_gate` is, at drain time).
  A `gate` naming a wave id that doesn't exist renders at depth 0 rather
  than erroring the whole board — a dangling reference is loudly rejected
  where it matters (drain) and gracefully shown where it doesn't (here).
  A genuine gate **cycle**, in contrast, still errors the whole render —
  there's no sane partial order to fall back to.
- **Four counts, one selector match.** `matched` (any status),
  `pending`, `in_progress`, and `approved` (`ac_state:approved`, any
  status) are all computed in a single pass over the matched set per wave —
  no repeated resolution.

## Code flow

- `brana backlog wave board [--json]` (CLI) → `cmd_wave_board`
  (`brana-cli/src/commands/backlog.rs`) → `tasks::wave_board`
  (`brana-core/src/tasks/wave.rs`), which composes `wave_gate_topo_order`
  (ordering) and `wave_counts` (per-wave aggregation).
- Default output: themed table (mirrors the `initiatives`/`epics` dashboard
  convention — themed table default, `--json` opt-out). `--json` emits the
  same rows as a flat JSON array.

## Testing

Unit tests first, per AC ("unit tests first: topo/gate render + count
aggregation"), in `brana-core/src/tasks/wave.rs`'s test module: topo
ordering (linear chain, fan-in shared gate, tie-break by id, 2-cycle,
self-gate, broken-reference degrade-not-crash) and count aggregation
(status/ac_state bucketing, zero-match, unsupported-selector-form rejection).
CLI-level tests in `brana-cli/src/commands/backlog.rs` cover the read-only
guarantee (byte-identical tasks.json before/after) and cycle-error
propagation through the CLI layer. Run: `cargo test -p brana-core -p
brana-cli wave`.

## Known limitations

- **No `--epic`/`--tag` filter.** Renders every wave in tasks.json; scoping
  to one epic's waves is left to a future iteration if the cockpit needs it
  (not required by this task's AC).
- **TUI rendering deferred.** t-2825 (loop-first epic) is where a richer
  dashboard consumes this same `wave_board` function; this task ships the
  CLI/data layer only.
