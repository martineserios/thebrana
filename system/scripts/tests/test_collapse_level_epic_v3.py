"""Unit + integration tests for system/scripts/migrate/collapse-level-epic-v3.py
(t-2312 / ADR-065 backlog v3 schema migration).

Loaded via importlib since the script's filename uses dashes (matches this
repo's migrate/ naming convention -- not meant to be imported as a module),
mirroring test_normalize_tags.py / test_audit_orphaned_active_epic.py.
"""
import importlib.util
import json
import pathlib
import subprocess

import pytest

SCRIPT_PATH = pathlib.Path(__file__).parent.parent / "migrate" / "collapse-level-epic-v3.py"
spec = importlib.util.spec_from_file_location("collapse_level_epic_v3", SCRIPT_PATH)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

resolve_type = mod.resolve_type
collapse_level = mod.collapse_level
is_epic_node_marker = mod.is_epic_node_marker
collect_epic_slugs = mod.collect_epic_slugs
find_existing_epic_nodes = mod.find_existing_epic_nodes
plan_epic_nodes = mod.plan_epic_nodes
retype_reused_nodes = mod.retype_reused_nodes
reparent_by_epic = mod.reparent_by_epic
drop_epic_keys = mod.drop_epic_keys
migrate = mod.migrate
next_id = mod.next_id
is_tasks_file_dirty = mod.is_tasks_file_dirty

TODAY = "2026-07-22"


def fake_next_id(tasks):
    return next_id(tasks)


# ── resolve_type / collapse_level (Transform 1) ──────────────────────────

def test_resolve_type_backfills_from_level_when_type_missing():
    assert resolve_type(None, "phase") == ("phase", True)


def test_resolve_type_backfills_from_level_when_type_empty_string():
    assert resolve_type("", "milestone") == ("milestone", True)


def test_resolve_type_type_wins_on_conflict():
    """ADR-065 D8: type survives -- more populated, ~ sole live conflict is
    t-1539 (level=milestone, type=task), resolved by keeping type."""
    assert resolve_type("task", "milestone") == ("task", False)


def test_resolve_type_type_wins_when_equal():
    assert resolve_type("task", "task") == ("task", False)


def test_resolve_type_both_absent_noop():
    assert resolve_type(None, None) == (None, False)


def test_collapse_level_backfill_and_drop():
    task = {"id": "t-1", "level": "phase"}
    backfilled, had_level = collapse_level(task)
    assert backfilled is True
    assert had_level is True
    assert task["type"] == "phase"
    assert "level" not in task


def test_collapse_level_conflicting_type_wins_level_still_dropped():
    task = {"id": "t-1539", "level": "milestone", "type": "task"}
    backfilled, had_level = collapse_level(task)
    assert backfilled is False, "type must win on conflict per ADR-065 D8"
    assert had_level is True
    assert task["type"] == "task"
    assert "level" not in task


def test_collapse_level_no_level_key_is_noop_besides_flags():
    task = {"id": "t-1", "type": "task"}
    backfilled, had_level = collapse_level(task)
    assert backfilled is False
    assert had_level is False
    assert task["type"] == "task"


def test_collapse_level_null_level_value_still_dropped():
    task = {"id": "t-1", "type": "task", "level": None}
    backfilled, had_level = collapse_level(task)
    assert backfilled is False
    assert had_level is True, "key presence (even null) counts as a drop"
    assert "level" not in task


# ── is_epic_node_marker / detection heuristic ─────────────────────────────

def test_marker_requires_in_prefix_and_epic():
    assert is_epic_node_marker({"id": "in-002", "epic": "cc-alignment"}) is True


def test_marker_rejects_t_prefix_even_with_type_initiative():
    """t-1608-shaped tasks: type=initiative but t- id and no level -- must
    NOT be treated as a node marker (weaker signal than the in- id scheme)."""
    assert is_epic_node_marker({"id": "t-1608", "type": "initiative", "epic": "backlog-git-alignment"}) is False


def test_marker_rejects_in_prefix_without_epic():
    assert is_epic_node_marker({"id": "in-005", "epic": None}) is False


# ── epic node creation (no existing marker) ───────────────────────────────

