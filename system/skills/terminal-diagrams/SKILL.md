---
name: terminal-diagrams
description: "Draw and check terminal diagrams: flow, sequence, state, data flow, swimlane, decision table, ER, dependency. Read when work-preferences.md's trigger fires."
keywords: [diagram, visualization, ascii, terminal, box-drawing, flowchart, sequence, state machine, data flow, swimlane, decision table, causal loop, ER, dependency graph, architecture, tree, comparison]
group: domain
allowed-tools:
  - Read
status: stable
---
# Terminal Diagrams

Draw processes, flows, structures and logic as plain monospace text in the response, with no
external renderer. This is **reference material**: read it when a structural answer would land
faster as a picture. The trigger lives in `system/rules/work-preferences.md` §Terminal diagrams.

A diagram earns its place only when the reader can *find* things in it faster than in prose:
who talks to whom, which branch, what state comes next. If two or three sentences say it as
fast, write the sentences.

## The loop

```text nocheck
question ──► CHOOSE type ──► DRAW on a fixed grid ──► CHECK with check.py ──► caption + send
                                     ▲                       │ issues
                                     └───── fix (max 3) ◄────┘
```

1. **Choose** the type from the reader's question (table below), not from habit.
2. **Draw** with the safe glyph set, one claim per figure.
3. **Check** any diagram with boxes or junctions before sending, when Bash is available. Pipe
   it to the checker that ships next to this file; no scratch file needed:

   ```text nocheck
   D=$(ls -d ~/.claude/plugins/cache/brana/brana/*/skills/terminal-diagrams | tail -1)
   python3 "$D/check.py" - <<'EOF'
   ...diagram...
   EOF
   ```

   Inside the brana repo, use `system/skills/terminal-diagrams/check.py`. `check.py FILE.md`
   checks every fenced block of a document. Fix what it reports and re-run; after 3 failed
   rounds, simplify (fewer boxes, a list, or a table). Without Bash, walk **Before sending**
   by hand.
4. **Caption** with one line stating the claim the figure makes.

## Choose the diagram

| Reader's question | Draw | Notes |
|---|---|---|
| What happens, in what order, with which branches? | Flow / pipeline | Show every exit of a decision |
| In what order do the parties talk? | Sequence | One lane per actor; time runs down |
| What states can it be in, and what moves it? | State machine | Arrows labelled with the trigger |
| Where does data come from, change and get stored? | Data flow | Sources, processes, stores |
| Who owns each step, where are the handoffs? | Swimlane | One lane per team or system |
| Which outcome for which combination of inputs? | Decision table | Markdown table, not boxes |
| Why does it keep growing or settle down? | Causal loop | Signed links, R/B loop label |
| Which entities exist and how do they relate? | Entity-relationship | Cardinality on each end |
| What blocks what, what can run in parallel? | Dependency graph | Layer by depth, left to right |
| What are the parts and who uses them? | Architecture (context/container) | Two levels at most |
| How is it nested or grouped? | Tree / hierarchy | |
| Which option, or what changed? | Comparison table / 2×2 | Show the difference, not two lists |
| When does each thing happen? | Timeline | |

Too big for a terminal (more than ~12 nodes)? Split it first. See **Escalate** at the end.

## Principles

- **Draw the mechanism, not the names.** Boxes in a row with arrows say nothing; arrows
  labelled with *what moves* (`records`, `HTTP 201`, `nightly batch`) say how it works.
- **Label every edge** that the reader would otherwise have to guess. Prefer verbs or payloads.
- **One direction of travel.** Top to bottom for processes, left to right for pipelines.
  Back-edges (retries, loops) are the exception and should look like one.
- **Avoid crossings first, style later.** Edge crossings hurt comprehension more than anything
  else. Reorder nodes until lines don't cross; if they still must, split the figure.
- **Group by proximity.** Things that belong together sit together or inside one container.
- **Complete decisions.** Every decision shows all its exits (`yes`/`no`, each status code).
- **One claim per figure; overview then zoom.** Past ~12 nodes, draw the overview with
  collapsed groups and a second figure for the part that matters.
- **Same notation throughout.** If a symbol isn't obvious, add a one-line legend.

## Primitives and safe glyphs

```text nocheck
boxes      ┌─┐ │ └─┘   rounded ╭╮╰╯ (processes)   double ═ ║ (stores)
junctions  ├ ┤ ┬ ┴ ┼   tree connectors ├── └── │ (same as display-themes.md)
arrows     ─► ◄─ │▼ ▲│  direct / sync    ┄┄► indirect: async, reply or external message
inline     → ← ↓ ↑      markers ● start ◉ end      (+) (−) link signs   [R] [B] loop types
```

Use only single-width characters. The checker rejects the rest:

