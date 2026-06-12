---
title: Knowledge Base Redesign — One Schema, Three Consumers
status: planned
created: 2026-06-12
planned: 2026-06-12 (phase t-2021)
---

# Knowledge Base Redesign — One Schema, Three Consumers

> Brainstormed 2026-06-12 (from t-156 Knowledge Graphs, now cancelled into the phase). Status: planned — challenger-reviewed twice (idea 2026-06-12, task tree 2026-06-12), backlog written as phase t-2021.

## Problem

The knowledge base grew as ~6 independent stores with no shared schema:

| Store | Convention |
|---|---|
| `brana-knowledge/dimensions/` | research docs, partial frontmatter |
| `docs/reflections/`, `docs/architecture/decisions/`, `docs/ideas/` | specs, partial typed-link discipline |
| `~/.claude/projects/*/memory/` | 170+ flat files, own frontmatter (name/description/type) |
| `~/.claude/memory/` | flat aggregates (patterns.md, knowledge-staging.md) |
| ruflo namespaces | vector index over some of the above |
| `tasks.json` context fields | tactical knowledge |

The 2026-06-11 audit symptoms — "disjoint TBoxes" (brana-ontology.yaml v1.5 vs ADR-038 memory taxonomy) and missing typed relations (9% of memory files have wiki-links, ~30% broken) — are both downstream of this fragmentation.

## Discussion findings (Phase 3)

1. **TBox conflict re-diagnosed:** not two competing schemas — a type-mapping gap. brana-ontology.yaml defines graph node types (T-Box); ADR-038 defines memory file routing types (A-Box classification). The "Pattern" overlap is a level confusion, closable with a mapping paragraph.
2. **Mapping criteria** (which memory types deserve graph nodes): *structural* (knowledge, not behavior) + *has edges* + *traversal value*. Verdict: `pattern`, `field-note` → graph; `convention`/`adr` → phase 2 if distinct; `feedback`, `project`, `user` → ruflo-only.
3. **Ruflo does no graph traversal itself.** Traversal = `/brana:build` LOAD 2b reading `docs/spec-graph.json` (1-hop, depends_on/informs). `brana graph build` (Rust CLI) already reads BOTH frontmatter relations and body typed links. Memory files are simply not scanned.
4. **Graph vs better-ruflo:** vectors cover discovery; graph is irreplaceable for impact analysis (transitive depends_on), orphan detection, and deterministic structural loading.
5. **Reframe (user):** redesign the knowledge base from scratch — one frontmatter spec where the ontology IS the schema. Every file declares `type:` (ontology type) + `relations:` (typed edges). Wiki-links serve Obsidian, frontmatter serves the graph, text serves ruflo. One file, three consumers, zero translation layers.
6. **Hard constraint:** `~/.claude/projects/*/memory/` is harness-fixed (CC auto-loads MEMORY.md from that path). Can't relocate; can conform its files to the unified spec as a satellite shelf.
7. **Ratio assessment:** graph bolted onto current corpus = medium effort, low-medium power (sparse edges, patched schemas). Graph after redesign = nearly free (CLI already reads frontmatter), full power. The redesign is the investment; the graph is one of three dividends (ruflo precision, Obsidian navigability are the others).

## Research findings (Phase 2/3 — 2026-06-12)

### Internal (codebase scout)

1. **Ruflo doesn't care about folders.** Namespace is assigned per `memory_store()` call, not derived from location. Keys are content-based. A folder redesign neither helps nor breaks ruflo retrieval — only the bulk indexer scripts (`feed-ruflo-index.sh`, `index-knowledge.sh`) hardcode paths and would need updating.
2. **Ruflo has no metadata filtering.** "Find all `status: draft`" is impossible in ruflo — it's namespace + semantic + keyword only. Structured queries are the graph's job, full stop.
3. **ADR-021 already mandates the 3-layer architecture** (ontology → frontmatter → graph) and per-doc temporal metadata (valid_from, confidence_tier, maturity_stage) — largely unimplemented in practice. The redesign is partially *already decided*, just not executed.
4. **ADR-028 constraints:** frontmatter relations must use ontology relationship types (no ad-hoc fields); deferred types auto-promote on first frontmatter use; measurement-gated.
5. **7 prior idea docs overlap** (kairos, autodream, dated-memory-files, pattern-learning-redesign, inbox-pipeline, pipeline-glue, resilient-pattern-store). Conflicts: staging dir ownership, draft schema, memory write routing. Any redesign must absorb or supersede these, not add an 8th parallel proposal.

