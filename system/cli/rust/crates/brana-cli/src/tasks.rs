//! Shared task loading, filtering, and classification logic.
//! Used by brana (dispatcher), brana-query, and brana-fmt.

use serde::Deserialize;
use serde_json::Value;
use std::collections::{HashMap, HashSet};
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

/// Save a TasksFile back to disk (pretty-printed).
pub fn save_tasks(path: &Path, val: &Value) -> Result<(), String> {
    std::fs::write(path, serde_json::to_string_pretty(val).unwrap() + "\n")
        .map_err(|e| format!("write failed: {e}"))
}

/// Load tasks as raw serde_json::Value (preserves all fields for mutation).
/// Normalizes bare JSON arrays into `{tasks: [...]}` so callers can always use `val["tasks"]`.
pub fn load_raw(path: &Path) -> Result<Value, String> {
    let content = std::fs::read_to_string(path)
        .map_err(|e| format!("{}: {e}", path.display()))?;
    let val: Value = serde_json::from_str(content.trim()).map_err(|e| format!("invalid JSON: {e}"))?;
    if val.is_array() {
        Ok(serde_json::json!({"tasks": val}))
    } else {
        Ok(val)
    }
}

/// Find the next available task ID (highest numeric suffix + 1).
pub fn next_id(tasks: &[Value]) -> String {
    let max = tasks.iter()
        .filter_map(|t| t["id"].as_str())
        .filter_map(|id| id.split('-').last()?.parse::<u32>().ok())
        .max()
        .unwrap_or(0);
    format!("t-{}", max + 1)
}

/// Set a field on a task. Handles scalars, array append (+val)/remove (-val), and --append for text.
pub fn set_field(task: &mut Value, field: &str, value: &str, append: bool) -> Result<(), String> {
    match field {
        "tags" | "blocked_by" => {
            let arr = task[field].as_array_mut()
                .ok_or_else(|| format!("{field} is not an array"))?;
            if let Some(stripped) = value.strip_prefix('+') {
                let v = Value::String(stripped.to_string());
                if !arr.contains(&v) { arr.push(v); }
            } else if let Some(stripped) = value.strip_prefix('-') {
                arr.retain(|v| v.as_str() != Some(stripped));
            } else {
                return Err(format!("use +val or -val for array fields (got: {value})"));
            }
            Ok(())
        }
        "context" | "notes" | "description" => {
            if append {
                let existing = task[field].as_str().unwrap_or("").to_string();
                let new_val = if existing.is_empty() {
                    value.to_string()
                } else {
                    format!("{existing}\n{value}")
                };
                task[field] = Value::String(new_val);
            } else {
                task[field] = Value::String(value.to_string());
            }
            Ok(())
        }
        "priority" | "effort" | "status" | "stream" | "type" | "strategy"
        | "build_step" | "execution" | "branch" | "subject" | "parent"
        | "started" | "completed" | "created" | "github_issue" => {
            if value == "null" {
                task[field] = Value::Null;
            } else {
                task[field] = Value::String(value.to_string());
            }
            Ok(())
        }
        _ => Err(format!("unknown field: {field}")),
    }
}

/// Collect tag inventory: tag -> {total, pending, active, done, blocked}.
pub fn tag_inventory(tasks: &[Value], all: &[Value]) -> Vec<(String, HashMap<String, usize>)> {
    let mut map: HashMap<String, HashMap<String, usize>> = HashMap::new();
    for t in tasks.iter().filter(|t| matches!(t["type"].as_str(), Some("task" | "subtask"))) {
        if let Some(tags) = t["tags"].as_array() {
            let st = classify(t, all);
            for tag in tags.iter().filter_map(|v| v.as_str()) {
                let entry = map.entry(tag.to_string()).or_default();
                *entry.entry("total".into()).or_default() += 1;
                *entry.entry(st.into()).or_default() += 1;
            }
        }
    }
    let mut result: Vec<_> = map.into_iter().collect();
    result.sort_by(|a, b| b.1.get("total").unwrap_or(&0).cmp(a.1.get("total").unwrap_or(&0)));
    result
}

/// Compute aggregate stats by status, stream, priority, type.
pub fn compute_stats(tasks: &[Value], all: &[Value]) -> Value {
    let mut by_status: HashMap<String, usize> = HashMap::new();
    let mut by_stream: HashMap<String, HashMap<String, usize>> = HashMap::new();
    let mut by_priority: HashMap<String, usize> = HashMap::new();
    let mut by_type: HashMap<String, usize> = HashMap::new();

    for t in tasks {
        let st = classify(t, all).to_string();
        let stream = t["stream"].as_str().unwrap_or("none").to_string();
        let pri = t["priority"].as_str().unwrap_or("null").to_string();
        let tp = t["type"].as_str().unwrap_or("task").to_string();

        *by_status.entry(st.clone()).or_default() += 1;
        let stream_entry = by_stream.entry(stream).or_default();
        *stream_entry.entry("total".into()).or_default() += 1;
        *stream_entry.entry(st).or_default() += 1;
        *by_priority.entry(pri).or_default() += 1;
        *by_type.entry(tp).or_default() += 1;
    }

    serde_json::json!({
        "total": tasks.len(),
        "by_status": by_status,
        "by_stream": by_stream,
        "by_priority": by_priority,
        "by_type": by_type,
    })
}

