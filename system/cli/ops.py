"""brana ops — scheduler and system operations CLI."""

from __future__ import annotations

import json
import re
import subprocess
from datetime import datetime
from pathlib import Path
from typing import Optional

import typer

from .config import (
    SCHEDULER_CONFIG, SCHEDULER_LOGS, SCHEDULER_STATUS, SCHEDULER_TEMPLATE,
    detect_project, load_json,
)
from .theme import color, console, create_table, get_theme, icon, print_header

ops_app = typer.Typer()


# ── helpers ──────────────────────────────────────────────────────────────


def _load_scheduler() -> dict:
    data = load_json(SCHEDULER_CONFIG)
    return data if data else {"jobs": {}}


def _load_status() -> dict:
    data = load_json(SCHEDULER_STATUS)
    return data if data else {}


def _get_timer_info(job_name: str) -> dict:
    unit = f"brana-sched-{job_name}.timer"
    try:
        result = subprocess.run(
            ["systemctl", "--user", "show", unit,
             "--property=ActiveState,NextElapseUSecRealtime,Result"],
            capture_output=True, text=True, timeout=5,
        )
        info = {}
        for line in result.stdout.strip().splitlines():
            if "=" in line:
                k, v = line.split("=", 1)
                info[k] = v
        return info
    except (subprocess.TimeoutExpired, FileNotFoundError):
        return {}


def _status_icon(status: str, theme: dict) -> str:
    mapping = {
        "SUCCESS": "done",
        "FAILED": "blocked",
        "TIMEOUT": "blocked",
        "SKIPPED": "parked",
    }
    return icon(mapping.get(status, "pending"), theme)


def _status_color(status: str) -> str:
    mapping = {
        "SUCCESS": "green",
        "FAILED": "red",
        "TIMEOUT": "red",
        "SKIPPED": "dim",
    }
    return mapping.get(status, "yellow")


# ── commands ─────────────────────────────────────────────────────────────


@ops_app.command()
def status(wide: bool = typer.Option(False, "--wide", "-w")):
    """Dashboard: all jobs, last run, next trigger, health."""
    theme = get_theme()
    sched = _load_scheduler()
    last_status = _load_status()
    jobs = sched.get("jobs", {})

    print_header("Scheduler", theme)

    if wide:
        table = create_table("", "Job", "Schedule", "Enabled", "Last Run", "Status",
                             "Next Trigger", "Project")
        for name, cfg in sorted(jobs.items()):
            enabled = cfg.get("enabled", True)
            job_status = last_status.get(name, {})
            st = job_status.get("status", "—")
            ts = job_status.get("timestamp", "—")
            if ts != "—":
                try:
                    ts = datetime.fromisoformat(ts).strftime("%Y-%m-%d %H:%M")
                except ValueError:
                    pass

            timer = _get_timer_info(name)
            next_trigger = timer.get("NextElapseUSecRealtime", "—")
            if next_trigger and next_trigger != "—":
                # systemd gives epoch microseconds or human-readable
                try:
                    next_trigger = next_trigger.split(" ")[0:3]
                    next_trigger = " ".join(next_trigger)
                except (IndexError, ValueError):
                    pass

            ic = _status_icon(st, theme) if enabled else icon("parked", theme)
            table.add_row(
                ic, name, cfg.get("schedule", "—"),
                "yes" if enabled else "no",
                ts, st, str(next_trigger),
                Path(cfg.get("project", "")).name,
                style=_status_color(st) if enabled else "dim",
            )
        console.print(table)
    else:
        for name, cfg in sorted(jobs.items()):
            enabled = cfg.get("enabled", True)
            job_status = last_status.get(name, {})
            st = job_status.get("status", "—")
            ts = job_status.get("timestamp", "")
            if ts:
                try:
                    ts = datetime.fromisoformat(ts).strftime("%m-%d %H:%M")
                except ValueError:
                    pass

            ic = _status_icon(st, theme) if enabled else icon("parked", theme)
            schedule = cfg.get("schedule", "—")
            style = _status_color(st) if enabled else "dim"

            line = f"  {ic} {name:<24} {schedule:<24} {st:<10} {ts}"
            if not enabled:
                line += "  [disabled]"
            console.print(line, style=style)

    console.print()


