---
status: shipped
---
# Wave gate enforcement (t-2744)

> Extended 2026-08-14 by [ADR-080](../decisions/ADR-080-plan-time-wave-graphs-epic-runner.md) §1
> (t-2840) — see §ADR-080 extension below. The "MVP only resolves tag:<name>"
> restriction and the out-of-scope line on selector forms are superseded.

Status: **implemented (t-2775, 2026-08-13).** `check_wave_gate` +
`resolve_wave_selector` live in `brana-core/src/tasks/wave.rs` (exported as
importable functions per [ADR-079](../decisions/ADR-079-backlog-drain-loop-handoff.md)
§2 — the loop runner t-2813 must call the same resolver);
`cmd_wave_drain` in `brana-cli/src/commands/backlog.rs`, wired as
`brana backlog wave drain <id>`. The open question in §1 (drain on an
already-draining/shipped wave) was decided during implementation:
**draining → idempotent** (re-resolves and re-reports, fits ADR-079's
re-resolve-each-cycle model), **shipped → rejected, fail loud**.

## Problem

Wave CRUD landed in full (t-2315, ADR-065): 4 MCP tools
(`backlog_wave_{add,get,list,set}`), matching CLI subcommands
(`brana backlog wave {add,get,list,set}`), storage (`waves` sibling array
in `tasks.json`, `next_wave_id`/`validate_wave_status`/`set_wave_field` in
`brana-core/src/tasks/{mod,validation}.rs` post-t-2745 split). But a
2026-08-12 audit found: zero waves exist in live data, no task carries any
wave-referencing field, and `gate` (a wave id that should block draining
until the gated wave ships) is stored but read by nothing — confirmed by
an exhaustive grep across `brana-core`/`brana-cli`/`brana-mcp` finding zero
consumers outside the storage write path and unit-test assertions.

