# t-3186 — Entity Topology for the Brana Knowledge Base: Research Findings

**Date:** 2026-08-24 · **Task:** t-3186 (research) · **Author:** research agent (read-only pass)

Scope: people, companies, and software/tools as first-class linked entities across ingested
content (LinkedIn posts, YouTube transcripts, articles). Five questions: extraction approach,
storage model, linking/dedup, retrieval integration, pipeline hook point.

---

## 1. What the project docs already decided

| Decision | Where | Relevance to entity topology |
|---|---|---|
| Document-type ontology: claim/pattern/event/source/hub/decision. Frontmatter `relations:` is the **single authoritative edge source** for the graph; body wiki-links are decoration. | `docs/architecture/decisions/ADR-057-unit-of-knowledge.md` §3 | ADR-057 types say what a document **is**; entities say what a document is **about**. Complementary axes — an entity layer adds nodes referenced *by* documents, it does not compete with document types. |
| Graph-node eligibility test: *structural* (knowledge, not behavior) + *has edges* + *traversal value*. | ADR-057 §4 | Person/Company/Tool entities pass all three — this answers "should entities be graph nodes" affirmatively from an existing doc, not from new doctrine. |
| Non-action: "No new ruflo namespaces; **no ruflo metadata-filtering workarounds (structured queries are the graph's job)**." | ADR-057 §Non-Actions | Directly constrains the storage question: ruflo tags may *decorate* entries for recall filtering, but the entity registry's authority must live in a graph/JSON structure, not in ruflo tag conventions. |
| Measurement-gated type activation: deferred ontology types **auto-promote on first frontmatter use**; zero-usage types demote after 30 days. 15 types exist today — all document/work types; **no Person, Organization, or Tool type exists**. | `docs/architecture/decisions/ADR-028-ontology-v2.md`; `docs/brana-ontology.yaml` (v1.6) | The sanctioned, low-ceremony path to add entity types: add them as `deferred` in the YAML, let first use promote them. No big ontology rewrite needed. |
| Relationship vocabulary is closed (active: depends_on/informs/supersedes; deferred: contradicts, implements, applies_to, produced_by, decided_by, blocked_by, tested_by, triggered_by). No "mentions"/"authored_by" relationship exists. | `docs/brana-ontology.yaml` §relationships | Entity edges need 1-2 new relationship types (e.g. `mentions`, `authored_by`) — an ontology change an ADR must own. |
| PlatformAdapter (enum dispatch): shared pipeline skeleton queue→Tier1→Tier2→Tier3; `ShortSignalAdapter` (linkedin/github/substack/arxiv, metadata-only) vs `LongFormAdapter` (youtube/articles, Tier3 grounded in `fetched_content`). `ingest` is the sole `PipelineState` writer; `canonicalize_url()` is the shared URL identity across `PipelineState` and ruflo. | `ADR-087-knowledge-pipeline-platform-adapters.md` + feature spec, on branch `knowledge-pipeline/feat/t-3151-youtube-pipeline-enrichment` (not yet on dev) | The "shared pipeline step both adapters call" slot the task asks about exists by design. Canonical-URL identity is the precedent for canonical *entity* identity. |
| Ingest is canonical URL entry; Gemini (agy) routes Tier1/2 atomic classification; Claude for Tier3 prose. | `docs/architecture/decisions/ADR-042-...md`, `docs/architecture/features/knowledge-pipeline-compute.md` | Entity extraction is exactly the "atomic, system-isolated classification" shape ADR-040/042 route to agy — or it can ride existing calls (see §2). |
| `extract_insight()` already makes **one agy JSON call per stored URL** (`{"summary","topic"}`, claude fallback, truncation fallback) at `process-url` time. | `system/cli/rust/crates/brana-core/src/knowledge_pipeline.rs:2481` | The cheapest extraction hook in the whole system: extending this JSON schema costs zero additional LLM calls. |
| Ruflo storage tags are flat strings: `[platform, topic]`, youtube `[platform, "transcript", caption_source]`; key = `knowledge:url:{slug}` of canonical URL. | `system/cli/rust/crates/brana-cli/src/commands/knowledge.rs:94-125` | Adding `entity:{slug}` tags is mechanically trivial and backward-compatible. |
| `UrlEntry.author` (person slug from LinkedIn URL path) is **already captured on every pipeline entry** but links to nothing. | `knowledge_pipeline.rs:60-101`; inbox-to-dimensions spec §Content sourcing | The system already extracts one entity class (post authors) — it just has no registry to resolve into. |
| SearchProvider trait + HybridProvider (FTS5 + ruflo, RRF merge) is the pluggable recall seam. | `docs/architecture/decisions/ADR-058-search-provider-hybrid-recall.md` | Entity-aware recall composes here without touching callers. |
| Retrieval routing: structural/impact queries → graph CLI; open-ended → Explore; decisions → recall. | `ADR-064-retrieval-routing-graphify.md` | "What content mentions X" is a structural query → belongs on the graph/registry side, consistent with ADR-057's non-action. |
| Generated-graph JSON precedents: `docs/spec-graph.json` (`{generated, generator, ontology_version, nodes{path→{title,type}}, edges[], stats}`, 605 nodes) and `graphify-out/graph.json` (node-link, 14MB, gitignored artifacts dir). | repo files | A small hand-plus-machine-maintained `entities.json` follows the spec-graph precedent (checked in, versioned, regenerable views), not the graphify precedent (bulk derived artifact). |
| A hand-maintained proto-entity-page already exists: the KG-creators reference memory (6 people, each with platform URLs, focus, signal, plus a tools table). | `~/.claude/projects/.../memory/reference_ontology-kg-creators.md` | This is exactly the artifact entity topology should *generate* — seed data for a backfill, and evidence of the user's actual need shape (person → platforms → tools → content). |

