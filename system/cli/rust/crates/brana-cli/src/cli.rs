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
    Dev,
    Ops,
    Research,
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
    Initiative,
}

#[derive(Clone, ValueEnum)]
pub enum TaskKind {
    Feature,
    Fix,
    Refactor,
    Research,
    Docs,
    Design,
    Ops,
}

#[derive(Clone, ValueEnum)]
pub enum TaskWorkType {
    Implement,
    Research,
    Design,
    Ops,
    Review,
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
    /// Transcribe audio file to text (whisper.cpp, local — requires libwhisper.so.1 on LD_LIBRARY_PATH)
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
    /// RSS/Atom feed polling and monitoring
    Feed {
        #[command(subcommand)]
        cmd: FeedCmd,
    },
    /// Gmail newsletter subscription management (IMAP)
    Inbox {
        #[command(subcommand)]
        cmd: InboxCmd,
    },
    /// Skill discovery and routing
    Skills {
        #[command(subcommand)]
        cmd: SkillsCmd,
    },
    /// Session handoff notes — read, list, or locate
    Handoff {
        #[command(subcommand)]
        cmd: Option<HandoffCmd>,
    },
    /// Unified session state management
    Session {
        #[command(subcommand)]
        cmd: SessionCmd,
    },
    /// Knowledge base management — reindex, status
    Knowledge {
        #[command(subcommand)]
        cmd: KnowledgeCmd,
    },
    /// Knowledge graph operations (ontology-aware)
    Graph {
        #[command(subcommand)]
        cmd: GraphCmd,
    },
    /// Reference doc generation — generate docs/reference/ from source metadata
    Reference {
        #[command(subcommand)]
        cmd: ReferenceCmd,
    },
    /// Append-only JSONL decision log
    Decisions {
        #[command(subcommand)]
        cmd: DecisionsCmd,
    },
    /// How to deploy brana (hint — deploy = merge to main)
    Deploy,
    /// Signal ratings dashboard — view ratings.jsonl breakdown and recent signals
    Ratings {
        /// Max recent signals to show (default 10)
        #[arg(long, default_value = "10")]
        last: usize,
        /// Output raw JSON instead of human-readable dashboard
        #[arg(long)]
        json: bool,
    },
}

#[derive(Subcommand)]
pub enum ReferenceCmd {
    /// Generate docs/reference/ from skills, agents, hooks, rules, commands frontmatter
    Generate {
        /// Output directory (default: docs/reference/)
        #[arg(long)]
        output_dir: Option<std::path::PathBuf>,
        /// Check mode: report what would change, exit 1 if changes needed
        #[arg(long)]
        check: bool,
    },
}

#[derive(Subcommand)]
pub enum DecisionsCmd {
    /// Append an entry to the decision log
    Log {
        /// Agent or author name (e.g. "main", "session-end")
        agent: String,
        /// Entry type: decision | finding | concern | action | error | cost
        #[arg(value_name = "TYPE")]
        entry_type: String,
        /// Content / message
        content: String,
        /// Severity level (e.g. LOW, HIGH) — stored uppercased
        #[arg(long)]
        severity: Option<String>,
        /// Comma-separated refs (e.g. task IDs "t-001,t-002")
        #[arg(long)]
        refs: Option<String>,
        /// Target (e.g. a file path or task ID)
        #[arg(long)]
        target: Option<String>,
    },
    /// Read and filter decision log entries
    Read {
        /// Show only the last N entries
        #[arg(long)]
        last: Option<usize>,
        /// Filter by entry type
        #[arg(long = "type", value_name = "TYPE")]
        entry_type: Option<String>,
        /// Filter by agent name
        #[arg(long)]
        agent: Option<String>,
        /// Filter by severity
        #[arg(long)]
        severity: Option<String>,
        /// Output as JSONL (one entry per line)
        #[arg(long)]
        json: bool,
    },
    /// Archive entries older than N days to archive/ subdirectory
    Archive {
        /// Days threshold (default: 30)
        #[arg(long, default_value = "30")]
        days: u64,
        /// Show what would be archived without moving files
        #[arg(long)]
        dry_run: bool,
    },
}

