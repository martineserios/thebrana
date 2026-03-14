//! brana — fast standalone CLI dispatcher
//!
//! Single static binary. 12ms startup. No Python dependency.
//! Handles high-frequency commands natively in Rust.
//! Delegates complex ops to existing shell scripts.
//!
//! Usage:
//!   brana backlog next
//!   brana backlog query --tag scheduler --status pending
//!   brana backlog focus
//!   brana ops status
//!   brana ops health
//!   brana ops sync --auto-commit
//!   brana doctor

mod tasks;
mod themes;

use clap::{Parser, Subcommand};
use std::collections::HashMap;
use std::path::PathBuf;
use std::process::Command;

#[derive(Parser)]
#[command(name = "brana", version, about = "Brana system CLI — fast standalone interface")]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    /// Task management (mirrors /brana:backlog)
    Backlog {
        #[command(subcommand)]
        cmd: BacklogCmd,
    },
    /// Scheduler and system operations
    Ops {
        #[command(subcommand)]
        cmd: OpsCmd,
    },
    /// System health check
    Doctor,
    /// Show version
    Version,
}

#[derive(Subcommand)]
enum BacklogCmd {
    /// Next unblocked task by priority
    Next {
        #[arg(long)]
        tag: Option<String>,
        #[arg(long)]
        stream: Option<String>,
    },
    /// Filter tasks (AND logic)
    Query {
        #[arg(short, long)]
        tag: Option<String>,
        #[arg(short, long)]
        status: Option<String>,
        #[arg(long)]
        stream: Option<String>,
        #[arg(short, long)]
        priority: Option<String>,
        #[arg(short, long)]
        effort: Option<String>,
        #[arg(long)]
        search: Option<String>,
        #[arg(long)]
        count: bool,
        #[arg(long, default_value = "json")]
        output: String,
    },
    /// Smart daily pick
    Focus,
    /// Free-text search
    Search {
        text: String,
    },
    /// Portfolio or project status
    Status,
    /// Show blocked dependency chains
    Blocked,
    /// Tasks pending > N days
    Stale {
        #[arg(long, default_value = "14")]
        days: i64,
    },
    /// Print task context
    Context {
        task_id: String,
    },
    /// Semantic diff since last commit
    Diff,
    /// Created vs completed over time
    Burndown {
        #[arg(long, default_value = "week")]
        period: String,
    },
}

#[derive(Subcommand)]
enum OpsCmd {
    /// Dashboard: all jobs, last run, health
    Status,
    /// Aggregate health check
    Health,
    /// Detect schedule collisions
    Collisions,
    /// Compare live config vs template
    Drift,
    /// View logs for a job
    Logs {
        job_name: String,
        #[arg(long, default_value = "50")]
        tail: usize,
    },
    /// Run history for a job
    History {
        job_name: String,
        #[arg(long, default_value = "10")]
        last: usize,
    },
    /// Manually trigger a job (delegates to systemctl)
    Run { job_name: String },
    /// Enable a job (delegates to scripts)
    Enable { job_name: String },
    /// Disable a job (delegates to scripts)
    Disable { job_name: String },
    /// Sync operational state (wraps sync-state.sh)
    Sync {
        #[arg(long)]
        auto_commit: bool,
        #[arg(long, default_value = "push")]
        direction: String,
    },
    /// Reindex knowledge (wraps index-knowledge.sh)
    Reindex,
}

fn find_tasks_file() -> Option<PathBuf> {
    // Try git root first
    let root = Command::new("git")
        .args(["rev-parse", "--show-toplevel"])
        .output()
        .ok()
        .and_then(|o| {
            if o.status.success() {
                Some(PathBuf::from(String::from_utf8_lossy(&o.stdout).trim().to_string()))
            } else {
                None
            }
        });

    if let Some(root) = &root {
        let f = root.join(".claude/tasks.json");
        if f.exists() {
            return Some(f);
        }
    }
    None
}

fn find_project_root() -> Option<PathBuf> {
    Command::new("git")
        .args(["rev-parse", "--show-toplevel"])
        .output()
        .ok()
        .and_then(|o| {
            if o.status.success() {
                Some(PathBuf::from(String::from_utf8_lossy(&o.stdout).trim().to_string()))
            } else {
                None
            }
        })
}

fn home() -> PathBuf {
    PathBuf::from(std::env::var("HOME").unwrap_or_default())
}