@ops_app.command()
def health():
    """Aggregate health: failures in 24h, missed runs, lock contention."""
    theme = get_theme()
    sched = _load_scheduler()
    last_status = _load_status()
    jobs = sched.get("jobs", {})

    now = datetime.now()
    failures_24h = []
    skipped_24h = []

    for name, info in last_status.items():
        ts = info.get("timestamp", "")
        try:
            run_time = datetime.fromisoformat(ts)
            if (now - run_time).total_seconds() > 86400:
                continue
        except ValueError:
            continue

        if info.get("status") == "FAILED":
            failures_24h.append(name)
        elif info.get("status") == "SKIPPED":
            skipped_24h.append(name)

    # Check for schedule collisions
    collisions = _find_collisions(jobs)

    print_header("Scheduler health", theme)

    ok = icon("done", theme)
    fail = icon("blocked", theme)
    warn = icon("pending", theme)

    if failures_24h:
        console.print(f"  {fail} Failures (24h): {', '.join(failures_24h)}", style="red")
    else:
        console.print(f"  {ok} No failures in 24h", style="green")

    if skipped_24h:
        console.print(f"  {warn} Skipped/locked: {', '.join(skipped_24h)}", style="yellow")

    if collisions:
        console.print(f"  {fail} Schedule collisions:", style="red")
        for group in collisions:
            console.print(f"      {group['schedule']} on {group['project']}: {', '.join(group['jobs'])}")
    else:
        console.print(f"  {ok} No schedule collisions", style="green")

    enabled = sum(1 for j in jobs.values() if j.get("enabled", True))
    disabled = len(jobs) - enabled
    console.print(f"\n  {enabled} enabled, {disabled} disabled, {len(jobs)} total")
    console.print()


def _find_collisions(jobs: dict) -> list[dict]:
    groups: dict[tuple, list] = {}
    for name, cfg in jobs.items():
        if not cfg.get("enabled", True):
            continue
        key = (cfg.get("schedule", ""), Path(cfg.get("project", "")).name)
        groups.setdefault(key, []).append(name)

    return [
        {"schedule": k[0], "project": k[1], "jobs": v}
        for k, v in groups.items()
        if len(v) > 1
    ]


@ops_app.command()
def logs(
    job_name: str = typer.Argument(..., help="Job name"),
    tail: int = typer.Option(50, "--tail", "-n", help="Number of lines"),
):
    """View logs for a scheduler job."""
    job_log_dir = SCHEDULER_LOGS / job_name
    if not job_log_dir.exists():
        console.print(f"\n  No logs found for '{job_name}'.\n")
        raise typer.Exit(1)

    log_files = sorted(job_log_dir.glob("*.log"), reverse=True)
    if not log_files:
        console.print(f"\n  No log files in {job_log_dir}.\n")
        raise typer.Exit(1)

    latest = log_files[0]
    lines = latest.read_text().splitlines()
    show = lines[-tail:] if len(lines) > tail else lines

    console.print(f"\n  [dim]{latest.name}[/]\n")
    for line in show:
        if "SUCCESS" in line:
            console.print(f"  [green]{line}[/]")
        elif "FAILED" in line or "ERROR" in line:
            console.print(f"  [red]{line}[/]")
        elif "TIMEOUT" in line or "SKIPPED" in line:
            console.print(f"  [yellow]{line}[/]")
        else:
            console.print(f"  {line}")
    console.print()


