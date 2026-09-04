# Knowledge Health Review — 2026-09-01

---
date: 2026-09-01
scope: monthly knowledge health — docs/ staleness, broken links, spec-graph orphans, memory
related: ADR-016 (spec-dependency-graph), ADR-028 (ontology-v2), ADR-037 (memory-enforcement), docs/reviews/knowledge-2026-08-01.md
---

**Verdict:** Corpus is actively growing and structurally sound. Three standing issues carry over from August with no new root causes: (1) 333 cross-repo dimension links unresolvable in this clone, (2) 122 Roadmap orphans in spec-graph concentrated in `ideas/drained/`, `guide/workflows/`, and `architecture/features/`, and (3) 11 ADR orphans disconnected from the graph. MCP server failures (`brana`, `ruflo`) are an operational concern independent of doc health.

---

## 1. Spec-graph snapshot

| Metric | Aug 2026 | Sep 2026 | Delta |
|--------|----------|----------|-------|
| Nodes  | 536      | 620      | +84   |
| Edges  | 2,000    | 2,426    | +426  |
| Orphans | 139     | 142      | +3    |
| Generated | 2026-07-31 | 2026-09-01 | — |
| Ontology | — | 1.5 | — |

Node type breakdown (Sep):
- Roadmap: 440 (71%)
- Dimension: 84 (14%)
- ADR: 88 (14%)
- Reflection: 8 (1%)

Growth is healthy — 84 new nodes and 426 new edges in one month. The Roadmap category dominates at 71%, consistent with the feature-spec and ADR-heavy development pattern.

---

## 2. Staleness — INCONCLUSIVE (fresh clone)

All `docs/` files show `2026-08-30` as their last commit in this environment because this is a fresh clone where all history landed in a single initial commit. True staleness can only be assessed in the working environment with full git history. **No action needed here.**

If running this review locally: flag any file with no commit newer than 90 days (`git log -1 --format='%ci' -- <file>`). Based on the August review, the corpus was fully refreshed through 2026-07-31 — nothing was stale then.

---

## 3. Broken internal links — 482 total

### 3a. Cross-repo dimension links — 333 (CARRY-OVER, HIGH)

Same root cause as August: live docs link to `dimensions/XX-name.md` (relative), but `docs/dimensions/` does not exist — dimensions live in `brana-knowledge/` (a separate repo not cloned here).

**Top offenders (unchanged from August):**
| File | Broken links |
|------|-------------|
| `docs/24-roadmap-corrections.md` | 85 |
| `docs/reflections/08-diagnosis.md` | 64 |
| `docs/17-implementation-roadmap.md` | 29 |
| `docs/25-self-documentation.md` | 24 |
| `docs/reflections/14-mastermind-architecture.md` | 23 |
| `docs/18-lean-roadmap.md` | 22 |
| `docs/reflections/31-assurance.md` | 21 |

**Fix:** Add CI exclusion for `dimensions/` relative paths (any link-checker will false-positive these). Add a header comment to the top 5 files noting cross-repo links. This was recommended in the August review and remains unactioned — escalating to medium priority.

### 3b. Other broken links — 149

Most are:
- `../../.claude/tasks.json` — 10 occurrences; tasks.json doesn't live under `docs/` and is gitignored. These links in reflections are stale — either remove or update to backlog URLs.
- `../39-architecture-redesign.md` — 5 occurrences; file exists at `docs/39-architecture-redesign.md` but links from deeper subdirectory contexts resolve incorrectly. Check nesting depth.
- Placeholder links (`path`, `path.md`, `relative-path.md`) — 11 occurrences scattered across feature specs and guide docs. These are unfilled templates.

**Recommended fix for placeholders:** search `grep -r '"path\b\|"relative-path' docs/` and fill or remove. 11 occurrences is manageable.

---

## 4. Spec-graph orphans — 142 nodes

### 4a. Roadmap orphans — 122 (ELEVATED)

