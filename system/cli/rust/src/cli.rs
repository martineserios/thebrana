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

mod sync;
mod tasks;
mod themes;

use clap::{Parser, Subcommand, ValueEnum};
use std::collections::{HashMap, HashSet};
use std::path::PathBuf;
use std::process::Command;

// ── ValueEnum types for parse-time validation ──────────────────────────

#[derive(Clone, ValueEnum)]
enum TaskStatus {
    Pending,
    #[value(name = "in_progress")]
    InProgress,
    Completed,
    Cancelled,
}

#[derive(Clone, ValueEnum)]
enum TaskStream {
    Roadmap,
    Bugs,
    #[value(name = "tech-debt")]
    TechDebt,
    Docs,
    Experiments,
    Research,
    Personal,
}

#[derive(Clone, ValueEnum)]
enum TaskPriority {
    #[value(name = "P0")]
    P0,
    #[value(name = "P1")]
    P1,
    #[value(name = "P2")]
    P2,
    #[value(name = "P3")]
    P3,
}

#[derive(Clone, ValueEnum)]
enum TaskEffort {
    #[value(name = "S")]
    S,
    #[value(name = "M")]
    M,
    #[value(name = "L")]
    L,
    #[value(name = "XL")]
    Xl,
}

#[derive(Clone, ValueEnum)]
enum TaskType {
    Task,
    Subtask,
    Phase,
    Milestone,
}

#[derive(Clone, ValueEnum)]
enum BurndownPeriod {
    Day,
    Week,
    Month,
}

// Convert ValueEnums to the string form used in tasks.json
fn ve_str<T: ValueEnum>(v: &Option<T>) -> Option<String> {
    v.as_ref().map(|val| {
        val.to_possible_value().unwrap().get_name().to_string()
    })
}

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
    /// Validate a tasks.json file (JSON + schema)
    Validate {
        /// Path to tasks.json
        file: PathBuf,
    },
    /// List portfolio client/project paths from tasks-portfolio.json
    Portfolio,
    /// Run a task: create worktree, print claude command, set in_progress
    Run {
        /// Task ID (e.g., t-525)
        task_id: String,
        /// Spawn claude in a tmux window (requires tmux)
        #[arg(long)]
        spawn: bool,
    },
    /// Show next unblocked tasks with model recommendations, optionally auto-spawn
    Queue {
        /// Max tasks to show (default 5)
        #[arg(long, default_value = "5")]
        max: usize,
        /// Auto-spawn agents on all candidates (requires tmux)
        #[arg(long)]
        auto: bool,
    },
    /// List or manage active agents
    Agents {
        #[command(subcommand)]
        cmd: Option<AgentsCmd>,
    },
    /// Show version
    Version,
}

#[derive(Subcommand)]
enum AgentsCmd {
    /// Kill an active agent
    Kill {
        /// Agent ID (from brana agents output)
        agent_id: String,
    },
}

