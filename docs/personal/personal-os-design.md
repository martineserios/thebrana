# Personal OS — Framework & Design

**Date:** 2026-03-11
**Status:** Framework defined. Phase 0 ready to start.

---

## Part I: Philosophy

### Why This Exists

You have too many ideas and no structure to channel them. You're a builder who builds for others but hasn't turned the lens inward. You want your thinking to compound — not scatter across notebooks, apps, and conversations that die when the context closes.

This system exists to solve one problem: **make your thinking cumulative.** Every idea you capture, every book you read, every reflection you write should feed forward into the next one. Not through organization — through a practice that naturally connects things over time.

### Core Beliefs

**1. Thinking is the product, not a step toward one.**
You enjoy thinking and reflecting. This isn't a means to productivity — it's the core activity. The system serves thinking, not the other way around. If the system ever feels like overhead, it's broken.

**2. Range over depth.**
You're not building expertise in one domain. You're a connector — philosophy, self-help, technology, and the intersections between them. The value comes from collisions between domains, not mastery of one. The system must preserve range and reward unexpected connections.

**3. Ideas are yours. Expression is literary.**
You don't write to teach or prescribe. You build a world where your ideas live inside a narrative. The reader experiences the framework by entering the story, not by reading instructions. This means synthesis is not essay-writing — it's world-building. Notes become scenes, themes become characters, frameworks become plot.

**4. One funnel, one place.**
Everything enters through one channel: Telegram. Kindle highlights, voice notes, ideas, links, reactions. One intake. The system sorts, not you. Fighting your natural capture behavior is a design failure.

**5. Questions drive direction, not goals.**
You don't set targets — you follow questions. "What does autonomy really mean?" is more useful to you than "Write 3 essays this month." The active question is the compass. When the question evolves, the direction changes. That's not failure — that's thinking.

**6. 80% is perfect.**
You'll miss days. The system expects it and doesn't punish it. Three misses in a row is a signal to adjust the system, not to feel guilty. Perfection kills practices; consistency sustains them.

**7. Simple until proven insufficient.**
Every feature starts as the dumbest possible version. Complexity is earned by real friction, never by imagination. If a sticky note works, don't build an app. If an app works, don't build a platform.

### What Kind of Thinker You Are

- **Connector-challenger.** You collide ideas from different domains and question what seems obvious. Your thinking produces new perspectives, not expertise.
- **Range-driven explorer.** Travel, languages, sports, CS, philosophy — you don't optimize one thing, you range across many. Closer to Japanese ikigai (distributed meaning) than Western single-purpose.
- **High Openness, moderate Conscientiousness** (Big Five estimate). Ideas flow freely; structure doesn't come naturally. Systems must create structure without constraining flow.
- **Morning peak, no routine.** Energy is highest in the morning but the start time varies. The system triggers you — you don't trigger yourself.

### Domains of Thought

Your thinking ranges across:
- **Philosophy** — how to live, what matters, meaning
- **Self-help / living better** — practical frameworks for daily life
- **Technology** — what it enables, what it destroys, how to build
- **Intersections** — where these domains collide is where your original ideas live

---

## Part II: Information Treatment Model

### How Information Flows

```
INPUT                    PROCESS                     OUTPUT
─────                    ───────                     ──────
Kindle highlights ─┐
Voice notes ───────┤
Ideas ─────────────┼──→ Telegram Bot ──→ Journal ──→ Weekly Review ──→ Synthesis
Links ─────────────┤         │                            │                │
Conversations ─────┘         │                            │                │
                        (single funnel)              (notice themes)  (write to think)
                                                          │                │
                                                          ▼                ▼
                                                     Active Question    Writing
                                                          │            ┌───┴───┐
                                                          ▼            ▼       ▼
                                                       Reading     LinkedIn   Book
                                                          │         (byproduct) (world)
                                                          │
                                                          ▼
                                                    Extractions ──→ back to Journal
```

### The Five Stages of an Idea

