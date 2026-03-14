//! Shared task loading, filtering, and classification logic.
//! Used by brana (dispatcher), brana-query, and brana-fmt.

use serde::Deserialize;
use serde_json::Value;
use std::collections::HashSet;
use std::path::Path;

#[derive(Deserialize)]
pub struct TasksFile {
    #[serde(default)]
    pub project: String,
    #[serde(default)]
    pub tasks: Vec<Value>,
}

/// Load tasks from file. Supports both {tasks: [...]} and bare [...].
pub fn load_tasks(path: &Path) -> Result<TasksFile, String> {
    let content = std::fs::read_to_string(path)
        .map_err(|e| format!("{}: {}", path.display(), e))?;
    let content = content.trim();
    if content.is_empty() {
        return Ok(TasksFile {
            project: "unknown".into(),
            tasks: vec![],
        });
    }
    if let Ok(tf) = serde_json::from_str::<TasksFile>(content) {
        return Ok(tf);
    }
    if let Ok(arr) = serde_json::from_str::<Vec<Value>>(content) {
        return Ok(TasksFile {
            project: "unknown".into(),
            tasks: arr,
        });
    }
    Err(format!("invalid JSON in {}", path.display()))
}

/// Classify a task's effective status.
pub fn classify(task: &Value, all: &[Value]) -> &'static str {
    match task["status"].as_str().unwrap_or("") {
        "completed" | "cancelled" => "done",
        "in_progress" => "active",
        _ => {
            if let Some(deps) = task["blocked_by"].as_array() {
                if !deps.is_empty() {
                    let done_ids: HashSet<&str> = all
                        .iter()
                        .filter(|t| {
                            matches!(t["status"].as_str(), Some("completed" | "cancelled"))
                        })
                        .filter_map(|t| t["id"].as_str())
                        .collect();
                    if !deps
                        .iter()
                        .all(|d| done_ids.contains(d.as_str().unwrap_or("")))
                    {
                        return "blocked";
                    }
                }
            }
            if task["tags"]
                .as_array()
                .map_or(false, |t| t.iter().any(|v| v.as_str() == Some("parked")))
            {
                return "parked";
            }
            "pending"
        }
    }
}

/// Free-text search across subject, description, context, notes.
pub fn text_match(task: &Value, needle: &str) -> bool {
    let n = needle.to_lowercase();
    ["subject", "description", "context", "notes"]
        .iter()
        .any(|f| {
            task[f]
                .as_str()
                .map_or(false, |v| v.to_lowercase().contains(&n))
        })
}

/// Filter tasks by multiple criteria (AND logic).
pub fn filter_tasks<'a>(
    tasks: &'a [Value],
    all: &[Value],
    tag: Option<&str>,
    status: Option<&str>,
    stream: Option<&str>,
    priority: Option<&str>,
    effort: Option<&str>,
    search: Option<&str>,
    types: &[&str],
) -> Vec<&'a Value> {
    tasks
        .iter()
        .filter(|t| {
            let tt = t["type"].as_str().unwrap_or("task");
            if !types.contains(&tt) {
                return false;
            }
            if let Some(s) = status {
                if classify(t, all) != s {
                    return false;
                }
            }
            if let Some(tag) = tag {
                let tags: Vec<&str> = t["tags"]
                    .as_array()
                    .map(|a| a.iter().filter_map(|v| v.as_str()).collect())
                    .unwrap_or_default();
                if !tags.contains(&tag) {
                    return false;
                }
            }
            if let Some(s) = stream {
                if t["stream"].as_str().unwrap_or("") != s {
                    return false;
                }
            }
            if let Some(p) = priority {
                if t["priority"].as_str().unwrap_or("") != p {
                    return false;
                }
            }
            if let Some(e) = effort {
                if t["effort"].as_str().unwrap_or("") != e {
                    return false;
                }
            }
            if let Some(q) = search {
                if !text_match(t, q) {
                    return false;
                }
            }
            true
        })
        .collect()
}

