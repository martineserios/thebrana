//! Task-to-GitHub-Issue sync planning.
//!
//! Pure functions that produce a `SyncPlan` from task data.
//! The CLI layer executes the plan via `gh` subprocess calls.
//! No I/O in this module.

use serde_json::Value;
use std::collections::HashMap;

/// Configuration for a sync target.
#[derive(Debug, Clone)]
pub struct SyncConfig {
    pub owner: String,
    pub repo: String,
    pub project_number: u64,
    pub keep_streams: Vec<String>,
}

/// A planned sync action.
#[derive(Debug, Clone)]
pub enum SyncAction {
    /// Create a new GitHub issue for this task.
    Create {
        task_id: String,
        title: String,
        body: String,
        labels: Vec<String>,
    },
    /// Update an existing GitHub issue.
    Update {
        task_id: String,
        issue_num: u64,
        title: String,
        body: String,
        labels: Vec<String>,
        close_reason: Option<String>,
        reopen: bool,
    },
}

/// The full sync plan: actions to execute + updated state.
#[derive(Debug, Clone)]
pub struct SyncPlan {
    pub actions: Vec<SyncAction>,
    pub updated_hashes: HashMap<String, String>,
}

/// Compute a content hash for change detection.
pub fn compute_hash(task: &Value) -> String {
    format!(
        "{}|{}|{}|{}",
        task["status"].as_str().unwrap_or(""),
        task["priority"].as_str().unwrap_or(""),
        task["effort"].as_str().unwrap_or(""),
        task["subject"].as_str().unwrap_or(""),
    )
}

/// Build label list for a task.
pub fn build_labels(task: &Value) -> Vec<String> {
    let mut labels = vec![];
    if let Some(stream) = task["stream"].as_str() {
        labels.push(format!("stream:{stream}"));
    }
    if let Some(tags) = task["tags"].as_array() {
        for tag in tags {
            if let Some(t) = tag.as_str() {
                labels.push(format!("tag:{t}"));
            }
        }
    }
    if matches!(task["type"].as_str(), Some("phase" | "milestone")) {
        labels.push("enhancement".into());
    }
    labels
}

/// Build issue body markdown from task data.
pub fn build_body(task: &Value, task_map: &HashMap<String, u64>) -> String {
    let mut lines = vec![];

    if let Some(desc) = task["description"].as_str() {
        if !desc.is_empty() {
            lines.push(desc.to_string());
            lines.push(String::new());
        }
    }

    lines.push("## Metadata".into());
    lines.push(format!("- **Task ID:** `{}`", task["id"].as_str().unwrap_or("?")));
    lines.push(format!("- **Type:** {}", task["type"].as_str().unwrap_or("—")));
    lines.push(format!("- **Stream:** {}", task["stream"].as_str().unwrap_or("—")));
    lines.push(format!("- **Status:** {}", task["status"].as_str().unwrap_or("—")));

    let optional_fields = [
        ("priority", "Priority", false),
        ("effort", "Effort", false),
        ("strategy", "Strategy", false),
        ("branch", "Branch", true),
        ("started", "Started", false),
        ("completed", "Completed", false),
    ];
    for (field, label, is_code) in optional_fields {
        if let Some(val) = task[field].as_str() {
            if is_code {
                lines.push(format!("- **{label}:** `{val}`"));
            } else {
                lines.push(format!("- **{label}:** {val}"));
            }
        }
    }

    if let Some(parent) = task["parent"].as_str() {
        if let Some(issue) = task_map.get(parent) {
            lines.push(format!("- **Parent:** #{issue}"));
        }
    }

    if let Some(blocked) = task["blocked_by"].as_array() {
        if !blocked.is_empty() {
            let refs: Vec<String> = blocked.iter()
                .filter_map(|b| b.as_str())
                .map(|b| {
                    task_map.get(b)
                        .map(|n| format!("#{n}"))
                        .unwrap_or_else(|| b.to_string())
                })
                .collect();
            lines.push(format!("- **Blocked by:** {}", refs.join(", ")));
        }
    }

    if let Some(ctx) = task["context"].as_str() {
        if !ctx.is_empty() {
            lines.push(String::new());
            lines.push("## Context".into());
            lines.push(ctx.to_string());
        }
    }

    if let Some(notes) = task["notes"].as_str() {
        if !notes.is_empty() {
            lines.push(String::new());
            lines.push("## Notes".into());
            lines.push(notes.to_string());
        }
    }

    lines.join("\n")
}

