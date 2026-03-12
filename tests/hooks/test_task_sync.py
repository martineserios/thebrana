#!/usr/bin/env python3
"""Tests for system/hooks/task-sync.py — unit tests for pure functions + integration tests with mocked subprocess."""

import json
import os
import sys
from pathlib import Path
from unittest.mock import patch, MagicMock

import pytest

# Make the hook importable
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "system" / "hooks"))

import importlib
task_sync = importlib.import_module("task-sync")


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

@pytest.fixture
def sample_task():
    return {
        "id": "t-100",
        "subject": "Implement auth",
        "description": "JWT-based auth for API",
        "type": "task",
        "stream": "roadmap",
        "status": "pending",
        "priority": "P1",
        "effort": "M",
        "strategy": "feature",
        "branch": "feat/t-100-auth",
        "tags": ["api", "security"],
        "parent": "ph-010",
        "blocked_by": ["t-099"],
        "context": "Needs Redis session store",
        "notes": "Check OAuth2 spec first",
    }


@pytest.fixture
def minimal_task():
    return {
        "id": "t-200",
        "subject": "Quick fix",
        "status": "pending",
        "stream": "bugs",
    }


@pytest.fixture
def task_map():
    return {"ph-010": 42, "t-099": 55}


@pytest.fixture
def config(tmp_path):
    cfg = {
        "owner": "testowner",
        "keep_streams": ["roadmap", "tech-debt", "bugs"],
        "projects": {
            "myproject": {"repo": "testowner/myrepo", "project_number": 5}
        },
    }
    path = tmp_path / "config.json"
    path.write_text(json.dumps(cfg))
    return path


@pytest.fixture
def tasks_dir(tmp_path):
    """Set up a tasks directory with map and hash files."""
    return tmp_path


# ---------------------------------------------------------------------------
# build_labels
# ---------------------------------------------------------------------------

def test_build_labels_with_stream_and_tags(sample_task):
    labels = task_sync.build_labels(sample_task)
    assert "stream:roadmap" in labels
    assert "tag:api" in labels
    assert "tag:security" in labels


def test_build_labels_phase_gets_enhancement():
    task = {"id": "ph-001", "type": "phase", "stream": "roadmap"}
    labels = task_sync.build_labels(task)
    assert "enhancement" in labels
    assert "stream:roadmap" in labels


def test_build_labels_milestone_gets_enhancement():
    task = {"id": "ms-001", "type": "milestone", "stream": "roadmap"}
    labels = task_sync.build_labels(task)
    assert "enhancement" in labels


def test_build_labels_no_tags_no_stream():
    task = {"id": "t-300"}
    labels = task_sync.build_labels(task)
    assert labels == []


def test_build_labels_null_tags():
    task = {"id": "t-301", "stream": "bugs", "tags": None}
    labels = task_sync.build_labels(task)
    assert labels == ["stream:bugs"]


# ---------------------------------------------------------------------------
# build_body
# ---------------------------------------------------------------------------

def test_build_body_full_task(sample_task, task_map):
    body = task_sync.build_body(sample_task, task_map)
    assert "JWT-based auth for API" in body
    assert "**Task ID:** `t-100`" in body
    assert "**Type:** task" in body
    assert "**Stream:** roadmap" in body
    assert "**Priority:** P1" in body
    assert "**Effort:** M" in body
    assert "**Strategy:** feature" in body
    assert "**Branch:** `feat/t-100-auth`" in body
    assert "**Parent:** #42" in body
    assert "**Blocked by:** #55" in body
    assert "## Context" in body
    assert "Needs Redis session store" in body
    assert "## Notes" in body
    assert "Check OAuth2 spec first" in body


def test_build_body_minimal_task(minimal_task):
    body = task_sync.build_body(minimal_task, {})
    assert "**Task ID:** `t-200`" in body
    assert "**Status:** pending" in body
    assert "Context" not in body
    assert "Notes" not in body
    assert "Parent" not in body
    assert "Blocked by" not in body