Ideas don't follow a pipeline. They follow a **maturation cycle** — some mature fast, some take months, some compost and feed others invisibly.

| Stage | What happens | Where it lives | How long |
|-------|-------------|---------------|----------|
| **Raw** | It hits you — a highlight, a thought, a reaction | `journal/` | Seconds |
| **Noticed** | It reappears in weekly review — you see a pattern | `journal/` (highlighted) | 1-4 weeks |
| **Explored** | You read about it, think about it, write 300 words | `synthesis/` | Weeks |
| **Shaped** | You've refined it enough to share or use in narrative | `writing/drafts/` | Weeks-months |
| **Expressed** | It enters the world — LinkedIn, book, conversation | `writing/linkedin/` or `writing/book/` | When ready |

**Key principle:** Ideas can sit at any stage indefinitely. There is no pressure to advance them. The compost principle: ideas that don't resurface fed your thinking anyway. The system never nags about stale captures.

### How You Treat Each Input Type

| Input | What you do | What the system does |
|-------|------------|---------------------|
| **Kindle highlight** | Share to Telegram | Bot saves to today's journal with source tag |
| **Own idea** | Text or voice note to Telegram | Bot saves to today's journal |
| **Link/article** | Share to Telegram | Bot saves URL + your one-line reaction |
| **Book extraction** | "This book argues X. I think Y because Z." | Bot saves to `reading/{source}.md` |
| **Conversation insight** | Quick note to Telegram after the conversation | Bot saves to today's journal |

**The rule:** You never decide where something goes. You send everything to one place. The system routes it.

### How You Treat Reading

Reading is not a separate activity. It's part of the thinking loop.

1. **You read what your thinking demands.** Active questions (when they emerge) guide selection. But you also read what catches you — serendipity feeds the connector.
2. **Highlights flow to Telegram.** Kindle → share → bot captures.
3. **Extractions are in your words.** Not highlights alone — what you think about the highlight. "Seneca says X. I think this connects to my idea about Y."
4. **Unfinished books are fine.** You read to think, not to complete. When the question evolves, the book can change.
5. **No reading lists.** The stack of half-read books IS your reading list. If nothing pulls you, don't force it.

### How You Treat Writing

Three distinct practices, each with its own purpose:

**1. Thinking writing (private, daily)**
Morning prompt responses, captures, reactions. This is how you process the world. It's for you. It's never published. It's the raw material.

**2. Synthesis writing (semi-private, weekly)**
300-800 word pieces that emerge from the weekly review. You pick a thread and write about it — not to publish, but to understand it better. Writing as thinking tool. These accumulate and reveal the themes of your book.

**3. Expression writing (public, when ready)**
Two channels:
- **LinkedIn:** Professional content. Byproduct of synthesis — when a synthesis piece has a clear insight relevant to your audience, reshape it for LinkedIn. Never write LinkedIn-first. The thinking comes first.
- **Literary/Book:** Your real creative ambition. A narrative world where your framework lives implicitly. Not essays — stories, scenes, perspectives. The reader absorbs ideas by experiencing them. This is where your philosophy, self-help thinking, and technology observations merge into something original.

### How the Book Emerges

You don't write a book. You grow one.

1. **Months 1-6:** Daily captures + weekly synthesis accumulate. You don't think about the book.
2. **Month 3-4:** Recurring themes become visible. `writing/book/threads.md` starts tracking them.
3. **Month 6+:** 3-5 dominant themes have 5+ synthesis pieces each. These are your chapters — not by plan, but by emergence.
4. **The creative leap:** You take those themes and build a world around them. Characters embody your questions. Scenes illustrate your frameworks. The narrative carries the philosophy without lecturing.

The book's framework ("live better by applying a framework") becomes visible through the story, not stated explicitly. The reader finishes the book and has absorbed the framework by living inside it.

---

## Part III: Thinking Frameworks

### The Connector's Toolkit

These are the intellectual moves your system supports and rewards:

