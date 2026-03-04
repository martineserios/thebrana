# Feature: LinkedIn Content Pipeline

**Date:** 2026-03-03
**Status:** designing
**Task:** [t-161](../../../.claude/tasks.json)
**Research:** [doc 43](~/enter_thebrana/brana-knowledge/dimensions/43-linkedin-personal-brand-strategy.md)
**Positioning research:** [t-170 research](research-positioning-2026-03-03.md) — niche validated, unoccupied, $11-14B market
**Challenger review:** [2026-03-03](challenge-2026-03-03.md) — 3 critical (resolved), 5 warnings (mitigated), 6 contradictions (reconciled)
**Implementation design:** [implementation.md](implementation.md) — full pipeline architecture, phases, templates, skill design, metrics
**Product literature insights:** [product-insights.md](product-insights.md) — frameworks from docs 40-42 applied to pipeline strategy

---

## Goal

Build a brana-assisted content pipeline that transforms session activity, frameworks, and learnings into LinkedIn draft posts. Human-edited, AI-extracted. 3x/week bilingual cadence (English for technical, Spanish for local/venture). Position as the person who translates between business and AI systems — with consulting potential.

## Positioning

**"I make AI work for businesses — here's how, and here's the system behind it."**

Bridge positioning: content speaks to founders in business language but demonstrates technical depth. Case Studies lead, brana proves the method. Every post should pass the dual test: founders hear "he solves my kind of problem," technical people hear "he thinks about architecture, not just code."

**Core identity:** Builder. Everything published traces to something built, broken, or used firsthand. No theory, no smoke — experience-based content only.

**Signature phrase:**
- Spanish: **"Todo es un sistema. Mapealo."**
- English: **"Everything is a system. Map it."**
- Closes every post. Means something different after every story. First half is the lens (seeing). Second half is the action (builder).
- **Brand statement** (bio, header, about section): "Behind every effortless moment is a system someone built with care."
- **Founding collection** (poster series, carousel covers): "Good systems make ordinary people do extraordinary things." / "Behind every smooth operation is someone who thought very carefully." / "Simplicity is what complexity looks like when it's done."

**Systems lens:** Perceives reality as systems — components, layers, patterns, interactions. This is NOT a curriculum or a teaching angle. It's just how he talks. The systems vocabulary appears naturally in posts, never explained, never performed. Repetition compounds. Post clarity is self-explanatory. The audience absorbs the lens through accumulation, not instruction.

**Background:** Civil Engineer (UBA) → Data Science Instructor/Program Lead (Digital House, scaled 3→16 courses) → ML Engineer → Freelance AI Engineer. 12+ projects across flood modeling, wildfire detection, medical AI, NLP voicebots, computer vision, CRM automation, WhatsApp platforms, marketplace. Brana is the meta-system built to manage all of it.

### Content Philosophy

- **Not trying to teach. Just talk that way.** Systems vocabulary and patterns appear naturally. No definitions, no "let me explain what a feedback loop is."
- **Repetition compounds.** A term used in post 3 reappears in post 11 in a different industry. By post 30, followers think in your language.
- **Principles emerge, not declared.** Phase A (12 manual posts) reveals the real principles. Don't design a curriculum before having an audience.
- **Zoom as signature format.** Posts move between abstraction layers — enter at one level, exit at another. The movement between layers IS the content.

### Components Shelf (grows organically)

A personal vocabulary of recurring building blocks and patterns. Used naturally in posts, never defined. Grows over time as real projects reveal them.

**Building blocks (what you name):**
- "The human gate" — where the system stops and waits for a person to decide
- "The silent bottleneck" — the process everyone works around but nobody sees
- "The memory layer" — where the system retains what it learned
- "The bridge" — the piece connecting a digital system to a non-digital process
- "The correction loop" — where the system learns from its own failures
- (more will emerge from Phase A)

**Patterns (what you recognize):**
- The feedback loop, the gradual migration, the abstraction layer, the flow bottleneck, the redundant component
- Cross-domain: same pattern appearing in different industries (flood modeling ↔ patient flow ↔ campaign delivery)
- (more will emerge from Phase A)

### Recurring Content Angles

Discovered during brainstorming. Not a schedule — seeds for Phase A.

