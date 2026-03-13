# ADR-019: Brana Chat Sessions — Channel-Agnostic Agent Interface

**Date:** 2026-03-13
**Status:** accepted
**Related:** ADR-003 (agent execution), ADR-018 (model routing), dim-36 (claw ecosystem), dim-39 (Kapso), ph-013, t-412

## Context

Brana currently operates only through Claude Code CLI sessions. The goal is to interact with brana agents — and agents built on brana — through WhatsApp, web chat, and other channels. These aren't generic chatbots. Each conversation is a **persistent brana session** with access to:

- Skills and commands from the brana system
- Memory (ruflo/claude-flow) for cross-session recall
- Scoped data (client-specific, persona-specific)
- MCP tools and integrations

Three types of users need access at different trust levels:

| User type | Example | Trust | Volume | Needs |
|-----------|---------|-------|--------|-------|
| **End users** | Somos patients, TinyHomes guests | Low | High | KB queries, simple actions |
| **Clients** | Business owners we work with | Medium | Medium | KB + actions (book, send, update CRM) |
| **Operator** | Martin | Full | Low | Full brana (skills, memory, git, admin) |

### Constraints

- WhatsApp is the primary channel, via **Kapso** (non-negotiable — already in production for proyecto_anita and somos_mirada, [dim doc 39](~/enter_thebrana/brana-knowledge/dimensions/39-kapso-ai-platform.md))
- Must be channel-agnostic: WhatsApp first, but the session layer must not couple to any channel
- Claude API is pay-per-token (no subscription bridge for programmatic access)
- Cost control is critical: prompt caching, model routing, and session management reduce spend by 60-90%
- Security: each session needs data scoping (a somos agent must not access anita data)
- Build generic first, specialize later — broad infrastructure before client-specific personas

### Framework landscape (March 2026)

| Framework | Channels | Security | Fit |
|-----------|----------|----------|-----|
| **Kapso** | WhatsApp (SaaS) | Managed | Our WhatsApp delivery layer |
| **ZeroClaw** | 15+ (Telegram, Discord, Slack, Matrix, etc.) | WASM sandbox | Multi-channel runtime (future) |
| **NanoClaw** | WhatsApp only | Docker containers | Per-client isolation |
| **OpenClaw** | 8+ | DISQUALIFIED (CVE-2026-25253, 42K exposed) | — |
| **gokapso/claude-code-whatsapp** | WhatsApp | E2B sandbox | Reference implementation |

## Decision

### Architecture: 3 layers

```
┌─────────────────────────────────────────────────┐
│                 Channel Adapters                 │
│  Kapso (WhatsApp)  │  Web Widget  │  CLI  │ ... │
└────────────┬───────────────┬──────────┬─────────┘
             │               │          │
             ▼               ▼          ▼
┌─────────────────────────────────────────────────┐
│              Session Manager (API)               │
│  - Session CRUD (create, resume, close)          │
│  - Conversation persistence (Postgres)           │
│  - Tier-based access control                     │
│  - Token budget per session/user/tier            │
│  - Context window management (sliding + summary) │
│  - Async queue (inbound msg → agent response)    │
└────────────────────────┬────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────┐
│              Brana Agent Runtime                  │
│  - Claude API (Anthropic SDK)                    │
│  - Persona config (system prompt, tools, scope)  │
│  - MCP tools (ruflo memory, knowledge base)      │
│  - Tiered data scoping (client/project isolation) │
│  - Prompt caching + model routing (ADR-018)      │
└─────────────────────────────────────────────────┘
```

### Tiered Access Model

Each persona belongs to a tier. The tier determines the capability ceiling — what tools, data, memory, and models are available.

```
┌──────────┬──────────────┬───────────────────────────────┐
│  Tier 1  │  Tier 2      │  Tier 3                       │
│  End User│  Client      │  Operator                     │
├──────────┼──────────────┼───────────────────────────────┤
│ KB query │ KB + actions  │ Full brana (skills, memory,   │
│ Scoped   │ Scoped        │ git, cross-client, admin)     │
│ No cross-│ Session       │ Cross-session memory          │
│ session  │ memory        │ (personal assistant)          │
│ memory   │               │                               │
│ Haiku    │ Sonnet        │ Sonnet/Opus routing           │
│ Low cost │ Medium cost   │ Full cost                     │
│ High vol │ Medium vol    │ Low volume                    │
└──────────┴──────────────┴───────────────────────────────┘
```

**Tier 1 — End Users** (somos patients, tinyhomes guests):
- Read-only knowledge base queries via ruflo memory_search
- Scoped to one client's data namespace
- No conversation memory across sessions (privacy by default)
- Haiku model only (cheapest, fastest)
- Strict token budget (low per-message, low per-day)
- No tool execution beyond KB lookup

