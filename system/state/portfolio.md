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
| Glide as MVP backend (Tables + UI + API eliminates Postgres/admin/auth for pilots) | `clients/mya/docs/ideas/mvp-architecture.md` | mya, any B2B2C MVP |
| Lovable → Claude Code handoff (30 min scaffold, GitHub push, Claude wires APIs) | `clients/mya/docs/ideas/mvp-architecture.md` | mya, any frontend-heavy client |
| NanoClaw/ZeroClaw/Claw ecosystem (architecture, Docker isolation, Agent SDK) | `brana-knowledge/dimensions/36-claw-ecosystem-chat-interface.md` | brapsoclaw, any chat agent project |

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

### anita (Proyecto Anita)
- **Type:** Multi-tenant WhatsApp campaign management platform
- **Projects:** proyecto_anita (`clients/proyecto_anita`)
- **Remote:** `https://github.com/martineserios/proyecto-anita.git`
- **Details:** `.claude/CLAUDE.md`, `docs/decisions/`

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
- **Type:** Venture — AI-powered legal services platform
- **Location:** `~/enter_thebrana/ventures/lexia/`
- **Status:** Discovery — concept validated via voice notes, lawyer cofounder identified, no revenue
- **Details:** `.claude/CLAUDE.md`, `docs/decisions/ADR-001-ai-legal-services-model.md`

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
