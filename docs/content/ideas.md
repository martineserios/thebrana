# Content Ideas

<!-- Status: [seed] → [picked] → [written] → [published] -->
<!-- Cap: 10 active [seed] entries. Oldest seeds expire to [expired] when over cap. -->

## 2026-03-11

### [expired] The system that catches its own mistakes
- **Angle:** Built an adversarial review agent (/brana:challenge). It caught a critical architecture mistake — syncing event logs directly to repo would have broken multi-project logging. The correction loop saved hours of debugging.
- **Pillar:** Build-in-Public
- **Components:** "The correction loop"
- **Sources:** session handoff 2026-03-11 #7, ADR-015 sync fix, commits 43727cf/71b3d27/f186ba1

### [expired] 142 tasks synced in one command
- **Angle:** Built GitHub Issues sync for my task system. Bulk-synced 142 tasks. The gh CLI crashes with exit 134 when you pipe JSON output in certain sandboxes — had to redirect to temp files. The fix nobody documents.
- **Pillar:** How-To
- **Sources:** t-160, session handoff 2026-03-11 #6, commits e134bf5/a97e5f9/cec1dc1/8c7c6e5

### [expired] I built a graph of my own specs
- **Angle:** 40+ specification docs with cross-references. Changed one, broke three others silently. Built a dependency graph that auto-detects blast radius. Now every spec change knows what else it touches.
- **Pillar:** Build-in-Public
- **Components:** "The memory layer"
- **Sources:** ADR-016, t-348/350/353, spec-graph.json, commits 2bac31a/76e02fc/681cc86

### [picked] Stop writing prompts. Start writing specs.
- **Angle:** Three ADRs in one week: spec dependency graph, decision log, model routing. The pattern: specifications ARE the context. Not prompt engineering — specification-driven development. The spec tells the AI what to do better than any prompt.
- **Pillar:** Contrarian
- **Sources:** ADR-016/017/018, TurboFlow integration commit 1da021e

## 2026-03-12

### [expired] Your AI agent is burning 25,000 tokens you can't see
- **Angle:** Ghost tokens — invisible waste in AI agent systems. Most teams never measure actual token consumption vs useful output. Observability isn't optional for production AI. The silent bottleneck: you're paying for reasoning that goes nowhere.
- **Pillar:** How-To
- **Components:** "The silent bottleneck"
- **Sources:** Avi Pil LinkedIn post (t-182), production AI cost patterns

### [expired] Your AI agent doesn't need more tools — it needs a browser
- **Angle:** Pinchtab: 12MB binary, zero deps, pure HTTP API for AI agent browser control. Accessibility-first DOM. The pattern: agents that can see and interact with the web without Selenium/Playwright complexity. Infrastructure decision that changes what agents can do.
- **Pillar:** Case Study
- **Components:** "The bridge"
- **Sources:** Niranjan Akella LinkedIn post (t-190), agent infrastructure patterns

### [expired] Someone reverse-engineered Claude Code — here's what they found
- **Angle:** An engineer deconstructed Claude Code's internals and open-sourced the findings. What the architecture reveals about building AI-native dev tools: the system prompt, tool orchestration, context management. Reverse engineering as architecture learning.
- **Pillar:** How-To
- **Sources:** Ayel Magambetov LinkedIn post (t-210), Claude Code architecture

### [expired] AI agents that understand data governance exist — you're just not building them
- **Angle:** MCP (Model Context Protocol) + data governance. Most AI implementations ignore compliance until it's too late. The human gate: where the system stops and waits for a governance decision before proceeding. Building compliant AI from day one, not as an afterthought.
- **Pillar:** Case Study
- **Components:** "The human gate"
- **Sources:** Ronald Mego LinkedIn post (t-211), MCP governance patterns

### [expired] We're still building software like it's 2015
- **Angle:** The paradigm shift most teams resist: AI-native development isn't "add AI to your workflow" — it's rethinking the workflow from scratch. Waterfall → agile was painful. Agile → AI-native will be worse. The teams that adapt aren't the ones with the best models.
- **Pillar:** Contrarian
- **Sources:** Robert Kelly LinkedIn post (t-189), AI-native development patterns

### [expired] Open-source AI agents are eating the enterprise stack
- **Angle:** OpenClaw and similar frameworks: open-source agent architectures that rival enterprise tools. The correction loop: open-source agents learn faster because failures are visible. Why the next wave of AI infrastructure will be built in the open.
- **Pillar:** Contrarian
- **Components:** "The correction loop"
- **Sources:** Vinoth Govindarajan LinkedIn post (t-188), OpenClaw framework

## 2026-03-25

