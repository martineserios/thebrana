//! Backlog subcommand handlers

use std::path::PathBuf;

use crate::tasks;
use crate::themes;
use crate::util::{delegate_python, find_tasks_file};

// ── backlog commands ────────────────────────────────────────────────────

pub fn cmd_next(theme: &themes::Theme, tag: Option<String>, stream: Option<String>) {
    let tf = find_tasks_file().unwrap_or_else(|| { eprintln!("tasks.json not found"); std::process::exit(1); });
    let data = tasks::load_tasks(&tf).unwrap_or_else(|e| { eprintln!("{e}"); std::process::exit(1); });
    let mut candidates = tasks::filter_tasks(
        &data.tasks, &data.tasks,
        tag.as_deref(), Some("pending"), stream.as_deref(), None, None, None,
        &["task", "subtask"],
    );
    tasks::sort_by_priority(&mut candidates);
    let top: Vec<_> = candidates.into_iter().take(3).collect();

    if top.is_empty() {
        println!("\n  No unblocked tasks found.\n");
        return;
    }

    println!("\n{}Next up{}", themes::ansi(theme.color("header")), themes::RESET);
    for (i, t) in top.iter().enumerate() {
        let pri = t["priority"].as_str().unwrap_or("—");
        let eff = t["effort"].as_str().unwrap_or("—");
        let st = t["stream"].as_str().unwrap_or("—");
        let line = format!(
            "  {}. {} {}  {}  {}  {}  {}",
            i + 1, theme.icon("pending"),
            t["id"].as_str().unwrap_or("?"),
            t["subject"].as_str().unwrap_or(""),
            pri, eff, st,
        );
        println!("{}{line}{}", themes::ansi(theme.color("pending")), themes::RESET);
    }
    println!();
}

pub fn cmd_query(
    tag: Option<String>, status: Option<String>, stream: Option<String>,
    priority: Option<String>, effort: Option<String>, search: Option<String>,
    count: bool, output: String, theme: &themes::Theme,
    task_type: Option<String>, parent: Option<String>, branch: Option<String>,
) {
    let tf = find_tasks_file().unwrap_or_else(|| { eprintln!("tasks.json not found"); std::process::exit(1); });
    let data = tasks::load_tasks(&tf).unwrap_or_else(|e| { eprintln!("{e}"); std::process::exit(1); });

    // Determine type filter
    let types: Vec<&str> = if let Some(ref tp) = task_type {
        tp.split(',').collect()
    } else {
        vec!["task", "subtask"]
    };

    // Multi-tag support: split by comma for AND logic
    let tag_list: Option<Vec<&str>> = tag.as_deref().map(|t| t.split(',').collect());

    let mut results = tasks::filter_tasks(
        &data.tasks, &data.tasks,
        None, status.as_deref(), stream.as_deref(),
        priority.as_deref(), effort.as_deref(), search.as_deref(),
        &types,
    );

    // Apply multi-tag AND filter
    if let Some(ref tags) = tag_list {
        results.retain(|t| {
            let task_tags: Vec<&str> = t["tags"].as_array()
                .map(|a| a.iter().filter_map(|v| v.as_str()).collect())
                .unwrap_or_default();
            tags.iter().all(|tag| task_tags.contains(tag))
        });
    }

    // Apply parent filter
    if let Some(ref pid) = parent {
        results.retain(|t| t["parent"].as_str() == Some(pid.as_str()));
    }

    // Apply branch filter
    if let Some(ref br) = branch {
        results.retain(|t| t["branch"].as_str() == Some(br.as_str()));
    }

    if count {
        println!("{}", results.len());
    } else if output == "ids" {
        for t in &results {
            if let Some(id) = t["id"].as_str() { println!("{id}"); }
        }
    } else if output == "themed" {
        for t in &results {
            let st = tasks::classify(t, &data.tasks);
            println!("  {}", themes::render_task_line(t, st, theme, true));
        }
        println!("\n  {} tasks\n", results.len());
    } else {
        println!("{}", serde_json::to_string(&results).unwrap());
    }
}