#[derive(Subcommand)]
pub enum KnowledgeCmd {
    /// Reindex knowledge base into ruflo memory
    Reindex {
        /// Only index git-changed files (for post-commit hook)
        #[arg(long)]
        changed: bool,
        /// Index pattern files from auto-memory dirs instead of knowledge docs
        #[arg(long)]
        patterns: bool,
        /// Specific files to index (default: all 7 categories)
        #[arg(trailing_var_arg = true)]
        files: Vec<PathBuf>,
    },
    /// Show knowledge index status (entry count, last indexed)
    Status,
    /// Semantic search against the ruflo knowledge namespace
    Search {
        /// Search query
        query: String,
        /// Max results to return (default 10)
        #[arg(long, default_value = "10")]
        limit: usize,
        /// Ruflo namespace to search (default: knowledge)
        #[arg(long, default_value = "knowledge")]
        namespace: String,
        /// Output raw JSON instead of human-readable text
        #[arg(long)]
        json: bool,
    },
    /// Run the inbox→dimensions pipeline (Tier 1/2/3 processing)
    Process {
        /// Tier 1: score unprocessed LinkedIn URLs for relevance (batch ≤50)
        #[arg(long)]
        tier1: bool,
        /// Tier 2: assign tier1-passed URLs to dimension clusters, produce report
        #[arg(long)]
        tier2: bool,
        /// Tier 3: synthesise an approved cluster into a draft dimension doc
        #[arg(long)]
        draft: Option<String>,
        /// Print the current cluster report
        #[arg(long)]
        report: bool,
        /// Show pipeline state summary (counts by tier, draft cap status)
        #[arg(long)]
        status: bool,
        /// Remove a URL from the processed index so it re-enters the pipeline
        #[arg(long)]
        reset_url: Option<String>,
        /// Print planned actions without writing anything
        #[arg(long)]
        dry_run: bool,
    },
    /// Promote a draft dimension doc to accepted (moves to dimensions/, updates frontmatter)
    Promote {
        /// Path to the draft file (relative to brana-knowledge/ or absolute)
        draft_path: PathBuf,
        /// Print planned actions without writing anything
        #[arg(long)]
        dry_run: bool,
    },
}

#[derive(Subcommand)]
pub enum GraphCmd {
    /// Build/rebuild spec-graph.json from docs + ontology
    Build {
        /// Output path (default: docs/spec-graph.json)
        #[arg(long)]
        output: Option<PathBuf>,
    },
    /// List orphan nodes (zero edges). Shows only structural orphans by default.
    Orphans {
        /// Show all orphans including expected leaf nodes (dimensions, guides, research)
        #[arg(long)]
        all: bool,
    },
    /// Query nodes by type or relationship
    Query {
        /// Filter by entity type (Dimension, ADR, etc.)
        #[arg(long = "type")]
        node_type: Option<String>,
        /// Filter by relationship type (depends_on, informs, etc.)
        #[arg(long)]
        rel: Option<String>,
    },
    /// Find path between two nodes
    Path {
        /// Source node (exact path or fuzzy match)
        from: String,
        /// Target node (exact path or fuzzy match)
        to: String,
    },
    /// Show graph statistics
    Stats,
    /// Validate graph against ontology axioms
    Validate,
}

#[derive(Subcommand)]
pub enum HandoffCmd {
    /// Show the latest handoff entry (default)
    Last {
        /// Number of entries to show (default 1)
        #[arg(short, long, default_value = "1")]
        n: usize,
    },
    /// List all entry headings
    List,
    /// Print the resolved handoff file path
    Path,
}