/// Build a tree structure from parent references.
pub fn build_tree(tasks: &[Value], all: &[Value]) -> Vec<Value> {
    let root_ids: Vec<&str> = tasks.iter()
        .filter(|t| matches!(t["type"].as_str(), Some("phase")))
        .filter_map(|t| t["id"].as_str())
        .collect();

    let mut result = Vec::new();
    for rid in &root_ids {
        if let Some(phase) = tasks.iter().find(|t| t["id"].as_str() == Some(rid)) {
            result.push(build_node(phase, tasks, all));
        }
    }

    // Orphan tasks (no parent, not a phase/milestone)
    let parented: HashSet<&str> = tasks.iter()
        .filter_map(|t| t["parent"].as_str())
        .collect();
    let _phase_ms_ids: HashSet<&str> = tasks.iter()
        .filter(|t| matches!(t["type"].as_str(), Some("phase" | "milestone")))
        .filter_map(|t| t["id"].as_str())
        .collect();

    // Tasks under milestones are already included, tasks without parent go to streams
    let orphans: Vec<&Value> = tasks.iter()
        .filter(|t| matches!(t["type"].as_str(), Some("task" | "subtask")))
        .filter(|t| t["parent"].as_str().is_none() || t["parent"].is_null())
        .filter(|t| !parented.contains(t["id"].as_str().unwrap_or("")))
        .collect();

    if !orphans.is_empty() {
        // Group by stream
        let mut by_stream: HashMap<String, Vec<Value>> = HashMap::new();
        for t in orphans {
            let stream = t["stream"].as_str().unwrap_or("other").to_string();
            let st = classify(t, all);
            let mut node = serde_json::json!({
                "id": t["id"],
                "subject": t["subject"],
                "type": t["type"],
                "status": st,
            });
            if let Some(bs) = t["build_step"].as_str() {
                node["build_step"] = Value::String(bs.into());
            }
            by_stream.entry(stream).or_default().push(node);
        }
        for (stream, tasks) in by_stream {
            result.push(serde_json::json!({
                "id": stream,
                "subject": stream,
                "type": "stream",
                "children": tasks,
            }));
        }
    }

    result
}

fn build_node(task: &Value, all_tasks: &[Value], all: &[Value]) -> Value {
    let id = task["id"].as_str().unwrap_or("?");
    let st = classify(task, all);

    // Find children
    let children: Vec<Value> = all_tasks.iter()
        .filter(|t| t["parent"].as_str() == Some(id))
        .map(|t| build_node(t, all_tasks, all))
        .collect();

    // Compute progress from leaf tasks
    let (done, total) = count_leaves(&children, task);

    let mut node = serde_json::json!({
        "id": id,
        "subject": task["subject"],
        "type": task["type"],
        "status": st,
    });
    if !children.is_empty() {
        node["children"] = Value::Array(children);
        node["progress"] = serde_json::json!({"done": done, "total": total});
    }
    if let Some(bs) = task["build_step"].as_str() {
        node["build_step"] = Value::String(bs.into());
    }
    node
}

fn count_leaves(children: &[Value], _parent: &Value) -> (usize, usize) {
    let mut done = 0;
    let mut total = 0;
    for c in children {
        if let Some(sub) = c["children"].as_array() {
            if !sub.is_empty() {
                let (d, t) = count_leaves(sub, c);
                done += d;
                total += t;
                continue;
            }
        }
        total += 1;
        if c["status"].as_str() == Some("done") {
            done += 1;
        }
    }
    (done, total)
}

/// Get subtree of a specific task (phase or milestone).
pub fn subtree(tasks: &[Value], all: &[Value], root_id: &str) -> Option<Value> {
    tasks.iter()
        .find(|t| t["id"].as_str() == Some(root_id))
        .map(|t| build_node(t, tasks, all))
}