/// Sort by priority (P0 first), then status (in_progress first), then order.
pub fn sort_by_priority(tasks: &mut [&Value]) {
    tasks.sort_by(|a, b| {
        let pri = |t: &Value| match t["priority"].as_str() {
            Some("P0") => 0,
            Some("P1") => 1,
            Some("P2") => 2,
            Some("P3") => 3,
            _ => 4,
        };
        let status_ord = |t: &Value| {
            if t["status"].as_str() == Some("in_progress") {
                0
            } else {
                1
            }
        };
        let order = |t: &Value| t["order"].as_i64().unwrap_or(999);

        (pri(a), status_ord(a), order(a)).cmp(&(pri(b), status_ord(b), order(b)))
    });
}

/// Focus score: priority weight + staleness - effort - blocked depth.
pub fn focus_score(task: &Value) -> f64 {
    let pri = match task["priority"].as_str() {
        Some("P0") => 400.0,
        Some("P1") => 300.0,
        Some("P2") => 200.0,
        Some("P3") => 100.0,
        _ => 50.0,
    };

    let staleness = task["created"]
        .as_str()
        .and_then(|d| chrono::NaiveDate::parse_from_str(d, "%Y-%m-%d").ok())
        .map(|d| (chrono::Local::now().date_naive() - d).num_days() as f64 * 2.0)
        .unwrap_or(0.0);

    let effort = match task["effort"].as_str() {
        Some("S") => 10.0,
        Some("M") => 20.0,
        Some("L") => 30.0,
        Some("XL") => 40.0,
        _ => 15.0,
    };

    let blocked_depth = task["blocked_by"]
        .as_array()
        .map_or(0, |a| a.len()) as f64
        * 50.0;

    pri + staleness - effort - blocked_depth
}

/// Find duplicate task IDs.
pub fn find_duplicate_ids(tasks: &[Value]) -> Vec<String> {
    let mut seen = HashSet::new();
    let mut dupes = Vec::new();
    for t in tasks {
        if let Some(id) = t["id"].as_str() {
            if !seen.insert(id) {
                dupes.push(id.to_string());
            }
        }
    }
    dupes
}

/// Validate tasks.json schema. Returns list of error strings.
pub fn validate_schema(path: &Path) -> Vec<String> {
    let content = match std::fs::read_to_string(path) {
        Ok(c) => c,
        Err(e) => return vec![format!("cannot read file: {e}")],
    };
    let content = content.trim();
    if content.is_empty() {
        return vec!["file is empty".into()];
    }

    let val: Value = match serde_json::from_str(content) {
        Ok(v) => v,
        Err(_) => return vec!["invalid JSON".into()],
    };

    let mut errors = Vec::new();

    if val["version"].is_null() {
        errors.push("missing version".into());
    }
    if val["project"].is_null() {
        errors.push("missing project".into());
    }
    if !val["tasks"].is_array() {
        errors.push("tasks must be array".into());
        return errors;
    }

    let valid_statuses = ["pending", "in_progress", "completed", "cancelled"];
    let valid_types = ["phase", "milestone", "task", "subtask"];

    if let Some(tasks) = val["tasks"].as_array() {
        for t in tasks {
            let id = t["id"].as_str().unwrap_or("?");
            if t["id"].is_null() {
                errors.push("task missing id".into());
            }
            if t["subject"].is_null() {
                errors.push(format!("task {id} missing subject"));
            }
            if t["status"].is_null() {
                errors.push(format!("task {id} missing status"));
            } else if let Some(s) = t["status"].as_str() {
                if !valid_statuses.contains(&s) {
                    errors.push(format!("task {id}: invalid status {s}"));
                }
            }
            if t["type"].is_null() {
                errors.push(format!("task {id} missing type"));
            } else if let Some(tp) = t["type"].as_str() {
                if !valid_types.contains(&tp) {
                    errors.push(format!("task {id}: invalid type {tp}"));
                }
            }
            if t["stream"].is_null() {
                errors.push(format!("task {id} missing stream"));
            }
            if !t["tags"].is_null() {
                if !t["tags"].is_array() {
                    errors.push(format!("task {id}: tags must be array"));
                } else if let Some(tags) = t["tags"].as_array() {
                    if tags.iter().any(|v| !v.is_string()) {
                        errors.push(format!("task {id}: tags items must be strings"));
                    }
                }
            }
            if !t["context"].is_null() && !t["context"].is_string() {
                errors.push(format!("task {id}: context must be string"));
            }
        }
    }

    errors
}