@ops_app.command()
def history(
    job_name: str = typer.Argument(..., help="Job name"),
    last: int = typer.Option(10, "--last", "-n", help="Number of runs to show"),
):
    """Run history for a job (pass/fail trend)."""
    theme = get_theme()
    job_log_dir = SCHEDULER_LOGS / job_name
    if not job_log_dir.exists():
        console.print(f"\n  No history for '{job_name}'.\n")
        raise typer.Exit(1)

    log_files = sorted(job_log_dir.glob("*.log"), reverse=True)[:last]

    print_header(f"History: {job_name} (last {len(log_files)})", theme)
    for lf in log_files:
        content = lf.read_text()
        if "SUCCESS" in content:
            st, style = "SUCCESS", "green"
        elif "FAILED" in content:
            st, style = "FAILED", "red"
        elif "TIMEOUT" in content:
            st, style = "TIMEOUT", "red"
        elif "SKIPPED" in content:
            st, style = "SKIPPED", "dim"
        else:
            st, style = "UNKNOWN", "yellow"

        date = lf.stem  # filename is timestamp
        console.print(f"  [{style}]{_status_icon(st, theme)} {date}  {st}[/]")

    console.print()


@ops_app.command()
def collisions():
    """Detect same-project schedule conflicts."""
    theme = get_theme()
    sched = _load_scheduler()
    groups = _find_collisions(sched.get("jobs", {}))

    if not groups:
        console.print(f"\n  {icon('done', theme)} No schedule collisions.\n", style="green")
        return

    print_header("Schedule collisions", theme)
    for g in groups:
        console.print(
            f"  {icon('blocked', theme)} {g['schedule']} on {g['project']}: "
            f"{', '.join(g['jobs'])}",
            style="red",
        )
    console.print()


@ops_app.command()
def drift():
    """Compare live scheduler config vs template."""
    theme = get_theme()

    if SCHEDULER_TEMPLATE is None or not SCHEDULER_TEMPLATE.exists():
        console.print("\n  Template not found.\n")
        raise typer.Exit(1)

    template = load_json(SCHEDULER_TEMPLATE)
    live = _load_scheduler()

    if template is None:
        console.print("\n  Cannot load template.\n")
        raise typer.Exit(1)

    tmpl_jobs = template.get("jobs", {})
    live_jobs = live.get("jobs", {})

    drifts = []

    for name in set(tmpl_jobs) | set(live_jobs):
        if name not in tmpl_jobs:
            drifts.append(f"  [yellow]+ {name}: in live but not in template[/]")
        elif name not in live_jobs:
            drifts.append(f"  [red]- {name}: in template but not in live[/]")
        else:
            for field in ["schedule", "enabled", "command", "project", "type"]:
                tv = tmpl_jobs[name].get(field)
                lv = live_jobs[name].get(field)
                if tv != lv:
                    drifts.append(f"  [yellow]~ {name}.{field}: template={tv} live={lv}[/]")

    if not drifts:
        console.print(f"\n  {icon('done', theme)} No drift — live matches template.\n", style="green")
        return

    print_header("Config drift (template vs live)", theme)
    for line in drifts:
        console.print(line)
    console.print()


_JOB_NAME_RE = re.compile(r"^[a-zA-Z0-9_-]+$")


def _validate_job_name(job_name: str):
    if not _JOB_NAME_RE.match(job_name):
        console.print(f"\n  Invalid job name '{job_name}'. Use alphanumeric, hyphens, underscores.\n")
        raise typer.Exit(1)


@ops_app.command()
def run(job_name: str = typer.Argument(..., help="Job to trigger manually")):
    """Manually trigger a scheduler job now."""
    _validate_job_name(job_name)
    sched = _load_scheduler()
    if job_name not in sched.get("jobs", {}):
        console.print(f"\n  Job '{job_name}' not found in scheduler config.\n")
        raise typer.Exit(1)

    unit = f"brana-sched-{job_name}.service"
    console.print(f"\n  Starting {unit}...")

    try:
        subprocess.run(
            ["systemctl", "--user", "start", unit],
            check=True, timeout=10,
        )
        console.print(f"  [green]Triggered. Check logs: brana ops logs {job_name}[/]\n")
    except subprocess.CalledProcessError as e:
        console.print(f"  [red]Failed to start: {e}[/]\n")
        raise typer.Exit(1)


