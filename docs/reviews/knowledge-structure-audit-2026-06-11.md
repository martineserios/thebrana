# Knowledge Structure Audit — Ontology Analysis

---
date: 2026-06-11
scope: knowledge structure — docs/ taxonomy, memory stores, ontology alignment
related: t-156 (Knowledge Graphs), ADR-028 (ontology v2), ADR-038 (memory write gateway), docs/reviews/architecture-review-2026-06-10.md
---

**Verdict:** Not an ontology-absence problem — **two ontologies that don't know about each other, and an assimilation pipeline with an intake but no digestion**. The spec layer (`docs/`) is well-designed: `brana-ontology.yaml` v1.5 already defines types, typed relations, and axioms. The memory layer (280+ files across 4 stores) runs on a separate, disjoint taxonomy (ADR-038), enforces none of its own rules at write time, and has almost no relations between facts. Knowledge is captured prolifically and consolidated almost never. The 2026-06-10 architecture review named the symptom ("write-only memory"); this audit explains the structural cause.

## 1. The map — what exists

| Store | Size | Governing schema | Health |
|---|---|---|---|
| `docs/` (thebrana) | 276 files, ~15 types | brana-ontology.yaml + ADR frontmatter | Good design, partial deployment |
| `brana-knowledge/dimensions/` | 80 dimension docs | maintain/snapshot classes | Good |
| Project auto-memory (`~/.claude/projects/…/memory/`) | 206 files, 6 prefixes | ADR-038 taxonomy | Structurally degrading |
| Global memory (`~/.claude/memory/`) | 43 live files + 3 aggregates | ADR-038 (loosely) | Index covers 2 of 43 files |
| ruflo vector store | pattern/knowledge namespaces | quarantine→proven confidence | Doubly-indexes patterns |
| `spec-graph.json` | ~430 nodes, ~1,636 edges | ontology v1.5 | Covers specs only — memory invisible to it |

Note: an apparent 2,185-file global store is an artifact — 2,117 files are `pre-lint-heal-*` backup snapshots, not live content.

## 2. Core finding: two disjoint TBoxes

- **TBox 1** — `brana-ontology.yaml` (ADR-028): 5 active types (Dimension, Reflection, ADR, Pattern, Roadmap), 3 active relations (`depends_on`, `informs`, `supersedes`), 6 axioms (transitivity, supersession chains, single-source, staleness, orphan detection). Measurement-gated activation.
- **TBox 2** — ADR-038 memory taxonomy: 7 types (feedback, project, user, pattern, convention, field-note, adr) with routing rules and write semantics.

**No mapping between them.** `Pattern` appears in both with different definitions and homes. `FieldNote` is deferred in TBox 1 but active in TBox 2. `ADR` is a doc type in one, a memory-routing target in the other. Consequences: the spec-graph can never see memory; the axioms (orphan detection, staleness, single-source) never apply to the 280 files that need them most; "what do I know about X?" requires querying 4 stores with no federation.

## 3. ABox reality: instances violate the schema

The schema is not enforced where writes happen:

- **Type drift:** 6 `pattern_*` files carry `type: feedback`; all 6 `topic_*` files are typed `feedback`; 5 files have no frontmatter at all. Two competing frontmatter shapes coexist (top-level `type:` vs `metadata.type:`). Root cause already on record in memory `feedback_enum-validation-three-write-paths`: three write paths, only one validates.
- **Single-source axiom violated:** ~59 pattern slugs exist in *both* the project store and global `patterns.md`. Doc 14 and ARCHITECTURE.md coexist (ADR-021 split incomplete). No declared canonical copy.
- **Identity split:** type is encoded twice — filename prefix AND frontmatter — and they disagree.

## 4. Relations: the missing layer (blocks assimilation)

Specs have typed edges. Memory has almost none: 9.4% of project memory files contain `[[wiki-links]]`; ~25–30% of those are broken; all are untyped.

Assimilation IS relation-building. `feedback_` files are *episodic* memory (one incident); `pattern_` files are *semantic* memory (generalized). A healthy system consolidates episodic into semantic and lets episodes decay. This one structurally can't: no `generalizes`/`derived_from` relation to record consolidation, no lifecycle field to mark an episode absorbed. Result: **109 feedback files, 54% of the project store**, and MEMORY.md (the only context-loaded artifact) over its 200-line cap and truncating.

## 5. Lifecycle: facets exist everywhere except where needed

Status facets exist in three places — ADRs (`proposed→accepted→superseded`), ruflo (`quarantine→proven`), dimensions (`maintain`/`snapshot`) — and nowhere in file-based memory. No memory ever graduates, gets contradicted, or dies. Promotion machinery exists on paper but is stalled:

