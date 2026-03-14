"""brana backlog — task management CLI (mirrors /brana:backlog)."""

from __future__ import annotations

import json
import subprocess
from collections import Counter
from datetime import datetime, timedelta
from pathlib import Path
from typing import Optional

import typer
from rich.text import Text
from rich.tree import Tree

from .config import (
    classify_task, detect_project, git_root, load_json, load_portfolio,
    load_tasks, tasks_file_path,
)
from .theme import (
    color, console, create_table, get_theme, icon, print_header,
    priority_label, progress_bar, styled_task_line, task_line,
)

backlog_app = typer.Typer()


# ── helpers ──────────────────────────────────────────────────────────────


def _filter_tasks(
    tasks: list[dict],
    all_tasks: list[dict],
    *,
    tag: str | None = None,
    status_filter: str | None = None,
    stream: str | None = None,
    priority: str | None = None,
    effort: str | None = None,
    types: tuple[str, ...] = ("task", "subtask"),
) -> list[dict]:
    result = []
    for t in tasks:
        if t.get("type") not in types:
            continue
        if status_filter:
            if classify_task(t, all_tasks) != status_filter:
                continue
        if tag and tag not in (t.get("tags") or []):
            continue
        if stream and t.get("stream") != stream:
            continue
        if priority and t.get("priority") != priority:
            continue
        if effort and t.get("effort") != effort:
            continue
        result.append(t)
    return result


def _sort_by_priority(tasks: list[dict]) -> list[dict]:
    pri_order = {"P0": 0, "P1": 1, "P2": 2, "P3": 3}

    def sort_key(t):
        p = pri_order.get(t.get("priority"), 4)
        status_order = 0 if t.get("status") == "in_progress" else 1
        return (p, status_order, t.get("order") or 999, t.get("created", ""))

    return sorted(tasks, key=sort_key)


def _focus_score(task: dict, all_tasks: list[dict]) -> float:
    pri_weights = {"P0": 400, "P1": 300, "P2": 200, "P3": 100}
    score = pri_weights.get(task.get("priority"), 50)

    created = task.get("created")
    if created:
        try:
            days = (datetime.now() - datetime.fromisoformat(created)).days
            score += days * 2
        except ValueError:
            pass

    effort_weights = {"S": 10, "M": 20, "L": 30, "XL": 40}
    score -= effort_weights.get(task.get("effort"), 15)

    blocked_by = task.get("blocked_by") or []
    score -= len(blocked_by) * 50

    return score


def _build_blocked_chain(
    task_id: str, all_tasks: list[dict], depth: int = 0,
    visited: set | None = None,
) -> list[tuple[int, dict]]:
    if visited is None:
        visited = set()
    if task_id in visited:
        return []
    visited.add(task_id)
    chain = []
    task = next((t for t in all_tasks if t["id"] == task_id), None)
    if not task:
        return chain
    chain.append((depth, task))
    for bid in task.get("blocked_by") or []:
        blocker = next((t for t in all_tasks if t["id"] == bid), None)
        if blocker and classify_task(blocker, all_tasks) != "done":
            chain.extend(_build_blocked_chain(bid, all_tasks, depth + 1, visited))
    return chain


# ── commands ─────────────────────────────────────────────────────────────


