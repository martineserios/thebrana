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
