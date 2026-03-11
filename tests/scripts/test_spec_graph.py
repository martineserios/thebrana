#!/usr/bin/env python3
"""Tests for system/scripts/spec_graph.py"""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path

import pytest

# Make the script importable
REPO_ROOT = Path(__file__).resolve().parent.parent.parent
sys.path.insert(0, str(REPO_ROOT / "system" / "scripts"))

import spec_graph


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

@pytest.fixture
def repo(tmp_path: Path) -> Path:
    """Create a minimal repo structure under tmp_path."""
    (tmp_path / ".git").mkdir()
    (tmp_path / "docs").mkdir()
    (tmp_path / "system" / "skills").mkdir(parents=True)
    return tmp_path


def _write(repo: Path, relpath: str, content: str) -> Path:
    p = repo / relpath
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(content)
    return p


# ---------------------------------------------------------------------------
# 1. Code fence skipping
# ---------------------------------------------------------------------------

def test_code_fence_skipping(repo: Path) -> None:
    content = """\
Some text [real](docs/real.md)

```
[inside fence](docs/fenced.md)
```

After fence [also real](docs/also-real.md)
"""
    refs, impls = spec_graph.extract_links(
        content, Path("docs/source.md"), repo
    )
    assert "docs/real.md" in refs
    assert "docs/also-real.md" in refs
    assert "docs/fenced.md" not in refs


# ---------------------------------------------------------------------------
# 2. Language specifier fences
# ---------------------------------------------------------------------------

def test_language_specifier_fences(repo: Path) -> None:
    content = """\
Before [real](docs/a.md)

```json
[inside](docs/nope.md)
```

```python
[also inside](docs/nope2.md)
```

After [real2](docs/b.md)
"""
    refs, _ = spec_graph.extract_links(
        content, Path("docs/source.md"), repo
    )
    assert "docs/a.md" in refs
    assert "docs/b.md" in refs
    assert "docs/nope.md" not in refs
    assert "docs/nope2.md" not in refs


# ---------------------------------------------------------------------------
# 3. Tilde path expansion
# ---------------------------------------------------------------------------

def test_tilde_path_expansion(repo: Path) -> None:
    # Create a dimensions dir to act as symlink target
    home = Path.home()
    # We test the _resolve_path function directly
    # Simulate: ~/enter_thebrana/brana-knowledge/dimensions/22-testing.md
    # with dimensions_real pointing to the actual brana-knowledge/dimensions
    bk_dim = home / "enter_thebrana" / "brana-knowledge" / "dimensions"

    resolved = spec_graph._resolve_path(
        "~/enter_thebrana/brana-knowledge/dimensions/22-testing.md",
        Path("docs/source.md"),
        repo,
        dimensions_real=bk_dim,
    )
    assert resolved == "docs/dimensions/22-testing.md"


# ---------------------------------------------------------------------------
# 4. URL skipping
# ---------------------------------------------------------------------------

def test_url_skipping(repo: Path) -> None:
    content = """\
[google](https://google.com) and [http](http://example.com)
[local](docs/local.md)
"""
    refs, _ = spec_graph.extract_links(content, Path("docs/s.md"), repo)
    assert refs == ["docs/local.md"]


# ---------------------------------------------------------------------------
# 5. Anchor skipping
# ---------------------------------------------------------------------------

def test_anchor_skipping(repo: Path) -> None:
    content = """\
[heading](#some-heading)
[with anchor](docs/target.md#section)
[bare anchor](#)
"""
    refs, _ = spec_graph.extract_links(content, Path("docs/s.md"), repo)
    # Only the one with a path component should be kept (anchor stripped)
    assert refs == ["docs/target.md"]


# ---------------------------------------------------------------------------
# 6. Glob pattern skipping
# ---------------------------------------------------------------------------

def test_glob_pattern_skipping(repo: Path) -> None:
    content = """\
[all skills](system/skills/*)
[braces](system/hooks/{pre,post}*.sh)
[exact](system/skills/build/SKILL.md)
"""
    refs, impls = spec_graph.extract_links(content, Path("docs/s.md"), repo)
    assert "system/skills/build/SKILL.md" in impls
    assert not any("*" in i for i in impls)
    assert not any("{" in i for i in impls)


# ---------------------------------------------------------------------------
# 7. Relative path resolution
# ---------------------------------------------------------------------------

