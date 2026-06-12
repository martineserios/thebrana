---
depends_on:
  - docs/architecture/decisions/ADR-028-ontology-v2.md
  - docs/architecture/decisions/ADR-021-knowledge-architecture-v2.md
informs:
  - docs/architecture/decisions/ADR-042-knowledge-ingest-canonical-entry-point-gemini-routing.md
  - docs/architecture/decisions/ADR-038-memory-write-gateway.md
  - docs/ideas/knowledge-base-redesign.md
status: proposed
---

# ADR-056: Unit of Knowledge — One Schema, Three Consumers

**Date:** 2026-06-12
**Status:** Proposed — acceptance conditional on t-2030 (ontology update) merging before Phase 1 begins: the schema names four types (`claim`, `event`, `source`, `hub`) that brana-ontology.yaml v1.5 does not carry, and validate.sh Check 18 would reject them until the ontology does
**Tasks:** t-2027 (this ADR), phase t-2021 (Knowledge Base Redesign); consumers: t-2028 (ADR-042 amendment), t-2030 (ontology update), t-2031..t-2035 (enforcement), t-2039 (event promotion)
**Source:** docs/ideas/knowledge-base-redesign.md (brainstorm + dual challenger review 2026-06-12); 2026-06-11 knowledge-structure audit; corpus-root and migration-mode decisions confirmed by user 2026-06-12

## Context

The knowledge base grew as ~6 independent stores with no shared schema: `brana-knowledge/dimensions/`, the spec corpus in `thebrana/docs/` (reflections, decisions, ideas), two CC memory directories (`~/.claude/projects/*/memory/`, `~/.claude/memory/`), the ruflo vector index, and `tasks.json` context fields. The 2026-06-11 audit symptoms — disjoint type systems (brana-ontology.yaml vs the ADR-038 memory taxonomy) and near-absent typed relations in memory files — are downstream of this fragmentation.

Three prior decisions constrain this one:

- **ADR-021** (accepted) mandated per-doc temporal metadata (`valid_from`, `confidence_tier`, `maturity_stage`) and the 3-layer architecture. The temporal mandate was never implemented — no current dimension doc carries those fields. The lesson is structural: **a schema announced without a blocking enforcement mechanism does not get adopted.** This ADR executes the temporal mandate and pairs it with enforcement (phase t-2021, Phase 1).
- **ADR-028** (accepted) fixes the 3-layer constraint (ontology → frontmatter → graph), requires frontmatter relations to use ontology relationship types only, and defines measurement-gated type activation (deferred types auto-promote on first frontmatter use, zero-usage types demote).
- **ADR-038** (proposed, unimplemented) drafted a 7-type memory routing taxonomy and a write gateway. Its CLI was never built. This ADR absorbs its taxonomy (see §7); the gateway concept survives as the Phase 1 hard gate (t-2035).

Research grounding (2026-06-12 scouts): atomic notes outperform long multi-topic docs on retrieval precision (multi-theme documents dilute embeddings); graph queries are irreplaceable for schema-bound/structural questions where vector-only retrieval fails; folder taxonomies are decorative to every machine consumer — type belongs in frontmatter. Brana already has the right pipeline shape (ruflo indexers / graph CLI / MEMORY.md are three extraction passes over the same files); the content units are what's wrong.

## Decision

One frontmatter spec where the ontology IS the schema. Every corpus file declares `type:` (an ontology type) and `relations:` (typed edges). The text serves ruflo, the frontmatter serves the graph, the wiki-links serve Obsidian. One file, three consumers, zero translation layers.

### 1. Corpus root — federated, with brana-knowledge/ as the vault

**`brana-knowledge/` is the canonical vault** — the home of atoms, hubs, and source notes, and the Obsidian vault root. The corpus is federated:

| Shelf | Location | Role | Constraint |
|---|---|---|---|
| **Vault** | `brana-knowledge/` | atoms (claim/pattern/event/source), hubs, source notes | Obsidian vault root |
| **Spec shelf** | `thebrana/docs/` | decisions (ADRs), reflections, feature specs, domain models | repo-coupled (spec-graph.json, validate.sh, reconcile); conforms to the same schema in place |
| **Satellite shelves** | `~/.claude/projects/*/memory/`, `~/.claude/memory/` | CC harness memory | location harness-fixed (CC auto-loads MEMORY.md); files conform to the schema, never relocate |

