#!/usr/bin/env python3
"""
check-shared-coverage.py — validate that all mcp__* tools used in _shared/*.md procedures
are present in the allowed-tools frontmatter of consumer SKILL.md files.

A SKILL.md (or any file in its directory) is a "consumer" if it contains a reference
to the shared procedure file (e.g. `_shared/adversarial-hive-mind.md`).

Exit 0 = all covered. Exit 1 = missing tools found.
"""
import sys
import re
from pathlib import Path

REPO_ROOT = Path(__file__).parent.parent.parent
SHARED_DIR = REPO_ROOT / "system/skills/_shared"
SKILLS_DIR = REPO_ROOT / "system/skills"

TOOL_PATTERN = re.compile(r'mcp__[a-zA-Z0-9_-]+')


def get_shared_tools(shared_file: Path) -> set:
    return set(TOOL_PATTERN.findall(shared_file.read_text()))


def get_allowed_tools(skill_file: Path) -> set | None:
    """Parse allowed-tools from YAML frontmatter. Returns None if no frontmatter/field."""
    text = skill_file.read_text()
    if not text.startswith("---"):
        return None
    try:
        end = text.index("---", 3)
    except ValueError:
        return None
    frontmatter = text[3:end]
    tools = set()
    in_allowed = False
    for line in frontmatter.splitlines():
        stripped = line.strip()
        if stripped.startswith("allowed-tools:"):
            in_allowed = True
        elif in_allowed:
            if stripped.startswith("- "):
                tools.add(stripped[2:].strip())
            elif stripped and not line.startswith(" ") and not line.startswith("\t"):
                in_allowed = False
    return tools if tools else None


def skill_dir_references_shared(skill_dir: Path, shared_name: str) -> bool:
    """Return True if any .md in skill_dir (incl. subdirs) references _shared/{shared_name}."""
    needle = f"_shared/{shared_name}"
    for md in skill_dir.rglob("*.md"):
        if "_shared" in md.parts:
            continue
        if needle in md.read_text():
            return True
    return False


def main() -> int:
    shared_tools: dict[str, set] = {}
    for f in sorted(SHARED_DIR.glob("*.md")):
        tools = get_shared_tools(f)
        if tools:
            shared_tools[f.name] = tools

    if not shared_tools:
        print("OK — no mcp__ tools found in _shared/ (nothing to validate).")
        return 0

    failures: list[tuple] = []

    for skill_dir in sorted(SKILLS_DIR.iterdir()):
        if not skill_dir.is_dir() or skill_dir.name.startswith("_"):
            continue
        skill_file = skill_dir / "SKILL.md"
        if not skill_file.exists():
            continue
        allowed = get_allowed_tools(skill_file)
        if allowed is None:
            continue  # No allowed-tools constraint — not checked

        for shared_name, tools in shared_tools.items():
            if not skill_dir_references_shared(skill_dir, shared_name):
                continue
            missing = tools - allowed
            if missing:
                failures.append((skill_file.relative_to(REPO_ROOT), shared_name, sorted(missing)))

    if not failures:
        print("OK — all _shared/ tool references covered in consumer SKILL.md allowed-tools.")
        return 0

    print("FAIL — missing tool coverage in consumer SKILL.md allowed-tools:\n")
    for skill_path, shared_name, missing in failures:
        print(f"  {skill_path}")
        print(f"    shared procedure: _shared/{shared_name}")
        for tool in missing:
            print(f"    missing: {tool}")
        print()
    return 1


if __name__ == "__main__":
    sys.exit(main())