/// Plan the sync: determine which tasks need creating and which need updating.
pub fn plan_sync(
    tasks: &[Value],
    task_map: &HashMap<String, u64>,
    hashes: &HashMap<String, String>,
    config: &SyncConfig,
) -> SyncPlan {
    let keep: std::collections::HashSet<&str> = config.keep_streams.iter()
        .map(|s| s.as_str())
        .collect();

    // Filter to qualifying tasks
    let qualifying: HashMap<&str, &Value> = tasks.iter()
        .filter_map(|t| {
            let id = t["id"].as_str()?;
            let stream = t["stream"].as_str().unwrap_or("");
            if keep.contains(stream) { Some((id, t)) } else { None }
        })
        .collect();

    let mut actions = vec![];
    let mut updated_hashes = hashes.clone();

    // New tasks: in qualifying but not in map
    let mut new_task_ids: Vec<&str> = qualifying.keys()
        .filter(|id| !task_map.contains_key(**id))
        .copied()
        .collect();

    // Sort: phases first, then milestones, then tasks, then subtasks
    let type_order = |t: &Value| -> u8 {
        match t["type"].as_str() {
            Some("phase") => 0,
            Some("milestone") => 1,
            Some("task") => 2,
            Some("subtask") => 3,
            _ => 2,
        }
    };
    new_task_ids.sort_by(|a, b| {
        let ta = qualifying[a];
        let tb = qualifying[b];
        type_order(ta).cmp(&type_order(tb))
            .then_with(|| {
                let oa = ta["order"].as_u64().unwrap_or(999);
                let ob = tb["order"].as_u64().unwrap_or(999);
                oa.cmp(&ob)
            })
    });

    for tid in &new_task_ids {
        let task = qualifying[tid];
        let title = format!("[{tid}] {}", task["subject"].as_str().unwrap_or("Untitled"));
        let body = build_body(task, task_map);
        let labels = build_labels(task);

        actions.push(SyncAction::Create {
            task_id: tid.to_string(),
            title,
            body,
            labels,
        });
        updated_hashes.insert(tid.to_string(), compute_hash(task));
    }

    // Changed tasks: in both map and qualifying, hash differs
    for (tid, task) in &qualifying {
        if !task_map.contains_key(*tid) {
            continue; // new, handled above
        }
        let current = compute_hash(task);
        if hashes.get(*tid).map(|h| h.as_str()) == Some(current.as_str()) {
            continue; // unchanged
        }

        let issue_num = task_map[*tid];
        let title = format!("[{tid}] {}", task["subject"].as_str().unwrap_or("Untitled"));
        let body = build_body(task, task_map);
        let labels = build_labels(task);
        let status = task["status"].as_str().unwrap_or("pending");

        let close_reason = match status {
            "completed" => Some("completed".into()),
            "cancelled" => Some("not_planned".into()),
            _ => None,
        };
        let reopen = matches!(status, "pending" | "in_progress");

        actions.push(SyncAction::Update {
            task_id: tid.to_string(),
            issue_num,
            title,
            body,
            labels,
            close_reason,
            reopen,
        });
        updated_hashes.insert(tid.to_string(), current);
    }

    SyncPlan { actions, updated_hashes }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn test_config() -> SyncConfig {
        SyncConfig {
            owner: "testowner".into(),
            repo: "testowner/testrepo".into(),
            project_number: 1,
            keep_streams: vec!["roadmap".into(), "bugs".into()],
        }
    }

    #[test]
    fn test_build_labels() {
        let task = json!({"stream": "roadmap", "tags": ["cli", "rust"], "type": "task"});
        let labels = build_labels(&task);
        assert_eq!(labels, vec!["stream:roadmap", "tag:cli", "tag:rust"]);
    }

    #[test]
    fn test_build_labels_phase_gets_enhancement() {
        let task = json!({"stream": "roadmap", "tags": [], "type": "phase"});
        let labels = build_labels(&task);
        assert!(labels.contains(&"enhancement".to_string()));
    }

    #[test]
    fn test_build_body_basic() {
        let task = json!({
            "id": "t-1",
            "type": "task",
            "stream": "roadmap",
            "status": "pending",
            "description": "Fix the bug",
        });
        let body = build_body(&task, &HashMap::new());
        assert!(body.contains("Fix the bug"));
        assert!(body.contains("**Task ID:** `t-1`"));
        assert!(body.contains("**Stream:** roadmap"));
    }

    #[test]
    fn test_build_body_with_parent_ref() {
        let task = json!({"id": "t-2", "type": "task", "stream": "roadmap", "status": "pending", "parent": "t-1"});
        let mut map = HashMap::new();
        map.insert("t-1".into(), 42);
        let body = build_body(&task, &map);
        assert!(body.contains("**Parent:** #42"));
    }

    #[test]
    fn test_compute_hash() {
        let task = json!({"status": "pending", "priority": "P0", "effort": "S", "subject": "Test"});
        assert_eq!(compute_hash(&task), "pending|P0|S|Test");
    }

    #[test]
    fn test_plan_sync_new_tasks() {
        let tasks = vec![
            json!({"id": "t-1", "subject": "New task", "stream": "roadmap", "type": "task", "status": "pending", "tags": []}),
        ];
        let plan = plan_sync(&tasks, &HashMap::new(), &HashMap::new(), &test_config());
        assert_eq!(plan.actions.len(), 1);
        match &plan.actions[0] {
            SyncAction::Create { task_id, .. } => assert_eq!(task_id, "t-1"),
            _ => panic!("expected Create"),
        }
    }

    #[test]
    fn test_plan_sync_changed_task() {
        let tasks = vec![
            json!({"id": "t-1", "subject": "Updated", "stream": "roadmap", "type": "task", "status": "in_progress", "tags": []}),
        ];
        let mut map = HashMap::new();
        map.insert("t-1".into(), 10);
        let mut hashes = HashMap::new();
        hashes.insert("t-1".into(), "pending|P0|S|Old".into());

        let plan = plan_sync(&tasks, &map, &hashes, &test_config());
        assert_eq!(plan.actions.len(), 1);
        match &plan.actions[0] {
            SyncAction::Update { task_id, issue_num, .. } => {
                assert_eq!(task_id, "t-1");
                assert_eq!(*issue_num, 10);
            }
            _ => panic!("expected Update"),
        }
    }

    #[test]
    fn test_plan_sync_unchanged_skipped() {
        let tasks = vec![
            json!({"id": "t-1", "subject": "Same", "stream": "roadmap", "type": "task", "status": "pending", "priority": null, "effort": null, "tags": []}),
        ];
        let mut map = HashMap::new();
        map.insert("t-1".into(), 10);
        let mut hashes = HashMap::new();
        hashes.insert("t-1".into(), "pending|||Same".into());

        let plan = plan_sync(&tasks, &map, &hashes, &test_config());
        assert_eq!(plan.actions.len(), 0); // no change
    }

    #[test]
    fn test_plan_sync_filters_by_stream() {
        let tasks = vec![
            json!({"id": "t-1", "subject": "Keep", "stream": "roadmap", "type": "task", "status": "pending", "tags": []}),
            json!({"id": "t-2", "subject": "Skip", "stream": "personal", "type": "task", "status": "pending", "tags": []}),
        ];
        let plan = plan_sync(&tasks, &HashMap::new(), &HashMap::new(), &test_config());
        assert_eq!(plan.actions.len(), 1);
    }

    #[test]
    fn test_plan_sync_phases_first() {
        let tasks = vec![
            json!({"id": "t-1", "subject": "Task", "stream": "roadmap", "type": "task", "status": "pending", "tags": [], "order": 1}),
            json!({"id": "ph-1", "subject": "Phase", "stream": "roadmap", "type": "phase", "status": "pending", "tags": [], "order": 1}),
        ];
        let plan = plan_sync(&tasks, &HashMap::new(), &HashMap::new(), &test_config());
        assert_eq!(plan.actions.len(), 2);
        match &plan.actions[0] {
            SyncAction::Create { task_id, .. } => assert_eq!(task_id, "ph-1"), // phase first
            _ => panic!("expected Create"),
        }
    }

    #[test]
    fn test_plan_sync_close_completed() {
        let tasks = vec![
            json!({"id": "t-1", "subject": "Done", "stream": "roadmap", "type": "task", "status": "completed", "tags": []}),
        ];
        let mut map = HashMap::new();
        map.insert("t-1".into(), 10);
        let mut hashes = HashMap::new();
        hashes.insert("t-1".into(), "pending|||Done".into());

        let plan = plan_sync(&tasks, &map, &hashes, &test_config());
        match &plan.actions[0] {
            SyncAction::Update { close_reason, reopen, .. } => {
                assert_eq!(close_reason.as_deref(), Some("completed"));
                assert!(!reopen);
            }
            _ => panic!("expected Update"),
        }
    }
}