**1. Collision.** Take two ideas from different domains and ask: what happens if they're both true? Philosophy + technology. Stoicism + AI. Self-help + fiction. The system helps by surfacing connections across your captures — the weekly review is where collisions happen.

**2. Challenge.** Take something you believe and ask: what if I'm wrong? The morning prompt ("What do I believe that might be wrong?") makes this a habit. Your beliefs file (`identity/beliefs.md`) is a living document — entries get crossed out and replaced, not preserved.

**3. Perspective shift.** How would someone from a completely different context see this? A Stoic philosopher, a tech CEO, a farmer, a child. The system supports this by keeping your range wide — reading across domains, not narrowing.

**4. Depth on demand.** When a collision or challenge produces something interesting, go deep. Find the book, the paper, the thinker who explored this before you. Extract their reasoning. Agree or disagree. This is where `questions/active.md` earns its existence — but only when the question emerges naturally.

### Frameworks Applied to Daily Practice

| Framework | How it shows up | When |
|-----------|----------------|------|
| **Stoic morning preparation** | Prompt + one intention | Every morning |
| **Atomic Habits (Clear)** | Bot ping = cue, response = routine, rereading = reward | Every morning |
| **Identity framing (Clear)** | "I am someone who thinks before doing" | Background |
| **Ikigai (Japanese)** | Distributed meaning — range is the point, not focus | Background |
| **Deep Work (Newport)** | Reading blocks are protected focus time | 2-3x/week |
| **Forte CODE** | Capture with a verb, express to create | Capture + synthesis |
| **Progressive summarization (Forte)** | Raw → noticed → explored → shaped | Idea maturation |
| **PPV alignment check (Bradley)** | "Is what I did connected to what matters?" | Weekly review |
| **Stoic evening review (Seneca)** | What worked, what didn't, what to practice | Weekly review |
| **Graeber's meaning test** | "Would anyone notice if I stopped?" | Quarterly check |
| **Narrative Identity** | Rewrite your story to guide future choices | Quarterly |
| **Dichotomy of control** | Redirect energy to what you influence | When overwhelmed |
| **Energy > time (Abdaal)** | Design around energy, protect morning peak | Always |

---

## Part IV: Structure

### Where It Lives

Separate repo: `~/enter_thebrana/personal/`

Same ecosystem as brana, own git history. Research docs in `thebrana/docs/personal/` are inputs — this is the output. Different things.

### File Structure

```
personal/
├── identity/                 ← WHO YOU ARE (changes slowly)
│   ├── mission.md            ← one sentence + the problem chain (P0, P1, P2)
│   ├── values.md             ← 5-7 ranked values (Schwartz-informed)
│   ├── beliefs.md            ← things you hold true, updated when proven wrong
│   ├── models.md             ← mental models for decisions
│   └── narrative.md          ← "the story so far" (rewritten quarterly)
│
├── journal/                  ← THE THINKING LOOP (changes daily)
│   ├── 2026-03-11.md         ← one file per day: prompt + response + captures
│   └── ...
│
├── questions/                ← WHAT YOU'RE TRYING TO UNDERSTAND
│   ├── active.md             ← current 1-3 questions driving reading
│   └── resolved.md           ← past questions + conclusions
│
├── reading/                  ← EXTRACTIONS (your words, not theirs)
│   ├── {book-or-source}.md   ← one file per source
│   └── ...
│
├── synthesis/                ← WEEKLY OUTPUTS
│   ├── 2026-w11-theme.md     ← week + theme
│   └── ...
│
├── writing/                  ← EXPRESSION LAYER
│   ├── drafts/               ← literary pieces in progress
│   ├── linkedin/             ← published or ready-to-publish
│   └── book/                 ← book threads
│       └── threads.md        ← running index of recurring themes
│
└── review/                   ← SYSTEM HEALTH
    └── weekly-log.md         ← append-only: date + themes + thread + ritual tracker
```

### Why This Shape