/// Find parent IDs that should be auto-completed (all children done).
pub fn find_rollup_candidates(tasks: &[Value]) -> Vec<String> {
    let mut candidates = Vec::new();
    for parent in tasks
        .iter()
        .filter(|t| matches!(t["type"].as_str(), Some("milestone" | "phase")))
    {
        let pid = match parent["id"].as_str() {
            Some(id) => id,
            None => continue,
        };
        if parent["status"].as_str() == Some("completed") {
            continue;
        }

        let children: Vec<_> = tasks
            .iter()
            .filter(|t| t["parent"].as_str() == Some(pid))
            .collect();

        if !children.is_empty()
            && children
                .iter()
                .all(|c| c["status"].as_str() == Some("completed"))
        {
            candidates.push(pid.to_string());
        }
    }
    candidates
}

/// Perform rollup: mark parents as completed, write back to file.
/// Returns list of completed parent IDs.
pub fn perform_rollup(path: &Path, dry_run: bool) -> Result<Vec<String>, String> {
    let content =
        std::fs::read_to_string(path).map_err(|e| format!("{}: {e}", path.display()))?;
    let mut val: Value =
        serde_json::from_str(content.trim()).map_err(|e| format!("invalid JSON: {e}"))?;

    let tasks = val["tasks"]
        .as_array()
        .ok_or("tasks is not an array")?;
    let candidates = find_rollup_candidates(tasks);

    if candidates.is_empty() || dry_run {
        return Ok(candidates);
    }

    let today = chrono::Local::now().format("%Y-%m-%d").to_string();
    let now = chrono::Local::now().to_rfc3339();

    if let Some(tasks) = val["tasks"].as_array_mut() {
        for t in tasks.iter_mut() {
            if let Some(id) = t["id"].as_str() {
                if candidates.contains(&id.to_string()) {
                    t["status"] = Value::String("completed".into());
                    t["completed"] = Value::String(today.clone());
                }
            }
        }
    }
    val["last_modified"] = Value::String(now);

    std::fs::write(
        path,
        serde_json::to_string_pretty(&val).unwrap() + "\n",
    )
    .map_err(|e| format!("write failed: {e}"))?;

    Ok(candidates)
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn sample_tasks() -> Vec<Value> {
        vec![
            json!({"id": "t-001", "status": "completed", "type": "task", "tags": ["auth"], "blocked_by": []}),
            json!({"id": "t-002", "status": "in_progress", "type": "task", "tags": ["api"], "blocked_by": [], "build_step": "build"}),
            json!({"id": "t-003", "status": "pending", "type": "task", "tags": ["scheduler"], "blocked_by": [], "priority": "P2", "effort": "S", "created": "2026-01-15"}),
            json!({"id": "t-004", "status": "pending", "type": "task", "tags": ["scheduler", "dx"], "blocked_by": ["t-002"]}),
            json!({"id": "t-005", "status": "pending", "type": "task", "tags": ["parked"], "blocked_by": []}),
            json!({"id": "t-006", "status": "cancelled", "type": "task", "tags": [], "blocked_by": []}),
            json!({"id": "ph-001", "status": "pending", "type": "phase", "tags": [], "blocked_by": []}),
        ]
    }

    #[test]
    fn test_classify_completed() {
        let tasks = sample_tasks();
        assert_eq!(classify(&tasks[0], &tasks), "done");
    }

    #[test]
    fn test_classify_cancelled() {
        let tasks = sample_tasks();
        assert_eq!(classify(&tasks[5], &tasks), "done");
    }

    #[test]
    fn test_classify_in_progress() {
        let tasks = sample_tasks();
        assert_eq!(classify(&tasks[1], &tasks), "active");
    }

    #[test]
    fn test_classify_pending_unblocked() {
        let tasks = sample_tasks();
        assert_eq!(classify(&tasks[2], &tasks), "pending");
    }

    #[test]
    fn test_classify_blocked() {
        let tasks = sample_tasks();
        assert_eq!(classify(&tasks[3], &tasks), "blocked");
    }

    #[test]
    fn test_classify_parked() {
        let tasks = sample_tasks();
        assert_eq!(classify(&tasks[4], &tasks), "parked");
    }

    #[test]
    fn test_cancelled_blocker_unblocks() {
        let tasks = vec![
            json!({"id": "t-a", "status": "cancelled", "tags": [], "blocked_by": []}),
            json!({"id": "t-b", "status": "pending", "type": "task", "tags": [], "blocked_by": ["t-a"]}),
        ];
        assert_eq!(classify(&tasks[1], &tasks), "pending");
    }

    #[test]
    fn test_filter_by_tag() {
        let tasks = sample_tasks();
        let result = filter_tasks(&tasks, &tasks, Some("scheduler"), None, None, None, None, None, &["task", "subtask"]);
        assert_eq!(result.len(), 2);
    }

    #[test]
    fn test_filter_by_status() {
        let tasks = sample_tasks();
        let result = filter_tasks(&tasks, &tasks, None, Some("active"), None, None, None, None, &["task", "subtask"]);
        assert_eq!(result.len(), 1);
        assert_eq!(result[0]["id"].as_str().unwrap(), "t-002");
    }

    #[test]
    fn test_filter_excludes_phases() {
        let tasks = sample_tasks();
        let result = filter_tasks(&tasks, &tasks, None, None, None, None, None, None, &["task", "subtask"]);
        assert!(result.iter().all(|t| t["type"].as_str().unwrap() != "phase"));
    }

    #[test]
    fn test_text_match() {
        let task = json!({"subject": "Fix JWT middleware", "description": "Auth token handling"});
        assert!(text_match(&task, "jwt"));
        assert!(text_match(&task, "auth"));
        assert!(!text_match(&task, "database"));
    }

    #[test]
    fn test_sort_by_priority() {
        let tasks = vec![
            json!({"priority": "P2", "status": "pending", "order": 1}),
            json!({"priority": "P0", "status": "pending", "order": 1}),
            json!({"priority": null, "status": "pending", "order": 1}),
            json!({"priority": "P1", "status": "in_progress", "order": 1}),
        ];
        let mut refs: Vec<&Value> = tasks.iter().collect();
        sort_by_priority(&mut refs);
        assert_eq!(refs[0]["priority"].as_str(), Some("P0"));
        assert_eq!(refs[1]["priority"].as_str(), Some("P1"));
        assert_eq!(refs[2]["priority"].as_str(), Some("P2"));
        assert!(refs[3]["priority"].is_null());
    }

    #[test]
    fn test_focus_score_priority_matters() {
        let p0 = json!({"priority": "P0", "effort": "S", "created": "2026-03-01", "blocked_by": []});
        let p3 = json!({"priority": "P3", "effort": "S", "created": "2026-03-01", "blocked_by": []});
        assert!(focus_score(&p0) > focus_score(&p3));
    }

    #[test]
    fn test_focus_score_smaller_effort_wins() {
        let small = json!({"priority": "P2", "effort": "S", "created": "2026-03-01", "blocked_by": []});
        let large = json!({"priority": "P2", "effort": "XL", "created": "2026-03-01", "blocked_by": []});
        assert!(focus_score(&small) > focus_score(&large));
    }

    #[test]
    fn test_find_duplicate_ids() {
        let tasks = vec![
            json!({"id": "t-001"}),
            json!({"id": "t-002"}),
            json!({"id": "t-001"}),
        ];
        let dupes = find_duplicate_ids(&tasks);
        assert_eq!(dupes, vec!["t-001"]);
    }

    #[test]
    fn test_no_duplicates() {
        let tasks = vec![json!({"id": "t-001"}), json!({"id": "t-002"})];
        assert!(find_duplicate_ids(&tasks).is_empty());
    }

    #[test]
    fn test_rollup_all_children_done() {
        let tasks = vec![
            json!({"id": "ms-001", "type": "milestone", "status": "pending", "parent": null}),
            json!({"id": "t-010", "type": "task", "status": "completed", "parent": "ms-001"}),
            json!({"id": "t-011", "type": "task", "status": "completed", "parent": "ms-001"}),
        ];
        let candidates = find_rollup_candidates(&tasks);
        assert_eq!(candidates, vec!["ms-001"]);
    }

    #[test]
    fn test_rollup_not_all_children_done() {
        let tasks = vec![
            json!({"id": "ms-001", "type": "milestone", "status": "pending", "parent": null}),
            json!({"id": "t-010", "type": "task", "status": "completed", "parent": "ms-001"}),
            json!({"id": "t-011", "type": "task", "status": "pending", "parent": "ms-001"}),
        ];
        let candidates = find_rollup_candidates(&tasks);
        assert!(candidates.is_empty());
    }

    #[test]
    fn test_rollup_already_completed_parent() {
        let tasks = vec![
            json!({"id": "ms-001", "type": "milestone", "status": "completed", "parent": null}),
            json!({"id": "t-010", "type": "task", "status": "completed", "parent": "ms-001"}),
        ];
        let candidates = find_rollup_candidates(&tasks);
        assert!(candidates.is_empty());
    }

    #[test]
    fn test_rollup_no_children() {
        let tasks = vec![
            json!({"id": "ms-001", "type": "milestone", "status": "pending", "parent": null}),
        ];
        let candidates = find_rollup_candidates(&tasks);
        assert!(candidates.is_empty());
    }

    #[test]
    fn test_validate_schema_valid() {
        let dir = std::env::temp_dir().join("brana-test-validate");
        std::fs::create_dir_all(&dir).ok();
        let path = dir.join("valid.json");
        std::fs::write(&path, r#"{"version":"1","project":"test","tasks":[
            {"id":"t-1","subject":"Test","status":"pending","type":"task","stream":"roadmap","tags":["a"],"context":"ctx"}
        ]}"#).unwrap();
        let errors = validate_schema(&path);
        assert!(errors.is_empty(), "expected no errors, got: {:?}", errors);
        std::fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn test_validate_schema_missing_fields() {
        let dir = std::env::temp_dir().join("brana-test-validate2");
        std::fs::create_dir_all(&dir).ok();
        let path = dir.join("invalid.json");
        std::fs::write(&path, r#"{"tasks":[{"id":"t-1"}]}"#).unwrap();
        let errors = validate_schema(&path);
        assert!(errors.iter().any(|e| e.contains("missing version")));
        assert!(errors.iter().any(|e| e.contains("missing project")));
        assert!(errors.iter().any(|e| e.contains("missing subject")));
        assert!(errors.iter().any(|e| e.contains("missing status")));
        std::fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn test_validate_schema_invalid_json() {
        let dir = std::env::temp_dir().join("brana-test-validate3");
        std::fs::create_dir_all(&dir).ok();
        let path = dir.join("bad.json");
        std::fs::write(&path, "not json at all").unwrap();
        let errors = validate_schema(&path);
        assert_eq!(errors, vec!["invalid JSON"]);
        std::fs::remove_dir_all(&dir).ok();
    }
}
