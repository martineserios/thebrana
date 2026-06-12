# MODEL-001: brana-core Bounded Contexts

> Created 2026-04-05. Source: idea doc `docs/ideas/brana-cli-mcp-layer.md`, codebase inventory.

## Purpose

Define the bounded contexts, aggregate roots, ubiquitous language, and domain events for `brana-core` — the shared library that both `brana-cli` and `brana-mcp` consume. This model is the source of truth for module boundaries.

---

## Bounded Contexts

Nine contexts, grouped by cohesion. Each becomes a top-level module in `brana-core`.

### 1. Backlog (`core::backlog`)

The central domain. Manages the task lifecycle — creation, querying, mutation, classification, and analysis.

**Aggregate root:** `TaskStore` (owns the tasks.json file and all operations on it)

**Entities:**
- `Task` — id, subject, description, status, priority, effort, stream, type, tags, parent, blocked_by, branch, context, notes, created, started, completed, order, execution, github_issue, build_step, strategy
- `TasksFile` — project name + Vec<Task>

**Value objects:**
- `TaskStatus` — pending | in_progress | completed | cancelled
- `TaskClassification` — done | active | blocked | parked | pending (computed)
- `TaskPriority` — P0 | P1 | P2 | P3
- `TaskEffort` — S | M | L | XL
- `TaskStream` — roadmap | bugs | tech-debt | docs | experiments | research | personal
- `TaskType` — task | subtask | phase | milestone
- `FocusScore` — f64 (priority weight + staleness + effort + blocking depth)
- `BurndownBucket` — date range + created count + completed count

**Operations (pure functions on task data):**
- `load(path) -> TasksFile`
- `save(path, TasksFile)`
- `filter(tasks, FilterCriteria) -> Vec<Task>`
- `sort_by_priority(tasks)`
- `classify(task, all) -> TaskClassification`
- `focus_score(task) -> FocusScore`
- `blocked_chain(task, all) -> Vec<TaskId>` (with cycle detection)
- `stale_tasks(tasks, threshold_days) -> Vec<Task>`
- `burndown(tasks, period) -> Vec<BurndownBucket>`
- `compute_stats(tasks) -> Stats`
- `build_tree(tasks) -> Vec<TreeNode>`
- `subtree(tasks, root_id) -> TreeNode`
- `tag_inventory(tasks) -> Vec<(tag, status_counts)>`
- `search(tasks, needle) -> Vec<Task>`
- `next_id(tasks) -> TaskId`
- `set_field(task, field, value, append)`
- `add_task(store, task_data) -> Task`
- `delete_task(store, id, cascade) -> usize`
- `move_task(store, id, new_parent)`
- `archive_phase(store, phase_id) -> (archived_tasks, count)`
- `rollup_candidates(tasks) -> Vec<TaskId>`
- `perform_rollup(store, dry_run) -> Vec<TaskId>`
- `validate_schema(tasks) -> Vec<ValidationError>`
- `find_duplicate_ids(tasks) -> Vec<TaskId>`
- `queue_candidates(tasks, max) -> Vec<Task>` (unblocked + scored)
- `complexity_score(task) -> f64`
- `recommended_model(score) -> ModelName`
- `validate_runnable(task, all) -> Result<()>`
- `branch_for_task(task) -> String`

**State files owned:**
- `.claude/tasks.json` (primary, worktree-aware via git-common-dir)
- `.claude/tasks-archive.json`
- `.claude/tasks-portfolio.json`

**Context boundary:** Backlog never calls feed, inbox, files, or scheduler directly. It is the most consumed context (by sync, agents, CLI, MCP).

---

### 2. Feeds (`core::feeds`)

RSS/Atom feed polling with conditional HTTP and entry deduplication.

**Aggregate root:** `FeedRegistry` (owns feeds.json and all feed state)

**Entities:**
- `Feed` — name, url, action (log | task), enabled
- `FeedState` — etag, last_modified, last_entry_ids, last_poll, new_count

**Value objects:**
- `FeedAction` — Log | Task
- `FeedLogEntry` — feed, title, link, published, polled_at

