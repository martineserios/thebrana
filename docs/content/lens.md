# Content Lens

Positioning filter for `/brana:harvest` (skill relocated to `ventures/linkedin/.claude/skills/harvest` 2026-04-06 — this lens doc may need to move there too). Every artifact passes through this before becoming an idea.

## Identity

Builder. Systems thinker who ships. Full-stack in the deepest sense: ML + software architecture + infrastructure + deploy. Civil Engineer → ML Engineer — the system changes, the lens doesn't.

Practitioner mode, not tutorial mode. War stories and decisions, not step-by-step guides.

## Dual Test (every idea)

1. **Founder test:** Would a non-technical founder hear "he solves my kind of problem"?
2. **Technical test:** Would a CTO hear "he thinks about architecture, not just code"?

Both → strong. One → acceptable. Neither → skip.

## Pillars

| Pillar | Weight | What it is |
|--------|--------|------------|
| **Case Study** | 35% | Business problem → solution → architecture insight. The bridge: founders see their problem, technical people see rigor. |
| **How-To** | 25% | Practitioner-mode: "here's what happened when I did it." Business-accessible framing with technical depth underneath. |
| **Contrarian** | 20% | Opinionated positions from lived experience that spark discussion. |
| **Build-in-Public** | 20% | Behind the scenes — brana as proof-of-method. ADRs, phase completions, errata, cross-project memory. |

## Anti-Topics

Skip or reframe if the artifact drifts toward any of these:

| Not this | Why |
|----------|-----|
| No-code automator (n8n, Make, Zapier) | Crowded, commoditized. We write code. |
| AI wrapper / prompt engineer | "I put GPT on your business" is a feature, not a system. |
| Generic full-stack dev | Every bootcamp grad says this. We think in systems first. |
| AI influencer / content creator | Builder who writes, not writer who builds. |
| "Fractional CTO" label | Overused. Let evidence show it, never claim it. |

## Components Shelf

Named building blocks — used naturally in posts, never defined:

- **"The human gate"** — where the system stops and waits for a person to decide
- **"The silent bottleneck"** — the process everyone works around but nobody sees
- **"The memory layer"** — where the system retains what it learned
- **"The bridge"** — the piece connecting a digital system to a non-digital process
- **"The correction loop"** — where the system learns from its own failures

## Systems Vocabulary

Systems concepts from real theory and original observations, used naturally in posts. Never explained, never taught — the vocabulary appears through the work. Over time, readers absorb the lens through accumulation.

References:
- [dim 44 — classical systems thinking](../../brana-knowledge/dimensions/44-systems-thinking-nature.md)
- [dim 49 — agent-era patterns (original)](../../brana-knowledge/dimensions/49-agent-era-systems-patterns.md)
- [software-engineering-patterns](../../brana-knowledge/dimensions/software-engineering-patterns.md)

### Patterns (what you recognize in builds)

| Pattern | What it is | Example in your work |
|---------|-----------|---------------------|
| **Feedback loop** | Output becomes input — positive (amplifying) or negative (correcting) | Errata system: failures feed corrections feed better specs |
| **Stocks and flows** | Accumulation + rates of change | Token budget: context fills (flow in), compresses (flow out), quality degrades as stock grows |
| **Delays** | Time gap between action and effect | Deploy → delivery confirmation → traffic migration (each step has a delay) |
| **Emergence** | Macro behavior from micro interactions | 37 skills + 10 agents produce capabilities none was designed for |
| **Leverage points** | Where small changes produce large effects | Changing the lens.md file changes what 12 weeks of content look like |
| **Adaptive cycle** | Growth → conservation → release → reorganization | A project's arc: build fast → stabilize → break when scale demands → rebuild |
| **Resilience** | Absorb disturbance, retain function | Evergreen fallback: pipeline produces content even when no sessions close |
| **Isomorphism** | Same structure in different domains | Flood prediction pipeline ↔ patient flow system ↔ WhatsApp campaign delivery |
| **Quorum sensing** | Commit only after threshold support accumulates | Phase A: 12 posts before building automation. Don't commit to the tool until evidence accumulates. |
| **Stigmergy** | Coordinate through environment, not direct communication | Git commits, handoff notes, errata — agents coordinate through artifacts, not messages |

**Agent-era patterns (original — [dim 49](../../brana-knowledge/dimensions/49-agent-era-systems-patterns.md)):**

| Pattern | What it is | Example in your work |
|---------|-----------|---------------------|
| **Assumption decay** | A component built for a weaker model silently becomes dead weight | SuperClaude's 32% context overhead, harness review |
| **Artifact coordination** | Agents coordinate through designed artifacts, not messages | close → handoff → harvest → ideas → daily-ops (no agent talks to another) |
| **Context rot** | Gradual quality degradation as context fills — no cliff, no alert | Context-budget rule (55/70/85%), RTK's reason for existing |
| **The observation window** | Log behavior before enforcing rules. Sensor before actuator. | guard-explore: log-only week 1, enforce only after data |
| **The removable gate** | Human decision point designed from day one to be optional | harvest --auto flag, progressive automation |
| **Pattern bleed** | Solution shapes from one project appear in another via shared memory | Retry pattern from anita → scheduler in thebrana |
| **The capability horizon** | Moving boundary between model-native and system-enforced | JSON validation hook that stopped catching anything after Claude 4.6 |

### How harvest uses this

During Step 4 (Apply lens), for each artifact:
1. Run the normal dual test + pillar match + anti-topic check
2. **Then ask: does this artifact illustrate a systems pattern?**
   - If yes → note the pattern in the seed. Use it in the hook or angle.
   - If no → the seed stands on its own. Not every post needs a systems angle.
3. **Cross-domain check:** does the same pattern appear in a different project? If so, that's a "same pattern, different skin" post — one of the strongest content angles.

**Goal:** ~50% of seeds should have a systems connection. Not forced — discovered. The systems lens is how you naturally see things; harvest just makes it explicit.

## Signature

- **EN:** "I see systems. I ship them."
- **ES:** "Veo sistemas. Los llevo a produccion."