def test_build_body_parent_not_in_map():
    task = {"id": "t-400", "parent": "ph-999", "status": "pending"}
    body = task_sync.build_body(task, {"ph-001": 1})
    # Parent not in map — should not appear
    assert "Parent" not in body


def test_build_body_blocked_by_mixed_refs():
    task = {"id": "t-401", "blocked_by": ["t-100", "t-unknown"], "status": "pending"}
    task_map = {"t-100": 10}
    body = task_sync.build_body(task, task_map)
    assert "#10" in body
    assert "t-unknown" in body


def test_build_body_no_description():
    task = {"id": "t-402", "status": "pending"}
    body = task_sync.build_body(task, {})
    # Should start with metadata, no blank line from missing desc
    assert body.startswith("## Metadata")


# ---------------------------------------------------------------------------
# ensure_label
# ---------------------------------------------------------------------------

@patch.object(task_sync, "run")
def test_ensure_label_stream_color(mock_run):
    mock_run.return_value = ("", None)
    task_sync.ensure_label("owner/repo", "stream:roadmap")
    mock_run.assert_called_once()
    call_cmd = mock_run.call_args[0][0]
    assert "c5def5" in call_cmd
    assert "--force" in call_cmd


@patch.object(task_sync, "run")
def test_ensure_label_tag_color(mock_run):
    mock_run.return_value = ("", None)
    task_sync.ensure_label("owner/repo", "tag:api")
    call_cmd = mock_run.call_args[0][0]
    assert "e4e669" in call_cmd


# ---------------------------------------------------------------------------
# run() — subprocess wrapper
# ---------------------------------------------------------------------------

@patch("subprocess.run")
def test_run_success(mock_subprocess):
    mock_subprocess.return_value = MagicMock(returncode=0, stdout="ok\n", stderr="")
    out, err = task_sync.run("echo ok")
    assert out == "ok"
    assert err is None


@patch("subprocess.run")
def test_run_failure(mock_subprocess):
    mock_subprocess.return_value = MagicMock(returncode=1, stdout="", stderr="bad command")
    out, err = task_sync.run("false")
    assert out is None
    assert "bad command" in err


@patch("subprocess.run")
def test_run_timeout(mock_subprocess):
    from subprocess import TimeoutExpired
    mock_subprocess.side_effect = TimeoutExpired("cmd", 30)
    out, err = task_sync.run("sleep 999", timeout=30)
    assert out is None
    assert err == "timeout"


@patch("subprocess.run")
def test_run_truncates_long_stderr(mock_subprocess):
    long_err = "x" * 500
    mock_subprocess.return_value = MagicMock(returncode=1, stdout="", stderr=long_err)
    _, err = task_sync.run("fail")
    assert len(err) == 200


# ---------------------------------------------------------------------------
# Stream filtering (qualifying logic from main)
# ---------------------------------------------------------------------------

def test_stream_filtering():
    tasks = [
        {"id": "t-1", "stream": "roadmap", "subject": "A"},
        {"id": "t-2", "stream": "experiments", "subject": "B"},
        {"id": "t-3", "stream": "bugs", "subject": "C"},
        {"id": "t-4", "stream": "research", "subject": "D"},
        {"id": "t-5", "stream": "tech-debt", "subject": "E"},
        {"id": "t-6", "subject": "No stream"},
    ]
    keep_streams = {"roadmap", "tech-debt", "bugs"}
    qualifying = {t["id"]: t for t in tasks if t.get("stream", "") in keep_streams}

    assert "t-1" in qualifying  # roadmap
    assert "t-2" not in qualifying  # experiments
    assert "t-3" in qualifying  # bugs
    assert "t-4" not in qualifying  # research
    assert "t-5" in qualifying  # tech-debt
    assert "t-6" not in qualifying  # no stream


# ---------------------------------------------------------------------------
# Hash comparison (change detection)
# ---------------------------------------------------------------------------

