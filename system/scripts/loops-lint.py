#!/usr/bin/env python3
"""Lint a system/loops/ catalog entry against the entry-schema contract.

Contract source: docs/architecture/features/loops-library.md (t-2826).
Usage: loops-lint.py <entry.md> [entry2.md ...]
Exit 0 if every entry passes, 1 if any fails (errors printed to stdout).
"""
import re
import sys
from pathlib import Path

import yaml

REQUIRED_KEYS = ["name", "autonomy", "supervised", "drains", "fills", "spawns", "records"]
LIST_KEYS = ["drains", "fills", "spawns"]
VALID_AUTONOMY = {"L0", "L1", "L2", "L3"}
DENIED_VERBS_HEADING = re.compile(r"^#+\s*denied verbs\b", re.IGNORECASE | re.MULTILINE)


def parse_entry(path):
    """Split a loop entry file into (frontmatter dict, body string)."""
    text = path.read_text()
    if not text.startswith("---\n"):
        return None, text
    end = text.find("\n---\n", 4)
    if end == -1:
        return None, text
    frontmatter_text = text[4:end]
    body = text[end + 5:]
    frontmatter = yaml.safe_load(frontmatter_text) or {}
    return frontmatter, body


def lint_content(frontmatter, body):
    """Pure validation: frontmatter dict + body string -> list of error strings.

    Empty list means the entry passes.
    """
    errors = []

    for key in REQUIRED_KEYS:
        if key not in frontmatter:
            errors.append(f"missing required frontmatter key: {key}")

    if "cadence" not in frontmatter and "pacing" not in frontmatter:
        errors.append("missing required frontmatter key: one of cadence/pacing")

    autonomy = frontmatter.get("autonomy")
    if autonomy is not None and autonomy not in VALID_AUTONOMY:
        errors.append(f"invalid autonomy value: {autonomy!r} (must be one of {sorted(VALID_AUTONOMY)})")

    records = frontmatter.get("records")
    if records is not None and not isinstance(records, str):
        errors.append(
            "records field must be a string reference to the single-sourced beat-record "
            "schema (docs/architecture/features/loops-library.md), not an inline redefinition"
        )

    for key in LIST_KEYS:
        value = frontmatter.get(key)
        if value is not None and not isinstance(value, list):
            errors.append(f"{key} field must be a list, got {type(value).__name__}")

    supervised = frontmatter.get("supervised")
    if supervised is not None and not isinstance(supervised, bool):
        errors.append(f"supervised field must be a boolean, got {type(supervised).__name__}")
    elif supervised is False:
        errors.append("supervised: false is unreachable until ADR-062 lands (Boundaries: never enable unattended mode)")

    if autonomy is not None and autonomy != "L0" and autonomy in VALID_AUTONOMY:
        if not DENIED_VERBS_HEADING.search(body):
            errors.append(
                f"autonomy {autonomy} requires a 'Denied verbs' markdown heading in the body "
                "(a substring mention in prose does not count)"
            )

    return errors


def main(argv):
    if not argv:
        print("usage: loops-lint.py <entry.md> [entry2.md ...]", file=sys.stderr)
        return 1

    any_failed = False
    for arg in argv:
        path = Path(arg)
        frontmatter, body = parse_entry(path)
        if frontmatter is None:
            print(f"{path}: FAIL — no YAML frontmatter found")
            any_failed = True
            continue
        errors = lint_content(frontmatter, body)
        if errors:
            any_failed = True
            for err in errors:
                print(f"{path}: FAIL — {err}")
        else:
            print(f"{path}: PASS")

    return 1 if any_failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
