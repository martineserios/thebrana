#!/usr/bin/env python3
"""spec_graph.py — Parse markdown docs and emit a JSON dependency graph.

Pure Python (stdlib only). Walks docs/, resolves cross-references and
system/ file mentions, outputs docs/spec-graph.json.

Usage:
    uv run python3 system/scripts/spec_graph.py generate [--output PATH]
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

# ---------------------------------------------------------------------------
# Repo root detection
# ---------------------------------------------------------------------------

def find_repo_root(start: Path | None = None) -> Path:
    """Return the repo root via git or by walking up to find .git/."""
    if start is None:
        start = Path(__file__).resolve().parent
    # Try git first
    try:
        result = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            capture_output=True, text=True, check=True, cwd=str(start),
        )
        return Path(result.stdout.strip())
    except (subprocess.CalledProcessError, FileNotFoundError):
        pass
    # Walk up
    cur = start
    while cur != cur.parent:
        if (cur / ".git").exists():
            return cur
        cur = cur.parent
    raise RuntimeError("Cannot determine repo root")


# ---------------------------------------------------------------------------
# Markdown link extraction
# ---------------------------------------------------------------------------

_LINK_RE = re.compile(r"\[([^\]]*)\]\(([^)]+)\)")
_FENCE_RE = re.compile(r"^(\s*)(```|~~~)")
_SYSTEM_PATH_RE = re.compile(r"system/[^\s,)}\]\"']+")

# Typed link pattern: [Label type](path.md) where type is one of the ontology relationship types
# Examples: [ADR-019 assumes](path.md), [/brana:build implements](docs/architecture/decisions/ADR-006.md)
_RELATIONSHIP_TYPES = frozenset({"assumes", "implements", "informs", "enriches", "supersedes"})
_TYPED_LINK_RE = re.compile(
    r"\[([^\]]+)\s+(assumes|implements|informs|enriches|supersedes)\]\(([^)]+)\)"
)
_INLINE_CODE_RE = re.compile(r"`[^`]+`")


def _is_fence_open(line: str, in_fence: bool, fence_marker: str | None) -> tuple[bool, str | None]:
    """Track fenced-code-block state.  Returns (in_fence, fence_marker)."""
    m = _FENCE_RE.match(line)
    if m is None:
        return in_fence, fence_marker
    marker = m.group(2)  # ``` or ~~~
    if not in_fence:
        return True, marker
    # Close only if same marker
    if marker == fence_marker:
        return False, None
    return in_fence, fence_marker


def extract_links(
    content: str,
    source_path: Path,
    repo_root: Path,
    dimensions_real: Path | None = None,
) -> tuple[list[str], list[str]]:
    """Return (references, impl_files) extracted from *content*.

    *source_path* is the repo-root-relative path of the file being parsed.
    *dimensions_real* is the resolved real path of the dimensions symlink target
    (used to map ~/enter_thebrana/brana-knowledge/dimensions/... back to
    docs/dimensions/...).
    """
    references: list[str] = []
    impl_files: list[str] = []

    in_fence = False
    fence_marker: str | None = None

    for line in content.splitlines():
        in_fence, fence_marker = _is_fence_open(line, in_fence, fence_marker)
        if in_fence:
            continue

        # Markdown links  [text](path)
        for _text, raw_target in _LINK_RE.findall(line):
            target = raw_target.strip()

            # Skip URLs
            if target.startswith(("http://", "https://")):
                continue

            # Skip bare anchors
            if target.startswith("#"):
                continue

            # Strip anchors from path
            target = target.split("#")[0]
            if not target:
                continue

            resolved = _resolve_path(target, source_path, repo_root, dimensions_real)
            if resolved is None:
                continue

            # Classify
            if "system/" in resolved:
                if not _has_glob(resolved):
                    impl_files.append(resolved)
            else:
                references.append(resolved)

        # Inline system/ path mentions (not inside links — already captured above)
        for raw_match in _SYSTEM_PATH_RE.findall(line):
            # Skip if already inside a markdown link on this line
            # (crude but effective: check if this exact string appears inside a ](…))
            if f"]({raw_match})" in line:
                continue
            if _has_glob(raw_match):
                continue
            # Clean trailing punctuation
            cleaned = raw_match.rstrip(".,;:!?\"'")
            impl_files.append(cleaned)

    return _dedup_list(references), _dedup_list(impl_files)


def extract_typed_edges(
    content: str,
    source_path: Path,
    repo_root: Path,
    dimensions_real: Path | None = None,
) -> list[dict[str, str]]:
    """Extract typed relationship edges from content.

    Scans for patterns like [Label type](path.md) where type is one of:
    assumes, implements, informs, enriches, supersedes.

    Returns a list of {"from": source_key, "to": target_key, "type": rel_type}.
    """
    edges: list[dict[str, str]] = []
    source_key = str(source_path)

    in_fence = False
    fence_marker: str | None = None

    for line in content.splitlines():
        in_fence, fence_marker = _is_fence_open(line, in_fence, fence_marker)
        if in_fence:
            continue

        # Strip inline code spans to avoid matching examples like `[X assumes](path)`
        clean_line = _INLINE_CODE_RE.sub("", line)

        for _label, rel_type, raw_target in _TYPED_LINK_RE.findall(clean_line):
            target = raw_target.strip()

            # Skip URLs and bare anchors
            if target.startswith(("http://", "https://", "#")):
                continue

            # Strip anchors
            target = target.split("#")[0]
            if not target:
                continue

            resolved = _resolve_path(target, source_path, repo_root, dimensions_real)
            if resolved is None:
                continue

            edges.append({
                "from": source_key,
                "to": resolved,
                "type": rel_type,
            })

    return edges


def _has_glob(path: str) -> bool:
    return "*" in path or "{" in path


def _resolve_path(
    target: str,
    source_path: Path,
    repo_root: Path,
    dimensions_real: Path | None,
) -> str | None:
    """Resolve *target* to a repo-root-relative string, or None."""

    # Tilde paths: ~/enter_thebrana/...
    if target.startswith("~"):
        expanded = Path(target).expanduser().resolve()
        # Try to make relative to repo root
        try:
            rel = expanded.relative_to(repo_root.resolve())
            return str(rel)
        except ValueError:
            pass
        # If it points into the dimensions real dir, map back
        if dimensions_real is not None:
            try:
                rel_to_dim = expanded.relative_to(dimensions_real)
                return str(Path("docs/dimensions") / rel_to_dim)
            except ValueError:
                pass
        # Can't resolve — skip
        return None

    # Already repo-root-relative (no leading ./ or ../)
    if not target.startswith("."):
        return target

    # Relative path — resolve from source file's parent
    source_dir = source_path.parent
    resolved = (source_dir / target)
    # Normalize (collapse ..)
    parts: list[str] = []
    for part in resolved.parts:
        if part == "..":
            if parts:
                parts.pop()
        elif part != ".":
            parts.append(part)
    return "/".join(parts) if parts else None


def _dedup_list(items: list[str]) -> list[str]:
    seen: set[str] = set()
    result: list[str] = []
    for item in items:
        if item not in seen:
            seen.add(item)
            result.append(item)
    return result


# ---------------------------------------------------------------------------
# Graph building
# ---------------------------------------------------------------------------

def collect_markdown_files(docs_dir: Path, repo_root: Path) -> dict[str, Path]:
    """Collect all .md files from docs/ including symlinked dirs.

    Returns a dict mapping repo-root-relative canonical key to the actual
    file path on disk (which may differ for symlinked dirs).
    """
    found: dict[str, Path] = {}

    # Primary walk (rglob won't follow symlinks in Python 3.13)
    for p in docs_dir.rglob("*.md"):
        rel = p.relative_to(repo_root)
        found[str(rel)] = p

    # Explicit walks for dirs that may be symlinks or missed
    for subdir_name in ("dimensions", "research", "guide", "architecture"):
        subdir = docs_dir / subdir_name
        if subdir.exists():
            real_subdir = subdir.resolve()
            for p in real_subdir.rglob("*.md"):
                # Map back to docs/ relative form
                rel_to_sub = p.relative_to(real_subdir)
                canonical = Path("docs") / subdir_name / rel_to_sub
                key = str(canonical)
                if key not in found:
                    found[key] = p

    return found


def build_graph(
    repo_root: Path,
    docs_dir: Path | None = None,
) -> dict[str, Any]:
    """Build the full spec graph and return the JSON-serialisable dict."""

    if docs_dir is None:
        docs_dir = repo_root / "docs"

    # Resolve dimensions symlink target
    dim_link = docs_dir / "dimensions"
    dimensions_real: Path | None = None
    if dim_link.exists():
        dimensions_real = dim_link.resolve()

    md_file_map = collect_markdown_files(docs_dir, repo_root)

    nodes: dict[str, dict[str, list[str]]] = {}
    all_typed_edges: list[dict[str, str]] = []

    for key, md_path in md_file_map.items():
        rel = Path(key)
        content = md_path.read_text(errors="replace")
        refs, impls = extract_links(content, rel, repo_root, dimensions_real)
        nodes[key] = {
            "references": refs,
            "referenced_by": [],  # filled in reverse pass
            "impl_files": impls,
        }

        # Extract typed edges
        typed = extract_typed_edges(content, rel, repo_root, dimensions_real)
        all_typed_edges.extend(typed)

    # Reverse pass
    for src, data in nodes.items():
        for ref in data["references"]:
            if ref in nodes:
                if src not in nodes[ref]["referenced_by"]:
                    nodes[ref]["referenced_by"].append(src)

    # Dedup typed edges (same from/to/type)
    seen_edges: set[tuple[str, str, str]] = set()
    deduped_typed: list[dict[str, str]] = []
    for edge in all_typed_edges:
        key_tuple = (edge["from"], edge["to"], edge["type"])
        if key_tuple not in seen_edges:
            seen_edges.add(key_tuple)
            deduped_typed.append(edge)

    # Sort typed edges for deterministic output
    deduped_typed.sort(key=lambda e: (e["type"], e["from"], e["to"]))

    # Metrics
    edge_count = sum(len(d["references"]) for d in nodes.values())
    impl_ref_count = sum(len(d["impl_files"]) for d in nodes.values())
    orphan_count = sum(
        1 for d in nodes.values()
        if not d["references"] and not d["referenced_by"]
    )

    return {
        "_meta": {
            "generated": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
            "node_count": len(nodes),
            "edge_count": edge_count,
            "impl_ref_count": impl_ref_count,
            "orphan_count": orphan_count,
            "typed_edge_count": len(deduped_typed),
        },
        "nodes": dict(sorted(nodes.items())),
        "typed_edges": deduped_typed,
    }


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def cmd_generate(args: argparse.Namespace) -> None:
    repo_root = find_repo_root()
    graph = build_graph(repo_root)
    output = Path(args.output) if args.output else repo_root / "docs" / "spec-graph.json"
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(graph, indent=2) + "\n")
    meta = graph["_meta"]
    print(
        f"spec-graph: {meta['node_count']} nodes, {meta['edge_count']} edges, "
        f"{meta['impl_ref_count']} impl refs, {meta['orphan_count']} orphans, "
        f"{meta['typed_edge_count']} typed edges "
        f"-> {output}"
    )


def main(argv: list[str] | None = None) -> None:
    parser = argparse.ArgumentParser(description="Spec dependency graph generator")
    sub = parser.add_subparsers(dest="command")

    gen = sub.add_parser("generate", help="Generate spec-graph.json")
    gen.add_argument("--output", "-o", help="Output path (default: docs/spec-graph.json)")
    gen.set_defaults(func=cmd_generate)

    args = parser.parse_args(argv)
    if not hasattr(args, "func"):
        parser.print_help()
        sys.exit(1)
    args.func(args)


if __name__ == "__main__":
    main()
