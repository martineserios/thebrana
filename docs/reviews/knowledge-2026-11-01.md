# Knowledge Health Review — 2026-11-01

---
date: 2026-11-01
scope: monthly knowledge health — docs/ staleness, broken links, spec-graph orphans, memory
related: ADR-016 (spec-dependency-graph), ADR-028 (ontology-v2), ADR-037 (memory-enforcement), docs/reviews/knowledge-2026-10-01.md
---

**Verdict:** Active month — recall-bundle work (t-3505–t-3547) landed 6 new ADRs (ADR-094–ADR-099) and significant recall infrastructure. Spec-graph was refreshed in October (LOW item resolved). However, the **broken link count increased from 387 → 473 (+86)**, a regression driven primarily by `reflections/08-diagnosis.md` growing from 20 → 64 broken links (+44). All three HIGH/MEDIUM carry-over items from October remain unactioned — this is now the **4th month** for placeholder links and the **4th month** for cross-repo dimension link exclusion. Orphan count ticked up slightly (+4). MCP server failures continue.

---

## 1. Spec-graph snapshot

| Metric | Oct 2026 | Nov 2026 | Delta |
|--------|----------|----------|-------|
| Nodes  | 641      | 657      | +16   |
| Edges  | 2,551    | 2,598    | +47   |
| Orphans | 144     | 148      | +4    |
| Generated | 2026-09-21 | 2026-10-06 | refreshed ✓ |
| Ontology | 1.5 | 1.5 | — |

Node type breakdown (Nov):

| Type | Count | % |
|------|-------|---|
| Roadmap | 469 | 71% |
| ADR | 95 | 14% |
| Dimension | 85 | 13% |
| Reflection | 8 | 1% |

**ADR gap:** 98 ADR files on disk (ADR-001 through ADR-099), but only 95 in the graph — ADR-097, ADR-098, and ADR-099 were added after the 2026-10-06 regeneration. Spec-graph is 25 days stale as of this review. **Recommend regenerating** (`brana graph build`) after the next ship cycle, or as a standalone `dev` commit.

Orphan growth (+4) is driven by Roadmap nodes only; ADR and Dimension orphan counts are unchanged.

---

## 2. Staleness — NO STALE DOCS

Cutoff: 90 days before 2026-11-01 = **2026-08-03**. All `docs/` files show a last-commit date of 2026-08-31 (the mass import), which is 62 days — within the window. Active commits in October (recall-bundle ADRs, weekly reviews through 2026-10-16) confirm the corpus is being maintained. No docs require staleness action.

