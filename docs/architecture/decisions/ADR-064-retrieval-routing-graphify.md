# ADR-064: Retrieval Routing — Structural Repo Queries via graphify

- **Status:** Accepted
- **Date:** 2026-07-19
- **Evidence:** pilot t-2271 (graphify 0.8.37 on anita-api)
- **Related:** ADR-058 (hybrid recall), delegation-routing.md, context-budget.md

## Context

Repo information is currently retrieved through three surfaces, each with a
distinct sweet spot and cost profile:

| Surface | Sweet spot | Cost |
|---------|-----------|------|
| Grep/Glob/Read | exact strings, known locations | ~free |
| Explore agents | open-ended "how does X work" | 5–15K tokens hidden per question |
| `brana recall` (FTS5 + ruflo, ADR-058) | decisions, learnings, cross-session knowledge | cheap, but never parses code |

None of these answers **structural** questions well: "what calls X", "what
breaks if I change Y", "how do A and B connect". Grep gives depth-1 importers
only; Explore burns thousands of tokens re-deriving structure the AST already
knows; recall doesn't index code at all.

[graphify](https://github.com/Graphify-Labs/graphify) builds a knowledge graph
from a repo via tree-sitter AST — deterministic, local, zero LLM tokens for
code — and answers structural queries against `graphify-out/graph.json`.

### Pilot evidence (t-2271, anita-api: 161 files → 1008 nodes / 1897 edges, ~10s build)

**Wins** — deterministic, file:line-anchored, all edges tagged EXTRACTED:

- `graphify explain <symbol>` — callers + callees + location in ~150–300 tokens
  (vs several grep rounds, or thousands of tokens for an Explore agent).
- `graphify affected <module>` — **transitive** impact at depth 2 (~200 tokens):
  every route, lib, and test reached. Grep cannot do this without manual iteration.
- `graphify path A B` — connection tracing between any two nodes.

**Losses** — `graphify query "<plain language>"` is keyword-seeded BFS, not
semantic search: on the pilot it seeded onto test-helper functions and returned
test-file noise. Explore agents remain strictly better for open-ended questions.

## Decision

**Route retrieval by query shape**, adding graphify as a fourth surface scoped
to structural queries only:

1. Exact string / known location → Grep/Glob.
2. Structural (calls/impact/connection/symbol neighborhood) → graphify
   `explain` / `affected` / `path`, when a graph exists.
3. Open-ended exploration → Explore agent (graphify community report may seed
   entry points).
4. Decisions, learnings, cross-session knowledge → `brana recall`.
5. Single known file → Read.

**Implementation is rule-layer first**: `system/rules/retrieval-routing.md`
makes Claude the interpreter — zero code, same pattern as
`delegation-routing.md`. A `brana recall` third retrieval arm (graphify behind
the ADR-058 RRF merge, fired on structural-keyword match when `graph.json`
exists) is **deferred** to a separate task until rule-layer usage proves the
routing table.

**Constraints** (from pilot + git/identity discipline):

- CLI only. Never `graphify install` (writes a skill into `~/.claude/` —
  violates the identity-layer rule) and never `graphify hook install`.
- Graph is a build artifact: `graphify-out/` stays untracked (gitignore it in
  repos that adopt it); `GRAPH_REPORT.md` records the built-from commit for
  staleness checks; rebuild is `graphify update .` (local, free).
- `graphify query` is not used for open-ended questions.

## Alternatives considered

- **graphify as full replacement for Explore/recall** — rejected: `query` is
  lexical BFS (pilot noise), and the graph is per-repo with no cross-session or
  cross-project memory. Its own LOCOMO QA accuracy trails supermemory.
- **CLI integration first (recall third arm)** — deferred, not rejected:
  building routing into `brana recall` before the table is validated by use
  inverts the audit-first discipline. Rule-layer costs nothing and headless
  runners can adopt the CLI arm later.
- **graphify strict-mode hook** (block first raw read, redirect to graph) —
  rejected for now: another hook in an already hook-heavy system, and it
  requires the skill install we're avoiding.

## Consequences

- Structural questions drop from thousands of tokens (Explore) or several tool
  rounds (grep) to one ~200-token CLI call — direct context-budget win.
- New moving part: graph staleness. Mitigated by the commit stamp in
  GRAPH_REPORT.md and free local rebuilds; not mitigated automatically (no
  hooks by decision).
- graphify (YC S26) is an external dependency; the routing rule degrades
  gracefully — no graph.json means falling back to the pre-existing surfaces.
- Follow-up candidates: `brana recall` third arm; `graphify-out/` gitignore
  convention for adopting repos.
