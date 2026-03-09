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

**"I see systems. Then I build them. Business problems → AI/ML products, architecture to production."**

LinkedIn headline (decided 2026-03-07): `I see systems. Then I build them. Business problems → AI/ML products, architecture to production.`

Systems thinker who ships. The differentiator is the systems lens — seeing components, layers, patterns, interactions where others see chaos. The proof is end-to-end builds: architecture to deploy, ML to infra, one brain. Content speaks to founders in business language but demonstrates technical depth that earns CTO-level peer recognition.

**Dual test (every post):** Founders hear "he solves my kind of problem." Technical people hear "he thinks about architecture, not just code."

**Core identity:** Builder. Everything published traces to something built, broken, or used firsthand. No theory, no smoke — experience-based content only. Not just a systems thinker — a systems thinker who implements. Full-stack in the deepest sense: ML + software architecture + infrastructure + deploy.

**Positioning evolution (decided 2026-03-07):** Started as "AI systems designer" (narrow, captures brana well). Evolved to "systems thinker who builds" — broader, honest about the full range (NexEye full-SaaS architecture, brana open source, 12+ cross-domain projects). The systems lens IS the differentiator on LinkedIn (nobody else leads with this). The full-stack depth IS the proof (shown in About, Experience, and content — not claimed in the headline).

**CTO-readiness signal (implicit, never claimed):** The profile should make CTOs think "this person thinks like me" and founders think "this is the technical partner I need." Never say "fractional CTO" — let the evidence lead the viewer to that conclusion. The career arc (Civil Engineer → ML → AI Systems) is itself the differentiator.

**Signature phrase (decided 2026-03-09, reverted to two beats after challenge):**
- English: **"Everything is a system. Map it."**
- Spanish: **"Todo es un sistema. Mapealo."**
- Two beats only. Lens + action. Three-beat version ("Push it to production" / "Ponelo en producción") was tested and cut — it diluted the punch and repeated "production" already covered in the About body. Shorter is stickier.
- Closes every post AND the About section. Means something different after every story. First half is the lens (seeing). Second half is the action (builder).
- Lands harder with the full-range positioning: "sistema" means the *whole thing* — ML, infra, business process, deploy — not just the AI layer.
- "Mapealo" is rioplatense (voseo) — intentional brand mark, only voseo element in the otherwise LATAM-neutral Spanish profile.
- **Brand statement** (bio, header, about section): "Behind every effortless moment is a system someone built with care."
- **Founding collection** (poster series, carousel covers): "Good systems make ordinary people do extraordinary things." / "Behind every smooth operation is someone who thought very carefully." / "Simplicity is what complexity looks like when it's done."

**Systems lens:** Perceives reality as systems — components, layers, patterns, interactions. This is NOT a curriculum or a teaching angle. It's just how he talks. The systems vocabulary appears naturally in posts, never explained, never performed. Repetition compounds. Post clarity is self-explanatory. The audience absorbs the lens through accumulation, not instruction.

**Background:** Civil Engineer (UBA) → Data Science Instructor/Program Lead (Digital House, scaled 3→16 courses) → ML Engineer → Freelance AI Engineer. 12+ projects across flood modeling, wildfire detection, medical AI, NLP voicebots, computer vision, CRM automation, WhatsApp platforms, marketplace. Brana is the meta-system built to manage all of it.

### Anti-positioning (decided 2026-03-07)

What we are NOT. These are explicit guardrails — if content, copy, or profile decisions drift toward any of these, course-correct immediately.

| Not this | Why | The actual difference |
|----------|-----|----------------------|
| **No-code automator** (n8n, Make, Zapier) | Crowded, low-value, commoditized. Our work requires real code and architecture. | We write code — PyTorch, FastAPI, React, Docker, Terraform. We design inference pipelines, not drag-and-drop flows. |
| **AI wrapper / prompt engineer** | "I put GPT on your business" is not a system. It's a feature. | We build the system around the AI — data pipelines, feedback loops, memory layers, deploy infra. The model is 10% of the work. |
| **Generic full-stack dev** | Commoditized on LinkedIn. Every bootcamp grad says this. | We think in systems first, then build. The Civil Engineer → ML arc is the differentiator. Architecture decisions, not CRUD apps. |
| **AI influencer / content creator** | We're a builder who writes, not a writer who builds. | Every post traces to something built, broken, or shipped. Zero theory-only content. |
| **"Fractional CTO" label** | Overused, often means "advisor who doesn't code." | We code, architect, AND deploy. CTO-level thinking + IC-level execution. Let the evidence show it, never claim the title. |

