---
depends_on:
  - docs/architecture/decisions/ADR-051-reminder-store-architecture.md
  - docs/ideas/async-close-design.md
informs:
  - docs/ideas/async-first-close.md
  - docs/architecture/features/reminder-system.md
status: accepted
---

# ADR-052: Close Queue — Rust-Owned Writes, agy Extraction Contract

**Date:** 2026-06-10
**Status:** Accepted
**Tasks:** t-1970 (phase), t-1971 (this ADR), t-1972 (queue CLI), t-1973 (close skill), t-1974 (cron), t-1975 (surfacing), t-1976 (batch sources), t-1977 (docs)
**Source:** async-close design (docs/ideas/async-close-design.md Q1–Q3) + plan challenger review 2026-06-10 (verdict: PROCEED WITH CHANGES — 4 CRITICAL, 4 HIGH findings, all resolved here)

## Context

Track 1 makes session close a 30-second snapshot + queue append; Track 2 is a nightly cron that runs one LLM pass per queued session and routes extracted learnings. This creates a second per-user, cross-project JSON store (`~/.claude/close-queue.json`) with the same risk profile that nearly wrecked the reminder store: concurrent writers (parallel sessions closing simultaneously, and the cron rewriting while a session closes), with silent entry loss as the failure mode. ADR-051 settled the pattern; this ADR extends it and pins the cron and extraction contracts the plan left implicit.

## Decision

### 1. Queue store: Rust-owned mutation (extends ADR-051)

`~/.claude/close-queue.json` is mutated **only** by `brana close-queue` subcommands (named `close-queue`, not `queue` — `brana queue` already exists as the task-spawn command; discovered at t-1972 implementation, amended 2026-06-11):

- `brana close-queue append --project … --branch … --git-root … --git-range … --snapshot-path … [--commit-count N] [--session-notes-path …]`
- `brana close-queue list [--unprocessed]`
- `brana close-queue mark-processed <id> --summary-path …`
- `brana close-queue mark-failed <id> --error …` (increments `retry_count`)
- `brana close-queue prune` (entries >30 days old, processed or failed)

The Rust write path owns: sidecar advisory lock (`close-queue.json.lock` — never the store inode, which atomic rename replaces), parse-before-write validation, mktemp-in-store-dir + atomic rename, serde evolution rules identical to ADR-051 §4 (no `deny_unknown_fields`, post-v1 fields `Option<T>`/default, version via `serde_json::Value`, UTC RFC3339).

### 2. Cron never touches JSON directly (challenger C4)

`close-extraction.sh` interacts with the queue **exclusively** through `brana close-queue` subcommands — zero jq reads, zero file writes to the store. Each subcommand locks-and-rewrites atomically; the cron re-reads via `brana close-queue list --unprocessed` per iteration rather than caching the queue in a shell variable across mutations. A session closing mid-cron-run appends safely because `append` and `mark-processed` serialize on the same lock.