**`identity/`** — Five files. Written once, revisited quarterly. `beliefs.md` is the most alive — entries get challenged and replaced. `narrative.md` evolves most — your story, rewritten as your understanding shifts.

**`journal/`** — One file per day. Everything from that day in one place. No categorization at capture time. The weekly review extracts meaning — the journal is raw material.

**`questions/`** — The engine. 1-3 active questions drive reading and thinking. When answered or stale, they move to `resolved.md` with conclusions. New questions emerge from weekly review. Only activate this when questions emerge organically from practice.

**`reading/`** — Not a catalog. Only sources you're extracting from. Your words: "This argues X, I think Y because Z." Partial extractions are fine — you moved on because the question changed.

**`synthesis/`** — Weekly review output. 300-800 words. Named by week + theme. Building blocks of the book. After 6 months, this folder IS your first draft material.

**`writing/`** — Where synthesis graduates to. `drafts/` for literary work. `linkedin/` for professional content. `book/threads.md` tracks the 3-5 recurring themes — your table of contents emerging organically.

**`review/`** — One file, append-only. Date, themes, chosen thread, 7 binary checkmarks. That's it.

### What's NOT Here

- No `goals/` — questions drive direction, not OKR spreadsheets
- No `habits/` — one binary metric in the weekly log
- No `projects/` — that's brana's tasks.json
- No `health/` or `relationships/` — add only when you feel the pull
- No tags, categories, metadata — chronology and filenames are enough

---

## Part V: Rhythms

### Daily

| When | What | Time |
|------|------|------|
| Morning (triggered) | Respond to prompt + set one intention | 5-10 min |
| During day | Capture to Telegram (ideas, highlights, reactions) | Async, zero effort |

### Weekly

| When | What | Time |
|------|------|------|
| Fixed day (TBD) | Read week's journal. Notice themes. Pick one thread to deepen, one to write about. | 30 min |

### Quarterly

| When | What | Time |
|------|------|------|
| Every ~3 months | Rewrite `narrative.md`. Review/update `beliefs.md`. Check alignment. | 1 hour |

### The Morning Ritual

**Trigger:** Telegram bot sends a prompt (Phase 0: phone alarm).

**Three rotating prompt modes:**
1. **Reflect:** "What's on your mind right now?"
2. **Deepen:** "Yesterday you wrote about X. What's one thing you still don't understand about it?"
3. **Challenge:** "What do I believe that might be wrong?"

**Then:** One intention — "Today, the one thing that matters is ___"