**ML identity guardrail:** Machine learning is core to who we are — not a buzzword. The profile, About, and content must make clear this person does real ML (NLP, computer vision, graph neural networks, model training, inference pipelines) not just API calls to OpenAI. The headline includes "AI/ML" not just "AI." Technical posts reference real ML trade-offs, not wrapper patterns.

### Project Assets (honest status)

| Asset | What it is | Status | Usable claims |
|-------|-----------|--------|---------------|
| **brana** | AI development system (37 skills, 10 agents, 580+ knowledge entries) | Open source, in daily use across 6 projects | "Built and use daily" — real metrics, real system |
| **NexEye** | Real-time wildfire detection platform (full SaaS: FastAPI + React + YOLO + Docker Swarm) | Pre-production. Contract near-signed with Neuquén province government. | "Designed and built the full architecture" — not "in production" |
| **Past work** | Encora (2y11m), Froneus (7m), INTA flood model, Galo AI, Digital House | Delivered, in production | Full claims — these shipped |

**Rule:** Never claim production scale for pre-production work. NexEye is a portfolio piece and architecture story, not a "running at scale" claim. When the Neuquén contract signs and it goes live, update this section.

### Business Model & Economic Strategy (decided 2026-03-07)

**Revenue target:** $10k/month as a solo developer.

**Revenue engine:** AI consulting / business-to-system translation. Fast cash cycle (2-4 week projects), upsell after initial delivery, referral-driven pipeline. This is what LinkedIn optimizes for.

**Growth model:** Land → deliver → expand. First engagement $3-5k (map process, implement one system). Second $3-5k (results earned trust). Third becomes retainer ($2-3k/month). Three clients at recurring = $6-9k/month base + new projects on top.

**CTO/cofounder roles:** Come through relationships and reputation, not LinkedIn posts. The content and profile build the credibility that makes these conversations happen naturally. Don't chase — attract.

**NexEye:** Parallel track. If contract signs, it becomes both a product revenue stream and the flagship case study. Until then, it's architecture evidence.

**Why not lead with big builds:** Building NexEye-type products solo means doing 5 roles (CTO + backend + frontend + DevOps + ML) for one salary. Intellectually satisfying but economically inefficient at $10k/month. Consulting is higher $/hour, faster cash cycle, and creates the optionality for selective big builds later.

**Diversity preference:** Consulting satisfies this — new domain every few weeks (medical practice, wildfire detection, WhatsApp campaigns, marketplace). Cross-domain pattern recognition IS the systems lens in action.

### Content Philosophy

- **Not trying to teach. Just talk that way.** Systems vocabulary and patterns appear naturally. No definitions, no "let me explain what a feedback loop is."
- **Repetition compounds.** A term used in post 3 reappears in post 11 in a different industry. By post 30, followers think in your language.
- **Principles emerge, not declared.** Phase A (12 manual posts) reveals the real principles. Don't design a curriculum before having an audience.
- **Zoom as signature format.** Posts move between abstraction layers — enter at one level, exit at another. The movement between layers IS the content.
- **Practitioner mode, not tutorial mode (decided 2026-03-07).** Technical posts show implementation depth through war stories and decisions, not step-by-step instructions. "I deployed Docker Swarm on Hetzner. Here's the decision that broke everything." NOT "How to deploy Docker Swarm — step by step." Tutorial mode attracts juniors. Practitioner mode attracts peers and decision-makers. The 45% technical content (Pillar 2 How-Tos 25% + Pillar 4 Build-in-Public 20%) establishes CTO-level credibility while remaining accessible to founders through narrative framing.

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