#[derive(Subcommand)]
enum BacklogCmd {
    /// Next unblocked task by priority
    Next {
        #[arg(long)]
        tag: Option<String>,
        #[arg(long, value_enum)]
        stream: Option<TaskStream>,
    },
    /// Filter tasks (AND logic)
    Query {
        /// Tag filter (comma-separated for AND: "dx,cli")
        #[arg(short, long)]
        tag: Option<String>,
        #[arg(short, long, value_enum)]
        status: Option<TaskStatus>,
        #[arg(long, value_enum)]
        stream: Option<TaskStream>,
        #[arg(short, long, value_enum)]
        priority: Option<TaskPriority>,
        #[arg(short, long, value_enum)]
        effort: Option<TaskEffort>,
        #[arg(long)]
        search: Option<String>,
        #[arg(long)]
        count: bool,
        #[arg(long, default_value = "json")]
        output: String,
        /// Filter by type (task, subtask, phase, milestone)
        #[arg(long = "type", value_enum)]
        task_type: Option<TaskType>,
        /// Filter by parent ID
        #[arg(long)]
        parent: Option<String>,
        /// Filter by branch field
        #[arg(long)]
        branch: Option<String>,
    },
    /// Smart daily pick
    Focus,
    /// Free-text search
    Search {
        text: String,
    },
    /// Portfolio or project status
    Status {
        /// Cross-client status from tasks-portfolio.json
        #[arg(long)]
        all: bool,
        /// Output JSON instead of themed
        #[arg(long)]
        json: bool,
    },
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
        #[arg(long, value_enum, default_value = "week")]
        period: BurndownPeriod,
    },
    /// Auto-complete parents whose children are all done
    Rollup {
        #[arg(long)]
        file: Option<PathBuf>,
        #[arg(long)]
        dry_run: bool,
    },
    /// Set a field on a task
    Set {
        /// Task ID (e.g. t-463)
        task_id: String,
        /// Field name (status, priority, tags, context, etc.)
        field: String,
        /// Value (use +val/-val for array fields)
        value: String,
        /// Append to text fields instead of replacing
        #[arg(long)]
        append: bool,
        /// Path to tasks.json (auto-detected if omitted)
        #[arg(long)]
        file: Option<PathBuf>,
    },
    /// Add a new task from JSON
    Add {
        /// Task JSON (subject, stream, type required; id auto-assigned)
        #[arg(long)]
        json: String,
        /// Path to tasks.json (auto-detected if omitted)
        #[arg(long)]
        file: Option<PathBuf>,
    },
    /// Get full task JSON or a single field
    Get {
        /// Task ID
        task_id: String,
        /// Return only this field
        #[arg(long)]
        field: Option<String>,
    },
    /// Aggregate stats by status, stream, priority, type
    Stats,
    /// Tag inventory, filtering, and bulk management
    Tags {
        /// AND filter: tasks with ALL listed tags (comma-separated)
        #[arg(long)]
        filter: Option<String>,
        /// OR filter: tasks with ANY listed tag (comma-separated)
        #[arg(long)]
        any: Option<String>,
        /// Output format
        #[arg(long, default_value = "json")]
        output: String,
    },
    /// Full roadmap tree (phases → milestones → tasks)
    Roadmap {
        /// Output JSON instead of themed
        #[arg(long)]
        json: bool,
    },
    /// Subtree of a phase or milestone
    Tree {
        /// Root task ID (phase or milestone)
        root_id: String,
        /// Output JSON instead of themed
        #[arg(long)]
        json: bool,
    },
    /// Sync tasks with GitHub Issues (parallel, via gh api)
    Sync {
        /// Show what would happen without making changes
        #[arg(long)]
        dry_run: bool,
        /// Force re-sync even if github_issue is already set
        #[arg(long)]
        force: bool,
        /// Max parallel GitHub API calls (1-20)
        #[arg(long, default_value = "10")]
        parallel: usize,
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
    /// Compute session metrics from JSONL event file
    Metrics {
        /// Path to session JSONL file
        session_file: PathBuf,
    },
}

