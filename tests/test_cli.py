"""Tests for brana CLI core utilities — theme, config, classification, filtering."""

import json
from pathlib import Path

import pytest


@pytest.fixture
def themes():
    themes_file = Path(__file__).parent.parent / "system" / "cli" / "themes.json"
    return json.loads(themes_file.read_text())


@pytest.fixture
def sample_tasks():
    return [
        {"id": "t-001", "subject": "Done task", "status": "completed", "type": "task",
         "tags": ["auth"], "stream": "roadmap", "priority": "P1", "effort": "S",
         "blocked_by": [], "created": "2026-01-01", "completed": "2026-01-05"},
        {"id": "t-002", "subject": "Active task", "status": "in_progress", "type": "task",
         "tags": ["auth", "api"], "stream": "roadmap", "priority": "P0", "effort": "M",
         "blocked_by": [], "created": "2026-01-10", "build_step": "build"},
        {"id": "t-003", "subject": "Pending task", "status": "pending", "type": "task",
         "tags": ["scheduler"], "stream": "tech-debt", "priority": "P2", "effort": "S",
         "blocked_by": [], "created": "2026-01-15"},
        {"id": "t-004", "subject": "Blocked task", "status": "pending", "type": "task",
         "tags": ["scheduler", "dx"], "stream": "tech-debt", "priority": None, "effort": "L",
         "blocked_by": ["t-002"], "created": "2026-02-01"},
        {"id": "t-005", "subject": "Parked task", "status": "pending", "type": "task",
         "tags": ["parked"], "stream": "roadmap", "priority": None, "effort": None,
         "blocked_by": [], "created": "2026-02-10"},
        {"id": "ph-001", "subject": "Phase 1", "status": "pending", "type": "phase",
         "tags": [], "stream": "roadmap", "blocked_by": []},
    ]


# ── themes.json validity ────────────────────────────────────────────────


class TestThemes:
    def test_all_three_themes_present(self, themes):
        assert "classic" in themes
        assert "emoji" in themes
        assert "minimal" in themes

    def test_each_theme_has_required_icons(self, themes):
        required = {"done", "active", "pending", "blocked", "parked"}
        for name, theme in themes.items():
            icons = set(theme.get("icons", {}).keys())
            assert required <= icons, f"{name} missing icons: {required - icons}"

    def test_each_theme_has_bars(self, themes):
        for name, theme in themes.items():
            assert "fill" in theme.get("bars", {}), f"{name} missing bars.fill"
            assert "empty" in theme.get("bars", {}), f"{name} missing bars.empty"

    def test_each_theme_has_colors(self, themes):
        for name, theme in themes.items():
            assert "colors" in theme, f"{name} missing colors"

    def test_emoji_has_health_dots(self, themes):
        assert "health" in themes["emoji"]
        assert "done" in themes["emoji"]["health"]
        assert "active" in themes["emoji"]["health"]
        assert "blocked" in themes["emoji"]["health"]


# ── classify_task ────────────────────────────────────────────────────────


class TestClassifyTask:
    def test_completed_is_done(self, sample_tasks):
        from system.cli.config import classify_task
        result = classify_task(sample_tasks[0], sample_tasks)
        assert result == "done"

    def test_in_progress_is_active(self, sample_tasks):
        from system.cli.config import classify_task
        result = classify_task(sample_tasks[1], sample_tasks)
        assert result == "active"

    def test_pending_unblocked_is_pending(self, sample_tasks):
        from system.cli.config import classify_task
        result = classify_task(sample_tasks[2], sample_tasks)
        assert result == "pending"

    def test_pending_with_incomplete_blocker_is_blocked(self, sample_tasks):
        from system.cli.config import classify_task
        result = classify_task(sample_tasks[3], sample_tasks)
        assert result == "blocked"

    def test_pending_with_completed_blocker_is_pending(self, sample_tasks):
        from system.cli.config import classify_task
        # Make blocker completed
        tasks = [dict(t) for t in sample_tasks]
        tasks[1] = dict(tasks[1], status="completed")
        result = classify_task(tasks[3], tasks)
        assert result == "pending"

    def test_parked_tag_returns_parked(self, sample_tasks):
        from system.cli.config import classify_task
        result = classify_task(sample_tasks[4], sample_tasks)
        assert result == "parked"

    def test_phase_type_still_classifies(self, sample_tasks):
        from system.cli.config import classify_task
        result = classify_task(sample_tasks[5], sample_tasks)
        assert result == "pending"


