# Voice & Tone Guide

**Task:** t-174
**Status:** draft — iterate after first 12 posts
**Source:** [brief.md](brief.md) positioning, anti-positioning, content philosophy

---

## The Voice in One Line

A builder narrating what he sees — systems, layers, decisions — while he builds it.

---

## Trait Scales

Target tone defined from strategy. Your natural voice will pull these in its own direction as you write real posts. Recalibrate after Phase A (12 posts).

| Trait | Scale (0-100) | What it means here |
|-------|:---:|---|
| **Directness** | 85 | Lead with the point. No throat-clearing, no "I've been thinking about..." |
| **Formality** | 25 | Conversational. Contractions. Short sentences. Never academic. |
| **Technical depth** | 70 | Show the architecture, name the tools, reference real trade-offs. But frame for founders first. |
| **Confidence** | 75 | State what you know clearly. Never hedge what you've built. Admit what you don't know just as directly. |
| **Warmth** | 45 | Not cold, not effusive. Matter-of-fact with occasional dry humor. The warmth comes from honesty, not from trying to be likable. |
| **Abstraction** | 60 | Move between layers (the "zoom" format). Start concrete, pull up to the pattern, or start abstract and land in a specific terminal. |
| **Vulnerability** | 55 | Share failures and mistakes — but as data, not as emotional narrative. "This broke. Here's why. Here's what I learned." |
| **Opinionation** | 80 | Have a take. State it. Don't soften with "but that's just me" or "your mileage may vary." |
| **Humor** | 30 | Dry, rare, situational. Never forced. A well-placed aside, not a punchline. |

---

## Voice Rules

### 1. Builder first, writer second

Every sentence earns its place by connecting to something built, broken, or shipped. If a paragraph could appear in a generic "AI thought leader" post, cut it.

**Yes:** "I deployed Docker Swarm on Hetzner. Encrypted overlays silently drop packets on their private network. Took me 3 days to find it."
**No:** "Infrastructure decisions are critical in today's AI landscape."

### 2. Systems vocabulary — used, never explained

Use the language naturally. Don't define terms. Don't teach. The audience absorbs through repetition across posts.

**Yes:** "The silent bottleneck was the approval chain — 4 people for a decision that could be a rule."
**No:** "A bottleneck, in systems thinking, is a point where flow is constrained..."

### 3. Practitioner mode, not tutorial mode

Show what happened. Not how to do it. War stories and decisions, not step-by-step guides.

**Yes:** "We tried session-based auth first. Killed it after two weeks — stateless API needed JWT. Here's the decision that mattered."
**No:** "How to implement JWT authentication in FastAPI — a step-by-step guide."

### 4. The dual test

Before publishing, ask: does a founder hear "he solves my kind of problem"? Does a CTO hear "he thinks about architecture, not just code"? If only one passes, rewrite.

### 5. Concrete before abstract

Start with the specific thing that happened. Pull up to the pattern only after the reader is grounded in the real story. The zoom between layers is the content — but always enter from the ground floor.

**Yes:** "A surgical practice in Buenos Aires was losing 30% of leads between WhatsApp inquiry and first appointment. The system had no memory — every conversation started from zero."
**No:** "Memory layers in AI systems are often overlooked..."

### 6. Short > long

Sentences: 8-15 words is the sweet spot. Paragraphs: 1-3 sentences. Occasional one-word paragraph for punch. White space is a formatting tool.

If you can say it in fewer words, do.

### 7. Honest status, always

Pre-production is pre-production. "Designed and built" is not "running at scale." State exactly where things stand. The honesty IS the credibility signal.

### 8. Contrarian takes need proof

Don't be contrarian for attention. Be contrarian because you built something that showed you the other side. State the conventional view, state yours, show the evidence.

**Yes:** "Everyone says 'move fast and break things.' I spent 3 days on a deployment bug because I moved too fast. Now I spec first."
**No:** "Hot take: specs are underrated in AI. Agree?"

---

## Tone Shifts by Context