pub fn cmd_focus(theme: &themes::Theme) {
    let tf = find_tasks_file().unwrap_or_else(|| { eprintln!("tasks.json not found"); std::process::exit(1); });
    let data = tasks::load_tasks(&tf).unwrap_or_else(|e| { eprintln!("{e}"); std::process::exit(1); });

    let mut scored: Vec<_> = data.tasks.iter()
        .filter(|t| t["type"].as_str().unwrap_or("task") == "task" || t["type"].as_str() == Some("subtask"))
        .filter(|t| tasks::classify(t, &data.tasks) == "pending")
        .map(|t| (t, tasks::focus_score(t)))
        .collect();
    scored.sort_by(|a, b| b.1.partial_cmp(&a.1).unwrap_or(std::cmp::Ordering::Equal));
    let top: Vec<_> = scored.into_iter().take(3).collect();

    if top.is_empty() {
        println!("\n  No actionable tasks.\n");
        return;
    }

    println!("\n{}Focus — today's pick{}", themes::ansi(theme.color("header")), themes::RESET);
    for (i, (t, score)) in top.iter().enumerate() {
        let pri = t["priority"].as_str().unwrap_or("—");
        let eff = t["effort"].as_str().unwrap_or("—");
        println!(
            "{}  {}. {} {}  {}  {}  {}  (score: {:.0}){}",
            themes::ansi(theme.color("pending")),
            i + 1, theme.icon("pending"),
            t["id"].as_str().unwrap_or("?"),
            t["subject"].as_str().unwrap_or(""), pri, eff, score,
            themes::RESET,
        );
    }
    println!();
}

pub fn cmd_search(text: &str, theme: &themes::Theme) {
    let tf = find_tasks_file().unwrap_or_else(|| { eprintln!("tasks.json not found"); std::process::exit(1); });
    let data = tasks::load_tasks(&tf).unwrap_or_else(|e| { eprintln!("{e}"); std::process::exit(1); });
    let results = tasks::filter_tasks(
        &data.tasks, &data.tasks,
        None, None, None, None, None, Some(text), &["task", "subtask"],
    );
    if results.is_empty() {
        println!("\n  No tasks match \"{text}\".\n");
        return;
    }
    println!("\n{}Search: \"{text}\"{}", themes::ansi(theme.color("header")), themes::RESET);
    for t in &results {
        let st = tasks::classify(t, &data.tasks);
        println!("  {}", themes::render_task_line(t, st, theme, true));
    }
    println!("\n  {} tasks\n", results.len());
}

pub fn cmd_status(theme: &themes::Theme, all: bool, json_out: bool) {
    if all {
        match tasks::portfolio_status() {
            Ok(results) => {
                if json_out {
                    println!("{}", serde_json::to_string(&results).unwrap());
                } else {
                    println!("\n{}Portfolio{}", themes::ansi(theme.color("header")), themes::RESET);
                    for p in &results {
                        let client = p["client"].as_str().unwrap_or("?");
                        let total = p["total"].as_u64().unwrap_or(0) as usize;
                        let done = p["done"].as_u64().unwrap_or(0) as usize;
                        let active = p["active"].as_u64().unwrap_or(0) as usize;
                        let blocked = p["blocked"].as_u64().unwrap_or(0) as usize;
                        println!("  {}{}{} {} {done}/{total} done, {active} active, {blocked} blocked",
                            themes::ansi(theme.color("header")), client, themes::RESET,
                            theme.bar(done, total, 8));
                    }
                    println!();
                }
            }
            Err(e) => { eprintln!("{e}"); std::process::exit(1); }
        }
        return;
    }

    let tf = find_tasks_file().unwrap_or_else(|| { eprintln!("tasks.json not found"); std::process::exit(1); });
    let data = tasks::load_tasks(&tf).unwrap_or_else(|e| { eprintln!("{e}"); std::process::exit(1); });

    let task_items: Vec<_> = data.tasks.iter()
        .filter(|t| matches!(t["type"].as_str(), Some("task" | "subtask")))
        .collect();
    let total = task_items.len();
    let done = task_items.iter().filter(|t| tasks::classify(t, &data.tasks) == "done").count();
    let active = task_items.iter().filter(|t| tasks::classify(t, &data.tasks) == "active").count();
    let blocked = task_items.iter().filter(|t| tasks::classify(t, &data.tasks) == "blocked").count();

    if json_out {
        println!("{}", serde_json::to_string(&serde_json::json!({
            "project": data.project,
            "total": total, "done": done, "active": active, "blocked": blocked,
        })).unwrap());
    } else {
        println!("\n{}{}{}",
            themes::ansi(theme.color("header")), data.project, themes::RESET);
        println!("  {} {done}/{total} done, {active} active, {blocked} blocked\n",
            theme.bar(done, total, 8));
    }
}