@backlog_app.command()
def status(
    project: Optional[str] = typer.Option(None, "--project", "-p", help="Project name"),
    all_clients: bool = typer.Option(False, "--all", "-a", help="Cross-client view"),
    wide: bool = typer.Option(False, "--wide", "-w", help="Tabular wide output"),
):
    """Portfolio or project status overview."""
    theme = get_theme()

    if all_clients or project is None:
        # Portfolio summary
        portfolio = load_portfolio()
        if not portfolio:
            _, pname = detect_project()
            data = load_tasks()
            _render_project_status(data, pname, theme, wide)
            return

        print_header("Portfolio", theme)
        for proj in portfolio:
            proj_path = Path(proj["path"])
            tasks_file = proj_path / ".claude" / "tasks.json"
            if not tasks_file.exists():
                continue
            pdata = load_json(tasks_file)
            if pdata is None:
                continue
            if isinstance(pdata, list):
                pdata = {"project": proj.get("slug", proj_path.name), "tasks": pdata}
            slug = proj.get("_client", proj.get("slug", proj_path.name))

            tasks = [t for t in pdata.get("tasks", []) if t.get("type") in ("task", "subtask")]
            done = sum(1 for t in tasks if t.get("status") == "completed")
            active = sum(1 for t in tasks if t.get("status") == "in_progress")
            total = len(tasks)
            pending = total - done - active

            if total == 0:
                continue

            bar = progress_bar(done, total, theme=theme)
            health = ""
            if "health" in theme:
                if done == total:
                    health = theme["health"]["done"] + " "
                elif any(classify_task(t, tasks) == "blocked" for t in tasks):
                    health = theme["health"]["blocked"] + " "
                else:
                    health = theme["health"]["active"] + " "

            console.print(f"  {health}{slug:<16} {bar}  {active} active, {pending} pending")

        console.print()
        return

    # Single project
    data = load_tasks()
    _, pname = detect_project()
    _render_project_status(data, project or pname, theme, wide)


def _render_project_status(data: dict, project_name: str, theme: dict, wide: bool):
    tasks = data.get("tasks", [])
    all_tasks = tasks

    if wide:
        table = create_table("", "ID", "Subject", "Status", "Tags", "Pri", "Eff", "Stream",
                             title=project_name)
        for t in tasks:
            if t.get("type") not in ("task", "subtask"):
                continue
            st = classify_task(t, all_tasks)
            tags = ", ".join((t.get("tags") or [])[:3])
            table.add_row(
                icon(st, theme), t["id"], t.get("subject", ""),
                st, tags, t.get("priority") or "—",
                t.get("effort") or "—", t.get("stream") or "—",
                style=color(st, theme),
            )
        console.print(table)
        console.print()
        return

    # Compact view grouped by stream
    print_header(f"{project_name}", theme)

    streams: dict[str, list] = {}
    for t in tasks:
        if t.get("type") not in ("task", "subtask"):
            continue
        s = t.get("stream", "other")
        streams.setdefault(s, []).append(t)

    for stream_name in ["roadmap", "bugs", "tech-debt", "research", "experiments", "docs"]:
        stream_tasks = streams.pop(stream_name, [])
        if not stream_tasks:
            continue
        done = sum(1 for t in stream_tasks if t.get("status") == "completed")
        console.print(f"\n  {stream_name.title():<16} {progress_bar(done, len(stream_tasks), theme=theme)}")
        for t in stream_tasks:
            st = classify_task(t, all_tasks)
            if st == "done":
                continue
            console.print(f"    {task_line(t, st, theme)}", style=color(st, theme))

    # Remaining streams
    for stream_name, stream_tasks in streams.items():
        if not stream_tasks:
            continue
        done = sum(1 for t in stream_tasks if t.get("status") == "completed")
        console.print(f"\n  {stream_name.title():<16} {progress_bar(done, len(stream_tasks), theme=theme)}")

    # Tag summary
    tag_counts: Counter = Counter()
    for t in tasks:
        if t.get("status") != "completed" and t.get("type") in ("task", "subtask"):
            for tg in t.get("tags") or []:
                tag_counts[tg] += 1
    if tag_counts:
        top_tags = " ".join(f"{tg}({c})" for tg, c in tag_counts.most_common(8))
        console.print(f"\n  Tags: {top_tags}")

    console.print()


@backlog_app.command(name="next")
def next_task(
    project: Optional[str] = typer.Option(None, "--project", "-p"),
    stream: Optional[str] = typer.Option(None, "--stream", "-s"),
    tag: Optional[str] = typer.Option(None, "--tag", "-t"),
):
    """Next unblocked task by priority."""
    theme = get_theme()
    data = load_tasks()
    all_tasks = data.get("tasks", [])

    candidates = _filter_tasks(all_tasks, all_tasks, tag=tag, stream=stream)
    candidates = [t for t in candidates if classify_task(t, all_tasks) == "pending"]
    candidates = _sort_by_priority(candidates)[:3]

    if not candidates:
        console.print("\n  No unblocked tasks found.\n")
        return

    print_header("Next up", theme)
    for i, t in enumerate(candidates, 1):
        pri = priority_label(t.get("priority"), theme)
        eff = t.get("effort") or "—"
        st = t.get("stream") or "—"
        console.print(
            f"  {i}. {icon('pending', theme)} {t['id']}  {t.get('subject', '')}  "
            f"{pri}  {eff}  {st}",
            style=color("pending", theme),
        )
    console.print()


