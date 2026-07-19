#!/usr/bin/env python3
"""Union doc edges graphify's free pass misses into graphify-out/graph.json.

graphify >=0.8.43 already ingests inline/reference md links and [[wikilinks]]
(#1376). This overlay adds only the residual, still-deterministic edges:

  - frontmatter keys: produced_by:/supersedes: (single value or [a, b] list)
  - textual ADR-NNN references, resolved to docs/architecture/decisions/ADR-NNN-*.md

Edges are emitted as relation "references" (the only doc relation `graphify
affected`/`path` traverse) with provenance in `frontmatter_key`/`_origin`.
Fused by direct union — NOT `graphify merge-graphs`, which namespaces node ids
per input repo and duplicates same-corpus nodes (t-2274).

Idempotent: node ids are deduped, and an edge is skipped when the base graph
already has any edge with the same (source, target, relation). Re-run after
every `graphify update` — the rebuild wipes the overlay.

Usage: doc-graph-overlay.py [ROOT] [--graph graphify-out/graph.json] [--dry-run]
"""

import argparse
import json
import re
import sys
from pathlib import Path

FRONTMATTER_KEYS = ("produced_by", "supersedes")
DOC_GLOBS = ("docs/**/*.md", "system/**/*.md")
ADR_REF = re.compile(r"\bADR-(\d{3})\b")


def node_id(relpath: str) -> str:
    """graphify node-id recipe: relpath, strip .md, lowercase, non-alnum -> _."""
    stem = re.sub(r"\.md$", "", relpath)
    return re.sub(r"[^a-z0-9]+", "_", stem.lower()).strip("_")


def _doc_node(relpath: str) -> dict:
    return {
        "id": node_id(relpath),
        "label": Path(relpath).name,
        "file_type": "document",
        "source_file": relpath,
        "source_location": "L1",
        "_origin": "doc-overlay",
    }


def _link(src_rel: str, tgt_rel: str, **extra) -> dict:
    return {
        "relation": "references",
        "confidence": "EXTRACTED",
        "confidence_score": 1.0,
        "weight": 1.0,
        "source_file": src_rel,
        "source_location": "L1",
        "_origin": "doc-overlay",
        "source": node_id(src_rel),
        "target": node_id(tgt_rel),
        **extra,
    }


def _iter_docs(root: Path):
    for pattern in DOC_GLOBS:
        yield from sorted(root.glob(pattern))


def _frontmatter(text: str) -> str | None:
    if not text.startswith("---"):
        return None
    parts = text.split("---", 2)
    return parts[1] if len(parts) >= 3 else None


def _split_values(raw: str) -> list[str]:
    return [v.strip().strip("[]").strip() for v in raw.strip().strip("[]").split(",")]


def extract_frontmatter_edges(root: Path) -> tuple[list[dict], list[dict]]:
    nodes, links, seen = {}, [], set()
    for md in _iter_docs(root):
        fm = _frontmatter(md.read_text(errors="ignore"))
        if fm is None:
            continue
        src_rel = str(md.relative_to(root))
        for key in FRONTMATTER_KEYS:
            m = re.search(rf"^{key}:\s*(.+)$", fm, re.M)
            if not m:
                continue
            for value in _split_values(m.group(1)):
                if not value or value == "-":
                    continue
                if not (root / value).is_file():
                    continue
                tgt_rel = value
                pair = (node_id(src_rel), node_id(tgt_rel))
                if pair[0] == pair[1] or pair in seen:
                    continue
                seen.add(pair)
                nodes[pair[0]] = _doc_node(src_rel)
                nodes[pair[1]] = _doc_node(tgt_rel)
                links.append(_link(src_rel, tgt_rel, frontmatter_key=key))
    return list(nodes.values()), links


def extract_adr_ref_edges(root: Path) -> tuple[list[dict], list[dict]]:
    adr_dir = root / "docs" / "architecture" / "decisions"
    adr_files = {}
    for adr in adr_dir.glob("ADR-*.md") if adr_dir.is_dir() else []:
        m = ADR_REF.match(adr.name)
        if m:
            adr_files[m.group(1)] = str(adr.relative_to(root))

    nodes, links, seen = {}, [], set()
    for md in _iter_docs(root):
        src_rel = str(md.relative_to(root))
        for num in set(ADR_REF.findall(md.read_text(errors="ignore"))):
            tgt_rel = adr_files.get(num)
            if tgt_rel is None or tgt_rel == src_rel:
                continue
            pair = (node_id(src_rel), node_id(tgt_rel))
            if pair in seen:
                continue
            seen.add(pair)
            nodes[pair[0]] = _doc_node(src_rel)
            nodes[pair[1]] = _doc_node(tgt_rel)
            links.append(_link(src_rel, tgt_rel, textual_ref=f"ADR-{num}"))
    return list(nodes.values()), links


def collect(root: Path) -> tuple[list[dict], list[dict]]:
    fm_nodes, fm_links = extract_frontmatter_edges(root)
    adr_nodes, adr_links = extract_adr_ref_edges(root)
    nodes = {n["id"]: n for n in fm_nodes + adr_nodes}
    return list(nodes.values()), fm_links + adr_links


def union(base: dict, nodes: list[dict], links: list[dict]) -> dict:
    have_nodes = {n["id"] for n in base["nodes"]}
    have_edges = {(l["source"], l["target"], l.get("relation")) for l in base["links"]}
    base["nodes"] += [n for n in nodes if n["id"] not in have_nodes]
    base["links"] += [
        l for l in links if (l["source"], l["target"], l["relation"]) not in have_edges
    ]
    return base


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("root", nargs="?", default=".", help="repo root (default: .)")
    ap.add_argument("--graph", default="graphify-out/graph.json", help="graph.json to union into")
    ap.add_argument("--dry-run", action="store_true", help="report counts, write nothing")
    args = ap.parse_args()

    root = Path(args.root).resolve()
    graph_path = Path(args.graph)
    base = json.loads(graph_path.read_text())
    n_nodes, n_links = len(base["nodes"]), len(base["links"])

    nodes, links = collect(root)
    merged = union(base, nodes, links)
    added_nodes = len(merged["nodes"]) - n_nodes
    added_links = len(merged["links"]) - n_links

    if args.dry_run:
        print(f"dry-run: would add {added_nodes} nodes, {added_links} edges", file=sys.stderr)
        return
    graph_path.write_text(json.dumps(merged))
    print(f"doc-graph-overlay: +{added_nodes} nodes, +{added_links} edges -> {graph_path}",
          file=sys.stderr)


if __name__ == "__main__":
    main()