1. **Before/after system diagrams** — draw the invisible system before you touched it, then the after. The visual transformation is the post.
2. **Layers game** — every post reveals one layer deeper than expected. Audience learns: "there's always another layer."
3. **Same pattern, different skin** — one pattern across 2-3 industries. Your cross-domain superpower.
4. **Gradual adaptation** — "Applying AI to non-digital businesses has to be gradual. We're still working with humans." Contrarian to the "automate everything" hype.
5. **What I removed** — subtraction as design. "7 tools became 3 and a single flow." KISS.
6. **The inherited system** — "I don't build from zero. I adapt what you already have." Respects existing processes and humans.
7. **The refusal story** — projects you said no to. "After mapping the system, I told them they didn't need AI."
8. **Eternal apprentice who ships** — show the learning AND the result in the same post. Real, relatable, cross-project.
9. **The meta-system** — brana as a system for building systems. Abstraction layers in action.

## Audience

**Primary:** Non-technical founders and business owners with AI FOMO — they know AI matters but can't translate their business problems into systems. They need an interpreter who understands their business, designs the solution, and delivers end-to-end. These are the people who already pay.

**Secondary:** Technical leaders (CTOs, tech leads, AI engineers) — they validate credibility, engage with technical depth, and some become clients. Brana content resonates here.

- LATAM tech community (Spanish content — original, not translated)

## Constraints

- All published content must be human-written or heavily edited (LinkedIn 360 Brew penalizes AI content: -30% reach, -55% engagement)
- No external links in post body (always in first comment, -60% reach penalty)
- Scheduling via Buffer/LinkedIn native is allowed (not "automation" in the ban-risk sense — engagement pods and auto-posting bots carry the 23% ban risk)
- 90-day minimum before visible traction — set expectations accordingly
- Content must be authentic: real experiences, real numbers, real failures

## Stage Awareness (from product literature review)

**Current stage: Empathy** (Lean Analytics framework). Market signals validated ($11-14B, 26% CAGR, niche unoccupied) but no customer conversations yet. The OMTM is problem validation, not engagement rate. Phase A is discovery, not a content grind.

**Implications:**
- Phase A (12 manual posts) is the Build-Measure-Learn loop, not a publishing obligation
- Each post should test a hypothesis (which pillar resonates? which format works?)
- Mom Test conversations with 5-10 CTOs/tech leads needed before Phase C
- Gate the skill build (t-166) ruthlessly on Phase A results

## Approach: Brana-Assisted Pipeline

### Phase A: Manual-first validation (weeks 1-4)

Publish manually for 4 weeks before building any skill. This validates pillar weights, reveals the real editing burden, and produces actual data. Design from experience, not theory.

```
Week 1-4: Manual mode
───────────────────────────────

  Your brana sessions                   You
  ─────────────────                     ───
  sessions.md                           │
  git log                               │
  errata (doc 24)              ──→  Write posts manually  ──→  LinkedIn
  ADRs                                  │                        │
  frameworks                            │                        ▼
  research backlog                      │                  Track in published.md
                                        │                  Note what worked/didn't
                                        │
                                     Learn: which pillar resonates?
                                     Learn: how long does editing take?
                                     Learn: what's your natural voice?
```

### Phase B: Skill-assisted execution (week 5+)

After 12+ manual posts, build `/content-draft` informed by real experience.

```
  Brana session activity          You
  ─────────────────────          ───
  sessions.md (abs path)         │
  git log                        │
  errata (doc 24)       ──→  /content-draft  ──→  docs/content/drafts/
  ADRs                           │                    │
  frameworks                     │                    ▼
  research backlog               │              Review + Edit
                                 │              (your voice, your judgment)
                                 │                    │
                                 │                    ▼
                                 │              Schedule (Buffer/native)
                                 │              Post when YOU can respond
                                 │                    │
                                 │                    ▼
                                 │              Publish (3x/week)
```

## Scope (v1)

### Content System

- **4 content pillars** with templates and examples per pillar
- **Voice/tone guide** with 3-5 example posts in natural voice (task: t-174)
- **Post templates** for each pillar x format combination (text, carousel)
- **Content calendar** (markdown or Google Sheet) with pillar rotation
- **Draft queue** at `docs/content/drafts/` — markdown files, one per post
- **3-post buffer** maintained at all times to survive missed batch sessions

### `/content-draft` Skill (built in Phase B, after manual validation)