@backlog_app.command()
def query(
    tag: Optional[str] = typer.Option(None, "--tag", "-t"),
    status_filter: Optional[str] = typer.Option(None, "--status", "-s",
                                                 help="done|active|pending|blocked"),
    stream: Optional[str] = typer.Option(None, "--stream"),
    priority: Optional[str] = typer.Option(None, "--priority", "-p"),
    effort: Optional[str] = typer.Option(None, "--effort", "-e"),
    wide: bool = typer.Option(False, "--wide", "-w"),
):
    """Filter tasks with AND logic."""
    theme = get_theme()
    data = load_tasks()
    all_tasks = data.get("tasks", [])

    results = _filter_tasks(
        all_tasks, all_tasks,
        tag=tag, status_filter=status_filter, stream=stream,
        priority=priority, effort=effort,
    )

    if not results:
        console.print("\n  No tasks match the filters.\n")
        return

    if wide:
        table = create_table("", "ID", "Subject", "Status", "Tags", "Pri", "Eff", "Stream")
        for t in results:
            st = classify_task(t, all_tasks)
            tags = ", ".join((t.get("tags") or [])[:3])
            table.add_row(
                icon(st, theme), t["id"], t.get("subject", ""),
                st, tags, t.get("priority") or "—",
                t.get("effort") or "—", t.get("stream") or "—",
                style=color(st, theme),
            )
        console.print(table)
    else:
        for t in results:
            st = classify_task(t, all_tasks)
            console.print(f"  {task_line(t, st, theme)}", style=color(st, theme))

    console.print(f"\n  {len(results)} tasks\n")


@backlog_app.command()
def search(text: str = typer.Argument(..., help="Free-text search")):
    """Search across subjects, descriptions, and contexts."""
    theme = get_theme()
    data = load_tasks()
    all_tasks = data.get("tasks", [])
    needle = text.lower()

    results = []
    for t in all_tasks:
        if t.get("type") not in ("task", "subtask"):
            continue
        haystack = " ".join([
            t.get("subject", ""),
            t.get("description", ""),
            t.get("context") or "",
            t.get("notes") or "",
        ]).lower()
        if needle in haystack:
            results.append(t)

    if not results:
        console.print(f'\n  No tasks match "{text}".\n')
        return

    print_header(f'Search: "{text}"', theme)
    for t in results:
        st = classify_task(t, all_tasks)
        console.print(f"  {task_line(t, st, theme)}", style=color(st, theme))
    console.print(f"\n  {len(results)} tasks\n")


@backlog_app.command()
def focus(project: Optional[str] = typer.Option(None, "--project", "-p")):
    """Smart daily pick — weighs priority, staleness, effort, blocked depth."""
    theme = get_theme()
    data = load_tasks()
    all_tasks = data.get("tasks", [])

    candidates = [
        t for t in all_tasks
        if t.get("type") in ("task", "subtask")
        and classify_task(t, all_tasks) == "pending"
    ]

    if not candidates:
        console.print("\n  No actionable tasks.\n")
        return

    scored = [(t, _focus_score(t, all_tasks)) for t in candidates]
    scored.sort(key=lambda x: -x[1])
    top = scored[:3]

    print_header("Focus — today's pick", theme)
    for i, (t, score) in enumerate(top, 1):
        pri = priority_label(t.get("priority"), theme)
        eff = t.get("effort") or "—"
        console.print(
            f"  {i}. {icon('pending', theme)} {t['id']}  {t.get('subject', '')}  "
            f"{pri}  {eff}  (score: {score:.0f})",
            style=color("pending", theme),
        )
    console.print()