**Operations:**
- `load_feeds() -> Vec<Feed>`
- `save_feeds(feeds)`
- `add_feed(url, name, action) -> Feed`
- `remove_feed(name)`
- `load_state(name) -> FeedState`
- `save_state(name, state)`
- `poll_one(feed) -> PollResult` (HTTP with If-None-Match / If-Modified-Since)
- `poll_all() -> Vec<PollResult>`
- `append_log(entry: FeedLogEntry)`
- `status() -> Vec<FeedStatus>`

**State files owned:**
- `~/.claude/scheduler/feeds.json`
- `~/.claude/scheduler/state/{name}.json`
- `~/.claude/scheduler/feed-log.jsonl`

**Cross-context interaction:** When action = "task", feeds emits a `NewFeedEntry` event. The CLI layer translates this into a backlog `add_task` call. Core never calls backlog directly — the integration point is in the application layer (CLI or MCP).

---

### 3. Inbox (`core::inbox`)

Gmail newsletter monitoring via IMAP with multi-account support.

**Aggregate root:** `InboxRegistry` (owns inbox.json and all account state)

**Entities:**
- `Account` — name, imap_host, imap_port, user, password_env, label, enabled, subscriptions
- `Subscription` — name, from, frequency (daily | weekly | monthly), enabled
- `InboxState` — last_poll, last_uid, unmatched_count

**Value objects:**
- `Frequency` — Daily | Weekly | Monthly
- `InboxLogEntry` — subscription, from, subject, date, matched, polled_at
- `CredentialSource` — Keyring | EnvVar | Interactive

**Operations:**
- `load_config() -> InboxConfig`
- `save_config(config)`
- `add_account(name, user, label)`
- `add_subscription(name, from, frequency, account)`
- `remove_subscription(name)`
- `load_state(account) -> InboxState`
- `save_state(account, state)`
- `poll_account(account, label_override) -> PollResult` (IMAP + TLS)
- `append_log(entry: InboxLogEntry)`
- `status() -> Vec<AccountStatus>`

**External dependencies (passed in, not owned):**
- Credential provider trait (keyring, env var, or interactive — injected by CLI)
- IMAP connection (native-tls — could be abstracted behind a trait for testing)

**State files owned:**
- `~/.claude/scheduler/inbox.json`
- `~/.claude/scheduler/state/inbox-{account}.json`
- `~/.claude/scheduler/inbox-log.jsonl`

---

### 4. Files (`core::files`)

Large file tracking with content-addressed storage and remote sync.

**Aggregate root:** `Manifest` (owns .brana-files.json)

**Entities:**
- `FileEntry` — path, sha256, size, url, r2_key

**Value objects:**
- `FileState` — Ok | Missing | Modified { actual_hash } | Error
- `FileStatus` — name, entry, state
- `PullResult` — downloaded, skipped, failed
- `PushResult` — uploaded, skipped, failed

**Operations:**
- `Manifest::load(project_dir) -> Manifest`
- `Manifest::save(project_dir)`
- `Manifest::add(name, entry)`
- `Manifest::status(project_dir) -> Vec<FileStatus>`
- `file_sha256(path) -> String`
- `pull(manifest, project_dir) -> PullResult`
- `push(manifest, project_dir, remote) -> PushResult`

**External dependencies (passed in):**
- Download function (currently shells out to `curl` — CLI concern)
- Upload function (currently shells out to `rclone` — CLI concern)

**State files owned:**
- `.brana-files.json` (project root)

---

### 5. Scheduler (`core::scheduler`)

Job configuration, health monitoring, and collision detection. Ported from `ops.py`.

**Aggregate root:** `SchedulerConfig` (owns scheduler.json)

**Entities:**
- `Job` — name, schedule (cron), enabled, command, project, type

**Value objects:**
- `JobStatus` — Success | Failed | Timeout | Skipped
- `JobRun` — job_name, status, timestamp
- `HealthReport` — failures_24h, skipped_jobs, stale_jobs
- `Collision` — schedule, project, jobs (multiple jobs with same schedule+project)
- `DriftReport` — added, removed, changed (template vs live comparison)

**Operations:**
- `load_config() -> SchedulerConfig`
- `load_status() -> Vec<JobRun>`
- `check_health(config, status) -> HealthReport`
- `detect_collisions(config) -> Vec<Collision>`
- `drift_compare(config, template) -> DriftReport`
- `failure_history(status, hours) -> Vec<JobRun>`

