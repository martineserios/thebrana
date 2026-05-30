//! Integration tests for brana-mcp tools.
//!
//! These test the tool handler functions directly with fixture data,
//! bypassing the MCP transport layer. The transport (stdio) is tested
//! by pmcp's own test suite.

use serde_json::{json, Value};
use std::fs;
use std::path::PathBuf;

/// Create a temporary tasks.json with fixture data and return its path.
fn fixture_tasks(dir: &std::path::Path) -> PathBuf {
    let claude_dir = dir.join(".claude");
    fs::create_dir_all(&claude_dir).unwrap();
    let path = claude_dir.join("tasks.json");
    fs::write(&path, serde_json::to_string_pretty(&json!({
        "project": "test",
        "tasks": [
            {
                "id": "t-001",
                "subject": "Fix login bug",
                "status": "pending",
                "type": "task",
                "tags": ["auth", "urgent"],
                "priority": "P0",
                "effort": "S",
                "parent": null,
                "blocked_by": [],
                "created": "2026-04-01",
                "description": "Login fails on mobile devices",
                "context": null,
                "notes": null,
            },
            {
                "id": "t-002",
                "subject": "Add dark mode",
                "status": "in_progress",
                "type": "task",
                "tags": ["ui"],
                "priority": "P1",
                "effort": "M",
                "parent": null,
                "blocked_by": [],
                "created": "2026-04-02",
                "started": "2026-04-03",
                "description": null,
                "context": null,
                "notes": null,
            },
            {
                "id": "t-003",
                "subject": "Write API docs",
                "status": "completed",
                "type": "task",
                "tags": ["docs"],
                "priority": "P2",
                "effort": "S",
                "parent": null,
                "blocked_by": [],
                "created": "2026-03-15",
                "completed": "2026-04-01",
                "description": null,
                "context": null,
                "notes": null,
            },
        ]
    })).unwrap()).unwrap();
    path
}

// ── brana-core function tests with fixture data ──────────────────────────

#[test]
fn test_load_and_filter_by_status() {
    let dir = tempfile::tempdir().unwrap();
    let path = fixture_tasks(dir.path());

    let data = brana_core::tasks::load_tasks(&path).unwrap();
    assert_eq!(data.tasks.len(), 3);

    let pending = brana_core::tasks::filter_tasks(
        &data.tasks, &data.tasks,
        None, Some("pending"), None, None, None, &["task"], None, None,
    );
    assert_eq!(pending.len(), 1);
    assert_eq!(pending[0]["id"], "t-001");
}

#[test]
fn test_filter_by_tag() {
    let dir = tempfile::tempdir().unwrap();
    let path = fixture_tasks(dir.path());

    let data = brana_core::tasks::load_tasks(&path).unwrap();

    let auth_tasks = brana_core::tasks::filter_tasks(
        &data.tasks, &data.tasks,
        Some("auth"), None, None, None, None, &["task"], None, None,
    );
    assert_eq!(auth_tasks.len(), 1);
    assert_eq!(auth_tasks[0]["id"], "t-001");
}

#[test]
fn test_filter_by_priority() {
    let dir = tempfile::tempdir().unwrap();
    let path = fixture_tasks(dir.path());

    let data = brana_core::tasks::load_tasks(&path).unwrap();

    let p0 = brana_core::tasks::filter_tasks(
        &data.tasks, &data.tasks,
        None, None, Some("P0"), None, None, &["task"], None, None,
    );
    assert_eq!(p0.len(), 1);
    assert_eq!(p0[0]["id"], "t-001");
}

#[test]
fn test_search() {
    let dir = tempfile::tempdir().unwrap();
    let path = fixture_tasks(dir.path());

    let data = brana_core::tasks::load_tasks(&path).unwrap();

    let results = brana_core::tasks::filter_tasks(
        &data.tasks, &data.tasks,
        None, None, None, None, Some("login"), &["task"], None, None,
    );
    assert_eq!(results.len(), 1);
    assert_eq!(results[0]["id"], "t-001");
}

// ── Wave 4B: epic model tests ─────────────────────────────────────────────