@backlog_app.command()
def blocked(project: Optional[str] = typer.Option(None, "--project", "-p")):
    """Show blocked dependency chains."""
    theme = get_theme()
    data = load_tasks()
    all_tasks = data.get("tasks", [])

    blocked_tasks = [
        t for t in all_tasks
        if t.get("type") in ("task", "subtask")
        and classify_task(t, all_tasks) == "blocked"
    ]

    if not blocked_tasks:
        console.print("\n  No blocked tasks.\n")
        return

    print_header("Blocked chains", theme)
    seen = set()
    for t in blocked_tasks:
        if t["id"] in seen:
            continue
        chain = _build_blocked_chain(t["id"], all_tasks)
        for depth, ct in chain:
            seen.add(ct["id"])
            st = classify_task(ct, all_tasks)
            indent = "  " + "    " * depth
            console.print(f"{indent}{task_line(ct, st, theme)}", style=color(st, theme))
        console.print()


@backlog_app.command()
def stale(days: int = typer.Option(14, "--days", "-d", help="Staleness threshold in days")):
    """Tasks pending > N days with no activity."""
    theme = get_theme()
    data = load_tasks()
    all_tasks = data.get("tasks", [])
    cutoff = (datetime.now() - timedelta(days=days)).strftime("%Y-%m-%d")

    stale_tasks = []
    for t in all_tasks:
        if t.get("type") not in ("task", "subtask"):
            continue
        if t.get("status") not in ("pending",):
            continue
        created = t.get("created", "9999-99-99")
        if created < cutoff:
            stale_tasks.append(t)

    stale_tasks.sort(key=lambda t: t.get("created", ""))

    if not stale_tasks:
        console.print(f"\n  No tasks pending > {days} days.\n")
        return

    print_header(f"Stale tasks (>{days} days)", theme)
    for t in stale_tasks:
        created = t.get("created")
        if not created:
            continue
        try:
            age = (datetime.now() - datetime.fromisoformat(created)).days
        except ValueError:
            continue
        st = classify_task(t, all_tasks)
        console.print(
            f"  {task_line(t, st, theme)}  ({age}d)",
            style=color(st, theme),
        )
    console.print(f"\n  {len(stale_tasks)} stale tasks\n")


@backlog_app.command()
def burndown(period: str = typer.Option("week", "--period", "-p", help="week or month")):
    """Completed vs created over time."""
    if period not in ("week", "month"):
        console.print(f"\n  Invalid period '{period}'. Use 'week' or 'month'.\n")
        raise typer.Exit(1)

    theme = get_theme()
    data = load_tasks()
    all_tasks = data.get("tasks", [])

    now = datetime.now()
    if period == "week":
        start = (now - timedelta(days=7)).strftime("%Y-%m-%d")
        label = "Last 7 days"
    else:
        start = (now - timedelta(days=30)).strftime("%Y-%m-%d")
        label = "Last 30 days"

    created = [t for t in all_tasks if (t.get("created") or "") >= start
               and t.get("type") in ("task", "subtask")]
    completed = [t for t in all_tasks if (t.get("completed") or "") >= start
                 and t.get("type") in ("task", "subtask")]

    print_header(f"Burndown — {label}", theme)
    console.print(f"  Created:   {len(created)}")
    console.print(f"  Completed: {len(completed)}")
    delta = len(completed) - len(created)
    direction = "↓" if delta > 0 else "↑" if delta < 0 else "="
    style = "green" if delta > 0 else "red" if delta < 0 else "yellow"
    console.print(f"  Net:       [{style}]{direction} {abs(delta)}[/]")
    console.print()