**Rules:**
- Morning is thinking, not admin (Abdaal's "no planning" rule)
- Prompts rotate across all domains, not just work
- Voice notes count — no pressure to type perfectly
- 80% completion target. Miss a day, fine. Three in a row = adjust the system.

### The Weekly Review

**One job:** Read what you captured and find what matters.

**Process:**
1. Read the week's journal entries
2. What themes kept showing up?
3. What surprised you?
4. Pick ONE thread to deepen through reading
5. Pick ONE thread to write about (synthesis)
6. Quick check: "Is what I spent time on connected to what I say matters?"
7. Log: date + themes + thread + 7 ritual checkmarks

**Output:** One thread to read about, one to write about. Nothing more.

---

## Part VI: Brana Integration

The personal space is content. Brana is the system that helps you work with it.

| Brana feature | What it does | Phase |
|---------------|-------------|-------|
| Telegram bot | Single intake: prompts, capture, highlights → `journal/` | 0-1 |
| `/brana:log` | Quick capture fallback when not on Telegram | Now |
| `/brana:research` | When active question needs sourcing → finds books/papers | 1+ |
| `/brana:close` | Session end → extracts personal learnings | Now |
| Weekly review skill | Reads week's journal, surfaces themes, helps draft synthesis | 2+ |
| Reading recommender | Reads `questions/active.md` → suggests sources | 3+ |
| Connection finder | Surfaces links between captures across weeks/months | 3+ |

---

## Part VII: Workflows (Target — Phase 2+)

### Triggers

| Trigger | What fires | How |
|---------|-----------|-----|
| Morning nudge | Daily ritual | Telegram bot sends prompt |
| Capture impulse | Idea lands | Message the bot |
| Kindle highlight | Reading extraction | Share from Kindle to Telegram |
| Weekly anchor | Review session | Calendar event + bot reminder |

### Flow 1: Morning Ritual
```
Bot sends prompt → respond (text/voice) → bot logs to journal/{date}.md
    → bot echoes yesterday's intention → set today's intention → done
```

### Flow 2: Capture
```
Send anything to bot → bot appends to journal/{date}.md under "## Captures"
    → silent save → optional: bot asks "connected to [active question]?"
```

### Flow 3: Kindle Integration
```
Share highlight from Kindle → bot saves to journal/{date}.md with source tag
    → if you add a reaction, it's saved alongside the highlight
    → reading/{source}.md gets created/appended automatically
```

### Flow 4: Weekly Review
```
Bot pulls week's entries → presents top themes by frequency
    → pick one thread to deepen, one to write about
    → bot creates synthesis/{week}-{theme}.md skeleton
    → Stoic retrospective + alignment check
    → bot updates review/weekly-log.md
```

### Flow 5: Reading Integration
```
Active question emerges → bot (or /brana:research) searches for sources
    → pick one → read → share extractions to Telegram
    → bot logs to reading/{source}.md
    → extractions feed next weekly review
```

### Flow 6: Synthesis → Expression
```
3-4 synthesis pieces on same theme → bot flags "ready to draft?"
    → bot compiles related syntheses into writing/drafts/{theme}.md
    → shape it → move to linkedin/ or book/ when ready
```

### Flow 7: Quarterly Narrative
```
~3 months of practice → bot (or you) prompts story rewrite
    → pull last quarter's syntheses + resolved questions
    → rewrite identity/narrative.md
    → review/update identity/beliefs.md
```

### Behavioral Principles

1. **"One active question" rule** — 1-3 questions at a time. Everything orbits them. But they emerge from practice, not from planning.
2. **"Compost" principle** — unused captures are fine. They fed your thinking even if they never became a synthesis. No nagging.
3. **"Don't break chain, forgive the break"** — 80% target. Three misses = system adjustment, not guilt.
4. **"Energy-first" rule** — morning = thinking only. Admin, logistics, review = later.
5. **"Read to think, not to finish"** — abandon books freely. Follow the question.
6. **"Write to understand, share when ready"** — synthesis is private thinking. Expression happens when the idea demands it, not on a calendar.
7. **"One funnel"** — everything enters through Telegram. You never decide where something goes. The system routes.

---

## Part VIII: Phased Rollout

### Phase 0: The Dumb Version (30 days)

**Purpose:** Prove the practice before building the product.

| What | How | Tool |
|------|-----|------|
| Morning prompt | Phone alarm or basic Telegram bot | Alarm / Telegram |
| Respond | Answer one of 3 prompts + set intention | Text or voice |
| Capture during day | Send to Telegram (self-message or bot) | Telegram |
| Weekly review | Read the week's entries. One surprise. Two sentences. | 10 min |
| Writing | When you feel like it | Whatever |

**Three prompts (rotate daily):**
1. "What's on my mind right now?"
2. "What did I think about yesterday that I still don't understand?"
3. "What do I believe that might be wrong?"

**Track:** Binary morning ritual. 80% target.

**At 30 days, answer:**
1. Did I actually do it? (<50% = redesign the practice, not the tool)
2. What was annoying enough to automate?
3. What structure did my content naturally fall into?
4. Did active questions emerge organically?
5. Did I want to write? When? About what?

### Phase 1: Add Structure (month 2)

Based on Phase 0 learnings. Create only the structure you actually need.

### Phase 2: Build the Bot (month 3+)

Automate only the friction you experienced. Telegram bot with exactly the features Phase 0-1 proved necessary.

### Phase 3: Full Architecture (when earned)

Each component from the target design activates when the previous layer is solid.

---

## Part IX: Source Frameworks

| Framework | What we took | What we left |
|-----------|-------------|--------------|
| Miessler Telos | Problem chain, mission, beliefs/models files, signal capture concept | 10-file structure, named personas, voice interface |
| Forte PARA/BASB | Actionability principle, CODE express step, progressive summarization | PARA categories, "capture everything" mindset |
| Bradley PPV | Alignment check, review cadences | Notion implementation, full complexity |
| Abdaal | Energy > time, "no planning" mornings, journaling prompts | Content pipeline, MILES |
| Stoicism | Morning preparation, weekly review, dichotomy of control | — (took most of it) |
| Ikigai (Japanese) | Distributed meaning — range, not single mission | Western 4-circle Venn |
| Graeber | "Would anyone notice?" filter | — (diagnostic only) |
| Newport | Deep work blocks for reading, attention as budget | Time-blocking rigidity |
| Clear | Identity-based habits, cue-routine-reward, 2-min rule | — (took most of it) |
| Narrative Identity | Quarterly story, coherence → well-being | — |
| Big Five | Design systems that work WITH your traits | Formal assessment (later) |
| Schwartz Values | Values hierarchy for `values.md` | Full 10-value mapping (later) |

---

## Part X: Challenge Log

### 2026-03-11 — Simplicity Challenge (Opus)

**Verdict: RECONSIDER → adopted as Phase 0**

Critical findings accepted:
- System depends on bot that doesn't exist → start without bot (or minimal bot)
- Six workflows for someone who gets overwhelmed → start with one workflow

Warnings accepted:
- Graduation pattern may be a publishing pipeline → reframed as "maturation cycle" (ideas sit at any stage indefinitely)
- Weekly review does too much → simplified for Phase 0
- Active questions driving reading may be backwards → let them emerge organically

Decision: Keep full design as target. Start with 30-day practice. Build only what solves real friction.

---

## Part XI: Workflow Catalog

Ten workflows derived from the research. These are **designs, not tasks** — nothing gets built until the practice earns it (see Gated Build Order below).

### W1. Weekly Review Ritual
**Source:** Stoicism (Seneca evening review) + Bradley PPV (alignment zone) + Forte CODE (express step)

The keystone workflow. Everything feeds in (journal, captures, reading), everything flows out (synthesis, questions, themes).

**Behavior:**
1. Read this week's `journal/*.md` entries
2. Surface recurring themes by frequency (words, topics, emotions)
3. Present: "These themes kept showing up: X, Y, Z"
4. Pick ONE thread to deepen through reading, ONE to write about
5. Bradley alignment check: "Is what you spent time on connected to what you say matters?"
6. Append to `review/weekly-log.md`: date, themes, chosen threads, 7 binary ritual checkmarks
7. Create `synthesis/{week}-{theme}.md` skeleton

**Implementation:** `/brana:review-personal` skill. Trigger: Sunday reminder via bot + available as skill anytime.

**Prerequisite:** 4+ journal entries per week for 4 consecutive weeks.

### W2. Morning Ritual Enhancement
**Source:** Stoicism (morning preparation) + Atomic Habits (cue-routine-reward)

The bot already sends prompts. This closes the loop.

**Behavior:**
- Echo yesterday's intention before today's prompt: "Yesterday you said: ___. How did it go?"
- Deepen mode references actual journal content: "Yesterday you wrote about X. What don't you understand about it?"
- Optional evening micro-check (1 message): "One word for today?" — Seneca's review at minimum friction

**Implementation:** `bot.py` enhancement. Small — maybe 20-30 lines.

**Prerequisite:** Consistent morning prompt replies (15+ in 21 days).

### W3. Identity Docs as Guided Conversations
**Source:** Miessler Telos (problem chain) + Narrative Identity + Schwartz Values

Identity docs can't be written by Claude alone — they require your input. But the conversation can be guided.

**Behavior:**
- Interactive session walks through Telos exercise: problems → mission → values → beliefs → narrative
- Uses the 30-minute self-knowledge exercise from personality research as entry point
- Persists answers to `identity/*.md` as you go
- Quarterly trigger: revisit `narrative.md` based on what changed

**Implementation:** `/brana:think identity` subcommand or standalone guided session.

**Prerequisite:** 30+ journal entries. Identity themes should be EXTRACTED from what you've already written, not declared in the abstract.

### W4. Kindle/Reading Integration
**Source:** Forte Progressive Summarization + design doc Flow 3

**Behavior:**
- Bot detects shared text with book-like patterns (quotes, page references) → routes to `reading/{source}.md`
- Prompts: "What do you think about this?" — your reaction is the extraction, not the highlight
- Weekly review surfaces reading themes alongside journal themes

**Implementation:** `bot.py` pattern detection + routing. Maybe 40 lines.

**Prerequisite:** You're actually reading and want to capture highlights. Don't build before the pull exists.

### W5. Synthesis → Expression Pipeline
**Source:** Forte CODE Express + design doc Flow 6

**Behavior:**
- Scans `synthesis/` for theme clusters
- Flags when 3+ synthesis pieces orbit one theme: "Ready to draft?"
- Compiles related pieces into `writing/drafts/{theme}.md`
- For LinkedIn-ready pieces, reshapes through `/brana:harvest` content lens

**Implementation:** Extension of `/brana:harvest` (already exists for LinkedIn).

**Prerequisite:** 10+ synthesis files. Themes must emerge, not be assigned.

### W6. Question Engine
**Source:** design doc + Newport Deep Work

**Behavior:**
- Weekly review naturally surfaces questions ("I keep writing about X but don't understand Y")
- Capture to `questions/active.md` with origin context
- Active question scopes `/brana:research`: "Find sources that address: {question}"
- Reading extractions tag back to the question they're exploring
- When answered → move to `resolved.md` with conclusion

**Implementation:** Light — mostly convention + weekly review integration.

**Prerequisite:** Questions emerge organically from the practice. Never force them.

### W7. Connection Finder
**Source:** Ikigai (range over depth) + Forte progressive summarization

**Behavior:**
- Scans `journal/`, `synthesis/`, `reading/` for semantic overlaps across time
- Surfaces: "You wrote about X three weeks ago and Y this week — they might connect"
- Uses keyword overlap or embeddings

**Implementation:** Part of weekly review or standalone `/brana:think connections`.

**Prerequisite:** 3+ months of journal + synthesis. Needs volume for meaningful connections.

### W8. Book Thread Tracker
**Source:** design doc Part II (how the book emerges)

**Behavior:**
- After months of synthesis, scan for dominant themes (5+ pieces each)
- Auto-populate `writing/book/threads.md` with theme clusters, linked to source synthesis files
- Table of contents emerges organically

**Implementation:** Script or skill that reads synthesis/ and clusters.

**Prerequisite:** 6+ months of synthesis writing. This is the longest-horizon workflow.

### W9. Energy-Aware Scheduling
**Source:** Abdaal (energy > time) + health research

**Behavior:**
- If health tracking adopted (single wearable → 5 metrics), weekly review includes energy pattern
- "Your best journal entries happen on mornings after 7+ hours sleep"
- Adjust bot prompt timing based on actual wake patterns

**Implementation:** Health data integration + bot scheduling adjustment.

**Prerequisite:** Wearable device + 30 days of data. Low priority until practice is solid.

### W10. Relationship Memory
**Source:** Dunbar layers + Ferrazzi 80/20 pinging

**Behavior:**
- File-based people registry (`people/{name}.md`)
- Dunbar layer assignment (inner 5, close 15, good 50)
- Bot captures after conversations: "Just talked to X about Y"
- Periodic nudge: "Haven't connected with {inner-5-person} in 3 weeks"

**Implementation:** New directory + bot integration + scheduled nudges.

**Prerequisite:** Social practice established. Build when you feel the pull, not before.

---

## Part XII: Gated Build Order

Nothing gets built until its gate clears. Gates are sequential — each requires proof before advancing.

| Gate | Action | Proof to advance |
|------|--------|-----------------|
| **Gate 0** | Use the bot as-is. Reply to morning prompts. Optionally add evening nudge (5 lines in bot.py). | 15+ journal entries in 21 days |
| **Gate 1** | Manual weekly review: calendar reminder, text editor, 15 min. Extract identity themes from existing entries. | 4 consecutive weekly reviews with actual output in `review/weekly-log.md` |
| **Gate 2** | Build W1 (`/brana:review-personal`). It has data to work with and a proven habit to automate. | Skill used 4+ times with real output |
| **Gate 3** | Build W2 (morning enhancement) + W3 (identity docs from journal themes). | Identity docs written, morning reply rate stable |
| **Gate 4** | Build W4-W6 as the practice demands. Only what solves real friction. | Organic pull — you're doing the behavior manually and it's annoying |
| **Gate 5** | W7-W10. Long-horizon. Months away. | Volume exists (50+ synthesis files, 3+ months data) |

**Rules:**
- Workflows live here as designs. They enter `tasks.json` only when their gate clears.
- Clearing a gate = the behavior exists FIRST, the tool follows.
- If a gate stalls for 30+ days, reconsider the workflow — maybe the behavior isn't wanted.

---

## Part XIII: Open Design Work

- [x] Pick morning alarm time window → 8 AM Buenos Aires
- [ ] Pick weekly review day (Sunday proposed)
- [x] Start Phase 0 → bot deployed, prompts running
- [x] Build minimal Telegram bot → `bot.py` on Oracle Cloud
- [ ] Share bookshelf → refine domains of thought
- [ ] Book framework deeper definition
- [ ] Identity files (deferred to Gate 3 — extract from journal, don't declare)
- [ ] Phase 0 retrospective (after Gate 0 clears)
- [ ] Brana skill design: `/brana:think` (Gate 3)
- [ ] Brana skill design: `/brana:review-personal` (Gate 2)
- [ ] Decide operating frameworks for Q2: pick 2 from the 9 researched (recommended: Atomic Habits + Stoicism)
- [ ] Define ghost-completion prevention: tasks with `type: recurring` require 3+ uses before `completed`

---

## Part XIV: Challenge Log

### 2026-03-11 — Simplicity Challenge (Opus)

**Verdict: RECONSIDER → adopted as Phase 0**

Critical findings accepted:
- System depends on bot that doesn't exist → start without bot (or minimal bot)
- Six workflows for someone who gets overwhelmed → start with one workflow

Warnings accepted:
- Graduation pattern may be a publishing pipeline → reframed as "maturation cycle" (ideas sit at any stage indefinitely)
- Weekly review does too much → simplified for Phase 0
- Active questions driving reading may be backwards → let them emerge organically

Decision: Keep full design as target. Start with 30-day practice. Build only what solves real friction.

### 2026-03-17 — Simplicity Challenge (Opus)

**Verdict: RECONSIDER → adopted as Gated Build Order**

Critical findings accepted:
- Practice doesn't exist yet (2 entries in 6 days) — automating nothing
- Weekly review has nothing to review — build it after journal volume exists
- 52% ghost completion rate is the real problem — building more workflows feeds the pattern

Warnings accepted:
- Four Tier 1 items fragments attention → sequential gates instead
- Identity docs premature → extract from journal themes, don't declare in abstract
- Nine frameworks is six too many → pick 2 operating frameworks per quarter
- Kindle integration solves a problem that doesn't exist yet

Decision: Capture all 10 workflows as designs in the doc. Gate their build behind behavioral proof. Nothing enters tasks.json until its gate clears. The framework shapes as you iterate — the practice leads, the tooling follows.
