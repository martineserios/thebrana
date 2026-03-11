# ADR-017: JSONL Decision Log

**Date:** 2026-03-11
**Status:** accepted
**Related:** ADR-004 (session handoff), ADR-013 (event log), ADR-015 (state consolidation), t-354

## Context

During a session, agents make decisions, discover things, and flag concerns. This information is currently:

- **Ephemeral**: written to `/tmp/brana-session-*.jsonl`, deleted at session end
- **Summarized lossy**: session-end.sh computes aggregate metrics and stores a summary. Individual events are lost.
- **Not concurrent-safe**: tasks.json is monolithic JSON — simultaneous agent writes cause data loss

### Two separate event systems

The `/tmp/brana-session-*.jsonl` stream and this decision log serve different purposes:

| System | Schema | Purpose | Lifecycle |
|--------|--------|---------|-----------|
| `/tmp/brana-session-*.jsonl` | `{ts, tool, outcome, detail, cascade}` | Tool-level telemetry | Per-session, deleted |
| `system/state/decisions/*.jsonl` | `{ts, agent, type, content, severity, refs}` | Semantic decisions/findings | Git-tracked, 30-day retention |

## Decision

Git-tracked, append-only JSONL files in `system/state/decisions/`. One file per session. Each line is a self-contained JSON entry.

### Entry types

| Type | When | Example |
|------|------|---------|
| `decision` | A choice was made | "Chose JSONL over SQLite" |
| `finding` | Something discovered | "Spec graph has 19 orphan docs" |
| `concern` | Risk identified | "No test coverage for auth" |
| `action` | Something done | "Created task t-350" |
| `error` | Something failed | "Build failed: missing dep" |
| `cost` | Resource tracking | "t-348 routed to opus (score: 0.75)" |

### Write→read loop

Phase 2 ships both writers AND readers. session-end.sh writes a summary entry; session-start.sh injects last session's HIGH findings as context. The feedback loop works on day one.

### Retention

- Active: last 30 days in `system/state/decisions/`
- Archived: older files in `archive/` subdirectory
- Archive policy: filename date, not mtime

## Alternatives considered

### JSON object with entries array
`{"entries": [...]}`. Rejected: conflicts on every concurrent write. Two agents appending simultaneously means one's changes are lost.

### SQLite
Binary file, can't git diff/merge, requires dependency. Rejected at current scale. Deferred to Phase 5 when decision log queries span 100+ files.

### YAML
Indentation-fragile appends. Rejected: one misaligned line corrupts the file.

## Consequences

- Session decisions are now git-tracked and persistent
- `grep "HIGH" decisions/*.jsonl` provides instant triage
- Session-start injects prior findings, enabling cross-session continuity
- JSONL files accumulate — archive policy prevents bloat
- Two event systems coexist (telemetry + decisions) with distinct schemas and lifecycles
