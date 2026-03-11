# Spec Dependency Graph

The spec graph maps relationships between brana's ~150 documentation files and the system/ implementation files they describe.

## What it does

- Tracks which docs link to which other docs (references/referenced_by)
- Tracks which docs describe which system/ files (impl_files)
- Enables targeted scanning instead of exhaustive full-doc sweeps

## When to regenerate

| Event | Regenerate? |
|-------|:-----------:|
| Added/removed a `[text](path)` link | **Yes** |
| Created or deleted a doc | **Yes** |
| After `/brana:maintain-specs` | **Yes** |
| Edited content within a doc | No |
| Content/typo fix | No |

```bash
uv run python3 system/scripts/spec_graph.py generate
```

Output: `docs/spec-graph.json`

## How skills use it

**`/brana:reconcile`** — reads `impl_files` to find which docs describe the system/ area being checked. Only scans those docs instead of all ~150.

**`/brana:build PLAN`** — identifies system/ files the feature will modify, then shows a blast radius table of all docs that reference those files.

**`/brana:maintain-specs`** — when a doc changes, reads its `referenced_by` list and only re-evaluates those 1-hop neighbors instead of all 5 reflections.

All three fall back to full scanning if the graph doesn't exist.

## Staleness

The session-start hook checks `_meta.generated` once per session. If older than 7 days or missing, it warns:

> Spec graph is stale (generated: DATE, Nd ago). Run: uv run python3 system/scripts/spec_graph.py generate

## JSON schema

```json
{
  "_meta": {
    "generated": "2026-03-11T18:36:38Z",
    "node_count": 153,
    "edge_count": 405,
    "impl_ref_count": 181,
    "orphan_count": 19
  },
  "nodes": {
    "docs/reflections/14-mastermind-architecture.md": {
      "references": ["docs/dimensions/05-...md"],
      "referenced_by": ["docs/17-implementation-roadmap.md"],
      "impl_files": ["system/skills/build/SKILL.md"]
    }
  }
}
```

## Querying

```bash
# Graph stats
jq '._meta' docs/spec-graph.json

# All dimension docs in the graph
jq '.nodes | keys[] | select(contains("dimensions"))' docs/spec-graph.json

# What docs reference a specific file
jq '.nodes | to_entries[] | select(.value.impl_files | index("system/skills/build/SKILL.md")) | .key' docs/spec-graph.json

# Orphan docs (no references, no referenced_by)
jq '[.nodes | to_entries[] | select((.value.references | length) == 0 and (.value.referenced_by | length) == 0) | .key]' docs/spec-graph.json
```

## Troubleshooting

**Missing dimension docs** — `docs/dimensions` is a symlink to `../../brana-knowledge/dimensions`. The script walks this path explicitly because Python's `rglob` doesn't follow symlinks. If dimension docs are missing from the graph, verify the symlink: `ls -la docs/dimensions`.

**Stale graph after maintain-specs** — regenerate after any run that may have added or removed links.

**High orphan count** — orphan docs have no incoming or outgoing references. This is normal for standalone research docs. Review orphans periodically to see if they should link to other docs.
