# Feature: LEARN Worker Compute-Chain Contract — agy-first, Claude engine-switch, token ceiling, checkpoint/resume

**Date:** 2026-09-04
**Status:** design (contract for t-2405/t-2406/t-2407/t-2408/t-2409 — not yet implemented)
**Task:** t-2404
**Decision:** [ADR-068](../decisions/ADR-068-v3-supersession.md) §Decision item 3, row "ADR-050 blast-radius constants" (frozen — this spec elaborates it, never restates it) · [brana-v3-redesign.md](../../ideas/drained/brana-v3-redesign.md) principle 7 (t-2286 resolution)

## Problem

The nightly LEARN worker (`system/cron/close-extraction.sh`, ADR-052 §6-7, backed
by `~/.claude/close-queue.json`) drains the close-queue one entry at a time via
agy (Layer A). It already has a *per-entry* Claude fallback (`claude_fallback()`)
for when agy 429s or returns empty output on a single entry. What it does **not**
have is a *per-run* stop condition: nothing accounts for how much compute a run
has spent, so the only ceiling today is the scheduler's wall-clock
`timeoutSeconds: 1800` (`system/state/scheduler.json`) — a blunt kill from
outside the script, not a cooperative stop the worker chooses. Principle 7 (v3
redesign, t-2286 resolution) requires a **hard per-run token ceiling with
checkpoint/resume — never unboundedly deferred**. This doc is the contract wave-2's
implementation tasks (t-2405-t-2409) build against.

## Current reality (baseline, confirmed against source 2026-09-04)

`close-extraction.sh`'s per-entry loop, for each queue entry:

1. Calls `agy -p "$PROMPT"` (Layer A, free/cheap).
2. On agy failure classified as quota (`429`/`rate.?limit`/`resource_exhausted` in
   output, or exit 0 with empty stdout — the t-2082 regression): calls
   `claude_fallback()`, which shells out once to `claude -p "$prompt"`.
3. If **both** agy and the Claude fallback fail for that entry: `skip_entry` +
   `break` — the *whole run* stops, deferring every remaining entry to the next
   nightly cron fire (02:00). This is the residual "skip-and-defer" path t-2409
   deletes.
4. There is no token/cost accounting anywhere in the script. A run that never
   hits agy-quota can process an unbounded number of entries until the
   scheduler's `timeoutSeconds` kills the process tree mid-entry — losing
   whatever that entry's `fail_entry`/`mark-processed` bookkeeping would have
   recorded, since a hard `timeout` kill does not run the script's own
   cleanup path.

The queue itself (`brana close-queue`, backed by `~/.claude/close-queue.json`)
already persists per-entry state (`processed` / `retry_count` / `last_error`) —
so entry-level resume already exists structurally. What's missing is *run-level*
resume: a way to stop cleanly mid-run on a compute budget, not a crash, and know
exactly where to pick up next time.

## Contract

### 1. Engine chain (agy-first, Claude engine-switch)

Unchanged in shape from what already ships, formalized as the LEARN worker's
compute chain:

```
agy (Layer A, per-entry) --fail(quota)--> claude -p (Layer A fallback, per-entry)
                          --fail(non-quota)--> fail_entry (retry budget burned)
```

**What's new:** the chain gets a **third rung** — when the *run-level token
ceiling* (below) is hit, the worker does not fall through to `claude_fallback`
for the current entry at all. It stops the loop cleanly, exactly as if it had
finished the queue, and leaves the entry `unprocessed` for the next run. This
is a distinct exit path from `skip_entry` (agy+Claude both failed on *this*
entry) — ceiling-stop is "the budget for *this run* is spent," not "this entry
is unreachable."

### 2. Per-run token ceiling

- A hard ceiling on **tokens spent this run**, tracked across both agy and
  Claude calls (agy calls are free/quota-metered separately and do not count
  against the Claude-credit ceiling directly, but a run that engine-switches to
  Claude for every entry must still stop — the ceiling exists to bound Claude
  spend specifically, since agy already self-limits via its own quota).
- Checked **before** each entry's `claude_fallback` call and before starting a
  new entry's agy pass (a coarse per-entry check, not mid-prompt — matching the
  existing per-entry loop granularity; splitting a single agy/claude call
  mid-stream is out of scope).
- On ceiling hit: log the stop reason, write the checkpoint (below), and exit
  0 — a ceiling stop is expected steady-state behavior, not a failure
  (`EXIT_CODE` stays whatever it was from completed entries; a ceiling stop by
  itself must not flip it to 1).