pub fn cmd_blocked(theme: &themes::Theme) {
    let tf = find_tasks_file().unwrap_or_else(|| { eprintln!("tasks.json not found"); std::process::exit(1); });
    let data = tasks::load_tasks(&tf).unwrap_or_else(|e| { eprintln!("{e}"); std::process::exit(1); });
    let blocked: Vec<_> = data.tasks.iter()
        .filter(|t| matches!(t["type"].as_str(), Some("task" | "subtask")))
        .filter(|t| tasks::classify(t, &data.tasks) == "blocked")
        .collect();
    if blocked.is_empty() {
        println!("\n  No blocked tasks.\n");
        return;
    }
    println!("\n{}Blocked chains{}", themes::ansi(theme.color("header")), themes::RESET);
    for t in &blocked {
        println!("  {}", themes::render_task_line(t, "blocked", theme, true));
    }
    println!();
}

pub fn cmd_stale(days: i64, theme: &themes::Theme) {
    let tf = find_tasks_file().unwrap_or_else(|| { eprintln!("tasks.json not found"); std::process::exit(1); });
    let data = tasks::load_tasks(&tf).unwrap_or_else(|e| { eprintln!("{e}"); std::process::exit(1); });
    let cutoff = (chrono::Local::now() - chrono::Duration::days(days))
        .format("%Y-%m-%d").to_string();

    let stale: Vec<_> = data.tasks.iter()
        .filter(|t| t["status"].as_str() == Some("pending"))
        .filter(|t| matches!(t["type"].as_str(), Some("task" | "subtask")))
        .filter(|t| t["created"].as_str().unwrap_or("9999") < cutoff.as_str())
        .collect();

    if stale.is_empty() {
        println!("\n  No tasks pending > {days} days.\n");
        return;
    }
    println!("\n{}Stale tasks (>{days} days){}", themes::ansi(theme.color("header")), themes::RESET);
    for t in &stale {
        let st = tasks::classify(t, &data.tasks);
        let age = t["created"].as_str()
            .and_then(|d| chrono::NaiveDate::parse_from_str(d, "%Y-%m-%d").ok())
            .map(|d| (chrono::Local::now().date_naive() - d).num_days())
            .unwrap_or(0);
        println!("  {} ({age}d)", themes::render_task_line(t, st, theme, true));
    }
    println!("\n  {} stale tasks\n", stale.len());
}

pub fn cmd_context(task_id: &str, theme: &themes::Theme) {
    let tf = find_tasks_file().unwrap_or_else(|| { eprintln!("tasks.json not found"); std::process::exit(1); });
    let data = tasks::load_tasks(&tf).unwrap_or_else(|e| { eprintln!("{e}"); std::process::exit(1); });
    let task = data.tasks.iter().find(|t| t["id"].as_str() == Some(task_id));
    let task = task.unwrap_or_else(|| { eprintln!("Task {task_id} not found."); std::process::exit(1); });

    let st = tasks::classify(task, &data.tasks);
    println!("\n{}{task_id} {}{}", themes::ansi(theme.color("header")),
        task["subject"].as_str().unwrap_or(""), themes::RESET);
    println!("  Status: {st}  Stream: {}  Priority: {}  Effort: {}",
        task["stream"].as_str().unwrap_or("—"),
        task["priority"].as_str().unwrap_or("—"),
        task["effort"].as_str().unwrap_or("—"));

    for (label, field) in [("Context", "context"), ("Notes", "notes"), ("Description", "description")] {
        if let Some(val) = task[field].as_str() {
            if !val.is_empty() {
                println!("\n  \x1b[2m{label}:\x1b[0m");
                for line in val.lines() { println!("    {line}"); }
            }
        }
    }
    println!();
}

// ── write commands ──────────────────────────────────────────────────────

pub fn cmd_set(task_id: &str, field: &str, value: &str, append: bool, file: Option<PathBuf>) {
    let tf = file.unwrap_or_else(|| find_tasks_file().unwrap_or_else(|| { eprintln!("tasks.json not found"); std::process::exit(1); }));
    let mut val = tasks::load_raw(&tf).unwrap_or_else(|e| { eprintln!("{e}"); std::process::exit(1); });

    let idx = val["tasks"].as_array()
        .and_then(|arr| arr.iter().position(|t| t["id"].as_str() == Some(task_id)));
    let idx = match idx {
        Some(i) => i,
        None => { eprintln!("{{\"ok\":false,\"error\":\"task {task_id} not found\"}}"); std::process::exit(1); }
    };

    let task = &mut val["tasks"][idx];
    match tasks::set_field(task, field, value, append) {
        Ok(()) => {
            let actual = val["tasks"][idx][field].clone();
            tasks::save_tasks(&tf, &val).unwrap_or_else(|e| { eprintln!("{e}"); std::process::exit(1); });
            println!("{}", serde_json::json!({"ok": true, "id": task_id, "field": field, "value": actual}));
        }
        Err(e) => {
            eprintln!("{{\"ok\":false,\"error\":{}}}", serde_json::to_string(&e).unwrap());
            std::process::exit(1);
        }
    }
}