def test_epic_node_creation_no_existing_marker():
    tasks = [
        {"id": "t-1", "epic": "foo"},
        {"id": "t-2", "epic": "foo"},
        {"id": "t-3", "epic": "foo"},
    ]
    node_id_by_slug, new_nodes, reused, created = plan_epic_nodes(tasks, next_id, TODAY)
    assert created == ["foo"]
    assert reused == []
    assert len(new_nodes) == 1
    assert new_nodes[0]["subject"] == "foo"
    assert new_nodes[0]["type"] == "epic"
    assert node_id_by_slug["foo"] == new_nodes[0]["id"]


# ── epic node reuse (existing in- marker) ─────────────────────────────────

def test_epic_node_reuse_no_duplicate_created():
    tasks = [
        {"id": "in-099", "subject": "Foo", "type": "initiative", "epic": "foo"},
        {"id": "t-1", "epic": "foo"},
        {"id": "t-2", "epic": "foo"},
        {"id": "t-3", "epic": "foo"},
    ]
    node_id_by_slug, new_nodes, reused, created = plan_epic_nodes(tasks, next_id, TODAY)
    assert reused == ["foo"]
    assert created == []
    assert new_nodes == []
    assert node_id_by_slug["foo"] == "in-099"


def test_epic_node_reuse_retypes_marker_to_epic():
    tasks = [{"id": "in-099", "type": "initiative", "epic": "foo"}]
    node_id_by_slug, new_nodes, reused, created = plan_epic_nodes(tasks, next_id, TODAY)
    retyped = retype_reused_nodes(tasks, [node_id_by_slug[s] for s in reused])
    assert retyped == 1
    assert tasks[0]["type"] == "epic"


def test_retype_is_idempotent():
    tasks = [{"id": "in-099", "type": "epic", "epic": "foo"}]
    changed = retype_reused_nodes(tasks, ["in-099"])
    assert changed == 0


# ── re-parenting ───────────────────────────────────────────────────────────

def test_reparent_sets_parent_to_node_id():
    tasks = [{"id": "t-1", "epic": "foo"}, {"id": "t-2", "epic": "foo"}]
    node_id_by_slug = {"foo": "t-100"}
    count = reparent_by_epic(tasks, node_id_by_slug)
    assert count == 2
    assert tasks[0]["parent"] == "t-100"
    assert tasks[1]["parent"] == "t-100"


def test_reparent_skips_the_node_itself():
    tasks = [{"id": "t-100", "epic": "foo"}, {"id": "t-1", "epic": "foo"}]
    node_id_by_slug = {"foo": "t-100"}
    count = reparent_by_epic(tasks, node_id_by_slug)
    assert count == 1
    assert "parent" not in tasks[0] or tasks[0].get("parent") is None


def test_reparent_preserves_existing_parent():
    """714-task live-data finding: a task already parented under a
    milestone must NOT be silently re-homed under the epic node -- see
    module docstring 'Why parented tasks are not re-parented'."""
    tasks = [{"id": "t-1", "epic": "foo", "parent": "ms-010"}]
    node_id_by_slug = {"foo": "t-100"}
    count = reparent_by_epic(tasks, node_id_by_slug)
    assert count == 0
    assert tasks[0]["parent"] == "ms-010"


def test_reparent_ignores_tasks_without_epic():
    tasks = [{"id": "t-1"}]
    count = reparent_by_epic(tasks, {"foo": "t-100"})
    assert count == 0
    assert "parent" not in tasks[0]


# ── epic key exhaustive drop ────────────────────────────────────────────────

def test_drop_epic_keys_removes_from_all_including_nodes():
    tasks = [
        {"id": "in-099", "type": "initiative", "epic": "foo"},
        {"id": "t-1", "epic": "foo"},
        {"id": "t-2"},
    ]
    count = drop_epic_keys(tasks)
    assert count == 2
    assert all("epic" not in t for t in tasks)


# ── end-to-end migrate() ────────────────────────────────────────────────────

def test_migrate_end_to_end_new_node_and_reparent():
    tasks = [
        {"id": "t-1", "level": "phase", "epic": "foo"},
        {"id": "t-2", "type": "task", "epic": "foo", "parent": "ms-010"},
        {"id": "t-3", "epic": "bar"},
    ]
    report = migrate(tasks, next_id_fn=next_id, today=TODAY)

    assert report["level_backfilled"] == 1
    assert report["level_dropped"] == 1
    assert report["epic_slugs_found"] == 2
    assert report["epic_nodes_created"] == 2
    assert report["epic_nodes_reused"] == 0
    assert report["tasks_reparented"] == 2  # t-1 (no parent) + t-3 (no parent); t-2 keeps ms-010
    assert report["epic_keys_dropped"] == 3

    assert all("epic" not in t for t in tasks)
    assert all("level" not in t for t in tasks)
    t1 = next(t for t in tasks if t["id"] == "t-1")
    t2 = next(t for t in tasks if t["id"] == "t-2")
    assert t1["type"] == "phase"
    assert t1["parent"] != "ms-010"  # reparented to the new foo node
    assert t2["parent"] == "ms-010"  # preserved


