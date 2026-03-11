# ADR-016: Spec Dependency Graph

**Date:** 2026-03-11
**Status:** accepted
**Related:** ADR-001 (reconcile command), ADR-006 (merge enter into thebrana), t-347

## Context

Brana has ~150 spec documents across docs/, docs/reflections/, docs/dimensions/ (symlinked), docs/architecture/, docs/guide/, and docs/research/. Three skills need to know "what else is affected?" when a doc changes:

- `/brana:reconcile` (SKILL.md) had **hardcoded doc number lists** like `(01-07, 09-13, 16, 20-23, 26-28, 33-38)`. New docs were invisible until someone manually added their number.
- `/brana:build PLAN` had **zero impact analysis**. Work started without knowing which docs describe the files about to change.
- `/brana:maintain-specs` **scanned all 5 reflections every run** regardless of which doc actually changed.

## Decision

A pure Python script (`system/scripts/spec_graph.py`) parses all markdown docs, extracts cross-reference links and system file mentions, and outputs a JSON dependency graph to `docs/spec-graph.json`.

### Graph structure

Each document becomes a node with three relationship types:
- **references** — docs this doc links to (outbound edges from `[text](path)` links)
- **referenced_by** — docs that link to this doc (computed in reverse pass)
- **impl_files** — system/ files mentioned in the doc

### Algorithm

1. Walk `docs/` with `rglob("*.md")` for thebrana docs
2. Walk `docs/dimensions/` explicitly (Python 3.13's rglob doesn't follow symlinks)
3. For each file: extract links outside code fences, resolve paths, collect system/ references
4. Forward pass builds references + impl_files; reverse pass computes referenced_by

### Consumer changes

- **Reconcile:** finds nodes whose `impl_files` match the system/ area being checked, scans only those docs
- **Build PLAN:** displays a blast radius table before task breakdown
- **Maintain-specs:** only re-evaluates 1-hop `referenced_by` neighbors of the changed doc

All consumers fall back to current behavior if `docs/spec-graph.json` doesn't exist.

### Staleness

Session-start hook checks `_meta.generated` once per session. If older than 7 days, warns the user.

## Alternatives considered

### KuzuDB graph database
Embedded property graph with Cypher queries. Rejected: ~150 nodes is trivially fast with JSON adjacency lists. The dependency (embedded C++ binary) adds complexity for no benefit at this scale. Deferred to Phase 5 when node count exceeds ~500.

### Shell wrapper scripts
Generate the graph via bash + jq. Rejected: regex-heavy markdown parsing in bash is brittle and unmaintainable. Python's pathlib and re modules handle this cleanly.

### Query CLI for consumers
A `spec_graph.py query --impl-files system/skills/build` subcommand. Rejected: Claude reads JSON directly and reasons about it. A query CLI adds a tool boundary without adding capability. The JSON format is already machine-readable.

## Consequences

- Reconcile no longer needs hardcoded doc number lists — new docs are automatically included
- Build PLAN shows blast radius before implementation starts
- Maintain-specs can skip unaffected reflections
- Graph must be regenerated when links change (not on content-only edits)
- Consumer SKILL.md instructions will need rewriting if/when migrating to KuzuDB (Phase 5 cost)