- Reads `sessions.md` at its actual absolute path: `~/.claude/projects/.../memory/sessions.md`
- Also queries claude-flow `memory_search` for richer structured session data (fallback if sessions.md is sparse)
- Reads `git log --since="7 days ago"`, recent errata, completed tasks
- Presents candidates grouped by pillar, filtered by novelty (checks published.md) and pillar balance
- User picks 3 topics (no opaque scoring formula — human judgment is the ranker)
- Drafts 3 post skeletons: structure + data points + creator tags. NOT full copy — the human writes the voice.
- Auto-updates published.md when user confirms a post was scheduled (eliminates manual SPOF)
- Evergreen mode: when no fresh activity, surfaces frameworks and knowledge entries instead

### Bilingual Strategy

| Language | Content type | Weight | Pillar focus |
|----------|-------------|--------|-------------|
| English | Technical how-tos, frameworks, build-in-public | 70% | Pillars 1-3 |
| Spanish | Case studies, venture insights, LATAM tech commentary | 30% | Pillar 4 + selected from 1-3 |

Spanish content is **original**, not translated. Uses Argentine context, local examples, local pain points.

Note: at ~1 Spanish post/week, building a standalone LATAM audience is slow. Spanish content serves dual purpose: LATAM visibility + demonstrates range to bilingual followers. If Spanish posts outperform, increase allocation.

### Operational Cadence

- **Weekly batch (flexible day, ~2 hours):** `/content-draft` → review → edit → schedule
- **3 posts/week:** schedule for times when you CAN respond (golden hour: first 60-90 min determines reach)
- **Daily:** 5-10 substantive comments on peer posts (build relationships before tagging)
- **Monthly:** review metrics, adjust pillar weights based on data

## Content Pillars (bridge strategy — decided t-175)

Pillar weights reflect the bridge positioning: Case Studies lead (both audiences), brana supports (technical credibility). Week-4 gate: review what resonated after 12 posts and adjust.

**Content rule:** Every post must trace to something built, broken, or used firsthand. No theory-only content.

### Pillar 1: Case Studies (35%) — the spine

Business problem → solution → architecture insight. The bridge pillar: founders see their problem, technical people see rigor. Draw from current freelance projects AND past experience (12+ projects total).

| Project | Angle |
|---------|-------|
| Somos Mirada | "How I automated a surgical practice's patient flow with AI" |
| Somos Mirada | "Meta account hygiene — when your WhatsApp templates get rejected" |
| NexEye | "Deploying computer vision on Docker Swarm — what broke and what I learned" |
| Proyecto Anita | "Multi-tenant WhatsApp campaigns: the architecture decision that saved us" |
| Psilea | "Running a microdosing venture with the same system I use for code" |
| INA (past) | "Graph neural networks for flood prediction — designing AI for critical infrastructure" |
| Medical AI (past) | "Memory-enhanced RAG for medical treatment — why chatbots need to remember" |
| Wildfire Detection (past) | "End-to-end CV pipeline: from labeling to production inference" |

Each project yields 3-5 distinct stories (sub-projects, architecture decisions, failures, outcomes). Estimated runway: 75-90+ posts before needing new material.

### Pillar 2: How-Tos (25%)

Accessible: "how to think about AI for your business" + occasional technical deep dive. Always rooted in something you built.

| Topic | Hook |
|-------|------|
| Business-AI translation | "Your business has a process. AI can improve it. Here's how I evaluate which ones." |
| DDD → SDD → TDD → Code | "The spec-first workflow — why I write the spec before the code" |
| Context Budget (55/70/85%) | "Your AI degrades before you notice — the budget system" |
| Failure tracking | "Why I document every AI mistake — and how it makes the next project better" |
| Graduation Pathway | "Manual → Convention → Workflow → Enforcement" |

### Pillar 3: Contrarian Takes (20%)

Opinionated positions from lived experience that spark discussion. Works for both audiences.

| Take | Hook |
|------|------|
| Spec-first > prompt-first | "Stop writing prompts. Start writing specifications." |
| Failure as data | "My AI has 80+ documented failures. That's a feature, not a bug." |
| Vibe coding critique | "Vibe coding is technical debt with extra steps." |
| Non-CS path | "I'm a Civil Engineer. Here's why that makes me better at AI systems than most programmers." |
| AI FOMO reframe | "You don't need AI. You need someone who understands your business AND AI." |

### Pillar 4: Build-in-Public (20%)