#[test]
fn test_focus_score_epic_boost() {
    // A P2 task with epic boost=500 should outrank a P0 task with no boost.
    let p2_epic = json!({
        "id": "t-A", "type": "task", "status": "pending",
        "priority": "P2", "effort": "S", "blocked_by": [],
        "epic": "cc-alignment",
    });
    let p0_no_epic = json!({
        "id": "t-B", "type": "task", "status": "pending",
        "priority": "P0", "effort": "S", "blocked_by": [],
    });
    let score_a = brana_core::tasks::focus_score(&p2_epic, 500.0);
    let score_b = brana_core::tasks::focus_score(&p0_no_epic, 0.0);
    assert!(score_a > score_b, "epic boost must overcome P2 vs P0 gap: {score_a} vs {score_b}");
}

#[test]
fn test_epic_work_type_filter_roundtrip() {
    // Tasks with epic and work_type fields are preserved through load+filter.
    let dir = tempfile::tempdir().unwrap();
    let claude_dir = dir.path().join(".claude");
    std::fs::create_dir_all(&claude_dir).unwrap();
    let path = claude_dir.join("tasks.json");
    std::fs::write(&path, serde_json::to_string_pretty(&json!({
        "project": "test",
        "tasks": [
            {"id":"t-001","subject":"implement feature","type":"task","status":"pending",
             "priority":"P1","effort":"S","work_type":"implement","epic":"cc-alignment",
             "tags":[],"blocked_by":[],"created":"2026-01-01"},
            {"id":"t-002","subject":"research spike","type":"task","status":"pending",
             "priority":"P2","effort":"M","work_type":"research",
             "tags":[],"blocked_by":[],"created":"2026-01-01"},
        ]
    })).unwrap()).unwrap();

    let data = brana_core::tasks::load_tasks(&path).unwrap();

    // Filter by work_type=implement
    let impl_tasks = brana_core::tasks::filter_tasks(
        &data.tasks, &data.tasks,
        None, None, None, None, None, &["task"], None, Some("implement"),
    );
    assert_eq!(impl_tasks.len(), 1);
    assert_eq!(impl_tasks[0]["id"], "t-001");
    assert_eq!(impl_tasks[0]["work_type"], "implement");
    assert_eq!(impl_tasks[0]["epic"], "cc-alignment");

    // Filter by epic=cc-alignment
    let init_tasks = brana_core::tasks::filter_tasks(
        &data.tasks, &data.tasks,
        None, None, None, None, None, &["task"], Some("cc-alignment"), None,
    );
    assert_eq!(init_tasks.len(), 1);
    assert_eq!(init_tasks[0]["id"], "t-001");
}

#[test]
fn test_set_field() {
    let dir = tempfile::tempdir().unwrap();
    let path = fixture_tasks(dir.path());

    let mut val = brana_core::tasks::load_raw(&path).unwrap();
    let tasks = val["tasks"].as_array_mut().unwrap();
    let task = tasks.iter_mut().find(|t| t["id"] == "t-001").unwrap();

    brana_core::tasks::set_field(task, "status", "in_progress", false).unwrap();
    assert_eq!(task["status"], "in_progress");

    brana_core::tasks::set_field(task, "tags", "+critical", false).unwrap();
    let tags: Vec<&str> = task["tags"].as_array().unwrap()
        .iter().filter_map(|v| v.as_str()).collect();
    assert!(tags.contains(&"critical"));
    assert!(tags.contains(&"auth"));
}

#[test]
fn test_set_field_remove_tag() {
    let dir = tempfile::tempdir().unwrap();
    let path = fixture_tasks(dir.path());

    let mut val = brana_core::tasks::load_raw(&path).unwrap();
    let tasks = val["tasks"].as_array_mut().unwrap();
    let task = tasks.iter_mut().find(|t| t["id"] == "t-001").unwrap();

    brana_core::tasks::set_field(task, "tags", "-urgent", false).unwrap();
    let tags: Vec<&str> = task["tags"].as_array().unwrap()
        .iter().filter_map(|v| v.as_str()).collect();
    assert!(!tags.contains(&"urgent"));
    assert!(tags.contains(&"auth"));
}