Concentrated in:
| Directory | Count |
|-----------|-------|
| `docs/ideas/drained/` | 17 |
| `docs/guide/workflows/` | 13 |
| `docs/architecture/features/` | 12 |
| `docs/guide/features/` | 7 |
| `docs/reviews/` | 7 |
| `docs/research/` | ~15 |
| `docs/personal/` | 7 |
| `docs/dimensions/` (stub copies) | 11 |

**Root cause:** Feature specs, guide stubs, personal research, and drained ideas are created but never wired into the reflection or dimension graph. The `docs/dimensions/` copies are stub duplicates of content that belongs in `brana-knowledge/dimensions/` — these are the ones at risk of diverging.

**Fix:** Run `/brana:reconcile --scope propagation` to identify which orphans have parent reflections that should reference them. The `docs/ideas/drained/` cluster is expected to be orphaned — drained ideas are intentionally parked. The `docs/guide/` and `architecture/features/` orphans are higher priority: they represent living documentation that should be linked from reflections or ADRs.

### 4b. ADR orphans — 11 (NEW since August, HIGH)

These ADRs exist in the graph as nodes but have no edges to/from any Dimension or Reflection:

- ADR-034 (skill-tiering)
- ADR-035 (skill-usage-telemetry)
- ADR-041 (agy-invocation-contract)
- ADR-043 (session-labels-breadcrumb)
- ADR-044 (initiative-accumulator)
- ADR-045 (backlog-ui-transport)
- ADR-046 (smart-search-load-default)
- ADR-048 (memory-consolidation-trigger-model)
- ADR-058 (search-provider-hybrid-recall)
- ADR-064 (retrieval-routing-graphify)
- ADR-073 (persona-session-state)

**Fix:** Each should be linked from the Dimension or Reflection it was derived from. The `brana graph build` tool should infer these from `related:` frontmatter — check if frontmatter is populated. Reaching 11 ADR orphans is a signal that frontmatter discipline is slipping on new ADRs.

### 4c. Dimension orphans — 9

Mostly specialty topic dimensions (Chess ERP, Upstash, WhatsApp templates) with no parent reflection. Low priority — these may be exploratory. Exception: `brana-knowledge/dimensions/new-topic.md` is a template stub and should be deleted or renamed.

---

## 5. Memory — NOT APPLICABLE

`.claude/memory/` does not exist in this repository. Memory lives in the deployed `~/.claude/` environment. No audit possible from this clone.

---

## 6. Operational findings

**MCP server failures:** Both `brana` and `ruflo` MCP servers failed to connect at session start (`ENOENT: no such file or directory`). This is a deployment gap — the binaries are not installed in this remote environment. No knowledge docs are affected, but any session-level knowledge tooling (ruflo queries, brana graph commands) is unavailable.

---

## 7. Priority action list

| Priority | Item | Effort |
|----------|------|--------|
| **HIGH** | Add CI link-check exclusion for `dimensions/` relative paths | 30 min |
| **HIGH** | Add frontmatter `related:` to 11 orphaned ADRs (034, 035, 041, 043–046, 048, 058, 064, 073) | 2h |
| **MEDIUM** | Fix 11 placeholder links (`path`, `path.md`, `relative-path.md`) | 1h |
| **MEDIUM** | Wire `docs/guide/` and `docs/architecture/features/` orphans into reflections | 2h |
| **LOW** | Delete `brana-knowledge/dimensions/new-topic.md` stub | 5 min |
| **LOW** | Remove or update 10 stale `tasks.json` links in reflection docs | 30 min |

---

## 8. Month-over-month summary

| Metric | Aug | Sep | Trend |
|--------|-----|-----|-------|
| Total nodes | 536 | 620 | +84 ↑ healthy |
| Edges | 2,000 | 2,426 | +426 ↑ healthy |
| Orphan rate | 26% (139/536) | 23% (142/620) | ↓ improving |
| Broken links | 692 | 482 | ↓ improving |
| ADR orphans | — | 11 | ⚠ new finding |
| Placeholder links | 13 | 11 | ↓ slight improvement |

Graph growth is healthy and the orphan rate is actually improving as edges grow faster than nodes. The main regression is 11 newly orphaned ADRs — frontmatter discipline on ADR authoring should be tightened before this grows further.