**Corpus roots are to become configuration, not convention.** Today no `corpus_roots` config exists: `brana graph build` hardcodes two scan roots (`docs/`, `brana-knowledge/dimensions/`) and `index-knowledge.sh` hardcodes its `DOC_CATEGORIES` array. Phase 1 (t-2033, t-2034) replaces both with a `corpus_roots` list naming the shelves above (config location decided in those tasks); from then on tools never hardcode shelf paths and adding/moving a shelf is a one-line change. **Transition window:** until Phase 1 ships, atoms written to `brana-knowledge/atoms/` are invisible to the graph, and `classify_node()`'s path-based fallbacks would mislabel them (any `brana-knowledge/` path falls back to `Dimension`) — those fallback heuristics are explicitly in t-2033's scope. No atom authoring is announced until Phase 1 is merged. Reversibility guarantee: the vault is a folder of plain Markdown with standard frontmatter — relocatable later by editing `corpus_roots`, with no content rewrite.

**Vault layout** (decorative — ergonomics only; no tool may infer type from path):

```
brana-knowledge/
  atoms/          # claim, pattern, event, source — flat, type in frontmatter
  hubs/           # maps of content (curated synthesis)
  dimensions/     # legacy long-form docs — healed opportunistically (Phase 3: top-5)
  references/     # legacy source lists — become source atoms opportunistically
  inbox/ drafts/  # transient working areas (not corpus content)
  backup/         # vector-DB backups and backup tooling — NOT corpus content
```

**Backup untangling:** the DB backup artifacts currently at the repo root (`agentdb.rvf`, `ruvector.db`, lock file, backup scripts) move under `backup/`, excluded from corpus indexing (corpus_roots never lists it). Obsidian exclusion is a per-machine user setting (Settings → Files & Links → Excluded files), not a committable config — documented, not automated. These are live database files written by a cron: the move is its own task with a stop-cron → move → update script paths → restart-cron sequence, never a bare `git mv` while the cron runs.

**Obsidian fit (confirmed):** open `brana-knowledge/` as the vault. Frontmatter renders natively as Obsidian Properties (type, status, dates are filterable); wiki-links power the graph view and backlinks; flat-ish folders with frontmatter types is exactly the layout Obsidian handles best. One caveat: the satellite shelves live outside the vault root, so memory files won't appear in Obsidian unless symlinked in (symlinks work but are fragile across machines) — accepted for v1; the satellites' consumers are ruflo and the graph, not Obsidian.

### 2. Type system — C-minimal

```
ATOMS (typed, atomic, machine-validated)
  claim    — falsifiable statement; carries confidence and review_due
  pattern  — problem → solution; quarantine → proven lifecycle
  event    — immutable, timestamped; never stale; causal anchor
  source   — external reference; carries tier

SYNTHESIS (curated, may be long)
  hub      — map of content; curates atoms and other hubs
  decision — ADR; unchanged from today

DEFERRED (ADR-028 measurement-gated; auto-promote on first frontmatter use)
  constraint, question
```

Scope, not kind, distinguishes a dimension-hub from a reflection-hub — the link structure expresses it; no separate type. `decision` is the existing ADR type under its ontology name; ADR files do not change shape beyond schema conformance.

Ontology impact (executed in t-2030, Phase 0): `Claim`, `Event`, `Source`, `Hub` enter the active set; `Pattern` is already active; `Decision` aliases the existing ADR node type; `Dimension` and `Reflection` remain as legacy active types until Phase 3 heals them into hubs, then demote per ADR-028 measurement gating.

### 3. Frontmatter schema

Required on every corpus file (all shelves):

```yaml
---
type: claim | pattern | event | source | hub | decision   # ontology enum — REQUIRED
title: one-line title                                      # REQUIRED
created: YYYY-MM-DD                                        # REQUIRED
valid_from: YYYY-MM-DD          # defaults to created; bi-temporal per ADR-021
review_due: YYYY-MM-DD          # REQUIRED except type: event, source
status: draft | active | superseded | archived             # REQUIRED
confidence: proven | working | quarantine                  # REQUIRED for claim, pattern
tier: high | medium | low                                  # REQUIRED for source
relations:                      # typed edges — ontology relationship types ONLY (ADR-028)
  - type: informs               # depends_on | informs | supersedes (+ deferred types on promotion)
    to: atoms/2026-06-12-ruflo-db-wipe.md
tags: []                        # optional
---
```

Per-type rules:

| Type | Immutable? | review_due | Extra required |
|---|---|---|---|
| claim | no | yes | confidence |
| pattern | no | yes | confidence |
| event | **yes — append-only corpus, never edited after creation** | no (never stale) | — |
| source | no | no | tier |
| hub | no | yes | — |
| decision | body frozen per ADR convention | no (status carries lifecycle) | — |

Per-type vocabulary exceptions: for `type: decision`, `status` additionally accepts the existing ADR vocabulary (`Proposed | Accepted | Superseded`) — current ADR files must not need rewriting to pass. For `type: hub`, `review_due` defaults to 18 months from `created`; operational/tactical hubs (e.g. project-context hubs that update continuously) may omit it — the validator accepts absent `review_due` on hubs with `status: active`.

Satellite-file coexistence: existing memory files carry `name:`/`description:`/`type: feedback`-style frontmatter (ADR-038 routing types, not ontology types). The schema gate treats ADR-038 routing types on satellite shelves as *legacy-valid* until the Phase 3 reconciliation (t-2043) converts them; `name:` and `description:` coexist with the new fields (MEMORY.md indexing keeps reading them).

Wiki-links in the body remain free-form (Obsidian navigation). **Frontmatter `relations:` is the single authoritative edge source for the graph** — `brana graph build` reads it; body links are decoration. This resolves the current split where the graph CLI reads both.

Temporal semantics: this executes ADR-021's mandate with two simplifications — `confidence` replaces `confidence_tier` (same intent, per-type applicability), and `status` absorbs `maturity_stage` (draft≈seedling, active≈budding/evergreen). ADR-021's review-cadence guidance (tech 6mo / architecture 18mo / methodology 36mo) becomes the default `review_due` offsets at authoring time.

### 4. Old → new mapping

| Current store / unit | Becomes |
|---|---|
| Dimension doc | hub + extracted claim/source atoms (Phase 3, top-5 first) |
| Reflection | hub that curates other hubs; novel conclusions extracted as claims |
| Idea doc | question/claim atoms + optional hub (lifecycle sweep t-2041) |
| ADR | decision — schema conformance only |
| `feedback_*` memory file | pattern or claim atom if structural; stays ruflo-only if behavioral |
| `field-note_*` memory file | claim atom |
| `pattern_*` memory file | pattern atom |
| `project_*` / `user_*` memory file | satellite-only (behavioral, no graph node) — conforms to schema, type from the deferred/behavioral set |
| `/brana:log` entries | event atoms (promoted selectively — §6) |
| Project context | hub curating recent events + active claims (replaces the mutable blob) |
| ruflo vector index | downstream consumer — no schema of its own; keeps indexing conformant files unchanged |
| `tasks.json` context fields | unchanged — tactical, not corpus |

Graph-node eligibility (from the 2026-06-12 discussion): *structural* (knowledge, not behavior) + *has edges* + *traversal value*. `pattern` and `field-note`-derived claims qualify; `feedback`/`project`/`user` remain ruflo-and-satellite only.

### 5. Migration — convention-forward with a ratcheting completion gate

**No big-bang.** The convention binds new writes only, enforced before announced (Phase 1 gates ship before Phase 2 authoring changes). The old corpus heals opportunistically plus scheduled Phase 3 work.

**Completion gate (per shelf):** percentage of *active* files (status not archived) passing the validate.sh schema check. The gate **ratchets**: each `validate.sh` run records per-shelf compliance; a drop below the high-water mark fails validation. **Archiving does not count as migration**: validate.sh also tracks absolute active-file counts per shelf, and a shelf whose active count drops without a matching rise in schema-conformant archived files emits a WARN — `status: archived` is not an escape hatch from the schema. A shelf is *migrated* at full compliance of active files; the redesign is *complete* when every shelf is migrated and no active file carries a legacy type (`Dimension`, `Reflection`).

**Baselines:** the vault and spec shelves start the ratchet at their measured Day-1 compliance. The satellite shelves start at their measured baseline too — but until the Phase 3 reconciliation (t-2043) ships, satellite non-conformance is WARN-level, not FAIL (every existing memory file would otherwise fail on day one).

**Enforcement (binding on Phase 1 — the answer to the ADR-021 ghost):**
- validate.sh schema/lifecycle checks, blocking (t-2032)
- `brana graph build` + `index-knowledge.sh` classify by frontmatter `type:`, never by path (t-2033, t-2034)
- memory-write hard gate (t-2035): `memory-write-gate.sh` is **promoted from advisory to enforcement class** — its hooks.json entry drops `continueOnBlock: true` (per the gate taxonomy in `docs/architecture/hooks.md`, enforcement hooks carry *no* `continueOnBlock` key; `continueOnBlock: false` is not a recognized pattern). The CC auto-memory bypass is preserved by the `~/.claude/` path check *inside the script*, not by hook config. The bypass sentinel is `/tmp/brana-memory-write-active` — the sentinel live skill procedures already set; no second sentinel is introduced. t-2035 amends hooks.json and the hooks.md gate-classification table in the same commit.
- **No authoring convention is announced or documented as active until these gates are merged.**