#[test]
fn test_add_task_and_save() {
    let dir = tempfile::tempdir().unwrap();
    let path = fixture_tasks(dir.path());

    let mut val = brana_core::tasks::load_raw(&path).unwrap();
    let tasks = val["tasks"].as_array().unwrap();
    let id = brana_core::tasks::next_id(tasks);
    assert!(id.starts_with("t-"), "expected t-NNN, got {id}");

    let new_task = json!({
        "id": id,
        "subject": "New task",
        "status": "pending",
        "type": "task",
        "tags": [],
        "created": "2026-04-05",
    });

    val["tasks"].as_array_mut().unwrap().push(new_task);
    brana_core::tasks::save_tasks(&path, &val).unwrap();

    // Reload and verify
    let reloaded = brana_core::tasks::load_tasks(&path).unwrap();
    assert_eq!(reloaded.tasks.len(), 4);
    assert_eq!(reloaded.tasks[3]["subject"], "New task");
}

#[test]
fn test_compute_stats() {
    let dir = tempfile::tempdir().unwrap();
    let path = fixture_tasks(dir.path());

    let data = brana_core::tasks::load_tasks(&path).unwrap();
    let stats = brana_core::tasks::compute_stats(&data.tasks, &data.tasks);

    // Raw status counts (matches CLI TaskStatus enum). t-1340.
    assert_eq!(stats["by_status"]["pending"], 1);
    assert_eq!(stats["by_status"]["in_progress"], 1);
    assert_eq!(stats["by_status"]["completed"], 1);

    // Synthetic state counts (classify() display rollup).
    assert_eq!(stats["by_state"]["pending"], 1);
    assert_eq!(stats["by_state"]["active"], 1);
    assert_eq!(stats["by_state"]["done"], 1);

    assert_eq!(stats["total"], 3);
}

#[test]
fn test_classify() {
    let dir = tempfile::tempdir().unwrap();
    let path = fixture_tasks(dir.path());

    let data = brana_core::tasks::load_tasks(&path).unwrap();

    assert_eq!(brana_core::tasks::classify(&data.tasks[0], &data.tasks), "pending");
    assert_eq!(brana_core::tasks::classify(&data.tasks[1], &data.tasks), "active");
    assert_eq!(brana_core::tasks::classify(&data.tasks[2], &data.tasks), "done");
}

// ── Batch set tests ─────────────────────────────────────────────────────

#[test]
fn test_batch_set_multiple_fields_single_task() {
    let dir = tempfile::tempdir().unwrap();
    let path = fixture_tasks(dir.path());

    let mut val = brana_core::tasks::load_raw(&path).unwrap();

    // Simulate batch: set strategy + status + branch on t-001
    {
        let tasks = val["tasks"].as_array_mut().unwrap();
        let task = tasks.iter_mut().find(|t| t["id"] == "t-001").unwrap();

        let fields = vec![
            ("strategy", "bug-fix"),
            ("status", "in_progress"),
            ("branch", "fix/t-001-login"),
        ];

        for (field, value) in &fields {
            brana_core::tasks::set_field(task, field, value, false).unwrap();
        }

        assert_eq!(task["strategy"], "bug-fix");
        assert_eq!(task["status"], "in_progress");
        assert_eq!(task["branch"], "fix/t-001-login");
    }

    // Single save
    brana_core::tasks::save_tasks(&path, &val).unwrap();

    // Reload and verify persistence
    let reloaded = brana_core::tasks::load_raw(&path).unwrap();
    let task = reloaded["tasks"].as_array().unwrap()
        .iter().find(|t| t["id"] == "t-001").unwrap();
    assert_eq!(task["strategy"], "bug-fix");
    assert_eq!(task["status"], "in_progress");
    assert_eq!(task["branch"], "fix/t-001-login");
}

#[test]
fn test_batch_set_multiple_tasks() {
    let dir = tempfile::tempdir().unwrap();
    let path = fixture_tasks(dir.path());

    let mut val = brana_core::tasks::load_raw(&path).unwrap();

    // Simulate batch: complete t-001 and t-002 in one pass
    {
        let tasks = val["tasks"].as_array_mut().unwrap();

        for task_id in &["t-001", "t-002"] {
            let task = tasks.iter_mut().find(|t| t["id"].as_str() == Some(*task_id)).unwrap();
            brana_core::tasks::set_field(task, "status", "completed", false).unwrap();
            brana_core::tasks::set_field(task, "completed", "2026-04-06", false).unwrap();
        }
    }

    // Single save
    brana_core::tasks::save_tasks(&path, &val).unwrap();

    // Reload and verify
    let reloaded = brana_core::tasks::load_raw(&path).unwrap();
    let tasks = reloaded["tasks"].as_array().unwrap();
    for task_id in &["t-001", "t-002"] {
        let task = tasks.iter().find(|t| t["id"].as_str() == Some(*task_id)).unwrap();
        assert_eq!(task["status"], "completed", "task {} not completed", task_id);
        assert_eq!(task["completed"], "2026-04-06");
    }
}

