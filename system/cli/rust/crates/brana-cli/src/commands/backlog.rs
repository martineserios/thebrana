//! Backlog subcommand handlers

use std::io::{self, BufRead, Write};
use std::path::PathBuf;

use anyhow::Context;

use crate::tasks;
use crate::themes;
use crate::util::find_tasks_file;

// ── backlog commands ────────────────────────────────────────────────────

/// Pure selection core of `cmd_next`: unblocked pending tasks, filtered and
/// priority-sorted, capped at `limit`. Blocker resolution runs against the
/// full `all` slice via `classify`, so a task blocked only by a completed
/// task in another epic correctly counts as ready — scoping the resolution
/// to an epic subset would mislabel it blocked (t-2279).
#[allow(clippy::too_many_arguments)]
pub(crate) fn select_next<'a>(
    all: &'a [serde_json::Value],
    tag: Option<&str>,
    kind: Option<&str>,
    priority: Option<&str>,
    effort: Option<&str>,
    task_type: Option<&str>,
    parent: Option<&str>,
    epic: Option<&str>,
    limit: usize,
) -> Vec<&'a serde_json::Value> {
    let types: Vec<&str> = match task_type {
        Some(tp) => tp.split(',').collect(),
        None => vec!["task", "subtask"],
    };

    let mut candidates = tasks::filter_tasks_by(
        all, all,
        &tasks::TaskFilter {
            tag,
            status: Some("pending"),
            priority,
            effort,
            epic,
            types: types.clone(),
            ..Default::default()
        },
    );

    // filter_tasks does raw-status matching (tasks.spec.md). For "next up"
    // we want only classify=="pending" — exclude blocked and parked.
    candidates.retain(|t| tasks::classify(t, all) == "pending");

    if let Some(k) = kind {
        candidates.retain(|t| t["kind"].as_str().unwrap_or("") == k);
    }
    if let Some(pid) = parent {
        candidates.retain(|t| t["parent"].as_str() == Some(pid));
    }

    tasks::sort_by_priority(&mut candidates);
    candidates.into_iter().take(limit).collect()
}

#[allow(clippy::too_many_arguments)]
pub fn cmd_next(
    theme: &themes::Theme, tag: Option<String>,
    kind: Option<String>,
    limit: usize, priority: Option<String>, task_type: Option<String>,
    effort: Option<String>, parent: Option<String>, epic: Option<String>, json_out: bool,
) -> anyhow::Result<()> {
    let tf = find_tasks_file().context("tasks.json not found")?;
    let data = tasks::load_tasks(&tf).map_err(|e| anyhow::anyhow!("{e}"))?;

    let top = select_next(
        &data.tasks,
        tag.as_deref(),
        kind.as_deref(),
        priority.as_deref(),
        effort.as_deref(),
        task_type.as_deref(),
        parent.as_deref(),
        epic.as_deref(),
        limit,
    );

    if json_out {
        println!("{}", serde_json::to_string(&top).unwrap());
        return Ok(());
    }

    if top.is_empty() {
        println!("\n  No unblocked tasks found.\n");
        return Ok(());
    }

    println!("\n{}Next up{}", themes::ansi(theme.color("header")), themes::RESET);
    for (i, t) in top.iter().enumerate() {
        let pri = t["priority"].as_str().unwrap_or("—");
        let eff = t["effort"].as_str().unwrap_or("—");
        let wt = t["work_type"].as_str().unwrap_or("—");
        let line = format!(
            "  {}. {} {}  {}  {}  {}  {}",
            i + 1, theme.icon("pending"),
            t["id"].as_str().unwrap_or("?"),
            t["subject"].as_str().unwrap_or(""),
            pri, eff, wt,
        );
        println!("{}{line}{}", themes::ansi(theme.color("pending")), themes::RESET);
    }
    println!();
    Ok(())
}

/// Sort `results` in place. `priority` = P0→P3 (reuses the `next` ordering);
/// `status` = lifecycle (active → pending → blocked → parked → done), tie-broken
/// by priority. `classify` runs against the full `all` slice so blocked/ready is
/// resolved across epics. Unknown keys are a no-op (t-2279).
pub(crate) fn sort_query(results: &mut [&serde_json::Value], all: &[serde_json::Value], sort: &str) {
    match sort {
        "priority" => tasks::sort_by_priority(results),
        "status" => {
            let rank = |t: &serde_json::Value| match tasks::classify(t, all) {
                "active" => 0,
                "pending" => 1,
                "blocked" => 2,
                "parked" => 3,
                _ => 4, // done
            };
            let pri = |t: &serde_json::Value| match t["priority"].as_str() {
                Some("P0") => 0,
                Some("P1") => 1,
                Some("P2") => 2,
                Some("P3") => 3,
                _ => 4,
            };
            results.sort_by(|a, b| (rank(a), pri(a)).cmp(&(rank(b), pri(b))));
        }
        _ => {}
    }
}