**State files read (not owned — written by systemd runner):**
- `~/.claude/scheduler/scheduler.json`
- `~/.claude/scheduler/last-status.json`
- `~/.claude/scheduler/logs/`

**External dependencies (CLI layer):**
- `systemctl` commands for timer management (enable, disable, status)
- Template file at `system/scheduler/scheduler.template.json`

**Context boundary:** Pure analysis on config/status data. Never mutates scheduler state (that's systemd's job). Never touches backlog.

---

### 6. Sync (`core::sync`)

Bidirectional task-to-GitHub-Issue synchronization. Ported from `task-sync.py`.

**Aggregate root:** `SyncState` (owns issue map + hash cache)

**Value objects:**
- `SyncPlan` — Vec<SyncAction>
- `SyncAction` — Create { task } | Update { task, issue_num } | Close { issue_num }
- `IssueBody` — markdown string built from task data
- `LabelSet` — stream labels + tag labels
- `FieldMapping` — task field to GitHub Project field mapping
- `SyncHash` — per-task hash for change detection

**Operations:**
- `load_issue_map(path) -> HashMap<TaskId, IssueNumber>`
- `save_issue_map(path, map)`
- `load_hashes(path) -> HashMap<TaskId, SyncHash>`
- `save_hashes(path, hashes)`
- `build_labels(task) -> LabelSet`
- `build_body(task, task_map) -> IssueBody`
- `compute_hash(task) -> SyncHash`
- `plan_sync(tasks, issue_map, hashes, config) -> SyncPlan`
- `field_mapping(task) -> FieldMapping`

**External dependencies (CLI layer):**
- `gh api` calls for issue create/update/close, label management, project field updates

**State files owned:**
- `.claude/task-issue-map.json`
- `.claude/task-sync-hashes.json`

**Context boundary:** Consumes backlog Task data (read-only). Never mutates tasks.json. The CLI layer executes the SyncPlan against GitHub.

---

### 7. Decisions (`core::decisions`)

Append-only structured decision log. Ported from `decisions.py`.

**Aggregate root:** `DecisionLog` (owns the JSONL session files)

**Value objects:**
- `EntryType` — Decision | Finding | Concern | Action | Error | Cost
- `LogEntry` — timestamp, agent, type, content, severity, refs, target
- `SessionId` — timestamp + PID + random

**Operations:**
- `log_entry(agent, type, content, severity?, refs?, target?) -> Path`
- `read_entries(filter: EntryFilter) -> Vec<LogEntry>`
- `archive(days, dry_run) -> ArchiveResult`

**State files owned:**
- `system/state/decisions/{date}-{session}.jsonl`
- `system/state/decisions/archive/`

**Context boundary:** Fully independent. No dependencies on other contexts.

---

### 8. Spec Graph (`core::spec_graph`)

Markdown cross-reference extraction and dependency graph building. Ported from `spec_graph.py`.

**Aggregate root:** `SpecGraph` (the computed graph)

**Value objects:**
- `GraphNode` — references, referenced_by, impl_files, guide_files, arch_files, ref_files
- `TypedEdge` — from, to, relationship_type
- `RelationshipType` — Assumes | Implements | Informs | Enriches | Supersedes
- `GraphMeta` — node_count, edge_count, impl_ref_count, orphan_count, typed_edge_count

**Operations:**
- `extract_links(content, source_path, repo_root) -> (references, impl_files)`
- `extract_typed_edges(content, source_path, repo_root) -> Vec<TypedEdge>`
- `collect_markdown_files(docs_dir, repo_root) -> HashMap<String, Path>`
- `build_graph(repo_root) -> SpecGraph`

**State files owned:**
- `docs/spec-graph.json` (output)

**Context boundary:** Read-only on the filesystem. No dependencies on other contexts.

---

### 9. Reference (`core::reference`)

Deterministic documentation generator from frontmatter metadata. Ported from `generate-reference.py`.

**Value objects:**
- `SkillMeta` — name, group, description, argument_hint, depends_on, allowed_tools, effort
- `AgentMeta` — name, model, description, tools, disallowed_tools
- `HookMeta` — event_type, matcher, command, timeout
- `RuleMeta` — name, description
- `CommandMeta` — name, description