### External (web scout)

1. **Atomic notes beat long docs by 30–50% in retrieval precision** — multi-theme documents dilute embeddings. Dimension docs (long, multi-topic) are structurally bad RAG inputs.
2. **GraphRAG hits 90%+ on schema-bound queries where vector-only RAG scores ~0%** (FalkorDB 2025 benchmark) — confirms graph is irreplaceable for structural queries, vectors for fuzzy discovery.
3. **Folders are decorative.** Industry converged: flat-ish vault (5–10 top dirs), types in frontmatter, links for navigation. Graph and vector consumers ignore folders entirely.
4. **"One schema serves all three consumers" is partly overstated:** frontmatter is the single source of *metadata* truth, but each consumer (RAG, graph, human) runs its own extraction pass. Brana already has exactly this shape (ruflo indexers / graph CLI / MEMORY.md) — the architecture is right; the content units are wrong.

## Type system (Phase 4 — converged 2026-06-12)

Three candidates were weighed: A (pure epistemic types), B (Zettelkasten roles), C (hybrid). **C-minimal chosen**: A's typed atoms give machine leverage (graph + validation); B's hubs give long-form synthesis a home; ADR-028 measurement gating prevents overengineering.

```
ATOMS (typed, atomic, machine-validated)
  claim    — falsifiable statement; has confidence, review_due
  pattern  — problem → solution; quarantine → proven lifecycle
  event    — immutable, timestamped; never stale; causal anchor
  source   — external reference; has tier

SYNTHESIS (curated, can be long)
  hub      — map-of-content; Dimensions/Reflections/project-context become hubs
  decision — ADR, unchanged

DEFERRED (ADR-028 measurement-gated, auto-promote on first use)
  constraint, question
```

### Temporality — two layers

1. **Knowledge ages:** every note carries `created`, `valid_from`, `review_due`, status transitions — this finally executes ADR-021's accepted-but-unimplemented temporal metadata mandate.
2. **Things happen:** `event` is a first-class atom type — immutable, append-only, never stale. Events are the causal backbone: "2026-03-31 ruflo DB wipe" → informs → ADR-026. Project context = event sourcing: a hub curating recent events + active claims, not a mutable blob that rots. Capture mechanism already exists (`/brana:log` append-only log); missing piece is promotion of significant events into typed event notes with relations.

### Old → new mapping

| Current | Becomes |
|---|---|
| Dimension | hub + extracted claim/source atoms |
| Reflection | hub that curates other hubs; novel conclusions extracted as claim atoms (scope, not kind, distinguishes it from a dimension-hub — the link structure expresses this, no separate type needed) |
| Idea doc | question/claim atoms + optional hub |
| ADR | decision (unchanged) |
| feedback memory | pattern or claim atom (or stays ruflo-only if behavioral) |
| field-note memory | claim atom |
| `/brana:log` entries | event atoms (promoted selectively) |
| project context | hub derived from events |

## Challenger review (2026-06-12, 3-lens: convergent/systems/critical)

**Verdict: proceed with amendments.**

### Blockers (HIGH confidence — ≥2 lenses)

1. **The ADR-021 ghost is real and unanswered.** Temporal fields were mandated 90 days ago and never implemented; this redesign *adds* maintenance burden without adding a new enforcement mechanism. → **Amendment:** Phase 1 must make schema compliance *blocking*, not advisory — `/brana:close`/memory-write gated on valid frontmatter (hook or CLI gateway), validate.sh checks shipped before any authoring convention is announced.
2. **Corpus root is undecided.** Without it, the scope of every pipeline change is unknowable and convention-forward migration has no completion gate. → **Amendment:** corpus root becomes an explicit decision in the Phase 0 ADR, with a defined migration completion gate.

### Majors (amendments)