#[test]
fn test_batch_partial_failure() {
    let dir = tempfile::tempdir().unwrap();
    let path = fixture_tasks(dir.path());

    let mut val = brana_core::tasks::load_raw(&path).unwrap();

    {
        let tasks = val["tasks"].as_array_mut().unwrap();
        let task = tasks.iter_mut().find(|t| t["id"] == "t-001").unwrap();

        // Valid field succeeds
        assert!(brana_core::tasks::set_field(task, "status", "completed", false).is_ok());
        // Invalid field fails
        assert!(brana_core::tasks::set_field(task, "nonexistent_field", "value", false).is_err());
        // Valid field after failure still works
        assert!(brana_core::tasks::set_field(task, "priority", "P1", false).is_ok());

        assert_eq!(task["status"], "completed");
        assert_eq!(task["priority"], "P1");
    }
}

// ── Regression: stream field must not appear in task fixtures (t-1564) ──

#[test]
fn test_fixture_tasks_have_no_stream_field() {
    let dir = tempfile::tempdir().unwrap();
    let path = fixture_tasks(dir.path());
    let data = brana_core::tasks::load_tasks(&path).unwrap();
    for task in &data.tasks {
        assert!(
            task.get("stream").is_none() || task["stream"] == serde_json::Value::Null,
            "fixture task {} must not have stream field (regression: t-1564)",
            task["id"]
        );
    }
}

// ── MCP server build test ────────────────────────────────────────────────

#[test]
fn test_server_builds_without_error() {
    // Verify the server can be constructed with all tools registered
    let result = pmcp::Server::builder()
        .name("brana-mcp-test")
        .version("0.0.0-test")
        .build();
    assert!(result.is_ok(), "Server build failed: {:?}", result.err());
}

// ── Session tool tests ───────────────────────────────────────────────────

/// Create a fake project root with a memory dir for session tests.
/// Returns a TempDir (must be kept alive) and the project root PathBuf.
fn fixture_project_root() -> (tempfile::TempDir, PathBuf) {
    let dir = tempfile::tempdir().unwrap();
    let root = dir.path().to_path_buf();
    // Pre-create the memory dir so tests can also check it is absent before writes
    (dir, root)
}

/// Build a minimal valid session state JSON value.
fn minimal_session_json(written_at: &str) -> Value {
    json!({
        "version": 1,
        "written_at": written_at,
        "branch": "feat/t-976",
        "accomplished": ["implemented session tools"],
        "learnings": [],
        "next": [],
        "blockers": []
    })
}

// ── session_write tests ──────────────────────────────────────────────────

#[test]
fn test_session_write_creates_state_file() {
    let (_dir, root) = fixture_project_root();

    let payload: brana_core::session::SessionState =
        serde_json::from_value(minimal_session_json("2026-04-06T10:00:00Z")).unwrap();

    brana_core::session::write_state(&root, &payload).unwrap();

    let state_path = brana_core::session::epic_scoped_state_path(&root, payload.branch.as_deref().unwrap_or(""));
    assert!(state_path.exists(), "session-state.json should exist after write");
}

#[test]
fn test_session_write_auto_fills_written_at_on_empty() {
    // When written_at is a valid RFC3339, it passes through unchanged.
    // The MCP tool fills it if empty — we test the core function here.
    let (_dir, root) = fixture_project_root();

    let state = brana_core::session::SessionState {
        version: 1,
        written_at: "2026-04-06T12:00:00Z".to_string(),
        branch: Some("main".to_string()),
        accomplished: vec!["thing A".to_string()],
        ..Default::default()
    };

    brana_core::session::write_state(&root, &state).unwrap();
    let loaded = brana_core::session::read_state(&root).unwrap();
    assert_eq!(loaded.accomplished, vec!["thing A"]);
}