fn find_tasks_file() -> Option<PathBuf> {
    // In worktrees, --show-toplevel returns the worktree root (which has its own
    // copy of tasks.json). Use --git-common-dir to find the main repo's .git dir,
    // then resolve to the main repo's .claude/tasks.json so all worktrees share
    // one authoritative file.
    let common_root = Command::new("git")
        .args(["rev-parse", "--git-common-dir"])
        .output()
        .ok()
        .and_then(|o| {
            if o.status.success() {
                let common_git = PathBuf::from(String::from_utf8_lossy(&o.stdout).trim().to_string());
                // --git-common-dir returns the .git directory; parent is the repo root
                common_git.parent().map(|p| p.to_path_buf())
            } else {
                None
            }
        });

    if let Some(root) = &common_root {
        let f = root.join(".claude/tasks.json");
        if f.exists() {
            return Some(f);
        }
    }

    // Fallback: try worktree root (for repos where .claude/ only exists in worktree)
    let toplevel = Command::new("git")
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

    if let Some(root) = &toplevel {
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
        Commands::Validate { file } => cmd_validate(&file),
        Commands::Portfolio => cmd_portfolio(),
        Commands::Run { task_id, spawn } => cmd_run(&task_id, spawn),
        Commands::Queue { max, auto } => cmd_queue(max, auto),
        Commands::Agents { cmd } => match cmd {
            None => cmd_agents(),
            Some(AgentsCmd::Kill { agent_id }) => cmd_agents_kill(&agent_id),
        },
        Commands::Backlog { cmd } => match cmd {
            BacklogCmd::Next { tag, stream } => cmd_next(&theme, tag, ve_str(&stream)),
            BacklogCmd::Query {
                tag, status, stream, priority, effort, search, count, output,
                task_type, parent, branch,
            } => cmd_query(tag, ve_str(&status), ve_str(&stream), ve_str(&priority), ve_str(&effort), search, count, output, &theme, ve_str(&task_type), parent, branch),
            BacklogCmd::Focus => cmd_focus(&theme),
            BacklogCmd::Search { text } => cmd_search(&text, &theme),
            BacklogCmd::Status { all, json } => cmd_status(&theme, all, json),
            BacklogCmd::Blocked => cmd_blocked(&theme),
            BacklogCmd::Stale { days } => cmd_stale(days, &theme),
            BacklogCmd::Context { task_id } => cmd_context(&task_id, &theme),
            BacklogCmd::Diff => cmd_diff(&theme),
            BacklogCmd::Burndown { period } => cmd_burndown(&period.to_possible_value().unwrap().get_name().to_string(), &theme),
            BacklogCmd::Rollup { file, dry_run } => cmd_rollup(file, dry_run),
            BacklogCmd::Set { task_id, field, value, append, file } => cmd_set(&task_id, &field, &value, append, file),
            BacklogCmd::Add { json, file } => cmd_add(&json, file),
            BacklogCmd::Get { task_id, field } => cmd_get(&task_id, field),
            BacklogCmd::Stats => cmd_stats(),
            BacklogCmd::Tags { filter, any, output } => cmd_tags(filter, any, output, &theme),
            BacklogCmd::Roadmap { json } => cmd_roadmap(json, &theme),
            BacklogCmd::Tree { root_id, json } => cmd_tree(&root_id, json, &theme),
            BacklogCmd::Sync { dry_run, force, parallel } => sync::cmd_sync(dry_run, force, parallel),
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
            OpsCmd::Metrics { session_file } => cmd_ops_metrics(&session_file),
        },
    }
}

// ── portfolio command ───────────────────────────────────────────────────