**Operations:**
- `parse_frontmatter(path) -> HashMap<String, Value>`
- `generate_skills(root) -> String`
- `generate_agents(root) -> String`
- `generate_hooks(root) -> String`
- `generate_rules(root) -> String`
- `generate_commands(root) -> String`

**State files owned:**
- `docs/reference/skills.md` (output)
- `docs/reference/agents.md` (output)
- `docs/reference/hooks.md` (output)
- `docs/reference/rules.md` (output)
- `docs/reference/commands.md` (output)

**Context boundary:** Read-only on system/ files. No dependencies on other contexts.

---

### 10. Notify (`core::notify`)

General notification infrastructure — channel registry and message delivery. Defined by [ADR-054](../architecture/decisions/ADR-054-reminder-delivery-channels.md) §1; first consumer is reminder dispatch.

**Aggregate root:** `ChannelRegistry` (owns `~/.claude/notify-channels.json` — hand-edited, read-only to the CLI)

**Entity:** `Channel` — name, type, per-type settings (secrets file path, server, topic), enabled

**Value objects:**
- `ChannelType` — Telegram | Desktop | Ntfy (non-exhaustive; Calendar is a deferred future type)
- `DispatchResult` — Sent | Failed { reason }
- `RoutingRule` — priority → channel names (`defaults` map; `low: []` means never push)

**Operations:**
- `load_registry(path) -> Option<ChannelRegistry>` (missing file → None, dispatch becomes a no-op)
- `resolve(registry, explicit_channels, priority) -> Vec<Channel>` (explicit list → named; `["all"]` → broadcast; none/empty → priority defaults)
- `send(channel, message) -> DispatchResult` (telegram/ntfy via ureq; desktop via notify-send subprocess — absent/headless counts as Failed, never errors)

**State files owned:**
- `~/.claude/notify-channels.json` (read-only — humans edit it)

**Context boundary:** Reminders consumes Notify via the application layer (dispatch in `brana remind due --dispatch`). Notify never reads or mutates the reminder store. `brana-scheduler-notify.sh` is an explicit non-consumer (brana-independence firebreak, ADR-054 §1).

---

## Agents (not a core context)

Agent management (spawn, track, kill) is tightly coupled to the CLI's git worktree and tmux operations. It stays in `brana-cli`, not `brana-core`.

**Data types (CLI-only):**
- `AgentEntry` — task_id, pid, tmux_target, worktree, branch
- Agent operations: `load_agents`, `save_agents`, `prune_dead_agents`, `new_agent_entry`

**Rationale:** Agents depend on process management (PID checking, tmux), git worktrees, and interactive spawning. These are inherently CLI concerns with no MCP consumer.

---

## Cross-Context Dependencies

```
              +-----------+
              |  Backlog  |  <-- consumed by Sync (read-only)
              +-----------+
                    ^
                    | (event: NewFeedEntry → add_task, via app layer)
              +-----------+
              |   Feeds   |
              +-----------+

All other contexts are independent:

  Inbox       Files       Scheduler     Decisions     Spec Graph     Reference
  (standalone) (standalone) (standalone)  (standalone)  (standalone)   (standalone)
```

