# Product Literature Cross-Insights for LinkedIn Content Pipeline

**Date:** 2026-03-03
**Sources:** [doc 40](~/enter_thebrana/brana-knowledge/dimensions/40-product-discovery-literature.md), [doc 41](~/enter_thebrana/brana-knowledge/dimensions/41-growth-metrics-market-strategy-literature.md), [doc 42](~/enter_thebrana/brana-knowledge/dimensions/42-product-operations-literature.md)
**Feature:** [brief](brief.md)

---

## 1. You're in the Empathy Stage — Act Like It

Lean Analytics (Croll & Yoskovitz) defines five growth stages: Empathy → Stickiness → Virality → Revenue → Scale. The positioning research (t-170) validated market signals ($11-14B, 26% CAGR, niche unoccupied) but **no customer conversations have happened yet**. That's textbook Empathy stage.

**What this means for the pipeline:**
- The OMTM (One Metric That Matters) is **problem validation**, not engagement rate or follower count
- Phase A (manual 12 posts) IS the discovery experiment, not a content grind
- Success = learning which pillar resonates and whether the audience exists, NOT hitting 3x/week

**Mom Test application (Fitzpatrick):** The research flagged "NEEDS VALIDATION: no customer conversations yet." Before optimizing pillar weights or building skills, have 5-10 conversations with CTOs/tech leads about their AI systems challenges. Ask about their past behavior (what they tried, what failed), not hypotheticals ("would you hire an AI systems designer?").

**Three currencies of commitment to seek:**
1. **Time:** They agree to a follow-up call after seeing your content
2. **Reputation:** They share your post or refer you to someone
3. **Money:** They inquire about consulting rates

If Phase A produces zero advancement signals after 12 posts, that's a pivot signal — not a reason to "try harder."

---

## 2. Discovery vs Delivery — Don't Collapse Them

Cagan's central thesis: products fail because teams build the wrong things, not because they build them wrong. The content pipeline has a clear dual-track structure:

| Track | Content Pipeline Equivalent |
|-------|---------------------------|
| **Discovery** | Which topics resonate? Which pillar drives engagement? What does the audience actually need? |
| **Delivery** | Templates, scheduling, /content-draft skill, Buffer automation |

**The risk:** Phase A is designed as discovery, but the implementation plan (ms-014, t-166) is heavy on delivery tooling. The brief explicitly gates the skill build on manual validation — respect that gate. Don't build /content-draft until 12 manual posts produce validated learning about what works.

**Cagan's 10 Questions applied to the content pipeline:**
1. What problem does this solve? → Positioning as AI systems designer for consulting pipeline
2. For whom? → AI engineers, tech leads, CTOs evaluating agentic workflows
3. How big? → $11-14B market, 8,000+ AI Architect job listings
4. Alternatives? → Following Reuven Cohen, Nathan Cavaglione, or reading Martin Fowler
5. Why us? → Brana is production-tested across 6 projects with 80+ documented failures
6. Why now? → SDD reaching mainstream (Fowler 2026), 72% reject vibe coding
7. GTM? → LinkedIn organic + creator network (55 catalogued)
8. Success metric? → Inbound consultation requests (1/month by month 6)
9. Critical factors? → Authentic voice, consistent cadence, substantive engagement
10. Recommendation? → Proceed with manual validation, gate skill build on results

---

## 3. Beachhead Before Bowling Alley

Moore's Crossing the Chasm maps directly to the content strategy:

**Beachhead = "AI systems designer" niche on LinkedIn.**
- Big enough to matter: $11-14B market, 26% CAGR
- Small enough to lead: no one occupies this exact position
- Crown jewels: brana (6 projects, 37 skills, 80+ documented errors)