This isn't an oversight — it's documented intent.
[backlog-v3-schema.md](backlog-v3-schema.md) (the ADR-065 design doc)
describes waves as "a named, drainable **selector**... a loop runs `while
wave.next(): work()`", and its implementation log for t-2315 states
explicitly: *"Selector resolution, `wave drain`, and any query-execution
engine remain explicitly deferred to the intent-CLI, a separate later
build unit."* `gate`'s entire meaning — "this wave can't drain until the
gated wave ships" — only exists in the context of a drain loop that
doesn't exist yet. There is nothing to gate.

## Scope decision: minimal drain, not the full v3 query-grammar vision

[backlog-v3-schema.md](backlog-v3-schema.md) describes a much larger
system than this task should build: a general query grammar (`backlog q
<tokens>`, `drainable`/`blocked`/`mine`/`stale`/`untraced` predicates),
intent aliases, and wave selectors resolved against that grammar
(`shape:mechanical ∧ ac_state:approved`). That's the deferred "intent-CLI"
— a separate, much larger build unit, and explicitly out of scope here.

**This spec covers only enough to make `gate` real**: a single new
subcommand, `brana backlog wave drain <id>`, plus the gate check that
blocks it. It deliberately does NOT build a general query grammar, a
background loop runner, or selector auto-resolution beyond what's needed
for `wave add --selector` to already accept (an opaque string today,
unparsed).

## Design

### 1. What "drain" means (MVP)

`backlog wave drain <id>`:

1. **Gate check (the actual point of this task).** If the wave has a
   non-empty `gate` field, look up the gated wave by id. If it doesn't
   exist: fail loud (`"gate wave {id} not found"` — matches the
   fail-loud-not-silent pattern used throughout this codebase for broken
   references, e.g. `resolve_epic_ancestor`'s exit-status contract). If it
   exists and its `status != "shipped"`: refuse to drain, report which
   wave is blocking. If `shipped` or `gate` is empty: proceed.
2. **Selector resolution (minimal, not the full grammar).** The existing
   `selector` field is stored as an opaque string (per t-2315: "opaque
   text, not parsed/executed"). For this MVP, support exactly one selector
   form: `tag:<name>` — resolves to `backlog_query(tag: name, status:
   "pending")`. This covers the "v3 wave 1: tag wave:v3-w1" pattern from
   the design doc's own examples and needs zero new query engine — it's a
   direct call to the existing `backlog_query`/`filter_tasks_by` machinery
   (`tag_matches`, already shared and tested). Any other selector string
   (the `shape:mechanical ∧ ac_state:approved`-style compound queries from
   the full vision) is explicitly **rejected** at `drain` time with a
   clear "selector form not supported — MVP only resolves tag:<name>"
   error, not silently ignored or partially matched.
3. **Report, don't execute.** `drain` prints the matched task list and
   sets `status: "draining"`. It does **not** spawn agents, run a loop, or
   touch tasks beyond the wave's own `status`. Actually working the
   matched tasks is `/brana:backlog execute` or manual — wiring `drain`
   directly into an execution loop is exactly the "intent-CLI" scope this
   spec declines.
4. **Shipping.** `brana backlog wave set <id> status shipped` already
   exists (no new mechanism) — an operator marks a wave shipped once its
   matched tasks are done. Not auto-detected in this MVP (auto-detecting
   "all matched tasks are complete" would require re-running the selector
   and is a reasonable fast-follow, not required for gate to become real).

### 2. Gate resolution

`gate` stores a wave id (`wave-N`), not a task id — distinct namespace
already enforced by `next_wave_id`'s `wave-` prefix (t-2315's own design
note: "so a bare wave-3 and t-3 can't be confused"). Resolution is a
single `waves.iter().find(|w| w["id"] == gate)` lookup — no parent-chain
walk needed (waves don't nest), unlike the epic-ancestor case t-2765 dealt
with.

**No cycle detection in the MVP.** A gate cycle (A gates on B, B gates on
A) would deadlock both waves' `drain` calls forever — but per t-2315's
precedent ("no referential check on `gate`... matches how `parent`/
`blocked_by` are never existence-checked at write time elsewhere"), and
given zero waves exist in live data today, this is a real-but-currently-
theoretical risk. `drain` failing loud with "wave-A blocked on wave-B
(not shipped)" for both directions IS the cycle manifesting as two
permanently-stuck drains — visible and debuggable, not a silent hang.
Add cycle detection at `wave add`/`wave set gate` write time only if it
turns out to matter once waves see real usage — flagging as a fast-follow
rather than building it speculatively against zero live data.

### 3. What does NOT change

- `wave add`/`get`/`list`/`set` — unchanged, all four already work.
- `validate_wave_status` — unchanged (`queued`/`draining`/`shipped`
  vocabulary already correct; `drain` sets `status: "draining"`, an
  operator sets `"shipped"` manually).
- No new MCP tool for `drain` in this MVP — CLI-only (`brana backlog wave
  drain <id>`), matching how `backlog_wave_add` etc. are thin CRUD
  wrappers and `drain` is meaningfully more than CRUD (it queries, it
  gates, it reports) — if agent-driven wave draining turns out to be
  wanted, add the MCP tool as a thin wrapper over the same CLI-backing
  function once the CLI shape is proven.

### 4. Tests

TDD as normal once implementation starts. Key cases to cover:
gate-not-shipped blocks drain with the blocking wave named in the error;
gate-shipped allows drain; empty/absent gate allows drain; nonexistent
gate id fails loud (not silently treated as "no gate"); `tag:<name>`
selector resolves and matches only pending tasks with that tag; any other
selector form is rejected with the "MVP only resolves tag:<name>" message,
not silently no-op'd.

## Out of scope (this spec, and the follow-up implementation task)

- The general query grammar (`backlog q`, `drainable`/`blocked`/`mine`/
  `stale`/`untraced` predicates, intent aliases) — the deferred
  intent-CLI, a separate, much larger build unit.
- Selector forms beyond `tag:<name>` (compound `∧` queries,
  `shape:`/`ac_state:`-style computed predicates).
- Auto-detecting a wave's completion (all matched tasks done →
  auto-`shipped`).
- Cycle detection on `gate` (§2) — noted as a fast-follow trigger, not
  built speculatively.
- An MCP `backlog_wave_drain` tool (§3) — CLI-only for the MVP.
- Anything from t-2743 (stale-task lifecycle) — a related but distinct
  spec; epic `wip_limit` enforcement and wave `gate` enforcement were
  always different failure modes (too much concurrent epic work vs. wave
  sequencing) and don't share implementation. Epic `wip_limit` itself was
  retired 2026-08-12 (t-2727, ADR-065's amendment) rather than enforced —
  epics turned out to be unbounded groupings, not concurrency-limited. A
  WIP-capping strategy *on waves* is a distinct, later follow-up (t-2782,
  blocked on this spec's `drain` implementation landing first) — not part
  of this MVP.

## Follow-up implementation task

File as a new task once this spec is reviewed: `cmd_wave_drain` in
`brana-cli/src/commands/backlog.rs` (alongside the existing `cmd_wave_*`
family), the gate-lookup + `tag:` selector resolution in `brana-core`
(likely `tasks/validation.rs` alongside `set_wave_field`, or a new
`tasks/wave.rs` if it grows enough to earn its own module — t-2745 split
`tasks.rs` by exactly this kind of size judgment), CLI wiring in `cli.rs`'s
`WaveCmd` enum. Suggested effort: S — the gate check itself is a single
lookup; the `tag:` selector reuses `backlog_query`'s existing tag filter
entirely.