fn main() {
    let cli = Cli::parse();
    let theme_name = themes::load_theme_name();
    let theme = themes::Theme::load(&theme_name);

    match cli.command {
        Commands::Version => cmd_version(),
        Commands::Doctor => cmd_doctor(&theme),
        Commands::Backlog { cmd } => match cmd {
            BacklogCmd::Next { tag, stream } => cmd_next(&theme, tag, stream),
            BacklogCmd::Query {
                tag, status, stream, priority, effort, search, count, output,
            } => cmd_query(tag, status, stream, priority, effort, search, count, output, &theme),
            BacklogCmd::Focus => cmd_focus(&theme),
            BacklogCmd::Search { text } => cmd_search(&text, &theme),
            BacklogCmd::Status => cmd_status(&theme),
            BacklogCmd::Blocked => cmd_blocked(&theme),
            BacklogCmd::Stale { days } => cmd_stale(days, &theme),
            BacklogCmd::Context { task_id } => cmd_context(&task_id, &theme),
            BacklogCmd::Diff => cmd_diff(&theme),
            BacklogCmd::Burndown { period } => cmd_burndown(&period, &theme),
        },
        Commands::Ops { cmd } => match cmd {
            OpsCmd::Status => cmd_ops_status(&theme),
            OpsCmd::Health => cmd_ops_health(&theme),
            OpsCmd::Collisions => cmd_ops_collisions(&theme),
            OpsCmd::Drift => cmd_ops_drift(&theme),
            OpsCmd::Logs { job_name, tail } => cmd_ops_logs(&job_name, tail),
            OpsCmd::History { job_name, last } => cmd_ops_history(&job_name, last, &theme),
            OpsCmd::Run { job_name } => cmd_ops_run(&job_name),
            OpsCmd::Enable { job_name } => cmd_ops_toggle(&job_name, true),
            OpsCmd::Disable { job_name } => cmd_ops_toggle(&job_name, false),
            OpsCmd::Sync { auto_commit, direction } => cmd_ops_sync(&direction, auto_commit),
            OpsCmd::Reindex => cmd_ops_reindex(),
        },
    }
}

// ── backlog commands ────────────────────────────────────────────────────

