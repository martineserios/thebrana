---
title: Universal Doc Graph — structural substrate for traversable, reconcilable docs
status: idea
created: 2026-06-22
relates: t-2222
supersedes_framing_of: open-threads-lifecycle.md
---

# Universal Doc Graph

> Brainstormed 2026-06-22. Status: idea (big — epic-scale).
> The open-threads feature (open-threads-lifecycle.md / t-2222) is the **first
> application** that proves this substrate. This doc is the substrate itself.

## The thesis ("structural redesign, no patches")

Brana today has several **narrow, separate propagation mechanisms** — each a point
solution:

| Existing narrow mechanism | What it does |
|---|---|
| `spec-graph.json` (`brana graph build`) | spec/doc → `impl_files` (code) edges, brana-only |
| `/brana:reconcile --scope propagation` | cascades dimension → reflection → roadmap |
| errata cascade | propagates corrections across docs |
| memory files `[[ ]]` | soft links between memory entries |
| ruflo `recall` | semantic retrieval over the corpus |
| (proposed) questions/awaiting-info | tracks open questions → stale docs |

These are **the same problem wearing different coats**: *information changed at node
A; nodes B, C, D that depend on A are now stale; bring them into agreement.* Patching
each separately (a questions tracker here, a spec-graph there) is symptomatic. The
**structural fix** is one shared model: docs/code/decisions/questions are **nodes** in
a typed graph; relationships are **edges**; reconciliation is **graph traversal +
edit-on-approval**. Every current mechanism becomes a special case of "traverse edges
of type T from a changed node, reconcile downstream." This is why a structural redesign
*dissolves* the questions-staleness problem instead of patching it.

## The model

**Nodes** — any addressable artifact with a stable ID: doc, doc-section (anchor),
code file, ADR, question, decision, task. (spec-graph.json already keys nodes by file
path with a `type` and `ontology_version` — generalize this.)

**Edges — two tiers:**

- **Soft (Obsidian layer):** `[[wikilinks]]` authored inline in prose. Cheap,
  human-friendly, give backlinks + a graph view. Weakly typed. Already used by memory files.
- **Hard (machine layer):** typed, directional edges in the generated graph index —
  generalize `impl_files` into a family: `impl_of`, `informs`/`depends_on`,
  `blocks`/`answers` (questions), `supersedes`/`errata`, `links`. Carry reconcile semantics.

Soft links **promote** to hard edges; hard edges **render** as navigable links.

**Engine** — ONE traversal+reconcile operation, generalizing `--scope propagation`:
given a changed/answered node, walk outbound reconcile-relevant edges, collect affected
nodes, run the existing **edit-on-approval LLM loop** on each. The store/index does
bookkeeping; `/brana:reconcile` does the editing. No new reconciliation engine.

**Project-agnostic packaging** — the graph index lives at a conventional per-project
path; the scanner + engine ship as brana *system* skills; no project topology baked in.
Each project grows its own graph by writing `[[ ]]` links + frontmatter edges.

## What it subsumes

`spec-graph.json` → one edge-type (`impl_of`) in the universal graph. `--scope
propagation` → traverse `informs`. errata → traverse `supersedes`. memory `[[ ]]` →
soft edges, now backlinked. questions → nodes + `blocks`/`answers` edges. ruflo recall
→ complementary semantic layer over the same node corpus.

## Genuine structural forks (the real design decisions)

1. **Index: derived vs declared.** Generate the index by scanning docs (`[[ ]]` +
   frontmatter) so docs are source-of-truth and the index is disposable (like
   `MEMORY.md`)? Or maintain a declared artifact (like today's `spec-graph.json`, which
   drifts)? **Lean: derive where possible, declare only what can't live in prose** —
   this directly kills the staleness/dead-target risk the challenger flagged.
2. **Granularity: doc-level vs section-level nodes.** Reconciliation often needs
   section precision ("this paragraph is stale"), but block-level nodes are heavy.
   Obsidian supports heading/block refs (`#`, `#^`) — possible middle ground.
3. **In-repo vs out-of-band.** Obsidian reads the repo's `.md` + links, so the index +
   soft links basically MUST be in-repo (committed, versioned, navigable) — adds files
   to client repos, but that's the cost of Obsidian-compatibility.
4. **Adoption without boiling the ocean.** The graph is **additive**: a doc with no
   links is just an isolated node; it still works. Graph-ify incrementally; the
   questions app forces the first edges. No big-bang migration.

## Strategy: questions as the proving slice (decided 2026-06-22)

Make the substrate its own **epic**. The open-threads feature (t-2222) is **slice 1**:
it *defines and exercises* the graph format (`blocks`/`answers` edges, the
traversal-reconcile loop) on a small surface — ships real value, proves the substrate,
requires no full migration. Universal doc adoption + the other edge types = later phases.

## Risks

- **Boil-the-ocean.** Mitigated by additive adoption + questions-first proving slice.
- **Index staleness** (the spec-graph.json disease). Mitigated by derive-don't-declare (fork 1).
- **Obsidian coupling cost** — in-repo index/links in client repos (fork 3).
- _Pre-mortem + substrate challenger pending._

## Next steps

1. Challenger pass on THIS substrate design (big architectural bet — before commitment).
2. Resolve forks 1–3 (derived/declared, granularity, in-repo).
3. ADR for the universal graph ontology + edge taxonomy.
4. Re-scope t-2222 as slice 1; plan the epic.
