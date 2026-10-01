# Knowledge Health Review — 2026-10-01

---
date: 2026-10-01
scope: monthly knowledge health — docs/ staleness, broken links, spec-graph orphans, memory
related: ADR-016 (spec-dependency-graph), ADR-028 (ontology-v2), ADR-037 (memory-enforcement), docs/reviews/knowledge-2026-09-01.md
---

**Verdict:** Corpus is healthy and growing at a steady pace. Three standing issues from September carry over with modest deltas: (1) cross-repo dimension links unresolvable in this clone, (2) 124 Roadmap orphans in spec-graph, (3) 11 ADR orphans. **One new finding**: `docs/archive/` is contributing 241 false-positive broken links that inflate the total count — these should be excluded from link-checking. Non-archive broken links are down from ~482 (Sep) to ~387, a meaningful improvement. Placeholder links remain unactioned at 11. MCP server failures (`brana`, `ruflo`) continue as an operational concern independent of doc health.

---

## 1. Spec-graph snapshot

| Metric | Sep 2026 | Oct 2026 | Delta |
|--------|----------|----------|-------|
| Nodes  | 620      | 641      | +21   |
| Edges  | 2,426    | 2,551    | +125  |
| Orphans | 142     | 144      | +2    |
| Generated | 2026-09-01 | 2026-09-21 | — |
| Ontology | 1.5 | 1.5 | — |

Node type breakdown (Oct):
- Roadmap: 456 (71%)
- Dimension: 84 (13%)
- ADR: 93 (15%)
- Reflection: 8 (1%)

Growth is healthy and consistent. 21 new nodes and 125 new edges in one month. The ADR count grew from 88 → 93 (+5), reflecting the ADR-080–ADR-085 additions from the ship/validate work. Spec-graph was last regenerated 2026-09-21 — 10 days of commits since then include ADR additions and hooks reference regeneration. **Recommend refreshing spec-graph.json** (`brana graph build`) after the next ship cycle.

---

## 2. Staleness — NO STALE DOCS

All `docs/` files have a last commit date of `2026-08-30` (the mass import), which is within the 90-day window (cutoff: 2026-07-03). The active ADRs and reference docs are being updated regularly (5+ ADR commits in September). No stale docs requiring action.

Note: this is a fresh remote clone — full history landed in a single commit, so individual file timestamps reflect that import date rather than true authorship dates. The September review confirmed the corpus was current as of 2026-07-31. No regression since then.

---

## 3. Broken internal links — 628 total (387 net of archive)

### 3a. Archive inflation — NEW FINDING (HIGH)

`docs/archive/` was created as a pre-supersession snapshot and contributes **241 broken links** from `docs/archive/24-roadmap-corrections.md` alone. These are expected: the archive preserves cross-repo `dimensions/` links that were valid at time of archival. The link checker should exclude this directory.

**Fix (actionable):** Add `docs/archive/` to the link-checker exclusion list (or `.markdownlintignore` / CI ignore config). One-line change.

### 3b. Cross-repo dimension links — ~290 (CARRY-OVER, HIGH)

Same root cause as August and September: live docs link to `dimensions/XX-name.md` (relative), but `docs/dimensions/` does not exist — dimensions live in `brana-knowledge/` (separate repo). Top offenders:

| File | Broken links |
|------|-------------|
| `docs/24-roadmap-corrections.md` | 83 |
| `docs/reflections/08-diagnosis.md` | 20 |
| `docs/17-implementation-roadmap.md` | 29 |
| `docs/25-self-documentation.md` | 24 |
| `docs/18-lean-roadmap.md` | 22 |
| `docs/30-backlog.md` | 15 |
| `docs/reflections/29-venture-management-reflection.md` | 13 |

**This was raised in August and September and remains unactioned. Escalating to HIGH.**

Recommended fix: add CI exclusion for relative paths matching `dimensions/.*\.md` pattern. This is a one-liner in any link-checker config. As a secondary action, add a short comment block at the top of the five most-linked files noting that `dimensions/` links are cross-repo (brana-knowledge) and will appear broken in this clone.

### 3c. Other broken links — ~97

Remaining (non-archive, non-dimension) broken links:
- `../../.claude/tasks.json` — 10 occurrences in reflections; tasks.json is gitignored and not under `docs/`. Remove these links from reflections — they reference runtime state, not static docs.
- `../39-architecture-redesign.md` — 5 occurrences; file exists at `docs/39-architecture-redesign.md` but links from deep subdirectories resolve incorrectly. Verify nesting depth on each.
- Cross-archive references — `docs/archive/reflections/14-mastermind-architecture.md` has 18 broken links into archived material; expected, skip.

---

## 4. Spec-graph orphans — 144 nodes

### 4a. Roadmap orphans — 124 (+2 from Sep)