**The audience segments map to Moore's adoption curve:**
- **Innovators (2.5%):** Claude Code power users already building systems (Reuven Cohen's community)
- **Early Adopters (13.5%):** Tech leads experimenting with agentic workflows, seeking competitive advantage
- **Early Majority (34%):** Engineering managers who want proven, reliable AI integration patterns

**Key insight:** Content for innovators (Pillar 1: Build-in-Public) and content for early majority (Pillar 4: Case Studies) require fundamentally different messaging. Build-in-Public attracts visionaries. Case Studies convert pragmatists. The challenger's question about pillar weights (t-175) is really a question about **which adoption segment to target first**.

**Moore's recommendation:** Win the early adopters first. Build-in-Public (40%) + Contrarian (20%) is the right v1 mix for that segment. Case Studies (10-20%) becomes the bowling pin when you need to cross the chasm to pragmatist buyers.

---

## 4. Build-Measure-Learn Applies to Content, Not Just Products

Ries's BML loop maps to the content batch cycle:

```
BUILD              MEASURE              LEARN
─────              ───────              ─────
Write 3 posts  →  Track engagement  →  Which pillar performed?
(weekly batch)    (comment rate,        What resonated?
                   profile views,       What fell flat?
                   DMs)                 Pivot or persevere?
                       │
                       ▼
               Innovation Accounting:
               Are engagement numbers
               actionable or vanity?
```

**Vanity vs actionable metrics for content:**
- **Vanity:** Impressions, follower count, total likes
- **Actionable:** Comment rate (0.3%+), profile views from target audience, inbound DMs, SSI

The metrics tracking task (t-169) already lists the right ones. The insight is: treat each week's 3 posts as a **micro-experiment**, not a publishing obligation. What hypothesis does each post test?

---

## 5. Hook Model for Content Retention

Eyal's Hook Model applies to building a repeat audience:

| Stage | Content Application |
|-------|-------------------|
| **Trigger** | External: LinkedIn feed, notifications. Internal: "what's Martin building this week?" |
| **Action** | Read the post (low friction — it's already in their feed) |
| **Variable Reward** | **Tribe:** peer recognition from engaging. **Hunt:** novel frameworks, contrarian takes. **Self:** "I learned something I can apply" |
| **Investment** | Comment, share, follow, save — each investment loads the next trigger |

**The Habit Zone:** High frequency (3x/week) + high perceived utility (actionable frameworks) = habit formation territory.

**Key design implication:** Each post must deliver variable reward. A predictable "here's what I built" update becomes ignorable. Mix pillars and formats to maintain novelty: build-in-public surprise → tactical how-to → contrarian provocation → case study result.

---

## 6. Opportunity Solution Tree for Content Strategy

Torres's OST framework structures the content pipeline as a discovery system:

```
DESIRED OUTCOME: 1 inbound consultation request/month by month 6
│
├── Opportunity: Target audience doesn't know "AI systems design" exists as a discipline
│   ├── Solution: Contrarian posts (Pillar 3) — "Stop writing prompts"
│   ├── Solution: Framework carousels (Pillar 2) — visual proof of the discipline
│   └── Experiment: Compare engagement on "contrarian hook" vs "how-to hook" posts
│
├── Opportunity: Target audience can't evaluate whether they need this
│   ├── Solution: Case studies (Pillar 4) — show before/after from real projects
│   ├── Solution: Build-in-public metrics (Pillar 1) — quantified improvement data
│   └── Experiment: Include specific numbers vs generic narrative — which converts?
│
├── Opportunity: No trust/credibility established yet
│   ├── Solution: Creator engagement (comment-first strategy)
│   ├── Solution: Response posts building on known creators' content
│   └── Experiment: Track profile views from comment engagement vs original posts
│
└── Opportunity: Audience doesn't know how to hire this capability
    ├── Solution: Whole product messaging — show consulting deliverables
    ├── Solution: DM conversations after engagement signals
    └── Experiment: Soft CTA in posts vs no CTA — does it matter at this stage?
```

**Weekly discovery cadence (Torres):** After each 3-post week, spend 30 min reviewing which opportunity branch moved. Update the tree. This replaces "gut feel" pillar adjustment with structured learning.

---

## 7. The Build Trap Warning

Perri's build trap is the biggest risk in ph-005. The plan has 17 tasks, 5 milestones, and a full skill build (t-166). The trap:

> Optimizing for output (shipping 3 posts/week, building /content-draft) instead of outcomes (do people actually want to hire an AI systems designer?).

**Escape routes:**
- Measure outcomes (DMs, consultation requests), not outputs (posts published)
- Phase A IS the Product Kata — understand direction, set success metrics, explore problems, explore solutions
- If 12 manual posts produce zero engagement from the target audience, the answer isn't "build the skill" — it's "pivot the positioning"

**Product Kata applied to Phase A:**
1. **Direction:** Position as AI systems designer, build consulting pipeline
2. **Success metric:** Comment rate >0.3%, profile views trending up from target audience
3. **Problem exploration:** Which content format + pillar combo generates engagement from the right people?
4. **Solution exploration:** Test 4 pillars × 3 formats manually
5. **Learning:** After 12 posts, which combinations worked? Where do real conversations happen?

---

## 8. Whole Product for Consulting Conversion

Moore's Whole Product concept applies when content converts to consulting leads. The "hire me" moment requires more than good posts:

| Whole Product Element | Status |
|-----------------------|--------|
| Core product (content demonstrating expertise) | Phase A builds this |
| Case studies / references | Pillar 4, available from portfolio |
| Documentation (frameworks, methodology) | Brana's 9 named frameworks exist |
| Services definition (what you deliver) | **Missing** — no service offering defined |
| Pricing model | Research shows $150-500/hr, but no personal rate set |
| Risk mitigation (guarantees, process transparency) | Brana's documented methodology IS this |

**Gap:** The pipeline focuses on content creation but doesn't define the consulting offering. Content generates interest; the whole product converts it. Consider defining a simple service menu (strategy roadmap, PoC build, training workshop) before Phase A ends — so when inbound arrives, there's something to sell.

---

## 9. JTBD — What Job Does the Audience Hire Your Content For?

Christensen's Jobs-to-be-Done reframes the pillar strategy:

| Audience Segment | Job They Hire Content For |
|-----------------|--------------------------|
| AI engineers | "Help me design better systems, not just write more code" |
| Tech leads | "Show me what good AI integration looks like so I can evaluate my team's approach" |
| CTOs | "Give me a framework for deciding where AI fits in our org" |
| LATAM tech | "Show me someone local succeeding at the frontier, not just translating US content" |

**Implication:** Each post should be frameable as a job. "I wrote about my ADR process" → "This helps tech leads evaluate their decision-making process for AI adoption." If a post doesn't serve a clear job, it's content for content's sake.

---

## Summary: 5 Decision-Grade Insights

1. **You're in Empathy, not Stickiness.** OMTM = problem validation (Mom Test conversations), not engagement rate. Phase A is discovery, not delivery.

2. **Gate the skill build ruthlessly.** /content-draft (t-166) only makes sense after 12 manual posts produce validated learning. Don't collapse discovery into delivery.

3. **Target early adopters first.** Build-in-Public 40% + Contrarian 20% is the right mix for visionaries. Case Studies increase later for pragmatist conversion (crossing the chasm).

4. **Treat each week as a micro-experiment.** 3 posts/week = 3 hypotheses tested. Use Torres's OST to track which opportunity branches are moving.

5. **Define the consulting offering before inbound arrives.** Content is the core product; the whole product includes service definition, pricing, and risk mitigation. Don't wait for demand to figure out the supply side.