@backlog_app.command()
def diff():
    """Semantic diff of tasks.json since last commit."""
    theme = get_theme()
    tf = tasks_file_path()

    root = git_root()
    if root is None:
        console.print("\n  Not in a git repository.\n")
        return

    try:
        rel_path = tf.relative_to(root)
        result = subprocess.run(
            ["git", "show", f"HEAD:{rel_path}"],
            capture_output=True, text=True, check=True, cwd=root,
        )
        old_data = json.loads(result.stdout)
    except (subprocess.CalledProcessError, json.JSONDecodeError, ValueError):
        console.print("\n  Cannot diff — no previous commit or file not tracked.\n")
        return

    new_data = load_json(tf)
    if new_data is None:
        console.print("\n  tasks.json not found.\n")
        return

    old_tasks = {t["id"]: t for t in (old_data.get("tasks") or old_data) if isinstance(t, dict)}
    new_tasks = {t["id"]: t for t in (new_data.get("tasks") or new_data) if isinstance(t, dict)}

    added = set(new_tasks) - set(old_tasks)
    removed = set(old_tasks) - set(new_tasks)
    common = set(old_tasks) & set(new_tasks)

    changes = []
    for tid in sorted(added):
        t = new_tasks[tid]
        changes.append(f"  [green]+ {tid} {t.get('subject', '')} (added, {t.get('status', '?')})[/]")
    for tid in sorted(removed):
        t = old_tasks[tid]
        changes.append(f"  [red]- {tid} {t.get('subject', '')} (removed)[/]")
    for tid in sorted(common):
        old, new = old_tasks[tid], new_tasks[tid]
        diffs = []
        for field in ["status", "priority", "effort", "tags", "build_step", "strategy", "context"]:
            ov, nv = old.get(field), new.get(field)
            if ov != nv:
                diffs.append(f"{field}: {ov} → {nv}")
        if diffs:
            changes.append(f"  [yellow]~ {tid} {new.get('subject', '')}: {'; '.join(diffs)}[/]")

    if not changes:
        console.print("\n  No changes since last commit.\n")
        return

    print_header("Tasks diff (vs last commit)", theme)
    for line in changes:
        console.print(line)
    console.print(f"\n  {len(changes)} changes\n")


@backlog_app.command()
def context(task_id: str = typer.Argument(..., help="Task ID (e.g., t-428)")):
    """Print task context inline."""
    theme = get_theme()
    data = load_tasks()
    all_tasks = data.get("tasks", [])

    task = next((t for t in all_tasks if t["id"] == task_id), None)
    if task is None:
        console.print(f"\n  Task {task_id} not found.\n")
        raise typer.Exit(1)

    st = classify_task(task, all_tasks)
    print_header(f"{task_id} {task.get('subject', '')}", theme)
    console.print(f"  Status: {st}  Stream: {task.get('stream', '—')}  "
                  f"Priority: {priority_label(task.get('priority'), theme)}  "
                  f"Effort: {task.get('effort') or '—'}")

    ctx = task.get("context")
    if ctx:
        console.print(f"\n  [dim]Context:[/]")
        for line in ctx.split("\n"):
            console.print(f"    {line}")
    else:
        console.print(f"\n  [dim]No context set.[/]")

    notes = task.get("notes")
    if notes:
        console.print(f"\n  [dim]Notes:[/]")
        for line in notes.split("\n"):
            console.print(f"    {line}")

    desc = task.get("description")
    if desc:
        console.print(f"\n  [dim]Description:[/]")
        for line in desc.split("\n"):
            console.print(f"    {line}")

    console.print()


@backlog_app.command()
def graph(
    parent_id: str = typer.Argument(..., help="Phase or milestone ID"),
    depth: int = typer.Option(0, "--depth", "-d", help="Max depth (0=unlimited)"),
):
    """ASCII dependency graph for a phase or milestone."""
    theme = get_theme()
    data = load_tasks()
    all_tasks = data.get("tasks", [])

    parent = next((t for t in all_tasks if t["id"] == parent_id), None)
    if parent is None:
        console.print(f"\n  {parent_id} not found.\n")
        raise typer.Exit(1)

    tree = Tree(f"[bold]{parent_id} {parent.get('subject', '')}[/]")
    _build_tree(tree, parent_id, all_tasks, theme, depth, current_depth=1)
    console.print()
    console.print(tree)
    console.print()


def _build_tree(
    tree: Tree, parent_id: str, all_tasks: list[dict],
    theme: dict, max_depth: int, current_depth: int,
):
    children = [t for t in all_tasks if t.get("parent") == parent_id]
    for child in children:
        st = classify_task(child, all_tasks)
        label = f"[{color(st, theme)}]{icon(st, theme)} {child['id']}  {child.get('subject', '')}[/]"
        branch = tree.add(label)
        if max_depth == 0 or current_depth < max_depth:
            _build_tree(branch, child["id"], all_tasks, theme, max_depth, current_depth + 1)
