#!/usr/bin/env python3
"""Audit + clear orphaned active_epic/active_initiative values in the global
tasks-config.json (t-2298 / ADR-066).

active_epic and active_initiative are project-scoped by definition (t-2158):
each lives in exactly one project's own .claude/tasks-config.json. The global
~/.claude/tasks-config.json should never carry an authoritative value for
either key -- but old values can linger from before that scoping was
enforced. This is a standing, re-runnable audit (not a one-shot patch),
since new orphans can reappear until every project has its own local config.

Usage:
    python3 audit-orphaned-active-epic.py            # dry-run (default): report only
    python3 audit-orphaned-active-epic.py --write     # actually clear orphaned keys
"""
import argparse
import json
import pathlib

HOME = pathlib.Path.home()
PROJECT_SCOPED_KEYS = ("active_epic", "active_initiative")


def orphaned_keys(global_cfg, project_configs):
    """Return {key: value} for global keys with no matching project-local value.

    Pure function -- no I/O. `project_configs` is a list of already-parsed
    project-local tasks-config.json dicts (or empty dicts/missing keys).
    """
    result = {}
    for key in PROJECT_SCOPED_KEYS:
        gval = global_cfg.get(key)
        if gval is None:
            continue
        if any(pc.get(key) == gval for pc in project_configs):
            continue
        result[key] = gval
    return result


def expand_home(path_str):
    if path_str.startswith("~"):
        return pathlib.Path(path_str).expanduser()
    return pathlib.Path(path_str)


def portfolio_project_paths(portfolio):
    """Extract every registered project path from tasks-portfolio.json's shape:
    {"clients": [{"projects": [{"path": "..."}]}]} (mirrors the jq expression
    already used for this in sync-state.sh cmd_pull's companion-file walk)."""
    paths = []
    for group in portfolio.get("clients", []):
        for project in group.get("projects", []):
            p = project.get("path")
            if p:
                paths.append(p)
    return paths


def load_project_configs(portfolio_paths):
    configs = []
    for rel in portfolio_paths:
        cfg_path = expand_home(rel) / ".claude" / "tasks-config.json"
        if cfg_path.exists():
            try:
                configs.append(json.loads(cfg_path.read_text()))
            except json.JSONDecodeError:
                continue
    return configs


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--write", action="store_true", help="actually clear orphaned keys (default: dry-run report only)")
    args = parser.parse_args()

    global_path = HOME / ".claude" / "tasks-config.json"
    if not global_path.exists():
        print("no global tasks-config.json found -- nothing to audit")
        return

    global_cfg = json.loads(global_path.read_text())

    portfolio_path = HOME / ".claude" / "tasks-portfolio.json"
    portfolio = json.loads(portfolio_path.read_text()) if portfolio_path.exists() else {}
    paths = portfolio_project_paths(portfolio)
    project_configs = load_project_configs(paths)

    orphans = orphaned_keys(global_cfg, project_configs)

    if not orphans:
        print(f"OK -- no orphaned keys in global config (checked {len(project_configs)} project-local configs)")
        return

    for key, value in orphans.items():
        print(f"orphaned: {key} = {value!r} (no project-local config among {len(project_configs)} matches it)")

    if not args.write:
        print("\nDry-run only -- rerun with --write to clear the orphaned key(s) above.")
        return

    for key in orphans:
        del global_cfg[key]
    global_path.write_text(json.dumps(global_cfg, indent=2) + "\n")
    print(f"\nCleared {len(orphans)} orphaned key(s) from {global_path}")


if __name__ == "__main__":
    main()