**Key rule:** Cross-context communication happens through the application layer (CLI or MCP), never within `brana-core`. Contexts share data types only when necessary (e.g., Sync reads `Task` from Backlog's types).

---

## Ubiquitous Language

| Term | Definition | Context |
|------|-----------|---------|
| **Task** | A unit of work with lifecycle (pending -> in_progress -> completed/cancelled) | Backlog |
| **Phase** | A grouping of milestones/tasks representing a major initiative | Backlog |
| **Milestone** | A checkpoint within a phase, grouping related tasks | Backlog |
| **Subtask** | A child task decomposed from a parent | Backlog |
| **Stream** | A work category (roadmap, bugs, tech-debt, docs, experiments, research) | Backlog |
| **Focus score** | Computed priority weighting: priority + staleness + effort + blocking depth | Backlog |
| **Blocked chain** | The transitive dependency path preventing a task from starting | Backlog |
| **Burndown** | Time-bucketed view of created vs completed tasks | Backlog |
| **Rollup** | Auto-completing a parent when all children are done | Backlog |
| **Classification** | Computed status: done, active, blocked, parked, pending | Backlog |
| **Feed** | An RSS/Atom source being monitored for new entries | Feeds |
| **Conditional poll** | HTTP request with ETag/Last-Modified to avoid re-fetching unchanged feeds | Feeds |
| **Subscription** | A newsletter sender being tracked within an inbox account | Inbox |
| **UID tracking** | IMAP message UID used to avoid re-processing emails | Inbox |
| **Manifest** | Content-addressed file registry (.brana-files.json) with SHA-256 hashes | Files |
| **File state** | Computed status: Ok, Missing, Modified, Error | Files |
| **Collision** | Two scheduler jobs with the same schedule on the same project | Scheduler |
| **Drift** | Difference between scheduler template and live config | Scheduler |
| **Sync plan** | Computed set of create/update/close actions for GitHub Issues | Sync |
| **Issue map** | Bidirectional mapping between task IDs and GitHub issue numbers | Sync |
| **Sync hash** | Per-task content hash for change detection (skip unchanged tasks) | Sync |
| **Decision log** | Append-only JSONL record of decisions, findings, concerns, and actions | Decisions |
| **Spec graph** | Directed graph of markdown document cross-references | Spec Graph |
| **Typed edge** | A labeled relationship between docs (assumes, implements, informs, enriches, supersedes) | Spec Graph |
| **Orphan** | A document with no incoming or outgoing references | Spec Graph |
| **Reference doc** | Auto-generated documentation from system/ frontmatter metadata | Reference |
| **Frontmatter** | YAML header block in markdown files containing structured metadata | Reference |
| **Store** | An aggregate root that owns a state file and all mutations to it | All |
| **Application layer** | CLI or MCP — the thin adapter that wires contexts together and handles I/O | Architecture |
| **CloseOrientation** | Why a session is closing: `continue`, `finish`, `patterns`, `abort` (v1). Forces the close weight — flag wins over auto-classification; each orientation pins a task-state target ([ADR-053](../architecture/decisions/ADR-053-close-oriented-modes.md)) | Session workflow |
| **Close weight** | How much close pipeline runs: NANO, LIGHT, INSTANT, FULL — auto-classified by `close-classify.sh` on bare invocation only ([ADR-052](../architecture/decisions/ADR-052-close-queue-architecture.md) §5) | Session workflow |

---

## Domain Events

Events that cross context boundaries. In `brana-core`, these are return values, not pub/sub. The application layer (CLI/MCP) decides what to do with them.

| Event | Source | Consumer | Payload |
|-------|--------|----------|---------|
| `NewFeedEntry` | Feeds (poll_one) | App layer -> Backlog (add_task) | feed_name, title, link, published |
| `TaskCompleted` | Backlog (set_field) | App layer -> Sync (plan update) | task_id, completed_date |
| `TaskCreated` | Backlog (add_task) | App layer -> Sync (plan create) | task |
| `PhaseArchived` | Backlog (archive_phase) | App layer -> cleanup | phase_id, archived_tasks |
| `RollupCompleted` | Backlog (perform_rollup) | App layer -> Sync (plan update) | Vec<task_id> |
| `PollCompleted` | Inbox (poll_account) | App layer -> logging | account, matched_count, unmatched_count |

---

## Shared Kernel

Types shared across multiple contexts (minimal — keep this small):

```rust
// core::common
pub type TaskId = String;      // "t-123", "ph-cli-arch"
pub type IssueNumber = u64;    // GitHub issue #
pub type SessionId = String;   // "{date}-{pid}-{random}"
```

Everything else stays within its bounded context. `Sync` imports `Task` from `Backlog` as a read-only dependency — it never mutates backlog state.

---

## What Stays Outside brana-core

| Concern | Location | Why |
|---------|----------|-----|
| CLI argument parsing (clap) | brana-cli | Presentation |
| ANSI themes, progress bars | brana-cli::theme | Presentation |
| `println!` formatting | brana-cli | Presentation |
| MCP tool definitions (#[tool]) | brana-mcp | Protocol adapter |
| JSON-RPC transport | brana-mcp | Protocol adapter |
| `systemctl` subprocess calls | brana-cli | External process |
| `gh api` subprocess calls | brana-cli | External process |
| `curl` / `rclone` subprocess calls | brana-cli | External process |
| Agent management (PID, tmux, worktrees) | brana-cli | Process lifecycle |
| Keyring interactive password entry | brana-cli | User interaction |
| `delegate_python()` | Deleted | Migration target |