def test_migrate_is_idempotent():
    tasks = [
        {"id": "t-1", "level": "phase", "epic": "foo"},
        {"id": "t-2", "epic": "foo", "parent": "ms-010"},
    ]
    first = migrate(tasks, next_id_fn=next_id, today=TODAY)
    assert any(v > 0 for v in first.values())

    second = migrate(tasks, next_id_fn=next_id, today=TODAY)
    assert all(v == 0 for v in second.values()), f"second run must report zero changes, got: {second}"


# ── dirty-repo refusal (integration, via subprocess) ────────────────────────

def _init_git_repo(tmp_path):
    subprocess.run(["git", "init", "-q"], cwd=tmp_path, check=True)
    subprocess.run(["git", "config", "user.email", "test@example.com"], cwd=tmp_path, check=True)
    subprocess.run(["git", "config", "user.name", "Test"], cwd=tmp_path, check=True)


def _write_tasks_json(tmp_path, tasks):
    claude_dir = tmp_path / ".claude"
    claude_dir.mkdir()
    tasks_path = claude_dir / "tasks.json"
    tasks_path.write_text(json.dumps({"version": 1, "project": "test", "tasks": tasks}, indent=2))
    return tasks_path


@pytest.fixture
def git_repo_with_tasks(tmp_path):
    _init_git_repo(tmp_path)
    tasks = [{"id": "t-1", "subject": "x", "level": "phase", "epic": "foo", "status": "pending", "type": "phase"}]
    tasks_path = _write_tasks_json(tmp_path, tasks)
    subprocess.run(["git", "add", "-A"], cwd=tmp_path, check=True)
    subprocess.run(["git", "commit", "-q", "-m", "init"], cwd=tmp_path, check=True)
    return tmp_path, tasks_path


def test_dirty_repo_refuses_write(git_repo_with_tasks):
    tmp_path, tasks_path = git_repo_with_tasks
    tasks_path.write_text(tasks_path.read_text() + "\n")  # dirty the file
    before = tasks_path.read_text()

    result = subprocess.run(
        ["python3", str(SCRIPT_PATH), "--write"],
        cwd=tmp_path, capture_output=True, text=True,
    )
    assert result.returncode != 0
    assert tasks_path.read_text() == before, "dirty-repo refusal must not write"


def test_dry_run_works_on_dirty_repo(git_repo_with_tasks):
    tmp_path, tasks_path = git_repo_with_tasks
    tasks_path.write_text(tasks_path.read_text() + "\n")  # dirty the file

    result = subprocess.run(
        ["python3", str(SCRIPT_PATH)],
        cwd=tmp_path, capture_output=True, text=True,
    )
    assert result.returncode == 0
    assert "Dry-run only" in result.stdout


def test_write_succeeds_on_clean_repo(git_repo_with_tasks):
    tmp_path, tasks_path = git_repo_with_tasks

    result = subprocess.run(
        ["python3", str(SCRIPT_PATH), "--write"],
        cwd=tmp_path, capture_output=True, text=True,
    )
    assert result.returncode == 0, result.stderr
    written = json.loads(tasks_path.read_text())
    written_tasks = written["tasks"]
    assert all("level" not in t and "epic" not in t for t in written_tasks)


def test_is_tasks_file_dirty_true_when_file_changed(git_repo_with_tasks):
    tmp_path, tasks_path = git_repo_with_tasks
    tasks_path.write_text(tasks_path.read_text() + "\n")
    assert is_tasks_file_dirty(tasks_path) is True


def test_is_tasks_file_dirty_false_on_clean_repo(git_repo_with_tasks):
    _, tasks_path = git_repo_with_tasks
    assert is_tasks_file_dirty(tasks_path) is False


# ── next_id parity with brana-core ──────────────────────────────────────────

def test_next_id_ignores_prefix_scheme():
    tasks = [{"id": "in-004"}, {"id": "t-2311"}, {"id": "ms-019"}]
    assert next_id(tasks) == "t-2312"


def test_next_id_empty_list():
    assert next_id([]) == "t-1"
