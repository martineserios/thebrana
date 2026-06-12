---
depends_on:
  - docs/architecture/decisions/ADR-051-reminder-store-architecture.md
  - docs/architecture/decisions/ADR-002-scheduler-thin-layer-over-systemd.md
  - docs/domain/MODEL-001-brana-core.md
informs:
  - docs/ideas/async-first-close.md
status: proposed
---

# ADR-054: Reminder Delivery Channels — Notify Context, Timed Dispatch

**Date:** 2026-06-12
**Status:** Proposed
**Tasks:** t-1996 (this ADR), t-1997 (schema + CLI), t-1998 (registry + adapters + dispatch), t-1999 (scheduler wiring), t-2000 (docs)
**Source:** Reminders/scheduler/calendar research 2026-06-12 (4-scout sweep + decision log); calendar sync deferred per user decision (decision log 2026-06-12)

## Context

The reminder store (ADR-051) is pull-based: reminders surface only at session start (pending count) or via `brana remind list`. There is no way to say "remind me at 15:00" and get pinged at 15:00. The gap is the time trigger and the delivery path — the store, the timer layer (ADR-002 systemd scheduler), and a push channel (Telegram send in `system/scheduler/brana-scheduler-notify.sh`) all exist but are not wired together.

The user wants delivery to be **channel-based**: named channels (Telegram, desktop, ntfy, …) that reminders can route to explicitly or broadcast across, with sensible defaults. Google Calendar sync was researched and **deferred** (decision log 2026-06-12): inbound calendar reads are a documented prompt-injection surface (zero-click RCE via calendar events, Feb 2026), and outbound sync is not needed for v1 delivery. The channel abstraction is the seam where calendar returns later as just another channel type.

Constraints inherited from prior decisions:

- ADR-051 §4: the store schema evolves only via `Option<T>` / `#[serde(default)]` fields; mutation only by the Rust CLI under the write lock.
- ADR-002: new timed behavior is a scheduler job over systemd timers — never a new daemon.
- MODEL-001: cross-context communication happens through the application layer; contexts stay independent.
- Telegram send already exists inline in `brana-scheduler-notify.sh` — duplicating it would create drift.

## Decision

### 1. A new bounded context: Notify (`core::notify`)

Channels are general notification infrastructure, not reminder-private. The context owns the channel registry and message delivery:

- **Aggregate root:** `ChannelRegistry` (owns `~/.claude/notify-channels.json`)
- **Entity:** `Channel` — name, type, settings (per-type: secrets file path, topic, …), enabled
- **Value objects:** `ChannelType` (Telegram | Desktop | Ntfy), `DispatchResult` (Sent | Failed { reason }), `RoutingRule` (priority → channel names)
- **Operations:** `load_registry()`, `resolve(explicit_channels, priority) -> Vec<Channel>`, `send(channel, message) -> DispatchResult`

