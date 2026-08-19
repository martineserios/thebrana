---
name: terminal-diagrams
description: "Reference for drawing any diagram (flow, tree, comparison, architecture) as plain monospace terminal text — box-drawing/ASCII, no external renderer. Read directly when work-preferences.md's proactive trigger fires."
keywords: [diagram, ascii, terminal, visualization, box-drawing, architecture, flowchart, tree, comparison]
group: domain
allowed-tools:
  - Read
status: stable
source: "Primitives extend system/skills/backlog/phases/display-themes.md. Worked examples adapt conventions (glyph legends, verification checklists) from tjboudreaux/cc-visualization-skills (MIT) — tools-visual-ascii-arch, tools-visual-workflows, tools-visual-state-machines."
acquired: "2026-08-19"
---
# Terminal Diagrams

Draw any diagram shape as plain monospace text — no external renderer, no Mermaid, no
Artifact call. This is **reference material**: read it directly when a structural answer
(architecture, flow, hierarchy, comparison) would be clearer as a diagram than prose alone —
the trigger heuristic lives in `system/rules/work-preferences.md` §Terminal diagrams.

Not a closed list of diagram "types." Every diagram below is the same handful of primitives
composed differently — learn the primitives, then compose whatever shape the answer needs.

## Primitives

**Boxes and lines** (Unicode box-drawing — matches the vocabulary already established in
`display-themes.md`'s tree connectors):

```
┌─────────┐   corners: ┌ ┐ └ ┘     lines: ─ (horizontal) │ (vertical)
│  node   │   tree connectors: ├── └── │   (reuse display-themes.md exactly)
└─────────┘
```

**Arrows and connectors:**

```
→ ←  ↓ ↑     sync / direct flow
⇢ ⇠          async / eventual (dotted-in-spirit; Unicode has no dashed arrow, use ⇢)
├──          branch point (tree, decision fan-out)
```

**Alignment rules** (non-negotiable — a misaligned diagram is worse than none):
- Fixed-width monospace only. Count visual width, not byte/char count — wide glyphs (most
  emoji, some box-drawing corners) can render 2-cells wide in a terminal; when in doubt, stick
  to the plain single-width set above and verify by eyeballing column alignment before sending.
- Keep total width reasonable for a terminal pane — wrap or restructure past ~80-100 columns
  rather than letting a line run long and reflow.
- Label every node and every edge that isn't obvious from position alone.

## Worked examples

These four are the styles most explanations need — not the only ones the primitives support
(see **Composing other shapes** below).

### 1. Flow / pipeline

```
┌─────────┐      ┌─────────┐      ┌─────────┐
│  LOAD    │ ───→ │ CLASSIFY │ ───→ │  BUILD   │
└─────────┘      └─────────┘      └─────────┘
```

Branching flow (decision point):

```
        ┌──────────┐
        │  Input    │
        └────┬─────┘
             │
        ┌────▼─────┐
        │ Valid?    │
        └────┬─────┘
        yes ─┤─ no
        ┌────▼───┐   ┌────▼────┐
        │ Process │   │ Reject  │
        └────────┘   └─────────┘
```

### 2. Tree / hierarchy

Reuse `display-themes.md`'s exact connector convention — don't invent a parallel one:

```
epic-cc-alignment
├── t-2991  proactive terminal diagrams
│   ├── t-2991a  rule trigger heuristic
│   └── t-2991b  reference file
└── t-2837  upstream authoring guideline
```

### 3. Comparison table

Box-grid, aligned columns — for before/after or option-vs-option:

```
┌──────────────┬─────────────────┬─────────────────┐
│              │ Option A         │ Option B         │
├──────────────┼─────────────────┼─────────────────┤
│ Cost          │ Free             │ $10/mo           │
│ Setup         │ 5 min            │ 30 min           │
│ Vendor lock   │ None             │ High             │
└──────────────┴─────────────────┴─────────────────┘
```

### 4. Architecture / component

The hardest to lay out well — favor clarity over completeness; drop detail before letting
the diagram get unreadable:

```
┌─────────────────────────────────────────┐
│              CLI (brana)                  │
│  ┌─────────┐   ┌─────────┐   ┌─────────┐ │
│  │ backlog  │   │  build   │   │  time   │ │
│  └────┬────┘   └────┬────┘   └────┬────┘ │
└───────┼─────────────┼─────────────┼──────┘
        │             │             │
        ▼             ▼             ▼
   tasks.json     worktrees      time.jsonl
```

Annotate edges with protocol/mechanism where it matters: `HTTP`, `gRPC`, `sync call`,
`async event` — a label beats a bare arrow whenever the reader would otherwise have to guess.

## Composing other shapes

Every diagram is nodes (boxes) + edges (arrows/connectors) + labels. Shapes not covered above
compose from the same primitives:

- **State machine:** boxes = states, labeled arrows = transitions/triggers
  (`[New] --signup--> [Activated]`).
- **Timeline/swimlane:** a horizontal `|-----|-----|-----|` axis with labeled ticks underneath.
- **Sequence:** vertical lanes per actor, horizontal labeled arrows between them at each step.

If a shape genuinely doesn't fit fixed-width text (dense graphs, precise geometry, anything
needing color/interactivity), that's the signal to stop and use `artifact-diagramming`
(Mermaid → Artifact) instead — this skill is for what fits in a terminal pane.

## Verification before sending

- Every node labeled; every non-obvious edge labeled.
- Alignment checked by eye — columns line up, no ragged edges from width miscounts.
- If the diagram doesn't clarify faster than 2-3 sentences would, it wasn't worth drawing —
  drop it and use prose.
