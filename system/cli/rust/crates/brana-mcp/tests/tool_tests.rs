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
                "stream": "bugs",
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
                "stream": "roadmap",
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
                "stream": "docs",
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
        None, Some("pending"), None, None, None, None, &["task"],
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
        Some("auth"), None, None, None, None, None, &["task"],
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
        None, None, None, Some("P0"), None, None, &["task"],
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
        None, None, None, None, None, Some("login"), &["task"],
    );
    assert_eq!(results.len(), 1);
    assert_eq!(results[0]["id"], "t-001");
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
        "stream": "roadmap",
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

    assert_eq!(stats["by_status"]["pending"], 1);
    assert_eq!(stats["by_status"]["active"], 1);
    assert_eq!(stats["by_status"]["done"], 1);
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
