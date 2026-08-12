---
title: Brana Agency Growth Machine
status: idea
created: 2026-08-11
---
# Brana Agency Growth Machine

> Brainstormed 2026-08-11. Status: idea (shaped, approved).

## Problem

The Brana agency's client inflow is referral/network-dependent — no systematic attraction, nurture, or conversion. `ventures/linkedin` (Phase A, 30-day manual validation) stalled at manual posting cadence; content pipeline stopped at seed generation. Meanwhile delivery capability is proven: ~10 AR SMB clients, WhatsApp/AI automation (Anita platform, Kapso, Meta BSP), plus a differentiated brand asset (brana, harness engineering).

## Direction (decided in brainstorm)

- **Two-track:** SMB WhatsApp/AI ops (revenue now, Spanish, LatAm) + harness engineering (brand, English, global).
- **Supersedes `ventures/linkedin`** — that venture becomes a channel inside this machine, not the strategy home.
- **Lead magnets (candidate set, sequencing TBD):** live WhatsApp demo agent · productized automation audit · ROI mini-app/calculator · SEO/GEO content guides.
- **90-day success:** 2-3 signed clients AND predictable pipeline (10+ qualified leads/mo).
- **Core design constraint (from challenge round):** operator time is the scarcest resource; the machine must be agent-automated — brana runs the funnel, the human only touches sales-ready leads. The machine itself is proof-of-work marketing ("we sell the machine we use").

## Research findings

- 2026 AI-agency playbook: LinkedIn as #1 channel; stack 3-4 strategies (content + outreach + lead magnet + nurture); interactive lead magnets (mini-apps, live demos) outperform gated PDFs; niche to one problem/one industry ([Ciela](https://ciela.ai/blogs/how-to-get-clients-ai-automation-agency), [ManyRequests](https://www.manyrequests.com/blog/ai-lead-generation-strategies), [Zouhall](https://zouhall.com/insights/how-to-start-and-scale-a-profitable-ai-automation-agency)).
- Internal knowledge: referred leads convert 3-5x; 92% trust word-of-mouth (`smb-marketing-channels` dimension). Community-led growth > influencer marketing.
- Existing assets: `docs/ideas/distribution-strategy.md` (brana tool + LinkedIn = same funnel; "brana demonstrates what you teach"), `content-skill-seed-to-post.md` (partial content pipeline, t-736), Anita/Kapso stack for live WhatsApp demos.

## Refined direction (challenge rounds)

- **No social posting.** User will not sustain a posting cadence (validated by two stalled attempts). All channels must work without feed presence. Consequence accepted: harness/brand track goes passive (GitHub + SEO only); SMB track is the machine.
- **Bottom of funnel stays human:** user takes the sales calls (~10/mo is acceptable). Machine's job is to fill and qualify, not close.
- **The MVP of the machine = website + demo agent:**
  1. An exceptional, attention-catching website (ES-first) — the agency's single surface.
  2. A live WhatsApp demo agent linked from it — the lead's *first taste* is experiencing a genuinely excellent agent. The agent validates the agency before any human conversation.
- Traffic channels (referral engine, partnerships, agent-written SEO/GEO content, automated outbound) feed the door later — build the destination first.

## Key asset discovery

- **thebrana.ai is live** (Vercel `thebrana-web`, v0-origin). A bilingual agency landing (t-2249) was built and rolled back same day — lives on branch `site/feat/t-2249-commercial-landing`. Re-ship path: `git revert a91c61e` on master, then merge the branch. The website workstream resumes t-2249, not greenfield.
- Demo agent bases: brapsoclaw (NanoClaw fork on Kapso), Anita agent stack, `llm-agent-test-strategy-patterns`.
- **Living portfolio (user addition):** the site auto-updates with current projects — brana close/ship emits a sanitized project card (anonymization gate; t-2249 tests already enforce "no client names"). Proof accumulates with zero extra operator effort.

## Risks

- **Empty showroom** (pre-mortem A): great site, zero traffic → mitigation: traffic commitment from day 1 — structured referral ask + demo link to every past client + 2 partnership conversations, launched WITH the site.
- **Merely-fine agent** (pre-mortem B): a mediocre first taste actively disqualifies → mitigation: wow-bar spec, test on 5 real SMB owners, ship only at 4/5 "quiero esto".
- Public agent abuse: prompt injection, API spend on open WhatsApp number → rate limits, spend caps, scoped prompts.
- Operator time: previous manual-cadence attempts stalled → mitigation: no-posting design, automation-first, human only at sales calls (~10/mo accepted).

## Second-order effects

- Demo agent → leads forward it in WhatsApp → the lead magnet is itself viral in the channel where the buyers live; every client-agent improvement upgrades the pitch.
- Referral asks to past clients → conversations reopen → likely reactivates the 4 stalled proposals (mya, batrade, las lupes, crea) before any new lead arrives.
- Living portfolio → shipping client work automatically improves the site → delivery and marketing become the same motion.

## Engineering disciplines (M+)

- **DDD:** ADR — demo agent stack (brapsoclaw/Kapso vs Anita-vendored); site re-ship decision (revert-then-merge t-2249 vs fresh).
- **TDD:** agent replay/shadow tests; keep t-2249 i18n test gates (key parity, no unsourced numbers, no client names).
- **SDD:** feature spec before build (spec gate applies).
- **Docs:** wow-bar spec + referral-ask playbook as living docs.

## Next steps (phased)

1. **Phase 1 — The Door:** offer definition (packages/pricing) → wow-bar spec → demo agent build + 5-owner test → re-ship t-2249 landing with agent CTA.
2. **Phase 2 — Traffic day 1:** referral engine (structured ask + demo link to all past clients), 2 partnership conversations (Kapso, contadores).
3. **Phase 3 — Compounding:** living portfolio automation (close/ship → site card), agent-written SEO/GEO ES content, automated outbound to niche lists, qualification/nurture automation.

## Success metric

90 days from Phase 1 ship: 2-3 signed clients AND 10+ qualified leads/mo entering the pipeline.
