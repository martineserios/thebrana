---
title: brana-mcp lock-acquire hang fix
status: draft
created: 2026-07-22
---
# brana-mcp lock-acquire hang fix

> Brainstormed 2026-07-22 from t-2305. Status: draft, ready to plan.

## Problem

`mcp__brana__backlog_*` tools (get, search, add — observed directly this session; likely all writers) hang indefinitely and never return, forcing a manual background/TaskStop escape hatch. CLI equivalents (`brana backlog get/search/add`) return instantly and correctly for the exact same operations — the bug is in the `brana-mcp` server layer, not the underlying `brana-core`/CLI logic.

## Root cause (verified, not inferred)

Two compounding facts, both confirmed by reading actual source (not speculation):

1. **`lock_sidecar()` (`brana-core/src/util.rs:774-787`)** acquires the tasks.json write lock via `f.lock()` — a synchronous, blocking `flock(2)` syscall with **no timeout** — called directly inside an async MCP tool handler.
2. **`pmcp` 2.1.0's stdio dispatch is fully serialized, not pipelined** (verified in the vendored crate source, `~/.cargo/registry/src/.../pmcp-2.1.0/src/server/mod.rs:744-765`): `spawn_message_handler` is a single spawned task that loops `receive_message → handle_transport_message(...).await → loop`, and `handle_request_message` calls `server.handle_request(...).await` inline — no per-request `tokio::spawn`. There is **zero concurrency across requests** by design.

Consequence: if any single tool-handler call blocks on the unbounded `flock()` (e.g. contending with a concurrent `brana` CLI process also holding the sidecar lock — very plausible this session, given heavy concurrent `brana backlog set`/worktree/scheduler CLI activity), the entire server freezes for the rest of the session. Every subsequent request of *any* tool — including reads like `backlog_get` that don't even take the lock — queues behind that one stuck call and never gets read from stdin, let alone processed. This explains why `get`, `search`, and `add` all hung in sequence: not three independent bugs, but one earlier blocked call starving pmcp's single serialized loop.

**Ruled out / distinguished:** `session_write`'s historical 78 tool-*failures* (per session-start telemetry) are a **separate issue** — confirmed `session.rs`'s write path does not use `lock_sidecar`/`flock` at all (different mechanism: "archive previous, validate, atomic rename"). Different symptom (fast error, not hang) from a different code path. Do not conflate the two when scoping the fix.

## Why `spawn_blocking` alone is NOT sufficient

The natural first instinct — wrap the blocking `flock()` call in `tokio::task::spawn_blocking` — was challenged and found insufficient. It would free *other* tokio tasks (e.g. the notification channel) to keep running, but pmcp's own message-receive loop still cannot read the *next* incoming request until the current handler's future resolves, because that `.await` is inline in a single non-concurrent loop. Bounded or not, dispatch stays linear. The fix has to make the **lock acquire itself bounded**, not just move it off the async executor.

## Proposed solution

Add a bounded-wait lock acquire to `lock_sidecar()` (or a new `lock_sidecar_timeout()` used by the MCP tool handlers specifically): retry/poll `try_lock()` with a short interval up to a timeout (e.g. 5-10s), and on timeout return a clear `pmcp::Error` ("tasks.json lock held by another process — retry") instead of blocking forever. This is a purely additive change to `brana-core::util` — the CLI's existing blocking-forever behavior can stay as-is if desired (CLI users see it happening and can Ctrl-C; the MCP path has no such visibility), or CLI can adopt the same bounded wait for consistency.

Secondary, good-practice-regardless fix: wrap the (now-bounded) lock acquire + JSON read/write in `spawn_blocking` anyway, so a merely-slow (not stuck) operation doesn't block the notification channel or other background tokio tasks — doesn't fix the core symptom alone, but is cheap and correct to add alongside the timeout.

## Risks

- **Top risk (pre-mortem-style):** a bounded timeout just converts "hangs forever" into "fails after 10s with an unhelpful retry-storm" if the real contention source (concurrent CLI writes during heavy session activity) isn't also addressed — e.g. if agents/hooks retry on failure without backoff, a timeout could turn one graceful queue into a thundering herd of failed retries. Mitigation: the returned error should be a clear, distinct error type/message so callers (and future agent code) can implement sane backoff, and this should be tested under actual concurrent-writer load, not just single-process unit tests.
- Not yet confirmed whether the *specific* trigger this session was CLI-vs-CLI contention, CLI-vs-MCP contention, or a leaked/orphaned lock from a crashed process — worth adding a diagnostic (e.g. log the PID/timestamp holding the lock) alongside the timeout fix so future occurrences are debuggable, not just survivable.

## Next steps

1. Add bounded lock-acquire (with timeout + clear error) to `brana-core::util::lock_sidecar` or a new sibling function used by MCP handlers.
2. Wrap lock acquire + read/write in `spawn_blocking` in the MCP tool handlers (secondary hardening).
3. Write a regression test that holds the sidecar lock from one process/thread and confirms a second acquire attempt times out cleanly (bounded) rather than hanging — mirrors the pattern used for `test-scheduler-runner-lock.sh` earlier this session.
4. Confirm via reproduction through the MCP path: (a) hold the lock, fire a real lock-acquiring writer (`backlog_set`), confirm it returns a clean timeout error within the window instead of hanging; (b) queue an unrelated, lock-free read (`backlog_get`) behind it through pmcp's real serialized dispatch loop, confirm that read's response only arrives once the blocking call resolves — not lost, not early. **Correction (2026-07-22, Challenger gate iteration 2):** the original wording here said "fire a `backlog_get`... confirm it returns an error" — imprecise. `backlog_get` never acquires the lock at all (pure unlocked read), so it architecturally cannot itself produce a timeout error. It hung in the original bug only as a victim of the dispatch queue, which is what (b) above actually proves.
5. Update t-2305's AC to reflect the confirmed root cause and this concrete fix plan.

### Second-order effects

- [Add bounded timeout] → [MCP calls fail fast under contention instead of hanging] → **risk**: if calling code (skills, hooks) doesn't already handle MCP tool errors gracefully, fast-fail could surface as more visible errors in skill runs than the silent-hang did — worth auditing whether backlog-skill call sites already have the documented CLI-fallback behavior wired as automatic (not just manual, per t-2305's AC4) so a timeout error triggers graceful degradation rather than a confusing skill-level failure.
- [Add bounded timeout] → [lock contention becomes visible/debuggable via clear errors] → **opportunity**: this is the first real signal that concurrent brana CLI + MCP usage during active sessions creates write contention on tasks.json at all — worth quietly watching whether this becomes a recurring pattern as more concurrent tooling (reminder dispatch, scheduler jobs, TUI in t-2301) starts hitting the same store.