#[derive(Subcommand)]
pub enum SessionCmd {
    /// Write session state from a JSON file (validate, archive, atomic write)
    Write {
        /// Path to JSON file with session state
        #[arg(long)]
        file: Option<PathBuf>,
        /// Auto-capture minimal state (session-end safety net)
        #[arg(long)]
        minimal: bool,
    },
    /// Read latest session state
    Read {
        /// Output raw JSON instead of human-readable text
        #[arg(long)]
        json: bool,
    },
    /// List past sessions from history
    History {
        /// Max entries to show (default 10)
        #[arg(long, default_value = "10")]
        limit: usize,
    },
    /// Print the session-state.json path
    Path,
    /// One-time migration: parse session-handoff.md → bootstrap JSON
    Migrate,
    /// Mark current session state as consumed (set consumed_at to now)
    MarkConsumed,
    /// Friction classifier — analyze session history for patterns
    Insights {
        /// Max sessions to analyse (default 30)
        #[arg(long, default_value = "30")]
        limit: usize,
        /// Output raw JSON instead of human-readable table
        #[arg(long)]
        json: bool,
    },
}

#[derive(Subcommand)]
pub enum SkillsCmd {
    /// Recommend skills for a task based on context matching
    Suggest {
        /// Task ID (e.g., t-123) — reads metadata for matching
        #[arg(long)]
        task: Option<String>,
        /// Free-text query (alternative to --task)
        #[arg(long)]
        query: Option<String>,
    },
    /// Search local skills by keyword
    Search {
        /// Search terms
        query: String,
    },
    /// List all local skills with metadata
    List {
        /// Human-readable grouped table instead of JSON
        #[arg(long)]
        human: bool,
    },
    /// Reindex skills into ruflo memory for semantic routing
    Reindex {
        /// Only reindex skills modified since last run
        #[arg(long)]
        changed: bool,
        /// Force full reindex, bypassing the mtime check even when --changed is set
        #[arg(long)]
        force: bool,
    },
    /// Show skill invocation counts from session history
    Usage {
        /// Rolling window in days (default: 30)
        #[arg(long, default_value = "30")]
        days: u64,
        /// Flag skills below this count as cull candidates (default: 5)
        #[arg(long, default_value = "5")]
        cull_threshold: u64,
        /// Output raw JSON instead of human-readable table
        #[arg(long)]
        json: bool,
    },
    /// Emit a Mermaid flowchart of skill groups and dependencies
    Graph,
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
        /// Filter by stream (deprecated — use --kind)
        #[arg(long, value_enum)]
        stream: Option<TaskStream>,
        /// Filter by work kind: feature, fix, refactor, research, docs, design, ops
        #[arg(long, value_enum)]
        kind: Option<TaskKind>,
        /// Max results to show (default 5)
        #[arg(long, alias = "top", default_value = "5")]
        limit: usize,
        #[arg(long, value_enum)]
        priority: Option<TaskPriority>,
        /// Filter by type (task, subtask, phase, milestone, initiative)
        #[arg(long = "type", value_enum)]
        task_type: Option<TaskType>,
        #[arg(long, value_enum)]
        effort: Option<TaskEffort>,
        /// Filter by parent ID
        #[arg(long)]
        parent: Option<String>,
        /// Output JSON array instead of themed list
        #[arg(long)]
        json: bool,
    },
    /// Filter tasks (AND logic)
    Query {
        /// Tag filter (comma-separated for AND: "dx,cli")
        #[arg(short, long)]
        tag: Option<String>,
        #[arg(short, long, value_enum)]
        status: Option<TaskStatus>,
        /// Filter by stream (deprecated — use --kind)
        #[arg(long, value_enum)]
        stream: Option<TaskStream>,
        /// Filter by work kind: feature, fix, refactor, research, docs, design, ops
        #[arg(long, value_enum)]
        kind: Option<TaskKind>,
        #[arg(short, long, value_enum)]
        priority: Option<TaskPriority>,
        #[arg(short, long, value_enum)]
        effort: Option<TaskEffort>,
        #[arg(long)]
        search: Option<String>,
        #[arg(long)]
        count: bool,
        /// Output format: json (default), ids, themed
        #[arg(long, default_value = "json")]
        output: String,
        /// Shorthand for --output json (alias for scripting ergonomics)
        #[arg(long)]
        json: bool,
        /// Filter by type (task, subtask, phase, milestone, initiative)
        #[arg(long = "type", value_enum)]
        task_type: Option<TaskType>,
        /// Filter by parent ID
        #[arg(long)]
        parent: Option<String>,
        /// Filter by branch field
        #[arg(long)]
        branch: Option<String>,
        /// Filter by work type: implement, research, design, ops, review
        #[arg(long, value_enum)]
        work_type: Option<TaskWorkType>,
        /// Filter by initiative slug
        #[arg(long)]
        initiative: Option<String>,
    },
    /// Smart daily pick
    Focus {
        /// Number of tasks to show (default 3)
        #[arg(long, default_value = "3")]
        top: usize,
        /// Output JSON array instead of themed list
        #[arg(long)]
        json: bool,
        /// Filter by work type: implement, research, design, ops, review
        #[arg(long, value_enum)]
        work_type: Option<TaskWorkType>,
        /// Override active initiative slug (defaults to tasks-config.json active_initiative)
        #[arg(long)]
        initiative: Option<String>,
    },
    /// Free-text search
    Search {
        text: String,
        /// Output JSON array instead of themed list
        #[arg(long)]
        json: bool,
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
    /// Bulk-close pending tasks that have feat/fix commits on main
    TriageStale {
        /// Show matches without closing anything
        #[arg(long)]
        dry_run: bool,
        /// Tasks to show per confirmation prompt
        #[arg(long, default_value = "10")]
        batch: usize,
        /// Close all matches without prompting
        #[arg(long)]
        yes: bool,
        /// Override repo path (default: CWD)
        #[arg(long)]
        git_dir: Option<std::path::PathBuf>,
        #[arg(long)]
        file: Option<std::path::PathBuf>,
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
        /// Value (use +val/-val for array fields; prefix with -- for values starting with -)
        value: String,
        /// Append to text fields instead of replacing
        #[arg(long)]
        append: bool,
        /// Path to tasks.json (auto-detected if omitted)
        #[arg(long)]
        file: Option<PathBuf>,
    },
    /// Set the active initiative in tasks-config.json
    #[command(name = "set-active")]
    SetActive {
        /// Initiative slug (e.g. "cc-alignment", "notebooklm")
        slug: String,
    },
    /// Add a new task from JSON or shorthand flags
    Add {
        /// Task JSON (subject, type required; id auto-assigned). Use @filepath to read from file, - to read from stdin.
        #[arg(long)]
        json: Option<String>,
        /// Task subject (shorthand, used when --json is omitted)
        #[arg(long)]
        subject: Option<String>,
        /// Stream: roadmap, bugs, tech-debt, docs, experiments, research (deprecated — use --kind)
        #[arg(long)]
        stream: Option<String>,
        /// Work kind: feature, fix, refactor, research, docs, design, ops
        #[arg(long)]
        kind: Option<String>,
        /// Task type: phase, milestone, task, subtask, initiative
        #[arg(long = "type")]
        task_type: Option<String>,
        /// Comma-separated tags
        #[arg(long)]
        tags: Option<String>,
        /// Description
        #[arg(long)]
        description: Option<String>,
        /// Effort: S, M, L, XL
        #[arg(long)]
        effort: Option<String>,
        /// Parent task ID
        #[arg(long)]
        parent: Option<String>,
        /// Priority: P0, P1, P2, P3
        #[arg(long)]
        priority: Option<String>,
        /// Rich context — why the task matters, prior decisions, constraints. Required for M+ effort per memory rule.
        #[arg(long)]
        context: Option<String>,
        /// Path to tasks.json (auto-detected if omitted)
        #[arg(long)]
        file: Option<PathBuf>,
        /// Initiative slug (e.g., "cc-alignment", "notebooklm")
        #[arg(long)]
        initiative: Option<String>,
        /// Work type: implement, research, design, ops, review
        #[arg(long)]
        work_type: Option<String>,
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
    /// Delete a task by ID (removes from blocked_by of other tasks)
    Delete {
        /// Task ID (e.g. t-034)
        task_id: String,
        /// Also delete all children (tasks with parent == this ID)
        #[arg(long)]
        cascade: bool,
        /// Path to tasks.json (auto-detected if omitted)
        #[arg(long)]
        file: Option<PathBuf>,
    },
    /// Move a task to a new parent
    Move {
        /// Task ID (e.g. t-034)
        task_id: String,
        /// New parent ID (or "null" to make root-level)
        #[arg(long)]
        parent: String,
        /// Path to tasks.json (auto-detected if omitted)
        #[arg(long)]
        file: Option<PathBuf>,
    },
    /// Archive completed phases (move to tasks-archive.json)
    Archive {
        /// Phase ID to archive (omit to list archivable phases)
        phase_id: Option<String>,
        /// Path to tasks.json (auto-detected if omitted)
        #[arg(long)]
        file: Option<PathBuf>,
    },
    /// Sync tasks with GitHub Issues or Linear (--linear flag)
    Sync {
        /// Show what would happen without making changes
        #[arg(long)]
        dry_run: bool,
        /// Force re-sync even if issue ID is already set
        #[arg(long)]
        force: bool,
        /// Max parallel GitHub API calls (1-20, ignored when --linear)
        #[arg(long, default_value = "10")]
        parallel: usize,
        /// Sync to Linear instead of GitHub Issues
        #[arg(long)]
        linear: bool,
        /// Narrow Linear sync to a single project slug (e.g. palco, dgrx)
        #[arg(long, requires = "linear")]
        project: Option<String>,
    },
    /// Mark a task as completed (alias for `set <id> status completed`)
    Complete {
        /// Task ID (e.g. t-463)
        task_id: String,
        /// Path to tasks.json (auto-detected if omitted)
        #[arg(long)]
        file: Option<PathBuf>,
    },
}

#[derive(Subcommand)]
pub enum OpsCmd {
    /// Dashboard: all jobs, last run, health
    Status {
        /// Include remote environments (Oracle VM via SSH)
        #[arg(long)]
        all: bool,
    },
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

#[derive(Subcommand)]
pub enum FeedCmd {
    /// Register an RSS/Atom feed to monitor
    Add {
        /// Feed URL
        url: String,
        /// Human-readable name (derived from URL if omitted)
        #[arg(long)]
        name: Option<String>,
        /// Action on new entries: log (default) or task
        #[arg(long, default_value = "log")]
        action: String,
    },
    /// List all registered feeds
    List,
    /// Poll one or all feeds for new entries
    Poll {
        /// Feed name to poll (omit for all)
        name: Option<String>,
        /// Poll all feeds
        #[arg(long)]
        all: bool,
    },
    /// Remove a registered feed
    Remove {
        /// Feed name
        name: String,
    },
    /// Show last poll results per feed
    Status,
}

#[derive(Subcommand)]
pub enum InboxCmd {
    /// Register a newsletter subscription
    Add {
        /// Subscription name (e.g., "stratechery")
        name: String,
        /// Sender email address to match
        #[arg(long)]
        from: String,
        /// Expected frequency: daily, weekly, monthly
        #[arg(long, default_value = "weekly")]
        frequency: String,
        /// Account name (default: first account)
        #[arg(long)]
        account: Option<String>,
    },
    /// List registered newsletter subscriptions
    List,
    /// Poll Gmail for new newsletter emails
    Poll {
        /// Gmail label/folder to check (overrides account label)
        #[arg(long)]
        label: Option<String>,
        /// Poll only this account (default: all enabled)
        #[arg(long)]
        account: Option<String>,
    },
    /// Remove a newsletter subscription
    Remove {
        /// Subscription name
        name: String,
    },
    /// Show arrival stats (expected vs actual per subscription)
    Status,
    /// Add a Gmail account
    AddAccount {
        /// Account name (e.g., "personal", "work")
        name: String,
        /// Gmail address for this account
        #[arg(long)]
        user: String,
        /// Gmail label to poll (default: Newsletters)
        #[arg(long, default_value = "Newsletters")]
        label: String,
    },
    /// Store or update App Password in system keyring
    SetPassword {
        /// Account name
        name: String,
    },
}