**Tier 2 — Clients** (business owners):
- Knowledge base + action tools (Kapso send_template, Google Sheets read/write, webhook calls)
- Scoped to their client data
- Session memory — remembers within one conversation, forgets between conversations
- Sonnet model (quality for business decisions)
- Medium token budget
- MCP tools as defined in persona config

**Tier 3 — Operator** (Martin):
- Full brana skill access (/research, /review, /backlog, etc.)
- Cross-client access, admin tools
- Cross-session memory — personal assistant that remembers everything via ruflo
- Sonnet/Opus per-message routing (ADR-018 scoring)
- No token budget limit (or very high)
- All MCP tools, file access, git operations

### Layer 1: Channel Adapters

Each channel adapter translates between a channel's message format and the Session Manager's unified API. Adapters are stateless — they receive a message, call the Session Manager, and forward the response back.

| Channel | Adapter | How |
|---------|---------|-----|
| **WhatsApp** | Kapso | Kapso webhook → Session Manager. Kapso handles Meta API, templates, media. Use Kapso Builder SDK for flow definitions. |
| **Web** | Custom widget | Minimal React/vanilla JS chat widget. WebSocket or SSE for streaming. Embeddable via script tag. |
| **CLI** | Terminal | readline-based or rich terminal. For dev/testing. |
| **Future** | ZeroClaw or custom | Telegram, Discord, Slack. Revisit when needed — ZeroClaw's trait system makes this pluggable. |

### Layer 2: Session Manager

FastAPI server. The central orchestrator.

```
POST   /sessions                — create session (persona, user, channel)
POST   /sessions/{id}/message   — send message, get response (202 Accepted + async)
GET    /sessions/{id}           — session state + history
DELETE /sessions/{id}           — close session
GET    /sessions/{id}/stream    — SSE stream for real-time responses (web widget)
GET    /health                  — health check
```

**Conversation persistence:** Postgres. Each message stored with role, content, token count, timestamp. Session metadata: persona, user, channel, tier, token budget consumed, created/last_active.

**Async processing:** Inbound messages enqueue to a task queue (Redis + RQ or Celery). Worker picks up, calls Claude API, stores response, notifies channel adapter via webhook/callback. Non-blocking — channel adapters get immediate 202 Accepted.

**Context window management:**
- Sliding window: keep last N messages in context (N varies by tier)
- Auto-summarize: when approaching context limit, summarize older messages into a compact block
- Prompt caching: system prompt + persona config cached (10% of input cost on cache hit)

**Token budgets:** Per-session and per-user daily limits. Configurable per tier and per persona. Alert at 80%, hard stop at 100%. Tier 3 (operator) gets no hard limit.

**Session lifecycle:**
- Create: on first message from a user+channel+persona combo
- Resume: on subsequent messages within timeout window (configurable per tier)
- Close: on explicit close, timeout, or budget exhaustion
- Memory flush: on close, Tier 2 forgets; Tier 3 stores summary to ruflo

### Layer 3: Brana Agent Runtime

The agent that runs within each session. NOT a generic LLM wrapper — a brana-powered agent with tier-enforced capabilities.

**Persona config** (YAML per persona):
```yaml
name: somos-assistant
tier: 2  # client tier
system_prompt: "You are a medical practice assistant for Somos Mirada..."
model: sonnet
tools:
  - ruflo_memory_search
  - kapso_send_template
  - google_sheets_read
data_scope:
  client: somos_mirada
  knowledge_namespaces:
    - knowledge
    - client:somos
memory_policy: session  # none | session | persistent
budget:
  max_tokens_per_response: 4096
  max_tokens_per_session: 50000
  max_tokens_per_day: 200000
temperature: 0.3
```

**Tier enforcement:** The runtime validates every tool call against the persona's tier and tool allowlist. A Tier 1 persona cannot invoke `kapso_send_template` even if someone crafts a prompt injection requesting it. Enforcement happens at the Session Manager level (before the tool call reaches the MCP server), not at the LLM level.

**Data scoping:** Each persona defines which client data it can access. Scoping happens at the MCP tool level:
- ruflo: namespace filtering (only query allowed namespaces)
- File tools: path filtering (only read allowed paths)
- Kapso: phone number / account scoping

**MCP integration:** The agent runtime connects to ruflo's MCP server for memory search/store, and can use any MCP tools defined in the persona config. This is how brana knowledge flows into chat sessions.

**Model routing:** Tier 1 is locked to haiku. Tier 2 defaults to sonnet. Tier 3 uses per-message complexity scoring from ADR-018 (haiku → sonnet → opus).

### WhatsApp-specific: Kapso integration