**Two-profile approach (decided 2026-03-07):** Use LinkedIn's built-in secondary language profile feature. Each audience sees a fully native profile automatically.

| Element | English (primary) | Spanish (secondary) |
|---------|-------------------|---------------------|
| **Headline** | `I see systems. Then I build them. Business problems → AI/ML products, architecture to production.` | `Veo sistemas. Los llevo a producción. Problemas de negocio → productos de IA/ML.` |
| **About** | Full English (see below) | Full Spanish, LATAM-neutral body + rioplatense signature only (see below) |
| **Experience** | English descriptions, system-problem-first framing | Spanish descriptions, adapted for LATAM context |
| **Skills** | Same (language-neutral) | Same |

#### About section copy (decided 2026-03-09, 4 challenge rounds)

**English:**

> Every business runs on a system — most just don't know it. How work comes in, how it moves through your team, how it gets delivered. I start every project the same way: map it, design it, build it — end to end. I don't own a layer of the solution. I own the whole thing — from the problem to the solution in production.
>
> I don't start building until I've seen the problem from every angle I can find — how the business works, how the data flows, how AI fits — if it fits at all — how the system holds. Then I design the architecture, build it, and push it to production myself. I've done this across flood prediction, real-time computer vision, AI for health tech, and CRM automation. The pattern is always the same.
>
> Civil Engineer. Then ML Engineer. The system changes. The lens doesn't.
>
> I write about what I build — including what didn't work. That's usually the better post. If any of this sounds familiar, say hi.
>
> Everything is a system. Map it.

**Spanish:**

> Todo negocio funciona con un sistema — la mayoría no lo sabe. Cómo entra el trabajo, cómo se mueve dentro del equipo, cómo se entrega. Cada proyecto arranca igual: mapearlo, diseñarlo, implementarlo — de punta a punta. No me quedo con una parte de la solución. Me quedo con toda — del problema a la solución en producción.
>
> No arranco a desarrollar hasta que veo el problema desde todos los ángulos posibles — cómo funciona el negocio, cómo fluyen los datos, cómo encaja la IA — si es que encaja — cómo se comporta el sistema. Después diseño la solución, la desarrollo, y la llevo a producción yo mismo. Lo hice en predicción de inundaciones, visión por computadora en tiempo real, IA para healthtech y automatización de CRM. El patrón es siempre el mismo.
>
> Ingeniero Civil. Después, Ingeniero en ML. El sistema cambia. La forma de verlo, no.
>
> Escribo sobre lo que hago — incluyendo lo que no salió bien. Esos suelen ser los mejores posts. Si algo te resuena, estoy por acá.
>
> Todo es un sistema. Mapealo.

**Register decision:** LATAM-neutral body text (no voseo, no Argentine slang). Rioplatense only in the signature ("Mapealo") as an intentional brand mark.

**Content posts** follow separate language weights:

| Language | Content type | Weight | Pillar focus |
|----------|-------------|--------|-------------|
| English | Technical how-tos, frameworks, build-in-public | 70% | Pillars 1-3 |
| Spanish | Case studies, venture insights, LATAM tech commentary | 30% | Pillar 4 + selected from 1-3 |

**Rules:**
- Spanish content is **original**, not translated. Uses Argentine context, local examples, local pain points.
- Don't mix languages in a single profile section. Each profile is fully in its language.
- Each profile closes with the signature in its own language. English: "Everything is a system. Map it." Spanish: "Todo es un sistema. Mapealo."

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

Practitioner-mode: "here's what happened when I did it" not "here's how to do it." Business-accessible framing with technical depth underneath. Always rooted in something built. Includes architecture and infrastructure topics — not just AI layer. (Updated 2026-03-07: expanded scope to reflect full-range positioning.)

| Topic | Hook |
|-------|------|
| Business-AI translation | "Your business has a process. AI can improve it. Here's how I evaluate which ones." |
| DDD → SDD → TDD → Code | "The spec-first workflow — why I write the spec before the code" |
| Context Budget (55/70/85%) | "Your AI degrades before you notice — the budget system" |
| Failure tracking | "Why I document every AI mistake — and how it makes the next project better" |
| Graduation Pathway | "Manual → Convention → Workflow → Enforcement" |
| Docker Swarm architecture | "Encrypted overlay networking silently drops packets on Hetzner. Took me 3 days." |
| CI/CD pipeline design | "Our staging deploy went to production. Here's the one secret we forgot." |
| Multi-environment deployment | "Why I destroy and rebuild infrastructure from scratch — and the script that makes it safe" |

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