- `knowledge-staging.md` `Promote to:` field — sampled entries show `Promoted: —`, including one from 2026-04-20 (52 days against a declared 30-day stale threshold). That stale entry (`spec-graph-knowledge-graph-discipline-gap`) is itself a correct diagnosis of this problem.
- `patterns.md` at 99/100 cap; pruning rule stated, never run.
- `ideas/` holds 46 files against a declared cap of 10 active.
- Global MEMORY.md indexes 2 of 43 files.

Capture works. Digestion doesn't exist.

## 6. Nature of each type — verdicts

**Spec layer:** ADRs are the best-governed type (status, dates, typed edges — the template to copy). Dimensions' maintain/snapshot split is good faceting. Reflections' DAG is good but the doc-14 split is half-done. `reference/` as generated projections is the right pattern (one source, derived views). `ideas/` is capture-without-triage. `field-notes/` adopted by 1 of 15 doc types.

**Memory layer:** `feedback` is the overloaded dumping ground — the ADR-038 tie-breaker ("prefer feedback") guarantees it. `pattern` is sound but doubly-homed. `project` (upsert state facts) is well-designed. `topic_` files are the sleeper: only 6 exist, but they are an emergent SKOS-style concept-hub layer — exactly the clustering the flat index lacks. `field-note` vs `feedback` boundary doesn't hold in practice.

## 7. Recommendations, in order

1. **One TBox.** Extend `brana-ontology.yaml` to cover memory: ADR-038's 7 types as subclasses of a `Memory` class; define `Pattern` once with one canonical home; declare the authoritative store per type (single-source axiom, applied).
2. **Enforce at the gateway.** Finish deploying the ADR-038 write gateway as the *only* write path: closed type enum, one frontmatter shape, validate.sh check for memory files (mirror of Check 18 for specs). Stops drift at the source.
3. **Typed relations in memory frontmatter.** Minimum viable set: `generalizes` (pattern → the feedback incidents it consolidates), `supersedes`, `derived_from`. Converts the pile into a graph and makes consolidation recordable.
4. **Lifecycle facet on every memory** (`status: quarantine|proven|superseded|consolidated`) plus an actual digestion step — a periodic consolidation pass merging N similar feedbacks into a pattern or topic, marking episodes consolidated. Fixes the feedback pile and index overflow structurally, not by raising caps.
5. **Index as projection, not inventory.** Generate MEMORY.md clustered by `topic_` hubs — topics + proven + recent, not all files alphabetically. The index is the context-window interface; today it is a flat phone book that truncates.
6. **Mechanical cleanup** (one session): 5 frontmatter-less files, 6 misclassified patterns, broken wiki-links, rebuild global MEMORY.md, dedupe 59 cross-store slugs, wire staging stale-after and patterns.md pruning.

## 8. Existing assets

Dimension 47 (Ontology Engineering), dimension 48 (Knowledge Graphs), and pending task t-156 already point here. Doc 48 warns that graphs without ontology-constrained writes accumulate semantic duplicates — precisely what the memory layer is doing. Recommendations 1–3 are arguably the real scope of t-156.

## Appendix: instance-level violations (audit evidence)

- Missing frontmatter (5): `feedback_compound-bash-pretooluse-checkout-block_2026-06-09T14-27-19.md`, `feedback_challenger-skills-on-demand-not-preloaded_2026-06-09T12-33-44.md`, `feedback_tasks-json-mcp-stash-pop-after-branch_2026-06-09T14-27-24.md`, `feedback_memory-indexer-reinflates-removed-entries_2026-06-08T12-47-43.md`, `feedback_rust-skills-hook-granularity_2026-06-04T21-32-45.md`
- `pattern_` prefix with `type: feedback` (6): `pattern_project-manifests-over-sibling-tags-tech-detection.md`, `pattern_zsh-for-loop-no-word-split_2026-06-10.md`, `pattern_pretooluse-compound-command-intercept_2026-06-08.md`, `pattern_replicated-logic-tests-rot_2026-06-11.md`, `pattern_silent-loss-needs-lock-not-watchdog_2026-06-10.md`, `pattern_procedure-patches-need-sunset-comments.md`
- Broken wiki-links sampled: `[[memory-routing-taxonomy]]`, `[[parallel-bash]]`, `[[feedback_bash-unmatched-glob-set-e-trap]]`
- Dated-suffix adoption: 72/202 project files (35.6%) — mixed dated/undated within same prefix
- ADR-020 skipped in numbering with no explanation