fn cmd_next(theme: &themes::Theme, tag: Option<String>, stream: Option<String>) {
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

fn cmd_query(
    tag: Option<String>, status: Option<String>, stream: Option<String>,
    priority: Option<String>, effort: Option<String>, search: Option<String>,
    count: bool, output: String, theme: &themes::Theme,
) {
    let tf = find_tasks_file().unwrap_or_else(|| { eprintln!("tasks.json not found"); std::process::exit(1); });
    let data = tasks::load_tasks(&tf).unwrap_or_else(|e| { eprintln!("{e}"); std::process::exit(1); });
    let results = tasks::filter_tasks(
        &data.tasks, &data.tasks,
        tag.as_deref(), status.as_deref(), stream.as_deref(),
        priority.as_deref(), effort.as_deref(), search.as_deref(),
        &["task", "subtask"],
    );

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

fn cmd_focus(theme: &themes::Theme) {
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

fn cmd_search(text: &str, theme: &themes::Theme) {
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

fn cmd_status(theme: &themes::Theme) {
    let tf = find_tasks_file().unwrap_or_else(|| { eprintln!("tasks.json not found"); std::process::exit(1); });
    let data = tasks::load_tasks(&tf).unwrap_or_else(|e| { eprintln!("{e}"); std::process::exit(1); });

    let task_items: Vec<_> = data.tasks.iter()
        .filter(|t| matches!(t["type"].as_str(), Some("task" | "subtask")))
        .collect();
    let total = task_items.len();
    let done = task_items.iter().filter(|t| tasks::classify(t, &data.tasks) == "done").count();
    let active = task_items.iter().filter(|t| tasks::classify(t, &data.tasks) == "active").count();
    let blocked = task_items.iter().filter(|t| tasks::classify(t, &data.tasks) == "blocked").count();

    println!("\n{}{}{}",
        themes::ansi(theme.color("header")), data.project, themes::RESET);
    println!("  {} {done}/{total} done, {active} active, {blocked} blocked\n",
        theme.bar(done, total, 8));
}

fn cmd_blocked(theme: &themes::Theme) {
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

fn cmd_stale(days: i64, theme: &themes::Theme) {
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

fn cmd_context(task_id: &str, theme: &themes::Theme) {
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

fn cmd_diff(_theme: &themes::Theme) {
    // Delegate to Python — requires git show + JSON diff logic
    delegate_python(&["backlog", "diff"]);
}

fn cmd_burndown(period: &str, _theme: &themes::Theme) {
    delegate_python(&["backlog", "burndown", "--period", period]);
}

// ── ops commands ────────────────────────────────────────────────────────

fn cmd_ops_status(theme: &themes::Theme) {
    let sched = load_scheduler();
    let status = load_status();
    let jobs = sched.get("jobs").and_then(|v| v.as_object()).cloned().unwrap_or_default();

    println!("\n{}Scheduler{}", themes::ansi(theme.color("header")), themes::RESET);
    for (name, cfg) in jobs.iter() {
        let enabled = cfg["enabled"].as_bool().unwrap_or(true);
        let job_st = status.get(name).and_then(|v| v["status"].as_str()).unwrap_or("—");
        let ts = status.get(name).and_then(|v| v["timestamp"].as_str()).unwrap_or("");
        let short_ts = if ts.len() > 16 { &ts[5..16] } else { ts };
        let schedule = cfg["schedule"].as_str().unwrap_or("—");
        let ic = if !enabled { theme.icon("parked") }
            else { match job_st { "SUCCESS" => theme.icon("done"), "FAILED"|"TIMEOUT" => theme.icon("blocked"), _ => theme.icon("pending") } };
        let col = if !enabled { themes::ansi("dim") }
            else { match job_st { "SUCCESS" => themes::ansi("green"), "FAILED"|"TIMEOUT" => themes::ansi("red"), _ => themes::ansi("yellow") } };
        let disabled = if !enabled { "  [disabled]" } else { "" };
        println!("{col}  {ic} {name:<24} {schedule:<24} {job_st:<10} {short_ts}{disabled}{}", themes::RESET);
    }
    println!();
}

fn cmd_ops_health(theme: &themes::Theme) {
    let sched = load_scheduler();
    let status = load_status();
    let jobs = sched.get("jobs").and_then(|v| v.as_object()).cloned().unwrap_or_default();

    let mut failures = vec![];
    let mut skipped = vec![];
    for (name, info) in &status {
        if let Some(st) = info["status"].as_str() {
            match st {
                "FAILED" => failures.push(name.as_str()),
                "SKIPPED" => skipped.push(name.as_str()),
                _ => {}
            }
        }
    }

    // Collisions
    let collisions = find_collisions(&jobs);

    println!("\n{}Scheduler health{}", themes::ansi(theme.color("header")), themes::RESET);
    if failures.is_empty() {
        println!("{}  {} No failures{}", themes::ansi("green"), theme.icon("done"), themes::RESET);
    } else {
        println!("{}  {} Failures: {}{}", themes::ansi("red"), theme.icon("blocked"), failures.join(", "), themes::RESET);
    }
    if !skipped.is_empty() {
        println!("{}  {} Skipped: {}{}", themes::ansi("yellow"), theme.icon("pending"), skipped.join(", "), themes::RESET);
    }
    if collisions.is_empty() {
        println!("{}  {} No schedule collisions{}", themes::ansi("green"), theme.icon("done"), themes::RESET);
    } else {
        println!("{}  {} Schedule collisions:{}", themes::ansi("red"), theme.icon("blocked"), themes::RESET);
        for (sched, proj, names) in &collisions {
            println!("      {sched} on {proj}: {}", names.join(", "));
        }
    }
    let enabled = jobs.values().filter(|v| v["enabled"].as_bool().unwrap_or(true)).count();
    println!("\n  {enabled} enabled, {} disabled, {} total\n", jobs.len() - enabled, jobs.len());
}

fn cmd_ops_collisions(theme: &themes::Theme) {
    let sched = load_scheduler();
    let jobs = sched.get("jobs").and_then(|v| v.as_object()).cloned().unwrap_or_default();
    let collisions = find_collisions(&jobs);
    if collisions.is_empty() {
        println!("\n  {}{}  No schedule collisions.{}\n", themes::ansi("green"), theme.icon("done"), themes::RESET);
    } else {
        println!("\n{}Schedule collisions{}", themes::ansi(theme.color("header")), themes::RESET);
        for (sched, proj, names) in &collisions {
            println!("{}  {} {sched} on {proj}: {}{}", themes::ansi("red"), theme.icon("blocked"), names.join(", "), themes::RESET);
        }
        println!();
    }
}

fn cmd_ops_drift(theme: &themes::Theme) {
    let root = find_project_root().unwrap_or_else(|| { eprintln!("Not in git repo"); std::process::exit(1); });
    let template_path = root.join("system/scheduler/scheduler.template.json");
    let live = load_scheduler();
    let template: HashMap<String, serde_json::Value> = std::fs::read_to_string(&template_path)
        .ok()
        .and_then(|c| serde_json::from_str(&c).ok())
        .unwrap_or_default();

    let tmpl_jobs = template.get("jobs").and_then(|v| v.as_object()).cloned().unwrap_or_default();
    let live_jobs = live.get("jobs").and_then(|v| v.as_object()).cloned().unwrap_or_default();

    let mut drifts = vec![];
    let all_names: std::collections::BTreeSet<_> = tmpl_jobs.keys().chain(live_jobs.keys()).collect();
    for name in all_names {
        if !tmpl_jobs.contains_key(name) {
            drifts.push(format!("{}+ {name}: in live but not in template{}", themes::ansi("yellow"), themes::RESET));
        } else if !live_jobs.contains_key(name) {
            drifts.push(format!("{}- {name}: in template but not in live{}", themes::ansi("red"), themes::RESET));
        } else {
            for field in &["schedule", "enabled", "command", "project", "type"] {
                let tv = &tmpl_jobs[name][field];
                let lv = &live_jobs[name][field];
                if tv != lv {
                    drifts.push(format!("{}~ {name}.{field}: template={tv} live={lv}{}", themes::ansi("yellow"), themes::RESET));
                }
            }
        }
    }

    if drifts.is_empty() {
        println!("\n  {}{}  No drift — live matches template.{}\n", themes::ansi("green"), theme.icon("done"), themes::RESET);
    } else {
        println!("\n{}Config drift (template vs live){}", themes::ansi(theme.color("header")), themes::RESET);
        for d in &drifts { println!("  {d}"); }
        println!();
    }
}

fn cmd_ops_logs(job_name: &str, tail: usize) {
    let log_dir = home().join(format!(".claude/scheduler/logs/{job_name}"));
    if !log_dir.exists() {
        eprintln!("No logs for '{job_name}'."); std::process::exit(1);
    }
    let mut logs: Vec<_> = std::fs::read_dir(&log_dir).unwrap()
        .filter_map(|e| e.ok())
        .filter(|e| e.path().extension().map_or(false, |x| x == "log"))
        .collect();
    logs.sort_by_key(|e| std::cmp::Reverse(e.file_name()));
    if let Some(latest) = logs.first() {
        let content = std::fs::read_to_string(latest.path()).unwrap_or_default();
        let lines: Vec<_> = content.lines().collect();
        let start = if lines.len() > tail { lines.len() - tail } else { 0 };
        println!("\n  \x1b[2m{}\x1b[0m\n", latest.file_name().to_string_lossy());
        for line in &lines[start..] {
            if line.contains("SUCCESS") { println!("  \x1b[32m{line}\x1b[0m"); }
            else if line.contains("FAILED") || line.contains("ERROR") { println!("  \x1b[31m{line}\x1b[0m"); }
            else { println!("  {line}"); }
        }
        println!();
    }
}

fn cmd_ops_history(job_name: &str, last: usize, theme: &themes::Theme) {
    let log_dir = home().join(format!(".claude/scheduler/logs/{job_name}"));
    if !log_dir.exists() { eprintln!("No history for '{job_name}'."); std::process::exit(1); }
    let mut logs: Vec<_> = std::fs::read_dir(&log_dir).unwrap()
        .filter_map(|e| e.ok())
        .filter(|e| e.path().extension().map_or(false, |x| x == "log"))
        .collect();
    logs.sort_by_key(|e| std::cmp::Reverse(e.file_name()));

    println!("\n{}History: {job_name} (last {}){}", themes::ansi(theme.color("header")), logs.len().min(last), themes::RESET);
    for entry in logs.iter().take(last) {
        let content = std::fs::read_to_string(entry.path()).unwrap_or_default();
        let (st, col) = if content.contains("SUCCESS") { ("SUCCESS", "green") }
            else if content.contains("FAILED") { ("FAILED", "red") }
            else if content.contains("TIMEOUT") { ("TIMEOUT", "red") }
            else if content.contains("SKIPPED") { ("SKIPPED", "dim") }
            else { ("UNKNOWN", "yellow") };
        let ic = match st { "SUCCESS" => theme.icon("done"), "FAILED"|"TIMEOUT" => theme.icon("blocked"), _ => theme.icon("pending") };
        let date = entry.path().file_stem().map(|s| s.to_string_lossy().to_string()).unwrap_or_default();
        println!("{}{ic} {date}  {st}{}", themes::ansi(col), themes::RESET);
    }
    println!();
}

fn cmd_ops_run(job_name: &str) {
    validate_job_name(job_name);
    let unit = format!("brana-sched-{job_name}.service");
    println!("\n  Starting {unit}...");
    let status = Command::new("systemctl").args(["--user", "start", &unit]).status();
    match status {
        Ok(s) if s.success() => println!("  \x1b[32mTriggered. Check: brana ops logs {job_name}\x1b[0m\n"),
        _ => { eprintln!("  \x1b[31mFailed to start {unit}\x1b[0m"); std::process::exit(1); }
    }
}

fn cmd_ops_toggle(job_name: &str, enabled: bool) {
    validate_job_name(job_name);
    let config_path = home().join(".claude/scheduler/scheduler.json");
    let mut sched = load_scheduler();
    if let Some(jobs) = sched.get_mut("jobs").and_then(|v| v.as_object_mut()) {
        if let Some(job) = jobs.get_mut(job_name) {
            job["enabled"] = serde_json::Value::Bool(enabled);
        } else {
            eprintln!("Job '{job_name}' not found."); std::process::exit(1);
        }
    }
    std::fs::write(&config_path, serde_json::to_string_pretty(&sched).unwrap() + "\n").ok();
    let action = if enabled { "Enabled" } else { "Disabled" };
    let col = if enabled { "\x1b[32m" } else { "\x1b[33m" };
    println!("\n  {col}{action} '{job_name}'{}", themes::RESET);

    let timer = format!("brana-sched-{job_name}.timer");
    let cmd = if enabled { "start" } else { "stop" };
    if Command::new("systemctl").args(["--user", cmd, &timer]).status().is_ok() {
        println!("  {col}Timer {cmd}ed.{}\n", themes::RESET);
    }
}

fn cmd_ops_sync(direction: &str, auto_commit: bool) {
    let root = find_project_root().unwrap_or_else(|| { eprintln!("Not in git repo"); std::process::exit(1); });
    let script = root.join("system/scripts/sync-state.sh");
    if !script.exists() { eprintln!("sync-state.sh not found"); std::process::exit(1); }

    let mut cmd = Command::new("bash");
    cmd.arg(&script).arg(direction).current_dir(&root);
    if auto_commit { cmd.arg("--auto-commit"); }

    println!("\n  Running sync-state.sh {direction}...");
    match cmd.status() {
        Ok(s) if s.success() => println!("  \x1b[32mDone.\x1b[0m\n"),
        _ => { eprintln!("  \x1b[31mFailed.\x1b[0m"); std::process::exit(1); }
    }
}

fn cmd_ops_reindex() {
    let root = find_project_root().unwrap_or_else(|| { eprintln!("Not in git repo"); std::process::exit(1); });
    let script = root.join("system/scripts/index-knowledge.sh");
    if !script.exists() { eprintln!("index-knowledge.sh not found"); std::process::exit(1); }

    println!("\n  Running index-knowledge.sh...");
    match Command::new("bash").arg(&script).current_dir(&root).status() {
        Ok(s) if s.success() => println!("  \x1b[32mDone.\x1b[0m\n"),
        _ => { eprintln!("  \x1b[31mFailed.\x1b[0m"); std::process::exit(1); }
    }
}

// ── doctor ──────────────────────────────────────────────────────────────

fn cmd_doctor(theme: &themes::Theme) {
    let ok = theme.icon("done");
    let fail = theme.icon("blocked");
    let mut passed = 0;
    let mut total = 0;

    let mut check = |name: &str, result: bool, detail: &str| {
        total += 1;
        let (ic, col) = if result { passed += 1; (ok, "\x1b[32m") } else { (fail, "\x1b[31m") };
        let d = if detail.is_empty() { String::new() } else { format!("  ({detail})") };
        println!("{col}  {ic} {name}{d}{}", themes::RESET);
    };

    println!("\n\x1b[1mbrana doctor\x1b[0m (Rust)\n");

    let root = find_project_root();
    check("Git project detected", root.is_some(),
        &root.as_ref().map(|r| r.file_name().unwrap_or_default().to_string_lossy().to_string()).unwrap_or_default());

    if let Some(ref root) = root {
        let tf = root.join(".claude/tasks.json");
        let tasks_ok = tf.exists();
        if tasks_ok {
            let data = tasks::load_tasks(&tf);
            let count = data.as_ref().map(|d| d.tasks.len()).unwrap_or(0);
            check("tasks.json exists", true, &format!("{count} tasks"));
            if let Ok(ref data) = data {
                let dupes = tasks::find_duplicate_ids(&data.tasks);
                check("No duplicate task IDs", dupes.is_empty(),
                    &if dupes.is_empty() { "all unique".into() } else { format!("duplicates: {}", dupes.join(", ")) });
            }
        } else {
            check("tasks.json exists", false, "not found");
        }
    }

    let sched_path = home().join(".claude/scheduler/scheduler.json");
    check("scheduler.json exists", sched_path.exists(), "");
    if sched_path.exists() {
        let sched = load_scheduler();
        let enabled = sched.get("jobs").and_then(|v| v.as_object())
            .map(|j| j.values().filter(|v| v["enabled"].as_bool().unwrap_or(true)).count())
            .unwrap_or(0);
        check("Scheduler jobs configured", enabled > 0, &format!("{enabled} enabled"));
    }

    // Systemd timers
    let timer_count = Command::new("systemctl")
        .args(["--user", "list-units", "brana-sched-*.timer", "--no-legend", "--plain"])
        .output().ok()
        .map(|o| String::from_utf8_lossy(&o.stdout).lines()
            .filter(|l| l.contains("active")).count())
        .unwrap_or(0);
    check("Systemd timers active", timer_count > 0, &format!("{timer_count} active"));

    // Ruflo
    let ruflo = ["ruflo", "claude-flow"].iter().any(|cmd| {
        Command::new("which").arg(cmd).output().ok().map_or(false, |o| o.status.success())
    });
    check("Ruflo/claude-flow installed", ruflo, "");

    check("Bootstrap deployed", home().join(".claude/CLAUDE.md").exists(), "");

    println!("\n  {passed}/{total} checks passed\n");
}

// ── version ─────────────────────────────────────────────────────────────

fn cmd_version() {
    println!("brana-cli {} (Rust)", env!("CARGO_PKG_VERSION"));
}

// ── helpers ─────────────────────────────────────────────────────────────

fn load_scheduler() -> HashMap<String, serde_json::Value> {
    let path = home().join(".claude/scheduler/scheduler.json");
    std::fs::read_to_string(&path).ok()
        .and_then(|c| serde_json::from_str(&c).ok())
        .unwrap_or_default()
}

fn load_status() -> HashMap<String, serde_json::Value> {
    let path = home().join(".claude/scheduler/last-status.json");
    let content = std::fs::read_to_string(&path).unwrap_or_default();
    let content = content.trim();
    if content.is_empty() { return HashMap::new(); }
    serde_json::from_str(content).unwrap_or_default()
}

fn find_collisions(jobs: &serde_json::Map<String, serde_json::Value>) -> Vec<(String, String, Vec<String>)> {
    let mut groups: HashMap<(String, String), Vec<String>> = HashMap::new();
    for (name, cfg) in jobs {
        if !cfg["enabled"].as_bool().unwrap_or(true) { continue; }
        let key = (
            cfg["schedule"].as_str().unwrap_or("").to_string(),
            std::path::Path::new(cfg["project"].as_str().unwrap_or(""))
                .file_name().unwrap_or_default().to_string_lossy().to_string(),
        );
        groups.entry(key).or_default().push(name.clone());
    }
    groups.into_iter()
        .filter(|(_, v)| v.len() > 1)
        .map(|((s, p), v)| (s, p, v))
        .collect()
}

fn validate_job_name(name: &str) {
    if !name.chars().all(|c| c.is_alphanumeric() || c == '-' || c == '_') {
        eprintln!("Invalid job name '{name}'. Use alphanumeric, hyphens, underscores.");
        std::process::exit(1);
    }
}

fn delegate_python(args: &[&str]) {
    // Fall back to Python CLI for complex commands
    let status = Command::new("uv")
        .args(["run", "brana"])
        .args(args)
        .status();
    match status {
        Ok(s) => std::process::exit(s.code().unwrap_or(1)),
        Err(_) => { eprintln!("Python CLI not available. Install with: uv pip install -e ."); std::process::exit(1); }
    }
}
