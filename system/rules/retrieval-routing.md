---
paths: ["src/**", "lib/**", "api/**", "app/**", "services/**", "system/**", "tests/**", "test/**"]
---
# Retrieval Routing

Pick the retrieval surface by query shape — walk top-to-bottom, first match wins. (ADR-064, pilot t-2271)

```
1. Exact string / known symbol location → Grep/Glob.
2. Structural — "what calls X", "what breaks if I change Y", "how do A and B
   connect", "explain this symbol" → graphify explain/affected/path,
   IF graphify-out/graph.json exists in the repo.
3. Open-ended — "how does X work", unfamiliar area → Explore agent
   (graphify GRAPH_REPORT.md communities can seed entry points first).
4. Past decisions, learnings, cross-session knowledge → brana recall.
5. Single known file → Read.
```

## graphify usage

- **No graph?** Fall back to grep/Explore. Build one (`graphify update .` — local,
  ~10s, 0 tokens) only when the repo will be queried repeatedly this session.
- **Staleness**: GRAPH_REPORT.md records the built-from commit. If HEAD moved,
  `graphify update .` before trusting `affected`.
- **Node names**: functions need the `()` suffix (`runPlannerForTenant()`);
  bare stems fuzzy-match (`planner` works where `planner.ts` may not).
- **Doc edges (thebrana)**: after `graphify update .`, run
  `python3 system/scripts/doc-graph-overlay.py .` — unions frontmatter
  (`produced_by:`/`supersedes:`) and textual ADR-NNN edges into graph.json
  (rebuild wipes the overlay; direct union, never `merge-graphs` — t-2274/t-2275).
- **Never** `graphify install` (writes into `~/.claude/`) or `graphify hook install`.
  CLI only. `graphify-out/` stays untracked — gitignore it in adopting repos.
- **Never** use `graphify query "<plain language>"` for open-ended questions —
  it is keyword-seeded BFS, not semantic search; it returns lexical-match noise
  (pilot t-2271). Route those to Explore instead.

```
Example:
  "what breaks if I change segmentResolver?"
    → graphify affected segmentResolver.ts        (~200 tokens, transitive)
  "how does campaign scheduling work end to end?"
    → Explore agent — NOT graphify query
  "did we already decide how recall merges providers?"
    → brana recall (ADR-058)
```