def test_relative_path_resolution(repo: Path) -> None:
    # Source is docs/reflections/14-arch.md, link is ../18-lean-roadmap.md
    resolved = spec_graph._resolve_path(
        "../18-lean-roadmap.md",
        Path("docs/reflections/14-arch.md"),
        repo,
        dimensions_real=None,
    )
    assert resolved == "docs/18-lean-roadmap.md"

    # Deeper relative
    resolved2 = spec_graph._resolve_path(
        "../../system/skills/build/SKILL.md",
        Path("docs/reflections/14-arch.md"),
        repo,
        dimensions_real=None,
    )
    assert resolved2 == "system/skills/build/SKILL.md"


# ---------------------------------------------------------------------------
# 8. Reverse pass (referenced_by)
# ---------------------------------------------------------------------------

def test_reverse_pass(repo: Path) -> None:
    _write(repo, "docs/a.md", "[link to b](docs/b.md)\n")
    _write(repo, "docs/b.md", "No links here.\n")

    graph = spec_graph.build_graph(repo, docs_dir=repo / "docs")
    nodes = graph["nodes"]

    assert "docs/b.md" in nodes["docs/a.md"]["references"]
    assert "docs/a.md" in nodes["docs/b.md"]["referenced_by"]


# ---------------------------------------------------------------------------
# 9. Meta section
# ---------------------------------------------------------------------------

def test_meta_section(repo: Path) -> None:
    _write(repo, "docs/a.md", "[b](docs/b.md)\n")
    _write(repo, "docs/b.md", "orphan text\n")
    _write(repo, "docs/c.md", "also orphan\n")

    graph = spec_graph.build_graph(repo, docs_dir=repo / "docs")
    meta = graph["_meta"]

    assert "generated" in meta
    assert meta["node_count"] == 3
    assert meta["edge_count"] == 1  # a -> b
    assert isinstance(meta["impl_ref_count"], int)
    assert isinstance(meta["orphan_count"], int)
    # c has no refs and no referenced_by -> orphan
    assert meta["orphan_count"] >= 1


# ---------------------------------------------------------------------------
# 10. Symlink explicit walk
# ---------------------------------------------------------------------------

def test_symlink_explicit_walk(repo: Path) -> None:
    # Create a real dir outside docs/ and symlink it as docs/dimensions
    real_dims = repo / "external_dimensions"
    real_dims.mkdir()
    (real_dims / "01-topic.md").write_text("dimension content\n")

    dim_link = repo / "docs" / "dimensions"
    dim_link.symlink_to(real_dims)

    file_map = spec_graph.collect_markdown_files(repo / "docs", repo)
    assert "docs/dimensions/01-topic.md" in file_map


# ---------------------------------------------------------------------------
# 11. Duplicate dedup
# ---------------------------------------------------------------------------

def test_duplicate_dedup(repo: Path) -> None:
    # Create a real dir and symlink so the same file could be found twice
    real_dims = repo / "external_dimensions"
    real_dims.mkdir()
    (real_dims / "dup.md").write_text("[a](docs/a.md)\n")

    dim_link = repo / "docs" / "dimensions"
    dim_link.symlink_to(real_dims)

    # Also put a regular file so rglob finds it
    _write(repo, "docs/regular.md", "hello\n")

    files = spec_graph.collect_markdown_files(repo / "docs", repo)
    # Build the graph — should not have duplicate keys
    graph = spec_graph.build_graph(repo, docs_dir=repo / "docs")
    keys = list(graph["nodes"].keys())

    # No duplicate paths
    assert len(keys) == len(set(keys))
    # dimensions/dup.md appears exactly once
    dim_keys = [k for k in keys if "dup.md" in k]
    assert len(dim_keys) == 1


# ---------------------------------------------------------------------------
# Integration: end-to-end generate via CLI
# ---------------------------------------------------------------------------

def test_generate_cli(repo: Path) -> None:
    _write(repo, "docs/a.md", "[b](docs/b.md)\n[skill](system/skills/x.md)\n")
    _write(repo, "docs/b.md", "standalone\n")

    out = repo / "output.json"
    # Monkeypatch repo root detection
    original = spec_graph.find_repo_root
    spec_graph.find_repo_root = lambda start=None: repo
    try:
        spec_graph.main(["generate", "--output", str(out)])
    finally:
        spec_graph.find_repo_root = original

    assert out.exists()
    data = json.loads(out.read_text())
    assert "_meta" in data
    assert "nodes" in data
    assert data["_meta"]["node_count"] == 2
    assert "system/skills/x.md" in data["nodes"]["docs/a.md"]["impl_files"]