fn cmd_portfolio() {
    let home = std::env::var("HOME").unwrap_or_default();
    let portfolio_path = PathBuf::from(&home).join(".claude/tasks-portfolio.json");
    let content = match std::fs::read_to_string(&portfolio_path) {
        Ok(c) => c,
        Err(_) => { eprintln!("tasks-portfolio.json not found"); std::process::exit(1); }
    };
    let portfolio: serde_json::Value = match serde_json::from_str(&content) {
        Ok(v) => v,
        Err(e) => { eprintln!("invalid portfolio JSON: {e}"); std::process::exit(1); }
    };

    // Support both { clients: [...] } and { projects: [...] } schemas
    let clients = if let Some(clients) = portfolio["clients"].as_array() {
        clients.clone()
    } else if let Some(projects) = portfolio["projects"].as_array() {
        projects.iter().map(|p| {
            let slug = p["slug"].as_str().or_else(|| p["name"].as_str()).unwrap_or("unknown");
            serde_json::json!({"slug": slug, "projects": [p]})
        }).collect()
    } else {
        eprintln!("portfolio has no clients or projects array");
        std::process::exit(1);
    };

    let mut entries = Vec::new();
    for client in &clients {
        let client_slug = client["slug"].as_str().unwrap_or("unknown");
        let projects = client["projects"].as_array().cloned().unwrap_or_default();
        for proj in &projects {
            let proj_slug = proj["slug"].as_str().unwrap_or(client_slug);
            let path_str = proj["path"].as_str().unwrap_or("");
            let resolved = path_str.replace("~/", &format!("{home}/"));
            let tasks_path = PathBuf::from(&resolved).join(".claude/tasks.json");
            entries.push(serde_json::json!({
                "client": client_slug,
                "project": proj_slug,
                "path": resolved,
                "has_tasks": tasks_path.exists(),
            }));
        }
    }
    println!("{}", serde_json::to_string(&entries).unwrap());
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

fn cmd_status(theme: &themes::Theme, all: bool, json_out: bool) {
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

// ── new commands (Wave 1-4) ─────────────────────────────────────────────

fn cmd_set(task_id: &str, field: &str, value: &str, append: bool, file: Option<PathBuf>) {
    let tf = file.unwrap_or_else(|| find_tasks_file().unwrap_or_else(|| { eprintln!("tasks.json not found"); std::process::exit(1); }));
    let mut val = tasks::load_raw(&tf).unwrap_or_else(|e| { eprintln!("{e}"); std::process::exit(1); });

    // Find task index first
    let idx = val["tasks"].as_array()
        .and_then(|arr| arr.iter().position(|t| t["id"].as_str() == Some(task_id)));
    let idx = match idx {
        Some(i) => i,
        None => { eprintln!("{{\"ok\":false,\"error\":\"task {task_id} not found\"}}"); std::process::exit(1); }
    };

    // Mutate via index
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

fn cmd_add(json_str: &str, file: Option<PathBuf>) {
    let tf = file.unwrap_or_else(|| find_tasks_file().unwrap_or_else(|| { eprintln!("tasks.json not found"); std::process::exit(1); }));
    let mut val = tasks::load_raw(&tf).unwrap_or_else(|e| { eprintln!("{e}"); std::process::exit(1); });

    let mut new_task: serde_json::Value = serde_json::from_str(json_str)
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

fn cmd_get(task_id: &str, field: Option<String>) {
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

fn cmd_stats() {
    let tf = find_tasks_file().unwrap_or_else(|| { eprintln!("tasks.json not found"); std::process::exit(1); });
    let data = tasks::load_tasks(&tf).unwrap_or_else(|e| { eprintln!("{e}"); std::process::exit(1); });
    let stats = tasks::compute_stats(&data.tasks, &data.tasks);
    println!("{}", serde_json::to_string(&stats).unwrap());
}

fn cmd_tags(filter: Option<String>, any: Option<String>, output: String, theme: &themes::Theme) {
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

fn cmd_roadmap(json_out: bool, theme: &themes::Theme) {
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

fn cmd_tree(root_id: &str, json_out: bool, theme: &themes::Theme) {
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
        // Phase/milestone: show with progress bar
        let col = themes::ansi(theme.color("header"));
        if let Some(progress) = node.get("progress") {
            let done = progress["done"].as_u64().unwrap_or(0) as usize;
            let total = progress["total"].as_u64().unwrap_or(0) as usize;
            println!("{indent}{col}{id}  {subject}  {}{}", theme.bar(done, total, 8), themes::RESET);
        } else {
            println!("{indent}{col}{id}  {subject}{}", themes::RESET);
        }
    } else {
        // Task: show with icon
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

// ── validate ─────────────────────────────────────────────────────────────

fn cmd_validate(file: &PathBuf) {
    let errors = tasks::validate_schema(file.as_path());
    if errors.is_empty() {
        println!("{{\"valid\":true}}");
    } else {
        let joined = errors.join("; ");
        let escaped = serde_json::to_string(&joined).unwrap();
        println!("{{\"valid\":false,\"errors\":{escaped}}}");
        std::process::exit(1);
    }
}

// ── rollup ───────────────────────────────────────────────────────────────

fn cmd_rollup(file: Option<PathBuf>, dry_run: bool) {
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

// ── ops metrics ──────────────────────────────────────────────────────────

fn cmd_ops_metrics(session_file: &PathBuf) {
    let content = std::fs::read_to_string(session_file).unwrap_or_default();
    let events: Vec<serde_json::Value> = content
        .lines()
        .filter_map(|l| serde_json::from_str(l).ok())
        .collect();

    let total = events.len();
    let successes = events.iter().filter(|e| e["outcome"].as_str() == Some("success")).count();
    let failures = events.iter().filter(|e| matches!(e["outcome"].as_str(), Some("failure" | "test-fail" | "lint-fail"))).count();
    let corrections = events.iter().filter(|e| e["outcome"].as_str() == Some("correction")).count();
    let test_writes = events.iter().filter(|e| e["outcome"].as_str() == Some("test-write")).count();
    let cascades = events.iter().filter(|e| e["cascade"].as_bool() == Some(true)).count();
    let pr_creates = events.iter().filter(|e| e["outcome"].as_str() == Some("pr-create")).count();
    let test_passes = events.iter().filter(|e| e["outcome"].as_str() == Some("test-pass")).count();
    let test_fails = events.iter().filter(|e| e["outcome"].as_str() == Some("test-fail")).count();
    let lint_passes = events.iter().filter(|e| e["outcome"].as_str() == Some("lint-pass")).count();
    let lint_fails = events.iter().filter(|e| e["outcome"].as_str() == Some("lint-fail")).count();
    let edits = events.iter().filter(|e| matches!(e["tool"].as_str(), Some("Edit" | "Write"))).count();
    let delegations = events.iter().filter(|e| e["tool"].as_str() == Some("Task")).count();

    // Tools and files
    let tools: std::collections::BTreeSet<&str> = events.iter().filter_map(|e| e["tool"].as_str()).collect();
    let files: std::collections::BTreeSet<&str> = events.iter()
        .filter_map(|e| e["detail"].as_str())
        .filter(|d| !d.is_empty())
        .collect();
    let files_vec: Vec<&str> = files.into_iter().take(10).collect();

    // Flywheel rates
    let correction_rate = if edits > 0 { corrections as f64 / edits as f64 } else { 0.0 };
    let test_write_rate = if edits > 0 { test_writes as f64 / edits as f64 } else { 0.0 };
    let cascade_rate = if failures > 0 { cascades as f64 / failures as f64 } else { 0.0 };

    // Auto-fix rate: failures followed by success on same detail
    let mut fail_files: HashSet<String> = HashSet::new();
    let mut auto_fixes = 0usize;
    for e in &events {
        let detail = e["detail"].as_str().unwrap_or("").to_string();
        match e["outcome"].as_str() {
            Some("failure" | "test-fail" | "lint-fail") => { fail_files.insert(detail); }
            Some("success" | "correction" | "test-pass" | "lint-pass") => {
                if fail_files.remove(&detail) { auto_fixes += 1; }
            }
            _ => {}
        }
    }
    let auto_fix_rate = if failures > 0 { auto_fixes as f64 / failures as f64 } else { 0.0 };

    let test_total = test_passes + test_fails;
    let test_pass_rate = if test_total > 0 { format!("{:.2}", test_passes as f64 / test_total as f64) } else { "N/A".into() };
    let lint_total = lint_passes + lint_fails;
    let lint_pass_rate = if lint_total > 0 { format!("{:.2}", lint_passes as f64 / lint_total as f64) } else { "N/A".into() };

    let output = serde_json::json!({
        "events": total,
        "successes": successes,
        "failures": failures,
        "corrections": corrections,
        "test_writes": test_writes,
        "cascades": cascades,
        "pr_creates": pr_creates,
        "edits": edits,
        "test_passes": test_passes,
        "test_fails": test_fails,
        "lint_passes": lint_passes,
        "lint_fails": lint_fails,
        "delegations": delegations,
        "flywheel": {
            "correction_rate": format!("{:.2}", correction_rate),
            "auto_fix_rate": format!("{:.2}", auto_fix_rate),
            "test_write_rate": format!("{:.2}", test_write_rate),
            "cascade_rate": format!("{:.2}", cascade_rate),
            "test_pass_rate": test_pass_rate,
            "lint_pass_rate": lint_pass_rate,
            "delegations": delegations,
            "pr_creates": pr_creates,
        },
        "tools": tools.into_iter().collect::<Vec<_>>().join(","),
        "files": files_vec.join(","),
    });

    println!("{}", serde_json::to_string(&output).unwrap());
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

fn cmd_run(task_id: &str, spawn: bool) {
    let tf = find_tasks_file().unwrap_or_else(|| {
        eprintln!("{}", serde_json::json!({"ok": false, "error": "tasks.json not found"}));
        std::process::exit(1);
    });
    let mut val = tasks::load_raw(&tf).unwrap_or_else(|e| {
        eprintln!("{}", serde_json::json!({"ok": false, "error": e}));
        std::process::exit(1);
    });
    let data = tasks::load_tasks(&tf).unwrap_or_else(|e| {
        eprintln!("{}", serde_json::json!({"ok": false, "error": e}));
        std::process::exit(1);
    });

    let task = data.tasks.iter().find(|t| t["id"].as_str() == Some(task_id));
    let task = match task {
        Some(t) => t,
        None => {
            eprintln!("{}", serde_json::json!({"ok": false, "error": format!("task {task_id} not found")}));
            std::process::exit(1);
        }
    };

    match tasks::validate_task_runnable(task, &data.tasks) {
        Ok(()) => {}
        Err(e) => {
            if e.contains("already in_progress") {
                let branch = task["branch"].as_str().unwrap_or("unknown");
                println!("{}", serde_json::json!({
                    "ok": true, "id": task_id, "status": "already_running", "branch": branch
                }));
                return;
            }
            eprintln!("{}", serde_json::json!({"ok": false, "error": e}));
            std::process::exit(1);
        }
    }

    let branch = tasks::branch_for_task(task);
    let repo_root = find_project_root().unwrap_or_else(|| {
        eprintln!("{}", serde_json::json!({"ok": false, "error": "not in a git repo"}));
        std::process::exit(1);
    });
    let repo_name = repo_root.file_name().unwrap().to_str().unwrap();
    let worktree_rel = tasks::worktree_path_for_task(task, repo_name);
    let worktree_abs = repo_root.parent().unwrap().join(&worktree_rel[3..]);

    // Create git worktree
    let wt_out = Command::new("git")
        .args(["worktree", "add", &worktree_rel, "-b", &branch])
        .current_dir(&repo_root)
        .output();
    match wt_out {
        Ok(o) if o.status.success() => {}
        Ok(o) => {
            let err = String::from_utf8_lossy(&o.stderr);
            if err.contains("already exists") {
                let wt2 = Command::new("git")
                    .args(["worktree", "add", &worktree_rel, &branch])
                    .current_dir(&repo_root)
                    .output();
                match wt2 {
                    Ok(o2) if o2.status.success() => {}
                    _ => {
                        eprintln!("{}", serde_json::json!({"ok": false, "error": format!("worktree failed: {err}")}));
                        std::process::exit(1);
                    }
                }
            } else {
                eprintln!("{}", serde_json::json!({"ok": false, "error": format!("worktree failed: {err}")}));
                std::process::exit(1);
            }
        }
        Err(e) => {
            eprintln!("{}", serde_json::json!({"ok": false, "error": format!("git error: {e}")}));
            std::process::exit(1);
        }
    }

    // Update task fields
    let idx = val["tasks"]
        .as_array()
        .and_then(|arr| arr.iter().position(|t| t["id"].as_str() == Some(task_id)));
    if let Some(idx) = idx {
        let today = chrono::Local::now().format("%Y-%m-%d").to_string();
        val["tasks"][idx]["status"] = serde_json::json!("in_progress");
        val["tasks"][idx]["started"] = serde_json::json!(today);
        val["tasks"][idx]["branch"] = serde_json::json!(branch);
        tasks::save_tasks(&tf, &val).unwrap_or_else(|e| {
            eprintln!("{}", serde_json::json!({"ok": false, "error": e}));
            std::process::exit(1);
        });
    }

    // Spawn in tmux if requested
    if spawn {
        if !tasks::is_in_tmux() {
            eprintln!("{}", serde_json::json!({
                "ok": false,
                "error": "tmux required for --spawn. Run without --spawn to get the command."
            }));
            std::process::exit(1);
        }

        let tmux_target = format!("t-{}", task_id.strip_prefix("t-").unwrap_or(task_id));
        let tmux_cmd = format!("cd {} && claude", worktree_abs.display());

        // Create new tmux window with claude running in it
        let spawn_result = Command::new("tmux")
            .args(["new-window", "-n", &tmux_target, &tmux_cmd])
            .output();

        match spawn_result {
            Ok(o) if o.status.success() => {
                // Get the PID of the new pane
                let pid_out = Command::new("tmux")
                    .args(["list-panes", "-t", &tmux_target, "-F", "#{pane_pid}"])
                    .output();
                let pid: u32 = pid_out.ok()
                    .and_then(|o| String::from_utf8(o.stdout).ok())
                    .and_then(|s| s.trim().parse().ok())
                    .unwrap_or(0);

                // Register agent
                let agents_path = home().join(".claude/agents.json");
                let mut agents = tasks::load_agents(&agents_path);
                let entry = tasks::new_agent_entry(
                    task_id, pid, &tmux_target, &worktree_rel, &branch,
                );
                agents.push(entry);
                tasks::save_agents(&agents_path, &agents).ok();

                println!("{}", serde_json::json!({
                    "ok": true,
                    "id": task_id,
                    "branch": branch,
                    "worktree": worktree_rel,
                    "tmux_target": tmux_target,
                    "pid": pid,
                    "spawned": true
                }));
            }
            Ok(o) => {
                let err = String::from_utf8_lossy(&o.stderr);
                eprintln!("{}", serde_json::json!({"ok": false, "error": format!("tmux spawn failed: {err}")}));
                std::process::exit(1);
            }
            Err(e) => {
                eprintln!("{}", serde_json::json!({"ok": false, "error": format!("tmux error: {e}")}));
                std::process::exit(1);
            }
        }
    } else {
        let cmd = format!("cd {} && claude", worktree_abs.display());
        println!("{}", serde_json::json!({
            "ok": true,
            "id": task_id,
            "branch": branch,
            "worktree": worktree_rel,
            "command": cmd
        }));
    }
}

fn cmd_agents() {
    let agents_path = home().join(".claude/agents.json");
    let agents = tasks::load_agents(&agents_path);
    let (alive, removed) = tasks::prune_dead_agents(agents);

    // Save pruned list back
    if removed > 0 {
        tasks::save_agents(&agents_path, &alive).ok();
    }

    if alive.is_empty() {
        println!("No active agents.");
        return;
    }

    println!("{}", tasks::format_agents_table(&alive));
    if removed > 0 {
        eprintln!("({removed} dead agent(s) pruned)");
    }
}

fn cmd_agents_kill(agent_id: &str) {
    let agents_path = home().join(".claude/agents.json");
    let agents = tasks::load_agents(&agents_path);

    let agent = agents.iter().find(|a| a["id"].as_str() == Some(agent_id));
    let agent = match agent {
        Some(a) => a.clone(),
        None => {
            eprintln!("{}", serde_json::json!({"ok": false, "error": format!("agent {agent_id} not found")}));
            std::process::exit(1);
        }
    };

    let pid = agent["pid"].as_u64().unwrap_or(0) as u32;
    let tmux_target = agent["tmux_target"].as_str().unwrap_or("");
    let task_id = agent["task_id"].as_str().unwrap_or("");

    // Try graceful kill via tmux C-c first
    if !tmux_target.is_empty() {
        Command::new("tmux")
            .args(["send-keys", "-t", tmux_target, "C-c"])
            .output()
            .ok();
        // Wait briefly for graceful exit
        std::thread::sleep(std::time::Duration::from_secs(3));
    }

    // Check if still alive
    if pid > 0 && tasks::is_pid_alive(pid) {
        // Send SIGTERM
        Command::new("kill").args(["-15", &pid.to_string()]).output().ok();
        std::thread::sleep(std::time::Duration::from_secs(2));

        // If still alive, SIGKILL
        if tasks::is_pid_alive(pid) {
            Command::new("kill").args(["-9", &pid.to_string()]).output().ok();
        }
    }

    // Remove from agents.json
    let remaining: Vec<_> = agents
        .into_iter()
        .filter(|a| a["id"].as_str() != Some(agent_id))
        .collect();
    tasks::save_agents(&agents_path, &remaining).ok();

    // Optionally reset task to pending
    if !task_id.is_empty() {
        let tf = find_tasks_file();
        if let Some(tf) = tf {
            let mut val = tasks::load_raw(&tf).unwrap_or_default();
            let idx = val["tasks"]
                .as_array()
                .and_then(|arr| arr.iter().position(|t| t["id"].as_str() == Some(task_id)));
            if let Some(idx) = idx {
                val["tasks"][idx]["status"] = serde_json::json!("pending");
                val["tasks"][idx]["started"] = serde_json::Value::Null;
                tasks::save_tasks(&tf, &val).ok();
            }
        }
    }

    println!("{}", serde_json::json!({
        "ok": true,
        "killed": agent_id,
        "task_reset": task_id
    }));
}

fn cmd_queue(max: usize, auto: bool) {
    let tf = find_tasks_file().unwrap_or_else(|| {
        eprintln!("{}", serde_json::json!({"ok": false, "error": "tasks.json not found"}));
        std::process::exit(1);
    });
    let data = tasks::load_tasks(&tf).unwrap_or_else(|e| {
        eprintln!("{}", serde_json::json!({"ok": false, "error": e}));
        std::process::exit(1);
    });

    let candidates = tasks::queue_candidates(&data.tasks, max);

    if candidates.is_empty() {
        println!("No unblocked tasks in queue.");
        return;
    }

    if auto {
        if !tasks::is_in_tmux() {
            eprintln!("{}", serde_json::json!({
                "ok": false, "error": "tmux required for --auto. Run without --auto to see candidates."
            }));
            std::process::exit(1);
        }
        // Spawn each candidate
        for c in &candidates {
            let id = c["id"].as_str().unwrap_or("");
            eprintln!("Spawning {id}...");
            let result = Command::new(std::env::current_exe().unwrap())
                .args(["run", id, "--spawn"])
                .output();
            match result {
                Ok(o) => {
                    let out = String::from_utf8_lossy(&o.stdout);
                    let err = String::from_utf8_lossy(&o.stderr);
                    if o.status.success() {
                        println!("{out}");
                    } else {
                        eprintln!("  Failed: {err}");
                    }
                }
                Err(e) => eprintln!("  Error: {e}"),
            }
        }
    } else {
        // Display candidates as table
        println!("{:<10} {:<35} {:<5} {:<5} {:<10} {:<6} {:<7}",
            "ID", "SUBJECT", "PRI", "EFF", "STREAM", "SCORE", "MODEL");
        for c in &candidates {
            let id = c["id"].as_str().unwrap_or("?");
            let subject = c["subject"].as_str().unwrap_or("?");
            let subject_short = if subject.len() > 33 { &subject[..33] } else { subject };
            let pri = c["priority"].as_str().unwrap_or("—");
            let eff = c["effort"].as_str().unwrap_or("—");
            let stream = c["stream"].as_str().unwrap_or("—");
            let score = c["score"].as_f64().unwrap_or(0.0);
            let model = c["model"].as_str().unwrap_or("?");
            println!("{:<10} {:<35} {:<5} {:<5} {:<10} {:<6.2} {:<7}",
                id, subject_short, pri, eff, stream, score, model);
        }
        println!("\nRun with --auto to spawn agents on all, or: brana run <ID> --spawn");
    }
}

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
