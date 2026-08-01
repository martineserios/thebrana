# Knowledge Health Review — 2026-08-01

---
date: 2026-08-01
scope: monthly knowledge health — docs/ staleness, broken links, spec-graph orphans, memory
related: ADR-016 (spec-dependency-graph), ADR-028 (ontology-v2), ADR-037 (memory-enforcement), docs/reviews/knowledge-structure-audit-2026-06-11.md
---

**Verdict:** Doc corpus is actively maintained — zero staleness, strong recent activity. Two structural problems dominate: (1) 328 cross-repo dimension links in live docs that will never resolve inside this clone, and (2) 13 unfilled template placeholders scattered across new and reference docs. A smaller set of 7 moved-reflection links and 2 deleted-file links in README are straightforward to fix.

---

## 1. Spec-graph snapshot

| Metric | Value | Note |
|--------|-------|------|
| Nodes | 536 | Up from ~430 (June audit) |
| Edges | 2,000 | Up from ~1,636 |
| Generated | 2026-07-31 | Current |
| True orphans (no edge) | 139 | See §4 |

Node type breakdown:
- Roadmap: 371
- Dimension: 83
- ADR: 74
- Reflection: 8

---

## 2. Staleness — CLEAN

**No files flagged.** All 150+ docs in `docs/` were modified between 2026-07-27 and 2026-07-31. This is healthy; the bulk-commit on 2026-07-27 likely reflects a repo restructure or mass migration.

---

## 3. Broken internal links — 692 total

### 3a. Archive docs (273 links) — low priority

`docs/archive/24-roadmap-corrections.md` alone accounts for 243 broken links to moved/deleted dimensions and reflections. Archive is read-rarely; fix only if promoted back to live.

### 3b. Cross-repo dimension links — 328 occurrences, 23 files (HIGH)

Root cause: 99 unique `dimensions/XX.md` links in live docs that assume dimensions live under `docs/dimensions/`. They actually live in `brana-knowledge/` (a separate repo, not cloned here). Every CI link-checker will fail these.

**Affected files (top 5):**
- `docs/24-roadmap-corrections.md` (85 links)
- `docs/reflections/08-diagnosis.md` (64 links)
- `docs/reflections/14-mastermind-architecture.md` (23 links)
- `docs/18-lean-roadmap.md` (22 links)
- `docs/reflections/31-assurance.md` (21 links)

**Fix options:**
1. Add a note at the top of these files: `<!-- cross-repo links: dimensions/ → brana-knowledge/dimensions/ -->` and exclude the pattern from CI link-check
2. Migrate to absolute GitHub URLs for brana-knowledge dimension docs
3. Track as a known gap in `docs/guide/knowledge-system.md`

Recommended: option 1 + CI exclusion pattern. Don't rewrite 328 links manually.

### 3c. Placeholder/template links — 13 occurrences (MEDIUM)

Template stubs were never filled in. These are real breakage in reference docs:

| File | Broken target |
|------|--------------|
| `docs/reference/rules.md` | `relative-path.md` (×2) |
| `docs/architecture/system-documentation-map.md` | `relative-path.md` |
| `docs/reflections/31-assurance.md` | `./NN-filename.md` |
| `docs/architecture/hooks.md` | `${FILENAME}`, `topic_rust-cargo-patterns.md` |
| `docs/guide/knowledge-system.md` | `path.md` |
| `docs/guide/workflows/spec-graph.md` | `path` |
| `docs/ideas/skill-semantic-validation.md` | `relative/path.md` |

**Fix:** Replace each with actual target, or remove the link if the target doesn't exist yet.

### 3d. Reflections links to moved files — 7 occurrences (MEDIUM)

Six files link to reflection docs that moved or were archived:

| Source | Broken target | Status |
|--------|--------------|--------|
| `docs/24-roadmap-corrections.md` | `../archive/reflections/14-mastermind-architecture.md` | Archived version → file exists; path wrong |
| `docs/architecture/features/context-budget-real-limits.md` | `../reflections/08-diagnosis.md` | File exists at `docs/reflections/08-diagnosis.md` |
| `docs/architecture/features/scheduler.md` | `../reflections/32-lifecycle.md` | Exists at `docs/reflections/32-lifecycle.md` |
| `docs/architecture/decisions/ADR-006.md` | `../reflections/14-mastermind-architecture.md` | Exists |
| `docs/architecture/decisions/ADR-009.md` | `../reflections/14-mastermind-architecture.md` | Exists |
| `docs/reflections/32-lifecycle.md` | `../decisions/ADR-071-scheduler-thin-layer-over-systemd.md` | Exists |
| `docs/reflections/14-mastermind-architecture.md` | `../decisions/ADR-011-skills-bundling.md` etc. | Wrong `../docs/` prefix |

**Fix:** These are path-depth errors; the target files exist. Correct the relative paths. Should be a 15-minute fix.

### 3e. Deleted file references (MEDIUM)

`docs/README.md` (lines 87 and 226) and `docs/architecture/hooks.md` link to:
- `architecture/posttooluse-workaround.md` — deleted, not in git history after 2026-07-27
- `ideas/ruflo-native-integration.md` — deleted

**Fix:** Remove or replace these two entries in README.md and hooks.md.

### 3f. Old machine-path links in ideas docs (LOW)

Two ideas docs (`ideas/memory-consolidation-kairos.md`, `ideas/inbox-to-dimensions-pipeline.md`) contain hardcoded paths:
```
~/.claude/projects/-home-martineserios-enter-thebrana-thebrana/memory/...
```
These are dead on any machine other than the original dev box.

**Fix:** Replace with portable relative paths or remove.

---

## 4. Spec-graph orphans (139 nodes)

| Type | Orphan count | Expected? |
|------|-------------|-----------|
| Dimension | ~83 | Yes — cross-repo; brana-knowledge dims have no edges to docs |
| ADR | 12 | Partial — new ADRs 034–045 not yet referenced by any Reflection or Roadmap |
| Roadmap/other | ~44 | Some expected (roadmap leaves), some worth checking |

**ADR orphans to triage (not connected to any other node):**
ADR-034, ADR-035, ADR-040, ADR-041, ADR-043, ADR-044, ADR-045, and several newer ones. These decisions exist but haven't been referenced in any reflection or roadmap doc. Either they need to inform a reflection, or they're superseded and should be marked `status: Superseded`.

**Action:** Run `/brana:reconcile --scope propagation` — it will surface which orphan ADRs need wiring.

---

## 5. Memory stores

No `.claude/memory/` directory found in this repo (expected — per ADR-037, project memory lives in `~/.claude/projects/*/memory/` on the live machine, not in the repo). Memory-curator agent is properly defined at `system/agents/memory-curator.md`.

No MEMORY.md files found to audit in this clone. Memory health requires a live-machine run.

---

## 6. Priority action list

| Priority | Item | Effort |
|----------|------|--------|
| **P1** | Add CI link-check exclusion for `dimensions/` pattern (cross-repo links) | XS |
| **P1** | Fix 7 reflections broken-path links (target files exist, paths wrong) | XS |
| **P2** | Remove/replace 2 deleted-file links in README.md and hooks.md | XS |
| **P2** | Fill or remove 13 placeholder links in reference/hooks/ideas docs | S |
| **P3** | Triage 12 ADR orphans — wire to a reflection or mark Superseded | M |
| **P3** | Fix or remove old machine-path hardcodes in 2 ideas docs | XS |
| **P4** | Decide on archive/link-checker suppression strategy for docs/archive/ | M |

---

## 7. Health summary

| Dimension | Status | Trend |
|-----------|--------|-------|
| Staleness | ✅ Clean | Healthy — bulk activity this week |
| Broken links (non-archive) | ⚠️ 419 broken | Structural (cross-repo) + fixable set |
| Spec-graph coverage | ⚠️ 139 orphans | Growing corpus; wiring lag expected |
| Memory | — | Requires live-machine audit |
| Placeholder debt | ⚠️ 13 stubs | New, fixable |

Overall: the doc corpus is healthy and actively maintained. The broken-link count sounds alarming but ~80% is a single structural pattern (cross-repo dimension refs) that a CI exclusion and one comment-header per file can resolve cleanly. The remaining fixable set is ~85 links across ~15 files — a focused 2-hour cleanup.