### 6. Event-promotion heuristic (consumed by t-2039)

`/brana:log` stays append-only and low-friction. An entry is **promoted** to an `event` atom when it satisfies any of:

1. **Causal anchor** — it explains a decision or claim (something references or will reference it: "X happened → therefore ADR/claim Y").
2. **Irreversible or external** — deploys, data loss, client commitments, money moved, contracts.
3. **Expected recurrence** — the entry will be needed to recognize a repeat (incidents, vendor behavior).

Routine captures (links, passing ideas, status notes) are NOT events — they are source/question atoms or stay in the log. Promotion is suggest-then-confirm: Claude proposes (`/brana:log` flow or close-time sweep), the user confirms; never auto-promoted. Promoted events get `relations:` edges to what they inform — best-effort at creation: if the target is unknown at promotion time, `relations: [{type: informs, to: TBD}]` is a valid placeholder and does not block promotion; an event with no edge and no placeholder fails the validate.sh schema check. Immutability is scoped to the **body**: event body text is append-only and never edited, but `relations:` entries may be *appended* (never edited or removed) when a target is identified later or a placeholder is resolved.

### 7. ADR-038 disposition

ADR-038 (proposed, never implemented as a whole) is **superseded by this ADR for the graph-eligible taxonomy**: `pattern`, `field-note`, `feedback`, `project`, `user` map per §4. Its `convention` (→ CLAUDE.md) and `adr` (→ draft ADR) routing types are **not** absorbed — they remain governed by ADR-038 §A until explicitly superseded. The `brana memory write` CLI gateway (ADR-038 §C, partially live in brana-cli) **remains the authoring path for typed memory files**; the Phase 1 hard gate (t-2035) adds schema validation *inside* that gateway path and promotes the hook (per §5), not a parallel enforcement surface. ADR-038's intentional-bypass clause (CC auto-memory writes pass through) is retained via the script-internal `~/.claude/` path check.

ADR-042 is amended (t-2028, separate task) only to require `type:` frontmatter on ingest output; its Tier 1/2 Gemini routing is untouched.

## Ubiquitous language

**atom** (smallest typed knowledge unit) · **hub** (curated map of content) · **claim / pattern / event / source** (atom types per §2) · **decision** (ADR) · **shelf** (one corpus location) · **vault** (the brana-knowledge shelf, Obsidian root) · **satellite shelf** (harness-fixed memory dirs) · **corpus root** (configured shelf list) · **promotion** (log entry → event atom; deferred type → active type) · **ratchet** (compliance high-water mark that may not regress). A knowledge-context domain model (MODEL-002) may formalize these if the Rust CLI grows a knowledge bounded context; not required for this phase.

## Consequences

**Positive:** retrieval precision (atomic units, clean embeddings); structural queries become possible (impact analysis, orphan detection, deterministic LOAD — phase t-2021 Phase 4); Obsidian navigability for free; ADR-021's temporal mandate finally executes with teeth; one schema ends the six-convention drift; reversible corpus root.

**Negative / accepted:** authoring friction (frontmatter required — mitigated by templates and the suggest-then-confirm flows); satellites stay physically split (harness constraint) and invisible to Obsidian; long migration tail by design (ratchet makes it monotonic); ontology grows by four active types (watched by ADR-028's zero-usage demotion).

**Risks:** type-assignment quality is unproven until the ~50-note audit (t-2040) — the go/no-go before Phase 3 bulk healing; the ratchet depends on validate.sh actually blocking (Phase 1 is the keystone; if it slips, stop and reassess rather than announcing convention anyway).

## Non-Actions

- CC memory directories are not relocated (harness-fixed).
- No big-bang migration; no atomization beyond top-5 dimensions in Phase 3.
- `constraint` and `question` types are not activated here — ADR-028 auto-promotion on first use.
- No new ruflo namespaces; no ruflo metadata-filtering workarounds (structured queries are the graph's job).
- No calendar/Obsidian plugins or sync tooling — the vault is plain files.
- tasks.json context fields stay tactical — not corpus, not migrated.
