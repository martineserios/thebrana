# Brana Cloud Scheduler — Provider-Abstracted Job Orchestration

> Brainstormed 2026-03-30. Status: idea.

## Problem

Brana ops runs entirely on local systemd timers, which miss runs when the machine is off. Cloud-native scheduling (Claude Code `/schedule`, `/loop`) exists but isn't integrated into brana. There's no path toward cloud-first operations — recurring tasks depend on the machine being on.

## Proposed solution

Evolve `brana ops` into a provider-abstracted scheduler. Jobs dispatch to the right backend based on their requirements. Users interact with `brana ops`; the provider (systemd, RemoteTrigger, session /loop) is an implementation detail, swappable without changing user commands.

### Architecture

```
User -> brana ops add/status/health/enable/disable
              |
              +-- Provider: systemd (local)
              |   Jobs needing local fs/ruflo
              |
              +-- Provider: remotetrigger (Anthropic /schedule)
              |   Jobs needing only git + Claude skills + MCP
              |
              +-- Provider: loop (session-scoped)
              |   Ephemeral dev-time watches
              |
              +-- Future: other cloud providers (AWS Lambda, self-hosted, etc.)
```

### Job placement rule

One question: **does this job need local resources (ruflo, local fs, local MCP)?**
- Yes -> systemd
- No -> remotetrigger (/schedule)
- Session-scoped dev workflow -> /loop

No auto-failover needed. Most missed local jobs just run next cycle (`Persistent=true`).

## Research findings

- `/schedule` is a March 2026 Claude Code feature. Spawns fully isolated remote agents (CCR) in Anthropic's cloud on a cron schedule. Each run gets a fresh git checkout, Bash, Read/Write/Edit, and optional MCP connectors. Minimum 1-hour interval. Included in Pro ($20/mo) and Max ($100-200/mo) plans — burns tokens from plan allowance.
- `/loop` is local session-scoped cron. Runs while Claude Code session is open. Expires after 3 days. Good for dev workflows (watch tests, poll deploys), not for persistent ops.
- Current brana ops has 13 jobs on systemd timers (shipped, hardened). ~60% need local resources; ~40% are pure Claude skills that could run remotely today.
- Long-term: if ruflo becomes remotely accessible (remote MCP), ~90% of jobs could migrate to cloud.
- Cloud-first is the strategic direction: recurring tasks in the cloud, system accessible from any device, local for active development only.
- Vendor lock-in mitigated by the abstraction: brana is the interface, providers are swappable.

## Risks

- **Anthropic API changes** -> brana abstraction layer insulates user commands from provider changes
- **Token cost surprises** -> Phase 1 validates consumption with manual experiments before committing
- **Auth complexity** -> `/web-setup` is one-time; OAuth managed by Claude Code
- **/schedule feature instability** (new feature) -> keep systemd as fallback during Phases 1-3
- **No event-driven triggers** -> /schedule is cron-only, can't react to webhooks or events

## Phased rollout

### Phase 0 — Connect (hours)
- Run `/web-setup` to connect GitHub credentials
- Connect needed MCP connectors (Google Sheets, Slack, etc.) at claude.ai/settings/connectors

### Phase 1 — Manual /schedule experiments (days)
- Create 2-3 triggers manually via `/schedule` for skill-based jobs (weekly-review, knowledge-review)
- Validate: do they run reliably? Token consumption acceptable? Output quality?

### Phase 2 — Provider abstraction in brana ops (1-2 weeks)
- Add `provider` field to scheduler.json jobs: `"provider": "systemd" | "remotetrigger" | "loop"`
- `brana ops add --provider remotetrigger "weekly review"` -> calls RemoteTrigger API
- `brana ops status` -> queries all providers, unified output
- `brana ops health` -> aggregates health across tiers

### Phase 3 — Migrate eligible jobs (1 week)
- Move skill-based jobs to remotetrigger: knowledge-review, weekly-review, content-harvest, morning-check
- Keep local-dependent jobs on systemd: reindex-knowledge, sync-state, export-patterns, index-assumptions
- Validate stability over 2+ weeks

### Phase 4 — Cloud-first features (future)
- Cross-repo jobs: portfolio health checks across all client repos
- Client-specific monitors: proyecto_anita production checks, deployment validation
- Remote MCP ruflo access: migrate remaining local jobs to cloud
- Multi-provider support: add alternative cloud providers beyond Anthropic

## Field Notes

### 2026-03-30: Manual tasks → haiku triggers for automated monitoring
Manual/external monitoring tasks (e.g., "monitor token consumption for 1 week") can be fully automated with lightweight cloud triggers using haiku model. The trigger self-reports daily and auto-generates a summary after N days. Pattern: convert `execution: manual` observation tasks into cheap recurring triggers that produce their own deliverables.
Source: t-701 automation, session 2026-03-30

## Next steps

1. Run `/web-setup` to connect GitHub (prerequisite for everything)
2. Manually create one `/schedule` trigger to validate the feature works end-to-end
3. Track token consumption for 1 week to establish baseline
4. Design the `provider` field schema for scheduler.json