- Ceiling value: a `LEARN_TOKEN_CEILING` env override (tests) with a
  conservative shipped default, sized off wave-2's own cost-baseline spike
  (mirrors wave-4's t-2393 "cost-baseline spike first" pattern — do not guess a
  number here; measure real per-entry Claude-fallback token cost across a
  representative sample of queued entries during t-2405/t-2406 implementation,
  then set the default from that measurement plus headroom, not before).

### 3. Checkpoint/resume (queue cursor persistence)

- **The queue's own per-entry `processed`/`retry_count` state already is the
  checkpoint.** A ceiling-stopped run has processed some prefix of eligible
  entries and left the rest `unprocessed` — the *next* run's `close-queue list
  --unprocessed` naturally resumes from there, oldest-first, with no separate
  cursor file needed. This mirrors ADR-052 §2's existing rule ("re-read the
  queue per iteration via the CLI, no cached shell-variable view") and needs no
  new persistence mechanism.
- **What t-2406 must add:** the *ceiling-stop write path itself* — right now a
  scheduler-level `timeout` kill can sever the script mid-`fail_entry`/
  mid-`mark-processed`, before the CLI call that would have persisted that
  entry's outcome. A cooperative ceiling check that stops the loop *inside* the
  script (never relying on the external timeout to be the thing that stops it)
  guarantees every entry the worker touched is fully accounted (`mark-processed`
  or `mark-failed` already called) before exit. The AC that matters here is
  behavioral, not structural: **a mocked-token-accounting test must assert the
  worker STOPS (not merely resumes) once the ceiling is reached, and that the
  last entry it touched is in a terminal queue state, not a torn one.**
- Scheduler alignment: `timeoutSeconds: 1800` stays as an outer safety net (a
  script that hangs — e.g. agy itself wedged — still needs an external kill),
  but the token ceiling should be sized so a well-behaved run stops itself well
  before the wall-clock limit in the common case.

### 4. Curation gate (t-2407) — interface only

Out of this doc's detailed scope (t-2407 owns the design), but the compute
chain must call it: after Layer A extraction succeeds for an entry, learnings
route through the curation gate (dedup/decay) **before** `write_reminder`, not
after — a duplicate-suppressed learning should never reach the reminder store
and then get pruned; it should never be written. The gate consumes token
budget too (if it uses a model call for near-duplicate detection) and must be
accounted against the same per-run ceiling from #2.

### 5. Tier B observe-invariant (t-2408) — interface only

Per ADR-068's carried-forward mechanic table: LEARN writes are **Tier B
(scoped-mutation)** — the worker may write to the reminder store and the
close-queue's own bookkeeping, but a test must prove those writes are *inert*:
they gate nothing (no task auto-transitions, no memory writes, no ranking) and
require an explicit human-promotion step (`brana remind` review) before
anything downstream acts on them. The compute-chain changes in this doc (token
ceiling, ceiling-stop) do not touch this invariant — they change when/how the
loop stops, not what it's allowed to write.

## What this replaces

Per t-2409's AC: `grep -r` for the agy skip-and-defer stall path (the
"quota-exhausted... will retry next run" `break` on double-failure) must return
no matches in the LEARN worker code once t-2405/t-2406 land. That `break`
doesn't disappear — its *reason* changes from "both engines failed on one
entry, guessing the rest will too" (the deadlock-shaped assumption principle 7
retires) to "the run's token ceiling is spent" (a bounded, cooperative,
always-eventually-true stop condition). The double-engine-failure case still
exists as `fail_entry` (burns that one entry's retry budget) — it just no
longer assumes-and-aborts the rest of the run.

## Non-goals

- Does not change the extraction prompt contract (`system/cron/prompts/close-extraction.txt`)
  or the learnings JSON schema — orthogonal to compute-chain sequencing.
- Does not remove the scheduler-level `timeoutSeconds` safety net.
- Does not implement the curation gate or Tier B test themselves (t-2407, t-2408
  own those) — this doc only fixes their interface point in the compute chain.
- Does not set a numeric token-ceiling default here — that number comes from
  measurement during t-2405/t-2406, not from this design pass.

## Implementation tasks

| Task | Scope |
|---|---|
| t-2405 | Core drain loop (`brana-core::learn::drain_queue`) implementing this chain |
| t-2406 | Checkpoint/resume: cooperative ceiling check + stop, mocked-token-accounting test |
| t-2407 | Curation gate (dedup + decay) |
| t-2408 | Tier B scoped-mutation observe-invariant test |
| t-2409 | Remove the skip-and-defer stall path |
