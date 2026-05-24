---
status: accepted
produced_by: docs/ideas/claude-gemini-orchestration.md
depends_on: [ADR-040]
---
# ADR-041: agy Invocation Contract — Layer A vs B, Routing, /tmp/ Invariant, Version Pinning

**Status:** Accepted
**Date:** 2026-05-24
**Task:** t-1656 (brana-v2-compute-model initiative, Phase 3)

---

## Context

ADR-040 established the compute hierarchy (Claude orchestrates, Ruflo coordinates sub-agents,
Gemini executes as a stateless worker). This ADR locks the concrete invocation contract for
the Gemini worker (`agy`) — how Claude calls it, what guarantees hold at each layer, and how
failures are detected and surfaced.

Evidence base: adversarial spike run 2026-05-24 (t-1648). Failure-mode spec committed to
`docs/architecture/features/claude-gemini-orchestration.md`.

---

## Decisions

### 1. Two invocation layers — Layer A (Bash) and Layer B (MCP)

**Layer A — bare Bash:** `agy -p "..." > system/scheduler/outputs/{ts}.md`

Use for: scheduled overnight sweeps, quick one-shots, spike validation. Output goes to
`system/scheduler/outputs/` (not `/tmp/` — survives reboot before `/brana:close` runs).
No validation, no version check, no timeout enforcement — caller owns these.
`/brana:close` batch-extracts and removes processed files from `outputs/`.

**Layer B — `mcp__brana__agy_delegate` (via `/brana:gemini`):**

Use for: all skill-driven delegations with the full ROUTE→ENRICH→DELEGATE→APPLY→EXTRACT→PERSIST
lifecycle. Version check, 120s timeout, stdio isolation, output validation, and `/tmp/` cleanup
are all enforced by the MCP tool — callers get these for free.

**Rule:** never use Layer A for skill-driven work. Never use Layer B for fire-and-forget sweeps.

### 2. 4+1 routing heuristic

Before any delegation, four questions must all be yes:

1. **Atomic?** — completable in one `agy -p` call, no mid-task state needed
2a. **System-isolated?** — no writes to `system/`, git, hooks, `tasks.json` during execution
2b. **Context-enrichable?** — ENRICH (ruflo + task context) can supply sufficient background
3. **Speed/token benefit?** — repetitive, fast, or token-heavy for Claude

Plus the convention gate (the "+1"):

5. **Convention-sensitive?** If yes: ruflo mandatory; abort if ruflo unavailable.
   Convention-sensitive types: boilerplate generation, test scaffolding, ADR drafts, any
   output applied to the repo that must match codebase conventions to be correct.
   **Default: when in doubt, treat as convention-sensitive.**

Any "no" on 1–3 → Claude only. Convention-sensitive + ruflo down → abort, not fallback.

### 3. /tmp/ invariant is absolute

All Gemini output from Layer B lands in `/tmp/agy-{suffix}-{ts_ms}.md` only.
`agy_delegate.rs` hardcodes this path. Callers cannot override it.

Layer A scheduled sweeps write to `system/scheduler/outputs/` instead — ephemeral `/tmp/`
would be lost on reboot before `/brana:close` processes it.

Claude reads from `/tmp/` and applies changes via its own Write/Edit tools. CC hooks fire
normally on every repo change. No agy output ever lands in the repo without Claude's
explicit Write/Edit call.

### 4. AGY_PINNED_VERSION = "1.0.1"

`agy_delegate.rs` pins `const AGY_PINNED_VERSION: &str = "1.0.1"`. Version is checked at
every invocation via `agy --version`. Mismatch → hard error:

> "agy version mismatch: expected 1.0.1, got {actual} — update AGY_PINNED_VERSION in
> agy_delegate.rs after re-running adversarial spike"

**Upgrade procedure:** bump pin constant → re-run adversarial spike → confirm output contract
unchanged → commit. Do not bump without re-running the spike — agy is closed-source with no
semver guarantees.

If `agy --version` flag is ever removed: fall back to binary hash check (sha2 crate, deferred).
Current fallback returns a hard error with instructions rather than silently proceeding.

### 5. AGY_TIMEOUT_SECS = 120

Hard ceiling enforced by `tokio::time::timeout`. agy's own `--print-timeout` defaults to 5
minutes — our ceiling is 2 minutes. Any task needing more than 2 minutes is too large to
delegate atomically; break it down or handle in Claude.

On timeout: return structured error `{"error":"agy_timeout","elapsed_secs":120}`.
`/tmp/` cleanup happens in both success and timeout paths (Drop guard).

### 6. Version mismatch is a hard error, not a warning

Version mismatch aborts the delegation with a structured error. It does not proceed with a
warning. Rationale: agy is closed-source; a version change may silently alter exit codes,
error string patterns, or output format — all of which the validator depends on. An untested
version running in production is worse than a failed delegation.

---

## Failure-Mode Validator Rules

Built from adversarial spike (2026-05-24). In precedence order:

1. Exit code ≠ 0 → `agy_nonzero_exit` error
2. stdout empty after trim → `agy_empty_output` error
3. stdout starts with `"Error: "` → `agy_error` (covers empty prompt + internal timeout)
4. `tokio::time::timeout` fires → `agy_timeout` error
5. Otherwise → success, return trimmed stdout

stderr is always empty in observed agy behavior. Captured but not signal-bearing.

---

## Consequences

- `agy_delegate.rs` is the only surface coupled to agy's CLI. If agy's interface changes,
  only that file needs updating — the skill and rules are unchanged.
- All 6 decisions are structurally enforced in code; none rely on caller discipline.
- Layer A sweep scripts must follow the output-dir convention (`system/scheduler/outputs/`)
  or findings are lost on reboot. Template enforces this via path constants.
- Phase 4 (ENRICH/PERSIST wiring) and Phase 5 (hive-mind quorum) may proceed; this ADR
  provides the stable agy contract they depend on.

## Non-Actions

- This ADR does not specify ENRICH query parameters or enrichment quality thresholds (Phase 4).
- This ADR does not address `--bg` (background delegation) — deferred to v2 when t-1507
  (atomic tasks.json write) ships.
- This ADR does not set the AGY_PINNED_VERSION hash fallback implementation (needs sha2 crate).