#[allow(clippy::too_many_arguments)]
pub fn cmd_query(
    tag: Option<String>, status: Option<String>,
    kind: Option<String>,
    priority: Option<String>, effort: Option<String>, search: Option<String>,
    count: bool, output: String, theme: &themes::Theme,
    task_type: Option<String>, parent: Option<String>, branch: Option<String>,
    work_type: Option<String>, epic: Option<String>, ac_state: Option<String>,
    sort: Option<String>,
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

    let mut results = tasks::filter_tasks_by(
        &data.tasks, &data.tasks,
        &tasks::TaskFilter {
            status: status.as_deref(),
            priority: priority.as_deref(),
            effort: effort.as_deref(),
            search: search.as_deref(),
            types: types.clone(),
            epic: epic.as_deref(),
            work_type: work_type.as_deref(),
            ac_state: ac_state.as_deref(),
            ..Default::default()
        },
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

    // Apply kind filter
    if let Some(ref k) = kind {
        results.retain(|t| t["kind"].as_str().unwrap_or("") == k.as_str());
    }

    // Apply parent filter
    if let Some(ref pid) = parent {
        results.retain(|t| t["parent"].as_str() == Some(pid.as_str()));
    }

    // Apply branch filter
    if let Some(ref br) = branch {
        results.retain(|t| t["branch"].as_str() == Some(br.as_str()));
    }

    // Apply sort (default output order is file order)
    if let Some(ref key) = sort {
        sort_query(&mut results, &data.tasks, key);
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

pub fn cmd_focus(
    theme: &themes::Theme,
    top: usize,
    json_out: bool,
    work_type: Option<&str>,
    epic_override: Option<&str>,
) -> anyhow::Result<()> {
    let tf = find_tasks_file().context("tasks.json not found")?;
    let data = tasks::load_tasks(&tf).map_err(|e| anyhow::anyhow!("{e}"))?;

    let cfg = load_tasks_config();
    let active = epic_override
        .map(|s| s.to_string())
        .or_else(|| cfg["active_epic"].as_str().map(|s| s.to_string()));

    let mut scored: Vec<_> = data.tasks.iter()
        .filter(|t| matches!(t["type"].as_str().unwrap_or("task"), "task" | "subtask"))
        .filter(|t| tasks::classify(t, &data.tasks) == "pending")
        .filter(|t| work_type.map_or(true, |wt| t["work_type"].as_str().unwrap_or("") == wt))
        .map(|t| {
            let boost = active.as_deref()
                .filter(|a| t["epic"].as_str() == Some(a))
                .map_or(0.0, |_| 500.0);
            (t, tasks::focus_score(t, boost))
        })
        .collect();
    scored.sort_by(|a, b| b.1.partial_cmp(&a.1).unwrap_or(std::cmp::Ordering::Equal));

    if json_out {
        let out: Vec<_> = scored.iter().take(top).map(|(t, score)| {
            serde_json::json!({"task": t, "focus_score": score,
                "active_epic": active.as_deref()})
        }).collect();
        println!("{}", serde_json::to_string(&out).unwrap());
        return Ok(());
    }

    if scored.is_empty() {
        println!("\n  No actionable tasks.\n");
        return Ok(());
    }

    if let Some(ref slug) = active {
        // Active-epic path: ★ tasks first, then P0/P1 overflow
        let (epic_tasks, overflow): (Vec<_>, Vec<_>) = scored.iter().partition(|(t, _)| {
            t["epic"].as_str() == Some(slug.as_str())
        });
        let initiative_shown = epic_tasks.len().min(top);
        let overflow_slots = top.saturating_sub(initiative_shown);
        let overflow_shown: Vec<_> = overflow.iter()
            .filter(|(t, _)| matches!(t["priority"].as_str(), Some("P0") | Some("P1")))
            .take(overflow_slots)
            .collect();

        println!("\n{}Focus — active: {}{}", themes::ansi(theme.color("header")), slug, themes::RESET);
        let mut rank = 1;
        for (t, score) in epic_tasks.iter().take(top) {
            let pri = t["priority"].as_str().unwrap_or("—");
            let eff = t["effort"].as_str().unwrap_or("—");
            println!(
                "{}  {}. ★ {} {}  {}  {}  (score: {:.0}){}",
                themes::ansi(theme.color("pending")),
                rank, t["id"].as_str().unwrap_or("?"),
                t["subject"].as_str().unwrap_or(""), pri, eff, score,
                themes::RESET,
            );
            rank += 1;
        }
        if !overflow_shown.is_empty() {
            println!("{}  ─── overflow (P0/P1) ───{}", themes::ansi(theme.color("header")), themes::RESET);
            for (t, score) in &overflow_shown {
                let pri = t["priority"].as_str().unwrap_or("—");
                let eff = t["effort"].as_str().unwrap_or("—");
                println!(
                    "{}  {}. {} {}  {}  {}  (score: {:.0}){}",
                    themes::ansi(theme.color("pending")),
                    rank, t["id"].as_str().unwrap_or("?"),
                    t["subject"].as_str().unwrap_or(""), pri, eff, score,
                    themes::RESET,
                );
                rank += 1;
            }
        }
    } else {
        // No active epic — show top N by score
        println!("\n{}Focus — today's pick{}", themes::ansi(theme.color("header")), themes::RESET);
        for (rank, (t, score)) in scored.iter().take(top).enumerate() {
            let pri = t["priority"].as_str().unwrap_or("—");
            let eff = t["effort"].as_str().unwrap_or("—");
            println!(
                "{}  {}. {} {}  {}  {}  (score: {:.0}){}",
                themes::ansi(theme.color("pending")),
                rank + 1, t["id"].as_str().unwrap_or("?"),
                t["subject"].as_str().unwrap_or(""), pri, eff, score,
                themes::RESET,
            );
        }
    }

    println!();
    Ok(())
}

pub fn cmd_search(text: &str, theme: &themes::Theme, json_out: bool) -> anyhow::Result<()> {
    let tf = find_tasks_file().context("tasks.json not found")?;
    let data = tasks::load_tasks(&tf).map_err(|e| anyhow::anyhow!("{e}"))?;
    let results = tasks::filter_tasks_by(
        &data.tasks, &data.tasks,
        &tasks::TaskFilter {
            search: Some(text),
            types: vec!["task", "subtask"],
            ..Default::default()
        },
    );
    if json_out {
        println!("{}", serde_json::to_string(&results).unwrap());
        return Ok(());
    }
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
    println!("  Status: {st}  WorkType: {}  Priority: {}  Effort: {}",
        task["work_type"].as_str().unwrap_or("—"),
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

// ── config helpers ──────────────────────────────────────────────────────

/// Resolve the tasks-config.json path to write: project-local when a repo root is
/// found, else the global `~/.claude/tasks-config.json`.
fn tasks_config_path() -> std::path::PathBuf {
    crate::util::find_tasks_config().unwrap_or_else(crate::util::global_tasks_config_path)
}

/// Load tasks-config with per-repo scoping (delegates to the shared core resolver).
///
/// Doubles as seed-on-create: with no project-local file, this returns global minus the
/// project-scoped keys, so `cmd_set_active` carries theme/github_sync defaults into the new
/// local file while never inheriting a foreign `active_epic`.
fn load_tasks_config() -> serde_json::Value {
    crate::util::load_tasks_config()
}

/// Save tasks-config to the project-local path, creating `.claude/` if needed.
fn save_tasks_config(cfg: &serde_json::Value) -> anyhow::Result<()> {
    let path = tasks_config_path();
    if let Some(dir) = path.parent() {
        std::fs::create_dir_all(dir).ok();
    }
    let content = serde_json::to_string_pretty(cfg).unwrap() + "\n";
    std::fs::write(&path, content)
        .with_context(|| format!("failed to write {}", path.display()))
}

/// Set active_epic in tasks-config.json.
///
/// Hard-stops instead of falling back to the global config when no project root is
/// determinable (ADR-066): `active_epic` is project-scoped by definition, so there is
/// no correct project-local file to write when no project can be resolved — silently
/// writing global would reintroduce the cross-project bleed this ADR closes.
pub fn cmd_set_active(slug: &str) -> anyhow::Result<()> {
    if crate::util::find_tasks_config().is_none() {
        anyhow::bail!(
            "no project root found (not in a git repo, and no local .claude/ present) — \
             cannot resolve a scoped config path for set-active"
        );
    }
    let mut cfg = load_tasks_config();
    cfg["active_epic"] = serde_json::Value::String(slug.to_string());
    save_tasks_config(&cfg)?;
    println!("{}", serde_json::json!({"ok": true, "active_epic": slug}));
    Ok(())
}

// ── write commands ──────────────────────────────────────────────────────

pub fn cmd_set(task_id: &str, field: &str, value: &str, append: bool, file: Option<PathBuf>) -> anyhow::Result<()> {
    let tf = match file {
        Some(f) => f,
        None => find_tasks_file().context("tasks.json not found")?,
    };
    let _lock = tasks::lock_tasks(&tf).map_err(|e| anyhow::anyhow!("{e}"))?; // t-2166: serialize RMW
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
    kind: Option<String>,
    task_type: Option<String>,
    tags: Option<String>,
    description: Option<String>,
    effort: Option<String>,
    parent: Option<String>,
    priority: Option<String>,
    context: Option<String>,
    file: Option<PathBuf>,
    project: Option<String>,
    epic: Option<String>,
    work_type: Option<String>,
    acceptance_criteria: Vec<String>,
) -> anyhow::Result<()> {
    // Target backlog: explicit --file, else --project slug (cross-project via portfolio),
    // else the current project's tasks.json. --file and --project are mutually exclusive
    // (enforced by clap); the guard here is defensive.
    let tf = match (file, project) {
        (Some(_), Some(_)) => {
            eprintln!("{{\"ok\":false,\"error\":\"--file and --project are mutually exclusive\"}}");
            anyhow::bail!("--file and --project are mutually exclusive");
        }
        (Some(f), None) => f,
        (None, Some(slug)) => crate::util::resolve_project_tasks_file(&slug).map_err(|e| {
            eprintln!("{{\"ok\":false,\"error\":\"{e}\"}}");
            anyhow::anyhow!("{e}")
        })?,
        (None, None) => find_tasks_file().context("tasks.json not found")?,
    };
    let _lock = tasks::lock_tasks(&tf).map_err(|e| anyhow::anyhow!("{e}"))?; // t-2166: serialize RMW
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
        if let Some(ref k) = kind { obj.insert("kind".into(), serde_json::Value::String(k.clone())); }
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
        if epic.is_some() {
            eprintln!("  ⚠ --epic is deprecated and ignored (ADR-065: epic is now a hierarchy node, not a flat field) — link via --parent instead");
        }
        if let Some(ref wt) = work_type { obj.insert("work_type".into(), serde_json::Value::String(wt.clone())); }
        if !acceptance_criteria.is_empty() {
            let ac_arr: Vec<serde_json::Value> = acceptance_criteria.iter()
                .map(|s| serde_json::Value::String(s.clone()))
                .collect();
            obj.insert("acceptance_criteria".into(), serde_json::Value::Array(ac_arr));
        }
        serde_json::to_string(&obj).unwrap()
    } else {
        eprintln!("{{\"ok\":false,\"error\":\"provide --json or --subject\"}}");
        anyhow::bail!("provide --json or --subject");
    };

    let mut new_task: serde_json::Value = serde_json::from_str(&json_string).map_err(|e| {
        eprintln!("{{\"ok\":false,\"error\":\"invalid JSON: {e}\"}}");
        anyhow::anyhow!("invalid JSON: {e}")
    })?;

    // t-2310 (ADR-065): level/epic are retired write-surface fields — level
    // collapses into type, epic becomes a hierarchy node (not a flat value a
    // new task can carry). Reject the whole add rather than silently drop them.
    if new_task.as_object().map_or(false, |o| o.contains_key("level") || o.contains_key("epic")) {
        eprintln!("{{\"ok\":false,\"error\":\"level/epic fields are retired (ADR-065) — level collapses into type, epic is now a hierarchy node; use --parent for hierarchy\"}}");
        anyhow::bail!("level/epic fields are retired (ADR-065) — level collapses into type, epic is now a hierarchy node; use --parent for hierarchy");
    }

    if let Some(p) = new_task["priority"].as_str() {
        if let Err(e) = tasks::validate_priority(p) {
            eprintln!("{{\"ok\":false,\"error\":\"{e}\"}}");
            anyhow::bail!("{e}");
        }
    }

    if let Some(k) = new_task["kind"].as_str() {
        if let Err(e) = tasks::validate_kind(k) {
            eprintln!("{{\"ok\":false,\"error\":\"{e}\"}}");
            anyhow::bail!("{e}");
        }
    }
    if let Some(s) = new_task["status"].as_str() {
        if let Err(e) = tasks::validate_status(s) {
            eprintln!("{{\"ok\":false,\"error\":\"{e}\"}}");
            anyhow::bail!("{e}");
        }
    }
    if let Some(a) = new_task["ac_state"].as_str() {
        if let Err(e) = tasks::validate_ac_state(a) {
            eprintln!("{{\"ok\":false,\"error\":\"{e}\"}}");
            anyhow::bail!("{e}");
        }
    }
    {
        let effort = new_task["effort"].as_str();
        let context = new_task["context"].as_str();
        if let Err(e) = tasks::validate_context_for_effort(effort, context) {
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
    // t-1544: null priority is an error state — default to P3 at write time
    if new_task["priority"].is_null() { new_task["priority"] = serde_json::Value::String("P3".into()); }
    // t-2283: stamp ac_state:none on new tasks (v3 forward-only). Pre-existing
    // tasks loaded from the file keep their absent key — only this new object is
    // touched. An explicit ac_state in the payload (validated above) is preserved.
    if new_task["ac_state"].is_null() {
        new_task["ac_state"] = serde_json::Value::String(tasks::AC_STATE_DEFAULT.into());
    }
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

/// Definition-of-ready lint for autonomous dispatch (t-1981).
/// Returns Ok(ready); the caller maps not-ready to exit code 1.
pub fn cmd_lint(task_id: &str, json_out: bool, file: Option<PathBuf>) -> anyhow::Result<bool> {
    let tf = match file {
        Some(f) => f,
        None => find_tasks_file().context("tasks.json not found")?,
    };
    let data = tasks::load_tasks(&tf).map_err(|e| anyhow::anyhow!("{e}"))?;
    let task = data.tasks.iter().find(|t| t["id"].as_str() == Some(task_id))
        .ok_or_else(|| anyhow::anyhow!("task {task_id} not found"))?;

    let report = brana_core::lint::lint_task(task, &data.tasks);

    if json_out {
        println!("{}", serde_json::to_string(&report).unwrap());
    } else if report.ready {
        println!("{task_id} ready — all {} checks pass", report.checks.len());
    } else {
        println!("{task_id} not ready");
        for c in report.checks.iter().filter(|c| !c.pass) {
            println!("  ✗ {}: {}", c.name, c.reason);
        }
    }
    if !json_out {
        for w in &report.warnings {
            eprintln!("  ⚠ {w}");
        }
    }
    Ok(report.ready)
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
    let _lock = tasks::lock_tasks(&tf).map_err(|e| anyhow::anyhow!("{e}"))?; // t-2166: serialize RMW
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
    let _lock = tasks::lock_tasks(&tf).map_err(|e| anyhow::anyhow!("{e}"))?; // t-2166: serialize RMW
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
    let _lock = tasks::lock_tasks(&tf).map_err(|e| anyhow::anyhow!("{e}"))?; // t-2166: serialize RMW
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

// ── triage-stale command ──────────────────────────────────────────────────

pub fn cmd_triage_stale(
    dry_run: bool,
    batch_size: usize,
    yes: bool,
    git_dir: Option<PathBuf>,
    file: Option<PathBuf>,
) -> anyhow::Result<()> {
    // 1. Get git log
    let mut cmd = std::process::Command::new("git");
    if let Some(ref dir) = git_dir {
        cmd.arg("-C").arg(dir);
    }
    let output = cmd
        .args(["log", "--all", "--oneline"])
        .output()
        .context("failed to run git log")?;
    let log = String::from_utf8_lossy(&output.stdout);

    // 2. Extract shipped task IDs
    let shipped_ids = extract_task_ids_from_git_log(&log);
    if shipped_ids.is_empty() {
        println!("No shipped task IDs found in git log.");
        return Ok(());
    }

    // 3. Load pending tasks
    let tf = match file {
        Some(f) => f,
        None => find_tasks_file().context("tasks.json not found")?,
    };
    // NOTE (t-2166): deliberately NOT locked here. cmd_triage_stale runs an
    // interactive prompt loop (read_line) with incremental saves; holding the
    // flock across human think-time would block every other session. Needs a
    // two-phase redesign (collect approvals unlocked → apply under a short
    // lock) — deferred to the sync/run/triage follow-up task.
    let mut data = tasks::load_raw(&tf).map_err(|e| anyhow::anyhow!("{e}"))?;

    // Collect display info and matched IDs before taking any mutable borrow.
    // Each entry: (id, subject, work_type)
    let matched: Vec<(String, String, String)> = {
        let all_tasks: Vec<&serde_json::Value> = data["tasks"]
            .as_array()
            .map(|a| a.iter().collect())
            .unwrap_or_default();
        let pending: Vec<&serde_json::Value> = all_tasks
            .iter()
            .filter(|t| t["status"].as_str() == Some("pending"))
            .copied()
            .collect();
        find_shipped_pending(&pending, &shipped_ids)
            .into_iter()
            .map(|t| (
                t["id"].as_str().unwrap_or("").to_string(),
                t["subject"].as_str().unwrap_or("(no subject)").to_string(),
                t["work_type"].as_str().unwrap_or("?").to_string(),
            ))
            .collect()
    };

    if matched.is_empty() {
        println!("No pending tasks found with shipped commits.");
        return Ok(());
    }

    println!("\n{} pending tasks have commits on main:\n", matched.len());

    // 5. Present in batches
    let today = chrono::Local::now().format("%Y-%m-%d").to_string();
    let mut closed = 0usize;
    let stdin = io::stdin();
    let mut stdout = io::stdout();
    let total = matched.len();

    for chunk in matched.chunks(batch_size) {
        for (id, subj, work_type) in chunk {
            println!("  [{work_type}] {id} — {subj}");
        }
        println!();

        if dry_run {
            println!("  (dry-run: would close {} tasks)", chunk.len());
            continue;
        }

        let answer = if yes {
            "y".to_string()
        } else {
            print!("  Close these {} tasks? [y/n/q]: ", chunk.len());
            stdout.flush()?;
            let mut line = String::new();
            stdin.lock().read_line(&mut line)?;
            line.trim().to_lowercase()
        };

        match answer.as_str() {
            "y" | "yes" => {
                for (id, _, _) in chunk {
                    if !id.is_empty() {
                        if let Some(task) = data["tasks"]
                            .as_array_mut()
                            .and_then(|arr| arr.iter_mut().find(|x| x["id"].as_str() == Some(id.as_str())))
                        {
                            task["status"] = serde_json::json!("completed");
                            task["completed"] = serde_json::json!(today);
                        }
                        closed += 1;
                    }
                }
                tasks::save_tasks(&tf, &data).map_err(|e| anyhow::anyhow!("{e}"))?;
                println!("  ✓ closed {closed} tasks so far\n");
            }
            "q" | "quit" => {
                println!("  Stopped. {closed} tasks closed.");
                return Ok(());
            }
            _ => {
                println!("  Skipped.\n");
            }
        }
    }

    if dry_run {
        println!("dry-run: would close {} tasks total", total);
    } else {
        println!("Done. {closed} tasks closed.");
    }
    Ok(())
}

// ── triage-stale helpers ─────────────────────────────────────────────────

/// Parse `git log --all --oneline` output and return unique task IDs that
/// appear as the **scope** of a conventional commit or as the branch name in a
/// merge commit.
///
/// Matches:
/// - `<hash> <type>(t-NNN): …`  — scope IS the task ID
/// - `<hash> merge(feat/t-NNN…): …`  — merge of a task branch
///
/// Does NOT match:
/// - Casual mentions like `docs(research): … (t-NNN)` (scope ≠ task ID)
/// - Any other position in the commit subject
pub fn extract_task_ids_from_git_log(log: &str) -> Vec<String> {
    let mut seen = std::collections::HashSet::new();
    let mut ids = Vec::new();
    for line in log.lines() {
        // Strip leading 7-char hash + space: "<hash> <subject>"
        let subject = line.splitn(2, ' ').nth(1).unwrap_or(line);
        // Pattern 1: conventional commit with task ID as scope — \w+(t-NNN):
        // e.g. "feat(t-1032):", "test(t-84):", "merge(t-5):"
        if let Some(rest) = subject.find("(t-").map(|i| &subject[i+1..]) {
            if let Some(end) = rest.find(')') {
                let candidate = &rest[..end]; // "t-NNN"
                if candidate.starts_with("t-") && candidate[2..].chars().all(|c| c.is_ascii_digit()) {
                    let before = &subject[..subject.find("(t-").unwrap()];
                    // Scope must directly follow a commit type word (no '/')
                    if !before.contains('/') && before.chars().all(|c| c.is_alphanumeric() || c == ' ' || c == '-') {
                        if seen.insert(candidate.to_string()) {
                            ids.push(candidate.to_string());
                        }
                        continue;
                    }
                }
            }
        }
        // Pattern 2: merge commit of a task branch — merge(feat/t-NNN...) or merge(fix/t-NNN...)
        // e.g. "merge(feat/t-1032):", "merge(fix/t-999-slug):"
        if subject.starts_with("merge(") {
            let inner_start = "merge(".len();
            if let Some(close) = subject.find(')') {
                let inner = &subject[inner_start..close]; // "feat/t-1032" or "feat/t-1032-slug"
                if let Some(t_pos) = inner.find("/t-") {
                    let after_t = &inner[t_pos + 1..]; // "t-1032" or "t-1032-slug"
                    // find '-' after the "t-" prefix (skip first 2 chars)
                    let id_end = after_t[2..].find('-').map(|i| i + 2).unwrap_or(after_t.len());
                    // Only take digits after "t-"
                    let digits = &after_t[2..id_end];
                    if !digits.is_empty() && digits.chars().all(|c| c.is_ascii_digit()) {
                        let task_id = format!("t-{digits}");
                        if seen.insert(task_id.clone()) {
                            ids.push(task_id);
                        }
                    }
                }
            }
        }
    }
    ids
}

/// Cross-reference: return tasks (from `pending`) whose ID appears in `shipped_ids`.
pub fn find_shipped_pending<'a>(
    pending: &[&'a serde_json::Value],
    shipped_ids: &[String],
) -> Vec<&'a serde_json::Value> {
    let shipped: std::collections::HashSet<&str> = shipped_ids.iter().map(|s| s.as_str()).collect();
    pending.iter()
        .filter(|t| t["id"].as_str().map(|id| shipped.contains(id)).unwrap_or(false))
        .copied()
        .collect()
}

// ── initiatives + epics ─────────────────────────────────────────────────

#[derive(Debug)]
pub struct InitiativeStat {
    pub id: String,
    pub slug: String,
    pub subject: String,
    pub priority: String,
    pub status: String,
    pub total: usize,
    pub p1: usize,
    pub p2: usize,
    pub p3: usize,
    pub blocked: usize,
    pub done: usize,
}

#[derive(Debug)]
pub struct EpicStat {
    pub slug: String,
    pub total: usize,
    pub p1: usize,
    pub p2: usize,
    pub blocked: usize,
    pub done: usize,
}

pub fn collect_initiative_stats(tasks: &[serde_json::Value]) -> Vec<InitiativeStat> {
    let initiative_tasks: Vec<&serde_json::Value> = tasks.iter()
        .filter(|t| t["type"].as_str() == Some("initiative"))
        .collect();

    let mut stats = Vec::new();
    for ini in &initiative_tasks {
        let slug = match ini["epic"].as_str() { Some(s) => s, None => continue };
        let id = ini["id"].as_str().unwrap_or("?").to_string();
        let subject = ini["subject"].as_str().unwrap_or("").to_string();
        let priority = ini["priority"].as_str().unwrap_or("—").to_string();
        let status = ini["status"].as_str().unwrap_or("pending").to_string();

        let children: Vec<&serde_json::Value> = tasks.iter()
            .filter(|t| t["type"].as_str() != Some("initiative"))
            .filter(|t| t["epic"].as_str() == Some(slug))
            .collect();

        let total = children.len();
        let p1 = children.iter().filter(|t| t["priority"].as_str() == Some("P1")).count();
        let p2 = children.iter().filter(|t| t["priority"].as_str() == Some("P2")).count();
        let p3 = children.iter().filter(|t| t["priority"].as_str() == Some("P3")).count();
        let blocked = children.iter().filter(|t| {
            t["blocked_by"].as_array().map_or(false, |b| !b.is_empty())
                && t["status"].as_str() != Some("completed")
        }).count();
        let done = children.iter().filter(|t| t["status"].as_str() == Some("completed")).count();

        stats.push(InitiativeStat { id, slug: slug.to_string(), subject, priority, status, total, p1, p2, p3, blocked, done });
    }
    stats.sort_by(|a, b| a.slug.cmp(&b.slug));
    stats
}

pub fn collect_epic_stats(tasks: &[serde_json::Value]) -> Vec<EpicStat> {
    let mut slugs: Vec<&str> = tasks.iter()
        .filter(|t| t["type"].as_str() != Some("initiative"))
        .filter_map(|t| t["epic"].as_str())
        .filter(|s| !s.is_empty())
        .collect::<std::collections::HashSet<_>>()
        .into_iter()
        .collect();
    slugs.sort();

    slugs.iter().map(|slug| {
        let members: Vec<&serde_json::Value> = tasks.iter()
            .filter(|t| t["type"].as_str() != Some("initiative"))
            .filter(|t| t["epic"].as_str() == Some(slug))
            .collect();
        let total = members.len();
        let p1 = members.iter().filter(|t| t["priority"].as_str() == Some("P1")).count();
        let p2 = members.iter().filter(|t| t["priority"].as_str() == Some("P2")).count();
        let blocked = members.iter().filter(|t| {
            t["blocked_by"].as_array().map_or(false, |b| !b.is_empty())
                && t["status"].as_str() != Some("completed")
        }).count();
        let done = members.iter().filter(|t| t["status"].as_str() == Some("completed")).count();
        EpicStat { slug: slug.to_string(), total, p1, p2, blocked, done }
    }).collect()
}

pub fn cmd_initiatives(theme: &themes::Theme, json_out: bool) -> anyhow::Result<()> {
    let tf = find_tasks_file().context("tasks.json not found")?;
    let data = tasks::load_tasks(&tf).map_err(|e| anyhow::anyhow!("{e}"))?;
    let stats = collect_initiative_stats(&data.tasks);

    if json_out {
        let out: Vec<serde_json::Value> = stats.iter().map(|s| serde_json::json!({
            "id": s.id, "slug": s.slug, "subject": s.subject,
            "priority": s.priority, "status": s.status,
            "total": s.total, "p1": s.p1, "p2": s.p2, "p3": s.p3,
            "blocked": s.blocked, "done": s.done,
        })).collect();
        println!("{}", serde_json::to_string(&out).unwrap());
        return Ok(());
    }

    if stats.is_empty() {
        println!("\n  No initiatives found (no tasks with type=initiative).\n");
        return Ok(());
    }

    println!("\n{}Initiatives{}", themes::ansi(theme.color("header")), themes::RESET);
    for s in &stats {
        let pct = if s.total > 0 { s.done * 100 / s.total } else { 0 };
        let bar = theme.bar(s.done, s.total, 10);
        let flags = format!("P1:{} P2:{} P3:{} blocked:{}", s.p1, s.p2, s.p3, s.blocked);
        println!(
            "{}  {} {}  {} {}  {}%  {}{}\n    {}  {}",
            themes::ansi(theme.color("header")),
            s.id, s.slug,
            themes::RESET,
            s.subject,
            pct,
            bar,
            themes::RESET,
            flags,
            format!("{} tasks done/{}", s.done, s.total),
        );
    }
    println!();
    Ok(())
}

pub fn cmd_epics(theme: &themes::Theme, json_out: bool) -> anyhow::Result<()> {
    let tf = find_tasks_file().context("tasks.json not found")?;
    let data = tasks::load_tasks(&tf).map_err(|e| anyhow::anyhow!("{e}"))?;
    let stats = collect_epic_stats(&data.tasks);

    if json_out {
        let out: Vec<serde_json::Value> = stats.iter().map(|s| serde_json::json!({
            "slug": s.slug, "total": s.total, "p1": s.p1, "p2": s.p2,
            "blocked": s.blocked, "done": s.done,
        })).collect();
        println!("{}", serde_json::to_string(&out).unwrap());
        return Ok(());
    }

    if stats.is_empty() {
        println!("\n  No epics found.\n");
        return Ok(());
    }

    println!("\n{}Epics{}", themes::ansi(theme.color("header")), themes::RESET);
    for s in &stats {
        let pct = if s.total > 0 { s.done * 100 / s.total } else { 0 };
        let bar = theme.bar(s.done, s.total, 10);
        println!(
            "{}  {:<28}{}  {} {pct:>3}%  P1:{} P2:{} blocked:{}",
            themes::ansi(theme.color("header")),
            s.slug,
            themes::RESET,
            bar,
            s.p1, s.p2, s.blocked,
        );
    }
    println!();
    Ok(())
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

    // ── extract_task_ids_from_git_log ────────────────────────────────

    #[test]
    fn test_extract_scope_is_task_id() {
        let log = "941c44d feat(t-1032): enforce TDD gate in /brana:backlog plan\n";
        let ids = extract_task_ids_from_git_log(log);
        assert_eq!(ids, vec!["t-1032"]);
    }

    #[test]
    fn test_extract_merge_commit_branch_pattern() {
        let log = "9e9df44 merge(feat/t-1032): enforce TDD gate\n";
        let ids = extract_task_ids_from_git_log(log);
        assert_eq!(ids, vec!["t-1032"]);
    }

    #[test]
    fn test_extract_fix_branch_merge() {
        let log = "abc1234 merge(fix/t-999-some-slug): fix the thing\n";
        let ids = extract_task_ids_from_git_log(log);
        assert_eq!(ids, vec!["t-999"]);
    }

    #[test]
    fn test_extract_ignores_casual_mention_in_message() {
        // scope is 'research', t-1229 is a trailing mention only
        let log = "bb89d37 docs(research): Batch API integration design (t-1229)\n";
        let ids = extract_task_ids_from_git_log(log);
        assert!(ids.is_empty(), "casual mention should not match, got: {ids:?}");
    }

    #[test]
    fn test_extract_ignores_no_task_id() {
        let log = "7e8822c chore(state): sync tasks.json — close session Wave 4\n";
        let ids = extract_task_ids_from_git_log(log);
        assert!(ids.is_empty());
    }

    #[test]
    fn test_extract_deduplicates() {
        let log = "aaa feat(t-100): first\nbbb merge(feat/t-100): first merge\n";
        let ids = extract_task_ids_from_git_log(log);
        assert_eq!(ids, vec!["t-100"]);
    }

    #[test]
    fn test_extract_multiple_tasks() {
        let log = "aaa feat(t-1): thing one\nbbb merge(fix/t-2-slug): thing two\nccc test(t-3): tests\n";
        let mut ids = extract_task_ids_from_git_log(log);
        ids.sort();
        assert_eq!(ids, vec!["t-1", "t-2", "t-3"]);
    }

    #[test]
    fn test_extract_refactor_type() {
        let log = "abc refactor(t-42): restructure module\n";
        let ids = extract_task_ids_from_git_log(log);
        assert_eq!(ids, vec!["t-42"]);
    }

    // ── find_shipped_pending ─────────────────────────────────────────

    #[test]
    fn test_find_shipped_pending_returns_matching() {
        let t1 = json!({"id": "t-1", "status": "pending"});
        let t2 = json!({"id": "t-2", "status": "pending"});
        let t3 = json!({"id": "t-3", "status": "completed"});
        let pending = vec![&t1, &t2, &t3];
        let shipped = vec!["t-1".to_string(), "t-3".to_string()];
        let result = find_shipped_pending(&pending, &shipped);
        assert_eq!(result.len(), 2);
        assert!(result.iter().any(|t| t["id"] == "t-1"));
        assert!(result.iter().any(|t| t["id"] == "t-3"));
    }

    #[test]
    fn test_find_shipped_pending_no_matches() {
        let t1 = json!({"id": "t-99", "status": "pending"});
        let pending = vec![&t1];
        let shipped = vec!["t-1".to_string()];
        let result = find_shipped_pending(&pending, &shipped);
        assert!(result.is_empty());
    }

    #[test]
    fn test_find_shipped_pending_empty_inputs() {
        let result = find_shipped_pending(&[], &[]);
        assert!(result.is_empty());
    }

    // ── collect_initiative_stats ─────────────────────────────────────

    fn initiative_mock() -> Vec<serde_json::Value> {
        vec![
            json!({"id":"in-001","type":"initiative","subject":"Backlog UI","epic":"backlog-ui","status":"in_progress","priority":"P1","blocked_by":[]}),
            json!({"id":"t-10","type":"task","subject":"Task A","epic":"backlog-ui","status":"completed","priority":"P1","blocked_by":[]}),
            json!({"id":"t-11","type":"task","subject":"Task B","epic":"backlog-ui","status":"pending","priority":"P2","blocked_by":["t-10"]}),
            json!({"id":"t-12","type":"task","subject":"Task C","epic":"backlog-ui","status":"pending","priority":"P3","blocked_by":[]}),
            json!({"id":"in-002","type":"initiative","subject":"Memory Arch","epic":"memory-arch","status":"pending","priority":"P2","blocked_by":[]}),
            json!({"id":"t-20","type":"task","subject":"Task M","epic":"memory-arch","status":"pending","priority":"P1","blocked_by":[]}),
        ]
    }

    #[test]
    fn initiatives_groups_by_epic_slug() {
        let tasks = initiative_mock();
        let stats = collect_initiative_stats(&tasks);
        assert_eq!(stats.len(), 2);
        let bu = stats.iter().find(|s| s.slug == "backlog-ui").unwrap();
        assert_eq!(bu.total, 3);
        assert_eq!(bu.done, 1);
        assert_eq!(bu.p1, 1);
        assert_eq!(bu.p2, 1);
        assert_eq!(bu.p3, 1);
        assert_eq!(bu.blocked, 1); // t-11 has non-empty blocked_by and is not completed
    }

    #[test]
    fn initiatives_excludes_initiative_tasks_from_children() {
        let tasks = initiative_mock();
        let stats = collect_initiative_stats(&tasks);
        let ma = stats.iter().find(|s| s.slug == "memory-arch").unwrap();
        assert_eq!(ma.total, 1); // only t-20, not in-002 itself
    }

    #[test]
    fn initiatives_empty_when_no_initiative_type() {
        let tasks = vec![
            json!({"id":"t-1","type":"task","epic":"foo","status":"pending","priority":"P2","blocked_by":[]}),
        ];
        let stats = collect_initiative_stats(&tasks);
        assert!(stats.is_empty());
    }

    // ── collect_epic_stats ───────────────────────────────────────────

    #[test]
    fn epics_groups_non_initiative_tasks_by_slug() {
        let tasks = initiative_mock();
        let stats = collect_epic_stats(&tasks);
        // backlog-ui: 3 tasks, memory-arch: 1 task
        assert_eq!(stats.len(), 2);
        let bu = stats.iter().find(|s| s.slug == "backlog-ui").unwrap();
        assert_eq!(bu.total, 3);
        assert_eq!(bu.done, 1);
    }

    #[test]
    fn epics_sorted_alphabetically() {
        let tasks = initiative_mock();
        let stats = collect_epic_stats(&tasks);
        let slugs: Vec<&str> = stats.iter().map(|s| s.slug.as_str()).collect();
        let mut sorted = slugs.clone();
        sorted.sort();
        assert_eq!(slugs, sorted);
    }

    #[test]
    fn epics_skips_tasks_without_epic() {
        let tasks = vec![
            json!({"id":"t-1","type":"task","epic":null,"status":"pending","priority":"P2","blocked_by":[]}),
            json!({"id":"t-2","type":"task","epic":"foo","status":"pending","priority":"P2","blocked_by":[]}),
        ];
        let stats = collect_epic_stats(&tasks);
        assert_eq!(stats.len(), 1);
        assert_eq!(stats[0].slug, "foo");
    }

    // ── t-2279: select_next (next --epic) + sort_query (query --sort) ──

    // Mock exercising the cross-epic blocked_by trap: a task in epic
    // "env-hardening" blocked only by a *completed* task that lives in
    // another epic must count as ready. Resolving blockers against an
    // epic-scoped subset (the ad-hoc-Python bug) would mislabel it blocked.
    fn next_mock() -> Vec<serde_json::Value> {
        vec![
            json!({"id":"t-1","type":"task","subject":"cross-epic completed blocker","epic":"other","status":"completed","priority":"P1","blocked_by":[]}),
            json!({"id":"t-2","type":"task","subject":"ready — blocked only by completed t-1","epic":"env-hardening","status":"pending","priority":"P1","blocked_by":["t-1"]}),
            json!({"id":"t-3","type":"task","subject":"blocked — t-9 still open","epic":"env-hardening","status":"pending","priority":"P1","blocked_by":["t-9"]}),
            json!({"id":"t-9","type":"task","subject":"open blocker","epic":"other","status":"pending","priority":"P2","blocked_by":[]}),
            json!({"id":"t-4","type":"task","subject":"ready — other epic","epic":"other","status":"pending","priority":"P1","blocked_by":[]}),
        ]
    }

    #[test]
    fn select_next_scopes_to_epic_and_resolves_cross_epic_blockers() {
        let tasks = next_mock();
        let got = select_next(&tasks, None, None, None, None, None, None, Some("env-hardening"), 100);
        let ids: Vec<&str> = got.iter().map(|t| t["id"].as_str().unwrap()).collect();
        // t-2 ready (blocker completed, other epic); t-3 blocked (t-9 open); t-4 excluded (other epic)
        assert_eq!(ids, vec!["t-2"]);
    }

    #[test]
    fn select_next_without_epic_spans_all_epics() {
        let tasks = next_mock();
        let got = select_next(&tasks, None, None, None, None, None, None, None, 100);
        let ids: std::collections::HashSet<&str> =
            got.iter().map(|t| t["id"].as_str().unwrap()).collect();
        assert!(ids.contains("t-2"));  // ready
        assert!(ids.contains("t-4"));  // ready, other epic
        assert!(!ids.contains("t-3")); // blocked
        assert!(!ids.contains("t-1")); // completed
    }

    #[test]
    fn sort_query_by_priority_orders_p0_first() {
        let tasks = vec![
            json!({"id":"a","priority":"P2","status":"pending","blocked_by":[]}),
            json!({"id":"b","priority":"P0","status":"pending","blocked_by":[]}),
            json!({"id":"c","priority":"P1","status":"pending","blocked_by":[]}),
        ];
        let mut refs: Vec<&serde_json::Value> = tasks.iter().collect();
        sort_query(&mut refs, &tasks, "priority");
        let ids: Vec<&str> = refs.iter().map(|t| t["id"].as_str().unwrap()).collect();
        assert_eq!(ids, vec!["b", "c", "a"]);
    }

    #[test]
    fn sort_query_by_status_groups_lifecycle_then_priority() {
        let tasks = vec![
            json!({"id":"done","status":"completed","priority":"P0","blocked_by":[]}),
            json!({"id":"active","status":"in_progress","priority":"P3","blocked_by":[]}),
            json!({"id":"ready","status":"pending","priority":"P2","blocked_by":[]}),
            json!({"id":"blocked","status":"pending","priority":"P1","blocked_by":["missing"]}),
        ];
        let mut refs: Vec<&serde_json::Value> = tasks.iter().collect();
        sort_query(&mut refs, &tasks, "status");
        let ids: Vec<&str> = refs.iter().map(|t| t["id"].as_str().unwrap()).collect();
        // active → ready(pending) → blocked → done
        assert_eq!(ids, vec!["active", "ready", "blocked", "done"]);
    }

    // ── t-1544: priority default P3 at write time ────────────────────

    fn empty_tasks_file() -> tempfile::NamedTempFile {
        use std::io::Write;
        let mut f = tempfile::NamedTempFile::new().unwrap();
        write!(f, r#"{{"version":1,"project":"test","tasks":[]}}"#).unwrap();
        f.flush().unwrap();
        f
    }

    fn read_first_task(f: &tempfile::NamedTempFile) -> serde_json::Value {
        let data: serde_json::Value =
            serde_json::from_str(&std::fs::read_to_string(f.path()).unwrap()).unwrap();
        data["tasks"][0].clone()
    }

    #[test]
    fn cmd_add_defaults_priority_to_p3_when_absent() {
        let f = empty_tasks_file();
        cmd_add(
            Some(r#"{"subject":"no priority in json"}"#.into()),
            None, None, None, None, None, None, None, None,
            None, Some(f.path().to_path_buf()), None, None, None, vec![],
        ).unwrap();
        let task = read_first_task(&f);
        assert_eq!(task["priority"].as_str(), Some("P3"),
            "absent priority should default to P3, got: {}", task["priority"]);
    }

    #[test]
    fn cmd_add_defaults_priority_to_p3_when_null() {
        let f = empty_tasks_file();
        cmd_add(
            Some(r#"{"subject":"explicit null priority","priority":null}"#.into()),
            None, None, None, None, None, None, None, None,
            None, Some(f.path().to_path_buf()), None, None, None, vec![],
        ).unwrap();
        let task = read_first_task(&f);
        assert_eq!(task["priority"].as_str(), Some("P3"),
            "explicit null priority should default to P3, got: {}", task["priority"]);
    }

    #[test]
    fn cmd_add_keeps_explicit_priority() {
        let f = empty_tasks_file();
        cmd_add(
            Some(r#"{"subject":"explicit priority","priority":"P1"}"#.into()),
            None, None, None, None, None, None, None, None,
            None, Some(f.path().to_path_buf()), None, None, None, vec![],
        ).unwrap();
        let task = read_first_task(&f);
        assert_eq!(task["priority"].as_str(), Some("P1"),
            "explicit priority should be preserved, got: {}", task["priority"]);
    }

    #[test]
    fn cmd_add_keeps_p0_priority() {
        let f = empty_tasks_file();
        cmd_add(
            Some(r#"{"subject":"urgent","priority":"P0"}"#.into()),
            None, None, None, None, None, None, None, None,
            None, Some(f.path().to_path_buf()), None, None, None, vec![],
        ).unwrap();
        let task = read_first_task(&f);
        assert_eq!(task["priority"].as_str(), Some("P0"),
            "P0 priority should be preserved, got: {}", task["priority"]);
    }

    // ── t-2283: ac_state forward-only slice (CLI paths) ──────────────────

    fn tasks_file_with(tasks_json: &str) -> tempfile::NamedTempFile {
        use std::io::Write;
        let mut f = tempfile::NamedTempFile::new().unwrap();
        write!(f, r#"{{"version":1,"project":"test","tasks":{tasks_json}}}"#).unwrap();
        f.flush().unwrap();
        f
    }

    #[test]
    fn cmd_add_stamps_ac_state_none() {
        // AC#3: new tasks are stamped ac_state:none.
        let f = empty_tasks_file();
        cmd_add(
            Some(r#"{"subject":"new v3 task"}"#.into()),
            None, None, None, None, None, None, None, None,
            None, Some(f.path().to_path_buf()), None, None, None, vec![],
        ).unwrap();
        let task = read_first_task(&f);
        assert_eq!(task["ac_state"].as_str(), Some("none"),
            "new tasks must be stamped ac_state:none, got: {}", task["ac_state"]);
    }

    #[test]
    fn cmd_add_leaves_existing_legacy_task_keyless() {
        // AC#3 tail: adding a new task must not touch a pre-existing legacy task.
        let f = tasks_file_with(
            r#"[{"id":"t-1","subject":"legacy","status":"pending","type":"task","tags":[],"blocked_by":[]}]"#,
        );
        cmd_add(
            Some(r#"{"subject":"new one"}"#.into()),
            None, None, None, None, None, None, None, None,
            None, Some(f.path().to_path_buf()), None, None, None, vec![],
        ).unwrap();
        let data: serde_json::Value =
            serde_json::from_str(&std::fs::read_to_string(f.path()).unwrap()).unwrap();
        let arr = data["tasks"].as_array().unwrap();
        let legacy = arr.iter().find(|t| t["id"] == "t-1").unwrap();
        assert!(legacy.get("ac_state").is_none(), "existing legacy task must stay key-less");
        let new = arr.iter().find(|t| t["subject"] == "new one").unwrap();
        assert_eq!(new["ac_state"].as_str(), Some("none"));
    }

    // ── t-2310 (ADR-065): level/epic write-path sealing ──────────────────

    #[test]
    fn cmd_add_shorthand_epic_flag_is_noop() {
        let f = empty_tasks_file();
        cmd_add(
            None, Some("shorthand with epic".into()), None, None, None, None,
            None, None, None, None, Some(f.path().to_path_buf()), None,
            Some("cc-alignment".into()), None, vec![],
        ).unwrap();
        let task = read_first_task(&f);
        assert!(task.get("epic").is_none() || task["epic"].is_null(),
            "--epic must be a no-op, got: {}", task["epic"]);
    }

    #[test]
    fn cmd_add_json_payload_rejects_level_key() {
        let f = empty_tasks_file();
        let err = cmd_add(
            Some(r#"{"subject":"has level","level":"phase"}"#.into()),
            None, None, None, None, None, None, None, None,
            None, Some(f.path().to_path_buf()), None, None, None, vec![],
        ).unwrap_err();
        assert!(err.to_string().contains("level"), "error must name the field: {err}");
        let data: serde_json::Value =
            serde_json::from_str(&std::fs::read_to_string(f.path()).unwrap()).unwrap();
        assert_eq!(data["tasks"].as_array().unwrap().len(), 0,
            "rejected add must not persist a task");
    }

    #[test]
    fn cmd_add_json_payload_rejects_epic_key() {
        let f = empty_tasks_file();
        let err = cmd_add(
            Some(r#"{"subject":"has epic","epic":"cc-alignment"}"#.into()),
            None, None, None, None, None, None, None, None,
            None, Some(f.path().to_path_buf()), None, None, None, vec![],
        ).unwrap_err();
        assert!(err.to_string().contains("epic"), "error must name the field: {err}");
        let data: serde_json::Value =
            serde_json::from_str(&std::fs::read_to_string(f.path()).unwrap()).unwrap();
        assert_eq!(data["tasks"].as_array().unwrap().len(), 0,
            "rejected add must not persist a task");
    }

    #[test]
    fn cmd_add_parent_does_not_inherit_epic() {
        // Pre-t-2310: inherit_initiative() copied a parent's flat epic onto new
        // children. ADR-065 retires that — epic becomes a real hierarchy node
        // with real children, not something to flat-copy.
        let f = tasks_file_with(
            r#"[{"id":"ph-1","subject":"parent phase","status":"pending","type":"phase","tags":[],"blocked_by":[],"epic":"cc-alignment"}]"#,
        );
        cmd_add(
            Some(r#"{"subject":"child of ph-1","parent":"ph-1"}"#.into()),
            None, None, None, None, None, None, None, None,
            None, Some(f.path().to_path_buf()), None, None, None, vec![],
        ).unwrap();
        let data: serde_json::Value =
            serde_json::from_str(&std::fs::read_to_string(f.path()).unwrap()).unwrap();
        let arr = data["tasks"].as_array().unwrap();
        let child = arr.iter().find(|t| t["subject"] == "child of ph-1").unwrap();
        assert!(child.get("epic").is_none() || child["epic"].is_null(),
            "epic must not be inherited from parent, got: {}", child["epic"]);
    }

    #[test]
    fn cmd_set_ac_state_opt_in_adds_key_to_legacy() {
        // AC#5 (CLI path): setting ac_state on a legacy task adds the key.
        let f = tasks_file_with(
            r#"[{"id":"t-1","subject":"legacy","status":"pending","type":"task","tags":[],"blocked_by":[]}]"#,
        );
        cmd_set("t-1", "ac_state", "none", false, Some(f.path().to_path_buf())).unwrap();
        let task = read_first_task(&f);
        assert_eq!(task["ac_state"].as_str(), Some("none"));
    }

    #[test]
    fn cmd_set_unrelated_field_preserves_ac_state_cli_path() {
        // AC#2 (CLI path): an unrelated `set` must not clobber ac_state.
        let f = tasks_file_with(
            r#"[{"id":"t-1","subject":"s","status":"pending","type":"task","tags":[],"blocked_by":[],"ac_state":"proposed"}]"#,
        );
        cmd_set("t-1", "priority", "P1", false, Some(f.path().to_path_buf())).unwrap();
        let task = read_first_task(&f);
        assert_eq!(task["ac_state"].as_str(), Some("proposed"), "CLI set clobbered ac_state");
    }
}

/// `brana backlog migrate-epic` — rename `initiative` field → `epic` across tasks.json (t-1614).
pub fn cmd_backlog_migrate_epic(dry_run: bool, file: Option<PathBuf>) -> anyhow::Result<()> {
    let tf = match file {
        Some(f) => f,
        None => find_tasks_file().context("tasks.json not found")?,
    };
    let _lock = tasks::lock_tasks(&tf).map_err(|e| anyhow::anyhow!("{e}"))?; // t-2166: serialize RMW
    let mut val = tasks::load_raw(&tf).map_err(|e| anyhow::anyhow!("{e}"))?;
    let task_arr = val["tasks"].as_array_mut().context("tasks is not an array")?;
    let mut migrated = 0usize;
    for task in task_arr.iter_mut() {
        if task.as_object().map_or(false, |o| o.contains_key("initiative")) {
            *task = tasks::migrate_initiative_to_epic(task.clone());
            migrated += 1;
        }
    }
    if dry_run {
        println!("{}", serde_json::json!({"dry_run": true, "would_migrate": migrated}));
        return Ok(());
    }
    tasks::save_tasks(&tf, &val).map_err(|e| anyhow::anyhow!("{e}"))?;
    println!("{}", serde_json::json!({"ok": true, "migrated": migrated, "file": tf.display().to_string()}));
    Ok(())
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

/// ac-propose loop (t-2288). Without `apply`: emit the drain queue as JSON packets
/// (id, subject, description, context) for an AC generator. With `apply`: read
/// proposals and persist `ac_state:proposed` + `proposed_acceptance_criteria` for
/// current candidates only — the binary stays LLM-free; content comes from the
/// caller (agy/Claude at the agent layer).
pub fn cmd_ac_propose(
    file: Option<PathBuf>,
    apply: Option<PathBuf>,
    dry_run: bool,
) -> anyhow::Result<()> {
    let tf = match file {
        Some(f) => f,
        None => find_tasks_file().context("tasks.json not found")?,
    };

    match apply {
        // ── List mode: emit candidate packets (the drain). Read-only. ──
        None => {
            let val = tasks::load_raw(&tf).map_err(|e| anyhow::anyhow!(e))?;
            let all = val["tasks"].as_array().cloned().unwrap_or_default();
            let packets: Vec<serde_json::Value> = tasks::ac_propose_candidates(&all)
                .iter()
                .map(|t| {
                    serde_json::json!({
                        "id": t["id"],
                        "subject": t["subject"],
                        "description": t["description"],
                        "context": t["context"],
                    })
                })
                .collect();
            println!("{}", serde_json::to_string_pretty(&packets)?);
        }
        // ── Apply mode: read proposals, persist scoped mutation. ──
        Some(src) => {
            let raw = if src.as_os_str() == "-" {
                io::read_to_string(io::stdin())?
            } else {
                std::fs::read_to_string(&src)
                    .with_context(|| format!("reading proposals from {}", src.display()))?
            };
            let parsed: serde_json::Value =
                serde_json::from_str(raw.trim()).context("proposals must be valid JSON")?;
            let entries = parsed
                .as_array()
                .context("proposals must be a JSON array of {id, proposed_acceptance_criteria}")?;

            let mut proposals: std::collections::HashMap<String, Vec<String>> =
                std::collections::HashMap::new();
            for e in entries {
                let id = e["id"]
                    .as_str()
                    .context("each proposal needs a string `id`")?
                    .to_string();
                let crit: Vec<String> = e["proposed_acceptance_criteria"]
                    .as_array()
                    .context("each proposal needs `proposed_acceptance_criteria` (array of strings)")?
                    .iter()
                    .filter_map(|c| c.as_str().map(str::to_string))
                    .collect();
                if crit.is_empty() {
                    anyhow::bail!("proposal for {id} has no non-empty criteria");
                }
                // A duplicate id would silently drop all but the last entry — surface it.
                if proposals.contains_key(&id) {
                    anyhow::bail!("duplicate id {id:?} in proposals — each task may appear once");
                }
                proposals.insert(id, crit);
            }

            match tasks::perform_ac_propose(&tf, &proposals, dry_run) {
                Ok(ids) => {
                    let action = if dry_run { "would propose" } else { "proposed" };
                    let json_ids = serde_json::to_string(&ids).unwrap();
                    println!("{{\"ac_propose\":{json_ids},\"action\":\"{action}\"}}");
                }
                Err(e) => anyhow::bail!("ac-propose failed: {e}"),
            }
        }
    }
    Ok(())
}
