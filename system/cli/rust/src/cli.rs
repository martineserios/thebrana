//! Pure clap derive structs for the brana CLI.
//! No logic — only argument parsing definitions.

use clap::{Parser, Subcommand, ValueEnum};
use std::path::PathBuf;

// ── ValueEnum types for parse-time validation ──────────────────────────

#[derive(Clone, ValueEnum)]
pub enum TaskStatus {
    Pending,
    #[value(name = "in_progress")]
    InProgress,
    Completed,
    Cancelled,
}

#[derive(Clone, ValueEnum)]
pub enum TaskStream {
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
pub enum TaskPriority {
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
pub enum TaskEffort {
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
pub enum TaskType {
    Task,
    Subtask,
    Phase,
    Milestone,
}

#[derive(Clone, ValueEnum)]
pub enum BurndownPeriod {
    Day,
    Week,
    Month,
}

/// Convert ValueEnums to the string form used in tasks.json.
pub fn ve_str<T: ValueEnum>(v: &Option<T>) -> Option<String> {
    v.as_ref().map(|val| {
        val.to_possible_value().unwrap().get_name().to_string()
    })
}

#[derive(Parser)]
#[command(name = "brana", version, about = "Brana system CLI — fast standalone interface")]
pub struct Cli {
    #[command(subcommand)]
    pub command: Commands,
}

#[derive(Subcommand)]
pub enum Commands {
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
    /// Transcribe audio file to text (whisper, local, pure Rust)
    Transcribe {
        /// Path to audio file (.wav, .mp3, .ogg, .m4a)
        file: PathBuf,
        /// Model size: tiny, base, small (default: base)
        #[arg(long, default_value = "base")]
        model: String,
    },
    /// Manage tracked large files (models, assets, datasets)
    Files {
        #[command(subcommand)]
        cmd: FilesCmd,
    },
}

#[derive(Subcommand)]
pub enum FilesCmd {
    /// List all tracked files
    List,
    /// Show status of tracked files (ok/missing/modified)
    Status,
    /// Register a file in the manifest
    Add {
        /// Logical name for the file (e.g., "whisper-base")
        name: String,
        /// Path to the file
        path: PathBuf,
        /// Remote download URL
        #[arg(long)]
        url: Option<String>,
        /// R2 key for push/pull
        #[arg(long)]
        r2_key: Option<String>,
    },
    /// Download missing/modified files from their remote sources
    Pull,
    /// Push tracked files to R2 remote storage
    Push {
        /// rclone remote name (default: "brana-r2")
        #[arg(long, default_value = "brana-r2")]
        remote: String,
    },
}

#[derive(Subcommand)]
pub enum AgentsCmd {
    /// Kill an active agent
    Kill {
        /// Agent ID (from brana agents output)
        agent_id: String,
    },
}

#[derive(Subcommand)]
pub enum BacklogCmd {
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
    /// Full roadmap tree (phases -> milestones -> tasks)
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
pub enum OpsCmd {
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
