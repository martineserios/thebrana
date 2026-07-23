"""Unit tests for system/scripts/migrate/drop-stream-field-v3.py
(t-2325 / ADR-065 backlog v3 schema cleanup).

Loaded via importlib since the script's filename uses dashes (matches this
repo's migrate/ naming convention), mirroring test_collapse_level_epic_v3.py.
"""
import importlib.util
import pathlib

SCRIPT_PATH = pathlib.Path(__file__).parent.parent / "migrate" / "drop-stream-field-v3.py"
spec = importlib.util.spec_from_file_location("drop_stream_field_v3", SCRIPT_PATH)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

drop_stream_keys = mod.drop_stream_keys


def test_drop_stream_keys_removes_field():
    tasks = [{"id": "t-1", "stream": "dev"}, {"id": "t-2", "stream": "ops"}]
    dropped = drop_stream_keys(tasks)
    assert dropped == 2
    assert "stream" not in tasks[0]
    assert "stream" not in tasks[1]


def test_drop_stream_keys_leaves_tasks_without_stream_untouched():
    tasks = [{"id": "t-1", "priority": "P2"}]
    dropped = drop_stream_keys(tasks)
    assert dropped == 0
    assert tasks[0] == {"id": "t-1", "priority": "P2"}


def test_drop_stream_keys_mixed():
    tasks = [{"id": "t-1", "stream": "dev"}, {"id": "t-2"}]
    dropped = drop_stream_keys(tasks)
    assert dropped == 1
    assert "stream" not in tasks[0]
    assert tasks[1] == {"id": "t-2"}


def test_drop_stream_keys_idempotent():
    tasks = [{"id": "t-1", "stream": "dev"}]
    first = drop_stream_keys(tasks)
    second = drop_stream_keys(tasks)
    assert first == 1
    assert second == 0