- **Never:** emoji, CJK text, tabs, `U+FE0F` variation selectors, zero-width joiners,
  diagonals `╱ ╲ ╳`, dashed `╌ ╍ ╎ ╏`, half-lines `╴╵╶╷…`, block art `▀ ▄ █ ░`.
  These render 1 or 2 cells depending on the terminal and font, so borders drift.
- **Aim for ≤ 80 columns** (the checker's hard limit is 100). Restructure before wrapping.
- **Labels go beside lines.** Short signs like `(+)` may sit inside a straight run; never put
  text on a corner or junction, where it breaks the connector.
- Pad every row of a box to the same width. Count cells, never eyeball.

## Cookbook

Every example below passes `check.py`. Copy the shape, not the content.

### Flow / pipeline

Linear:

```
┌───────┐ records ┌──────────┐  valid   ┌───────┐
│ INPUT ├────────►│ VALIDATE ├─────────►│ STORE │
└───────┘         └──────────┘          └───────┘
```

Branching (every exit shown, labels beside the lines):

```
     ┌───────────┐
     │ Request   │
     └─────┬─────┘
           ▼
   ┌───────────────┐
   │ Authorized?   │
   └───────┬───────┘
      ┌────┴────┐
   yes│         │no
      ▼         ▼
┌──────────┐ ┌────────────┐
│ Process  │ │ Reject 403 │
└──────────┘ └────────────┘
```

### Sequence

Lanes are columns; time runs down. Requests solid, replies `┄`.

```
     Client           Service           Provider
       │                │                  │
       │ POST /items    │                  │
       ├───────────────►│                  │
       │                │ lookup           │
       │                ├─────────────────►│
       │                │         result   │
       │                │◄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┤
       │    201 created │                  │
       │◄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┤                  │
       │                │                  │
```

Show error paths as a second, short sequence rather than squeezing `alt` blocks into one.

### State machine

Boxes are states, arrows carry the trigger. Mark the start with `●`.

```
 ●
 │
 ▼
┌───────┐ submit ┌─────────┐ approve ┌──────────┐ close ┌────────┐
│ Draft ├───────►│ Pending ├────────►│ Approved ├──────►│ Closed │
└───────┘        └────┬────┘         └──────────┘       └────────┘
                      │ reject
                      ▼
                ┌──────────┐
                │ Rejected │
                └──────────┘
```

More than ~6 states or many self-loops: add a transition table (`from | event | to | guard`)
under a smaller diagram instead of drawing every arrow.

### Data flow

Sources and sinks are boxes, processes are rounded, stores are double lines. Label each arrow
with the data, not the action.

```
┌────────┐ records ╭────────────╮ raw rows ═════════════════
│ Source ├────────►│ 1 Ingest   ├─────────► D1 Raw store
└────────┘         ╰────────────╯          ═════════════════
                                                  │ raw rows
                                                  ▼
                                           ╭────────────╮
                                           │ 2 Clean    │
                                           ╰─────┬──────╯
                                                 │ clean rows
                                                 ▼
┌────────┐ report  ╭────────────╮ tables   ═════════════════
│ Reader │◄────────┤ 3 Publish  │◄──────── D2 Clean store
└────────┘         ╰────────────╯          ═════════════════
```

Number processes so the text can refer to them (`step 2 drops duplicates`).

### Swimlane

One lane per owner. Steps sit in their owner's lane; a vertical arrow crossing a lane line is
a handoff, which is usually where things get lost.

```
Requester │ ┌───────────┐
          │ │ Submit    │
          │ └─────┬─────┘
──────────┼───────┼──────────────────────────────
Reviewer  │       ▼
          │ ┌───────────┐   ┌───────────┐
          │ │ Review    ├──►│ Approve   │
          │ └───────────┘   └─────┬─────┘
──────────┼───────────────────────┼──────────────
Operator  │                       ▼
          │                 ┌───────────┐
          │                 │ Fulfil    │
          │                 └───────────┘
```

Plain "who does what" lanes, not BPMN pools. Mark messages to outside parties `┄┄►` and say
so in the caption.

### Decision table

Many rules over the same inputs: use a markdown table (the terminal renders it), not boxes.
One row per rule, `–` for "doesn't matter", and say which rule wins when several match.

| Priority | Waiting | Size | → Action |
|---|---|---|---|
| high | – | – | escalate now |
| normal | ≤ 3 days | – | keep in queue |
| normal | > 3 days | small | auto-approve |
| normal | > 3 days | large | manual review |

Hit policy: **first match, top to bottom**. Check that the rules cover every combination.

### Causal loop

Why something spirals or stabilises. Each link is signed: `(+)` moves the same way, `(−)` the
opposite. Name the loop **[R]** reinforcing or **[B]** balancing. To decide, trace one
change all the way around rather than counting signs.

```
  Backlog ──────────(+)────► Wait time
     ▲                          │
    (+)          [R]           (+)
     │                          ▼
  Time on    ◄─────(+)───── Follow-up
  follow-ups                requests
```

A balancing loop (more capacity, a queue cap) usually belongs next to it. Draw it as a second
loop sharing a node.

### Entity-relationship

Boxes are entities, cardinality goes on each end (`1`, `0..1`, `*`, `1..*`). Add key fields
only when they matter to the question.

```
┌───────────┐ 1      * ┌──────────────┐ 1      * ┌───────────┐
│ Customer  ├──────────┤ Order        ├──────────┤ Line item │
├───────────┤          ├──────────────┤          ├───────────┤
│ id        │          │ id           │          │ id        │
│ email     │          │ customer_id  │          │ order_id  │
└───────────┘          │ placed_at    │          │ quantity  │
                       └──────────────┘          └───────────┘
```

### Dependency graph

What blocks what. Arrows point from prerequisite to dependant; lay out by depth, left to
right, so everything in one column can run in parallel.

```
spec ────────────┬───────► build API
                 │
                 └───────► build UI ──► release
                             ▲
design review ───────────────┘
```

The critical path is the longest chain. Name it in the caption (`spec → build UI → release`).

### Architecture (context / container)

Draw at most two levels: who uses the system and what it talks to (context), then the
deployable parts inside it (container). Annotate edges with protocol or mechanism.

```
           ┌──────┐
           │ User │
           └──┬───┘
              │ HTTPS
┌─────────────┼────────────────────────────┐
│ System      ▼                            │
│        ┌─────────┐  REST  ┌─────────┐    │
│        │ Web app ├───────►│   API   │    │
│        └─────────┘        └────┬────┘    │
└────────────────────────────────┼─────────┘
                                 │ SQL
                                 ▼
                           ┌──────────┐
                           │ Database │
                           └──────────┘
```

### Tree / hierarchy

Reuse `display-themes.md`'s connectors exactly; don't invent a parallel set.

```
release-2.0
├── feature-a
│   ├── task-1  schema
│   └── task-2  endpoint
└── feature-b
```

### Comparison table / 2×2

Show the *difference*: rows where the options are equal can usually go.

```
┌──────────────┬──────────────┬──────────────┐
│              │ Option A     │ Option B     │
├──────────────┼──────────────┼──────────────┤
│ Cost         │ Free         │ $10/mo       │
│ Setup        │ 5 min        │ 30 min       │
│ Vendor lock  │ None         │ High         │
└──────────────┴──────────────┴──────────────┘
```

Two-axis positioning (effort vs impact, urgency vs importance):

```
         low effort    high effort
       ┌─────────────┬─────────────┐
high   │ do now      │ plan        │
impact │ A, C        │ D           │
       ├─────────────┼─────────────┤
low    │ batch       │ drop        │
impact │ E           │ B           │
       └─────────────┴─────────────┘
```

### Timeline

```
 Week 1        Week 2        Week 3        Week 4
 ──┬─────────────┬─────────────┬─────────────┬──►
   │             │             │             │
 plan          build         test          release
```

### Other shapes

Everything is nodes, edges and labels; compose new shapes from the primitives above. When
nothing fits, a numbered list or a table is often better than a forced picture.

## Escalate when it doesn't fit

Stay in the terminal. Render a diagram (the platform's `artifact-diagramming` skill, SVG in an
artifact) only when the user asks for one. When a figure won't fit a terminal even after
splitting, or needs colour or interaction, offer the rendered version in one line instead of
making it. Never put confidential or client data on a hosted page without asking. For a
diagram that lives in a repo doc, propose a Mermaid block and ask first.

## Before sending

- [ ] The type matches the reader's question.
- [ ] Every edge that isn't obvious is labelled; every decision shows all exits.
- [ ] No crossings that reordering would remove.
- [ ] `check.py` passes (any diagram with boxes or junctions, when Bash is available).
- [ ] One-line caption states the claim.
- [ ] It's faster than the prose it replaces. If not, delete it.

## Credits

Originally authored for this repo, not an installed third-party skill (no `acquire-skills`
trust tier applies). Box-drawing and tree connectors extend
`system/skills/backlog/phases/display-themes.md`. Guidance draws on Larkin & Simon (1987) on why
diagrams help, Purchase et al. (1996+) on edge crossings, ISO 5807 flowchart conventions, the C4
model, DMN hit policies and system-dynamics loop notation. Early conventions took light
inspiration from `tjboudreaux/cc-visualization-skills` (MIT); no text or code was copied.