pub fn cmd_add(
    json: Option<String>,
    subject: Option<String>,
    stream: Option<String>,
    task_type: Option<String>,
    tags: Option<String>,
    description: Option<String>,
    effort: Option<String>,
    parent: Option<String>,
    file: Option<PathBuf>,
) {
    let tf = file.unwrap_or_else(|| find_tasks_file().unwrap_or_else(|| { eprintln!("tasks.json not found"); std::process::exit(1); }));
    let mut val = tasks::load_raw(&tf).unwrap_or_else(|e| { eprintln!("{e}"); std::process::exit(1); });

    // Resolve JSON from: --json inline, @file, stdin (-), or shorthand flags
    let json_string = if let Some(j) = json {
        if j == "-" {
            // Read from stdin
            use std::io::Read;
            let mut buf = String::new();
            std::io::stdin().read_to_string(&mut buf).unwrap_or_else(|e| {
                eprintln!("{{\"ok\":false,\"error\":\"failed to read stdin: {e}\"}}");
                std::process::exit(1);
            });
            buf
        } else if let Some(path) = j.strip_prefix('@') {
            // Read from file
            std::fs::read_to_string(path).unwrap_or_else(|e| {
                eprintln!("{{\"ok\":false,\"error\":\"failed to read {path}: {e}\"}}");
                std::process::exit(1);
            })
        } else {
            j
        }
    } else if let Some(ref subj) = subject {
        // Build JSON from shorthand flags
        let mut obj = serde_json::Map::new();
        obj.insert("subject".into(), serde_json::Value::String(subj.clone()));
        if let Some(ref s) = stream { obj.insert("stream".into(), serde_json::Value::String(s.clone())); }
        obj.insert("type".into(), serde_json::Value::String(task_type.unwrap_or_else(|| "task".into())));
        if let Some(ref t) = tags {
            let tag_arr: Vec<serde_json::Value> = t.split(',').map(|s| serde_json::Value::String(s.trim().to_string())).collect();
            obj.insert("tags".into(), serde_json::Value::Array(tag_arr));
        }
        if let Some(ref d) = description { obj.insert("description".into(), serde_json::Value::String(d.clone())); }
        if let Some(ref e) = effort { obj.insert("effort".into(), serde_json::Value::String(e.clone())); }
        if let Some(ref p) = parent { obj.insert("parent".into(), serde_json::Value::String(p.clone())); }
        serde_json::to_string(&obj).unwrap()
    } else {
        eprintln!("{{\"ok\":false,\"error\":\"provide --json or --subject\"}}");
        std::process::exit(1);
    };

    let mut new_task: serde_json::Value = serde_json::from_str(&json_string)
        .unwrap_or_else(|e| { eprintln!("{{\"ok\":false,\"error\":\"invalid JSON: {e}\"}}"); std::process::exit(1); });

    let tasks_arr = val["tasks"].as_array().cloned().unwrap_or_default();
    let id = tasks::next_id(&tasks_arr);

    // Set defaults
    new_task["id"] = serde_json::Value::String(id.clone());
    if new_task["status"].is_null() { new_task["status"] = serde_json::Value::String("pending".into()); }
    if new_task["execution"].is_null() { new_task["execution"] = serde_json::Value::String("code".into()); }
    if new_task["created"].is_null() {
        new_task["created"] = serde_json::Value::String(chrono::Local::now().format("%Y-%m-%d").to_string());
    }
    if new_task["tags"].is_null() { new_task["tags"] = serde_json::json!([]); }
    if new_task["blocked_by"].is_null() { new_task["blocked_by"] = serde_json::json!([]); }
    // Null defaults for optional fields
    for f in &["parent", "order", "priority", "effort", "branch", "github_issue",
               "started", "completed", "notes", "context", "strategy", "build_step", "description"] {
        if new_task[*f].is_null() && !new_task.as_object().map_or(true, |o| o.contains_key(*f)) {
            new_task[*f] = serde_json::Value::Null;
        }
    }

    let subject = new_task["subject"].as_str().unwrap_or("untitled").to_string();

    val["tasks"].as_array_mut()
        .unwrap_or_else(|| { eprintln!("{{\"ok\":false,\"error\":\"tasks.json has no tasks array\"}}"); std::process::exit(1); })
        .push(new_task);
    tasks::save_tasks(&tf, &val).unwrap_or_else(|e| { eprintln!("{e}"); std::process::exit(1); });
    println!("{}", serde_json::json!({"ok": true, "id": id, "subject": subject}));
}