#[test]
fn test_session_write_archives_previous_state() {
    let (_dir, root) = fixture_project_root();

    let state1: brana_core::session::SessionState =
        serde_json::from_value(minimal_session_json("2026-04-06T10:00:00Z")).unwrap();
    brana_core::session::write_state(&root, &state1).unwrap();

    let state2: brana_core::session::SessionState =
        serde_json::from_value(minimal_session_json("2026-04-06T11:00:00Z")).unwrap();
    brana_core::session::write_state(&root, &state2).unwrap();

    let history_path = brana_core::session::session_history_path(&root);
    assert!(history_path.exists(), "history file should exist after second write");

    let content = fs::read_to_string(&history_path).unwrap();
    assert!(content.contains("2026-04-06T10:00:00"), "first state should be in history");
}

#[test]
fn test_session_write_rejects_invalid_version() {
    let (_dir, root) = fixture_project_root();

    let mut state: brana_core::session::SessionState =
        serde_json::from_value(minimal_session_json("2026-04-06T10:00:00Z")).unwrap();
    state.version = 99;

    let result = brana_core::session::write_state(&root, &state);
    assert!(result.is_err(), "should reject unsupported schema version");
}

// ── session_read tests ───────────────────────────────────────────────────

#[test]
fn test_session_read_returns_none_when_no_state() {
    let (_dir, root) = fixture_project_root();
    assert!(brana_core::session::read_state(&root).is_none());
}

#[test]
fn test_session_read_returns_full_state() {
    let (_dir, root) = fixture_project_root();

    let state: brana_core::session::SessionState =
        serde_json::from_value(minimal_session_json("2026-04-06T10:00:00Z")).unwrap();
    brana_core::session::write_state(&root, &state).unwrap();

    let loaded = brana_core::session::read_state(&root).unwrap();
    assert_eq!(loaded.version, 1);
    assert_eq!(loaded.branch, Some("feat/t-976".to_string()));
    assert_eq!(loaded.accomplished, vec!["implemented session tools"]);
}

#[test]
fn test_session_read_specific_field_via_json() {
    let (_dir, root) = fixture_project_root();

    let state: brana_core::session::SessionState =
        serde_json::from_value(minimal_session_json("2026-04-06T10:00:00Z")).unwrap();
    brana_core::session::write_state(&root, &state).unwrap();

    let loaded = brana_core::session::read_state(&root).unwrap();
    let as_value = serde_json::to_value(&loaded).unwrap();
    // Simulate the MCP tool's optional field extraction
    assert_eq!(as_value["branch"], "feat/t-976");
    assert_eq!(as_value["version"], 1);
}

// ── session_history tests ────────────────────────────────────────────────

#[test]
fn test_session_history_empty_when_no_history() {
    let (_dir, root) = fixture_project_root();
    let history = brana_core::session::read_history(&root, 5);
    assert!(history.is_empty());
}

#[test]
fn test_session_history_most_recent_first() {
    let (_dir, root) = fixture_project_root();

    // Write 3 states sequentially to build history (each write archives the previous)
    let s1: brana_core::session::SessionState =
        serde_json::from_value(minimal_session_json("2026-04-06T08:00:00Z")).unwrap();
    brana_core::session::write_state(&root, &s1).unwrap();

    let s2: brana_core::session::SessionState =
        serde_json::from_value(minimal_session_json("2026-04-06T09:00:00Z")).unwrap();
    brana_core::session::write_state(&root, &s2).unwrap();

    let s3: brana_core::session::SessionState =
        serde_json::from_value(minimal_session_json("2026-04-06T10:00:00Z")).unwrap();
    brana_core::session::write_state(&root, &s3).unwrap();

    let history = brana_core::session::read_history(&root, 10);
    assert_eq!(history.len(), 2, "s1 and s2 should be in history (s3 is current)");
    // Most recent first
    assert!(history[0].written_at > history[1].written_at);
}

#[test]
fn test_session_history_limit_applied() {
    let (_dir, root) = fixture_project_root();

    // Write 4 states to build 3-entry history
    for h in 8..=11u32 {
        let s: brana_core::session::SessionState =
            serde_json::from_value(minimal_session_json(
                &format!("2026-04-06T{h:02}:00:00Z")
            )).unwrap();
        brana_core::session::write_state(&root, &s).unwrap();
    }

    let history = brana_core::session::read_history(&root, 2);
    assert_eq!(history.len(), 2, "limit of 2 should be respected");
}