Brana as proof-of-method — the "behind the scenes" that earns technical credibility. Supporting role, not main content.

| Source | Content example |
|--------|----------------|
| ADRs | "Why I merged 3 repos into 1 — the decision framework" |
| Phase completions | "37 skills, 10 agents, 9 hooks — what I shipped for my AI brain" |
| Errata entries | "80+ documented mistakes — why I track every error" |
| Cross-project memory | "Your AI starts from zero every session. Mine doesn't." |

## Creator Engagement Strategy

### Phased approach (challenger-informed)

**Weeks 1-4 (comments only):** Build recognition through substantive comments on peer posts. No tagging. No response posts. Just genuine engagement.

**Weeks 5-8 (selective tagging):** Tag 2-3 Tier 1 creators in response posts — only after they've seen your comments and name.

**Month 3+ (full engagement):** Response posts, comment threads, DM outreach (2-3 creators/month).

### Built-in network (from research backlog)

55 LinkedIn posts from 52 unique creators already catalogued.

- **Tier 1 (initial 2-3 only):** Reuven Cohen (Ruflo foundation), Nathan Cavaglione (build-in-public peer)
- **Tier 2 (after recognition):** Julian DeAngelis (context engineering), Steve Phelps (shared memory), Yauhen Klishevich (CLAUDE.md), Eddie Aftandilian (agentic CI/CD)
- **Tier 3 (comment only):** remaining 46 creators

### Engagement protocol

- Comment with substance (not "great post!" — add your perspective from brana experience)
- Links to your content always in comments, never in post body
- Only tag creators after 4+ weeks of genuine commenting engagement

## Format Mix (v1: 30-50-20)

Adjusted from 60-30-10 after challenger review (no carousel tooling exists for v1):

- **30%** carousels/PDFs — using /export-pdf for plain slides (v2: Canva templates for visual upgrade)
- **50%** text posts — takes, reflections, build-in-public updates, case studies
- **20%** polls/questions — community engagement, topic validation, pillar weight testing

Carousel % increases when visual tooling is available (t-176).

## Deferred (v2+)

- `/content-report` skill for weekly analytics
- Google Sheets integration for metrics tracking
- Content recycling system (top posts → carousels after 6 weeks)
- Creator engagement scoring database
- LinkedIn Newsletter launch
- Thought leadership ads (paid amplification)
- Consulting offer page / landing page
- Canva template integration for professional carousels
- /session-handoff integration to auto-flag content-worthy moments

## Metrics (track from day 1)

| Metric | Target | Tool |
|--------|--------|------|
| Comment rate | 0.3%+ | LinkedIn analytics |
| Profile views (target audience) | Trending up | LinkedIn analytics |
| Inbound DMs | Any | Manual count |
| Consultation requests | 1/month by month 6 | Manual count |
| SSI score | 70+ | LinkedIn dashboard (monthly) |

## Timeline

| Phase | Period | Deliverable |
|-------|--------|-------------|
| Foundation | Weeks 1-4 | Positioning validated, profile optimized, voice guide written, templates created, first 12 posts drafted (6 published, 6 buffer) |
| Launch | Weeks 5-8 | Publishing 3x/week, daily commenting, selective creator engagement |
| Adjust | Month 3 | Refine pillar weights from data, build /content-draft skill |
| Traction | Month 4 | First inbound opportunities, visible engagement |
| Scale | Month 5-6 | Add v2 features based on what's working |

## Resolved questions

- **Spanish content:** original, not translated (decided in shaping)
- **Scheduling vs automation:** Buffer/native scheduling is allowed — the ban risk is from auto-posting bots and engagement pods
- **AI draft polish level:** AI produces structure + data skeletons, NOT polished copy. Human writes the voice.
- **Foundation timeline:** 4 weeks (reconciled with doc 43), not 2 weeks
- **Scoring formula:** dropped in favor of filter→group→human-pick (challenger C3)
- **sessions.md location:** absolute path `~/.claude/projects/.../memory/sessions.md`, not in-repo (challenger C1)
- **Deduplication:** /content-draft auto-updates published.md, not manual (challenger W1)

## Pending decisions (tracked as tasks)

- t-175: Consulting pillar weight — keep Case Studies at 10% or increase to 20%?
- t-176: Carousel tooling decision — /export-pdf, Canva templates, or defer?
- t-174: Voice/tone guide — write 3-5 example posts defining natural voice