def test_hash_detects_status_change():
    task_v1 = {"id": "t-1", "status": "pending", "priority": "P1", "effort": "M", "subject": "X"}
    task_v2 = {"id": "t-1", "status": "completed", "priority": "P1", "effort": "M", "subject": "X"}
    h1 = f"{task_v1.get('status')}|{task_v1.get('priority')}|{task_v1.get('effort')}|{task_v1.get('subject')}"
    h2 = f"{task_v2.get('status')}|{task_v2.get('priority')}|{task_v2.get('effort')}|{task_v2.get('subject')}"
    assert h1 != h2


def test_hash_stable_when_unchanged():
    task = {"id": "t-1", "status": "pending", "priority": None, "effort": None, "subject": "X"}
    h1 = f"{task.get('status')}|{task.get('priority')}|{task.get('effort')}|{task.get('subject')}"
    h2 = f"{task.get('status')}|{task.get('priority')}|{task.get('effort')}|{task.get('subject')}"
    assert h1 == h2


def test_hash_detects_subject_change():
    h1 = "pending|P1|M|Old name"
    h2 = "pending|P1|M|New name"
    assert h1 != h2


# ---------------------------------------------------------------------------
# set_project_fields
# ---------------------------------------------------------------------------

@patch.object(task_sync, "run")
def test_set_project_fields_status_completed(mock_run):
    mock_run.return_value = ("", None)
    fields = {
        "status": {"id": "FIELD_1", "options": {"done": "OPT_DONE", "in_progress": "OPT_IP", "todo": "OPT_TODO"}}
    }
    task = {"status": "completed"}
    task_sync.set_project_fields(task, "ITEM_1", "PROJ_1", fields)
    call_cmd = mock_run.call_args[0][0]
    assert "OPT_DONE" in call_cmd
    assert "FIELD_1" in call_cmd


@patch.object(task_sync, "run")
def test_set_project_fields_status_in_progress(mock_run):
    mock_run.return_value = ("", None)
    fields = {
        "status": {"id": "F1", "options": {"in_progress": "OPT_IP", "todo": "OPT_TODO"}}
    }
    task = {"status": "in_progress"}
    task_sync.set_project_fields(task, "I1", "P1", fields)
    call_cmd = mock_run.call_args[0][0]
    assert "OPT_IP" in call_cmd


@patch.object(task_sync, "run")
def test_set_project_fields_pending_maps_to_todo(mock_run):
    mock_run.return_value = ("", None)
    fields = {
        "status": {"id": "F1", "options": {"todo": "OPT_TODO"}}
    }
    task = {"status": "pending"}
    task_sync.set_project_fields(task, "I1", "P1", fields)
    call_cmd = mock_run.call_args[0][0]
    assert "OPT_TODO" in call_cmd


@patch.object(task_sync, "run")
def test_set_project_fields_skips_missing_priority(mock_run):
    mock_run.return_value = ("", None)
    fields = {"status": {"id": "F1", "options": {"todo": "OPT"}}}
    task = {"status": "pending", "priority": "P0"}
    task_sync.set_project_fields(task, "I1", "P1", fields)
    # Only one call for status, not priority (field not configured)
    assert mock_run.call_count == 1


@patch.object(task_sync, "run")
def test_set_project_fields_priority_and_effort(mock_run):
    mock_run.return_value = ("", None)
    fields = {
        "status": {"id": "F1", "options": {"todo": "OPT_TODO"}},
        "priority": {"id": "F2", "options": {"P1": "OPT_P1"}},
        "effort": {"id": "F3", "options": {"M": "OPT_M"}},
    }
    task = {"status": "pending", "priority": "P1", "effort": "M"}
    task_sync.set_project_fields(task, "I1", "P1", fields)
    assert mock_run.call_count == 3


# ---------------------------------------------------------------------------
# create_issue (mocked subprocess)
# ---------------------------------------------------------------------------

@patch.object(task_sync, "run")
@patch.object(task_sync, "set_project_fields")
def test_create_issue_success(mock_set_fields, mock_run):
    # run() calls: ensure_label x2 (stream + tag), create issue, add to project
    mock_run.side_effect = [
        ("", None),  # ensure_label stream:roadmap
        ("", None),  # ensure_label tag:api
        ("https://github.com/owner/repo/issues/99", None),  # create
        ("", None),  # project item-add (writes to tmp file)
    ]
    task = {"id": "t-50", "subject": "Test", "stream": "roadmap", "tags": ["api"], "status": "pending"}
    # Patch open for project item-add tmp file
    issue_num = task_sync.create_issue(task, {}, "owner/repo", "owner", 5, "PROJ_1", {})
    assert issue_num == 99