**Cross-reference verdicts:**
- **Extends ADR-057** (no conflict): entity layer = new node kind + `mentions`-style edges; document schema untouched. Entity *pages* need no new document type — ADR-057 already says "scope, not kind, distinguishes" hubs, so a per-entity hub (`type: hub` about Matt Pocock) is schema-legal today.
- **Answers an ADR-057 open edge** via its own eligibility test (§4): entities qualify as graph nodes.
- **Conflicts avoided**: primary entity store must NOT be a ruflo-tag convention (ADR-057 non-action); ruflo tags are decoration only.
- **Extends ADR-087**: entity extraction slots in as the shared-step pattern ADR-087 establishes; LongForm's grounded `fetched_content` is what makes rich extraction possible for YouTube.
- **Answers ADR-021's ghost lesson** (schema without enforcement doesn't get adopted, restated in ADR-057 §Context): any entity convention needs a mechanical writer (the pipeline) rather than an authoring convention humans must remember.

---

## 2. Findings per scope item

### 2.1 Extraction approach — LLM-in-existing-calls, not a dedicated NER stack

- **Encoder NER (GLiNER/spaCy) vs LLM**: 2026 guidance is that compact encoders (GLiNER ~300M params, CPU-deployable, open-vocabulary) are the cheap/fast choice for high-volume span extraction, and out-benchmark zero-shot LLMs on classic NER; LLMs win on context, relations, and role understanding ("built by", "works at") and are 100–1000x costlier per span at production scale ([NER Guide 2026](https://slavadubrov.github.io/blog/2026/04/02/ner-guide/), [GLiNER-Relex](https://arxiv.org/html/2605.10108v1), [Tilores on LLM ER](https://tilores.io/content/can-llms-be-used-for-entity-resolution/)).
- **But brana's volume is ~12–15 items/day** (inbox-to-dimensions spec) under a Claude subscription plus agy's free Gemini quota — the per-token economics that motivate GLiNER don't apply. A local NER dependency (Python/ONNX) would add operational surface for no cost savings.
- **Zero-marginal-cost option exists**: `extract_insight()` already sends every stored URL's content through one agy JSON call. Extending its schema to `{"summary","topic","entities":[{"name","type","role"}]}` adds ~50–150 output tokens per item and **zero new calls**. Same trick applies to Tier3 draft synthesis (already Claude prose) — ask for a trailing entity JSON block. This mirrors the hybrid consensus (NER for bulk, LLM for context — [Neo4j agent-memory extraction](https://neo4j.com/labs/agent-memory/explanation/extraction-pipeline/), [GraphRAG SDK](https://falkordb.github.io/GraphRAG-SDK/extraction/)) collapsed to its LLM half because bulk is small.
- **ShortSignal has no content to extract from** (metadata-only until t-1144): its entity yield is the `author` slug (already parsed), platform, and whatever names appear in `title_signal`/tags. That's a regex/slug operation plus at most a piggyback on the existing Tier2 LLM call — not a new extraction pass.
- **Hybrid tiering recommendation**: (a) deterministic extraction at ingest (author, platform, domain → org) — free; (b) LLM extraction piggybacked on `extract_insight` for fetched content (youtube transcripts, articles, public pages) — free-riding existing calls; (c) richer relation extraction only at Tier3 draft time where Claude is already reading the whole cluster. No every-ingest dedicated extraction pass.

### 2.2 Storage model — small registry file + entity hubs + tag decoration

Three candidate models weighed against repo precedent:

| Option | Verdict |
|---|---|
| **ruflo tags as primary store** (`entity:matt-pocock` tags) | Rejected as *authority* — ADR-057 non-action explicitly bans ruflo metadata-filtering workarounds; tags carry no aliases, no canonical identity, no edges. Keep as **decoration** for recall filtering only. |
| **`entities.json` registry** (spec-graph.json precedent: checked-in, versioned, small) | **Recommended authority.** ~hundreds of entities at this scale; JSON with `{id, type, canonical_name, aliases[], platforms{linkedin,github,...}, first_seen, mention_count}` is greppable, mergeable, CLI-manageable, and feeds graph builds. SQLite is overkill below ~10⁴ entities and loses git history/reviewability. |
| **Dedicated store (SQLite)** | Deferred until scale demands it; the registry is regenerable/exportable so migration stays cheap. |

Layered on top:
- **Entity hub pages** (`brana-knowledge/hubs/` or `entities/`, `type: hub` frontmatter) for entities that cross a mention threshold — human-readable rollup, Obsidian-visible, schema-legal under ADR-057 today. The PKM literature converges on exactly this "person page / MOC" shape ([MOC practice](https://www.dsebastien.net/2022-05-15-maps-of-content/), [entity notes pattern](https://ericmjl.github.io/blog/2026/3/6/mastering-personal-knowledge-management-with-obsidian-and-ai/)).
- **Ontology change** (one ADR): add `Person`, `Organization`, `Tool` as **deferred** types + a `mentions` (and optionally `authored_by`) relationship — ADR-028's auto-promotion activates them on first frontmatter use, matching the repo's own measurement-gating doctrine.
- **Mention edges** live where ADR-057 says edges live: frontmatter `relations:` on atoms/hubs/drafts for corpus files; for pipeline-only items (ruflo `knowledge:url:*` entries that never become corpus files) the registry itself carries a lightweight `mentions` list (url-key → entity id) so the graph can be built without inventing a second edge authority for non-corpus content.

### 2.3 Linking/dedup — cascade, proportionate to single-user scale

Industry pattern is a cascade: exact/alias lookup → fuzzy string match → embedding similarity → LLM adjudication, with humans on low-confidence cases ([Elasticsearch Labs ER](https://www.elastic.co/search-labs/blog/entity-resolution-llm-elasticsearch), [LLM entity-matching study](https://arxiv.org/pdf/2405.16884), [Tilores](https://tilores.io/content/can-llms-be-used-for-entity-resolution/)). LightRAG's minimal answer — dedupe by `(normalized_name, type)`, longest description wins ([Neo4j LightRAG teardown](https://neo4j.com/blog/developer/under-the-covers-with-lightrag-extraction/)) — shows how little you can get away with.

Proportionate for brana (single user, hundreds of entities):
1. **Slug-normalize** (`Matt Pocock` → `matt-pocock`; domains unwrap to orgs: `anthropic.com` → `anthropic`) and look up canonical id + aliases in the registry. LinkedIn author slugs are near-canonical already.
2. **Fuzzy tier**: case/punctuation/diacritic-insensitive compare + containment (`pocock` ⊂ `matt-pocock`) — plain Rust, no deps.
3. **LLM adjudication only for unresolved near-misses**, batched into an existing nightly call, and — mirroring ADR-057's event-promotion doctrine — **suggest-then-confirm for merges**: Claude proposes "`claude-code` == `claude code (tool)`?", the user confirms; never auto-merge, because a wrong merge silently corrupts every rollup (same blast-radius logic as ADR-087's key-migration finding).
4. **Skip embedding similarity entirely at this scale** — it's the tier that pays off at 10⁴⁺ entities; the alias table does its job below that.

Identity rule: canonical id is a slug, immutable once minted (repo pattern `pattern_no-mutable-state-in-immutable-id`); renames are alias additions.

### 2.4 Retrieval integration — filter, hub, rollup

- **Entity-filtered recall**: `entity:{slug}` tags on ruflo entries let `brana recall --entity matt-pocock` (or a SearchProvider wrapper per ADR-058) constrain hybrid recall without new index infrastructure. This is LightRAG's "local/entity-level query" mode in miniature ([LightRAG](https://arxiv.org/html/2410.05779v1)); graph-augmented retrieval measurably beats vector-only on relationship-shaped questions ([structural analysis](https://arxiv.org/pdf/2606.06003)).
- **Entity hub pages as LOAD entry points**: "everything about Pocock" becomes one hub read instead of N searches — replacing today's hand-maintained KG-creators memory file with generated, current pages.
- **Cross-content rollups**: the registry's mention list makes "3 videos + 2 posts + 1 tool all trace to Pocock" a deterministic query; Tier3-style synthesis over an entity's mention set produces the cross-content learnings the task names as locked-up today.
- **Dimension synthesis**: Tier2 clustering currently sees only title/tags; entity co-occurrence (same tool mentioned across a cluster) is an additional, free clustering signal once tags exist — and ADR-087 already moves LongForm Tier2 to similarity-based grouping, which entity overlap complements.
- **Routing stays ADR-064-consistent**: "who/what mentions X" → registry/graph; "what did X say about Y" → entity-filtered recall.

### 2.5 Pipeline hook point — one shared step, called from three places

Given ADR-087's shape (shared skeleton, adapters override steps):

- **`extract_entities(content_or_metadata, platform) -> Vec<EntityMention>`** as a shared `brana-core` function, exactly like `check_semantic_dedup` is a shared pre-filter today.
- **Call site A — `process-url` / `extract_insight`** (the earliest point where full content exists): extend the existing agy JSON schema; store `entity:{slug}` tags on the ruflo entry; upsert registry mentions. This covers YouTube/articles *now*, before t-3151 even merges.
- **Call site B — pipeline Tier2/Tier3 via the adapters**: ShortSignal contributes deterministic entities (author, platform; title-signal names via the existing Tier2 LLM call at most); LongForm contributes content-grounded entities — but if ingest came via `--from-ruflo <key>` (ADR-087's wiring), extraction already happened at call site A and the step is a lookup, not a re-extraction. Idempotency by (canonical-url-key, entity-id) pair.
- **Call site C — Tier3 draft synthesis**: drafts get `relations: [{type: mentions, to: <entity>}]` frontmatter, so promoted dimension content enters the ADR-057 graph correctly from birth.
- **Ordering**: build the registry + call site A independently of t-3151; add the adapter-step wiring after t-3151 merges (it lands `--from-ruflo` and the adapter seam this depends on).

---

## 3. Recommended architecture

Add an **entity layer beside — not inside — the document ontology**: a small checked-in `entities.json` registry (canonical id, type, aliases, platform links, mention index) as the identity authority; ontology gains deferred `Person`/`Organization`/`Tool` types and a `mentions` relationship (ADR-028 auto-promotion); extraction piggybacks on LLM calls the pipeline already makes (`extract_insight` at process-url time, Tier3 drafting), plus deterministic capture of author/platform/domain at ingest; ruflo entries get `entity:{slug}` decoration tags for filtered recall; entities crossing a mention threshold get generated hub pages in the vault (schema-legal `type: hub` files, Obsidian-visible); dedup is a slug→alias→fuzzy cascade with LLM adjudication only for near-misses and suggest-then-confirm merges. Cost: zero new LLM calls in steady state; one new small JSON file; one ADR.

```
            ingest (sole writer, ADR-042/087)
                 │
   ┌─────────────┴──────────────┐
   │ ShortSignalAdapter          │ LongFormAdapter
   │ (author/platform/domain —   │ (fetched_content)
   │  deterministic entities)    │      │
   └─────────────┬───────────────┘      │
                 │      process-url ────┤
                 ▼           │          ▼
        ┌─────────────────────────────────────┐
        │ extract_entities (shared step)      │
        │  piggybacks extract_insight / Tier3 │
        └──────┬───────────────┬──────────────┘
               │ resolve       │ decorate
               ▼               ▼
        entities.json     ruflo tags            Tier3 drafts
        (identity +       entity:{slug}         relations: mentions
         aliases +             │                     │
         mention index)        ▼                     ▼
               │          entity-filtered      spec-graph /
               ├────────► recall (ADR-058)     brana graph build
               ▼
        entity hub pages (brana-knowledge/hubs/, type: hub)
        "everything about matt-pocock" rollups
```

---

## 4. Proposed follow-up tasks (candidates — NOT written to any backlog)

- **ADR: entity topology — registry, ontology types, mentions relationship** — kind: design, effort: M. Lock the decisions this research surfaces: entities.json as identity authority, deferred Person/Organization/Tool types + `mentions` in brana-ontology.yaml, ruflo-tags-as-decoration rule, suggest-then-confirm merge doctrine. Blocks all implementation below (M+ discipline).
- **entities.json registry + `brana knowledge entities` CLI** — kind: feature, effort: M. Registry schema, load/save with the pipeline's lock discipline, subcommands list/show/add-alias/merge (merge = confirm-gated), seed import from `reference_ontology-kg-creators.md` + distinct `UrlEntry.author` values already in pipeline state.
- **Entity extraction piggyback in `extract_insight` + ruflo tag decoration** — kind: feature, effort: M. Extend the agy/claude JSON contract with an `entities` array (schema-tolerant parsing: absent field ≠ failure), slug-resolve against the registry, append `entity:{slug}` tags at store time. Test-first on `resolve_extraction`-style pure functions.
- **Resolution cascade (slug → alias → fuzzy → batched LLM adjudication)** — kind: feature, effort: M. Pure-Rust tiers 1-2; unresolved near-misses queue into a review list surfaced by `/brana:review` weekly (matching the drafts-review integration precedent), never auto-merged.
- **Entity hub page generation** — kind: feature, effort: S. `brana knowledge entity-page <slug>` renders a `type: hub` markdown page (mentions rollup, platform links, recent content) into `brana-knowledge/hubs/`; threshold-triggered suggestion, user-invoked generation.
- **Backfill spike + quality audit** — kind: research, effort: S. One-shot sweep of existing `knowledge:url:*` ruflo entries and event-log URLs to seed mentions; audit ~50 extracted entities for type/identity quality — the go/no-go gate before wiring extraction into the adapters (mirrors ADR-057's t-2040 audit-gate pattern).

Suggested sequencing: ADR → registry → (piggyback extraction ∥ backfill spike) → cascade → hub pages. Adapter wiring waits for t-3151 to merge.

---

## 5. Assumptions needing user confirmation

- **Entity type set**: chose `person | organization | tool` only, because those are the classes named in the task and Tier2's `cluster_topic` already covers concepts/topics — needs confirmation (notably whether *content works* — a specific video/post — should be entities too; recommended no: the URL key already identifies them).
- **Registry location**: chose `brana-knowledge/entities.json` (vault-adjacent, git-tracked like drafts) because entities are knowledge, not spec, and the vault is the Obsidian root — needs confirmation (alternative: `docs/` beside spec-graph.json, or `~/.swarm/` unversioned like pipeline state; unversioned is NOT recommended — identity data wants git history).
- **Ontology mechanism**: chose adding deferred types + `mentions` relationship via ADR-028 auto-promotion because it's the repo's own sanctioned expansion path — needs confirmation (alternative: keep entities entirely outside the ontology/graph as a private pipeline index; loses graph traversal and contradicts ADR-057's eligibility test).
- **Extraction cadence**: chose piggyback-on-existing-LLM-calls (process-url + Tier3) with deterministic-only extraction at ingest, because it is zero-marginal-cost and ShortSignal has no content anyway — needs confirmation (alternative: a dedicated nightly extraction pass over new items; more thorough for title-signal names, one extra scheduled agy batch).
- **Merge policy**: chose suggest-then-confirm for all entity merges (never auto-merge) because a wrong merge silently corrupts rollups — needs confirmation that the review friction is acceptable (expected volume: a few candidates/week at current ingest rates).

## Sources (external)

- https://slavadubrov.github.io/blog/2026/04/02/ner-guide/ — NER model landscape 2026 (GLiNER vs spaCy vs LLM, cost guidance)
- https://arxiv.org/html/2605.10108v1 — GLiNER-Relex: encoder-based joint NER+relation extraction, cost framing vs autoregressive LLMs
- https://neo4j.com/labs/agent-memory/explanation/extraction-pipeline/ — hybrid NER+LLM extraction pipeline pattern
- https://falkordb.github.io/GraphRAG-SDK/extraction/ — two-step local-NER-then-LLM-verify extraction
- https://arxiv.org/html/2410.05779v1 — LightRAG: entity/relation extraction, incremental KG, dual-level (entity/global) retrieval
- https://neo4j.com/blog/developer/under-the-covers-with-lightrag-extraction/ — LightRAG dedup internals: (normalized_name, type) key, longest-description-wins
- https://www.elastic.co/search-labs/blog/entity-resolution-llm-elasticsearch — hybrid retrieval-then-LLM-judgment entity resolution
- https://arxiv.org/pdf/2405.16884 — LLM entity-matching strategies (match/compare/select) study
- https://tilores.io/content/can-llms-be-used-for-entity-resolution/ — LLM ER economics: 100–1000x cost at scale, good for small datasets/edge cases
- https://arxiv.org/pdf/2606.06003 — graph-augmented retrieval vs vector-only, structural analysis
- https://www.dsebastien.net/2022-05-15-maps-of-content/ — MOC/hub-page practice
- https://ericmjl.github.io/blog/2026/3/6/mastering-personal-knowledge-management-with-obsidian-and-ai/ — entity-notes (people/org) vault pattern with AI