# ── theme rendering ─────────────────────────────────────────────────────


class TestThemeRendering:
    def test_icon_returns_theme_icon(self):
        from system.cli.theme import icon
        theme = {"icons": {"done": "✓"}}
        assert icon("done", theme) == "✓"

    def test_icon_returns_fallback_for_unknown(self):
        from system.cli.theme import icon
        theme = {"icons": {}}
        assert icon("unknown", theme) == "?"

    def test_progress_bar_full(self):
        from system.cli.theme import progress_bar
        theme = {"bars": {"fill": "█", "empty": "░"}}
        result = progress_bar(8, 8, width=8, theme=theme)
        assert "████████" in result
        assert "8/8" in result

    def test_progress_bar_empty(self):
        from system.cli.theme import progress_bar
        theme = {"bars": {"fill": "█", "empty": "░"}}
        result = progress_bar(0, 8, width=8, theme=theme)
        assert "░░░░░░░░" in result
        assert "0/8" in result

    def test_progress_bar_half(self):
        from system.cli.theme import progress_bar
        theme = {"bars": {"fill": "█", "empty": "░"}}
        result = progress_bar(4, 8, width=8, theme=theme)
        assert "████░░░░" in result

    def test_progress_bar_zero_total(self):
        from system.cli.theme import progress_bar
        theme = {"bars": {"fill": "█", "empty": "░"}}
        assert progress_bar(0, 0, theme=theme) == ""

    def test_task_line_includes_id_and_subject(self):
        from system.cli.theme import task_line
        theme = {"icons": {"pending": "→"}, "colors": {}}
        task = {"id": "t-001", "subject": "Test task", "tags": []}
        result = task_line(task, "pending", theme)
        assert "t-001" in result
        assert "Test task" in result
        assert "→" in result

    def test_task_line_shows_tags(self):
        from system.cli.theme import task_line
        theme = {"icons": {"pending": "→"}, "colors": {}}
        task = {"id": "t-001", "subject": "Test", "tags": ["auth", "api"]}
        result = task_line(task, "pending", theme, show_tags=True)
        assert "[auth, api]" in result

    def test_task_line_truncates_tags_over_3(self):
        from system.cli.theme import task_line
        theme = {"icons": {"pending": "→"}, "colors": {}}
        task = {"id": "t-001", "subject": "Test", "tags": ["a", "b", "c", "d", "e"]}
        result = task_line(task, "pending", theme, show_tags=True)
        assert "+2" in result

    def test_task_line_blocked_shows_blocker(self):
        from system.cli.theme import task_line
        theme = {"icons": {"blocked": "·"}, "blocked_ref": "⛓", "colors": {}}
        task = {"id": "t-002", "subject": "Blocked", "tags": [], "blocked_by": ["t-001"]}
        result = task_line(task, "blocked", theme)
        assert "⛓" in result
        assert "t-001" in result


# ── filtering ────────────────────────────────────────────────────────────