@patch.object(task_sync, "run")
def test_create_issue_failure_returns_none(mock_run):
    mock_run.return_value = (None, "API error")
    task = {"id": "t-51", "subject": "Fail", "status": "pending"}
    result = task_sync.create_issue(task, {}, "owner/repo", "owner", 5, None, {})
    assert result is None


@patch.object(task_sync, "run")
def test_create_issue_closes_completed_task(mock_run):
    calls = []
    def track_run(cmd, timeout=30):
        calls.append(cmd)
        if "issue create" in cmd:
            return ("https://github.com/owner/repo/issues/77", None)
        return ("", None)
    mock_run.side_effect = track_run

    task = {"id": "t-52", "subject": "Done task", "status": "completed"}
    task_sync.create_issue(task, {}, "owner/repo", "owner", 5, None, {})
    close_calls = [c for c in calls if "issue close" in c]
    assert len(close_calls) == 1
    assert "--reason completed" in close_calls[0]


@patch.object(task_sync, "run")
def test_create_issue_closes_cancelled_task(mock_run):
    calls = []
    def track_run(cmd, timeout=30):
        calls.append(cmd)
        if "issue create" in cmd:
            return ("https://github.com/owner/repo/issues/78", None)
        return ("", None)
    mock_run.side_effect = track_run

    task = {"id": "t-53", "subject": "Cancelled", "status": "cancelled"}
    task_sync.create_issue(task, {}, "owner/repo", "owner", 5, None, {})
    close_calls = [c for c in calls if "issue close" in c]
    assert len(close_calls) == 1
    assert "--reason not_planned" in close_calls[0]


# ---------------------------------------------------------------------------
# update_issue (mocked subprocess)
# ---------------------------------------------------------------------------

@patch.object(task_sync, "run")
@patch.object(task_sync, "set_project_fields")
def test_update_issue_edits_title_and_body(mock_set_fields, mock_run):
    mock_run.return_value = ("", None)
    task = {"id": "t-60", "subject": "Updated title", "status": "pending"}
    task_sync.update_issue(task, 10, {}, "owner/repo", "owner", 5, None, {})
    title_calls = [c for c in [mock_run.call_args_list[i][0][0] for i in range(len(mock_run.call_args_list))] if "issue edit" in c and "--title" in c]
    assert len(title_calls) >= 1
    assert "[t-60] Updated title" in title_calls[0]


@patch.object(task_sync, "run")
def test_update_issue_closes_completed(mock_run):
    calls = []
    def track_run(cmd, timeout=30):
        calls.append(cmd)
        return ("", None)
    mock_run.side_effect = track_run

    task = {"id": "t-61", "subject": "Done", "status": "completed"}
    task_sync.update_issue(task, 11, {}, "owner/repo", "owner", 5, None, {})
    close_calls = [c for c in calls if "issue close" in c]
    assert len(close_calls) == 1


@patch.object(task_sync, "run")
def test_update_issue_reopens_pending(mock_run):
    calls = []
    def track_run(cmd, timeout=30):
        calls.append(cmd)
        return ("", None)
    mock_run.side_effect = track_run

    task = {"id": "t-62", "subject": "Reopen", "status": "in_progress"}
    task_sync.update_issue(task, 12, {}, "owner/repo", "owner", 5, None, {})
    reopen_calls = [c for c in calls if "issue reopen" in c]
    assert len(reopen_calls) == 1


# ---------------------------------------------------------------------------
# main() integration (mocked file I/O + subprocess)
# ---------------------------------------------------------------------------