Concentrated in:
| Directory | Approximate count |
|-----------|------------------|
| `docs/ideas/drained/` | ~17 |
| `docs/guide/workflows/` | ~13 |
| `docs/architecture/features/` | ~14 |
| `docs/architecture/field-notes/` | ~12 |

The 2-unit growth is minor. Most feature specs in `docs/architecture/features/` are intentionally leaf nodes — written as part of DDD/SDD but not yet linked from a parent roadmap node. This pattern is expected but worth a periodic sweep to connect orphaned feature specs to their parent epic.

**Recommended action:** During the next `/brana:reconcile --scope propagation` run, include a sub-step that links unconnected `features/` nodes to their parent epic in the graph.

### 4b. ADR orphans — 11 (unchanged)

Same set as September:
- ADR-034 (skill-tiering), ADR-035 (skill-usage-telemetry), ADR-041 (agy-invocation-contract)
- ADR-043 (session-labels-breadcrumb), ADR-044 (initiative-accumulator), ADR-045 (backlog-ui-transport)
- ADR-046 (smart-search-load-default), ADR-048 (memory-consolidation-trigger-model)
- ADR-058 (search-provider-hybrid-recall), ADR-064 (retrieval-routing-graphify), ADR-073 (persona-session-state)

These may represent decisions that were made but not yet cited by any reflection or roadmap node, or decisions that are implicitly superseded. **Recommended action:** review these 11 ADRs and either (a) add a `superseded_by` edge to the graph, or (b) add a citation from the relevant reflection.

### 4c. Dimension orphans — 9 (unchanged)

All in `brana-knowledge/dimensions/` (separate repo). Includes:
- `56-ruflo-agentdb-architecture.md`, `57-chess-erp-api.md`, `60-upstash-platform.md`
- Several ad-hoc dimensions: `alternative-education-methodologies.md`, `contract-operations-platforms.md`, `feynman-methodology.md`, `meta-whatsapp-template-classification.md`, `new-topic.md`, `serverless-edge-functions-platforms.md`

`new-topic.md` is a stale stub — should be deleted or renamed. The others appear to be research dimensions not yet referenced by any reflection. Low priority.

---

## 5. Placeholder links — 11 (CARRY-OVER, MEDIUM)

Same set of unfilled template links as September, distributed across:
- `docs/reference/rules.md` — 2 occurrences (`relative-path.md`)
- `docs/ideas/drained/skill-semantic-validation.md` — 1 (`relative/path.md`)
- `docs/guide/knowledge-system.md` — 1 (`path.md`)
- `docs/guide/workflows/spec-graph.md` — 1 (`path`)
- `docs/architecture/system-documentation-map.md` — 1 (`relative-path.md`)
- `docs/architecture/testing-validation.md` — 1 (`path`)
- `docs/architecture/features/knowledge-architecture-v2.md` — 2 (`path.md`)
- `docs/architecture/decisions/ADR-016-spec-dependency-graph.md` — 1 (`path`)
- `docs/architecture/decisions/ADR-021-knowledge-architecture-v2.md` — 1 (`path`)

These are low-cost to fix (fill or remove each link). Three months unactioned — suggest batching as a 30-minute cleanup task in the next maintenance window.

---

## 6. Memory files — NOT AUDITABLE (remote clone)

`.claude/memory/` is not present in this remote environment. The loop script references `~/.claude/projects/.../memory/MEMORY.md` which lives on the user's local machine, not in the repo. Memory hygiene requires a local session.

`.claude/loop.md` and `.claude/CLAUDE.md` are present and current. No action needed for in-repo `.claude/` files.

---

## 7. Activity since last review (2026-09-01)

Notable doc-touching commits:
- `ae0f76b chore(docs): refresh spec-graph.json` — spec-graph regenerated 2026-09-21
- `13be619 fix(docs): regenerate hooks.md reference after t-3361` — hooks reference kept current
- `320a39f docs(decisions): the log is also fed by task-completed.sh` — ADR addition
- `6fbf8a0 fix(state): stop publishing private client state` — privacy fix

Active development on the ship/validate path (t-3366, t-3369). No orphaned in-progress branches visible. Branch naming convention followed in all recent commits.

---

## Priority action list

| Priority | Finding | Action |
|----------|---------|--------|
| HIGH | Archive false positives (+241 broken links) | Exclude `docs/archive/` from link checker |
| HIGH | Cross-repo dimension links (carry-over, 3rd month) | Add CI exclusion for `dimensions/` relative paths |
| MEDIUM | 11 placeholder links (carry-over, 3rd month) | Batch fill/remove in a cleanup task |
| MEDIUM | 11 orphan ADRs in graph | Review each: add superseded_by edge or reflection citation |
| LOW | Spec-graph 10 days stale | Run `brana graph build` after next ship cycle |
| LOW | `brana-knowledge/dimensions/new-topic.md` orphan | Delete or rename stub |
| INFO | MCP servers `brana`/`ruflo` failing to connect | Operational issue; see session startup errors |
