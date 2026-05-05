//! Backlog subcommand handlers

use std::path::PathBuf;

use anyhow::Context;

use crate::tasks;
use crate::themes;
use crate::util::find_tasks_file;

// ── backlog commands ────────────────────────────────────────────────────

pub fn cmd_next(
    theme: &themes::Theme, tag: Option<String>, stream: Option<String>,
    limit: usize, priority: Option<String>, task_type: Option<String>,
    effort: Option<String>, parent: Option<String>,
) -> anyhow::Result<()> {
    let tf = find_tasks_file().context("tasks.json not found")?;
    let data = tasks::load_tasks(&tf).map_err(|e| anyhow::anyhow!("{e}"))?;

    let types: Vec<&str> = if let Some(ref tp) = task_type {
        tp.split(',').collect()
    } else {
        vec!["task", "subtask"]
    };

    let mut candidates = tasks::filter_tasks(
        &data.tasks, &data.tasks,
        tag.as_deref(), Some("pending"), stream.as_deref(),
        priority.as_deref(), effort.as_deref(), None,
        &types,
    );

    // filter_tasks does raw-status matching (tasks.spec.md). For "next up"
    // we want only classify=="pending" — exclude blocked and parked.
    candidates.retain(|t| tasks::classify(t, &data.tasks) == "pending");

    if let Some(ref pid) = parent {
        candidates.retain(|t| t["parent"].as_str() == Some(pid.as_str()));
    }

    tasks::sort_by_priority(&mut candidates);
    let top: Vec<_> = candidates.into_iter().take(limit).collect();

    if top.is_empty() {
        println!("\n  No unblocked tasks found.\n");
        return Ok(());
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
    Ok(())
}

pub fn cmd_query(
    tag: Option<String>, status: Option<String>, stream: Option<String>,
    priority: Option<String>, effort: Option<String>, search: Option<String>,
    count: bool, output: String, theme: &themes::Theme,
    task_type: Option<String>, parent: Option<String>, branch: Option<String>,
) -> anyhow::Result<()> {
    let tf = find_tasks_file().context("tasks.json not found")?;
    let data = tasks::load_tasks(&tf).map_err(|e| anyhow::anyhow!("{e}"))?;

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
    Ok(())
}

pub fn cmd_focus(theme: &themes::Theme) -> anyhow::Result<()> {
    let tf = find_tasks_file().context("tasks.json not found")?;
    let data = tasks::load_tasks(&tf).map_err(|e| anyhow::anyhow!("{e}"))?;

    let mut scored: Vec<_> = data.tasks.iter()
        .filter(|t| t["type"].as_str().unwrap_or("task") == "task" || t["type"].as_str() == Some("subtask"))
        .filter(|t| tasks::classify(t, &data.tasks) == "pending")
        .map(|t| (t, tasks::focus_score(t)))
        .collect();
    scored.sort_by(|a, b| b.1.partial_cmp(&a.1).unwrap_or(std::cmp::Ordering::Equal));
    let top: Vec<_> = scored.into_iter().take(3).collect();

    if top.is_empty() {
        println!("\n  No actionable tasks.\n");
        return Ok(());
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
    Ok(())
}

pub fn cmd_search(text: &str, theme: &themes::Theme) -> anyhow::Result<()> {
    let tf = find_tasks_file().context("tasks.json not found")?;
    let data = tasks::load_tasks(&tf).map_err(|e| anyhow::anyhow!("{e}"))?;
    let results = tasks::filter_tasks(
        &data.tasks, &data.tasks,
        None, None, None, None, None, Some(text), &["task", "subtask"],
    );
    if results.is_empty() {
        println!("\n  No tasks match \"{text}\".\n");
        return Ok(());
    }
    println!("\n{}Search: \"{text}\"{}", themes::ansi(theme.color("header")), themes::RESET);
    for t in &results {
        let st = tasks::classify(t, &data.tasks);
        println!("  {}", themes::render_task_line(t, st, theme, true));
    }
    println!("\n  {} tasks\n", results.len());
    Ok(())
}

pub fn cmd_status(theme: &themes::Theme, all: bool, json_out: bool) -> anyhow::Result<()> {
    if all {
        let results = tasks::portfolio_status().map_err(|e| anyhow::anyhow!("{e}"))?;
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
        return Ok(());
    }

    let tf = find_tasks_file().context("tasks.json not found")?;
    let data = tasks::load_tasks(&tf).map_err(|e| anyhow::anyhow!("{e}"))?;

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
    Ok(())
}

pub fn cmd_blocked(theme: &themes::Theme) -> anyhow::Result<()> {
    let tf = find_tasks_file().context("tasks.json not found")?;
    let data = tasks::load_tasks(&tf).map_err(|e| anyhow::anyhow!("{e}"))?;
    let blocked: Vec<_> = data.tasks.iter()
        .filter(|t| matches!(t["type"].as_str(), Some("task" | "subtask")))
        .filter(|t| tasks::classify(t, &data.tasks) == "blocked")
        .collect();
    if blocked.is_empty() {
        println!("\n  No blocked tasks.\n");
        return Ok(());
    }
    println!("\n{}Blocked chains{}", themes::ansi(theme.color("header")), themes::RESET);
    for t in &blocked {
        println!("  {}", themes::render_task_line(t, "blocked", theme, true));
    }
    println!();
    Ok(())
}

pub fn cmd_stale(days: i64, theme: &themes::Theme) -> anyhow::Result<()> {
    let tf = find_tasks_file().context("tasks.json not found")?;
    let data = tasks::load_tasks(&tf).map_err(|e| anyhow::anyhow!("{e}"))?;
    let cutoff = (chrono::Local::now() - chrono::Duration::days(days))
        .format("%Y-%m-%d").to_string();

    let stale: Vec<_> = data.tasks.iter()
        .filter(|t| t["status"].as_str() == Some("pending"))
        .filter(|t| matches!(t["type"].as_str(), Some("task" | "subtask")))
        .filter(|t| t["created"].as_str().unwrap_or("9999") < cutoff.as_str())
        .collect();

    if stale.is_empty() {
        println!("\n  No tasks pending > {days} days.\n");
        return Ok(());
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
    Ok(())
}

pub fn cmd_context(task_id: &str, theme: &themes::Theme) -> anyhow::Result<()> {
    let tf = find_tasks_file().context("tasks.json not found")?;
    let data = tasks::load_tasks(&tf).map_err(|e| anyhow::anyhow!("{e}"))?;
    let task = data.tasks.iter().find(|t| t["id"].as_str() == Some(task_id))
        .ok_or_else(|| anyhow::anyhow!("Task {task_id} not found."))?;

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
    Ok(())
}

// ── write commands ──────────────────────────────────────────────────────

pub fn cmd_set(task_id: &str, field: &str, value: &str, append: bool, file: Option<PathBuf>) -> anyhow::Result<()> {
    let tf = match file {
        Some(f) => f,
        None => find_tasks_file().context("tasks.json not found")?,
    };
    let mut val = tasks::load_raw(&tf).map_err(|e| anyhow::anyhow!("{e}"))?;

    let idx = val["tasks"].as_array()
        .and_then(|arr| arr.iter().position(|t| t["id"].as_str() == Some(task_id)))
        .ok_or_else(|| {
            eprintln!("{{\"ok\":false,\"error\":\"task {task_id} not found\"}}");
            anyhow::anyhow!("task {task_id} not found")
        })?;

    let task = &mut val["tasks"][idx];
    match tasks::set_field(task, field, value, append) {
        Ok(()) => {
            let actual = val["tasks"][idx][field].clone();
            tasks::save_tasks(&tf, &val).map_err(|e| anyhow::anyhow!("{e}"))?;
            println!("{}", serde_json::json!({"ok": true, "id": task_id, "field": field, "value": actual}));
            Ok(())
        }
        Err(e) => {
            eprintln!("{{\"ok\":false,\"error\":{}}}", serde_json::to_string(&e).unwrap());
            Err(anyhow::anyhow!("set field failed: {e}"))
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
    priority: Option<String>,
    context: Option<String>,
    file: Option<PathBuf>,
) -> anyhow::Result<()> {
    let tf = match file {
        Some(f) => f,
        None => find_tasks_file().context("tasks.json not found")?,
    };
    let mut val = tasks::load_raw(&tf).map_err(|e| anyhow::anyhow!("{e}"))?;

    // Resolve JSON from: --json inline, @file, stdin (-), or shorthand flags
    let json_string = if let Some(j) = json {
        if j == "-" {
            // Read from stdin
            use std::io::Read;
            let mut buf = String::new();
            std::io::stdin().read_to_string(&mut buf).map_err(|e| {
                eprintln!("{{\"ok\":false,\"error\":\"failed to read stdin: {e}\"}}");
                anyhow::anyhow!("failed to read stdin: {e}")
            })?;
            buf
        } else if let Some(path) = j.strip_prefix('@') {
            // Read from file
            std::fs::read_to_string(path).map_err(|e| {
                eprintln!("{{\"ok\":false,\"error\":\"failed to read {path}: {e}\"}}");
                anyhow::anyhow!("failed to read {path}: {e}")
            })?
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
        if let Some(ref pr) = priority { obj.insert("priority".into(), serde_json::Value::String(pr.clone())); }
        if let Some(ref c) = context { obj.insert("context".into(), serde_json::Value::String(c.clone())); }
        serde_json::to_string(&obj).unwrap()
    } else {
        eprintln!("{{\"ok\":false,\"error\":\"provide --json or --subject\"}}");
        anyhow::bail!("provide --json or --subject");
    };

    let mut new_task: serde_json::Value = serde_json::from_str(&json_string).map_err(|e| {
        eprintln!("{{\"ok\":false,\"error\":\"invalid JSON: {e}\"}}");
        anyhow::anyhow!("invalid JSON: {e}")
    })?;

    if let Some(p) = new_task["priority"].as_str() {
        if let Err(e) = tasks::validate_priority(p) {
            eprintln!("{{\"ok\":false,\"error\":\"{e}\"}}");
            anyhow::bail!("{e}");
        }
    }

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
        .ok_or_else(|| {
            eprintln!("{{\"ok\":false,\"error\":\"tasks.json has no tasks array\"}}");
            anyhow::anyhow!("tasks.json has no tasks array")
        })?
        .push(new_task);
    tasks::save_tasks(&tf, &val).map_err(|e| anyhow::anyhow!("{e}"))?;
    println!("{}", serde_json::json!({"ok": true, "id": id, "subject": subject}));
    Ok(())
}

pub fn cmd_get(task_id: &str, field: Option<String>) -> anyhow::Result<()> {
    let tf = find_tasks_file().context("tasks.json not found")?;
    let data = tasks::load_tasks(&tf).map_err(|e| anyhow::anyhow!("{e}"))?;
    let task = data.tasks.iter().find(|t| t["id"].as_str() == Some(task_id))
        .ok_or_else(|| anyhow::anyhow!("task {task_id} not found"))?;

    if let Some(f) = field {
        println!("{}", serde_json::to_string(&task[f.as_str()]).unwrap());
    } else {
        println!("{}", serde_json::to_string_pretty(task).unwrap());
    }
    Ok(())
}

pub fn cmd_stats() -> anyhow::Result<()> {
    let tf = find_tasks_file().context("tasks.json not found")?;
    let data = tasks::load_tasks(&tf).map_err(|e| anyhow::anyhow!("{e}"))?;
    let stats = tasks::compute_stats(&data.tasks, &data.tasks);
    println!("{}", serde_json::to_string(&stats).unwrap());
    Ok(())
}

pub fn cmd_tags(filter: Option<String>, any: Option<String>, output: String, theme: &themes::Theme) -> anyhow::Result<()> {
    let tf = find_tasks_file().context("tasks.json not found")?;
    let data = tasks::load_tasks(&tf).map_err(|e| anyhow::anyhow!("{e}"))?;

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
        return Ok(());
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
    Ok(())
}

pub fn cmd_roadmap(json_out: bool, theme: &themes::Theme) -> anyhow::Result<()> {
    let tf = find_tasks_file().context("tasks.json not found")?;
    let data = tasks::load_tasks(&tf).map_err(|e| anyhow::anyhow!("{e}"))?;
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
    Ok(())
}

pub fn cmd_tree(root_id: &str, json_out: bool, theme: &themes::Theme) -> anyhow::Result<()> {
    let tf = find_tasks_file().context("tasks.json not found")?;
    let data = tasks::load_tasks(&tf).map_err(|e| anyhow::anyhow!("{e}"))?;

    match tasks::subtree(&data.tasks, &data.tasks, root_id) {
        Some(tree) => {
            if json_out {
                println!("{}", serde_json::to_string(&tree).unwrap());
            } else {
                render_tree_node(&tree, theme, 0);
                println!();
            }
            Ok(())
        }
        None => anyhow::bail!("task {root_id} not found"),
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

pub fn cmd_diff(theme: &themes::Theme) -> anyhow::Result<()> {
    let tf = find_tasks_file().context("tasks.json not found")?;
    let root = crate::util::find_project_root().context("Not in git repo")?;
    let rel = tf.strip_prefix(&root).unwrap_or(&tf);

    let output = std::process::Command::new("git")
        .args(["show", &format!("HEAD:{}", rel.display())])
        .current_dir(&root)
        .output();

    let prev_tasks = match output {
        Ok(o) if o.status.success() => {
            let content = String::from_utf8_lossy(&o.stdout);
            serde_json::from_str::<serde_json::Value>(&content)
                .ok()
                .and_then(|v| v["tasks"].as_array().cloned())
                .unwrap_or_default()
        }
        _ => vec![],
    };

    let data = tasks::load_tasks(&tf).map_err(|e| anyhow::anyhow!("{e}"))?;
    let prev_ids: std::collections::HashSet<&str> = prev_tasks.iter().filter_map(|t| t["id"].as_str()).collect();
    let curr_ids: std::collections::HashSet<&str> = data.tasks.iter().filter_map(|t| t["id"].as_str()).collect();

    let added: Vec<_> = curr_ids.difference(&prev_ids).collect();
    let removed: Vec<_> = prev_ids.difference(&curr_ids).collect();

    println!("\n{}Task diff (vs last commit){}", themes::ansi(theme.color("header")), themes::RESET);
    if added.is_empty() && removed.is_empty() {
        println!("  No structural changes (IDs match).\n");
    } else {
        for id in &added {
            if let Some(t) = data.tasks.iter().find(|t| t["id"].as_str() == Some(id)) {
                println!("{}  + {} {}{}", themes::ansi("green"), id, t["subject"].as_str().unwrap_or(""), themes::RESET);
            }
        }
        for id in &removed {
            println!("{}  - {}{}", themes::ansi("red"), id, themes::RESET);
        }
        println!();
    }
    Ok(())
}

pub fn cmd_burndown(period: &str, theme: &themes::Theme) -> anyhow::Result<()> {
    let tf = find_tasks_file().context("tasks.json not found")?;
    let data = tasks::load_tasks(&tf).map_err(|e| anyhow::anyhow!("{e}"))?;
    let result = tasks::burndown(&data.tasks, period);

    let label = if period == "month" { "Last 30 days" } else { "Last 7 days" };
    let created = result["created"].as_u64().unwrap_or(0);
    let completed = result["completed"].as_u64().unwrap_or(0);
    let delta = result["delta"].as_i64().unwrap_or(0);
    let direction = result["direction"].as_str().unwrap_or("stable");

    let (arrow, color) = match direction {
        "shrinking" => ("↓", "green"),
        "growing" => ("↑", "red"),
        _ => ("=", "yellow"),
    };

    println!("\n{}Burndown — {label}{}", themes::ansi(theme.color("header")), themes::RESET);
    println!("  Created:   {created}");
    println!("  Completed: {completed}");
    println!("{}  Net:       {delta} {arrow}{}", themes::ansi(color), themes::RESET);
    println!();
    Ok(())
}

// ── rollup ───────────────────────────────────────────────────────────────

// ── pure logic (testable) ───────────────────────────────────────────────

/// Collect IDs of all descendants of `root_id` (BFS over parent field).
fn collect_descendants(tasks: &[serde_json::Value], root_id: &str) -> std::collections::HashSet<String> {
    let mut result = std::collections::HashSet::new();
    let mut queue = vec![root_id.to_string()];
    while let Some(pid) = queue.pop() {
        for t in tasks {
            if t["parent"].as_str() == Some(&pid) {
                if let Some(id) = t["id"].as_str() {
                    if result.insert(id.to_string()) {
                        queue.push(id.to_string());
                    }
                }
            }
        }
    }
    result
}

/// Remove `ids` from the tasks array and clean blocked_by references.
fn remove_ids_and_clean(val: &mut serde_json::Value, ids: &std::collections::HashSet<String>) {
    let tasks_arr = val["tasks"].as_array_mut().unwrap();
    tasks_arr.retain(|t| {
        t["id"].as_str().map_or(true, |id| !ids.contains(id))
    });
    for task in tasks_arr.iter_mut() {
        if let Some(deps) = task["blocked_by"].as_array_mut() {
            deps.retain(|d| d.as_str().map_or(true, |id| !ids.contains(id)));
        }
    }
}

/// Delete a task (and optionally its descendants) from a mutable Value.
/// Returns (removed_count) or an error message.
pub fn delete_task(val: &mut serde_json::Value, task_id: &str, cascade: bool) -> Result<usize, String> {
    let arr = val["tasks"].as_array().cloned().unwrap_or_default();

    if !arr.iter().any(|t| t["id"].as_str() == Some(task_id)) {
        return Err(format!("task {task_id} not found"));
    }

    let children: Vec<String> = arr.iter()
        .filter(|t| t["parent"].as_str() == Some(task_id))
        .filter_map(|t| t["id"].as_str().map(String::from))
        .collect();

    if !children.is_empty() && !cascade {
        return Err(format!("task {task_id} has {} children ({}). Use --cascade to delete them too.", children.len(), children.join(", ")));
    }

    let mut to_delete = std::collections::HashSet::new();
    to_delete.insert(task_id.to_string());
    if cascade {
        to_delete.extend(collect_descendants(&arr, task_id));
    }

    let removed_count = to_delete.len();
    remove_ids_and_clean(val, &to_delete);
    Ok(removed_count)
}

/// Move a task to a new parent. Returns (old_parent) or error.
pub fn move_task(val: &mut serde_json::Value, task_id: &str, new_parent: &str) -> Result<Option<String>, String> {
    let arr = val["tasks"].as_array().cloned().unwrap_or_default();

    let idx = arr.iter().position(|t| t["id"].as_str() == Some(task_id))
        .ok_or_else(|| format!("task {task_id} not found"))?;

    let old_parent = arr[idx]["parent"].as_str().map(String::from);

    if new_parent == "null" {
        val["tasks"][idx]["parent"] = serde_json::Value::Null;
    } else {
        if !arr.iter().any(|t| t["id"].as_str() == Some(new_parent)) {
            return Err(format!("parent {new_parent} not found"));
        }
        let descendants = collect_descendants(&arr, task_id);
        if descendants.contains(new_parent) {
            return Err(format!("circular: {new_parent} is a descendant of {task_id}"));
        }
        val["tasks"][idx]["parent"] = serde_json::Value::String(new_parent.to_string());
    }

    Ok(old_parent)
}

/// Archive a completed phase and its descendants. Returns (archived_tasks, archive_value) or error.
pub fn archive_phase(val: &mut serde_json::Value, phase_id: &str) -> Result<(Vec<serde_json::Value>, usize), String> {
    let arr = val["tasks"].as_array().cloned().unwrap_or_default();

    let phase = arr.iter().find(|t| t["id"].as_str() == Some(phase_id))
        .ok_or_else(|| format!("task {phase_id} not found"))?;

    if phase["type"].as_str() != Some("phase") {
        return Err(format!("{phase_id} is not a phase"));
    }
    if phase["status"].as_str() != Some("completed") {
        return Err(format!("{phase_id} is not completed"));
    }

    let mut to_archive = std::collections::HashSet::new();
    to_archive.insert(phase_id.to_string());
    to_archive.extend(collect_descendants(&arr, phase_id));

    let archived: Vec<serde_json::Value> = arr.iter()
        .filter(|t| t["id"].as_str().map_or(false, |id| to_archive.contains(id)))
        .cloned()
        .collect();
    let archived_count = archived.len();

    remove_ids_and_clean(val, &to_archive);
    Ok((archived, archived_count))
}

/// List completed phases eligible for archiving.
pub fn list_archivable(val: &serde_json::Value) -> Vec<serde_json::Value> {
    val["tasks"].as_array()
        .map(|arr| arr.iter()
            .filter(|t| t["type"].as_str() == Some("phase") && t["status"].as_str() == Some("completed"))
            .map(|p| serde_json::json!({"id": p["id"], "subject": p["subject"]}))
            .collect())
        .unwrap_or_default()
}

// ── CLI wrappers (thin, handle I/O + exit) ──────────────────────────────

pub fn cmd_delete(task_id: &str, cascade: bool, file: Option<PathBuf>) -> anyhow::Result<()> {
    let tf = match file {
        Some(f) => f,
        None => find_tasks_file().context("tasks.json not found")?,
    };
    let mut val = tasks::load_raw(&tf).map_err(|e| anyhow::anyhow!("{e}"))?;

    match delete_task(&mut val, task_id, cascade) {
        Ok(removed_count) => {
            tasks::save_tasks(&tf, &val).map_err(|e| anyhow::anyhow!("{e}"))?;
            println!("{}", serde_json::json!({"ok": true, "id": task_id, "action": "deleted", "cascade_removed": removed_count - 1}));
            Ok(())
        }
        Err(e) => {
            eprintln!("{{\"ok\":false,\"error\":{}}}", serde_json::to_string(&e).unwrap());
            Err(anyhow::anyhow!("{e}"))
        }
    }
}

pub fn cmd_move(task_id: &str, new_parent: &str, file: Option<PathBuf>) -> anyhow::Result<()> {
    let tf = match file {
        Some(f) => f,
        None => find_tasks_file().context("tasks.json not found")?,
    };
    let mut val = tasks::load_raw(&tf).map_err(|e| anyhow::anyhow!("{e}"))?;

    match move_task(&mut val, task_id, new_parent) {
        Ok(old_parent) => {
            tasks::save_tasks(&tf, &val).map_err(|e| anyhow::anyhow!("{e}"))?;
            println!("{}", serde_json::json!({
                "ok": true, "id": task_id, "field": "parent", "from": old_parent,
                "to": if new_parent == "null" { serde_json::Value::Null } else { serde_json::Value::String(new_parent.to_string()) }
            }));
            Ok(())
        }
        Err(e) => {
            eprintln!("{{\"ok\":false,\"error\":{}}}", serde_json::to_string(&e).unwrap());
            Err(anyhow::anyhow!("{e}"))
        }
    }
}

pub fn cmd_archive(phase_id: Option<String>, file: Option<PathBuf>) -> anyhow::Result<()> {
    let tf = match file {
        Some(f) => f,
        None => find_tasks_file().context("tasks.json not found")?,
    };
    let mut val = tasks::load_raw(&tf).map_err(|e| anyhow::anyhow!("{e}"))?;

    if phase_id.is_none() {
        let archivable = list_archivable(&val);
        println!("{}", serde_json::json!({"ok": true, "archivable": archivable}));
        return Ok(());
    }

    let pid = phase_id.unwrap();
    match archive_phase(&mut val, &pid) {
        Ok((archived, archived_count)) => {
            let archive_path = tf.with_file_name("tasks-archive.json");
            let mut archive_val = if archive_path.exists() {
                tasks::load_raw(&archive_path).unwrap_or_else(|_| serde_json::json!({"tasks": []}))
            } else {
                serde_json::json!({"tasks": []})
            };
            archive_val["tasks"].as_array_mut().unwrap().extend(archived);

            let remaining = val["tasks"].as_array().map_or(0, |a| a.len());
            tasks::save_tasks(&tf, &val).map_err(|e| anyhow::anyhow!("{e}"))?;
            tasks::save_tasks(&archive_path, &archive_val).map_err(|e| anyhow::anyhow!("{e}"))?;
            println!("{}", serde_json::json!({"ok": true, "archived": archived_count, "remaining": remaining}));
            Ok(())
        }
        Err(e) => {
            eprintln!("{{\"ok\":false,\"error\":{}}}", serde_json::to_string(&e).unwrap());
            Err(anyhow::anyhow!("{e}"))
        }
    }
}

// ── tests ───────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn mock_tasks() -> serde_json::Value {
        json!({"tasks": [
            {"id": "ph-001", "type": "phase", "subject": "Phase A", "status": "completed", "parent": null, "tags": [], "blocked_by": []},
            {"id": "ms-001", "type": "milestone", "subject": "Milestone A1", "status": "completed", "parent": "ph-001", "tags": [], "blocked_by": []},
            {"id": "t-001", "type": "task", "subject": "Task 1", "status": "completed", "parent": "ms-001", "tags": [], "blocked_by": []},
            {"id": "t-002", "type": "task", "subject": "Task 2", "status": "completed", "parent": "ms-001", "tags": [], "blocked_by": ["t-001"]},
            {"id": "t-003", "type": "task", "subject": "Standalone", "status": "pending", "parent": null, "tags": [], "blocked_by": ["t-001"]},
            {"id": "t-004", "type": "task", "subject": "Parent task", "status": "pending", "parent": null, "tags": [], "blocked_by": []},
            {"id": "st-004a", "type": "subtask", "subject": "Child A", "status": "pending", "parent": "t-004", "tags": [], "blocked_by": []},
            {"id": "st-004b", "type": "subtask", "subject": "Child B", "status": "pending", "parent": "t-004", "tags": [], "blocked_by": ["st-004a"]},
        ]})
    }

    fn task_ids(val: &serde_json::Value) -> Vec<String> {
        val["tasks"].as_array().unwrap().iter()
            .filter_map(|t| t["id"].as_str().map(String::from))
            .collect()
    }

    fn blocked_by(val: &serde_json::Value, task_id: &str) -> Vec<String> {
        val["tasks"].as_array().unwrap().iter()
            .find(|t| t["id"].as_str() == Some(task_id))
            .and_then(|t| t["blocked_by"].as_array())
            .map(|a| a.iter().filter_map(|v| v.as_str().map(String::from)).collect())
            .unwrap_or_default()
    }

    fn parent_of(val: &serde_json::Value, task_id: &str) -> Option<String> {
        val["tasks"].as_array().unwrap().iter()
            .find(|t| t["id"].as_str() == Some(task_id))
            .and_then(|t| t["parent"].as_str().map(String::from))
    }

    // ── delete tests ────────────────────────────────────────────────

    #[test]
    fn delete_removes_task() {
        let mut val = mock_tasks();
        let result = delete_task(&mut val, "t-003", false);
        assert!(result.is_ok());
        assert_eq!(result.unwrap(), 1);
        assert!(!task_ids(&val).contains(&"t-003".to_string()));
    }

    #[test]
    fn delete_cleans_blocked_by() {
        let mut val = mock_tasks();
        delete_task(&mut val, "t-001", false).unwrap();
        // t-002 had blocked_by: ["t-001"], should now be empty
        assert!(blocked_by(&val, "t-002").is_empty());
        // t-003 had blocked_by: ["t-001"], should now be empty
        assert!(blocked_by(&val, "t-003").is_empty());
    }

    #[test]
    fn delete_refuses_parent_without_cascade() {
        let mut val = mock_tasks();
        let result = delete_task(&mut val, "t-004", false);
        assert!(result.is_err());
        assert!(result.unwrap_err().contains("children"));
        // Task still exists
        assert!(task_ids(&val).contains(&"t-004".to_string()));
    }

    #[test]
    fn delete_cascade_removes_subtree() {
        let mut val = mock_tasks();
        let result = delete_task(&mut val, "t-004", true);
        assert!(result.is_ok());
        assert_eq!(result.unwrap(), 3); // t-004 + st-004a + st-004b
        let ids = task_ids(&val);
        assert!(!ids.contains(&"t-004".to_string()));
        assert!(!ids.contains(&"st-004a".to_string()));
        assert!(!ids.contains(&"st-004b".to_string()));
    }

    #[test]
    fn delete_nonexistent_fails() {
        let mut val = mock_tasks();
        let result = delete_task(&mut val, "t-999", false);
        assert!(result.is_err());
        assert!(result.unwrap_err().contains("not found"));
    }

    // ── move tests ──────────────────────────────────────────────────

    #[test]
    fn move_changes_parent() {
        let mut val = mock_tasks();
        let result = move_task(&mut val, "t-003", "ms-001");
        assert!(result.is_ok());
        assert_eq!(result.unwrap(), None); // was root (null parent)
        assert_eq!(parent_of(&val, "t-003").as_deref(), Some("ms-001"));
    }

    #[test]
    fn move_to_null_makes_root() {
        let mut val = mock_tasks();
        let result = move_task(&mut val, "t-001", "null");
        assert!(result.is_ok());
        assert_eq!(result.unwrap().as_deref(), Some("ms-001"));
        assert_eq!(parent_of(&val, "t-001"), None);
    }

    #[test]
    fn move_nonexistent_parent_fails() {
        let mut val = mock_tasks();
        let result = move_task(&mut val, "t-003", "ms-999");
        assert!(result.is_err());
        assert!(result.unwrap_err().contains("not found"));
    }

    #[test]
    fn move_circular_fails() {
        let mut val = mock_tasks();
        // Try to move t-004 under its own child st-004a
        let result = move_task(&mut val, "t-004", "st-004a");
        assert!(result.is_err());
        assert!(result.unwrap_err().contains("circular"));
    }

    #[test]
    fn move_nonexistent_task_fails() {
        let mut val = mock_tasks();
        let result = move_task(&mut val, "t-999", "ms-001");
        assert!(result.is_err());
    }

    // ── archive tests ───────────────────────────────────────────────

    #[test]
    fn archive_extracts_phase_subtree() {
        let mut val = mock_tasks();
        let result = archive_phase(&mut val, "ph-001");
        assert!(result.is_ok());
        let (archived, count) = result.unwrap();
        assert_eq!(count, 4); // ph-001 + ms-001 + t-001 + t-002
        let archived_ids: Vec<&str> = archived.iter().filter_map(|t| t["id"].as_str()).collect();
        assert!(archived_ids.contains(&"ph-001"));
        assert!(archived_ids.contains(&"ms-001"));
        assert!(archived_ids.contains(&"t-001"));
        assert!(archived_ids.contains(&"t-002"));
        // Remaining tasks should not include archived ones
        let remaining = task_ids(&val);
        assert!(!remaining.contains(&"ph-001".to_string()));
        assert!(remaining.contains(&"t-003".to_string()));
    }

    #[test]
    fn archive_cleans_blocked_by() {
        let mut val = mock_tasks();
        archive_phase(&mut val, "ph-001").unwrap();
        // t-003 had blocked_by: ["t-001"] which was archived
        assert!(blocked_by(&val, "t-003").is_empty());
    }

    #[test]
    fn archive_non_phase_fails() {
        let mut val = mock_tasks();
        let result = archive_phase(&mut val, "t-001");
        assert!(result.is_err());
        assert!(result.unwrap_err().contains("not a phase"));
    }

    #[test]
    fn archive_incomplete_phase_fails() {
        let mut val = mock_tasks();
        // ph-020 is pending, not completed — should be in mock but isn't, add inline
        val["tasks"].as_array_mut().unwrap().push(json!(
            {"id": "ph-020", "type": "phase", "subject": "Phase B", "status": "pending", "parent": null, "tags": [], "blocked_by": []}
        ));
        let result = archive_phase(&mut val, "ph-020");
        assert!(result.is_err());
        assert!(result.unwrap_err().contains("not completed"));
    }

    #[test]
    fn list_archivable_finds_completed_phases() {
        let val = mock_tasks();
        let result = list_archivable(&val);
        assert_eq!(result.len(), 1);
        assert_eq!(result[0]["id"].as_str(), Some("ph-001"));
    }
}

pub fn cmd_rollup(file: Option<PathBuf>, dry_run: bool) -> anyhow::Result<()> {
    let tf = match file {
        Some(f) => f,
        None => find_tasks_file().context("tasks.json not found")?,
    };
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
            anyhow::bail!("rollup failed: {e}");
        }
    }
    Ok(())
}