The voice stays the same. The tone adjusts slightly by pillar:

| Pillar | Tone adjustment |
|--------|----------------|
| **Case Studies** (35%) | Most narrative. Story structure: problem → system seen → solution → outcome/learning. Warmth +10. |
| **How-Tos** (25%) | Most technical. Architecture decisions, trade-offs, specific tools. Depth +10. Lean into the details. |
| **Contrarian Takes** (20%) | Most opinionated. Direct. Short paragraphs. High conviction. Opinionation +10. |
| **Build-in-Public** (20%) | Most personal. Behind-the-scenes, meta-system, numbers. Vulnerability +10. Let the process show. |

---

## Language Register

### English

Standard professional-casual. No slang, no academic jargon. Contractions always. "I" not "we" (solo practitioner). Technical terms used naturally (PyTorch, Docker Swarm, FastAPI — not explained).

Closer: **"Everything is a system. Map it."**

### Spanish

LATAM-neutral body. No voseo in body text. Professional but accessible — the kind of Spanish you'd use explaining something to a smart client in a meeting.

Exception: **"Todo es un sistema. Mapealo."** — rioplatense signature, intentional brand mark. Only voseo element.

---

## Patterns to Use

These are structural patterns, not templates. Mix and match.

### The Zoom
Enter at one abstraction layer, exit at another. The movement between layers IS the content.

> A WhatsApp message comes in. → A routing rule fires. → A CRM record updates. → A doctor sees a prioritized patient list. → That list is a system someone designed. → Systems are invisible until they break.

### The Reversal
Set up the expected conclusion, then land somewhere else.

> "After mapping the system, I told them they didn't need AI. They needed a shared spreadsheet and one rule."

### The Before/After
Draw the invisible system before you touched it. Then the after. The visual transformation is the post.

### The Cross-Domain
Same pattern, different skin. Flood prediction and patient flow share a pattern? That's the post.

### The Subtraction
What you removed matters more than what you added. "7 tools became 3 and a single flow."

---

## Components Shelf

Use these naturally. Never define them. They become your vocabulary over time.

- **"The human gate"** — where the system stops and waits for a person to decide
- **"The silent bottleneck"** — the process everyone works around but nobody sees
- **"The memory layer"** — where the system retains what it learned
- **"The bridge"** — the piece connecting a digital system to a non-digital process
- **"The correction loop"** — where the system learns from its own failures

More will emerge from writing. Add them here when they recur across 2+ posts.

---

## Anti-Patterns (things your voice is NOT)

| Anti-pattern | What it sounds like | Why it fails |
|---|---|---|
| **LinkedIn guru** | "3 things I learned about AI that changed my life" | Performative, no substance |
| **Tutorial author** | "Step 1: Install Docker. Step 2: Create a Dockerfile." | Attracts juniors, not clients |
| **Humble-brag** | "So humbled to announce..." | Dishonest signal |
| **Engagement bait** | "Agree? Disagree? Comment below!" | Manipulation |
| **AI hype merchant** | "AI will transform every industry by 2027" | Exactly the noise you're cutting through |
| **Vague visionary** | "The future of work is systems thinking" | No proof, no build, no substance |
| **Over-explainer** | Defining every term, adding disclaimers, qualifying every claim | Signals insecurity, slows the reader |

---

## Signature Elements

- **Closer:** "Everything is a system. Map it." / "Todo es un sistema. Mapealo." — ends every post and the About section. Means something different after every story.
- **Brand statement** (bio, headers): "Behind every effortless moment is a system someone built with care."
- **Career arc line** (when referencing background): "Civil Engineer. Then ML Engineer. The system changes. The lens doesn't."

---

## Iteration Protocol

This guide is a starting point — the strategic target. After each batch of posts:

1. Reread what you wrote. Which rules felt natural? Which felt forced?
2. Adjust trait scales based on what came out authentically
3. Add new components shelf terms that emerged
4. After 12 posts: full recalibration session — compare guide vs actual voice, close the gap from both sides
