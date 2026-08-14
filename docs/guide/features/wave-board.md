# Wave board

`brana backlog wave board` is a read-only cockpit gauge: one glance at every
wave's place in the gate chain, plus how many of its matched tasks are
pending, in flight, or AC-approved.

## Quick Start

```
brana backlog wave board
```

```
Wave Board
  wave-3 adr080-core   shipped   gate:none    matched:3  pending:0 in_progress:0 approved:3
  wave-4 adr080-consumers  draining  gate:wave-3  matched:11 pending:2 in_progress:1 approved:6
  wave-5 adr080-docsync    queued    gate:wave-4  matched:1  pending:1 in_progress:0 approved:0
```

Waves are always listed in gate order — a wave never appears before the wave
it's gated on. For machine consumption:

```
brana backlog wave board --json
```

## How It Works

- **Gate order, not creation order.** If wave-B gates on wave-A, wave-A is
  always listed first — even if wave-B was created earlier. Ungated waves
  come first; ties break by wave id.
- **Four counts per wave**, all computed from the wave's selector:
  - `matched` — every task the selector matches, any status.
  - `pending` — matched tasks still pending.
  - `in_progress` — matched tasks currently being built.
  - `approved` — matched tasks whose acceptance criteria are approved
    (`ac_state:approved`), any status.
- **Strictly read-only.** This command never writes to `tasks.json` — it's
  safe to run at any time, as often as you like, mid-drain or not.
- **A broken gate reference still renders.** If a wave's `gate` names a wave
  that no longer exists, that wave just shows up as if ungated — the board
  won't crash or blank out. (A genuine gate *cycle* is the one thing that
  still stops the whole render — there's no sane order to show.)

## Examples

**No waves yet** — prints "No waves found." and exits cleanly.

**A gate cycle** (misconfigured waves) — the command errors with a message
naming the cycle, instead of printing a partial or misleading board.

**JSON output** for scripting or a future TUI:
```json
[{"id":"wave-3","name":"adr080-core","status":"shipped","gate":null,
  "matched":3,"pending":0,"in_progress":0,"approved":3}, ...]
```