Note: Remote-clone limitation applies (mass-import date appears uniform; individual file authorship dates are not recoverable from this clone's history).

---

## 3. Broken internal links — 473 (non-archive) ⚠ REGRESSION

October net-of-archive count was ~387. This review counts 473 — an increase of **+86 broken links**. This is a regression, not noise.

### 3a. Cross-repo dimension links — dominant cause (~320 links) (CARRY-OVER HIGH, 4th month)

Same root cause as August through October: live docs reference `dimensions/XX-name.md` (relative paths), but `docs/dimensions/` does not exist in this repo — dimensions live in `brana-knowledge/`. This has been raised every month for four months and remains unactioned.

Top offenders (top 10 broken-link files):

| File | Broken links | Oct count | Delta |
|------|-------------|-----------|-------|
| `docs/24-roadmap-corrections.md` | 85 | 83 | +2 |
| `docs/reflections/08-diagnosis.md` | 64 | 20 | **+44** |
| `docs/17-implementation-roadmap.md` | 29 | 29 | 0 |
| `docs/25-self-documentation.md` | 24 | 24 | 0 |
| `docs/reflections/14-mastermind-architecture.md` | 23 | (not top-10) | new |
| `docs/18-lean-roadmap.md` | 22 | 22 | 0 |
| `docs/reflections/31-assurance.md` | 21 | (not top-10) | new |
| `docs/reflections/29-venture-management-reflection.md` | 18 | 13 | +5 |
| `docs/30-backlog.md` | 15 | 15 | 0 |
| `docs/reflections/32-lifecycle.md` | 15 | (not top-10) | new |

**Primary regression driver: `reflections/08-diagnosis.md` +44 links.** This file likely received substantial edits in October (perhaps during recall-bundle spec work) that added new `dimensions/` cross-repo references. Three reflections entered the top-10 for the first time (14-mastermind, 31-assurance, 32-lifecycle), suggesting reflections were updated to reference new dimensions added to brana-knowledge this month.

**Fix (unchanged from prior months):** Add a CI exclusion for relative paths matching `dimensions/.*\.md` in link-checker config. This is a one-liner. Additionally, the new entry of `reflections/08-diagnosis.md` warrants checking whether some links could be local cross-references (wrong relative path depth) rather than genuine cross-repo pointers.

### 3b. Runtime-state links — 11 occurrences (unchanged)

`../../.claude/tasks.json` appears in 11 reflection files. `tasks.json` is gitignored — these are dead links in a static check. Remove them or replace with a note that task state is runtime-only.

### 3c. Placeholder links — 11 (CARRY-OVER, **4th month** — ESCALATING)

Same 11 template placeholders as August, September, October. This is a trivial 30-minute fix that has been deferred four months:

| File | Link |
|------|------|
| `docs/reference/rules.md` | `relative-path.md` (×2) |
| `docs/ideas/drained/skill-semantic-validation.md` | `relative/path.md` |
| `docs/guide/knowledge-system.md` | `path.md` |
| `docs/guide/workflows/spec-graph.md` | `path` |
| `docs/architecture/system-documentation-map.md` | `relative-path.md` |
| `docs/architecture/testing-validation.md` | `path` |
| `docs/architecture/features/knowledge-architecture-v2.md` | `path.md` (×2) |
| `docs/architecture/decisions/ADR-016-spec-dependency-graph.md` | `path` |
| `docs/architecture/decisions/ADR-021-knowledge-architecture-v2.md` | `path` |

**Suggested fix:** Batch as a `chore` task; each is either fill-with-correct-path or delete-the-link. Entire fix fits in one small commit.

---

## 4. Spec-graph orphans — 148 nodes (+4)

| Type | Sep | Oct | Nov | Delta |
|------|-----|-----|-----|-------|
| Roadmap | 122 | 124 | 128 | +4 |
| ADR | 11 | 11 | 11 | 0 |
| Dimension | 9 | 9 | 9 | 0 |
| **Total** | 142 | 144 | 148 | +4 |

### 4a. Roadmap orphans — 128 (+4)

Steady slow growth consistent with new feature specs being written before they are linked into a parent epic. The 4-unit increase likely tracks with recall-bundle spec documents added in October. No action needed yet, but a periodic sweep (`/brana:reconcile --scope propagation`) remains recommended.

### 4b. ADR orphans — 11 (unchanged, MEDIUM carry-over)

Same 11 from September and October — none resolved in October:
- ADR-034 (skill-tiering), ADR-035 (skill-usage-telemetry), ADR-041 (agy-invocation-contract)
- ADR-043 (session-labels-breadcrumb), ADR-044 (initiative-accumulator), ADR-045 (backlog-ui-transport)
- ADR-046 (smart-search-load-default), ADR-048 (memory-consolidation-trigger-model)
- ADR-058 (search-provider-hybrid-recall), ADR-064 (retrieval-routing-graphify), ADR-073 (persona-session-state)

These have been orphaned 3+ months. Recommend a dedicated sweep: for each, either add `superseded_by` edge or cite from the relevant reflection. Some (ADR-058, ADR-064) may now be superseded by the recall-bundle work (ADR-099).

### 4c. Dimension orphans — 9 (unchanged)

All in `brana-knowledge/` (cross-repo). Includes the `new-topic.md` stub raised in prior months; status unverifiable from this clone.

---

## 5. Memory files — NOT AUDITABLE (remote clone)

`.claude/memory/` is not present in this remote environment. Memory hygiene requires a local session. No change from prior reviews.

In-repo `.claude/` files (`CLAUDE.md`, `loop.md`, `proven-config.json`, `workflows/`) are present and current.

---

## 6. Activity since last review (2026-10-01)

Significant October development on the recall-bundle epic:

- **Recall infrastructure** (t-3510, t-3517, t-3535, t-3536, t-3537, t-3540, t-3542, t-3543, t-3547): vector + FTS memory legs, usage log, `--bundle` / `--shadow` flags, scope hardening, session-start cleanup
- **Mods surface** (t-3505): cockpit, drift workflow, acknowledge valve — ADR-096 added
- **ADR-097** (upstream-band-standing-v1-3), **ADR-098** (retire-upstream-band), **ADR-099** (recall-bundle-and-usage-log)
- **Weekly reviews**: 2026-10-09, 2026-10-16
- **Spec-graph** regenerated 2026-10-06 (LOW item from October resolved ✓)
- Ship cycle: PR #1110 and PR #1109 merged to main

PR #1110 (`merge: origin/dev weekly review 2026-10-16`) is the most recent ship.

---

## 7. October priority action items — status

| Priority | Finding | Status |
|----------|---------|--------|
| HIGH | Archive false positives (+241 broken links) | ❌ Not done |
| HIGH | Cross-repo dimension links CI exclusion | ❌ Not done (4th month) |
| MEDIUM | 11 placeholder links | ❌ Not done (4th month) |
| MEDIUM | 11 orphan ADRs | ❌ Not done |
| LOW | Run `brana graph build` | ✅ Done (2026-10-06) |
| LOW | `brana-knowledge/dimensions/new-topic.md` stub | ❓ Unverifiable |

---

## Priority action list (November)

| Priority | Finding | Action |
|----------|---------|--------|
| HIGH | Broken link regression (+86): `reflections/08-diagnosis.md` added 44 links | Audit this file — are new links cross-repo or bad relative paths? |
| HIGH | Cross-repo dimension links CI exclusion (4th month) | One-liner in link-checker config — add `dimensions/.*\.md` exclusion |
| HIGH | Archive exclusion from link checker | One-liner — add `docs/archive/` to link-checker ignore |
| MEDIUM | 11 placeholder links (4th month) | Batch `chore` task — fill or delete each; 30-minute fix |
| MEDIUM | 11 orphan ADRs (3 months) | Review ADR-058/064 for recall-bundle supersession; cite or deprecate rest |
| LOW | Spec-graph 25 days stale; ADR-097/098/099 not indexed | Run `brana graph build` after next ship |
| INFO | MCP servers `brana`/`ruflo` still failing | Operational; unrelated to doc health |
