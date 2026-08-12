---
title: The Brana WhatsApp Agent
status: idea
created: 2026-08-11
---

# The Brana WhatsApp Agent

> Brainstormed 2026-08-11. Status: idea.

## Problem

The Brana (the agency) has no WhatsApp presence of its own. Inbound prospects have
to be triaged manually; there's no fast, always-on channel for lead qualification,
and no way to demonstrate the agency's own WhatsApp-agent capability to prospects
short of describing past client work (anita, dgrx, las-lupes, mya, somos_mirada).
Separately, Martin has no low-friction way to interact with brana (capture ideas,
run skills, check backlog/pipeline) from his phone via a channel he already uses
constantly.

## Proposed solution

A WhatsApp number for The Brana with per-sender-identity behavior, built on the
existing session architecture from ADR-019 (Channel Adapters → Session Manager →
Brana Agent Runtime, tiered personas):

- **Unknown senders → SDR persona (Tier 2-ish, client-facing):** engages
  immediately, asks qualifying questions (BANT-style: budget, need, timeline,
  authority), captures context, and only surfaces qualified leads to Martin.
  Doubles as a live sales demo — a prospect talking to the agent *is* the pitch
  for "we build WhatsApp agents."
- **Martin's own number → Operator persona (Tier 3):** full brana access —
  capture-on-the-go (voice notes → `brana transcribe` → event-log, same shape as
  the Telegram pipeline in t-2306), backlog ops from the phone, ad-hoc skill
  invocation.
- **Future (post-sale clients, not v1):** support/bug intake → auto-creates a
  backlog task in the client's project; project status queries. This formalizes
  the WhatsApp/CRM automation work already sold as one-off client builds (t-2249's
  portfolio: anita, dgrx, las-lupes, mya, somos) into a reusable offering.

## Jobs to be done

- **Functional:** qualify + capture context on every inbound prospect so Martin
  only spends time on conversations worth having.
- **Emotional:** confidence that nothing falls through the cracks (never lose a
  lead) and the agency reads as responsive/professional 24/7.
- **Social:** prospects experience The Brana as already using the product it
  sells — proof by dogfooding, not claims.
- User confirmed all three (time savings, never-lose-a-lead, professional image)
  are in play, unprioritized as of this writing.

## Research findings

- **ADR-019** (accepted, from t-412) already specifies the exact architecture
  needed: Channel Adapters (Kapso for WhatsApp) → Session Manager (FastAPI +
  Postgres + Redis async queue) → Brana Agent Runtime (persona config, tiered
  data scoping). Tier 3 (operator) = Martin's own number; the SDR persona is a
  new Tier ~2 persona this ADR didn't yet define.
- **t-409** (completed): Kapso is the non-negotiable WhatsApp layer — already
  proven in `proyecto_anita` and `somos_mirada`. Session (user-initiated, 24h
  window) messages are free; only templates cost money. ~$45/mo at 10K
  conversations for a reactive design.
- **t-417** (pending, P3, under ph-013 Agent Chat Interfaces): "WhatsApp
  integration via Kapso" already exists in the backlog as the implementation
  task this idea feeds into.
- **External research (2026):** WhatsApp SDR bots converge on automating
  BANT/CHAMP qualification frameworks, instant engagement, and seamless
  bot-to-human handoff with full context once a lead qualifies.
  [Trengo](https://trengo.com/blog/whatsapp-lead-qualification),
  [Fin AI](https://fin.ai/learn/best-ai-sdr-tools),
  [mkt4edu](https://www.mkt4edu.com/en/blog/sdr-agents-on-whatsapp).
- **Existing vendoring pattern (t-1950/t-1952):** when a shared WhatsApp
  component needs to live in multiple places, the precedent is vendor-from-source
  (`anita-whatsapp` lives in `ventures/proyecto_anita/shared/`, vendored into
  `clients/proyecto-anita/dgrx`) rather than duplicating logic per client. If this
  agent is later productized and sold, The Brana's own instance stays canonical
  and client instances get vendored copies.

## Discussion & decisions

- **Scope classification:** internal thebrana tooling — not a venture. This is
  the agency's own operating infrastructure, same category as other `system/`
  tooling (confirmed by user).
- **Challenge (Round 1):** the initial framing assumed building the full ADR-019
  session-manager stack (Postgres, async queue, 3-tier system) before validating
  whether the SDR persona even works. User agreed this was over-scoped for a
  first pass.
- **Two scoped-down alternatives compared:**
  - *A — Kapso-native flow:* fastest (days), zero brana infra touched, but the
    conversation never enters brana memory/skills — and critically, if this
    agent is meant to prove "we build WhatsApp agents" to prospects, it would be
    demoing Kapso's product, not The Brana's.
  - *B — Minimal brana bridge:* ~1 week, thin webhook + hardcoded SDR persona +
    integration with existing event-log/backlog patterns (t-1661, t-2306). Stays
    inside brana's world; promotable to the full ADR-019 stack later without a
    rewrite; **usable as sales proof** since it's actually The Brana's own
    architecture running.
  - **Decision driver:** user's plan to eventually sell WhatsApp agents to
    clients tips this decisively toward **Option B** — dogfooding your own
    product is the point.
- **Placement:**
  - *Code:* `thebrana/system/` (e.g. `system/services/whatsapp-bridge/`) —
    internal agency infra, not a venture or client engagement.
  - *Runtime:* **oracle-hub** — the existing always-on box already running the
    Telegram bot + cron jobs (t-2306). The WhatsApp bridge needs to be up 24/7
    independent of a laptop session; this is the same shape as already-solved
    problems there.
  - *Data:* conversations route into brana's existing event-log/knowledge
    pipeline, scoped by persona (lead conversations tagged separately from
    Martin's Tier-3 personal captures).
  - *If productized later:* extract and vendor into client repos, following the
    `anita-whatsapp` precedent — not duplicated per client.

## Risks

- **Scope creep into the full ADR-019 stack before validation** — mitigated by
  choosing Option B (minimal bridge) as the v1 build, deferring Postgres/async
  queue/full tier system until the SDR persona is proven.
- **Unprioritized success metrics** (time saved vs. never-lose-a-lead vs.
  professional image) risk building the wrong v1 measurement — needs
  prioritization before backlog planning locks scope.
- **Pre-mortem (user confirmed both as real concerns):**
  - *Silent technical failure* — the oracle-hub bridge crashes or the Kapso
    webhook silently stops firing and nobody notices for days (a failure mode
    already documented elsewhere in this repo: silent loss needs an active
    check, not just a watchdog). Mitigation: v1 needs a dead-man's-switch/health
    check that alerts Martin via a channel *other than* the bridge itself if it
    goes quiet.
  - *Dogfooding never converts to a sale* — the bridge works and even gets used,
    but "sell WhatsApp agents as a service" stays a stated intention and never
    becomes a packaged offering, leaving infra maintained for an ROI that never
    materialized. Mitigation: make "package as a sellable offering" an explicit
    tracked checkpoint task after the bridge is validated, not an implicit
    assumption.

## Next steps

1. Prioritize success metrics (time-to-response vs. lead quality vs. personal
   leverage) — currently unranked.
2. Write the SDR persona config (system prompt, BANT-style qualifying questions,
   handoff trigger) as a concrete artifact.
3. Scope the minimal brana bridge (Option B) as a buildable task: webhook
   receiver, Kapso wiring, event-log integration, oracle-hub deployment.
4. Decide whether this feeds into existing t-417 (WhatsApp integration via
   Kapso) or becomes its own task tree under ph-013.
