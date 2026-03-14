"""Brana CLI — standalone terminal interface for tasks, scheduler, and system health."""

from __future__ import annotations

import shutil
import subprocess
from pathlib import Path

import typer
from rich.table import Table

from .config import (
    CLAUDE_DIR, SCHEDULER_CONFIG, SCHEDULER_STATUS,
    detect_project, load_json, load_tasks,
)
from .theme import console, get_theme, icon

app = typer.Typer(
    name="brana",
    help="Brana system CLI — tasks, scheduler, and system health.",
    no_args_is_help=True,
)


def _register_subcommands():
    from .backlog import backlog_app
    from .ops import ops_app
    app.add_typer(backlog_app, name="backlog", help="Task management (mirrors /brana:backlog)")
    app.add_typer(ops_app, name="ops", help="Scheduler and system operations")


_register_subcommands()


@app.command()
def version():
    """Show brana system version, plugin version, and ruflo version."""
    # Brana version from pyproject.toml
    pyproject = Path(__file__).parent.parent.parent / "pyproject.toml"
    brana_version = "unknown"
    if pyproject.exists():
        for line in pyproject.read_text().splitlines():
            if line.strip().startswith("version"):
                brana_version = line.split("=")[1].strip().strip('"')
                break

    # Plugin version
    plugin_json = Path(__file__).parent.parent / ".claude-plugin" / "plugin.json"
    plugin_version = "unknown"
    plugin_data = load_json(plugin_json)
    if plugin_data:
        plugin_version = plugin_data.get("version", "unknown")

    # Ruflo version
    ruflo_version = "not found"
    for cmd in ["ruflo", "claude-flow"]:
        if shutil.which(cmd):
            try:
                result = subprocess.run([cmd, "--version"], capture_output=True, text=True, timeout=5)
                ruflo_version = result.stdout.strip() or result.stderr.strip()
            except (subprocess.TimeoutExpired, FileNotFoundError):
                pass
            break

    table = Table(show_header=False, show_edge=False, pad_edge=False)
    table.add_column("Component", style="cyan")
    table.add_column("Version")
    table.add_row("brana-cli", brana_version)
    table.add_row("plugin", plugin_version)
    table.add_row("ruflo", ruflo_version)
    console.print(table)


@app.command()
def doctor():
    """Health check: ruflo, systemd timers, tasks.json validity, bootstrap."""
    theme = get_theme()
    ok = icon("done", theme)
    fail = icon("blocked", theme)
    checks_passed = 0
    checks_total = 0

    def check(name: str, passed: bool, detail: str = ""):
        nonlocal checks_passed, checks_total
        checks_total += 1
        ic = ok if passed else fail
        if passed:
            checks_passed += 1
        msg = f"  {ic} {name}"
        if detail:
            msg += f"  ({detail})"
        style = "green" if passed else "red"
        console.print(f"[{style}]{msg}[/]")

    console.print("\n[bold]brana doctor[/]\n")

    # 1. Project detection
    root, name = detect_project()
    check("Git project detected", root is not None, name if root else "not in a git repo")

    # 2. tasks.json exists and is valid
    if root:
        tasks_file = root / ".claude" / "tasks.json"
        tasks_data = load_tasks(root)
        tasks_exist = tasks_file.exists()
        check("tasks.json exists", tasks_exist,
              f"{len(tasks_data.get('tasks', []))} tasks" if tasks_exist else "not found")

        # Duplicate ID check
        if tasks_exist:
            ids = [t["id"] for t in tasks_data.get("tasks", [])]
            dupes = [i for i in set(ids) if ids.count(i) > 1]
            check("No duplicate task IDs", len(dupes) == 0,
                  f"duplicates: {', '.join(dupes)}" if dupes else "all unique")

    # 3. Scheduler config
    sched_exists = SCHEDULER_CONFIG.exists()
    check("scheduler.json exists", sched_exists)
    if sched_exists:
        sched_data = load_json(SCHEDULER_CONFIG)
        enabled_jobs = [k for k, v in sched_data.get("jobs", {}).items() if v.get("enabled")]
        check("Scheduler jobs configured", len(enabled_jobs) > 0, f"{len(enabled_jobs)} enabled")

    # 4. Systemd timers
    try:
        result = subprocess.run(
            ["systemctl", "--user", "list-units", "brana-sched-*.timer", "--no-legend", "--plain"],
            capture_output=True, text=True, timeout=5,
        )
        timer_lines = [l for l in result.stdout.strip().splitlines() if l.strip()]
        active_timers = [l for l in timer_lines if "active" in l]
        check("Systemd timers active", len(active_timers) > 0,
              f"{len(active_timers)} active" if active_timers else "none found")
    except (subprocess.TimeoutExpired, FileNotFoundError):
        check("Systemd timers", False, "systemctl not available")

    # 5. Ruflo/claude-flow
    ruflo_found = False
    for cmd in ["ruflo", "claude-flow"]:
        if shutil.which(cmd):
            ruflo_found = True
            break
    check("Ruflo/claude-flow installed", ruflo_found)

    # 6. Bootstrap freshness
    bootstrap_marker = CLAUDE_DIR / "CLAUDE.md"
    check("Bootstrap deployed", bootstrap_marker.exists(),
          "~/.claude/CLAUDE.md present" if bootstrap_marker.exists() else "run bootstrap.sh")

    # 7. last-status.json
    status_exists = SCHEDULER_STATUS.exists()
    if status_exists:
        status_data = load_json(SCHEDULER_STATUS)
        if status_data:
            failures = [k for k, v in status_data.items() if v.get("status") == "FAILED"]
            check("No recent scheduler failures", len(failures) == 0,
                  f"failed: {', '.join(failures)}" if failures else "all ok")

    console.print(f"\n  {checks_passed}/{checks_total} checks passed\n")


if __name__ == "__main__":
    app()