pub fn cmd_get(task_id: &str, field: Option<String>) {
    let tf = find_tasks_file().unwrap_or_else(|| { eprintln!("tasks.json not found"); std::process::exit(1); });
    let data = tasks::load_tasks(&tf).unwrap_or_else(|e| { eprintln!("{e}"); std::process::exit(1); });
    let task = data.tasks.iter().find(|t| t["id"].as_str() == Some(task_id));
    let task = task.unwrap_or_else(|| { eprintln!("task {task_id} not found"); std::process::exit(1); });

    if let Some(f) = field {
        println!("{}", serde_json::to_string(&task[f.as_str()]).unwrap());
    } else {
        println!("{}", serde_json::to_string_pretty(task).unwrap());
    }
}

pub fn cmd_stats() {
    let tf = find_tasks_file().unwrap_or_else(|| { eprintln!("tasks.json not found"); std::process::exit(1); });
    let data = tasks::load_tasks(&tf).unwrap_or_else(|e| { eprintln!("{e}"); std::process::exit(1); });
    let stats = tasks::compute_stats(&data.tasks, &data.tasks);
    println!("{}", serde_json::to_string(&stats).unwrap());
}

pub fn cmd_tags(filter: Option<String>, any: Option<String>, output: String, theme: &themes::Theme) {
    let tf = find_tasks_file().unwrap_or_else(|| { eprintln!("tasks.json not found"); std::process::exit(1); });
    let data = tasks::load_tasks(&tf).unwrap_or_else(|e| { eprintln!("{e}"); std::process::exit(1); });

    // Filter mode
    if filter.is_some() || any.is_some() {
        let tag_list: Vec<&str> = filter.as_deref().or(any.as_deref())
            .unwrap_or("").split(',').collect();
        let is_and = filter.is_some();

        let results: Vec<&serde_json::Value> = data.tasks.iter()
            .filter(|t| matches!(t["type"].as_str(), Some("task" | "subtask")))
            .filter(|t| {
                let task_tags: Vec<&str> = t["tags"].as_array()
                    .map(|a| a.iter().filter_map(|v| v.as_str()).collect())
                    .unwrap_or_default();
                if is_and {
                    tag_list.iter().all(|tag| task_tags.contains(tag))
                } else {
                    tag_list.iter().any(|tag| task_tags.contains(tag))
                }
            })
            .collect();

        if output == "json" {
            println!("{}", serde_json::to_string(&results).unwrap());
        } else {
            let label = if is_and { format!("[{}]", tag_list.join(" + ")) }
                else { format!("[{}]", tag_list.join(" | ")) };
            println!("\n{}Tasks tagged {}{}", themes::ansi(theme.color("header")), label, themes::RESET);
            for t in &results {
                let st = tasks::classify(t, &data.tasks);
                println!("  {}", themes::render_task_line(t, st, theme, true));
            }
            println!("\n  {} tasks\n", results.len());
        }
        return;
    }

    // Inventory mode
    let inventory = tasks::tag_inventory(&data.tasks, &data.tasks);
    if output == "json" {
        let json: Vec<serde_json::Value> = inventory.iter().map(|(tag, counts): &(String, std::collections::HashMap<String, usize>)| {
            serde_json::json!({"tag": tag, "total": counts.get("total").copied().unwrap_or(0),
                "pending": counts.get("pending").copied().unwrap_or(0),
                "active": counts.get("active").copied().unwrap_or(0),
                "done": counts.get("done").copied().unwrap_or(0),
                "blocked": counts.get("blocked").copied().unwrap_or(0)})
        }).collect();
        println!("{}", serde_json::to_string(&json).unwrap());
    } else {
        println!("\n{}Tags{}", themes::ansi(theme.color("header")), themes::RESET);
        for (tag, counts) in &inventory {
            let total = counts.get("total").copied().unwrap_or(0);
            let parts: Vec<String> = ["pending", "active", "done", "blocked"].iter()
                .filter_map(|s| counts.get(*s).filter(|c| **c > 0).map(|c| format!("{c} {s}")))
                .collect();
            println!("  {tag:<20} {total} tasks  ({})", parts.join(", "));
        }
        println!();
    }
}

