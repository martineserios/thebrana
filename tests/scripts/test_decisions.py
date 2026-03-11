#!/usr/bin/env python3
"""Tests for system/scripts/decisions.py"""

import datetime
import json
import os
import sys
import threading
from pathlib import Path

import pytest

# Make the script importable
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "system" / "scripts"))

import decisions


@pytest.fixture(autouse=True)
def isolated_state(tmp_path, monkeypatch):
    """Redirect STATE_DIR to tmp_path and reset session file cache."""
    monkeypatch.setattr(decisions, "STATE_DIR", tmp_path)
    # Reset cached session file between tests
    monkeypatch.setattr(decisions, "_session_file", None)
    # Ensure a stable session id unless test overrides
    monkeypatch.setenv("BRANA_SESSION_ID", "test-session")
    return tmp_path


# ---------------------------------------------------------------------------
# log
# ---------------------------------------------------------------------------

def test_log_creates_session_file(isolated_state):
    path = decisions.log_entry("scout", "finding", "found a thing")
    assert path.exists()
    assert path.suffix == ".jsonl"
    # Filename starts with today's date
    today = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d")
    assert path.name.startswith(today)


def test_log_appends(isolated_state):
    decisions.log_entry("scout", "finding", "first")
    decisions.log_entry("scout", "finding", "second")
    files = list(isolated_state.glob("*.jsonl"))
    assert len(files) == 1
    lines = files[0].read_text().strip().splitlines()
    assert len(lines) == 2


def test_log_entry_schema(isolated_state):
    decisions.log_entry("scout", "finding", "schema check")
    files = list(isolated_state.glob("*.jsonl"))
    entry = json.loads(files[0].read_text().strip())
    assert "ts" in entry
    assert entry["agent"] == "scout"
    assert entry["type"] == "finding"
    assert entry["content"] == "schema check"


def test_log_optional_fields(isolated_state):
    decisions.log_entry(
        "challenger", "concern", "cost too high",
        severity="HIGH", refs=["doc-1", "doc-2"], target="budget.md",
    )
    files = list(isolated_state.glob("*.jsonl"))
    entry = json.loads(files[0].read_text().strip())
    assert entry["severity"] == "HIGH"
    assert entry["refs"] == ["doc-1", "doc-2"]
    assert entry["target"] == "budget.md"


def test_log_session_id_env(isolated_state, monkeypatch):
    monkeypatch.setenv("BRANA_SESSION_ID", "custom-abc")
    # Reset so it picks up the new env
    monkeypatch.setattr(decisions, "_session_file", None)
    path = decisions.log_entry("scout", "action", "env id")
    assert "custom-abc" in path.name


def test_log_session_id_fallback(isolated_state, monkeypatch):
    monkeypatch.delenv("BRANA_SESSION_ID", raising=False)
    monkeypatch.setattr(decisions, "_session_file", None)
    path = decisions.log_entry("scout", "action", "fallback id")
    # Filename: YYYY-MM-DD-HHMMSS-PID-RANDOM.jsonl
    name = path.name
    parts = name.replace(".jsonl", "").split("-")
    # At least date (3 parts) + time + pid + random = 6+
    assert len(parts) >= 6


# ---------------------------------------------------------------------------
# read
# ---------------------------------------------------------------------------

def test_read_no_files(isolated_state):
    output = decisions.read_entries()
    assert output == ""


def test_read_last_n(isolated_state):
    for i in range(10):
        decisions.log_entry("scout", "finding", f"item {i}")
    output = decisions.read_entries(last=5)
    lines = output.strip().splitlines()
    assert len(lines) == 5
    assert "item 9" in lines[-1]


def test_read_filter_type(isolated_state):
    decisions.log_entry("scout", "finding", "a finding")
    decisions.log_entry("scout", "decision", "a decision")
    decisions.log_entry("scout", "finding", "another finding")
    output = decisions.read_entries(entry_type="finding")
    lines = output.strip().splitlines()
    assert len(lines) == 2
    assert all("finding" in l for l in lines)


def test_read_filter_severity(isolated_state):
    decisions.log_entry("scout", "concern", "low risk", severity="LOW")
    decisions.log_entry("scout", "concern", "high risk", severity="HIGH")
    decisions.log_entry("scout", "concern", "no sev")
    output = decisions.read_entries(severity="HIGH")
    lines = output.strip().splitlines()
    assert len(lines) == 1
    assert "high risk" in lines[0]


def test_read_filter_agent(isolated_state):
    decisions.log_entry("scout", "finding", "scout msg")
    decisions.log_entry("challenger", "finding", "challenger msg")
    output = decisions.read_entries(agent="scout")
    lines = output.strip().splitlines()
    assert len(lines) == 1
    assert "scout" in lines[0]


def test_read_json_output(isolated_state):
    decisions.log_entry("scout", "finding", "json test")
    output = decisions.read_entries(as_json=True)
    entry = json.loads(output.strip())
    assert entry["content"] == "json test"


# ---------------------------------------------------------------------------
# archive
# ---------------------------------------------------------------------------

def test_archive_moves_old_files(isolated_state):
    # Create a file dated 60 days ago
    old_date = (datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(days=60)).strftime("%Y-%m-%d")
    old_file = isolated_state / f"{old_date}-old.jsonl"
    old_file.write_text('{"ts":"2026-01-01T00:00:00+00:00","agent":"x","type":"finding","content":"old"}\n')

    result = decisions.archive(days=30)
    assert "Archived 1 files" in result
    assert not old_file.exists()
    assert (isolated_state / "archive" / old_file.name).exists()


def test_archive_uses_filename_date(isolated_state):
    # Create file with old date in name but recent mtime
    old_date = (datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(days=60)).strftime("%Y-%m-%d")
    old_file = isolated_state / f"{old_date}-mtime-test.jsonl"
    old_file.write_text("{}\n")
    # mtime is now (just created), but filename date is old
    result = decisions.archive(days=30)
    assert "Archived 1 files" in result
    assert (isolated_state / "archive" / old_file.name).exists()


def test_archive_dry_run(isolated_state):
    old_date = (datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(days=60)).strftime("%Y-%m-%d")
    old_file = isolated_state / f"{old_date}-dry.jsonl"
    old_file.write_text("{}\n")

    result = decisions.archive(days=30, dry_run=True)
    assert "Would archive 1 files" in result
    # File should still be in place
    assert old_file.exists()
    assert not (isolated_state / "archive" / old_file.name).exists()


# ---------------------------------------------------------------------------
# concurrent & validation
# ---------------------------------------------------------------------------

def test_concurrent_log_no_corruption(isolated_state):
    """Two rapid appends from threads don't corrupt the file."""
    errors = []

    def writer(n):
        try:
            decisions.log_entry("thread", "action", f"msg-{n}")
        except Exception as e:
            errors.append(e)

    threads = [threading.Thread(target=writer, args=(i,)) for i in range(10)]
    for t in threads:
        t.start()
    for t in threads:
        t.join()

    assert not errors

    files = list(isolated_state.glob("*.jsonl"))
    total_lines = 0
    for f in files:
        for line in f.read_text().strip().splitlines():
            entry = json.loads(line)  # Must be valid JSON
            assert "ts" in entry
            total_lines += 1
    assert total_lines == 10


def test_invalid_type_rejected(isolated_state):
    with pytest.raises(SystemExit) as exc_info:
        decisions.log_entry("scout", "bogus", "should fail")
    assert exc_info.value.code == 1