/// Load tasks-portfolio.json and aggregate status across all projects.
pub fn portfolio_status() -> Result<Vec<Value>, String> {
    let home = std::env::var("HOME").unwrap_or_default();
    let portfolio_path = std::path::PathBuf::from(&home).join(".claude/tasks-portfolio.json");
    let content = std::fs::read_to_string(&portfolio_path)
        .map_err(|_| "tasks-portfolio.json not found".to_string())?;
    let portfolio: Value = serde_json::from_str(&content)
        .map_err(|e| format!("invalid portfolio JSON: {e}"))?;

    let mut results = Vec::new();

    // Support both { clients: [...] } and { projects: [...] } schemas
    let clients = if let Some(clients) = portfolio["clients"].as_array() {
        clients.clone()
    } else if let Some(projects) = portfolio["projects"].as_array() {
        // Legacy: wrap each project as a single-project client
        projects.iter().map(|p| {
            let slug = p["slug"].as_str().or_else(|| p["name"].as_str()).unwrap_or("unknown");
            serde_json::json!({"slug": slug, "projects": [p]})
        }).collect()
    } else {
        return Err("portfolio has no clients or projects array".into());
    };

    for client in &clients {
        let client_slug = client["slug"].as_str().unwrap_or("unknown");
        let projects = client["projects"].as_array().cloned().unwrap_or_default();
        for proj in &projects {
            let proj_slug = proj["slug"].as_str().unwrap_or(client_slug);
            let path_str = proj["path"].as_str().unwrap_or("");
            let resolved = path_str.replace("~/", &format!("{home}/"));
            let tasks_path = std::path::PathBuf::from(&resolved).join(".claude/tasks.json");

            if !tasks_path.exists() { continue; }

            let data = match load_tasks(&tasks_path) {
                Ok(d) => d,
                Err(_) => continue,
            };

            let task_items: Vec<_> = data.tasks.iter()
                .filter(|t| matches!(t["type"].as_str(), Some("task" | "subtask")))
                .collect();
            let total = task_items.len();
            let done = task_items.iter().filter(|t| classify(t, &data.tasks) == "done").count();
            let active = task_items.iter().filter(|t| classify(t, &data.tasks) == "active").count();
            let blocked = task_items.iter().filter(|t| classify(t, &data.tasks) == "blocked").count();

            let active_tasks: Vec<Value> = data.tasks.iter()
                .filter(|t| classify(t, &data.tasks) == "active")
                .map(|t| serde_json::json!({"id": t["id"], "subject": t["subject"]}))
                .collect();

            results.push(serde_json::json!({
                "client": client_slug,
                "project": proj_slug,
                "path": resolved,
                "total": total,
                "done": done,
                "active": active,
                "blocked": blocked,
                "active_tasks": active_tasks,
            }));
        }
    }

    Ok(results)
}

// ── Run command helpers (pure, testable) ─────────────────────────────

/// Compute the git branch name for a task based on stream + id + subject.
pub fn branch_for_task(task: &Value) -> String {
    let stream = task["stream"].as_str().unwrap_or("roadmap");
    let prefix = match stream {
        "bugs" => "fix",
        "tech-debt" => "refactor",
        "docs" => "docs",
        "experiments" => "experiment",
        "research" => "research",
        _ => "feat",
    };
    let id = task["id"].as_str().unwrap_or("t-000");
    let subject = task["subject"].as_str().unwrap_or("task");
    let slug: String = subject
        .to_lowercase()
        .chars()
        .map(|c| if c.is_alphanumeric() { c } else { '-' })
        .collect::<String>()
        .split('-')
        .filter(|s| !s.is_empty())
        .collect::<Vec<_>>()
        .join("-");
    let slug = if slug.len() > 40 { &slug[..40] } else { &slug };
    format!("{prefix}/{id}-{slug}")
}

/// Compute the worktree directory path for a task.
pub fn worktree_path_for_task(task: &Value, repo_name: &str) -> String {
    let stream = task["stream"].as_str().unwrap_or("roadmap");
    let prefix = match stream {
        "bugs" => "fix",
        "tech-debt" => "refactor",
        "docs" => "docs",
        "experiments" => "experiment",
        "research" => "research",
        _ => "feat",
    };
    let id = task["id"].as_str().unwrap_or("t-000");
    format!("../{repo_name}-{prefix}/{id}")
}

/// Validate that a task can be run: must be pending and not blocked.
pub fn validate_task_runnable(task: &Value, all: &[Value]) -> Result<(), String> {
    let id = task["id"].as_str().unwrap_or("?");
    let status = task["status"].as_str().unwrap_or("");
    if status == "in_progress" {
        return Err(format!("{id} already in_progress"));
    }
    if status != "pending" {
        return Err(format!("{id} is {status}, not pending"));
    }
    if let Some(deps) = task["blocked_by"].as_array() {
        for dep in deps {
            if let Some(dep_id) = dep.as_str() {
                if let Some(bt) = all.iter().find(|t| t["id"].as_str() == Some(dep_id)) {
                    if bt["status"].as_str() != Some("completed") {
                        let bs = bt["status"].as_str().unwrap_or("?");
                        return Err(format!("{id} blocked by {dep_id} ({bs})"));
                    }
                }
            }
        }
    }
    Ok(())
}

// ── Agent management (agents.json) ───────────────────────────────────

/// Load agents from agents.json. Returns empty vec if file doesn't exist.
pub fn load_agents(path: &Path) -> Vec<Value> {
    match std::fs::read_to_string(path) {
        Ok(content) => {
            let content = content.trim();
            if content.is_empty() { return vec![]; }
            serde_json::from_str(content).unwrap_or_default()
        }
        Err(_) => vec![],
    }
}