Adjusted from 60-30-10 after challenger review:

- **30%** carousels — created in NotebookLM from Claude-prepared source files and style guides (decided t-176, 2026-03-05)
- **50%** text posts — takes, reflections, build-in-public updates, case studies
- **20%** polls/questions — community engagement, topic validation, pillar weight testing

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
- **t-175: Case Studies weight:** increased to 35% (bridge spine connecting founders + technologists). Full weights: Case Studies 35%, How-Tos 25%, Contrarian 20%, Build-in-Public 20%. Week-4 gate applies.
- **t-176: Carousel tooling:** NotebookLM. Claude provides prompts, source files, and style guides. User creates carousels in NLM manually. (Updated from /brana:export-pdf, 2026-03-05.)
- **Positioning scope (2026-03-07):** Evolved from narrow "AI systems designer" to "systems thinker who builds." Systems lens is the headline differentiator. Full-stack depth (ML + architecture + infra + deploy) is the proof shown in About/Experience/content. Encompasses both consulting implementations and complex product builds (NexEye). CTO-readiness signaled implicitly, never claimed.
- **Headline (2026-03-07):** EN: `I see systems. Then I build them. Business problems → AI/ML products, architecture to production.` ES: `Veo sistemas. Los llevo a producción. Problemas de negocio → productos de IA/ML.`
- **About section (2026-03-09):** Complete in both languages after 4 challenge rounds. See Bilingual Strategy section for full copy. Key decisions: P1 for founders (systems lens + ownership), P2 for technical readers (perspectives + proof domains), career arc one-liner, practitioner content hook, non-salesy CTA, two-beat signature closer.
- **Signature reverted to two beats (2026-03-09):** "Everything is a system. Map it." / "Todo es un sistema. Mapealo." Three-beat version cut after challenge — diluted punch, repeated "production."
- **Technical content approach (2026-03-07):** Practitioner mode, not tutorial mode. War stories and decisions, not step-by-step guides. Attracts peers and decision-makers. 45% of content (Pillar 2 + Pillar 4) establishes technical credibility.
- **Economic strategy (2026-03-07):** Lead with consulting/implementation (fast cash, upsell, $10k/month target). CTO/cofounder roles come through reputation, not LinkedIn posts. Big builds are selective, not the primary revenue engine. Consulting satisfies diversity preference.

## Pending reviews (from challenge rounds)

Items to monitor and adjust based on real data. These are not blockers — they are calibration points validated through experimentation.

### Headline
- **"I see systems" cold landing test:** Monitor profile views → About read-through rate in weeks 1-4. If cold visitors don't convert to About reads, headline is the first suspect. Alternative ready: more concrete openers tested during shaping.

### About section — P2
- **Four domains may read as "jack of all trades" to CTOs:** "flood prediction, real-time computer vision, AI for health tech, and CRM automation." If CTO engagement is low, try cutting to three domains. The cross-domain range IS the differentiator per brief, but four in one sentence is the calibration edge.
- **"The pattern is always the same" is the least distinctive line.** Not weak enough to rewrite now, but first candidate for revision if About feels flat after publishing.

### CTA
- **English "say hi" vs Spanish "estoy por acá":** Spanish version is slightly more passive. If inbound from Spanish profile is low, switch to "escribime" (more direct, still casual). Monitor separately per language.

### Measurements (start tracking week 1)

| Signal | What to watch | Action trigger | Alternative ready |
|--------|--------------|----------------|-------------------|
| Headline click-through | Profile views → About reads | Low conversion after 4 weeks | More concrete headline openers explored in shaping session |
| CTO engagement | Comments/DMs from technical profiles | Near-zero after 8 weeks | Cut domains to 3, add more specific ML vocabulary |
| Spanish inbound | DMs/connections from LATAM | Zero after 6 weeks | Replace "estoy por acá" with "escribime" |
| "About" drop-off | Where people stop reading (track via profile view patterns) | High views, low engagement | Shorten P2 or move proof earlier |
| Domain list perception | Feedback on "jack of all trades" | Any CTO mentions it | Cut weakest domain, keep 3 strongest |

