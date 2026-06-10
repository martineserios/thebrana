<!-- reconcile phase: Propagation scope: errata cascade, fitness check, spec-graph consistency — loaded per the PHASES registry in ../SKILL.md (t-1942) -->

## Propagation Domain (`--scope propagation`)

Cascade pending errata through the spec layer hierarchy. Invokes existing commands as building blocks.

### PROP-1: Fitness check

Run `/brana:verify-docs` to check for doc drift, structural errors, and staleness. Surface any findings as candidates for manual correction.

### PROP-2: Spec-graph consistency

If `docs/spec-graph.json` exists:
1. Run `brana graph build` to regenerate
2. Compare output with existing graph
3. Flag new orphan nodes, broken edges, missing docs

### PROP-REPORT

Summary: errata applied, reflections updated, graph changes. Commit all propagation changes as one logical group.

---