```
User sends WhatsApp msg
  → Kapso webhook fires
  → Kapso flow routes to our webhook endpoint
  → POST /sessions/{id}/message
  → Session Manager enqueues (tier-aware)
  → Worker calls Claude API with persona context
  → Response stored + sent back via Kapso API
  → User sees reply in WhatsApp
```

**Cost optimization for WhatsApp:**
- Session messages (user-initiated, 24h window) = FREE on WhatsApp
- Design agents to be reactive — respond to user messages, don't proactively initiate
- Template messages (proactive) only for scheduled reminders, appointment confirmations
- Per-message pricing since July 2025: marketing $0.025-$0.14, utility $0.004-$0.05
- Estimated cost at 10K conversations/month (80% reactive): ~$45/mo WhatsApp + ~$200/mo Claude API (Sonnet)

### Hosting

Deferred — not locked in this ADR. Build containerized (Docker Compose), deploy anywhere. Candidates: Hetzner VPS (cheap, known), Railway (zero-ops), serverless (Lambda/Cloud Run for Tier 1 scale).

### What we DON'T build

- **Not a claw framework.** We build a session manager + channel adapters. If ZeroClaw matures, we can use it as an adapter layer later.
- **Not a chatbot builder.** Personas are config files, not a visual builder (Kapso handles that for WhatsApp flows).
- **Not multi-tenant SaaS yet.** Start with one deployment, persona-level scoping. Design so that client self-service (Tier 2 users creating their own personas via dashboard) can be added later without rewriting the core.

## Alternatives Considered

### A. ZeroClaw + Kapso
ZeroClaw as multi-channel runtime, Kapso for WhatsApp delivery. **Rejected for now** — ZeroClaw is Rust (different stack), newly released (3.4K stars), and adds complexity. Revisit when it matures or when we need 10+ channels.

### B. NanoClaw + Kapso
NanoClaw for Docker isolation per client, Kapso for WhatsApp. **Rejected** — NanoClaw is WhatsApp-only (same as Kapso), and its container-per-conversation model is overkill when tier-based scoping suffices.

### C. Kapso standalone
Use Kapso workflows and AI agents directly, no custom backend. **Rejected as sole solution** — Kapso doesn't support non-WhatsApp channels, and its AI agents don't have access to brana's skill/memory system. But Kapso IS the WhatsApp adapter.

### D. Fork gokapso/claude-code-whatsapp
Replace E2B with claude-flow, keep Kapso delivery. **Partially adopted** — the reference implementation informs our Kapso adapter design, but we build our own session manager rather than forking.

### E. Tier 3 first (operator-only MVP)
Build the most complex tier first, simplify down. **Rejected** — contradicts "generic to specific" principle. The session infrastructure is the same for all tiers; tiers are just config. Build the generic plumbing, then add tier-specific features.

## Consequences

- **Positive:** Channel-agnostic from day one. Adding a new channel = writing one adapter.
- **Positive:** Tiered access scales from simple KB bots to full brana operator access — same infrastructure, different config.
- **Positive:** Cost-controlled via tier-based budgets, prompt caching, model routing. WhatsApp reactive design minimizes messaging costs.
- **Positive:** Designed for growth — client self-service can be added without rewriting the core.
- **Negative:** Custom session manager is more work than adopting a framework. Justified by the unique requirement (brana system access + tiered scoping).
- **Negative:** Claude API dependency — no subscription bridge means variable costs. Mitigated by caching + routing + budgets.
- **Risk:** Kapso is a startup (Platanus-backed, solo founder). Mitigation: Kapso is the WhatsApp adapter, not the core. If Kapso disappears, swap adapter to 360dialog or direct Meta Cloud API.

## Implementation Plan — Generic to Specific

Build the infrastructure first, then specialize.

### Phase 1: Generic infrastructure (ms-048)
1. **Session Manager MVP** (t-413) — FastAPI server, session CRUD, Postgres storage
2. **Conversation persistence** (t-414) — message storage, history loading, context window management
3. **Auth + budgets** (t-415) — API key auth, per-session token tracking, tier-based limits

### Phase 2: Agent runtime + personas (ms-048 continued)
4. **Persona system** (t-416) — YAML config loader, tier enforcement, tool allowlisting, data scope validation

### Phase 3: Channel adapters (ms-049)
5. **Kapso adapter** (t-417) — WhatsApp webhook bridge via Kapso Builder SDK
6. **Web widget** (t-418) — embeddable chat, SSE streaming
7. **CLI chat** (t-419) — terminal interface for dev/testing

### Phase 4: Hardening (ms-050)
8. **Cost tracking** (t-420) — per-conversation token usage, budget dashboards
9. **Security** (t-421) — prompt injection defense, output filtering, OWASP LLM Top 10 review
10. **Monitoring** (t-422) — structured logging, error tracking, latency metrics, health checks