class TestFiltering:
    def test_filter_by_tag(self, sample_tasks):
        from system.cli.backlog import _filter_tasks
        result = _filter_tasks(sample_tasks, sample_tasks, tag="scheduler")
        assert len(result) == 2
        assert all("scheduler" in t.get("tags", []) for t in result)

    def test_filter_by_status(self, sample_tasks):
        from system.cli.backlog import _filter_tasks
        result = _filter_tasks(sample_tasks, sample_tasks, status_filter="active")
        assert len(result) == 1
        assert result[0]["id"] == "t-002"

    def test_filter_by_stream(self, sample_tasks):
        from system.cli.backlog import _filter_tasks
        result = _filter_tasks(sample_tasks, sample_tasks, stream="tech-debt")
        assert len(result) == 2

    def test_filter_excludes_phases(self, sample_tasks):
        from system.cli.backlog import _filter_tasks
        result = _filter_tasks(sample_tasks, sample_tasks)
        assert all(t["type"] != "phase" for t in result)

    def test_filter_combined_and_logic(self, sample_tasks):
        from system.cli.backlog import _filter_tasks
        result = _filter_tasks(
            sample_tasks, sample_tasks,
            tag="scheduler", stream="tech-debt",
        )
        assert len(result) == 2

    def test_sort_by_priority(self):
        from system.cli.backlog import _sort_by_priority
        tasks = [
            {"priority": "P2", "status": "pending", "order": 1, "created": "2026-01-01"},
            {"priority": "P0", "status": "pending", "order": 1, "created": "2026-01-01"},
            {"priority": None, "status": "pending", "order": 1, "created": "2026-01-01"},
            {"priority": "P1", "status": "in_progress", "order": 1, "created": "2026-01-01"},
        ]
        result = _sort_by_priority(tasks)
        assert result[0]["priority"] == "P0"
        assert result[1]["priority"] == "P1"
        assert result[2]["priority"] == "P2"
        assert result[3]["priority"] is None


# ── focus score ──────────────────────────────────────────────────────────


class TestFocusScore:
    def test_higher_priority_scores_higher(self, sample_tasks):
        from system.cli.backlog import _focus_score
        p0_task = {"priority": "P0", "created": "2026-03-01", "effort": "S", "blocked_by": []}
        p3_task = {"priority": "P3", "created": "2026-03-01", "effort": "S", "blocked_by": []}
        assert _focus_score(p0_task, sample_tasks) > _focus_score(p3_task, sample_tasks)

    def test_older_tasks_score_higher(self, sample_tasks):
        from system.cli.backlog import _focus_score
        old = {"priority": None, "created": "2025-01-01", "effort": "S", "blocked_by": []}
        new = {"priority": None, "created": "2026-03-14", "effort": "S", "blocked_by": []}
        assert _focus_score(old, sample_tasks) > _focus_score(new, sample_tasks)

    def test_smaller_effort_scores_higher(self, sample_tasks):
        from system.cli.backlog import _focus_score
        small = {"priority": "P2", "created": "2026-03-01", "effort": "S", "blocked_by": []}
        large = {"priority": "P2", "created": "2026-03-01", "effort": "XL", "blocked_by": []}
        assert _focus_score(small, sample_tasks) > _focus_score(large, sample_tasks)


# ── schedule collisions ─────────────────────────────────────────────────


class TestScheduleCollisions:
    def test_detects_collision(self):
        from system.cli.ops import _find_collisions
        jobs = {
            "job-a": {"schedule": "*-*-* 09:00:00", "project": "~/proj", "enabled": True},
            "job-b": {"schedule": "*-*-* 09:00:00", "project": "~/proj", "enabled": True},
            "job-c": {"schedule": "*-*-* 10:00:00", "project": "~/proj", "enabled": True},
        }
        result = _find_collisions(jobs)
        assert len(result) == 1
        assert set(result[0]["jobs"]) == {"job-a", "job-b"}

    def test_no_collision_different_schedule(self):
        from system.cli.ops import _find_collisions
        jobs = {
            "job-a": {"schedule": "*-*-* 09:00:00", "project": "~/proj", "enabled": True},
            "job-b": {"schedule": "*-*-* 09:02:00", "project": "~/proj", "enabled": True},
        }
        assert _find_collisions(jobs) == []

    def test_disabled_jobs_excluded(self):
        from system.cli.ops import _find_collisions
        jobs = {
            "job-a": {"schedule": "*-*-* 09:00:00", "project": "~/proj", "enabled": True},
            "job-b": {"schedule": "*-*-* 09:00:00", "project": "~/proj", "enabled": False},
        }
        assert _find_collisions(jobs) == []