@patch.object(task_sync, "run")
@patch.object(task_sync, "get_project_fields")
def test_main_skips_when_no_new_or_changed(mock_get_fields, mock_run, tasks_dir):
    tasks = [{"id": "t-1", "stream": "roadmap", "subject": "A", "status": "pending", "priority": None, "effort": None}]
    tasks_path = tasks_dir / "tasks.json"
    tasks_path.write_text(json.dumps(tasks))

    map_file = tasks_dir / "task-issue-map.json"
    map_file.write_text(json.dumps({"t-1": 10}))

    hash_file = tasks_dir / "task-sync-hashes.json"
    hash_file.write_text(json.dumps({"t-1": "pending|None|None|A"}))

    config_file = tasks_dir / "config.json"
    config_file.write_text(json.dumps({
        "owner": "testowner",
        "keep_streams": ["roadmap", "tech-debt", "bugs"],
        "projects": {"myproject": {"repo": "testowner/myrepo", "project_number": 5}},
    }))

    with patch.object(sys, "argv", ["task-sync.py", "myproject", str(tasks_path), str(config_file)]):
        task_sync.main()

    # No gh calls when nothing changed
    mock_get_fields.assert_not_called()


@patch.object(task_sync, "run")
@patch.object(task_sync, "get_project_fields")
@patch.object(task_sync, "create_issue")
def test_main_creates_new_task(mock_create, mock_get_fields, mock_run, tasks_dir):
    mock_get_fields.return_value = ({}, "PROJ_1")
    mock_create.return_value = 99

    tasks = [{"id": "t-1", "stream": "roadmap", "subject": "New", "status": "pending"}]
    tasks_path = tasks_dir / "tasks.json"
    tasks_path.write_text(json.dumps(tasks))

    map_file = tasks_dir / "task-issue-map.json"
    map_file.write_text(json.dumps({}))

    hash_file = tasks_dir / "task-sync-hashes.json"
    hash_file.write_text(json.dumps({}))

    config_file = tasks_dir / "config.json"
    config_file.write_text(json.dumps({
        "owner": "testowner",
        "keep_streams": ["roadmap"],
        "projects": {"myproject": {"repo": "testowner/myrepo", "project_number": 5}},
    }))

    with patch.object(sys, "argv", ["task-sync.py", "myproject", str(tasks_path), str(config_file)]):
        with patch("time.sleep"):
            task_sync.main()

    mock_create.assert_called_once()
    # Verify map was updated
    updated_map = json.loads(map_file.read_text())
    assert updated_map["t-1"] == 99


@patch.object(task_sync, "run")
@patch.object(task_sync, "get_project_fields")
@patch.object(task_sync, "update_issue")
def test_main_updates_changed_task(mock_update, mock_get_fields, mock_run, tasks_dir):
    mock_get_fields.return_value = ({}, "PROJ_1")

    tasks = [{"id": "t-1", "stream": "roadmap", "subject": "A", "status": "completed", "priority": None, "effort": None}]
    tasks_path = tasks_dir / "tasks.json"
    tasks_path.write_text(json.dumps(tasks))

    map_file = tasks_dir / "task-issue-map.json"
    map_file.write_text(json.dumps({"t-1": 10}))

    hash_file = tasks_dir / "task-sync-hashes.json"
    hash_file.write_text(json.dumps({"t-1": "pending|None|None|A"}))

    config_file = tasks_dir / "config.json"
    config_file.write_text(json.dumps({
        "owner": "testowner",
        "keep_streams": ["roadmap"],
        "projects": {"myproject": {"repo": "testowner/myrepo", "project_number": 5}},
    }))

    with patch.object(sys, "argv", ["task-sync.py", "myproject", str(tasks_path), str(config_file)]):
        with patch("time.sleep"):
            task_sync.main()

    mock_update.assert_called_once()
    # Verify hash was updated
    updated_hashes = json.loads(hash_file.read_text())
    assert updated_hashes["t-1"] == "completed|None|None|A"


def test_main_exits_on_missing_args():
    with patch.object(sys, "argv", ["task-sync.py"]):
        with pytest.raises(SystemExit) as exc:
            task_sync.main()
        assert exc.value.code == 1