@ops_app.command()
def enable(job_name: str = typer.Argument(..., help="Job to enable")):
    """Enable a disabled scheduler job."""
    _toggle_job(job_name, enabled=True)


@ops_app.command()
def disable(job_name: str = typer.Argument(..., help="Job to disable")):
    """Disable a scheduler job."""
    _toggle_job(job_name, enabled=False)


def _toggle_job(job_name: str, enabled: bool):
    _validate_job_name(job_name)
    sched = _load_scheduler()
    jobs = sched.get("jobs", {})

    if job_name not in jobs:
        console.print(f"\n  Job '{job_name}' not found.\n")
        raise typer.Exit(1)

    jobs[job_name]["enabled"] = enabled
    SCHEDULER_CONFIG.write_text(json.dumps(sched, indent=2) + "\n")

    action = "Enabled" if enabled else "Disabled"
    style = "green" if enabled else "yellow"
    console.print(f"\n  [{style}]{action} '{job_name}' in scheduler.json.[/]")

    # Also toggle systemd timer
    timer_unit = f"brana-sched-{job_name}.timer"
    systemd_action = "start" if enabled else "stop"
    try:
        subprocess.run(
            ["systemctl", "--user", systemd_action, timer_unit],
            check=True, timeout=10,
        )
        console.print(f"  [{style}]Timer {systemd_action}ed.[/]\n")
    except subprocess.CalledProcessError:
        console.print(f"  [yellow]Warning: could not {systemd_action} timer {timer_unit}[/]\n")


@ops_app.command()
def sync(
    auto_commit: bool = typer.Option(False, "--auto-commit", help="Auto-commit changes"),
    direction: str = typer.Option("push", help="push or pull"),
):
    """Sync operational state (wraps sync-state.sh)."""
    root, _ = detect_project()
    if root is None:
        console.print("\n  Not in a git project.\n")
        raise typer.Exit(1)

    script = root / "system" / "scripts" / "sync-state.sh"
    if not script.exists():
        console.print(f"\n  sync-state.sh not found at {script}.\n")
        raise typer.Exit(1)

    cmd = ["bash", str(script), direction]
    if auto_commit:
        cmd.append("--auto-commit")

    console.print(f"\n  Running sync-state.sh {direction}...")
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=60, cwd=root)
        for line in result.stdout.strip().splitlines():
            console.print(f"  {line}")
        if result.returncode != 0:
            for line in result.stderr.strip().splitlines():
                console.print(f"  [red]{line}[/]")
            raise typer.Exit(1)
    except subprocess.TimeoutExpired:
        console.print("  [red]Timeout after 60s.[/]\n")
        raise typer.Exit(1)
    console.print()


@ops_app.command()
def reindex():
    """Reindex brana-knowledge into ruflo memory (wraps index-knowledge.sh)."""
    root, _ = detect_project()
    if root is None:
        console.print("\n  Not in a git project.\n")
        raise typer.Exit(1)

    script = root / "system" / "scripts" / "index-knowledge.sh"
    if not script.exists():
        console.print(f"\n  index-knowledge.sh not found at {script}.\n")
        raise typer.Exit(1)

    console.print("\n  Running index-knowledge.sh (this may take a while)...")
    try:
        result = subprocess.run(
            ["bash", str(script)], capture_output=True, text=True,
            timeout=600, cwd=root,
        )
        for line in result.stdout.strip().splitlines():
            console.print(f"  {line}")
        if result.returncode != 0:
            for line in result.stderr.strip().splitlines():
                console.print(f"  [red]{line}[/]")
            raise typer.Exit(1)
    except subprocess.TimeoutExpired:
        console.print("  [red]Timeout after 10m.[/]\n")
        raise typer.Exit(1)
    console.print()
