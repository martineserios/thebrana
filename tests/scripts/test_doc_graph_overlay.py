"""Tests for doc-graph-overlay.py — frontmatter + textual-ADR edges unioned into graphify graph.json.

Spike evidence: t-2274. graphify's free pass (>=0.8.43) already ingests md links and
wikilinks; this overlay adds only what it misses — frontmatter keys and textual ADR refs.
"""

import importlib.util
import json
import sys
from pathlib import Path
from unittest.mock import patch

SCRIPT = Path(__file__).parents[2] / "system" / "scripts" / "doc-graph-overlay.py"

spec = importlib.util.spec_from_file_location("doc_graph_overlay", SCRIPT)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)


def _corpus(tmp_path: Path) -> Path:
    """Minimal doc corpus mirroring thebrana layout."""
    adr_dir = tmp_path / "docs" / "architecture" / "decisions"
    adr_dir.mkdir(parents=True)
    (adr_dir / "ADR-059-multi-agent-substrate-selection.md").write_text(
        "# ADR-059\n\nDecision text. See ADR-059 heading self-ref.\n"
    )
    (adr_dir / "ADR-040-compute-hierarchy.md").write_text(
        "---\nstatus: accepted\nproduced_by: docs/ideas/compute-model.md\n---\n# ADR-040\n"
    )
    ideas = tmp_path / "docs" / "ideas"
    ideas.mkdir(parents=True)
    (ideas / "compute-model.md").write_text("# Compute model\n")

    rules = tmp_path / "system" / "rules"
    rules.mkdir(parents=True)
    (rules / "delegation-routing.md").write_text(
        "---\nalways-load: true\n"
        "produced_by: docs/architecture/decisions/ADR-059-multi-agent-substrate-selection.md\n"
        "---\n# Delegation Routing\n"
    )
    # bracket-list frontmatter, "-" sentinel, nonexistent target
    (rules / "misc.md").write_text(
        "---\nproduced_by: [docs/ideas/compute-model.md, docs/ideas/gone.md]\nsupersedes: -\n---\n# Misc\n"
    )
    # textual ADR ref, no md link
    refl = tmp_path / "docs" / "reflections"
    refl.mkdir(parents=True)
    (refl / "notes.md").write_text("# Notes\n\nPer ADR-059 the substrate is native CC.\n")
    return tmp_path


def _base_graph(tmp_path: Path) -> Path:
    """Graphify-shaped base graph containing one existing doc node and one existing edge."""
    out = tmp_path / "graphify-out"
    out.mkdir()
    graph = {
        "directed": True,
        "multigraph": False,
        "graph": {},
        "nodes": [
            {
                "id": "docs_architecture_decisions_adr_059_multi_agent_substrate_selection",
                "label": "ADR-059-multi-agent-substrate-selection.md",
                "file_type": "document",
                "source_file": "docs/architecture/decisions/ADR-059-multi-agent-substrate-selection.md",
                "source_location": "L1",
                "_origin": "ast",
            },
            {
                "id": "docs_reflections_notes",
                "label": "notes.md",
                "file_type": "document",
                "source_file": "docs/reflections/notes.md",
                "source_location": "L1",
                "_origin": "ast",
            },
        ],
        "links": [
            # graphify already made this edge (e.g. from an md link) — overlay must not duplicate it
            {
                "relation": "references",
                "confidence": "EXTRACTED",
                "source": "docs_reflections_notes",
                "target": "docs_architecture_decisions_adr_059_multi_agent_substrate_selection",
                "_origin": "ast",
            }
        ],
        "hyperedges": [],
    }
    path = out / "graph.json"
    path.write_text(json.dumps(graph))
    return path


def test_node_id_recipe():
    assert (
        mod.node_id("docs/architecture/decisions/ADR-059-multi-agent-substrate-selection.md")
        == "docs_architecture_decisions_adr_059_multi_agent_substrate_selection"
    )
    assert mod.node_id("system/rules/delegation-routing.md") == "system_rules_delegation_routing"


def test_frontmatter_edges(tmp_path):
    root = _corpus(tmp_path)
    nodes, links = mod.extract_frontmatter_edges(root)
    pairs = {(l["source"], l["target"]) for l in links}
    assert (
        "system_rules_delegation_routing",
        "docs_architecture_decisions_adr_059_multi_agent_substrate_selection",
    ) in pairs
    # bracket list: existing member kept, nonexistent member skipped
    assert ("system_rules_misc", "docs_ideas_compute_model") in pairs
    assert not any(t.endswith("gone") for _, t in pairs)
    # "-" sentinel produces nothing
    assert all(l["frontmatter_key"] != "supersedes" for l in links)
    # traversable relation, provenance kept
    assert all(l["relation"] == "references" for l in links)
    assert all(l["_origin"] == "doc-overlay" for l in links)


def test_textual_adr_refs(tmp_path):
    root = _corpus(tmp_path)
    nodes, links = mod.extract_adr_ref_edges(root)
    pairs = {(l["source"], l["target"]) for l in links}
    assert (
        "docs_reflections_notes",
        "docs_architecture_decisions_adr_059_multi_agent_substrate_selection",
    ) in pairs
    # an ADR mentioning its own number is not a self-edge
    assert not any(s == t for s, t in pairs)


def test_union_dedupes_and_is_idempotent(tmp_path):
    root = _corpus(tmp_path)
    graph_path = _base_graph(tmp_path)
    base = json.loads(graph_path.read_text())
    n_nodes, n_links = len(base["nodes"]), len(base["links"])

    nodes, links = mod.collect(root)
    merged = mod.union(base, nodes, links)

    ids = [n["id"] for n in merged["nodes"]]
    assert len(ids) == len(set(ids)), "node ids must stay unique"
    # the textual notes->ADR-059 edge already existed in base — not re-added
    notes_edges = [
        l
        for l in merged["links"]
        if l["source"] == "docs_reflections_notes"
        and l["target"] == "docs_architecture_decisions_adr_059_multi_agent_substrate_selection"
    ]
    assert len(notes_edges) == 1
    assert len(merged["links"]) > n_links, "new frontmatter edges appended"

    # idempotent: second pass adds nothing
    again = mod.union(json.loads(json.dumps(merged)), nodes, links)
    assert len(again["links"]) == len(merged["links"])
    assert len(again["nodes"]) == len(merged["nodes"])


def test_main_in_place(tmp_path):
    root = _corpus(tmp_path)
    graph_path = _base_graph(tmp_path)
    with patch.object(
        sys, "argv", ["doc-graph-overlay.py", str(root), "--graph", str(graph_path)]
    ):
        mod.main()
    merged = json.loads(graph_path.read_text())
    assert any(l.get("_origin") == "doc-overlay" for l in merged["links"])
