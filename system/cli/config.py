"""Shared configuration — paths, JSON loading, project detection."""

from __future__ import annotations

import json
import subprocess
from pathlib import Path
from typing import Any


HOME = Path.home()
CLAUDE_DIR = HOME / ".claude"
TASKS_CONFIG = CLAUDE_DIR / "tasks-config.json"
PORTFOLIO_FILE = CLAUDE_DIR / "tasks-portfolio.json"
SCHEDULER_CONFIG = CLAUDE_DIR / "scheduler" / "scheduler.json"
SCHEDULER_STATUS = CLAUDE_DIR / "scheduler" / "last-status.json"
SCHEDULER_LOGS = CLAUDE_DIR / "scheduler" / "logs"
SCHEDULER_TEMPLATE = Path(__file__).parent.parent / "scheduler" / "scheduler.template.json"


def git_root() -> Path | None:
    try:
        result = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            capture_output=True, text=True, check=True,
        )
        return Path(result.stdout.strip())
    except (subprocess.CalledProcessError, FileNotFoundError):
        return None


def detect_project() -> tuple[Path | None, str]:
    root = git_root()
    if root is None:
        return None, "unknown"
    return root, root.name


def load_json(path: Path) -> Any:
    if not path.exists():
        return None
    text = path.read_text().strip()
    if not text:
        return None
    return json.loads(text)


def load_tasks(project_root: Path | None = None) -> dict:
    if project_root is None:
        project_root, _ = detect_project()
    if project_root is None:
        return {"project": "unknown", "tasks": []}
    tasks_file = project_root / ".claude" / "tasks.json"
    data = load_json(tasks_file)
    if data is None:
        return {"project": "unknown", "tasks": []}
    if isinstance(data, list):
        return {"project": "unknown", "tasks": data}
    return data


def load_portfolio() -> list[dict]:
    data = load_json(PORTFOLIO_FILE)
    if data is None:
        return []
    if "clients" in data:
        projects = []
        for client in data["clients"]:
            for proj in client.get("projects", []):
                proj = dict(proj)
                proj["_client"] = client["slug"]
                proj["path"] = str(Path(proj["path"].replace("~/", str(HOME) + "/")).expanduser())
                projects.append(proj)
        return projects
    if "projects" in data:
        projects = []
        for proj in data["projects"]:
            proj = dict(proj)
            proj["path"] = str(Path(proj["path"].replace("~/", str(HOME) + "/")).expanduser())
            projects.append(proj)
        return projects
    return []


def load_theme_name() -> str:
    cfg = load_json(TASKS_CONFIG)
    if cfg and "theme" in cfg:
        return cfg["theme"]
    return "classic"


def tasks_file_path(project_root: Path | None = None) -> Path:
    if project_root is None:
        project_root, _ = detect_project()
    if project_root is None:
        return Path(".claude/tasks.json")
    return project_root / ".claude" / "tasks.json"


def classify_task(task: dict, all_tasks: list[dict]) -> str:
    if task.get("status") == "completed":
        return "done"
    if task.get("status") == "in_progress":
        return "active"
    blocked_by = task.get("blocked_by") or []
    if blocked_by:
        completed_ids = {t["id"] for t in all_tasks if t.get("status") == "completed"}
        if not all(bid in completed_ids for bid in blocked_by):
            return "blocked"
    if "parked" in (task.get("tags") or []):
        return "parked"
    return "pending"