Consumers (all via the application layer, per MODEL-001's key rule):

1. **Reminder dispatch** (this ADR) — first consumer
2. **Calendar** (deferred) — future channel type; no code or schema accommodation in v1 beyond the type enum being non-exhaustive

**Explicit non-consumer:** `brana-scheduler-notify.sh` keeps its inline Telegram curl. Its brana-independence is deliberate — it must be able to report failures *of the brana binary itself* (stale binary, broken build, panicking dispatch job). Routing it through `brana notify send` would create a circular failure mode where the notification about the broken binary also fails. The duplication is a firebreak, not drift (challenger finding, 2026-06-12); a `# DELIBERATE: independent of brana binary — do not migrate to brana notify` comment marks the curl block.

### 2. Registry schema

`~/.claude/notify-channels.json` — per-user, cross-project, **hand-edited config, read-only to the CLI** (no locking needed; same `version` + lenient-parse evolution rules as ADR-051 §4):

```json
{
  "version": 1,
  "channels": {
    "telegram": { "type": "telegram", "secrets_file": "~/.hub-secrets" },
    "desktop":  { "type": "desktop" },
    "ntfy":     { "type": "ntfy", "server": "https://ntfy.sh", "topic": "<unguessable>" }
  },
  "defaults": { "high": ["telegram", "desktop"], "medium": ["desktop"], "low": [] }
}
```

- Secrets never live in the registry — only file references (Telegram token read from the secrets file at send time, ntfy topic is the sole inline credential by that protocol's design).
- `defaults.low: []` is intentional: low-priority reminders never push; they surface via the existing session-start path only.
- Missing registry file → dispatch is a silent no-op (warn once to stderr); the store remains fully functional pull-based.

### 3. Store schema additions (ADR-051 §4-compliant)

Three optional fields on the reminder entry; existing stores parse unchanged:

| Field | Type | Meaning |
|---|---|---|
| `due` | `Option<String>` (RFC3339 UTC) | When to push. `None` → never pushed (pull-only reminder, current behavior) |
| `channels` | `Option<Vec<String>>` | Explicit routing. `None`/empty → priority defaults from registry. `["all"]` → broadcast to every enabled channel |
| `dispatched_at` | `Option<String>` (RFC3339 UTC) | Set when dispatch attempted-and-at-least-one-channel-succeeded. Non-null → never dispatched again |

Lifecycle is unchanged (pending → resolved / snoozed / expired). Dispatch does **not** resolve a reminder — the human acting on it does. A snoozed reminder whose snooze expires with `due` in the past is eligible for dispatch on the next run only if `dispatched_at` is null.

### 4. CLI surface

```
brana remind write --text "Call Ramon" --at 15:00 --channels telegram,desktop
brana remind due [--dispatch]
brana notify send --channel telegram --message "..."   # adapter surface, also used by scheduler OnFailure
brana notify channels                                   # list registry channels + routing defaults
```

- `--at` accepts RFC3339, `HH:MM` (today, local timezone → stored UTC), or `YYYY-MM-DD HH:MM`. Past times are accepted with a warning (dispatches on next run).
- `brana remind due` lists pending reminders with `due <= now` and `dispatched_at == null`. With `--dispatch` it resolves channels, sends, and records `dispatched_at` — all under the ADR-051 write lock, making the dispatch marker the idempotency guarantee.

### 5. Dispatch semantics

- **Ownership:** Rust-side, consistent with ADR-051's "one owning binary" rationale. Adapters are thin subprocess execs (`curl` for telegram/ntfy, `notify-send` for desktop) — no HTTP client dependency added to the binary for v1.
- **Two-phase dispatch — the lock is never held across I/O** (challenger finding, 2026-06-12). Subprocess sends can take seconds; holding the store lock through them would block every concurrent reminder write (hooks, parallel sessions). Phases:
  1. **Select** (under lock): read store, collect entries with `due <= now`, `status == pending`, `dispatched_at == null`. Release lock.
  2. **Send** (no lock): run adapters for each selected entry.
  3. **Commit** (under lock): re-read store; for each entry that had ≥1 successful send and is *still* `dispatched_at == null`, set `dispatched_at`. Entries already marked by a concurrent run are left untouched.
- **Ordering is send-then-mark.** A crash between send and commit yields a duplicate ping on the next run; mark-then-send would yield a silent loss (marked, never delivered) — the exact failure class ADR-051 exists to prevent. For human notifications, duplicate beats lost. The double-ping window (select→commit of two concurrent runs) is narrow and bounded: timer runs are serialized by the ADR-002 runner's per-job flock, so the window only opens against a *manual* concurrent `--dispatch`.
- **Partial failure:** attempt every resolved channel; if **at least one** succeeds, set `dispatched_at` and log per-channel failures (journal). If **all** fail, leave `dispatched_at` null — the next scheduler run retries all channels. Consequence: a reminder delivered on one channel is never retried on a channel that failed — accepted for v1 (the human was reached); per-channel retry bookkeeping is explicitly out of scope.
- **Headless safety:** desktop adapter absent/no session → counts as Failed, never blocks, exit 0 (mirrors `remind.sh`'s hooks-never-block contract).

### 6. Scheduler wiring (ADR-002 pattern)

One template job, command-type (no `claude -p`, no LLM): `brana remind due --dispatch`, every 10 minutes. Empty store / nothing due → fast exit before any lock acquisition (same `[ -s file ]`-style cheap guard as session-start's read path). Job failures route through the existing `brana-sched-notify@.service` OnFailure unit, which stays brana-independent (§1) — so a broken dispatch binary still produces a failure notification.

### 7. Ubiquitous language (MODEL-001 additions)

| Term | Definition | Context |
|---|---|---|
| **Channel** | A named, configured delivery endpoint (telegram, desktop, ntfy) | Notify |
| **Channel registry** | Hand-edited config owning channel definitions + routing defaults | Notify |
| **Routing** | Resolving a reminder's target channels: explicit list > priority defaults | Notify |
| **Broadcast** | Routing to every enabled channel (`channels: ["all"]`) | Notify |
| **Dispatch** | The locked, idempotent act of sending a due reminder through its resolved channels | Reminders (app layer) |
| **Due** | The instant after which a reminder is eligible for dispatch | Reminders |

MODEL-001 gains the Notify context entry and a Reminders context entry (the store predates the model) — done in t-2000.

## Alternatives considered

### Calendar as the delivery backend
Google Calendar events with native popup notifications would deliver to the phone with zero adapter code. Rejected for v1: deferred by user decision; inbound reads are a 2026 prompt-injection surface; outbound-only sync still adds OAuth + API quota + a network dependency to the dispatch path. Returns later as a channel type — the registry is the seam.

### Dispatch in shell (extend brana-scheduler-notify.sh)
The Telegram send already lives there. Rejected: dispatch requires locked read-modify-write on the store (idempotency marker), and ADR-051 settled that store mutation belongs to the Rust binary exclusively. Shell dispatch would reintroduce the exact concurrent-write hazard ADR-051 exists to prevent.

### Migrating the OnFailure script onto `brana notify send`
Originally proposed in this ADR's draft to avoid duplicating the Telegram curl. Killed by challenger review (2026-06-12): the script's brana-independence is a deliberate firebreak — it is the component that reports brana-binary failures, so it cannot depend on the brana binary. Two Telegram send sites is the accepted cost; the script's copy is annotated as deliberate.

### Per-reminder systemd timers (one timer per due time)
Exact-time delivery instead of ≤10-minute granularity. Rejected: timer-unit churn, orphan cleanup on resolve/snooze, and ADR-002's spirit (a thin static job table, not dynamic unit generation). 10-minute granularity is acceptable for human reminders; revisit only with a concrete need for exactness.

### Reusing `tags` or `action` for routing (no schema change)
Encoding channels as `tags: ["ch:telegram"]`. Rejected: stringly-typed routing in a field with a different meaning; ADR-051 §4 makes proper optional fields cheap and non-breaking.

## Consequences

- "Remind me at 15:00" becomes: `brana remind write --text … --at 15:00`, delivered within 10 minutes of due time on the configured channels — no calendar, no new daemon, no new store.
- The notify context is reusable system infrastructure for future "push something to the human" needs — with the explicit exception of the OnFailure firebreak, which never migrates onto it.
- Two config surfaces (store + registry) instead of one; mitigated by the registry being optional — without it, behavior is exactly today's pull-based store.
- At-least-once semantics mean a rare double-ping is possible across an all-channels-failed retry where one send actually landed (e.g. curl timeout after server receipt). Accepted for human-notification stakes.
- The 10-minute dispatch granularity is a floor on timeliness; documented in the user guide (t-2000).

## Non-Actions

- No inbound calendar reads, no calendar writes (deferred — see decision log 2026-06-12).
- No new daemon, no per-reminder timers, no SQLite.
- No notification history/audit log beyond `dispatched_at` and the systemd journal.
- No registry mutation CLI (`brana notify` reads; humans edit the file).
- No recurring reminders in v1 (`due` is a single instant; recurrence belongs to the scheduler's cron layer if ever needed).
