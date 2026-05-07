# Auto-learning Loop Validation — t-938

> Date: 2026-05-07. Validated against brainstorm procedure (procedures/brainstorm.md).

## Summary

The four loop steps (LOAD→EXTRACT→EVALUATE→PERSIST) are structurally sound. EXTRACT and EVALUATE are pure LLM reasoning — no tool failures possible. LOAD and PERSIST both reach ruflo successfully. One critical bug found in LOAD's namespace strategy.

---

## LOAD — BROKEN (namespace bug)

**What the procedure says:** `mcp__ruflo__memory_search(namespace: "all", limit: 5, threshold: 0.4)`

**What actually happens:** `namespace: "all"` returns only `session` namespace records. It does **not** aggregate across `knowledge`, `pattern`, or `specs`.

Tested query: `"thebrana brainstorm knowledge pipeline auto-learning loop LOAD EXTRACT EVALUATE PERSIST"`
- `namespace: "all"` → 5 results, all from `session` namespace, scores 0.47–0.52
- `namespace: "specs"` → 0 results (namespace is empty — nothing indexed)
- `namespace: "knowledge"` → 5 relevant dimension doc chunks, scores 0.43–0.50 ✓
- `namespace: "pattern"` → 5 feedback patterns, scores 0.39–0.47 ✓

**Impact:** LOAD never surfaces dimension docs or patterns when using the `all` shortcut. Claude only sees old session summaries — stale, low-signal context.

**Fix needed:** Replace the single `namespace: "all"` call with three parallel calls:
```
mcp__ruflo__memory_search(query, namespace: "knowledge", limit: 3, threshold: 0.4)
mcp__ruflo__memory_search(query, namespace: "pattern",   limit: 3, threshold: 0.4)
mcp__ruflo__memory_search(query, namespace: "specs",     limit: 2, threshold: 0.4)
```

**Secondary finding:** `specs` namespace is empty. Knowledge indexing has never populated it. May be a dead namespace or an unrun indexing step.

---

## EXTRACT — WORKS (no tool calls)

Pure LLM reasoning step: review brainstorm output, classify findings as Pattern/ADR/Dimension/FieldNote. No tool dependencies. Ontology is clear. No failure modes beyond LLM quality.

---

## EVALUATE — WORKS (no tool calls)

Scoring rubric (Scope × Novelty → 0–10) is well-defined. SMALL/MEDIUM/LARGE gates are clear. The inline dedup check (`mcp__ruflo__memory_search` for MEDIUM findings) would hit the same namespace bug if querying `"all"` — but since it queries a specific finding summary, querying `namespace: "pattern"` directly would work.

---

## PERSIST — WORKS

`mcp__ruflo__memory_store` tested successfully:
- Stores with embedding in ~140ms
- `upsert: true` works
- Entry is immediately searchable after store (confirmed via follow-up search)
- Deletion works (`mcp__ruflo__memory_delete`, HNSW index invalidated correctly)

Tag structure `["client:thebrana", "source:brainstorm"]` follows existing conventions.

---

## Other findings

**Procedure location drift:** Task context said "4 SKILL.md files" but the loop now lives in `system/procedures/` (ADR-034 migration). The `.full` backup files in `system/skills/brainstorm/` and `system/skills/research/` are stale and should be deleted.

**Search latency:** `namespace: "all"` takes 376ms; per-namespace queries take 44–150ms each. Three parallel namespace queries would be ~150ms total — faster than the broken `all` query.

---

## Action items

| # | Fix | Effort | Priority |
|---|-----|--------|----------|
| 1 | Fix LOAD in brainstorm.md, research.md, build.md, review.md — replace `namespace: "all"` with 3 parallel namespace queries | S | P1 |
| 2 | Investigate `specs` namespace — is it intentionally empty or unrun indexing? | S | P2 |
| 3 | Delete stale `.full` files from system/skills/brainstorm/ and system/skills/research/ | XS | P3 |
