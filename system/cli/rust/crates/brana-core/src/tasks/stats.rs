use super::*;
use serde_json::Value;
use std::collections::{HashMap, HashSet};


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

/// Focus score: initiative boost + priority weight - effort - blocked depth.
///
/// `initiative_boost` is 500.0 when the task belongs to the active initiative,
/// 0.0 otherwise. Staleness is intentionally excluded — it rewarded neglect by
/// floating forgotten tasks above freshly-prioritised work.
pub fn focus_score(task: &Value, initiative_boost: f64) -> f64 {
    let pri = match task["priority"].as_str() {
        Some("P0") => 400.0,
        Some("P1") => 300.0,
        Some("P2") => 200.0,
        Some("P3") => 100.0,
        _ => 50.0,
    };

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

    initiative_boost + pri - effort - blocked_depth
}

/// Compute burndown: created vs completed counts over a time period.
///
/// Returns a JSON object with created_count, completed_count, delta, and period info.
pub fn burndown(tasks: &[Value], period: &str) -> Value {
    let now = chrono::Local::now().date_naive();
    let days = match period {
        "month" => 30,
        _ => 7, // default: week
    };
    let cutoff = (now - chrono::Duration::days(days)).format("%Y-%m-%d").to_string();

    let created_count = tasks.iter()
        .filter(|t| matches!(t["type"].as_str(), Some("task" | "subtask")))
        .filter(|t| t["created"].as_str().unwrap_or("") >= cutoff.as_str())
        .count();

    let completed_count = tasks.iter()
        .filter(|t| matches!(t["type"].as_str(), Some("task" | "subtask")))
        .filter(|t| t["completed"].as_str().unwrap_or("") >= cutoff.as_str())
        .count();

    let delta = completed_count as i64 - created_count as i64;

    serde_json::json!({
        "period": period,
        "days": days,
        "cutoff": cutoff,
        "created": created_count,
        "completed": completed_count,
        "delta": delta,
        "direction": if delta > 0 { "shrinking" } else if delta < 0 { "growing" } else { "stable" },
    })
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

/// Compute aggregate stats by status, priority, type, work_type, initiative.
pub fn compute_stats(tasks: &[Value], all: &[Value]) -> Value {
    // by_status: raw task.status (matches filter_tasks predicate / CLI enum).
    // by_state:  synthetic classify() output for display rollups.
    // See tasks.spec.md (t-1323, t-1340).
    let mut by_status: HashMap<String, usize> = HashMap::new();
    let mut by_state: HashMap<String, usize> = HashMap::new();
    let mut by_priority: HashMap<String, usize> = HashMap::new();
    let mut by_type: HashMap<String, usize> = HashMap::new();
    let mut by_work_type: HashMap<String, usize> = HashMap::new();
    let mut by_epic: HashMap<String, usize> = HashMap::new();
    let by_id: HashMap<&str, &Value> = all
        .iter()
        .filter_map(|t| t["id"].as_str().map(|id| (id, t)))
        .collect();

    for t in tasks {
        let raw = raw_status(t, "unknown").to_string();
        let state = classify(t, all).to_string();
        let pri = t["priority"].as_str().unwrap_or("null").to_string();
        let tp = t["type"].as_str().unwrap_or("task").to_string();

        *by_status.entry(raw).or_default() += 1;
        *by_state.entry(state).or_default() += 1;
        *by_priority.entry(pri).or_default() += 1;
        *by_type.entry(tp).or_default() += 1;

        if let Some(wt) = t["work_type"].as_str() {
            *by_work_type.entry(wt.to_string()).or_default() += 1;
        }
        // t-2740 (ADR-065): the flat `epic` field is retired (RETIRED_FIELDS,
        // write path sealed t-2310) — membership is the nearest type:"epic"
        // ancestor via the parent chain. Epic nodes are containers, not members.
        if t["type"].as_str() != Some("epic") {
            if let Some(slug) = resolve_epic_ancestor(t, &by_id) {
                *by_epic.entry(slug).or_default() += 1;
            }
        }
    }

    serde_json::json!({
        "total": tasks.len(),
        "by_status": by_status,
        "by_state": by_state,
        "by_priority": by_priority,
        "by_type": by_type,
        "by_work_type": by_work_type,
        "by_epic": by_epic,
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
        // Group orphan tasks by work_type
        let mut by_work_type: HashMap<String, Vec<Value>> = HashMap::new();
        for t in orphans {
            let wt = t["work_type"].as_str().unwrap_or("implement").to_string();
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
            by_work_type.entry(wt).or_default().push(node);
        }
        for (wt, tasks) in by_work_type {
            result.push(serde_json::json!({
                "id": wt,
                "subject": wt,
                "type": "work_type",
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
