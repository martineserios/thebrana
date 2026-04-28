# Portfolio

## Cross-Client Knowledge

| Topic | File | Relevant Clients |
|-------|------|------------------|
| Brainstorm governance gate for M+ efforts | `feedback_brainstorm_governance_gate.md` | brana (skill dev), all clients using brainstorm |
| Meta WhatsApp template classification formula | `meta-whatsapp-templates.md` | somos_mirada, proyecto_anita, any WhatsApp client |
| Railway.com platform evaluation (PaaS pricing, limits, regions) | `nexeye_eyedetect/docs/infrastructure/railway-platform-evaluation.md` | any client evaluating PaaS hosting |
| Client retention & engagement systems (flywheel, welcome kits, QR portals, referral reframing) | `brana-knowledge/dimensions/client-retention-engagement.md` | tinyhomes, any recurring-client service |
| SMB marketing channels & content strategy (GEO, WhatsApp, landing pages, SEO, B2B2C, regulated products) | `brana-knowledge/dimensions/smb-marketing-channels.md` | somos_mirada, proyecto_anita, tinyhomes, any SMB |
| Kapso AI platform (CLI, Builder SDK, agents, flows, functions, MCP, TypeScript SDK) | `brana-knowledge/dimensions/39-kapso-ai-platform.md` | proyecto_anita, somos_mirada, brapsoclaw, mya, any WhatsApp automation client |
| Respond.io platform (AI Agents, Workflows, Variables, MCP, HTTP Requests, plan gates) | `brana-knowledge/dimensions/50-respond-io-platform.md` | somos_mirada, any omnichannel CRM + AI automation client |
| YCloud WhatsApp BSP (Premier partner, pricing, per-recipient API shape, Kapso contrast, Meta 2026 pricing shift) | `brana-knowledge/dimensions/52-ycloud-whatsapp-platform.md` | proyecto_anita, somos_mirada, mya, brapsoclaw, any WhatsApp BSP decision |
| Chatwoot platform (OSS omnichannel inbox, self-hosted, 4 API layers, API Channel bridge pattern, Kapso integration paths A/B/C, Captain AI, pricing 2026) | `brana-knowledge/dimensions/51-chatwoot-platform.md` | proyecto_anita (Palco, Las Lupes, inbox-demanding tenants), any project needing self-hosted inbox vs Intercom/Zendesk/Respond.io |
| Bigin CRM platform (Zoho's CRM-lite, OAuth Self-Client, Bulk Write API, COQL queries, custom fields, Anita integration patterns A/B/C, weak webhook retry workarounds) | `brana-knowledge/dimensions/53-bigin-crm-platform.md` | proyecto_anita (DGRX simil-CRM target, any tenant needing CRM UI on top of Anita+Kapso), mya, any Anita tenant where insight extraction writes to a managed CRM |
| Glide as MVP backend (Tables + UI + API eliminates Postgres/admin/auth for pilots) | `clients/mya/docs/ideas/mvp-architecture.md` | mya, any B2B2C MVP |
| Lovable → Claude Code handoff (30 min scaffold, GitHub push, Claude wires APIs) | `clients/mya/docs/ideas/mvp-architecture.md` | mya, any frontend-heavy client |
| NanoClaw/ZeroClaw/Claw ecosystem (architecture, Docker isolation, Agent SDK) | `brana-knowledge/dimensions/36-claw-ecosystem-chat-interface.md` | brapsoclaw, any chat agent project |
| WhatsApp Difusiones Comerciales (Meta nativo ~2025, $0.0618/msg, sin scheduling/Excel/métricas) | `ventures/proyecto_anita/memory/event-log.md` | proyecto_anita, somos_mirada, mya, brapsoclaw |
| LLM agent test strategy patterns (tests don't make agents good · replay-based shadow · defer structural guards) | `llm-agent-test-strategy-patterns.md` | proyecto_anita (Agent v4), mya, brapsoclaw, somos_mirada, any LLM agent shipping to prod |
| 3-repeat rule for skill codification (build skills from observed usage, not upfront design) | `feedback_3repeat_skill_codification.md` | brana (skill dev), all projects building tools/agents |
| Reverse-eval for taste training (find flaws in flawed AI artifacts beats producing polished ones) | `feedback_reverse_eval_for_taste.md` | personal/growth, brana (PR review), any taste-driven discipline |
| Coach mode switching — silent during baseline, Socratic during work | `feedback_coach_mode_switching.md` | personal/growth, ai-native-education, any agent combining eval + coaching |

## Clients (paid work — external stakeholder)

For detailed facts, read each client's own docs. This is a routing index only.

### brana (enter_thebrana)
- **Type:** AI development system (brain for Claude Code)
- **Repos:** `enter` (architect), `thebrana` (operator), `brana-knowledge` (vault)
- **Details:** `thebrana/CLAUDE.md`, `enter/18-menu-driven-roadmap.md`

### mya (MirÁyAhorrÁ)
- **Type:** B2B2C hyperlocal promo platform — dietéticas/almacenes channel, AMBA
- **Projects:** mya (`clients/mya`)
- **Status:** Aligned 2026-04-14. P0 kickoff next. Score: 10/20 (Standard tier).
- **Stack:** Next.js 14 + Prisma + PostgreSQL+PostGIS + Kapso + Railway + Cloudflare R2
- **Alignment report:** `clients/mya/.claude/alignment-report.md`
- **Details:** `clients/mya/docs/scope-v1.md`, `clients/mya/docs/decisions/ADR-001-tech-stack.md`

### nexeye (NexeyeTech)
- **Type:** Eye detection product
- **Projects:** eyedetect (`clients/nexeye_eyedetect`)
- **Details:** `.claude/session-handoff.md`

### somos (Somos Mirada)
- **Type:** CRM + AI automation for surgical practice
- **Projects:** somos_mirada (`clients/somos_mirada`)
- **Details:** `features/meta-account-hygiene/proposal.md`


### prof_man
- **Type:** Code product — trading indicators & algo trading
- **Domain:** Trading (TradingView indicators now, Python bots + alert-to-execution later)
- **Stack:** Pine Script (TradingView) → Python (ccxt, exchange APIs) later
- **Projects:** prof_man (`clients/prof_man`)
- **Remote:** `https://github.com/martineserios/prof_man`
- **Client:** External (not personal venture)
- **Status:** Starting — 2026-04-01
- **Goal:** Personal trading edge for the client; build indicators, eventually automate

### mandawa
- **Type:** Paid client
- **Projects:** mandawa (`clients/mandawa`)

## Ventures (your IP — side projects, learning, monetizing)

### anita (Proyecto Anita)
- **Type:** Venture — multi-tenant WhatsApp campaign management platform (SaaS)
- **Location:** `~/enter_thebrana/ventures/proyecto_anita`
- **Remote:** `https://github.com/martineserios/proyecto-anita.git`
- **Stack:** FastAPI + Supabase + Kapso + React 18 + Cloud Run
- **Status:** Production. Tenants: Palco + PDB (cliente amigo de validación). **Delorenzi = primer cliente oficial post-validación** (cerrado 2026-04-23, ARS 1.35M/mes × 3m, 2 ops Gualeguaychú+Paraná, target primer mensaje 2026-06-01). Otros: DGRX (onboarding 2026-04-16), Las Lupes (closed 2026-04-21, cotización pendiente)
- **Details:** `.claude/CLAUDE.md`, `docs/decisions/`, `clients/` (per-client docs)

### linkedin
- **Type:** Client acquisition funnel — content pipeline, profile, network, consulting
- **Location:** `~/enter_thebrana/ventures/linkedin/`
- **LinkedIn slug:** `martinrios` (URL: linkedin.com/in/martinrios)
- **Details:** `CLAUDE.md`, `.claude/tasks.json`
- **Current Phase:** Phase A — 30-day manual validation

### tinyhomes
- **Type:** Marketplace — alojamientos alternativos
- **Location:** `~/enter_thebrana/ventures/tinyhomes/`
- **Remote:** `https://github.com/martineserios/tinyhomes.git`
- **Status:** Blocked — waiting on cofounder input before any work resumes
- **Details:** `docs/decisions/`, `.claude/tasks.json`

### brapsoclaw
- **Type:** Open-source — NanoClaw fork on Kapso (WhatsApp Business API)
- **Location:** `~/enter_thebrana/ventures/brapsoclaw/`
- **Remote:** `https://github.com/martineserios/brapsoclaw`
- **Details:** `.claude/CLAUDE.md`

### mcp-mercadolibre
- **Type:** Side project — MercadoLibre MCP integration
- **Location:** `~/enter_thebrana/ventures/mcp-mercadolibre/`

### ai-native-education
- **Type:** Venture — AI-native education framework & pedagogy (Feynman-AI methodology)
- **Location:** `~/enter_thebrana/ventures/ai-native-education/`
- **Status:** Pre-pilot. Kit v0.3 completo, calibrado con encuesta de 43 alumnos. Pares obligatorios confirmados por Chacha 2026-04-10. Arranque: Clase 1 el 30 de abril 2026.
- **Details:** `estadistica-feynman-ai/` (5 docs operativos + PDFs), `encuesta-resultados.md`
- **Next:** Chacha arma los pares antes del 30 de abril. Clase 1: live Claude onboarding + framing Feynman-AI.

### lexia
- **Type:** Venture — AI-powered legal services platform (Argentine corporate law)
- **Location:** `~/enter_thebrana/ventures/lexia/`
- **Team:** Tomás Catalán Pellet (shared cofounder w/ proyecto_anita) + Trusso (lawyer, legal domain + templates) + Martín (tech/AI operator, alias "Bonnie" in meetings)
- **Status:** Pre-launch product iteration — TCP + Trusso building for a while; Martín joined as operator. Active: product audit + template sourcing + token-cost pricing model. No revenue.
- **Details:** `.claude/CLAUDE.md`, ADR-001 (AI model), ADR-002 (monetization path, Proposed), meeting notes 2026-04-17

### prediktive-prep
- **Type:** Side project — learning/study material
- **Location:** `~/enter_thebrana/ventures/prediktive-prep/`

### psilea (ARCHIVED 2026-03-05)
- **Type:** Microdosing psilocybin business (venture)
- **Location:** `~/enter_thebrana/ventures/psilea/`
- **Status:** Archived — no longer active

## Personal (personal OS — not a project)

### personal
- **Type:** Personal OS — thinking practice, identity work, journaling, goals
- **Location:** `~/enter_thebrana/personal/`
- **Details:** `CLAUDE.md`, `.claude/tasks.json` (33 tasks, migrated from thebrana 2026-03-17)
- **Infra:** Telegram bot on Oracle Cloud Free Tier, LinkedIn MCP