### Experimentation mindset

This profile copy is a validated starting point, not a final version. Every element was shaped through multiple rounds of discussion, criteria analysis, and adversarial challenge. Alternatives exist for most decisions. The approach: ship → measure → adjust. Don't optimize in the abstract — let real engagement data drive changes.

## Current LinkedIn Profile State (snapshot 2026-03-05)

Baseline before optimization. Screenshots at `~/Pictures/Screenshots/Screenshot From 2026-03-05 13-31-*.png`.

### Header
- **Name:** Martín Ríos
- **Headline:** `Machine Learning Engineer | Data Developer | MLOps | AI Systems Builder`
- **Photo:** Headshot with headphones
- **Banner:** Default blue/teal gradient (no custom banner)
- **Location:** Argentina
- **Website:** https://github.com/martineserios
- **Connections:** 500+
- **Followers:** 8,795
- **Open to Work badge:** Active — Data Specialist, Data Scientist, Data Consultant (REMOVE — contradicts positioning)
- **Verified:** No (LinkedIn prompting to verify)
- **Profile languages:** English (primary), Español (secondary) — already configured

### About (current — to be replaced)
> In the range of opportunities, I prioritize those where learning is necessary. I choose to work on projects that challenge me, force me to adapt and learn those things that I am interested in. On a second level, I have a penchant for those projects with social impact. I value working in multidisciplinary teams, motivated by goals, with an open communication tone.

Generic, no positioning, no systems lens, no proof. Full replacement decided (see Bilingual Strategy > About section copy).

### Experience (7 roles visible)

| # | Title | Company | Type | Period | Duration | Key skills shown |
|---|-------|---------|------|--------|----------|------------------|
| 1 | Data Developer | Upwork | Freelance | Mar 2023 - Present | 3y 1m | AWS SageMaker, Terraform +5 |
| 2 | Data Scientist | Encora | Contract | Sep 2021 - Jul 2024 | 2y 11m | Azure ML, Azure Databricks +3 |
| 3 | Machine Learning Engineer | Froneus | Full-time | Mar 2021 - Sep 2021 | 7m | spaCy, Rasa +4 |
| 4 | Data Scientist | Instituto Nacional del Agua | Freelance | Mar 2020 - Mar 2021 | 1y 1m | PyTorch, PostgreSQL +2 |
| 5 | Data Engineer | Galo AI | Freelance | Sep 2019 - Aug 2020 | 1y | Google DataPrep, BigQuery +1 |
| 6-7 | (not visible — "Show all 7 experiences") | | | | | Likely Digital House + 1 more |

**Issues:** Titles are role-based ("Data Developer", "Data Scientist") not system-problem-first. Descriptions are task-lists, not narratives. No systems lens. Upwork as current employer signals freelancer-for-hire, not consultant. Need full reframe per st-007.

### Skills
- **Total:** 47
- **Top visible:** LangGraph, Streamlit (too tool-specific, should lead with broader capabilities)
- **Needs reorder:** Top 3 should signal positioning — Machine Learning, System Design/Architecture, Python

### Education
- **Universidad de Buenos Aires** — Civil Engineer (2009-2018)
- Good — the arc is visible. No changes needed.

### Certifications
- DS4A / Latin America 2020: Graduated with Honors — Correlation One

### Languages
- Inglés only listed (should add Español as native)

### Causes
- Disaster and Humanitarian Relief · Science and Technology · Economic Empowerment · Poverty Alleviation

### Activity
- Recent comments: "Buenas!" (2mo ago), "Gran solución!" (11mo ago), "Grosso!" (11mo ago)
- Low engagement history — profile optimization is the foundation before content starts

## Pending decisions (tracked as tasks)

- t-174: Voice/tone guide — write 3-5 example posts defining natural voice