- **ADR-042 conflict** (knowledge-pipeline-glue is an *accepted ADR*, not an absorbable idea doc) → Phase 0 includes an ADR-042 amendment.
- **Path-based classification everywhere:** `index-knowledge.sh` and `brana graph build` (`classify_node()`, `is_structural_orphan()`) classify by path, contradicting "folders are decorative" → explicit Phase 1 tasks: classify by frontmatter `type:`.
- **`/brana:close` Step 6 routing table** is the primary write path with no heuristic for new atom types → explicit Phase 2 task.
- **Atomization explosion:** splitting 30 dimensions → 450–750 orphan-at-birth files, drowning orphan detection → Phase 3 rescoped: top-5 dimensions only, hub-linking required at creation, orphan detection must understand hub-linked atoms first.
- **Type-assignment quality untested** → add measurement: sample audit of Claude's type assignments after first ~50 notes.

### Minor

- 170+ memory files need frontmatter reconciliation — scope explicitly in Phase 3.

## Open questions

- Migration scope: big-bang vs convention-forward (new files conform; old migrate opportunistically)?
- Folder structure: optimize for ruflo namespaces? for Obsidian vault? for ontology types?
- Where does the unified corpus root live — brana-knowledge/ as the vault?

## Phased rollout (shaped + amended)

- **Phase 0 — Unit-of-Knowledge ADR:** note types, lifecycle, frontmatter schema, old→new mapping, **corpus root decision** (challenger blocker), migration completion gate, ADR-042 amendment, absorption of the 7 overlapping idea docs. Blocks everything.
- **Phase 1 — Enforcement before convention:** validate.sh lifecycle checks; `brana graph build` + `index-knowledge.sh` classify by frontmatter `type:` (not path); memory-write gated on schema compliance (blocking, not advisory — the answer to the ADR-021 ghost).
- **Phase 2 — Convention-forward authoring:** `/brana:close` Step 6 routing table updated for atom types; `/brana:research` + inbox pipeline emit atomic notes; type-assignment sample audit after first ~50 notes.
- **Phase 3 — Heal the stock:** lifecycle sweep of docs/ideas/; top-5 dimensions atomized (hub-linking required at creation; orphan detection must understand hub-linked atoms first); memory-file frontmatter reconciliation; merge 24-roadmap-corrections into 18-lean-roadmap.
- **Phase 4 — Dividends:** LOAD traverses memory/atom nodes; `brana graph impact <doc>` staleness analysis.

**Governance (confirmed, M+ mandatory):** DDD — the Phase 0 ADR blocks all impl. TDD — graph-build/indexer/validate tests before each impl task. SDD — knowledge-system-extending.md, ARCHITECTURE.md, brana-ontology.yaml updates blocked_by impl. Docs — tech doc + guide via /brana:docs.

**Related task:** t-2039 — promote `/brana:log` events into typed event notes (Phase 2; heuristic defined in the Phase 0 ADR). *Correction 2026-06-12: this doc originally cited t-2006, which is an unrelated completed feed-index test task — stale reference, fixed at planning time.*

## Backlog (planned 2026-06-12)

Phase **t-2021** "Knowledge Base Redesign — One Schema, Three Consumers" (epic: knowledge-pipeline, tag: `kb-redesign`). A second challenger pass on the task tree (verdict: proceed with amendments) added per-phase test gates, the hard-block mechanism spec for the memory-write gate, and moved the ontology update into Phase 0.

| Milestone | Tasks |
|---|---|
| t-2022 Phase 0 — Unit-of-Knowledge ADR | t-2027 ADR (corpus root first) · t-2028 ADR-042 amendment · t-2029 absorb 6 idea docs · t-2030 ontology.yaml |
| t-2023 Phase 1 — Enforcement before convention | t-2031 [test] · t-2032 validate.sh · t-2033 graph.rs classify-by-type · t-2034 index-knowledge.sh · t-2035 memory-write hard gate |
| t-2024 Phase 2 — Convention-forward authoring | t-2036 [test] · t-2037 close routing · t-2038 research/inbox atoms · t-2039 event promotion · t-2040 type audit @50 |
| t-2025 Phase 3 — Heal the stock | t-2041 ideas sweep · t-2042 top-5 dimensions · t-2043 memory reconciliation · t-2044 roadmap merge |
| t-2026 Phase 4 — Dividends | t-2045 [test] · t-2046 LOAD traversal · t-2047 graph impact |
| Cross-phase | t-2048 spec sync · t-2049 tech doc + guide |

Superseded: t-156, t-1253, t-1259, t-1262 (cancelled with pointer notes).
