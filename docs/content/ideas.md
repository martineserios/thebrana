# Content Ideas

<!-- Status: [seed] → [picked] → [written] → [published] -->
<!-- Cap: 10 active [seed] entries. Oldest seeds expire to [expired] when over cap. -->

## 2026-03-11

### [seed] The system that catches its own mistakes
- **Angle:** Built an adversarial review agent (/brana:challenge). It caught a critical architecture mistake — syncing event logs directly to repo would have broken multi-project logging. The correction loop saved hours of debugging.
- **Pillar:** Build-in-Public
- **Components:** "The correction loop"
- **Sources:** session handoff 2026-03-11 #7, ADR-015 sync fix, commits 43727cf/71b3d27/f186ba1

### [seed] 142 tasks synced in one command
- **Angle:** Built GitHub Issues sync for my task system. Bulk-synced 142 tasks. The gh CLI crashes with exit 134 when you pipe JSON output in certain sandboxes — had to redirect to temp files. The fix nobody documents.
- **Pillar:** How-To
- **Sources:** t-160, session handoff 2026-03-11 #6, commits e134bf5/a97e5f9/cec1dc1/8c7c6e5

### [seed] I built a graph of my own specs
- **Angle:** 40+ specification docs with cross-references. Changed one, broke three others silently. Built a dependency graph that auto-detects blast radius. Now every spec change knows what else it touches.
- **Pillar:** Build-in-Public
- **Components:** "The memory layer"
- **Sources:** ADR-016, t-348/350/353, spec-graph.json, commits 2bac31a/76e02fc/681cc86

### [picked] Stop writing prompts. Start writing specs.
- **Angle:** Three ADRs in one week: spec dependency graph, decision log, model routing. The pattern: specifications ARE the context. Not prompt engineering — specification-driven development. The spec tells the AI what to do better than any prompt.
- **Pillar:** Contrarian
- **Sources:** ADR-016/017/018, TurboFlow integration commit 1da021e

## 2026-03-12

### [seed] Your AI agent is burning 25,000 tokens you can't see
- **Angle:** Ghost tokens — invisible waste in AI agent systems. Most teams never measure actual token consumption vs useful output. Observability isn't optional for production AI. The silent bottleneck: you're paying for reasoning that goes nowhere.
- **Pillar:** How-To
- **Components:** "The silent bottleneck"
- **Sources:** Avi Pil LinkedIn post (t-182), production AI cost patterns

### [seed] Your AI agent doesn't need more tools — it needs a browser
- **Angle:** Pinchtab: 12MB binary, zero deps, pure HTTP API for AI agent browser control. Accessibility-first DOM. The pattern: agents that can see and interact with the web without Selenium/Playwright complexity. Infrastructure decision that changes what agents can do.
- **Pillar:** Case Study
- **Components:** "The bridge"
- **Sources:** Niranjan Akella LinkedIn post (t-190), agent infrastructure patterns

### [seed] Someone reverse-engineered Claude Code — here's what they found
- **Angle:** An engineer deconstructed Claude Code's internals and open-sourced the findings. What the architecture reveals about building AI-native dev tools: the system prompt, tool orchestration, context management. Reverse engineering as architecture learning.
- **Pillar:** How-To
- **Sources:** Ayel Magambetov LinkedIn post (t-210), Claude Code architecture

### [seed] AI agents that understand data governance exist — you're just not building them
- **Angle:** MCP (Model Context Protocol) + data governance. Most AI implementations ignore compliance until it's too late. The human gate: where the system stops and waits for a governance decision before proceeding. Building compliant AI from day one, not as an afterthought.
- **Pillar:** Case Study
- **Components:** "The human gate"
- **Sources:** Ronald Mego LinkedIn post (t-211), MCP governance patterns

### [seed] We're still building software like it's 2015
- **Angle:** The paradigm shift most teams resist: AI-native development isn't "add AI to your workflow" — it's rethinking the workflow from scratch. Waterfall → agile was painful. Agile → AI-native will be worse. The teams that adapt aren't the ones with the best models.
- **Pillar:** Contrarian
- **Sources:** Robert Kelly LinkedIn post (t-189), AI-native development patterns

### [seed] Open-source AI agents are eating the enterprise stack
- **Angle:** OpenClaw and similar frameworks: open-source agent architectures that rival enterprise tools. The correction loop: open-source agents learn faster because failures are visible. Why the next wave of AI infrastructure will be built in the open.
- **Pillar:** Contrarian
- **Components:** "The correction loop"
- **Sources:** Vinoth Govindarajan LinkedIn post (t-188), OpenClaw framework