/// Save agents to agents.json.
pub fn save_agents(path: &Path, agents: &[Value]) -> Result<(), String> {
    let json = serde_json::to_string_pretty(agents)
        .map_err(|e| format!("serialize error: {e}"))?;
    std::fs::write(path, json).map_err(|e| format!("{}: {e}", path.display()))
}

/// Check if a PID is alive by testing /proc/{pid}/status.
pub fn is_pid_alive(pid: u32) -> bool {
    Path::new(&format!("/proc/{pid}")).exists()
}

/// Remove dead agents from the list. Returns (alive, removed_count).
pub fn prune_dead_agents(agents: Vec<Value>) -> (Vec<Value>, usize) {
    let before = agents.len();
    let alive: Vec<Value> = agents
        .into_iter()
        .filter(|a| {
            a["pid"].as_u64()
                .map(|pid| is_pid_alive(pid as u32))
                .unwrap_or(false)
        })
        .collect();
    let removed = before - alive.len();
    (alive, removed)
}

/// Create an agent entry for agents.json.
pub fn new_agent_entry(
    task_id: &str,
    pid: u32,
    tmux_target: &str,
    worktree: &str,
    branch: &str,
) -> Value {
    let id = format!("agent-{}", chrono::Local::now().format("%H%M%S"));
    serde_json::json!({
        "id": id,
        "task_id": task_id,
        "pid": pid,
        "tmux_target": tmux_target,
        "worktree": worktree,
        "branch": branch,
        "started": chrono::Local::now().format("%Y-%m-%dT%H:%M:%SZ").to_string(),
        "status": "active"
    })
}

/// Compute model routing score for a task (0.0–1.0).
/// Higher score = more complex = needs stronger model.
pub fn complexity_score(task: &Value) -> f64 {
    let mut score = 0.0;

    // Description length
    let desc_words = task["description"].as_str().unwrap_or("").split_whitespace().count();
    score += (desc_words as f64 / 100.0).min(0.3);

    // Dependency count
    let deps = task["blocked_by"].as_array().map(|a| a.len()).unwrap_or(0);
    score += (deps as f64 * 0.1).min(0.2);

    // Stream type
    if task["stream"].as_str() == Some("roadmap") {
        score += 0.2;
    }

    // Architecture tag
    if let Some(tags) = task["tags"].as_array() {
        if tags.iter().any(|t| t.as_str() == Some("architecture")) {
            score += 0.1;
        }
    }

    // Effort estimate
    match task["effort"].as_str() {
        Some("L") | Some("XL") => score += 0.1,
        _ => {}
    }

    score.min(1.0)
}

/// Recommend model based on complexity score.
pub fn recommended_model(score: f64) -> &'static str {
    if score < 0.3 { "haiku" }
    else if score <= 0.7 { "sonnet" }
    else { "opus" }
}

/// Build queue candidates: unblocked pending tasks sorted by priority with model recommendations.
pub fn queue_candidates(tasks: &[Value], max: usize) -> Vec<Value> {
    let mut pending_refs: Vec<&Value> = tasks.iter()
        .filter(|t| {
            let status = t["status"].as_str().unwrap_or("");
            let ttype = t["type"].as_str().unwrap_or("task");
            status == "pending" && (ttype == "task" || ttype == "subtask")
        })
        .filter(|t| validate_task_runnable(t, tasks).is_ok())
        .collect();

    sort_by_priority(&mut pending_refs);

    pending_refs.into_iter().take(max).map(|t| {
        let score = complexity_score(&t);
        let model = recommended_model(score);
        serde_json::json!({
            "id": t["id"],
            "subject": t["subject"],
            "priority": t["priority"],
            "effort": t["effort"],
            "stream": t["stream"],
            "score": (score * 100.0).round() / 100.0,
            "model": model,
        })
    }).collect()
}

/// Check if running inside a tmux session.
pub fn is_in_tmux() -> bool {
    std::env::var("TMUX").is_ok()
}