### [seed] How I cut 57% of my AI coding costs with one Rust CLI
- **Angle:** RTK (Rust Token Killer) rewrites command output before it enters context. 34 TOML filters, <10ms overhead, 57.6% savings measured on first session. The silent bottleneck: every `git status` was eating 80% more tokens than needed. One PreToolUse hook fixed it.
- **Pillar:** Case Study
- **Components:** "The silent bottleneck"
- **Systems:** stocks and flows — context window is a stock, tokens flow in, RTK reduces the inflow rate. Also: leverage point (#6 information flows — filtering what the system sees changes everything)
- **Sources:** t-626, `rtk gain` baseline (57.6%), RTK repo (github.com/rtk-ai/rtk), dim 46

### [picked] The 50-token trigger that controls which AI skill fires
- **Angle:** Claude Code reads ONLY the frontmatter description at startup to decide which skill to invoke. 50 tokens. That's the routing budget. Audited 34 skills — 5 had vague triggers that confused routing. The fix: verb-first, when-to-use, disambiguation. Routing architecture as a design discipline.
- **Pillar:** How-To
- **Components:** "The human gate"
- **Systems:** leverage point (#6 information flows) — 50 tokens of description determine which of 34 skills fires. Smallest input, largest behavioral change.
- **Sources:** t-625, ADR-025, dim 46 §2.1 (Dixit insight)

### [seed] How to calibrate your AI agent's judgment with 3 examples
- **Angle:** Anthropic's Bloom research: evaluators need few-shot examples and hard thresholds. Applied it to our challenger agent: 6 critical triggers, 5 warning triggers, 1-5 scoring rubric. Before calibration: subjective severity. After: any finding >= 4 forces RECONSIDER verdict. Three examples is all it took.
- **Pillar:** How-To
- **Components:** "The correction loop"
- **Systems:** negative feedback loop — calibration creates a balancing mechanism that prevents the challenger from over- or under-flagging. Three examples = the minimum viable regulator.
- **Sources:** t-637, Anthropic Bloom, CALIBRATION.md, dim 46 §6.3

### [seed] Strip your harness, don't grow it
- **Angle:** Anthropic's harness design article: "Every component encodes assumptions about model limitations. Re-evaluate after upgrades." Most builders add tools. Few ask: which tools are now redundant? Built a quarterly `/brana:review harness` check that traffic-lights every enforcement component. The contrarian move: subtract.
- **Pillar:** Contrarian
- **Components:** "The correction loop"
- **Systems:** adaptive cycle — conservation phase accumulates complexity (tools, rules, hooks). Release phase strips what's no longer needed. Most builders never enter release.
- **Sources:** t-638, Anthropic harness design article, /brana:review harness

### [seed] 5 security checks every Claude Code power user should run
- **Angle:** Built a 5-check scanner: secrets in CLAUDE.md (14 regex patterns), hook permission escalation, MCP token tax (4-17K per server), dangerous mode settings, unencrypted .env files. Most Claude Code setups have at least 2 findings. Zero dependencies, 30 seconds.
- **Pillar:** How-To
- **Sources:** t-636, /brana:audit skill, dim 46 §2.6 AgentShield

### [expired] Your AI agent's memory is already fine at 464 tokens
- **Angle:** Ran a design spike on "progressive disclosure memory." Finding: MEMORY.md is 116 lines, 464 tokens, well under Claude Code's 200-line auto-load limit. The system already uses progressive disclosure — heavy content is in linked files loaded on demand. The optimization everyone reaches for is already built in. Stop optimizing what isn't broken.
- **Pillar:** Contrarian
- **Sources:** t-635 spike, memory-framework.md, CC auto-memory docs

### [seed] What Anthropic's own engineers taught me about my agent system
- **Angle:** Anthropic Engineering published their harness design patterns. Mapped every finding against my existing system: 3-agent pattern validates our challenger, context anxiety confirms our context-budget rule, harness simplification principle became a new review check. Primary source → 4 task context updates + 2 new tasks in one session.
- **Pillar:** Build-in-Public
- **Components:** "The correction loop", "The memory layer"
- **Systems:** isomorphism — Anthropic's patterns and brana's patterns evolved independently to the same structures. Same system, different domains.
- **Sources:** dim 46, Anthropic harness design article, t-637/t-638

### [expired] I built a hook that watches my AI read files
- **Angle:** guard-explore: a PreToolUse hook that logs when AI reads implementation files without searching first. Week 1: logging only. Agentic Scripts measured 80% tool call reduction with search-first patterns. Raw data incoming — will know in 7 days if enforcement is justified. Building observability before policy.
- **Pillar:** Build-in-Public
- **Sources:** t-630, guard-explore.sh, dim 46 §2.2 (Agentic Scripts)

## 2026-03-27

### [seed] My deploy script confirms delivery before going live
- **Angle:** Built a WhatsApp campaign deploy pipeline that seeds real contacts from a Google Sheet, triggers messages, then polls the Kapso API for delivery confirmation before auto-migrating traffic. Three deploys, zero manual gates after the first. The bridge: connecting deployment to actual message delivery.
- **Pillar:** Case Study
- **Components:** "The bridge"
- **Systems:** delays — each step (seed → trigger → confirm → migrate) has a time gap. The pipeline makes the delays explicit and waits for each. Most deploys ignore the delay between "sent" and "delivered."
- **Sources:** proyecto_anita session 2026-03-21, deploy-multitenant.sh, smoke_test_confirm.py, 668 tests passing

### [seed] AI handles logistics, humans handle trust
- **Angle:** Planned unit economics for an AI training business (anit.ia). 4 Standard clients/mo = $4K/founder target. But the biggest open question isn't pricing — it's who the buyer is. 3 pilots will reveal the persona. You can model the economics perfectly and still not know who writes the check. AI handles the logistics. Humans handle the trust.
- **Pillar:** Contrarian
- **Systems:** quorum sensing — don't commit to the persona until 3 pilots accumulate evidence. The system waits for a threshold before acting, like a bee colony choosing a nest site.
- **Sources:** proyecto_anita/anit.ia session 2026-03-26, docs/features/capacitaciones-ia/

### [seed] A 22K-star framework puts prompts where I put specs
- **Angle:** SuperClaude: 22K stars, beautiful README, 32% context overhead (Issue #299). Their approach: inject system prompts that ask Claude to be better. My approach: specs that make it impossible to be worse. One is theater. One is architecture. The difference shows up in Issue #299.
- **Pillar:** Contrarian
- **Components:** "The correction loop"
- **Systems:** leverage point (#5 rules vs #12 parameters) — SuperClaude adjusts parameters (prompts). Specs change the rules the system operates under. Higher leverage, same cost.
- **Sources:** thebrana session 2026-03-26, t-651, dim 46 §6.2.1, SuperClaude repo