pub fn cmd_roadmap(json_out: bool, theme: &themes::Theme) {
    let tf = find_tasks_file().unwrap_or_else(|| { eprintln!("tasks.json not found"); std::process::exit(1); });
    let data = tasks::load_tasks(&tf).unwrap_or_else(|e| { eprintln!("{e}"); std::process::exit(1); });
    let tree = tasks::build_tree(&data.tasks, &data.tasks);

    if json_out {
        println!("{}", serde_json::to_string(&tree).unwrap());
    } else {
        println!("\n{}{} Roadmap{}", themes::ansi(theme.color("header")), data.project, themes::RESET);
        for node in &tree {
            render_tree_node(node, theme, 0);
        }
        println!();
    }
}

pub fn cmd_tree(root_id: &str, json_out: bool, theme: &themes::Theme) {
    let tf = find_tasks_file().unwrap_or_else(|| { eprintln!("tasks.json not found"); std::process::exit(1); });
    let data = tasks::load_tasks(&tf).unwrap_or_else(|e| { eprintln!("{e}"); std::process::exit(1); });

    match tasks::subtree(&data.tasks, &data.tasks, root_id) {
        Some(tree) => {
            if json_out {
                println!("{}", serde_json::to_string(&tree).unwrap());
            } else {
                render_tree_node(&tree, theme, 0);
                println!();
            }
        }
        None => { eprintln!("task {root_id} not found"); std::process::exit(1); }
    }
}

fn render_tree_node(node: &serde_json::Value, theme: &themes::Theme, depth: usize) {
    let indent = "  ".repeat(depth);
    let id = node["id"].as_str().unwrap_or("?");
    let subject = node["subject"].as_str().unwrap_or("");
    let status = node["status"].as_str().unwrap_or("pending");
    let tp = node["type"].as_str().unwrap_or("task");

    if matches!(tp, "phase" | "milestone" | "stream") {
        let col = themes::ansi(theme.color("header"));
        if let Some(progress) = node.get("progress") {
            let done = progress["done"].as_u64().unwrap_or(0) as usize;
            let total = progress["total"].as_u64().unwrap_or(0) as usize;
            println!("{indent}{col}{id}  {subject}  {}{}", theme.bar(done, total, 8), themes::RESET);
        } else {
            println!("{indent}{col}{id}  {subject}{}", themes::RESET);
        }
    } else {
        let ic = theme.icon(status);
        let col = themes::ansi(theme.color(status));
        let mut line = format!("{indent}  {col}{ic} {id}  {subject}");
        if let Some(bs) = node["build_step"].as_str() {
            line.push_str(&format!("  [{}]", bs.to_uppercase()));
        }
        println!("{line}{}", themes::RESET);
    }

    if let Some(children) = node["children"].as_array() {
        for child in children {
            render_tree_node(child, theme, depth + 1);
        }
    }
}

pub fn cmd_diff(_theme: &themes::Theme) {
    delegate_python(&["backlog", "diff"]);
}

pub fn cmd_burndown(period: &str, _theme: &themes::Theme) {
    delegate_python(&["backlog", "burndown", "--period", period]);
}

// ── rollup ───────────────────────────────────────────────────────────────

pub fn cmd_rollup(file: Option<PathBuf>, dry_run: bool) {
    let tf = file.unwrap_or_else(|| {
        find_tasks_file().unwrap_or_else(|| {
            eprintln!("tasks.json not found");
            std::process::exit(1);
        })
    });
    match tasks::perform_rollup(&tf, dry_run) {
        Ok(ids) if ids.is_empty() => {
            // No rollup needed — silent exit
        }
        Ok(ids) => {
            let action = if dry_run { "would complete" } else { "completed" };
            let json_ids = serde_json::to_string(&ids).unwrap();
            println!("{{\"rollup\":{json_ids},\"action\":\"{action}\"}}");
        }
        Err(e) => {
            eprintln!("rollup failed: {e}");
            std::process::exit(1);
        }
    }
}