/// Format agents as a table string for CLI output.
pub fn format_agents_table(agents: &[Value]) -> String {
    if agents.is_empty() {
        return "No active agents.".to_string();
    }
    let mut lines = vec![format!(
        "{:<12} {:<10} {:<8} {:<30} {:<20}",
        "ID", "TASK", "PID", "BRANCH", "STARTED"
    )];
    for a in agents {
        let id = a["id"].as_str().unwrap_or("?");
        let task = a["task_id"].as_str().unwrap_or("?");
        let pid = a["pid"].as_u64().unwrap_or(0);
        let branch = a["branch"].as_str().unwrap_or("?");
        let branch_short = if branch.len() > 28 { &branch[..28] } else { branch };
        let started = a["started"].as_str().unwrap_or("?");
        let started_short = if started.len() > 18 { &started[..18] } else { started };
        lines.push(format!(
            "{:<12} {:<10} {:<8} {:<30} {:<20}",
            id, task, pid, branch_short, started_short
        ));
    }
    lines.join("\n")
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

    // ── Wave 1: set_field tests ─────────────────────────────────────────

    #[test]
    fn test_set_field_scalar() {
        let mut task = json!({"id": "t-1", "status": "pending", "priority": null});
        set_field(&mut task, "status", "in_progress", false).unwrap();
        assert_eq!(task["status"], "in_progress");
        set_field(&mut task, "priority", "P1", false).unwrap();
        assert_eq!(task["priority"], "P1");
    }

    #[test]
    fn test_set_field_null() {
        let mut task = json!({"id": "t-1", "priority": "P1"});
        set_field(&mut task, "priority", "null", false).unwrap();
        assert!(task["priority"].is_null());
    }

    #[test]
    fn test_set_field_array_append_remove() {
        let mut task = json!({"id": "t-1", "tags": ["a", "b"]});
        set_field(&mut task, "tags", "+c", false).unwrap();
        assert_eq!(task["tags"], json!(["a", "b", "c"]));
        // No duplicates
        set_field(&mut task, "tags", "+c", false).unwrap();
        assert_eq!(task["tags"], json!(["a", "b", "c"]));
        // Remove
        set_field(&mut task, "tags", "-b", false).unwrap();
        assert_eq!(task["tags"], json!(["a", "c"]));
    }

    #[test]
    fn test_set_field_text_append() {
        let mut task = json!({"id": "t-1", "context": "line1"});
        set_field(&mut task, "context", "line2", true).unwrap();
        assert_eq!(task["context"], "line1\nline2");
    }

    #[test]
    fn test_set_field_text_replace() {
        let mut task = json!({"id": "t-1", "context": "old"});
        set_field(&mut task, "context", "new", false).unwrap();
        assert_eq!(task["context"], "new");
    }

    #[test]
    fn test_set_field_unknown() {
        let mut task = json!({"id": "t-1"});
        assert!(set_field(&mut task, "nonexistent", "val", false).is_err());
    }

    // ── Wave 1: next_id tests ───────────────────────────────────────────

    #[test]
    fn test_next_id() {
        let tasks = vec![json!({"id": "t-5"}), json!({"id": "t-10"}), json!({"id": "ph-001"})];
        assert_eq!(next_id(&tasks), "t-11");
    }

    #[test]
    fn test_next_id_empty() {
        let tasks: Vec<Value> = vec![];
        assert_eq!(next_id(&tasks), "t-1");
    }

    // ── Wave 2: tag_inventory tests ─────────────────────────────────────

    #[test]
    fn test_tag_inventory() {
        let tasks = sample_tasks();
        let inv = tag_inventory(&tasks, &tasks);
        let sched = inv.iter().find(|(t, _)| t == "scheduler").unwrap();
        assert_eq!(*sched.1.get("total").unwrap(), 2);
    }

    // ── Wave 2: compute_stats tests ─────────────────────────────────────

    #[test]
    fn test_compute_stats() {
        let tasks = sample_tasks();
        let stats = compute_stats(&tasks, &tasks);
        assert_eq!(stats["total"], 7);
        assert!(stats["by_status"]["done"].as_u64().unwrap() >= 2);
    }

    // ── Wave 3: build_tree tests ────────────────────────────────────────

    #[test]
    fn test_build_tree_with_phase() {
        let tasks = vec![
            json!({"id": "ph-001", "type": "phase", "status": "pending", "subject": "Phase 1", "tags": [], "blocked_by": []}),
            json!({"id": "ms-001", "type": "milestone", "status": "pending", "subject": "MS 1", "parent": "ph-001", "tags": [], "blocked_by": []}),
            json!({"id": "t-001", "type": "task", "status": "completed", "subject": "Task 1", "parent": "ms-001", "tags": [], "blocked_by": []}),
            json!({"id": "t-002", "type": "task", "status": "pending", "subject": "Task 2", "parent": "ms-001", "tags": [], "blocked_by": []}),
        ];
        let tree = build_tree(&tasks, &tasks);
        assert_eq!(tree.len(), 1); // one phase
        assert_eq!(tree[0]["id"], "ph-001");
        let ms = tree[0]["children"].as_array().unwrap();
        assert_eq!(ms.len(), 1);
        assert_eq!(ms[0]["progress"]["done"], 1);
        assert_eq!(ms[0]["progress"]["total"], 2);
    }

    #[test]
    fn test_subtree() {
        let tasks = vec![
            json!({"id": "ph-001", "type": "phase", "status": "pending", "subject": "P1", "tags": [], "blocked_by": []}),
            json!({"id": "t-001", "type": "task", "status": "completed", "subject": "T1", "parent": "ph-001", "tags": [], "blocked_by": []}),
        ];
        let tree = subtree(&tasks, &tasks, "ph-001");
        assert!(tree.is_some());
        let tree = tree.unwrap();
        assert_eq!(tree["children"].as_array().unwrap().len(), 1);
    }

    // ── Wave 4: multi-tag filter test ───────────────────────────────────

    #[test]
    fn test_multi_tag_filter() {
        let tasks = sample_tasks();
        let result = filter_tasks(&tasks, &tasks, Some("scheduler"), None, None, None, None, None, &["task", "subtask"]);
        assert_eq!(result.len(), 2);
        // Filter further for "dx" — only t-004 has both
        let filtered: Vec<_> = result.into_iter()
            .filter(|t| t["tags"].as_array().unwrap().iter().any(|v| v == "dx"))
            .collect();
        assert_eq!(filtered.len(), 1);
        assert_eq!(filtered[0]["id"], "t-004");
    }

    // ── Wave 5: agent management ─────────────────────────────────────────

    #[test]
    fn test_load_agents_empty_file() {
        let dir = std::env::temp_dir().join("brana-test-agents-empty");
        std::fs::create_dir_all(&dir).ok();
        let path = dir.join("agents.json");
        std::fs::write(&path, "").unwrap();
        let agents = load_agents(&path);
        assert!(agents.is_empty());
        std::fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn test_load_agents_missing_file() {
        let path = std::path::PathBuf::from("/tmp/nonexistent-agents-xyz.json");
        let agents = load_agents(&path);
        assert!(agents.is_empty());
    }

    #[test]
    fn test_save_and_load_agents() {
        let dir = std::env::temp_dir().join("brana-test-agents-roundtrip");
        std::fs::create_dir_all(&dir).ok();
        let path = dir.join("agents.json");
        let agents = vec![json!({"id": "agent-001", "task_id": "t-063", "pid": 12345})];
        save_agents(&path, &agents).unwrap();
        let loaded = load_agents(&path);
        assert_eq!(loaded.len(), 1);
        assert_eq!(loaded[0]["task_id"], "t-063");
        std::fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn test_is_pid_alive_self() {
        // Our own PID should be alive
        let pid = std::process::id();
        assert!(is_pid_alive(pid));
    }

    #[test]
    fn test_is_pid_alive_bogus() {
        // PID 99999999 should not exist
        assert!(!is_pid_alive(99999999));
    }

    #[test]
    fn test_prune_dead_agents() {
        let agents = vec![
            json!({"id": "a1", "pid": std::process::id()}), // alive (self)
            json!({"id": "a2", "pid": 99999999}),           // dead
        ];
        let (alive, removed) = prune_dead_agents(agents);
        assert_eq!(alive.len(), 1);
        assert_eq!(alive[0]["id"], "a1");
        assert_eq!(removed, 1);
    }

    #[test]
    fn test_new_agent_entry() {
        let entry = new_agent_entry("t-063", 12345, "brana:t-063", "../thebrana-docs/t-063", "docs/t-063-slug");
        assert_eq!(entry["task_id"], "t-063");
        assert_eq!(entry["pid"], 12345);
        assert_eq!(entry["tmux_target"], "brana:t-063");
        assert_eq!(entry["status"], "active");
    }

    #[test]
    fn test_format_agents_table_empty() {
        let output = format_agents_table(&[]);
        assert_eq!(output, "No active agents.");
    }

    #[test]
    fn test_format_agents_table_with_agents() {
        let agents = vec![json!({
            "id": "agent-001", "task_id": "t-063", "pid": 12345,
            "branch": "docs/t-063-slug", "started": "2026-03-16T13:00:00Z"
        })];
        let output = format_agents_table(&agents);
        assert!(output.contains("agent-001"));
        assert!(output.contains("t-063"));
        assert!(output.contains("12345"));
    }

    // ── Wave 6: queue + model routing ─────────────────────────────────

    #[test]
    fn test_complexity_score_minimal() {
        let task = json!({"description": "fix typo", "blocked_by": [], "stream": "bugs", "tags": [], "effort": "S"});
        let score = complexity_score(&task);
        assert!(score < 0.3, "minimal task should score < 0.3, got {score}");
    }

    #[test]
    fn test_complexity_score_complex() {
        let task = json!({
            "description": "Implement the full authentication system with JWT tokens, refresh rotation, middleware integration, session management, and database schema changes for the user auth table",
            "blocked_by": ["t-001", "t-002"],
            "stream": "roadmap",
            "tags": ["architecture"],
            "effort": "XL"
        });
        let score = complexity_score(&task);
        assert!(score > 0.7, "complex task should score > 0.7, got {score}");
    }

    #[test]
    fn test_recommended_model_haiku() {
        assert_eq!(recommended_model(0.1), "haiku");
        assert_eq!(recommended_model(0.29), "haiku");
    }

    #[test]
    fn test_recommended_model_sonnet() {
        assert_eq!(recommended_model(0.3), "sonnet");
        assert_eq!(recommended_model(0.5), "sonnet");
        assert_eq!(recommended_model(0.7), "sonnet");
    }

    #[test]
    fn test_recommended_model_opus() {
        assert_eq!(recommended_model(0.71), "opus");
        assert_eq!(recommended_model(1.0), "opus");
    }

    #[test]
    fn test_queue_candidates_basic() {
        let tasks = vec![
            json!({"id": "t-001", "status": "pending", "type": "task", "subject": "First", "priority": "P1", "effort": "S", "stream": "bugs", "blocked_by": [], "tags": [], "description": "fix"}),
            json!({"id": "t-002", "status": "pending", "type": "task", "subject": "Second", "priority": "P2", "effort": "M", "stream": "roadmap", "blocked_by": [], "tags": [], "description": "build feature"}),
            json!({"id": "t-003", "status": "completed", "type": "task", "subject": "Done", "priority": "P0", "effort": "S", "stream": "bugs", "blocked_by": [], "tags": [], "description": "done"}),
        ];
        let q = queue_candidates(&tasks, 5);
        assert_eq!(q.len(), 2); // only pending
        assert_eq!(q[0]["id"], "t-001"); // P1 before P2
    }

    #[test]
    fn test_queue_candidates_respects_max() {
        let tasks = vec![
            json!({"id": "t-001", "status": "pending", "type": "task", "subject": "A", "priority": "P1", "blocked_by": [], "tags": [], "description": "", "stream": "roadmap", "effort": null}),
            json!({"id": "t-002", "status": "pending", "type": "task", "subject": "B", "priority": "P2", "blocked_by": [], "tags": [], "description": "", "stream": "roadmap", "effort": null}),
            json!({"id": "t-003", "status": "pending", "type": "task", "subject": "C", "priority": "P3", "blocked_by": [], "tags": [], "description": "", "stream": "roadmap", "effort": null}),
        ];
        let q = queue_candidates(&tasks, 2);
        assert_eq!(q.len(), 2);
    }

    #[test]
    fn test_queue_candidates_skips_blocked() {
        let tasks = vec![
            json!({"id": "t-001", "status": "pending", "type": "task", "subject": "Blocked", "priority": "P1", "blocked_by": ["t-002"], "tags": [], "description": "", "stream": "roadmap", "effort": null}),
            json!({"id": "t-002", "status": "pending", "type": "task", "subject": "Blocker", "priority": "P2", "blocked_by": [], "tags": [], "description": "", "stream": "roadmap", "effort": null}),
        ];
        let q = queue_candidates(&tasks, 5);
        assert_eq!(q.len(), 1);
        assert_eq!(q[0]["id"], "t-002"); // only unblocked
    }

    // ── Wave 7: brana run helpers ────────────────────────────────────────

    #[test]
    fn test_branch_for_roadmap_task() {
        let task = json!({"id": "t-001", "stream": "roadmap", "subject": "My Task Name"});
        assert_eq!(branch_for_task(&task), "feat/t-001-my-task-name");
    }

    #[test]
    fn test_branch_for_bug_task() {
        let task = json!({"id": "t-002", "stream": "bugs", "subject": "Crash on login"});
        assert_eq!(branch_for_task(&task), "fix/t-002-crash-on-login");
    }

    #[test]
    fn test_branch_for_research_task() {
        let task = json!({"id": "t-003", "stream": "research", "subject": "Evaluate Options"});
        assert_eq!(branch_for_task(&task), "research/t-003-evaluate-options");
    }

    #[test]
    fn test_branch_for_tech_debt_task() {
        let task = json!({"id": "t-010", "stream": "tech-debt", "subject": "Clean up imports"});
        assert_eq!(branch_for_task(&task), "refactor/t-010-clean-up-imports");
    }

    #[test]
    fn test_branch_for_long_subject() {
        let task = json!({"id": "t-004", "stream": "roadmap", "subject": "This is a very long task subject that should be truncated to forty characters"});
        let branch = branch_for_task(&task);
        // slug part (after "feat/t-004-") should be truncated
        let slug = branch.strip_prefix("feat/t-004-").unwrap();
        assert!(slug.len() <= 40);
    }

    #[test]
    fn test_branch_for_special_chars() {
        let task = json!({"id": "t-005", "stream": "roadmap", "subject": "What's the deal? (100% done!)"});
        let branch = branch_for_task(&task);
        assert_eq!(branch, "feat/t-005-what-s-the-deal-100-done");
    }

    #[test]
    fn test_worktree_path_feat() {
        let task = json!({"id": "t-001", "stream": "roadmap"});
        assert_eq!(worktree_path_for_task(&task, "thebrana"), "../thebrana-feat/t-001");
    }

    #[test]
    fn test_worktree_path_fix() {
        let task = json!({"id": "t-002", "stream": "bugs"});
        assert_eq!(worktree_path_for_task(&task, "myproject"), "../myproject-fix/t-002");
    }

    #[test]
    fn test_validate_pending_unblocked() {
        let tasks = vec![
            json!({"id": "t-001", "status": "pending", "blocked_by": []}),
        ];
        assert!(validate_task_runnable(&tasks[0], &tasks).is_ok());
    }

    #[test]
    fn test_validate_already_running() {
        let tasks = vec![
            json!({"id": "t-001", "status": "in_progress", "blocked_by": []}),
        ];
        let err = validate_task_runnable(&tasks[0], &tasks).unwrap_err();
        assert!(err.contains("already in_progress"));
    }

    #[test]
    fn test_validate_completed() {
        let tasks = vec![
            json!({"id": "t-001", "status": "completed", "blocked_by": []}),
        ];
        let err = validate_task_runnable(&tasks[0], &tasks).unwrap_err();
        assert!(err.contains("is completed, not pending"));
    }

    #[test]
    fn test_validate_blocked() {
        let tasks = vec![
            json!({"id": "t-001", "status": "pending", "blocked_by": ["t-002"]}),
            json!({"id": "t-002", "status": "pending", "blocked_by": []}),
        ];
        let err = validate_task_runnable(&tasks[0], &tasks).unwrap_err();
        assert!(err.contains("blocked by t-002"));
    }

    #[test]
    fn test_validate_blocked_all_completed() {
        let tasks = vec![
            json!({"id": "t-001", "status": "pending", "blocked_by": ["t-002"]}),
            json!({"id": "t-002", "status": "completed", "blocked_by": []}),
        ];
        assert!(validate_task_runnable(&tasks[0], &tasks).is_ok());
    }

    // ── t-528: load_raw normalization ─────────────────────────────────

    #[test]
    fn test_load_raw_object_format() {
        let dir = std::env::temp_dir().join("brana-test-load-raw-obj");
        std::fs::create_dir_all(&dir).ok();
        let path = dir.join("tasks.json");
        std::fs::write(&path, r#"{"project":"test","tasks":[{"id":"t-1"}]}"#).unwrap();
        let val = load_raw(&path).unwrap();
        assert!(val["tasks"].is_array());
        assert_eq!(val["tasks"][0]["id"], "t-1");
        assert_eq!(val["project"], "test");
        std::fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn test_load_raw_bare_array() {
        let dir = std::env::temp_dir().join("brana-test-load-raw-arr");
        std::fs::create_dir_all(&dir).ok();
        let path = dir.join("tasks.json");
        std::fs::write(&path, r#"[{"id":"st-001","status":"pending"},{"id":"ms-001","status":"pending"}]"#).unwrap();
        let val = load_raw(&path).unwrap();
        assert!(val["tasks"].is_array());
        let arr = val["tasks"].as_array().unwrap();
        assert_eq!(arr.len(), 2);
        assert_eq!(arr[0]["id"], "st-001");
        assert_eq!(arr[1]["id"], "ms-001");
        std::fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn test_load_raw_empty_array() {
        let dir = std::env::temp_dir().join("brana-test-load-raw-empty");
        std::fs::create_dir_all(&dir).ok();
        let path = dir.join("tasks.json");
        std::fs::write(&path, "[]").unwrap();
        let val = load_raw(&path).unwrap();
        assert!(val["tasks"].is_array());
        assert_eq!(val["tasks"].as_array().unwrap().len(), 0);
        std::fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn test_load_raw_invalid_json() {
        let dir = std::env::temp_dir().join("brana-test-load-raw-bad");
        std::fs::create_dir_all(&dir).ok();
        let path = dir.join("tasks.json");
        std::fs::write(&path, "not json").unwrap();
        assert!(load_raw(&path).is_err());
        std::fs::remove_dir_all(&dir).ok();
    }

    // ── complexity_score edge cases ──────────────────────────────────

    #[test]
    fn test_complexity_score_max_components() {
        // All 5 components at max: 0.3 + 0.2 + 0.2 + 0.1 + 0.1 = 0.9
        let task = json!({
            "description": std::iter::repeat("word ").take(200).collect::<String>(),
            "blocked_by": ["t-1","t-2","t-3","t-4","t-5"],
            "stream": "roadmap",
            "tags": ["architecture"],
            "effort": "XL"
        });
        let score = complexity_score(&task);
        assert!((score - 0.9).abs() < 0.01, "max components should score ~0.9, got {score}");
        assert!(score <= 1.0, "score should never exceed 1.0");
    }

    #[test]
    fn test_complexity_score_empty_task() {
        let task = json!({});
        let score = complexity_score(&task);
        assert_eq!(score, 0.0);
    }

    #[test]
    fn test_complexity_score_roadmap_only() {
        let task = json!({"stream": "roadmap", "blocked_by": [], "tags": [], "effort": "S"});
        let score = complexity_score(&task);
        assert!((score - 0.2).abs() < f64::EPSILON, "roadmap-only should be 0.2, got {score}");
    }

    #[test]
    fn test_recommended_model_boundary() {
        assert_eq!(recommended_model(0.0), "haiku");
        assert_eq!(recommended_model(0.3), "sonnet");
        assert_eq!(recommended_model(0.7), "sonnet");
        assert_eq!(recommended_model(0.700001), "opus");
    }
}
