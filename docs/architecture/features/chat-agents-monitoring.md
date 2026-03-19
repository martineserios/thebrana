# Feature: Chat-Agents Monitoring & Logging

**Date:** 2026-03-16
**Status:** investigation
**Task:** t-422
**ADR:** [ADR-019](../decisions/ADR-019-brana-chat-sessions.md)
**Siblings:** t-420 (cost tracking), t-421 (security audit)

## Goal

Define the monitoring architecture for brana chat-agents (ADR-019). The Session Manager doesn't exist yet — this document specifies what to build when it does. Covers all 5 areas from the ADR scope: structured logging, error tracking, latency metrics, health checks, alerting on anomalies.

## Current State Inventory

Brana already has a layered monitoring system for CLI sessions. Chat-agents monitoring should extend these patterns rather than reinvent them.

### What Brana Monitors Today

| Layer | What | How | Retention |
|-------|------|-----|-----------|
| **Session events** | Tool invocations, outcomes (success/failure/correction/cascade) | `post-tool-use.sh` → `/tmp/brana-session-*.jsonl` | Per-session (deleted at end) |
| **Flywheel metrics** | correction_rate, test_write_rate, cascade_rate, auto_fix_rate | `session-end.sh` → `brana ops metrics` (Rust) | Permanent (decisions/*.jsonl) |
| **Decision log** | Concerns, findings, challenger output | Hooks → JSONL with 30-day archive | Permanent |
| **Cascade detection** | 3+ consecutive failures on same target | `post-tool-use-failure.sh` → flag files | Per-session |
| **Scheduler health** | Job status, drift, collisions, failure notifications | `brana ops status/health/drift/collisions` | Live queries + last-status.json |
| **System health** | 8-point check (git, tasks, scheduler, ruflo, bootstrap) | `brana doctor` | On-demand |

### Key Design Patterns to Reuse

1. **Append-only JSONL** — No locks, safe concurrent writes, full audit trail
2. **Immediate return, background processing** — Hooks return `{"continue": true}` before computing metrics
3. **Ephemeral + persistent split** — Raw events in `/tmp`, aggregated metrics in git-tracked state
4. **CLI as query layer** — No daemon; all checks are synchronous reads of JSON state files
5. **Graceful degradation** — Rust binary unavailable → fall back to Bash+jq

## Gap Analysis

### What Chat-Agents Needs (Not Covered by Existing Monitoring)

| Gap | Why It Matters | ADR-019 Reference |
|-----|---------------|-------------------|
| **Conversation-level logging** | Session lifecycle (create/resume/close), message history, token counts per turn | Lines 57, 143 — Postgres persistence |
| **Latency metrics (TTFT, roundtrip)** | Chat UX degrades noticeably above 3s; need p50/p95/p99 per tier | Phase 4, t-422 scope |
| **Per-channel health checks** | Kapso webhook responsiveness, Claude API availability, Redis queue depth | Line 140 — `GET /health` |
| **Alerting on anomalies** | Error rate spikes, latency degradation, budget breaches | Phase 4, t-422 scope |
| **Cost-per-conversation tracking** | Token spend attribution by persona/tier/user | Phase 4, t-420 scope |
| **Tier enforcement audit** | Blocked tool calls, data scope violations | Lines 187-193 — security boundary |
| **Async queue observability** | Worker lag, queue depth, dead letters | Lines 144-145 — Redis + RQ/Celery |
| **Model routing decisions** | Complexity scores, model selection patterns (Tier 3 only) | Line 196 — ADR-018 scoring |
| **Prompt cache hit rate** | Cost optimization validation (10% savings on hit) | Line 150 — prompt caching |

## Recommended Monitoring Architecture

### Three-Level Logging Hierarchy

Chat-agents monitoring uses a **conversation → message → span** hierarchy with correlation IDs for drill-down.

```
conversation_id (session lifecycle)
  └── message_id (per user/assistant turn)
        └── trace_id (per LLM API call, tool invocation, or external call)
```

#### Level 1: Conversation Log (Persistent — Postgres)

Already specified in ADR-019 (lines 57, 143). Each session row tracks:

```
session_id, persona, user_id, channel, tier,
created_at, last_active_at, closed_at, close_reason,
total_tokens_in, total_tokens_out, total_cost,
message_count, budget_consumed_pct
```

**Close reasons:** explicit, timeout, budget_exhaustion, error.

#### Level 2: Message Log (Persistent — Postgres)

Each message within a conversation:

```
message_id, session_id, role (user|assistant|system),
content_hash, token_count_in, token_count_out,
model_used, cache_hit (bool), latency_ms,
tool_calls (jsonb), error (jsonb|null),
created_at
```

No raw content stored by default (privacy). Content stored only for Tier 3 (operator) sessions or when debug mode is enabled. Content hash allows deduplication checks.

#### Level 3: Span Log (Ephemeral — JSONL, same pattern as CLI sessions)

Per-request detail for debugging. Follows OpenTelemetry GenAI semantic conventions (`gen_ai.*` namespace):

```jsonl
{"trace_id":"...","span":"llm_call","model":"claude-sonnet-4-20250514","tokens_in":1200,"tokens_out":340,"cache_hit":true,"latency_ms":1850,"ttft_ms":420,"timestamp":"..."}
{"trace_id":"...","span":"tool_call","tool":"ruflo_memory_search","latency_ms":45,"result":"ok","timestamp":"..."}
{"trace_id":"...","span":"webhook_callback","channel":"kapso","latency_ms":120,"status":200,"timestamp":"..."}
```

**Retention:** Ephemeral by default (same `/tmp/` pattern as CLI sessions). Promoted to persistent storage on error or when latency exceeds p99 threshold.

### Metrics

#### Core Metrics (5 metrics cover 80% of production issues)

| Metric | Measurement | Alert Threshold |
|--------|-------------|-----------------|
| **TTFT** (Time to First Token) | p50, p95, p99 per tier | p99 > 5s (Tier 1), > 8s (Tier 2/3) |
| **Roundtrip latency** | Message received → response sent | p99 > 10s (Tier 1), > 30s (Tier 2/3) |
| **Error rate** | Errors / total requests, 5-min rolling | > 5% sustained 10 min |
| **Queue depth** | Pending messages in async queue | > 50 (Tier 1), > 20 (Tier 2/3) |
| **Cache hit rate** | Prompt cache hits / total LLM calls | < 30% (investigate persona configs) |

#### Per-Tier Metrics

| Metric | Tier 1 (End User) | Tier 2 (Client) | Tier 3 (Operator) |
|--------|-------------------|-----------------|-------------------|
| Active sessions | Count, per-persona | Count, per-client | Count (always low) |
| Token budget usage | % of daily limit | % of session + daily | N/A (unlimited) |
| Model distribution | 100% Haiku | 100% Sonnet | Haiku/Sonnet/Opus split |
| Tool call volume | KB lookups only | Actions + KB | Full skill usage |

#### Channel Adapter Metrics

| Metric | Source | Purpose |
|--------|--------|---------|
| Webhook delivery success rate | Kapso API | Detect auto-pause risk (>85% failure triggers pause) |
| Webhook response time | Adapter timing | Must return < 10s (Kapso requirement) |
| Message status flow | sent → delivered → read → failed | Delivery health per phone number |
| Template failure rate | Kapso Broadcasts API | Campaign health |
| 24h window violations | Error 131047 count | Re-engagement policy compliance |

### Health Checks

#### `GET /health` — Liveness + Readiness

```json
{
  "status": "healthy",
  "checks": {
    "database": {"status": "ok", "latency_ms": 12},
    "claude_api": {"status": "ok", "latency_ms": 850, "last_checked": "..."},
    "redis_queue": {"status": "ok", "depth": 3},
    "ruflo_mcp": {"status": "ok", "latency_ms": 45}
  },
  "version": "0.1.0",
  "uptime_s": 86400
}
```

**Design decisions:**
- Claude API health check: cached probe every 60s (avoid cost of real calls)
- Separate `/health/live` (is the process running?) from `/health/ready` (can it serve traffic?) for container orchestration
- Each adapter gets its own health sub-check (Kapso webhook subscription status, Web widget SSE connection count)

#### `brana ops` Extension

Extend the existing `brana ops` CLI to query chat-agents health:

```
brana ops chat status          → Active sessions by tier/channel, queue depth
brana ops chat health          → Error rates, latency percentiles, budget warnings
brana ops chat sessions [--tier N] → List active sessions with token usage
```

This follows the established pattern: CLI reads JSON state files, no daemon required. The Session Manager writes state to a known path; the CLI reads it.

### Error Tracking

#### Error Categories (extends CLI cascade detection pattern)

| Category | Examples | Severity | Action |
|----------|----------|----------|--------|
| **LLM errors** | Rate limit, timeout, malformed response | High | Retry with backoff, route to fallback model |
| **Tool errors** | MCP server down, tool execution failure | Medium | Log, skip tool, inform user |
| **Channel errors** | Webhook delivery failure, template rejection | Medium | Retry per channel policy (Kapso: 4 retries over ~2.5 min) |
| **Budget errors** | Session/user/daily limit exceeded | Low | Alert at 80%, hard stop at 100% |
| **Security events** | Tier enforcement block, data scope violation, prompt injection attempt | High | Log full context, alert immediately |
| **Queue errors** | Worker crash, dead letter, timeout | High | Alert, auto-restart worker |

#### Cascade Detection for Chat

Adapt the CLI cascade pattern (3+ consecutive failures → flag) to chat context:
- 3+ LLM errors on same session → pause session, notify operator
- 5+ webhook delivery failures → check Kapso auto-pause status
- Budget breach on 3+ users in same tier → investigate persona config

### Alerting

#### Alert Tiers

| Priority | Condition | Channel | Response |
|----------|-----------|---------|----------|
| **P1 — Page** | Claude API down, all sessions failing, queue overflow | Desktop notification + event log | Investigate immediately |
| **P2 — Warn** | Latency p99 > 2x normal, error rate > 5%, budget breach | Event log + status file | Investigate within 1 hour |
| **P3 — Info** | Cache hit rate drop, model routing anomaly, session count spike | Event log only | Review at next session |

**Implementation:** Same pattern as scheduler notifications — write to `last-status.json` (primary), best-effort `notify-send` (secondary). No external alerting service needed for single-operator scale.

#### Anomaly Detection (deferred to v2)

For v1, use static thresholds (table above). When conversation volume grows beyond manual review:
- Latency: rolling p99 vs 7-day baseline, alert on >30% deviation
- Cost: daily spend vs projected budget, alert on >30% overshoot
- Error rate: 5-min rolling vs 1-hour baseline

## Integration with Sibling Tasks

### t-420: Cost Tracking

Monitoring provides the raw data; cost tracking consumes it.

| Monitoring Emits | Cost Tracking Consumes |
|-----------------|----------------------|
| `tokens_in`, `tokens_out` per message | Per-conversation cost (tokens × model rate) |
| `model_used` per message | Cost breakdown by model tier |
| `cache_hit` per LLM call | Cache savings calculation |
| `session_id` + `persona` + `tier` | Attribution by persona/tier/user |
| Budget `consumed_pct` | Alert at 80%, dashboard rollup |

**Shared schema:** Message log (Level 2) contains all fields needed for cost computation. Cost tracking adds a `cost_usd` computed column — no separate data pipeline.

### t-421: Security Audit

Monitoring provides the audit trail; security defines what to watch for.

| Monitoring Emits | Security Consumes |
|-----------------|-------------------|
| Tier enforcement blocks | Unauthorized access attempts |
| Data scope violations | Cross-client data leaks |
| Tool call validation failures | Prompt injection detection |
| Content hashes (Level 2) | Output filtering compliance |
| Session lifecycle events | Session hijacking detection |

**Shared schema:** Security events are a subset of the span log (Level 3) with `category: "security"`. Security audit defines the detection rules; monitoring logs and alerts on matches.

## Implementation Priority

### Phase 1 — Build with Session Manager (t-413, t-414)

These are free — they're part of the data model, not separate infrastructure.

- [ ] Conversation log schema (Level 1) in Postgres
- [ ] Message log schema (Level 2) in Postgres
- [ ] `GET /health` endpoint (liveness + readiness)
- [ ] Token counting per message (input + output)
- [ ] Session lifecycle events (create, resume, close with reason)

### Phase 2 — Build with Auth & Personas (t-415, t-416)

- [ ] Budget tracking (consumed_pct, alert at 80%)
- [ ] Tier enforcement logging (blocked calls with full context)
- [ ] Model routing decision logging (Tier 3 only)
- [ ] Per-tier metric aggregation

### Phase 3 — Build with Channel Adapters (t-417, t-418, t-419)

- [ ] Span logging (Level 3, ephemeral JSONL)
- [ ] Webhook delivery tracking (Kapso adapter)
- [ ] Channel-specific health sub-checks
- [ ] Adapter latency measurement

### Phase 4 — Hardening (t-422 implementation)

- [ ] `brana ops chat` CLI extension
- [ ] Latency percentile computation (p50/p95/p99)
- [ ] Static threshold alerting (P1/P2/P3)
- [ ] Cache hit rate tracking
- [ ] Error cascade detection for chat sessions
- [ ] Queue depth monitoring
- [ ] Span promotion (ephemeral → persistent on error)

### Deferred (v2)

- Anomaly detection (rolling baselines, statistical alerting)
- Web dashboard for conversation metrics
- Cross-session aggregation and trend analysis
- OpenTelemetry export (Datadog/Grafana integration)
- Slack/email alerting channels

## Design Principles

1. **Instrument at creation, not after.** Logging goes into the Session Manager from day one. Phase 4 adds dashboards and alerting on top of data that already exists.
2. **Reuse brana patterns.** JSONL for ephemeral spans, CLI for queries, `last-status.json` for alerts. No new infrastructure paradigms.
3. **Privacy by default.** Message content hashed, not stored (except Tier 3 or debug mode). Token counts and metadata are always stored.
4. **Cost-aware monitoring.** Claude API health checks are cached (60s), not per-request. Span logs are ephemeral unless promoted. No monitoring database — Postgres (already needed for conversations) handles everything.
5. **Single-operator scale.** Desktop notifications, CLI queries, event log. No Grafana, no PagerDuty, no external services. Scale up when conversation volume demands it.
