"""Theme system — loads themes.json, provides Rich styling helpers."""

from __future__ import annotations

import json
from functools import lru_cache
from pathlib import Path
from typing import Any

from rich.console import Console
from rich.table import Table
from rich.text import Text
from rich.tree import Tree

from .config import load_theme_name

THEMES_FILE = Path(__file__).parent / "themes.json"
console = Console()


@lru_cache(maxsize=1)
def load_themes() -> dict[str, Any]:
    return json.loads(THEMES_FILE.read_text())


def get_theme() -> dict[str, Any]:
    themes = load_themes()
    name = load_theme_name()
    return themes.get(name, themes["classic"])


def icon(status: str, theme: dict | None = None) -> str:
    if theme is None:
        theme = get_theme()
    return theme.get("icons", {}).get(status, "?")


def color(status: str, theme: dict | None = None) -> str:
    if theme is None:
        theme = get_theme()
    return theme.get("colors", {}).get(status, "white")


def progress_bar(done: int, total: int, width: int = 8, theme: dict | None = None) -> str:
    if theme is None:
        theme = get_theme()
    if total == 0:
        return ""
    fill_char = theme.get("bars", {}).get("fill", "█")
    empty_char = theme.get("bars", {}).get("empty", "░")
    filled = round(done / total * width)
    return fill_char * filled + empty_char * (width - filled) + f" {done}/{total}"


def task_line(task: dict, status: str, theme: dict | None = None, show_tags: bool = True) -> str:
    if theme is None:
        theme = get_theme()
    ic = icon(status, theme)
    subject = task.get("subject", "untitled")
    parts = [f"{ic} {task['id']}  {subject}"]

    tags = task.get("tags") or []
    if show_tags and tags:
        tag_str = ", ".join(tags[:3])
        if len(tags) > 3:
            tag_str += f" +{len(tags) - 3}"
        parts.append(f"[{tag_str}]")

    detail = ""
    if status == "blocked":
        blocked_by = task.get("blocked_by", [])
        ref = theme.get("blocked_ref", "blocked by")
        detail = f"  {ref} {', '.join(blocked_by)}"
    elif status == "done" and task.get("completed"):
        detail = f"  completed {task['completed']}"
    elif status == "active" and task.get("build_step"):
        detail = f"  [{task['build_step'].upper()}]"

    return " ".join(parts) + detail


def styled_task_line(task: dict, status: str, theme: dict | None = None) -> Text:
    if theme is None:
        theme = get_theme()
    line = task_line(task, status, theme)
    return Text(line, style=color(status, theme))


def priority_label(pri: str | None, theme: dict | None = None) -> str:
    if pri is None:
        return "—"
    if theme is None:
        theme = get_theme()
    if pri in ("P0", "P1") and "priority_high" in theme:
        return f"{theme['priority_high']}{pri}"
    return pri


def print_header(text: str, theme: dict | None = None):
    if theme is None:
        theme = get_theme()
    console.print(f"\n[{color('header', theme)}]{text}[/]")


def create_table(*columns: str, title: str | None = None) -> Table:
    table = Table(title=title, show_header=True, header_style="bold cyan",
                  pad_edge=False, show_edge=False)
    for col in columns:
        table.add_column(col)
    return table