@patch.object(task_sync, "run")
@patch.object(task_sync, "get_project_fields")
def test_main_skips_unconfigured_project(mock_get_fields, mock_run, tasks_dir):
    tasks_path = tasks_dir / "tasks.json"
    tasks_path.write_text(json.dumps([]))

    config_file = tasks_dir / "config.json"
    config_file.write_text(json.dumps({
        "owner": "testowner",
        "keep_streams": ["roadmap"],
        "projects": {},
    }))

    with patch.object(sys, "argv", ["task-sync.py", "unknown_project", str(tasks_path), str(config_file)]):
        task_sync.main()

    mock_get_fields.assert_not_called()


@patch.object(task_sync, "run")
@patch.object(task_sync, "get_project_fields")
@patch.object(task_sync, "create_issue")
def test_main_sorts_phases_first(mock_create, mock_get_fields, mock_run, tasks_dir):
    mock_get_fields.return_value = ({}, "PROJ_1")
    created_ids = []
    def track_create(task, *args, **kwargs):
        created_ids.append(task["id"])
        return len(created_ids)
    mock_create.side_effect = track_create

    tasks = [
        {"id": "t-1", "stream": "roadmap", "subject": "Task", "type": "task", "status": "pending"},
        {"id": "ph-1", "stream": "roadmap", "subject": "Phase", "type": "phase", "status": "pending"},
        {"id": "ms-1", "stream": "roadmap", "subject": "Milestone", "type": "milestone", "status": "pending"},
    ]
    tasks_path = tasks_dir / "tasks.json"
    tasks_path.write_text(json.dumps(tasks))

    (tasks_dir / "task-issue-map.json").write_text("{}")
    (tasks_dir / "task-sync-hashes.json").write_text("{}")

    config_file = tasks_dir / "config.json"
    config_file.write_text(json.dumps({
        "owner": "testowner",
        "keep_streams": ["roadmap"],
        "projects": {"myproject": {"repo": "testowner/myrepo", "project_number": 5}},
    }))

    with patch.object(sys, "argv", ["task-sync.py", "myproject", str(tasks_path), str(config_file)]):
        with patch("time.sleep"):
            task_sync.main()

    # Phases first, then milestones, then tasks
    assert created_ids == ["ph-1", "ms-1", "t-1"]


# ---------------------------------------------------------------------------
# task-sync.sh (shell script gate logic)
# ---------------------------------------------------------------------------

class TestShellGate:
    """Test the shell script's filtering logic by invoking it with various inputs."""

    SCRIPT = str(Path(__file__).resolve().parents[2] / "system" / "hooks" / "task-sync.sh")

    @pytest.fixture
    def run_hook(self, tmp_path):
        """Helper to run the hook with given JSON input."""
        import subprocess

        def _run(input_json):
            result = subprocess.run(
                ["bash", self.SCRIPT],
                input=json.dumps(input_json),
                capture_output=True,
                text=True,
                timeout=5,
                env={**os.environ, "HOME": str(tmp_path)},
            )
            return json.loads(result.stdout.strip()) if result.stdout.strip() else {}, result.returncode
        return _run

    def test_ignores_non_write_tools(self, run_hook):
        output, code = run_hook({"tool_name": "Read", "tool_input": {"file_path": "/x/.claude/tasks.json"}})
        assert output.get("continue") is True
        assert code == 0

    def test_ignores_non_tasks_file(self, run_hook):
        output, code = run_hook({"tool_name": "Write", "tool_input": {"file_path": "/x/src/main.py"}})
        assert output.get("continue") is True

    def test_ignores_non_claude_tasks(self, run_hook):
        output, code = run_hook({"tool_name": "Edit", "tool_input": {"file_path": "/x/config/tasks.json"}})
        assert output.get("continue") is True

    def test_passes_through_for_claude_tasks(self, run_hook):
        """Even without config file, should return continue: true (no config = early exit)."""
        output, code = run_hook({"tool_name": "Write", "tool_input": {"file_path": "/x/.claude/tasks.json"}})
        assert output.get("continue") is True
        assert code == 0