**Read-only exception (t-1979, challenger disposition #1):** the session-start hook's close-queue dead-man check reads the store with pure jq. It is deliberately independent of the brana binary — a dead cron, a missing binary, and an unregistered job all manifest as a stale queue, and the monitor must not depend on the thing it monitors. The exclusivity rule above governs *mutation* and *cron-side* access; read-only monitoring from hooks is sanctioned.

### 3. Entry identity: random id + dedup_key (challenger H5)

Entry `id` is **random** (`q-` + 8 random bytes hex), never content- or time-derived — deterministic `close-{ISO}-{project}` ids collide when parallel sessions close in the same second (the exact mistake reversed in ADR-051). Idempotency is carried by `dedup_key = {project}:{branch}:{git_range}`: `append` with a dedup_key matching an existing **unprocessed** entry is a no-op returning the existing entry (the same work range is already queued); processed/failed entries never absorb appends.

### 4. Schema v1

Per design Q2 with the fixes above:

```json
{
  "version": 1,
  "entries": [{
    "id": "q-3fa9c2d1e0b4a7f2",
    "dedup_key": "thebrana:feat/t-1234-x:abc123..def456",
    "timestamp": "2026-06-10T23:15:00Z",
    "branch": "feat/t-1234-x",
    "project": "thebrana",
    "git_root": "/home/user/project",
    "git_range": "abc123..def456",
    "commit_count": 3,
    "snapshot_path": "/home/user/.claude/sessions/snap-20260610-2315.diff",
    "snapshot_truncated": false,
    "session_notes_path": null,
    "processed": false,
    "processed_at": null,
    "summary_path": null,
    "failed": false,
    "retry_count": 0,
    "error": null
  }]
}
```

- `snapshot_path` is stored **absolute** — `append` expands `~` via `util::home()` at write time; `Path::new()` never sees a tilde (challenger H6)
- `snapshot_truncated`: snapshots are capped at **500KB** — close truncates the diff beyond that and sets the flag; the cron processes truncated snapshots with reduced completeness expectations, never fails them (challenger H8)
- `session_notes_path` is `Option<String>`, null in v1 (design Q1)

### 5. Close-mode matrix (challenger C3)

| Close mode | Queues? | Rationale |
|------------|---------|-----------|
| NANO (1 commit, ≤5 files, no code/config) | **no** | Below extraction threshold by definition; don't spend an LLM pass |
| LIGHT | **yes** | Cheap to queue; cron decides extraction value, not close |
| FULL (`--full`) | **yes** | Full debrief still runs; queue entry feeds the nightly summary |

`brana session write` (handoff state) is **retained** in all Track 1 paths — the queue supplements session-state, it does not replace it. NANO and LIGHT behavior must be covered by regression tests in t-1973.

### 6. Extraction worker: agy direct — provisional (challenger C2 + user decision)

The nightly worker is `agy -p` (Gemini Flash, Layer A — delegation-routing designates Layer A for scheduled sweeps; output to `/tmp` only, never runs git).

**Output contract:** agy must return structured JSON (written to `/tmp`):

```json
{"learnings": [{"type": "errata|pattern|field-note", "size": "SMALL|LARGE", "title": "...", "body": "...", "confidence": 0.0}]}
```

**Failure handling — pinned, not implementation judgment:**
- Output missing, empty, or unparseable as the schema above → `brana close-queue mark-failed <id> --error …`; **never** write partial results, **never** mark processed
- agy binary unreachable → all entries left unprocessed, entries touched get `mark-failed`, cron exits non-zero so `brana ops` health surfaces the failure
- After 3 failed retries on an entry → write a processing-failure reminder via `write_reminder`; human resolves

**Routing (v1, challenger H7):** ALL validated learnings route to the reminder store via `write_reminder` — none auto-write to ruflo/memory, because a shell cron has no MCP client. The human routes to memory at review time. Revisit only if a `brana memory write`-from-cron path ships.

**Deferral note (t-1979, challenger disposition #8):** auto-routing extracted learnings to memory is explicitly DEFERRED until the §6 revisit checkpoint (≈2 weeks of daily-summary review) confirms worker quality — human review is the safety property while the worker is unproven. Until then the cron writes a weekly `weekly-learnings-review:{ISO-week}` reminder nudging the human to route pending extraction learnings. Extraction reminder dedup keys take the form `extract:{project}:{type}:{slug}` — the type discriminator prevents a pattern and an errata with the same title from colliding (t-1979 #2; distinct from the queue-entry dedup_key in §3).

**Provisional clause:** agy is the v1 worker because all output is human-reviewed (quality ceiling is triage-grade, not judgment-grade) and the nightly cost is ~zero. **Revisit trigger:** after ~2 weeks of daily-summary review, if agy demonstrably misses learnings visible in the diffs, swap the worker to `claude -p` (or hybrid: agy nightly + Claude weekly over the week's summaries). The worker invocation is one line in the cron script; the queue plumbing is worker-agnostic by design.

### 7. Cron contract (design Q3, hardened)

Chronological (oldest first), sequential (one LLM pass at a time), per entry: read snapshot → agy pass → validate output → route to reminders → `mark-processed` with `summary_path`. Then: append (never replace — challenger M9) to `~/.claude/sessions/daily-summary-{date}.md`, `brana close-queue prune`, delete snapshot files of processed entries older than 30 days, plus a status-blind `find -mtime +30` sweep over `snap-*.diff` and `daily-summary-*.md` (failed/orphaned files age out too — t-1979 #5/#9). `mark-failed` reasons are categorized: `timeout:` / `rate-limit:` / `agy-error:` / `schema-invalid:` / `snapshot-missing:` (t-1979 #4). A missing agy or brana binary is a *pre-queue* exit (non-zero, scheduler health surfaces it) — no queue entry exists to mark, so `binary-missing` is intentionally not a queue-level error category. Stale-queue self-monitor: any entry unprocessed >3 days → reminder (dedup_key `stale-close-queue` so it counts occurrences instead of spamming).

### 8. Acceptance gate

t-1972 (queue CLI) must not start until this ADR's status is **Accepted** (challenger C1). Acceptance is recorded by flipping the frontmatter + Status field and committing.

## Alternatives considered

**Deterministic entry ids (`close-{ISO}-{project}`)** — rejected: same-second parallel closes collide; duplicate policy becomes ambiguous (drop = silent loss, append = duplicate extraction). Random id + explicit dedup_key separates identity from idempotency. Mirrors the ADR-051 id reversal.

**Cron reads queue JSON directly with jq** — rejected: reintroduces the read-modify-write race the Rust CLI exists to prevent; one mid-run append would be silently dropped on the cron's rewrite.

**`claude -p` as extraction worker** — deferred, not rejected: better judgment, but nightly token burn on a triage task whose output is human-gated anyway. Encoded as the revisit trigger in §6.

**Auto-routing SMALL learnings to ruflo memory from cron** — rejected for v1: no MCP client in shell cron context; pretending otherwise would have shipped a silently-dead code path (challenger H7).

## Consequences

- A second store ships with day-one locking and the race test as part of TDD scope — no deferred-hardening debt
- The cron is a thin orchestrator: all state mutation lives in two already-tested Rust surfaces (`brana close-queue`, `brana remind`)
- Extraction quality is bounded by Gemini Flash until the revisit trigger fires; the cost of being wrong is review noise, not corrupted memory
- close gets faster for every mode without losing the FULL escape hatch
