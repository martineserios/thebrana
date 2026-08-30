//! Shared task loading, filtering, and classification logic.
//! Used by brana (dispatcher), brana-query, and brana-fmt.

use serde::Deserialize;
use serde_json::Value;
use std::path::Path;


mod validation;
mod query;
mod role;
mod rollup;
mod stats;
mod wave;


pub use validation::*;
pub use query::*;
pub use role::*;
pub use rollup::*;
pub use stats::*;
pub use wave::*;



/// Number of extra attempts (beyond the first) when a read races a concurrent
/// out-of-band writer that doesn't go through [`write_atomic`] — e.g. `git
/// checkout`/`git merge` rewriting the working-tree file in place on a shared
/// checkout (t-2216/t-2206), or a direct edit that bypasses the CLI (t-2380).
/// brana's own writers are already torn-read-proof (atomic rename under an
/// exclusive sidecar lock — see [`write_atomic`]/[`lock_tasks`]), so this
/// guards against writers outside that contract, not against brana itself.
const READ_RETRY_ATTEMPTS: u32 = 3;
const READ_RETRY_DELAY_MS: u64 = 15;

/// Read `path` and parse it with `parse`, retrying a bounded number of times
/// on a **parse** failure only (never on an I/O error like file-not-found —
/// retrying that just delays an unavoidable error). Each retry re-reads the
/// file from scratch so a torn read caused by a concurrent in-place writer
/// self-heals once that writer's own write completes.
fn read_with_retry<T>(
    path: &Path,
    parse: impl Fn(&str) -> Result<T, String>,
) -> Result<T, String> {
    let mut last_err = String::new();
    for attempt in 0..=READ_RETRY_ATTEMPTS {
        let content = match std::fs::read_to_string(path) {
            Ok(c) => c,
            Err(e) => return Err(format!("{}: {e}", path.display())),
        };
        match parse(&content) {
            Ok(v) => return Ok(v),
            Err(e) => {
                last_err = e;
                if attempt < READ_RETRY_ATTEMPTS {
                    std::thread::sleep(std::time::Duration::from_millis(READ_RETRY_DELAY_MS));
                }
            }
        }
    }
    Err(last_err)
}

#[derive(Deserialize)]
pub struct TasksFile {
    #[serde(default)]
    pub project: String,
    #[serde(default)]
    pub tasks: Vec<Value>,
    /// Waves — thin stored process objects, NOT tasks (ADR-065, t-2315). A
    /// sibling top-level array using the same growth model tasks.json
    /// already uses for `tasks`. See next_wave_id()/set_wave_field().
    #[serde(default)]
    pub waves: Vec<Value>,
}

/// Load tasks from file. Supports both {tasks: [...]} and bare [...].
pub fn load_tasks(path: &Path) -> Result<TasksFile, String> {
    read_with_retry(path, |content| {
        let content = content.trim();
        if content.is_empty() {
            return Ok(TasksFile {
                project: "unknown".into(),
                tasks: vec![],
                waves: vec![],
            });
        }
        if let Ok(tf) = serde_json::from_str::<TasksFile>(content) {
            return Ok(tf);
        }
        if let Ok(arr) = serde_json::from_str::<Vec<Value>>(content) {
            return Ok(TasksFile {
                project: "unknown".into(),
                tasks: arr,
                waves: vec![],
            });
        }
        Err(format!("invalid JSON in {}", path.display()))
    })
}

/// Write `content` to `path` atomically via a PID-scoped temp file + rename.
///
/// The temp file is placed in the same directory as `path` so the rename
/// stays on the same filesystem (required for POSIX atomic replace).
/// PID scoping prevents concurrent processes from clobbering each other's
/// temp file before the rename completes.
fn write_atomic(path: &Path, content: &str) -> Result<(), String> {
    let dir = path.parent().ok_or("path has no parent directory")?;
    let file_name = path
        .file_name()
        .and_then(|n| n.to_str())
        .unwrap_or("tasks");
    let tmp = dir.join(format!("{}.{}.tmp", file_name, std::process::id()));
    std::fs::write(&tmp, content).map_err(|e| format!("write tmp failed: {e}"))?;
    std::fs::rename(&tmp, path).map_err(|e| {
        let _ = std::fs::remove_file(&tmp);
        format!("atomic rename failed: {e}")
    })
}

/// Canonical tasks-file schema version this binary understands and stamps on
/// write. t-2283 established the numeric-version convention at floor `2`
/// (ac_state slice). t-2308 bumps the floor to `3` for t-2284's own schema
/// slice (level/epic-collapse awareness) — reusing `2` here would be a no-op
/// since files are already stamped at version 2.
const CANONICAL_VERSION: i64 = 3;

/// Read a tasks-file `version` value as an integer, tolerating BOTH the numeric
/// form (`2`) and the legacy JSON-string form (`"1"`). The live tasks.json ships
/// `version` as a string, so a numbers-only check silently never matched (t-2283
/// challenger CRITICAL) — always route version reads through here.
fn version_as_int(v: &Value) -> Option<i64> {
    v.as_i64().or_else(|| v.as_str().and_then(|s| s.parse::<i64>().ok()))
}

/// True when `val` already carries a canonical version (a JSON NUMBER ≥
/// `CANONICAL_VERSION`). A legacy string `"3"` deliberately reads as *not*
/// canonical so it gets rewritten to the numeric form on the next save.
fn has_canonical_version(val: &Value) -> bool {
    matches!(val.get("version"), Some(Value::Number(n)) if n.as_i64().map_or(false, |v| v >= CANONICAL_VERSION))
}

/// t-2308 forward-only guard: true when `val` carries a version NUMBER this
/// binary was not built to understand (strictly greater than
/// `CANONICAL_VERSION`). `has_canonical_version` treats "at floor" and
/// "above floor" the same (both mean "don't rewrite"); this check isolates
/// the "above floor" case so callers can refuse to write instead of just
/// skipping the rewrite.
///
/// Forward-only: this protects binaries built from t-2308 onward against a
/// hypothetical future version 4+ file. It CANNOT protect binaries already
/// compiled before this change — those hardcode `>= 2` (or `>= 1`) and have
/// no way to learn about version 3 retroactively; only rebuilding/
/// redeploying the binary closes that gap.
fn is_unknown_newer_version(val: &Value) -> bool {
    val.get("version").and_then(version_as_int).map_or(false, |v| v > CANONICAL_VERSION)
}

/// t-2283 (v3 forward-only slice): normalize the tasks-file `version` stamp to
/// the canonical numeric floor (`CANONICAL_VERSION`). Absent, non-integer,
/// string, or numeric values below the floor upgrade to it; a value already
/// ≥ floor is preserved (and coerced to a JSON number so legacy string stamps
/// stop lying to `as_i64`-based checks) — this also means a version strictly
/// ABOVE the floor (unknown-newer, t-2308) is left completely untouched: this
/// binary does not know that schema shape and must not guess at a downgrade.
/// Non-breaking by design — existing v1/unversioned files load with task content
/// untouched, gaining only the canonical stamp. This is the "gate load on
/// version:3" rule: every loaded/saved file carries numeric version ≥ 3,
/// without a migration of legacy tasks (operator decision 2026-07-21:
/// auto-upgrade, not hard-reject).
fn normalize_version(val: &mut Value) {
    if has_canonical_version(val) {
        return;
    }
    if let Some(obj) = val.as_object_mut() {
        let current = obj.get("version").and_then(version_as_int).unwrap_or(1);
        obj.insert("version".into(), Value::from(current.max(CANONICAL_VERSION)));
    }
}

/// Save a TasksFile back to disk (pretty-printed, atomic). Guarantees a
/// canonical numeric version stamp (`CANONICAL_VERSION`, t-2283/t-2308). The
/// common write path (load_raw → mutate → save) already carries the
/// canonical stamp from load_raw, so the hot path skips the ~2,100-task
/// clone.
///
/// Forward-only guard (t-2308): refuses to write when `val` carries a
/// version this binary does not understand (see `is_unknown_newer_version`)
/// — read-only + a stderr warning, rather than silently overwriting a future
/// schema shape with an old binary's serialization of it. This only protects
/// binaries built from this change onward; it cannot retroactively guard
/// already-compiled binaries that hardcode an older floor.
pub fn save_tasks(path: &Path, val: &Value) -> Result<(), String> {
    if is_unknown_newer_version(val) {
        eprintln!(
            "warning: tasks.json version ({:?}) is newer than this binary understands (canonical={CANONICAL_VERSION}) — refusing to write, treating as read-only. Rebuild/upgrade this binary before saving.",
            val.get("version")
        );
        return Err(format!(
            "refusing to save: tasks.json version is newer than this binary supports (canonical={CANONICAL_VERSION})"
        ));
    }
    let content = if has_canonical_version(val) {
        serde_json::to_string_pretty(val)
    } else {
        let mut stamped = val.clone();
        normalize_version(&mut stamped);
        serde_json::to_string_pretty(&stamped)
    }
    .map_err(|e| format!("serialize failed: {e}"))?;
    write_atomic(path, &(content + "\n"))
}

/// Acquire the exclusive write lock for the tasks store at `path`.
///
/// Hold the returned guard across the **entire** read-modify-write —
/// `lock_tasks` → [`load_raw`] → mutate → [`next_id`] → [`save_tasks`] — so
/// `next_id` is computed from a fresh, under-lock read and concurrent
/// processes serialize instead of clobbering each other's writes (t-2166).
///
/// The lock is an exclusive advisory `flock(2)` on a `<store>.json.lock`
/// sidecar (see [`crate::util::lock_sidecar`]); the store inode itself is
/// replaced by the atomic rename inside [`save_tasks`], so the sidecar — not
/// the store file — is what serializes writers. Drop the guard (let it fall
/// out of scope) only after `save_tasks` returns.
pub fn lock_tasks(path: &Path) -> Result<std::fs::File, String> {
    crate::util::lock_sidecar(path)
}

/// Like [`lock_tasks`], but bounded (see [`crate::util::lock_sidecar_timeout`]).
///
/// Use this from any async caller — most notably `brana-mcp` tool handlers — instead of
/// [`lock_tasks`]. An unbounded `flock()` inside an async handler can starve a
/// fully-serialized event loop for its remaining lifetime if the lock is contended
/// (t-2305: this happened to `brana-mcp`'s stdio dispatch — one stuck handler froze the
/// server for every subsequent request, including unrelated reads).
pub fn lock_tasks_timeout(path: &Path) -> Result<std::fs::File, String> {
    crate::util::lock_sidecar_timeout(path, crate::util::DEFAULT_LOCK_TIMEOUT)
}

/// Load tasks as raw serde_json::Value (preserves all fields for mutation).
/// Normalizes bare JSON arrays into `{tasks: [...]}` so callers can always use `val["tasks"]`.
pub fn load_raw(path: &Path) -> Result<Value, String> {
    let val: Value = read_with_retry(path, |content| {
        serde_json::from_str(content.trim()).map_err(|e| format!("invalid JSON: {e}"))
    })?;
    let mut val = if val.is_array() {
        serde_json::json!({"tasks": val})
    } else {
        val
    };
    normalize_version(&mut val);
    Ok(val)
}

/// t-2841 (ADR-080 §5): the single ack owner. ANY status write — through
/// `set_field`, `perform_rollup`'s parent-completion, or the CLI bulk-close
/// command — must call this so a leased task never strands its lease no
/// matter which door closed it. Clears `lease` unconditionally (key removed,
/// never null — ADR-067); retires `reclaim_count` only on `completed` (it
/// lives outside `lease` precisely so it survives every other status write).
pub fn ack_status_write(task: &mut Value, new_status: &str) {
    if let Some(obj) = task.as_object_mut() {
        obj.remove("lease");
        if new_status == "completed" {
            obj.remove("reclaim_count");
        }
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

/// Find the next available wave ID (highest numeric suffix + 1). Waves live
/// in their own `waves` array with a distinct `wave-` prefix, never `t-` —
/// ADR-065 draws the line explicitly ("It selects tasks; it does not own
/// them") and a shared numbering scheme would let a bare "wave-3" and "t-3"
/// coexist while meaning unrelated things depending on which array a caller
/// looked in. Same algorithm as next_id() (t-2315).
pub fn next_wave_id(waves: &[Value]) -> String {
    let max = waves.iter()
        .filter_map(|w| w["id"].as_str())
        .filter_map(|id| id.split('-').last()?.parse::<u32>().ok())
        .max()
        .unwrap_or(0);
    format!("wave-{}", max + 1)
}


/// Compute the git branch name for a task based on work_type + kind + id + subject.
pub fn branch_for_task(task: &Value) -> String {
    let kind = task["kind"].as_str().unwrap_or("");
    let work_type = task["work_type"].as_str().unwrap_or("implement");
    let prefix = match kind {
        "fix" => "fix",
        "refactor" => "refactor",
        "docs" => "docs",
        _ => match work_type {
            "research" => "research",
            "design" => "design",
            "infra" => "infra",
            "chore" => "chore",
            "review" => "review",
            _ => "feat",
        },
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
    let kind = task["kind"].as_str().unwrap_or("");
    let work_type = task["work_type"].as_str().unwrap_or("implement");
    let prefix = match kind {
        "fix" => "fix",
        "refactor" => "refactor",
        "docs" => "docs",
        _ => match work_type {
            "research" => "research",
            "design" => "design",
            "infra" => "infra",
            "chore" => "chore",
            "review" => "review",
            _ => "feat",
        },
    };
    let id = task["id"].as_str().unwrap_or("t-000");
    format!("../{repo_name}-{prefix}/{id}")
}

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

    // Feature/implement work is typically more complex
    if matches!(task["kind"].as_str(), Some("feature") | None)
        && task["work_type"].as_str() == Some("implement")
    {
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
            "work_type": t["work_type"],
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

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;
    use std::collections::{HashMap, HashSet};

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

    // ADR-079 (amended 2026-08-23) / ADR-086 §4: a cancelled blocker is NOT
    // resolved — it must be removed from blocked_by explicitly. Every consumer
    // (classify → next/focus/blocked/board, wave_pull_decision) shares
    // `unmet_blockers`, so this one test pins the semantics for all of them.
    #[test]
    fn test_cancelled_blocker_stays_blocked() {
        let tasks = vec![
            json!({"id": "t-a", "status": "cancelled", "tags": [], "blocked_by": []}),
            json!({"id": "t-b", "status": "pending", "type": "task", "tags": [], "blocked_by": ["t-a"]}),
        ];
        assert_eq!(classify(&tasks[1], &tasks), "blocked");
        let by_id = wave::task_index(&tasks);
        assert_eq!(unmet_blockers(&tasks[1], &by_id), vec!["t-a"]);
    }

    #[test]
    fn test_unmet_blockers_resolves_only_on_completed_or_epic_done() {
        let tasks = vec![
            json!({"id": "t-done", "status": "completed", "tags": [], "blocked_by": []}),
            json!({"id": "t-canc", "status": "cancelled", "tags": [], "blocked_by": []}),
            json!({"id": "in-done", "status": "done", "type": "epic", "tags": [], "blocked_by": []}),
            json!({"id": "t-x", "status": "pending", "type": "task", "tags": [],
                   "blocked_by": ["t-done", "t-canc", "in-done", "t-ghost"]}),
        ];
        let by_id = wave::task_index(&tasks);
        // cancelled and unknown ids stay unmet; completed and epic-done resolve
        assert_eq!(unmet_blockers(&tasks[3], &by_id), vec!["t-canc", "t-ghost"]);
    }

    // ── t-2313 (ADR-065): epic blocked_by gate uses epic-vocab terminal states ──

    #[test]
    fn test_classify_epic_blocked_by_gates_generically() {
        let tasks = vec![
            json!({"id": "in-1", "status": "next", "type": "epic", "tags": [], "blocked_by": []}),
            json!({"id": "in-2", "status": "next", "type": "epic", "tags": [], "blocked_by": ["in-1"]}),
        ];
        assert_eq!(classify(&tasks[1], &tasks), "blocked", "epic in-2 must be gated on unfinished in-1");
    }

    #[test]
    fn test_classify_epic_done_status_unblocks_dependent_epic() {
        // ADR-065's epic gate ("epic N blocked on epic N-1 shipping") requires the
        // epic-status terminal value "done" to satisfy blocked_by, not just the
        // task-status "completed"/"cancelled" (t-2313 — classify()'s done_ids set
        // hardcoded the task vocabulary and never recognized an epic's own "done").
        let tasks = vec![
            json!({"id": "in-1", "status": "done", "type": "epic", "tags": [], "blocked_by": []}),
            json!({"id": "in-2", "status": "next", "type": "epic", "tags": [], "blocked_by": ["in-1"]}),
        ];
        assert_eq!(classify(&tasks[1], &tasks), "pending", "in-2 must unblock once in-1 is epic-done");
    }

    #[test]
    fn test_classify_epic_archived_status_is_finished() {
        let tasks = vec![
            json!({"id": "in-1", "status": "archived", "type": "epic", "tags": [], "blocked_by": []}),
        ];
        assert_eq!(classify(&tasks[0], &tasks), "done");
    }

    #[test]
    fn test_classify_task_status_done_does_not_leak_epic_semantics() {
        // A plain task's status literally spelled "done" (invalid task vocab —
        // validate_status would reject it) must NOT be treated as finished just
        // because is_finished() has a "done"/"archived" branch — that branch is
        // gated on type=="epic" specifically.
        let tasks = vec![
            json!({"id": "t-1", "status": "done", "type": "task", "tags": [], "blocked_by": []}),
        ];
        assert_eq!(classify(&tasks[0], &tasks), "pending");
    }

    #[test]
    fn test_filter_by_tag() {
        let tasks = sample_tasks();
        let result = filter_tasks(&tasks, &tasks, Some("scheduler"), None, None, None, None, &["task", "subtask"], None, None);
        assert_eq!(result.len(), 2);
    }

    #[test]
    fn test_filter_by_status() {
        let tasks = sample_tasks();
        // Raw status match — see tasks.spec.md (t-1323). Previously passed
        // "active" (classify output); now uses "in_progress" (CLI enum / raw
        // field value) which is the filter contract.
        let result = filter_tasks(&tasks, &tasks, None, Some("in_progress"), None, None, None, &["task", "subtask"], None, None);
        assert_eq!(result.len(), 1);
        assert_eq!(result[0]["id"].as_str().unwrap(), "t-002");
    }

    // ── t-1323: raw-status filter contract ────────────────────────────────
    //
    // These tests encode the spec in tasks.spec.md: `filter_tasks` must
    // compare the raw `task.status` field against the CLI enum input, not
    // `classify()` output. They FAIL against the pre-fix implementation and
    // MUST pass once the fix lands.

    #[test]
    fn test_filter_status_completed_matches_raw_field() {
        let tasks = sample_tasks();
        // CLI passes "completed" (enum value). Must match t-001 whose raw
        // status is "completed". Pre-fix this returned 0 items because
        // classify(t-001) == "done" != "completed".
        let result = filter_tasks(&tasks, &tasks, None, Some("completed"), None, None, None, &["task", "subtask"], None, None);
        assert_eq!(result.len(), 1, "--status completed must match raw completed tasks");
        assert_eq!(result[0]["id"].as_str().unwrap(), "t-001");
    }

    #[test]
    fn test_filter_status_cancelled_matches_raw_field() {
        let tasks = sample_tasks();
        // Pre-fix: classify(t-006) == "done", "done" != "cancelled" → 0 hits.
        let result = filter_tasks(&tasks, &tasks, None, Some("cancelled"), None, None, None, &["task", "subtask"], None, None);
        assert_eq!(result.len(), 1, "--status cancelled must match raw cancelled tasks");
        assert_eq!(result[0]["id"].as_str().unwrap(), "t-006");
    }

    #[test]
    fn test_filter_status_in_progress_matches_raw_field() {
        let tasks = sample_tasks();
        // Pre-fix: classify(t-002) == "active", "active" != "in_progress" → 0 hits.
        let result = filter_tasks(&tasks, &tasks, None, Some("in_progress"), None, None, None, &["task", "subtask"], None, None);
        assert_eq!(result.len(), 1, "--status in_progress must match raw in_progress tasks");
        assert_eq!(result[0]["id"].as_str().unwrap(), "t-002");
    }

    #[test]
    fn test_filter_status_pending_includes_blocked_and_parked() {
        let tasks = sample_tasks();
        // Under raw-status semantics, --status pending matches every task
        // whose raw status field is "pending" — regardless of whether it
        // would classify as blocked or parked. Callers that want
        // classify-based filtering (e.g. cmd_next) must apply a post-hoc
        // filter.
        let result = filter_tasks(&tasks, &tasks, None, Some("pending"), None, None, None, &["task", "subtask"], None, None);
        let ids: Vec<&str> = result.iter().filter_map(|t| t["id"].as_str()).collect();
        assert_eq!(result.len(), 3, "pending includes t-003 (plain), t-004 (blocked), t-005 (parked)");
        assert!(ids.contains(&"t-003"));
        assert!(ids.contains(&"t-004"));
        assert!(ids.contains(&"t-005"));
    }

    #[test]
    fn test_filter_rejects_synthetic_classify_values() {
        let tasks = sample_tasks();
        // Synthetic classify values ("done", "active", "blocked", "parked")
        // are no longer accepted — they're not in the CLI enum. Filtering
        // by them returns zero.
        for synthetic in &["done", "active", "blocked", "parked"] {
            let result = filter_tasks(&tasks, &tasks, None, Some(synthetic), None, None, None, &["task", "subtask"], None, None);
            assert_eq!(result.len(), 0, "--status {synthetic} (synthetic) must return 0 matches");
        }
    }

    #[test]
    fn test_filter_excludes_phases() {
        let tasks = sample_tasks();
        let result = filter_tasks(&tasks, &tasks, None, None, None, None, None, &["task", "subtask"], None, None);
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
        let p0 = json!({"priority": "P0", "effort": "S", "blocked_by": []});
        let p3 = json!({"priority": "P3", "effort": "S", "blocked_by": []});
        assert!(focus_score(&p0, 0.0) > focus_score(&p3, 0.0));
    }

    #[test]
    fn test_focus_score_smaller_effort_wins() {
        let small = json!({"priority": "P2", "effort": "S", "blocked_by": []});
        let large = json!({"priority": "P2", "effort": "XL", "blocked_by": []});
        assert!(focus_score(&small, 0.0) > focus_score(&large, 0.0));
    }

    #[test]
    fn test_focus_score_initiative_boost() {
        let boosted = json!({"priority": "P2", "effort": "S", "blocked_by": [], "epic": "cc-alignment"});
        let plain   = json!({"priority": "P0", "effort": "S", "blocked_by": []});
        // P2 + 500 boost = 690 > P0 + 0 = 390
        assert!(focus_score(&boosted, 500.0) > focus_score(&plain, 0.0));
    }

    #[test]
    fn test_focus_score_no_staleness() {
        // Two tasks with same priority and effort, created 100 days apart — scores must be equal.
        // Staleness was removed; age no longer affects score.
        let old   = json!({"priority": "P1", "effort": "M", "blocked_by": [], "created": "2020-01-01"});
        let fresh = json!({"priority": "P1", "effort": "M", "blocked_by": [], "created": "2026-05-19"});
        assert_eq!(focus_score(&old, 0.0), focus_score(&fresh, 0.0));
    }

    #[test]
    fn test_filter_tasks_by_work_type() {
        let tasks = vec![
            json!({"id": "t-1", "status": "pending", "type": "task", "tags": [], "blocked_by": [], "work_type": "implement"}),
            json!({"id": "t-2", "status": "pending", "type": "task", "tags": [], "blocked_by": [], "work_type": "research"}),
            json!({"id": "t-3", "status": "pending", "type": "task", "tags": [], "blocked_by": [], "work_type": "implement"}),
        ];
        let result = filter_tasks(&tasks, &tasks, None, None, None, None, None, &["task", "subtask"], None, Some("implement"));
        assert_eq!(result.len(), 2);
        assert!(result.iter().all(|t| t["work_type"] == "implement"));
    }

    #[test]
    fn test_filter_tasks_by_initiative() {
        let tasks = vec![
            json!({"id": "ep-1", "type": "epic", "subject": "cc-alignment", "parent": null}),
            json!({"id": "ep-2", "type": "epic", "subject": "notebooklm", "parent": null}),
            json!({"id": "t-1", "status": "pending", "type": "task", "tags": [], "blocked_by": [], "parent": "ep-1"}),
            json!({"id": "t-2", "status": "pending", "type": "task", "tags": [], "blocked_by": [], "parent": "ep-2"}),
            json!({"id": "t-3", "status": "pending", "type": "task", "tags": [], "blocked_by": [], "parent": "ep-1"}),
        ];
        let result = filter_tasks(&tasks, &tasks, None, None, None, None, None, &["task", "subtask"], Some("cc-alignment"), None);
        assert_eq!(result.len(), 2);
        let ids: Vec<&str> = result.iter().map(|t| t["id"].as_str().unwrap()).collect();
        assert!(ids.contains(&"t-1") && ids.contains(&"t-3"));
    }

    // ── t-3233: default-type-scope exclusion is counted, never silent ────

    #[test]
    fn test_excluded_by_type_count_mixed_types() {
        let tasks = vec![
            json!({"id": "t-1", "type": "task"}),
            json!({"id": "t-2", "type": "subtask"}),
            json!({"id": "ph-1", "type": "phase"}),
            json!({"id": "ms-1", "type": "milestone"}),
            json!({"id": "in-1", "type": "epic"}),
        ];
        assert_eq!(excluded_by_type_count(&tasks, &["task", "subtask"]), 3);
    }

    #[test]
    fn test_excluded_by_type_count_all_matching_is_zero() {
        let tasks = vec![
            json!({"id": "t-1", "type": "task"}),
            json!({"id": "t-2", "type": "subtask"}),
        ];
        assert_eq!(excluded_by_type_count(&tasks, &["task", "subtask"]), 0);
    }

    #[test]
    fn test_validate_task_types_accepts_comma_separated_valid_list() {
        let types = validate_task_types("task,subtask,phase,milestone,epic").unwrap();
        assert_eq!(types, vec!["task", "subtask", "phase", "milestone", "epic"]);
    }

    #[test]
    fn test_validate_task_types_trims_whitespace() {
        let types = validate_task_types("task, phase").unwrap();
        assert_eq!(types, vec!["task", "phase"]);
    }

    #[test]
    fn test_validate_task_types_rejects_typo_loudly() {
        // t-3233: a typo must error, never silently return zero results.
        let err = validate_task_types("taks").unwrap_err();
        assert!(err.contains("\"taks\""), "must name the bad token: {err}");
        assert!(err.contains("task"), "must list valid values: {err}");
    }

    #[test]
    fn test_validate_task_types_rejects_one_bad_token_in_a_list() {
        let err = validate_task_types("task,bogus,phase").unwrap_err();
        assert!(err.contains("\"bogus\""));
    }

    #[test]
    fn test_excluded_by_type_count_missing_type_defaults_to_task() {
        // Untyped entries default to "task" (the same convention `filter_tasks_by`
        // uses via `t["type"].as_str().unwrap_or("task")`) — must not be
        // double-counted as excluded when "task" is in scope.
        let tasks = vec![json!({"id": "t-1"})];
        assert_eq!(excluded_by_type_count(&tasks, &["task", "subtask"]), 0);
        assert_eq!(excluded_by_type_count(&tasks, &["phase"]), 1);
    }

    #[test]
    fn test_validate_work_type_valid() {
        for v in &["implement", "research", "design", "infra", "chore", "review", "null", ""] {
            assert!(validate_work_type(v).is_ok(), "expected Ok for {v:?}");
        }
    }

    #[test]
    fn test_validate_work_type_invalid() {
        for v in &["code", "manual", "feature", "build", "dev", "ops"] {
            assert!(validate_work_type(v).is_err(), "expected Err for {v:?}");
        }
    }

    #[test]
    fn test_validate_task_type_valid() {
        for v in &["task", "subtask", "phase", "milestone", "epic", "initiative", "null", ""] {
            assert!(validate_task_type(v).is_ok(), "expected Ok for {v:?}");
        }
    }

    #[test]
    fn test_validate_task_type_invalid() {
        // t-2739: kinds/work_types mistyped into `type` leaked into live data
        // (feature/research/chore/ops rows) — all must be rejected.
        for v in &["feature", "research", "chore", "ops", "fix", "banana"] {
            assert!(validate_task_type(v).is_err(), "expected Err for {v:?}");
        }
    }

    #[test]
    fn test_set_field_type_validates() {
        let mut task = json!({"id": "t-1", "type": "task"});
        assert!(set_field(&mut task, "type", "epic", false).is_ok());
        assert!(set_field(&mut task, "type", "feature", false).is_err());
        assert_eq!(
            task["type"].as_str(),
            Some("epic"),
            "rejected value must not overwrite the field"
        );
    }

    // ── t-2310 (ADR-065): level/epic write-path sealing ──────────────────
    // inherit_initiative() and validate_level() are removed outright — level
    // collapses into type, epic becomes a hierarchy node instead of something
    // flat-copied down a parent chain. See cmd_add_parent_does_not_inherit_epic
    // (backlog.rs) for the write-path replacement of the old inherit_initiative
    // unit tests below.

    #[test]
    fn test_filter_tasks_ignores_stale_level() {
        // A task carrying a stale `level` value (pre-ADR-065 data) must classify
        // purely by `type` — level is no longer read for filtering at all.
        let tasks = vec![
            json!({"id": "t-1", "type": "phase", "level": "task", "status": "pending", "tags": [], "blocked_by": []}),
            json!({"id": "ph-1", "type": "phase", "level": "phase", "status": "pending", "tags": [], "blocked_by": []}),
        ];
        let result = filter_tasks(&tasks, &tasks, None, None, None, None, None, &["task"], None, None);
        assert_eq!(result.len(), 0, "stale level=\"task\" must not override type=\"phase\"");
        let result_phase = filter_tasks(&tasks, &tasks, None, None, None, None, None, &["phase"], None, None);
        assert_eq!(result_phase.len(), 2, "both tasks classify as phase by type, regardless of stale level");
    }

    #[test]
    fn test_filter_tasks_falls_back_to_type_when_no_level() {
        // Without level field, type is still used for filtering.
        let tasks = vec![
            json!({"id": "t-1", "type": "task", "status": "pending", "tags": [], "blocked_by": []}),
            json!({"id": "ph-1", "type": "phase", "status": "pending", "tags": [], "blocked_by": []}),
        ];
        let result = filter_tasks(&tasks, &tasks, None, None, None, None, None, &["task"], None, None);
        assert_eq!(result.len(), 1);
        assert_eq!(result[0]["id"], "t-1");
    }

    #[test]
    fn test_branch_for_infra_task() {
        let task = json!({"id": "t-1", "work_type": "infra", "subject": "setup CI"});
        assert_eq!(branch_for_task(&task), "infra/t-1-setup-ci");
    }

    #[test]
    fn test_branch_for_chore_task() {
        let task = json!({"id": "t-1", "work_type": "chore", "subject": "cleanup logs"});
        assert_eq!(branch_for_task(&task), "chore/t-1-cleanup-logs");
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
            {"id":"t-1","subject":"Test","status":"pending","type":"task","tags":["a"],"context":"ctx"}
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
    fn test_validate_schema_accepts_epic_and_initiative_types() {
        // t-2322 (ADR-065): validate_schema()'s valid_types whitelist predates
        // the epic hierarchy model — type:"epic" (node markers, t-2312's
        // migration) and type:"initiative" (13 stray pre-migration survivors)
        // must not be flagged as invalid.
        let dir = std::env::temp_dir().join("brana-test-validate-epic-initiative");
        std::fs::create_dir_all(&dir).ok();
        let path = dir.join("epic-initiative.json");
        std::fs::write(&path, r#"{"version":"1","project":"test","tasks":[
            {"id":"t-1","subject":"Epic node","status":"next","type":"epic","tags":[],"context":null},
            {"id":"t-2","subject":"Stray initiative","status":"pending","type":"initiative","tags":[],"context":null}
        ]}"#).unwrap();
        let errors = validate_schema(&path);
        assert!(
            !errors.iter().any(|e| e.contains("invalid type")),
            "epic/initiative types must not be flagged as invalid, got: {:?}",
            errors
        );
        std::fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn test_validate_schema_accepts_epic_vocab_status_for_epic_type() {
        // t-2379: t-2322 fixed valid_types to accept "epic", but the status
        // check stayed unconditional against task-vocab statuses — every
        // real epic node (status:"next" per make_epic_node()/ADR-065) still
        // failed validate_schema() with "invalid status next". The status
        // check must branch on type:"epic" the same way set_field() does,
        // dispatching to validate_epic_status()'s vocab (active/next/parked/
        // done/archived/null) instead of the task vocab.
        let dir = std::env::temp_dir().join("brana-test-validate-epic-status");
        std::fs::create_dir_all(&dir).ok();
        let path = dir.join("epic-status.json");
        std::fs::write(&path, r#"{"version":"1","project":"test","tasks":[
            {"id":"t-1","subject":"Epic node","status":"next","type":"epic","tags":[],"context":null}
        ]}"#).unwrap();
        let errors = validate_schema(&path);
        assert!(
            !errors.iter().any(|e| e.contains("invalid status")),
            "epic-vocab status \"next\" on a type:\"epic\" task must not be flagged, got: {:?}",
            errors
        );
        std::fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn test_validate_schema_rejects_epic_vocab_status_for_non_epic_type() {
        // No cross-contamination: a non-epic task using epic vocab (e.g.
        // "next") is still invalid task status.
        let dir = std::env::temp_dir().join("brana-test-validate-non-epic-status");
        std::fs::create_dir_all(&dir).ok();
        let path = dir.join("non-epic-status.json");
        std::fs::write(&path, r#"{"version":"1","project":"test","tasks":[
            {"id":"t-1","subject":"Ordinary task","status":"next","type":"task","tags":[],"context":null}
        ]}"#).unwrap();
        let errors = validate_schema(&path);
        assert!(
            errors.iter().any(|e| e.contains("invalid status")),
            "epic-vocab status \"next\" on a non-epic task must still be rejected, got: {:?}",
            errors
        );
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

    #[test]
    fn test_validate_schema_rejects_invalid_work_type_kind_task_type() {
        // t-2742: validate_schema() predates validate_work_type/validate_kind/
        // validate_task_type (single-field write-path validators, t-1960/t-2739)
        // and never picked them up, so whole-file validation (the hook's Rust
        // path) silently missed drift on these three fields.
        let dir = std::env::temp_dir().join("brana-test-validate-work-type-kind");
        std::fs::create_dir_all(&dir).ok();
        let path = dir.join("bad-enums.json");
        std::fs::write(&path, r#"{"version":"1","project":"test","tasks":[
            {"id":"t-1","subject":"Bad work_type","status":"pending","type":"task","work_type":"bogus"},
            {"id":"t-2","subject":"Bad kind","status":"pending","type":"task","kind":"bogus"}
        ]}"#).unwrap();
        let errors = validate_schema(&path);
        assert!(
            errors.iter().any(|e| e.contains("t-1") && e.contains("work_type")),
            "expected work_type error, got: {:?}",
            errors
        );
        assert!(
            errors.iter().any(|e| e.contains("t-2") && e.contains("kind")),
            "expected kind error, got: {:?}",
            errors
        );
        std::fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn test_validate_schema_accepts_valid_work_type_kind_null() {
        let dir = std::env::temp_dir().join("brana-test-validate-work-type-kind-valid");
        std::fs::create_dir_all(&dir).ok();
        let path = dir.join("good-enums.json");
        std::fs::write(&path, r#"{"version":"1","project":"test","tasks":[
            {"id":"t-1","subject":"Good","status":"pending","type":"task","work_type":"implement","kind":"fix"},
            {"id":"t-2","subject":"Null ok","status":"pending","type":"task","work_type":null,"kind":null}
        ]}"#).unwrap();
        let errors = validate_schema(&path);
        assert!(
            !errors.iter().any(|e| e.contains("work_type") || e.contains("kind")),
            "valid/null work_type and kind must not error, got: {:?}",
            errors
        );
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

    #[test]
    fn test_set_field_rejects_level() {
        // ADR-065: level is retired — collapses into type. set_field must
        // reject it, not silently no-op (t-2310).
        let mut task = json!({"id": "t-1", "type": "task"});
        assert!(set_field(&mut task, "level", "phase", false).is_err());
        assert_eq!(task["type"], "task", "rejected write must not mutate the task");
        assert!(task.get("level").is_none(), "level must not be written");
    }

    #[test]
    fn test_set_field_rejects_epic() {
        // ADR-065: epic is retired as a flat field — becomes a hierarchy node.
        // set_field must reject it (t-2310).
        let mut task = json!({"id": "t-1"});
        assert!(set_field(&mut task, "epic", "harness", false).is_err());
        assert!(task.get("epic").is_none(), "epic must not be written");
    }

    #[test]
    fn test_set_field_rejects_stream() {
        // ADR-065: stream is retired — the 3-value dev/ops/research taxonomy
        // was superseded by tags/epic. set_field must reject it, not
        // silently no-op (t-2325).
        let mut task = json!({"id": "t-1", "type": "task"});
        assert!(set_field(&mut task, "stream", "dev", false).is_err());
        assert!(task.get("stream").is_none(), "stream must not be written");
    }

    #[test]
    fn test_set_field_rejects_wip_limit() {
        // ADR-065 D4 (retired 2026-08-12, t-2727): epic wip_limit is retired
        // — epics stay unbounded groupings, WIP control moves to waves
        // (t-2782). set_field must reject it, not silently no-op.
        let mut task = json!({"id": "in-1", "type": "epic"});
        assert!(set_field(&mut task, "wip_limit", "10", false).is_err());
        assert!(task.get("wip_limit").is_none(), "wip_limit must not be written");
    }

    // ── t-2385: RETIRED_FIELDS single source of truth (ADR-067) ──────────
    // set_field()'s exhaustive `match` + catch-all `_ => Err("unknown field")`
    // is already an allowlist-by-construction, so retired fields are already
    // hard-rejected there (tests above). The genuine gap is write paths that
    // merge raw JSON objects directly (cmd_add's --json ingestion), which
    // used to hand-roll independent contains_key checks per field. These
    // tests cover the new shared helper those paths call instead.

    #[test]
    fn test_reject_retired_fields_empty_object_passes() {
        let obj = json!({"subject": "hi"}).as_object().unwrap().clone();
        assert!(reject_retired_fields(&obj).is_ok());
    }

    #[test]
    fn test_reject_retired_fields_no_retired_keys_passes() {
        let obj = json!({"subject": "hi", "tags": ["a"], "priority": "P1"}).as_object().unwrap().clone();
        assert!(reject_retired_fields(&obj).is_ok());
    }

    #[test]
    fn test_reject_retired_fields_single_field_named() {
        let obj = json!({"subject": "hi", "level": "phase"}).as_object().unwrap().clone();
        let err = reject_retired_fields(&obj).unwrap_err();
        assert!(err.contains("level"), "error must name the field: {err}");
    }

    #[test]
    fn test_reject_retired_fields_all_named() {
        let obj = json!({"level": "x", "epic": "y", "stream": "z", "wip_limit": 5})
            .as_object().unwrap().clone();
        let err = reject_retired_fields(&obj).unwrap_err();
        assert!(err.contains("level"), "error must name level: {err}");
        assert!(err.contains("epic"), "error must name epic: {err}");
        assert!(err.contains("stream"), "error must name stream: {err}");
        assert!(err.contains("wip_limit"), "error must name wip_limit: {err}");
    }

    #[test]
    fn test_reject_retired_fields_wip_limit_named() {
        // ADR-065 D4 (retired 2026-08-12, t-2727): the epic wip_limit cap
        // never blocked in over a year of pilot and was wrong for 9/55 live
        // epics by 4-7x — retired rather than retuned. WIP control, if
        // wanted, moves to waves (t-2782), a different unit than epics.
        let obj = json!({"subject": "hi", "wip_limit": 10}).as_object().unwrap().clone();
        let err = reject_retired_fields(&obj).unwrap_err();
        assert!(err.contains("wip_limit"), "error must name the field: {err}");
    }

    #[test]
    fn test_reject_retired_fields_exact_match_only_no_substrings() {
        // "epics" and "streaming" are NOT the retired keys "epic"/"stream" —
        // exact key match only, no substring matching.
        let obj = json!({"epics": "x", "streaming": "y"}).as_object().unwrap().clone();
        assert!(reject_retired_fields(&obj).is_ok());
    }

    // ── t-2439: shared comma-string → array coercion ─────────────────────

    #[test]
    fn test_normalize_array_fields_splits_comma_string() {
        let mut task = json!({"tags": "a,b,c", "blocked_by": "t-1, t-2"});
        normalize_array_fields(&mut task);
        assert_eq!(task["tags"], json!(["a", "b", "c"]));
        assert_eq!(task["blocked_by"], json!(["t-1", "t-2"]));
    }

    #[test]
    fn test_normalize_array_fields_leaves_arrays_untouched() {
        let mut task = json!({"tags": ["a", "b"], "blocked_by": []});
        normalize_array_fields(&mut task);
        assert_eq!(task["tags"], json!(["a", "b"]));
        assert_eq!(task["blocked_by"], json!([]));
    }

    #[test]
    fn test_normalize_array_fields_empty_string_becomes_empty_array() {
        let mut task = json!({"tags": ""});
        normalize_array_fields(&mut task);
        assert_eq!(task["tags"], json!([]));
    }

    #[test]
    fn test_normalize_array_fields_ignores_absent_and_null() {
        // Absent keys must stay absent — cmd_add's own null-defaulting owns
        // that, and inventing keys here would resurrect retired-field-style
        // schema drift.
        let mut task = json!({"subject": "no arrays", "blocked_by": null});
        normalize_array_fields(&mut task);
        assert!(task.get("tags").is_none(), "must not invent a tags key");
        assert!(task["blocked_by"].is_null(), "null must stay null");
    }

    #[test]
    fn test_normalize_array_fields_trims_and_drops_blanks() {
        let mut task = json!({"tags": " a , , b "});
        normalize_array_fields(&mut task);
        assert_eq!(task["tags"], json!(["a", "b"]));
    }

    #[test]
    fn test_normalize_array_fields_does_not_split_acceptance_criteria() {
        // AC items are prose and legitimately contain commas — splitting them
        // would corrupt the payload. Only ARRAY_FIELDS are coerced.
        let mut task = json!({"acceptance_criteria": "tests pass, docs updated"});
        normalize_array_fields(&mut task);
        assert_eq!(task["acceptance_criteria"], json!("tests pass, docs updated"));
    }

    // ── t-252: isc field ────────────────────────────────────────────────

    #[test]
    fn test_set_field_isc_add_to_missing() {
        // isc auto-initializes when absent
        let mut task = json!({"id": "t-1"});
        set_field(&mut task, "isc", "+All tests passing", false).unwrap();
        assert_eq!(task["isc"], json!(["All tests passing"]));
    }

    #[test]
    fn test_set_field_isc_add_multiple() {
        let mut task = json!({"id": "t-1", "isc": []});
        set_field(&mut task, "isc", "+All tests passing", false).unwrap();
        set_field(&mut task, "isc", "+No credentials in git history", false).unwrap();
        assert_eq!(task["isc"], json!(["All tests passing", "No credentials in git history"]));
    }

    #[test]
    fn test_set_field_isc_no_duplicates() {
        let mut task = json!({"id": "t-1", "isc": ["All tests passing"]});
        set_field(&mut task, "isc", "+All tests passing", false).unwrap();
        assert_eq!(task["isc"].as_array().unwrap().len(), 1);
    }

    #[test]
    fn test_set_field_isc_remove() {
        let mut task = json!({"id": "t-1", "isc": ["crit-a", "crit-b"]});
        set_field(&mut task, "isc", "-crit-a", false).unwrap();
        assert_eq!(task["isc"], json!(["crit-b"]));
    }

    #[test]
    fn test_set_field_isc_bare_value_errors() {
        let mut task = json!({"id": "t-1", "isc": []});
        assert!(set_field(&mut task, "isc", "no-prefix", false).is_err());
    }

    // ── E2026-05-22-7: string-tagged task coercion ──────────────────────

    #[test]
    fn test_set_field_tags_string_coerce_add() {
        let mut task = json!({"id": "t-1", "tags": "ruflo,multi-agent"});
        set_field(&mut task, "tags", "+brana-v2-compute", false).unwrap();
        let tags = task["tags"].as_array().expect("tags should be array after coercion");
        assert!(tags.contains(&json!("ruflo")));
        assert!(tags.contains(&json!("multi-agent")));
        assert!(tags.contains(&json!("brana-v2-compute")));
    }

    #[test]
    fn test_set_field_tags_string_coerce_remove() {
        let mut task = json!({"id": "t-1", "tags": "ruflo,multi-agent"});
        set_field(&mut task, "tags", "-ruflo", false).unwrap();
        let tags = task["tags"].as_array().expect("tags should be array after coercion");
        assert!(!tags.contains(&json!("ruflo")));
        assert!(tags.contains(&json!("multi-agent")));
    }

    #[test]
    fn test_set_field_tags_empty_string_coerce() {
        let mut task = json!({"id": "t-1", "tags": ""});
        set_field(&mut task, "tags", "+new", false).unwrap();
        assert_eq!(task["tags"], json!(["new"]));
    }

    #[test]
    fn test_validate_schema_isc_valid() {
        use tempfile::NamedTempFile;
        use std::io::Write;
        let mut f = NamedTempFile::new().unwrap();
        write!(f, r#"{{"version":1,"project":"p","tasks":[{{"id":"t-1","subject":"s","status":"pending","type":"task","tags":[],"blocked_by":[],"isc":["All tests passing","Docs updated"]}}]}}"#).unwrap();
        let errs = validate_schema(f.path());
        assert!(errs.is_empty(), "unexpected errors: {errs:?}");
    }

    #[test]
    fn test_validate_schema_isc_not_array() {
        use tempfile::NamedTempFile;
        use std::io::Write;
        let mut f = NamedTempFile::new().unwrap();
        write!(f, r#"{{"version":1,"project":"p","tasks":[{{"id":"t-1","subject":"s","status":"pending","type":"task","tags":[],"blocked_by":[],"isc":"not-an-array"}}]}}"#).unwrap();
        let errs = validate_schema(f.path());
        assert!(errs.iter().any(|e| e.contains("isc") && e.contains("array")), "expected isc error, got: {errs:?}");
    }

    #[test]
    fn test_validate_schema_isc_non_string_item() {
        use tempfile::NamedTempFile;
        use std::io::Write;
        let mut f = NamedTempFile::new().unwrap();
        write!(f, r#"{{"version":1,"project":"p","tasks":[{{"id":"t-1","subject":"s","status":"pending","type":"task","tags":[],"blocked_by":[],"isc":[42,"valid"]}}]}}"#).unwrap();
        let errs = validate_schema(f.path());
        assert!(errs.iter().any(|e| e.contains("isc")), "expected isc error, got: {errs:?}");
    }

    // ── t-1344: priority enum validation ────────────────────────────────

    #[test]
    fn test_validate_priority_accepts_p_tier() {
        for p in &["P0", "P1", "P2", "P3"] {
            assert!(validate_priority(p).is_ok(), "{p} should be accepted");
        }
    }

    #[test]
    fn test_validate_priority_accepts_null_and_empty() {
        assert!(validate_priority("null").is_ok());
        assert!(validate_priority("").is_ok());
    }

    #[test]
    fn test_validate_priority_rejects_legacy_enum() {
        for p in &["high", "medium", "low", "High", "MEDIUM"] {
            assert!(validate_priority(p).is_err(), "{p} should be rejected");
        }
    }

    #[test]
    fn test_validate_priority_rejects_arbitrary() {
        for p in &["urgent", "P4", "p0", "0"] {
            assert!(validate_priority(p).is_err(), "{p} should be rejected");
        }
    }

    #[test]
    fn test_set_field_rejects_legacy_priority() {
        let mut task = json!({"id": "t-1", "priority": null});
        let err = set_field(&mut task, "priority", "high", false).unwrap_err();
        assert!(err.contains("priority"), "error should mention priority: {err}");
        assert!(task["priority"].is_null(), "task should be unchanged on error");
    }

    #[test]
    fn test_set_field_accepts_valid_priority() {
        let mut task = json!({"id": "t-1", "priority": null});
        set_field(&mut task, "priority", "P0", false).unwrap();
        assert_eq!(task["priority"], "P0");
        set_field(&mut task, "priority", "null", false).unwrap();
        assert!(task["priority"].is_null());
    }

    // ── t-1345: status enum validation ──────────────────────────────────

    #[test]
    fn test_validate_status_accepts_canonical() {
        for s in &["pending", "in_progress", "completed", "cancelled"] {
            assert!(validate_status(s).is_ok(), "{s} should be accepted");
        }
    }

    #[test]
    fn test_validate_status_accepts_null_and_empty() {
        assert!(validate_status("null").is_ok());
        assert!(validate_status("").is_ok());
    }

    #[test]
    fn test_validate_status_rejects_synthetic() {
        for s in &["done", "active", "blocked", "parked"] {
            assert!(validate_status(s).is_err(), "{s} should be rejected (synthetic)");
        }
    }

    #[test]
    fn test_validate_status_rejects_arbitrary() {
        for s in &["DONE", "Pending", "wip", "complete"] {
            assert!(validate_status(s).is_err(), "{s} should be rejected");
        }
    }

    // ── t-2313 (ADR-065): epic status vocabulary ────────────────────────────

    #[test]
    fn test_validate_epic_status_accepts_canonical() {
        for s in &["active", "next", "parked", "done", "archived"] {
            assert!(validate_epic_status(s).is_ok(), "{s} should be accepted");
        }
    }

    #[test]
    fn test_validate_epic_status_accepts_null_and_empty() {
        assert!(validate_epic_status("null").is_ok());
        assert!(validate_epic_status("").is_ok());
    }

    #[test]
    fn test_validate_epic_status_rejects_task_vocab() {
        for s in &["pending", "in_progress", "completed", "cancelled"] {
            assert!(validate_epic_status(s).is_err(), "{s} is task vocab, not epic vocab");
        }
    }

    #[test]
    fn test_validate_epic_status_rejects_arbitrary() {
        for s in &["ACTIVE", "wip", "on-hold"] {
            assert!(validate_epic_status(s).is_err(), "{s} should be rejected");
        }
    }

    #[test]
    fn test_set_field_status_epic_type_uses_epic_vocab() {
        let mut task = json!({"id": "in-1", "type": "epic"});
        set_field(&mut task, "status", "active", false).unwrap();
        assert_eq!(task["status"], "active");
        let err = set_field(&mut task, "status", "in_progress", false).unwrap_err();
        assert!(err.contains("active"), "error must list epic vocab: {err}");
    }

    #[test]
    fn test_set_field_status_non_epic_uses_task_vocab() {
        // Proves a non-epic task's status still validates against the OLD vocab.
        let mut task = json!({"id": "t-1", "type": "task"});
        set_field(&mut task, "status", "in_progress", false).unwrap();
        assert_eq!(task["status"], "in_progress");
        let err = set_field(&mut task, "status", "active", false).unwrap_err();
        assert!(err.contains("pending"), "error must list task vocab: {err}");
    }

    #[test]
    fn test_set_field_status_missing_type_defaults_to_task_vocab() {
        let mut task = json!({"id": "t-1"});
        assert!(set_field(&mut task, "status", "active", false).is_err());
        assert!(set_field(&mut task, "status", "in_progress", false).is_ok());
    }

    // ── t-2314 (ADR-065): active_epic fail-loud resolution ───────────────────

    #[test]
    fn test_assert_active_epic_resolves_via_node() {
        let tasks = vec![json!({"id": "in-1", "type": "epic", "subject": "harness-core", "tags": [], "blocked_by": []})];
        assert!(assert_active_epic_resolves(&tasks, "harness-core").is_ok());
    }

    #[test]
    fn test_assert_active_epic_resolves_via_flat_tag_pre_migration_compat() {
        // Pre-migration data (t-2312's script not yet run against live data):
        // epic membership is still expressed via the flat `epic` field.
        let tasks = vec![json!({"id": "t-1", "type": "task", "epic": "harness-core", "tags": [], "blocked_by": []})];
        assert!(assert_active_epic_resolves(&tasks, "harness-core").is_ok());
    }

    #[test]
    fn test_assert_active_epic_resolves_fails_on_unresolved_slug() {
        let tasks = vec![json!({"id": "t-1", "type": "task", "epic": "other-epic", "tags": [], "blocked_by": []})];
        let err = assert_active_epic_resolves(&tasks, "harness-core").unwrap_err();
        assert!(err.contains("harness-core"), "error must name the unresolved slug: {err}");
    }

    #[test]
    fn test_assert_active_epic_resolves_fails_on_empty_task_list() {
        assert!(assert_active_epic_resolves(&[], "harness-core").is_err());
    }

    // ── t-3203 (ADR-088): resolve_focus_epic() — session-scoped focus,
    // task-derived (not branch-derived), covering v2 (client/venture flat
    // `.epic`) and v3 (thebrana parent-chain) schemas via one helper ──

    #[test]
    fn test_resolve_focus_epic_explicit_arg_short_circuits() {
        // Explicit --epic always wins, even with tasks present that would
        // resolve to something else.
        let tasks = vec![json!({
            "id": "t-1", "type": "task", "status": "in_progress",
            "started": "2026-08-20", "epic": "other-epic"
        })];
        assert_eq!(
            resolve_focus_epic(Some("explicit-epic"), &tasks),
            Some("explicit-epic".to_string())
        );
    }

    #[test]
    fn test_resolve_focus_epic_v2_flat_field() {
        // Client/venture schema: most-recently-started in_progress task
        // carries a flat `.epic` field directly (no parent-chain to walk).
        let tasks = vec![json!({
            "id": "t-1", "type": "task", "status": "in_progress",
            "started": "2026-08-20", "epic": "env-hardening"
        })];
        assert_eq!(
            resolve_focus_epic(None, &tasks),
            Some("env-hardening".to_string())
        );
    }

    #[test]
    fn test_resolve_focus_epic_v3_parent_chain() {
        // thebrana schema: no flat `.epic`, resolve via parent-chain to a
        // real `type: "epic"` node ancestor — reuses resolve_epic_ancestor().
        let tasks = vec![
            json!({"id": "in-002", "type": "epic", "subject": "cc-alignment"}),
            json!({
                "id": "t-1", "type": "task", "status": "in_progress",
                "started": "2026-08-20", "parent": "in-002"
            }),
        ];
        assert_eq!(
            resolve_focus_epic(None, &tasks),
            Some("cc-alignment".to_string())
        );
    }

    #[test]
    fn test_resolve_focus_epic_no_in_progress_task_returns_none() {
        let tasks = vec![json!({
            "id": "t-1", "type": "task", "status": "pending", "epic": "harness-core"
        })];
        assert_eq!(resolve_focus_epic(None, &tasks), None);
    }

    #[test]
    fn test_resolve_focus_epic_unresolvable_epic_returns_none_not_error() {
        // In-progress task exists but its epic (flat or parent-chain) doesn't
        // resolve to anything real — non-fatal, unlike assert_active_epic_resolves.
        let tasks = vec![json!({
            "id": "t-1", "type": "task", "status": "in_progress",
            "started": "2026-08-20", "parent": "does-not-exist"
        })];
        assert_eq!(resolve_focus_epic(None, &tasks), None);
    }

    #[test]
    fn test_resolve_focus_epic_most_recently_started_wins() {
        // Two in_progress tasks — later `started` date wins.
        let tasks = vec![
            json!({"id": "t-1", "type": "task", "status": "in_progress", "started": "2026-08-10", "epic": "old-epic"}),
            json!({"id": "t-2", "type": "task", "status": "in_progress", "started": "2026-08-20", "epic": "new-epic"}),
        ];
        assert_eq!(
            resolve_focus_epic(None, &tasks),
            Some("new-epic".to_string())
        );
    }

    #[test]
    fn test_resolve_focus_epic_tie_break_by_numeric_id_descending() {
        // Same `started` date (realistic — date-only granularity) — higher
        // numeric task ID (created later) wins, matching statusline.sh's
        // own tie-break (statusline.sh:78-89).
        let tasks = vec![
            json!({"id": "t-100", "type": "task", "status": "in_progress", "started": "2026-08-20", "epic": "epic-a"}),
            json!({"id": "t-3196", "type": "task", "status": "in_progress", "started": "2026-08-20", "epic": "epic-b"}),
        ];
        assert_eq!(
            resolve_focus_epic(None, &tasks),
            Some("epic-b".to_string())
        );
    }

    #[test]
    fn test_resolve_focus_epic_empty_task_list_returns_none() {
        assert_eq!(resolve_focus_epic(None, &[]), None);
    }

    #[test]
    fn test_resolve_focus_epic_empty_flat_epic_falls_through_to_parent_chain() {
        // Boundary: an empty-string `.epic` field must not short-circuit as
        // "resolved" — it should fall through to the parent-chain walk.
        let tasks = vec![
            json!({"id": "in-002", "type": "epic", "subject": "cc-alignment"}),
            json!({
                "id": "t-1", "type": "task", "status": "in_progress",
                "started": "2026-08-20", "epic": "", "parent": "in-002"
            }),
        ];
        assert_eq!(
            resolve_focus_epic(None, &tasks),
            Some("cc-alignment".to_string())
        );
    }

    #[test]
    fn test_resolve_focus_epic_rejects_non_slug_epic_subject() {
        // Boundary: a pre-v3 epic marker with a full-sentence subject
        // (in-001..in-004 shape) must not leak through as a resolved slug —
        // resolve_epic_ancestor()'s is_epic_slug() gate already rejects it.
        let tasks = vec![
            json!({"id": "in-001", "type": "epic", "subject": "Backlog UI — rich task views"}),
            json!({
                "id": "t-1", "type": "task", "status": "in_progress",
                "started": "2026-08-20", "parent": "in-001"
            }),
        ];
        assert_eq!(resolve_focus_epic(None, &tasks), None);
    }

    // ── t-2377: TaskFilter.epic must resolve via parent-chain ancestor,
    // not the retired flat `epic` field (ADR-065, t-2284; sealed t-2310) ──

    #[test]
    fn test_filter_tasks_by_epic_resolves_via_parent_chain() {
        let all = vec![
            json!({"id": "t-1", "type": "epic", "subject": "cli-backlog-schema", "parent": null}),
            json!({"id": "t-2", "type": "task", "subject": "child of epic", "parent": "t-1", "status": "pending"}),
            json!({"id": "t-3", "type": "task", "subject": "unrelated", "parent": null, "status": "pending"}),
        ];
        let filter = TaskFilter { epic: Some("cli-backlog-schema"), types: vec!["task"], ..Default::default() };
        let matched = filter_tasks_by(&all, &all, &filter);
        assert_eq!(matched.len(), 1, "expected exactly the epic's child task to match, got {matched:?}");
        assert_eq!(matched[0]["id"], "t-2");
    }

    #[test]
    fn test_filter_tasks_by_epic_no_match_returns_empty() {
        let all = vec![
            json!({"id": "t-1", "type": "epic", "subject": "cli-backlog-schema", "parent": null}),
            json!({"id": "t-2", "type": "task", "subject": "child of epic", "parent": "t-1", "status": "pending"}),
        ];
        let filter = TaskFilter { epic: Some("other-epic"), types: vec!["task"], ..Default::default() };
        let matched = filter_tasks_by(&all, &all, &filter);
        assert!(matched.is_empty());
    }

    #[test]
    fn test_filter_tasks_by_epic_rejects_non_slug_epic_subject() {
        // Pre-v3 in-001..in-004 markers were retyped to type:"epic" but still
        // carry full sentence subjects, not slugs (t-2263 failure class).
        let all = vec![
            json!({"id": "in-1", "type": "epic", "subject": "Backlog UI — rich task views", "parent": null}),
            json!({"id": "t-2", "type": "task", "subject": "child", "parent": "in-1", "status": "pending"}),
        ];
        let filter = TaskFilter { epic: Some("Backlog UI — rich task views"), types: vec!["task"], ..Default::default() };
        let matched = filter_tasks_by(&all, &all, &filter);
        assert!(matched.is_empty(), "non-slug epic subject must never resolve, even on exact string match");
    }

    #[test]
    fn test_filter_tasks_by_no_epic_filter_is_noop() {
        let all = vec![json!({"id": "t-1", "type": "task", "subject": "x", "parent": null, "status": "pending"})];
        let filter = TaskFilter { types: vec!["task"], ..Default::default() };
        let matched = filter_tasks_by(&all, &all, &filter);
        assert_eq!(matched.len(), 1);
    }

    // ── t-939: validate_context_for_effort ──────────────────────────────

    #[test]
    fn test_context_required_for_m_effort() {
        assert!(validate_context_for_effort(Some("M"), None).is_err());
    }

    #[test]
    fn test_context_required_for_l_effort() {
        assert!(validate_context_for_effort(Some("L"), None).is_err());
    }

    #[test]
    fn test_context_required_for_xl_effort() {
        assert!(validate_context_for_effort(Some("XL"), None).is_err());
    }

    #[test]
    fn test_empty_context_rejected_for_m_plus() {
        assert!(validate_context_for_effort(Some("M"), Some("")).is_err());
        assert!(validate_context_for_effort(Some("M"), Some("   ")).is_err());
    }

    #[test]
    fn test_nonempty_context_accepted_for_m_plus() {
        assert!(validate_context_for_effort(Some("M"), Some("why this matters")).is_ok());
        assert!(validate_context_for_effort(Some("L"), Some("detailed context here")).is_ok());
        assert!(validate_context_for_effort(Some("XL"), Some("x")).is_ok());
    }

    #[test]
    fn test_small_efforts_exempt_from_context() {
        assert!(validate_context_for_effort(Some("S"), None).is_ok());
        assert!(validate_context_for_effort(Some("XS"), None).is_ok());
    }

    #[test]
    fn test_no_effort_exempt_from_context() {
        assert!(validate_context_for_effort(None, None).is_ok());
    }

    #[test]
    fn test_unknown_effort_exempt_from_context() {
        assert!(validate_context_for_effort(Some("HUGE"), None).is_ok());
    }

    #[test]
    fn test_set_field_rejects_synthetic_status() {
        let mut task = json!({"id": "t-1", "status": "pending"});
        let err = set_field(&mut task, "status", "done", false).unwrap_err();
        assert!(err.contains("status"), "error should mention status: {err}");
        assert_eq!(task["status"], "pending", "task should be unchanged on error");
    }

    #[test]
    fn test_set_field_accepts_valid_status() {
        let mut task = json!({"id": "t-1", "status": "pending"});
        set_field(&mut task, "status", "completed", false).unwrap();
        assert_eq!(task["status"], "completed");
        set_field(&mut task, "status", "cancelled", false).unwrap();
        assert_eq!(task["status"], "cancelled");
    }

    // ── t-1346: raw_status accessor ─────────────────────────────────────

    #[test]
    fn test_raw_status_returns_field_value() {
        let task = json!({"id": "t-1", "status": "in_progress"});
        assert_eq!(raw_status(&task, ""), "in_progress");
    }

    #[test]
    fn test_raw_status_uses_default_when_missing() {
        let task = json!({"id": "t-1"});
        assert_eq!(raw_status(&task, ""), "");
        assert_eq!(raw_status(&task, "unknown"), "unknown");
    }

    #[test]
    fn test_raw_status_uses_default_when_null() {
        let task = json!({"id": "t-1", "status": null});
        assert_eq!(raw_status(&task, "unknown"), "unknown");
    }

    #[test]
    fn test_raw_status_does_not_synthesize() {
        // Even if a task is "blocked" (would synthesize via classify), raw_status
        // returns the literal stored field — never classify() output.
        let task = json!({"id": "t-1", "status": "pending", "blocked_by": ["t-99"]});
        assert_eq!(raw_status(&task, ""), "pending");
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

    // ── t-2315 (ADR-065): wave process-object CRUD ──────────────────────

    #[test]
    fn test_next_wave_id_empty() {
        let waves: Vec<Value> = vec![];
        assert_eq!(next_wave_id(&waves), "wave-1");
    }

    #[test]
    fn test_next_wave_id_increments() {
        let waves = vec![json!({"id": "wave-1"}), json!({"id": "wave-4"})];
        assert_eq!(next_wave_id(&waves), "wave-5");
    }

    #[test]
    fn test_validate_wave_status_accepts_canonical() {
        for s in &["queued", "draining", "shipped"] {
            assert!(validate_wave_status(s).is_ok(), "{s} should be accepted");
        }
    }

    #[test]
    fn test_validate_wave_status_accepts_null_and_empty() {
        assert!(validate_wave_status("null").is_ok());
        assert!(validate_wave_status("").is_ok());
    }

    #[test]
    fn test_validate_wave_status_rejects_arbitrary() {
        for s in &["QUEUED", "active", "wip", "done"] {
            assert!(validate_wave_status(s).is_err(), "{s} should be rejected");
        }
    }

    #[test]
    fn test_set_wave_field_status() {
        let mut wave = json!({"id": "wave-1", "status": "queued"});
        set_wave_field(&mut wave, "status", "draining").unwrap();
        assert_eq!(wave["status"], "draining");
    }

    #[test]
    fn test_set_wave_field_status_rejects_invalid() {
        let mut wave = json!({"id": "wave-1", "status": "queued"});
        let err = set_wave_field(&mut wave, "status", "bogus").unwrap_err();
        assert!(err.contains("queued/draining/shipped"), "error must name valid vocab: {err}");
        assert_eq!(wave["status"], "queued", "rejected write must not mutate");
    }

    #[test]
    fn test_set_wave_field_status_allows_any_to_any() {
        // No forward-only enforcement — matches validate_status/validate_epic_status precedent.
        let mut wave = json!({"id": "wave-1", "status": "shipped"});
        set_wave_field(&mut wave, "status", "queued").unwrap();
        assert_eq!(wave["status"], "queued", "shipped -> queued must be allowed (free transitions)");
    }

    #[test]
    fn test_set_wave_field_selector_contract_gate() {
        let mut wave = json!({"id": "wave-1"});
        set_wave_field(&mut wave, "selector", "shape:mechanical").unwrap();
        set_wave_field(&mut wave, "contract", "all tests green").unwrap();
        set_wave_field(&mut wave, "gate", "wave-0").unwrap();
        assert_eq!(wave["selector"], "shape:mechanical");
        assert_eq!(wave["contract"], "all tests green");
        assert_eq!(wave["gate"], "wave-0");
    }

    // ── t-2782 (ADR-079 §3): wip_limit integer arm + draining-edit rejection ──

    #[test]
    fn test_set_wave_field_wip_limit_integer() {
        // First non-string wave field: stored as a JSON number, not a string —
        // a "3" string would defeat any numeric comparison at the loop's pull
        // step (the json-version-string-defeats-numeric-gate class).
        let mut wave = json!({"id": "wave-1", "status": "queued"});
        set_wave_field(&mut wave, "wip_limit", "3").unwrap();
        assert_eq!(wave["wip_limit"], json!(3));
        assert!(wave["wip_limit"].is_u64(), "must be a number, not a string");
    }

    #[test]
    fn test_set_wave_field_wip_limit_zero_and_null() {
        // 0 is legal (pause pulling); null clears back to unbounded (the default).
        let mut wave = json!({"id": "wave-1", "status": "queued", "wip_limit": 3});
        set_wave_field(&mut wave, "wip_limit", "0").unwrap();
        assert_eq!(wave["wip_limit"], json!(0));
        set_wave_field(&mut wave, "wip_limit", "null").unwrap();
        assert!(wave["wip_limit"].is_null());
    }

    #[test]
    fn test_set_wave_field_wip_limit_rejects_non_integer() {
        for bad in ["abc", "-1", "3.5", "", "3 "] {
            let mut wave = json!({"id": "wave-1", "status": "queued"});
            let err = set_wave_field(&mut wave, "wip_limit", bad).unwrap_err();
            assert!(
                err.contains("non-negative integer"),
                "error must name the expected shape for {bad:?}: {err}"
            );
            assert!(wave.get("wip_limit").is_none(), "rejected write must not mutate ({bad:?})");
        }
    }

    #[test]
    fn test_set_wave_field_selector_and_gate_rejected_while_draining() {
        // ADR-079 §3: waves have no log field, so a mid-drain selector/gate edit
        // would silently redirect the next pull cycle with zero audit trail.
        for field in ["selector", "gate"] {
            let mut wave = json!({
                "id":"wave-1","status":"draining","selector":"tag:x","gate":null
            });
            let before = wave.clone();
            let err = set_wave_field(&mut wave, field, "tag:y").unwrap_err();
            assert!(err.contains("requeue"), "error must say how to proceed: {err}");
            assert_eq!(wave, before, "rejected {field} edit must not mutate");
        }
    }

    #[test]
    fn test_set_wave_field_draining_still_allows_other_fields() {
        // Only selector/gate freeze during drain: status must stay writable
        // (requeue IS a status write), and name/contract/wip_limit are harmless.
        let mut wave = json!({"id":"wave-1","status":"draining","selector":"tag:x"});
        set_wave_field(&mut wave, "name", "renamed").unwrap();
        set_wave_field(&mut wave, "contract", "tests green").unwrap();
        set_wave_field(&mut wave, "wip_limit", "2").unwrap();
        set_wave_field(&mut wave, "status", "queued").unwrap();
        assert_eq!(wave["status"], "queued");
        // ...and once requeued, the selector edit goes through.
        set_wave_field(&mut wave, "selector", "tag:y").unwrap();
        assert_eq!(wave["selector"], "tag:y");
    }

    // ── t-2813 (ADR-079 §2/§3): wave pull — decision + atomic file-level ──

    fn pull_wave(status: &str, wip: Option<u64>) -> Value {
        let mut w = json!({"id":"wave-1","name":"w","selector":"tag:w1","status":status});
        if let Some(n) = wip {
            w["wip_limit"] = json!(n);
        }
        w
    }

    fn pull_task(id: &str, status: &str, ac_state: Option<&str>, tags: &[&str]) -> Value {
        let mut t = json!({"id":id,"subject":format!("s-{id}"),"status":status,"tags":tags});
        if let Some(a) = ac_state {
            t["ac_state"] = json!(a);
        }
        t
    }

    #[test]
    fn test_wave_pull_decision_pulls_first_eligible_in_array_order() {
        let wave = pull_wave("draining", Some(2));
        let tasks = vec![
            pull_task("t-1", "pending", Some("proposed"), &["w1"]), // unapproved
            pull_task("t-2", "pending", Some("approved"), &["w1"]), // first eligible
            pull_task("t-3", "pending", Some("approved"), &["w1"]),
        ];
        let d = wave_pull_decision(&wave, &tasks).unwrap();
        assert_eq!(d, PullDecision::Pulled { task_id: "t-2".into() });
    }

    #[test]
    fn test_wave_pull_decision_filters_unapproved_and_parked() {
        // ADR-079 §2 eligibility: pending ∧ approved ∧ ¬parked. ADR-078 parks
        // by tag while status stays pending — without the exclusion the loop
        // would autonomously work deliberately shelved tasks.
        let wave = pull_wave("draining", None);
        let tasks = vec![
            pull_task("t-1", "pending", Some("proposed"), &["w1"]),
            pull_task("t-2", "pending", None, &["w1"]),                    // legacy, no ac_state
            pull_task("t-3", "pending", Some("approved"), &["w1", "parked"]),
        ];
        let d = wave_pull_decision(&wave, &tasks).unwrap();
        assert_eq!(
            d,
            PullDecision::NoneEligible { matched: 3, unapproved: 2, parked: 1, blocked: 0 },
            "matched-but-not-eligible is visible and expected, not a bug"
        );
    }

    // t-3043 (ADR-079 §2 amendment, ADR-086 §4): the pull frontier is
    // open ∧ unblocked — a task with an unmet blocked_by is never pulled,
    // even when it is approved and sits first in array order. Live miss this
    // pins: wave-11 pulled t-2919 before its blocker t-2920.
    #[test]
    fn test_wave_pull_decision_skips_blocked_task_pulls_its_blocker() {
        let wave = pull_wave("draining", None);
        let mut blocked = pull_task("t-2", "pending", Some("approved"), &["w1"]);
        blocked["blocked_by"] = json!(["t-1"]);
        let tasks = vec![
            blocked,                                                 // first in order, but blocked
            pull_task("t-1", "pending", Some("approved"), &["w1"]), // its blocker — the correct pull
        ];
        let d = wave_pull_decision(&wave, &tasks).unwrap();
        assert_eq!(d, PullDecision::Pulled { task_id: "t-1".into() });
    }

    #[test]
    fn test_wave_pull_decision_reports_blocked_count_and_cancelled_is_unmet() {
        let wave = pull_wave("draining", None);
        let mut b1 = pull_task("t-2", "pending", Some("approved"), &["w1"]);
        b1["blocked_by"] = json!(["t-1"]);
        let mut b2 = pull_task("t-3", "pending", Some("approved"), &["w1"]);
        b2["blocked_by"] = json!(["t-canc"]); // cancelled blocker ≠ resolved
        let tasks = vec![
            b1,
            b2,
            pull_task("t-1", "in_progress", Some("approved"), &["w1"]),
            json!({"id": "t-canc", "status": "cancelled", "tags": [], "blocked_by": []}),
        ];
        let d = wave_pull_decision(&wave, &tasks).unwrap();
        assert_eq!(
            d,
            PullDecision::NoneEligible { matched: 2, unapproved: 0, parked: 0, blocked: 2 },
            "matched-but-blocked must be reported, not hidden"
        );
    }

    #[test]
    fn test_wave_pull_decision_at_limit_counts_in_progress_matches() {
        let wave = pull_wave("draining", Some(1));
        let tasks = vec![
            pull_task("t-1", "in_progress", Some("approved"), &["w1"]), // live
            pull_task("t-2", "pending", Some("approved"), &["w1"]),     // eligible but capped
        ];
        let d = wave_pull_decision(&wave, &tasks).unwrap();
        assert_eq!(d, PullDecision::AtLimit { live: 1, limit: 1 });
    }

    #[test]
    fn test_wave_pull_decision_null_wip_limit_is_unbounded() {
        let wave = pull_wave("draining", None);
        let tasks = vec![
            pull_task("t-1", "in_progress", Some("approved"), &["w1"]),
            pull_task("t-2", "in_progress", Some("approved"), &["w1"]),
            pull_task("t-3", "pending", Some("approved"), &["w1"]),
        ];
        let d = wave_pull_decision(&wave, &tasks).unwrap();
        assert_eq!(d, PullDecision::Pulled { task_id: "t-3".into() });
    }

    #[test]
    fn test_wave_pull_decision_zero_limit_pauses() {
        // wip_limit 0 = pause pulling (t-2782) — always at limit.
        let wave = pull_wave("draining", Some(0));
        let tasks = vec![pull_task("t-1", "pending", Some("approved"), &["w1"])];
        let d = wave_pull_decision(&wave, &tasks).unwrap();
        assert_eq!(d, PullDecision::AtLimit { live: 0, limit: 0 });
    }

    #[test]
    fn test_wave_pull_decision_refuses_non_draining_wave() {
        for status in ["queued", "shipped"] {
            let wave = pull_wave(status, None);
            let err = wave_pull_decision(&wave, &[]).unwrap_err();
            assert!(
                err.contains("draining"),
                "pull from a {status} wave must refuse, naming the required state: {err}"
            );
        }
    }

    #[test]
    fn test_pull_wave_task_persists_and_respects_limit() {
        use std::io::Write;
        let body = r#"{"version":1,"project":"p",
            "tasks":[{"id":"t-1","subject":"a","status":"pending","type":"task","tags":["w1"],"blocked_by":[],"ac_state":"approved"}],
            "waves":[{"id":"wave-1","name":"w","selector":"tag:w1","gate":null,"status":"draining","wip_limit":1}]}"#;
        let mut f = tempfile::NamedTempFile::new().unwrap();
        write!(f, "{body}").unwrap();

        // First pull: t-1 goes in_progress with a started date, persisted.
        let d = pull_wave_task(f.path(), "wave-1", "test-pump:s1").unwrap();
        assert_eq!(d, PullDecision::Pulled { task_id: "t-1".into() });
        let reloaded: Value =
            serde_json::from_str(&std::fs::read_to_string(f.path()).unwrap()).unwrap();
        let t1 = &reloaded["tasks"][0];
        assert_eq!(t1["status"], "in_progress");
        assert!(t1["started"].is_string(), "pull must stamp started");

        // Second pull: at limit now — and the no-write outcome must not
        // touch the file (byte-stable modulo nothing: reload and compare).
        let before = std::fs::read_to_string(f.path()).unwrap();
        let d2 = pull_wave_task(f.path(), "wave-1", "test-pump:s1").unwrap();
        assert_eq!(d2, PullDecision::AtLimit { live: 1, limit: 1 });
        assert_eq!(
            std::fs::read_to_string(f.path()).unwrap(),
            before,
            "a non-pulling decision must not rewrite the file"
        );
    }

    #[test]
    fn test_dry_run_wave_pull_reports_would_pull_writes_nothing() {
        use std::io::Write;
        let body = r#"{"version":1,"project":"p",
            "tasks":[{"id":"t-1","subject":"a","status":"pending","type":"task","tags":["w1"],"blocked_by":[],"ac_state":"approved"}],
            "waves":[{"id":"wave-1","name":"w","selector":"tag:w1","gate":null,"status":"draining","wip_limit":1}]}"#;
        let mut f = tempfile::NamedTempFile::new().unwrap();
        write!(f, "{body}").unwrap();
        let before = std::fs::read_to_string(f.path()).unwrap();
        let (d, simulated) = dry_run_wave_pull(f.path(), "wave-1").unwrap();
        assert_eq!(d, PullDecision::Pulled { task_id: "t-1".into() });
        assert!(!simulated, "draining wave needs no simulation");
        assert_eq!(std::fs::read_to_string(f.path()).unwrap(), before,
            "dry-run must be byte-identical — it writes nothing");
    }

    #[test]
    fn test_dry_run_wave_pull_simulates_queued_as_draining() {
        // AC 5: rehearse an unarmed (queued) wave — decision computed as-if
        // draining, flagged simulated, still zero writes.
        use std::io::Write;
        let body = r#"{"version":1,"project":"p",
            "tasks":[{"id":"t-1","subject":"a","status":"pending","type":"task","tags":["w1"],"blocked_by":[],"ac_state":"approved"}],
            "waves":[{"id":"wave-1","name":"w","selector":"tag:w1","gate":null,"status":"queued","wip_limit":1}]}"#;
        let mut f = tempfile::NamedTempFile::new().unwrap();
        write!(f, "{body}").unwrap();
        let before = std::fs::read_to_string(f.path()).unwrap();
        let (d, simulated) = dry_run_wave_pull(f.path(), "wave-1").unwrap();
        assert_eq!(d, PullDecision::Pulled { task_id: "t-1".into() });
        assert!(simulated, "queued wave must be labeled as simulated");
        assert_eq!(std::fs::read_to_string(f.path()).unwrap(), before);
        // The strict path stays strict: direct pull on queued still refuses.
        let err = pull_wave_task(f.path(), "wave-1", "test-pump:s1").unwrap_err();
        assert!(err.contains("draining"), "{err}");
    }

    #[test]
    fn test_dry_run_wave_pull_shipped_remains_caller_error() {
        use std::io::Write;
        let body = r#"{"version":1,"project":"p","tasks":[],
            "waves":[{"id":"wave-1","name":"w","selector":"tag:w1","gate":null,"status":"shipped"}]}"#;
        let mut f = tempfile::NamedTempFile::new().unwrap();
        write!(f, "{body}").unwrap();
        let err = dry_run_wave_pull(f.path(), "wave-1").unwrap_err();
        assert!(err.contains("shipped"), "shipped is not rehearsable: {err}");
    }

    #[test]
    fn test_pull_wave_task_unknown_wave_errors() {
        use std::io::Write;
        let mut f = tempfile::NamedTempFile::new().unwrap();
        write!(f, r#"{{"version":1,"project":"p","tasks":[],"waves":[]}}"#).unwrap();
        let err = pull_wave_task(f.path(), "wave-9", "test-pump:s1").unwrap_err();
        assert!(err.contains("wave-9"), "{err}");
    }

    // ── t-2841 (ADR-080 §5): lease + reclaim_count on atomic pull ────────

    #[test]
    fn test_pull_writes_lease_with_claimant_and_24h_expiry() {
        use std::io::Write;
        let body = r#"{"version":1,"project":"p",
            "tasks":[{"id":"t-1","subject":"a","status":"pending","type":"task","tags":["w1"],"blocked_by":[],"ac_state":"approved"}],
            "waves":[{"id":"wave-1","name":"w","selector":"tag:w1","gate":null,"status":"draining","wip_limit":1}]}"#;
        let mut f = tempfile::NamedTempFile::new().unwrap();
        write!(f, "{body}").unwrap();
        let d = pull_wave_task(f.path(), "wave-1", "drain-3:sess-b6c7").unwrap();
        assert_eq!(d, PullDecision::Pulled { task_id: "t-1".into() });
        let reloaded: Value =
            serde_json::from_str(&std::fs::read_to_string(f.path()).unwrap()).unwrap();
        let t1 = &reloaded["tasks"][0];
        // Lease persisted in the SAME write as in_progress (one critical section).
        assert_eq!(t1["status"], "in_progress");
        assert_eq!(t1["lease"]["claimant"], "drain-3:sess-b6c7");
        let exp = chrono::DateTime::parse_from_rfc3339(t1["lease"]["expires"].as_str()
            .expect("lease.expires must be an RFC3339 string")).unwrap();
        let ttl = exp.signed_duration_since(chrono::Local::now());
        assert!(ttl > chrono::Duration::hours(23) && ttl < chrono::Duration::hours(25),
            "default TTL must be ~24h, got {ttl}");
        // reclaim_count is NOT invented at pull time — key absent (ADR-067).
        assert!(t1.get("reclaim_count").is_none(),
            "pull must not create reclaim_count");
    }

    #[test]
    fn test_status_write_clears_lease_reclaim_count_survives() {
        // Ack path: ANY status write clears lease; reclaim_count lives
        // OUTSIDE lease and must survive lease clearing.
        let mut task = json!({"id":"t-1","status":"in_progress",
            "lease":{"claimant":"pump:x","expires":"2026-08-15T10:00:00+00:00"},
            "reclaim_count":1});
        set_field(&mut task, "status", "pending", false).unwrap();
        assert!(task.get("lease").is_none(),
            "status write must remove lease key entirely (absence, not null)");
        assert_eq!(task["reclaim_count"], 1,
            "reclaim_count must survive lease clearing");
    }

    #[test]
    fn test_completed_status_clears_lease_and_reclaim_count() {
        let mut task = json!({"id":"t-1","status":"in_progress",
            "lease":{"claimant":"pump:x","expires":"2026-08-15T10:00:00+00:00"},
            "reclaim_count":2});
        set_field(&mut task, "status", "completed", false).unwrap();
        assert!(task.get("lease").is_none(), "completion clears lease");
        assert!(task.get("reclaim_count").is_none(),
            "completion removes reclaim_count (key absent, not null)");
    }

    #[test]
    fn test_non_status_write_preserves_lease() {
        // Only status writes are acks — a notes/context append mid-flight
        // must not release the claim.
        let mut task = json!({"id":"t-1","status":"in_progress",
            "lease":{"claimant":"pump:x","expires":"2026-08-15T10:00:00+00:00"}});
        set_field(&mut task, "notes", "progress note", true).unwrap();
        assert_eq!(task["lease"]["claimant"], "pump:x",
            "non-status writes must not clear the lease");
    }

    #[test]
    fn test_manual_status_write_takes_no_lease() {
        // Manual `backlog start` (a plain status write) must NOT create a
        // lease — human work is not watchdog-reclaimable (ADR-080 §5).
        let mut task = json!({"id":"t-1","status":"pending"});
        set_field(&mut task, "status", "in_progress", false).unwrap();
        assert!(task.get("lease").is_none(), "manual start takes no lease");
        assert!(task.get("reclaim_count").is_none());
    }

    #[test]
    fn test_rollup_completion_clears_lease_and_reclaim_count() {
        // Evaluator gap (t-2841): rollup writes status directly — it must go
        // through the same ack as set_field, or a leased task completed via
        // rollup strands its lease. "ANY status write clears lease" (AC2).
        use std::io::Write;
        let body = r#"{"version":1,"project":"p","tasks":[
            {"id":"t-p","subject":"parent","status":"in_progress","type":"milestone","tags":[],"blocked_by":[],
             "lease":{"claimant":"pump:x","expires":"2026-08-15T10:00:00+00:00"},"reclaim_count":1},
            {"id":"t-c","subject":"child","status":"completed","type":"task","parent":"t-p","tags":[],"blocked_by":[]}
        ]}"#;
        let mut f = tempfile::NamedTempFile::new().unwrap();
        write!(f, "{body}").unwrap();
        let rolled = perform_rollup(f.path(), false).unwrap();
        assert!(rolled.contains(&"t-p".to_string()), "fixture: parent must roll up");
        let reloaded: Value =
            serde_json::from_str(&std::fs::read_to_string(f.path()).unwrap()).unwrap();
        let tp = &reloaded["tasks"][0];
        assert_eq!(tp["status"], "completed");
        assert!(tp.get("lease").is_none(), "rollup completion must clear lease");
        assert!(tp.get("reclaim_count").is_none(),
            "rollup completion must retire reclaim_count");
    }

    #[test]
    fn test_ack_status_write_helper_semantics() {
        // The single ack owner all status writers route through.
        let mut t = json!({"id":"t-1","status":"in_progress",
            "lease":{"claimant":"pump:x","expires":"2026-08-15T10:00:00+00:00"},
            "reclaim_count":3});
        ack_status_write(&mut t, "pending");
        assert!(t.get("lease").is_none());
        assert_eq!(t["reclaim_count"], 3);
        ack_status_write(&mut t, "completed");
        assert!(t.get("reclaim_count").is_none());
    }

    #[test]
    fn test_set_wave_field_gate_nonexistent_wave_id_not_validated() {
        // No referential check — matches parent/blocked_by precedent (t-2315 design call).
        let mut wave = json!({"id": "wave-1"});
        set_wave_field(&mut wave, "gate", "wave-999").unwrap();
        assert_eq!(wave["gate"], "wave-999");
    }

    #[test]
    fn test_set_wave_field_gate_clear_to_null() {
        let mut wave = json!({"id": "wave-1", "gate": "wave-0"});
        set_wave_field(&mut wave, "gate", "null").unwrap();
        assert!(wave["gate"].is_null());
    }

    #[test]
    fn test_set_wave_field_rejects_unknown_field() {
        let mut wave = json!({"id": "wave-1"});
        let err = set_wave_field(&mut wave, "bogus_field", "x").unwrap_err();
        assert!(err.contains("bogus_field"));
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

        // by_status uses raw task.status values (matches filter_tasks predicate
        // and CLI TaskStatus enum). t-1340.
        assert_eq!(stats["by_status"]["pending"], 4); // t-003, t-004, t-005, ph-001
        assert_eq!(stats["by_status"]["in_progress"], 1); // t-002
        assert_eq!(stats["by_status"]["completed"], 1); // t-001
        assert_eq!(stats["by_status"]["cancelled"], 1); // t-006
        assert!(stats["by_status"].get("done").is_none()); // synthetic must not leak in
        assert!(stats["by_status"].get("blocked").is_none());

        // by_state uses synthetic classify() output for display rollups.
        assert_eq!(stats["by_state"]["done"], 2); // t-001 + t-006
        assert_eq!(stats["by_state"]["active"], 1); // t-002
        assert_eq!(stats["by_state"]["blocked"], 1); // t-004 (blocked_by t-002)
        assert_eq!(stats["by_state"]["parked"], 1); // t-005
        assert_eq!(stats["by_state"]["pending"], 2); // t-003, ph-001
    }

    #[test]
    fn test_compute_stats_by_work_type() {
        let tasks = vec![
            json!({"id": "t-1", "type": "task", "status": "pending", "work_type": "implement", "tags": [], "blocked_by": []}),
            json!({"id": "t-2", "type": "task", "status": "completed", "work_type": "implement", "tags": [], "blocked_by": []}),
            json!({"id": "t-3", "type": "task", "status": "pending", "work_type": "research", "tags": [], "blocked_by": []}),
        ];
        let stats = compute_stats(&tasks, &tasks);
        assert_eq!(stats["by_work_type"]["implement"], 2);
        assert_eq!(stats["by_work_type"]["research"], 1);
        assert!(stats.get("by_stream").is_none(), "by_stream must not appear in stats output");
    }

    #[test]
    fn test_compute_stats_by_epic_parent_chain() {
        // t-2740 (ADR-065): by_epic must resolve membership via the parent
        // chain — the flat `epic` field was stripped from live data, so the
        // old `t["epic"].as_str()` read left by_epic permanently empty.
        let tasks = vec![
            json!({"id": "ep-1", "type": "epic", "subject": "cc-alignment", "parent": null, "status": "pending", "tags": [], "blocked_by": []}),
            json!({"id": "t-1", "type": "task", "subject": "direct child", "parent": "ep-1", "status": "pending", "tags": [], "blocked_by": []}),
            json!({"id": "t-2", "type": "task", "subject": "nested child", "parent": "t-1", "status": "pending", "tags": [], "blocked_by": []}),
            json!({"id": "t-3", "type": "task", "subject": "epic-less", "parent": null, "status": "pending", "tags": [], "blocked_by": []}),
        ];
        let stats = compute_stats(&tasks, &tasks);
        assert_eq!(stats["by_epic"]["cc-alignment"], 2, "direct + nested child must both resolve via parent chain");
        // The epic node is not a member of its own epic and the epic-less task
        // lands in no bucket (no "(none)" convention) — exactly one key.
        assert_eq!(stats["by_epic"].as_object().unwrap().len(), 1);
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
        let result = filter_tasks(&tasks, &tasks, Some("scheduler"), None, None, None, None, &["task", "subtask"], None, None);
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
        let task = json!({"description": "fix typo", "blocked_by": [], "tags": [], "effort": "S"});
        let score = complexity_score(&task);
        assert!(score < 0.3, "minimal task should score < 0.3, got {score}");
    }

    #[test]
    fn test_complexity_score_complex() {
        let task = json!({
            "description": "Implement the full authentication system with JWT tokens, refresh rotation, middleware integration, session management, and database schema changes for the user auth table",
            "blocked_by": ["t-001", "t-002"],
            "kind": "feature",
            "work_type": "implement",
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
            json!({"id": "t-001", "status": "pending", "type": "task", "subject": "First", "priority": "P1", "effort": "S", "blocked_by": [], "tags": [], "description": "fix"}),
            json!({"id": "t-002", "status": "pending", "type": "task", "subject": "Second", "priority": "P2", "effort": "M", "blocked_by": [], "tags": [], "description": "build feature"}),
            json!({"id": "t-003", "status": "completed", "type": "task", "subject": "Done", "priority": "P0", "effort": "S", "blocked_by": [], "tags": [], "description": "done"}),
        ];
        let q = queue_candidates(&tasks, 5);
        assert_eq!(q.len(), 2); // only pending
        assert_eq!(q[0]["id"], "t-001"); // P1 before P2
    }

    #[test]
    fn test_queue_candidates_respects_max() {
        let tasks = vec![
            json!({"id": "t-001", "status": "pending", "type": "task", "subject": "A", "priority": "P1", "blocked_by": [], "tags": [], "description": "", "effort": null}),
            json!({"id": "t-002", "status": "pending", "type": "task", "subject": "B", "priority": "P2", "blocked_by": [], "tags": [], "description": "", "effort": null}),
            json!({"id": "t-003", "status": "pending", "type": "task", "subject": "C", "priority": "P3", "blocked_by": [], "tags": [], "description": "", "effort": null}),
        ];
        let q = queue_candidates(&tasks, 2);
        assert_eq!(q.len(), 2);
    }

    #[test]
    fn test_queue_candidates_skips_blocked() {
        let tasks = vec![
            json!({"id": "t-001", "status": "pending", "type": "task", "subject": "Blocked", "priority": "P1", "blocked_by": ["t-002"], "tags": [], "description": "", "effort": null}),
            json!({"id": "t-002", "status": "pending", "type": "task", "subject": "Blocker", "priority": "P2", "blocked_by": [], "tags": [], "description": "", "effort": null}),
        ];
        let q = queue_candidates(&tasks, 5);
        assert_eq!(q.len(), 1);
        assert_eq!(q[0]["id"], "t-002"); // only unblocked
    }

    // ── Wave 7: brana run helpers ────────────────────────────────────────

    #[test]
    fn test_branch_for_implement_task() {
        let task = json!({"id": "t-001", "work_type": "implement", "subject": "My Task Name"});
        assert_eq!(branch_for_task(&task), "feat/t-001-my-task-name");
    }

    #[test]
    fn test_branch_for_fix_kind() {
        let task = json!({"id": "t-002", "kind": "fix", "work_type": "implement", "subject": "Crash on login"});
        assert_eq!(branch_for_task(&task), "fix/t-002-crash-on-login");
    }

    #[test]
    fn test_branch_for_research_task() {
        let task = json!({"id": "t-003", "work_type": "research", "subject": "Evaluate Options"});
        assert_eq!(branch_for_task(&task), "research/t-003-evaluate-options");
    }

    #[test]
    fn test_branch_for_refactor_kind() {
        let task = json!({"id": "t-010", "kind": "refactor", "work_type": "implement", "subject": "Clean up imports"});
        assert_eq!(branch_for_task(&task), "refactor/t-010-clean-up-imports");
    }

    #[test]
    fn test_branch_for_long_subject() {
        let task = json!({"id": "t-004", "work_type": "implement", "subject": "This is a very long task subject that should be truncated to forty characters"});
        let branch = branch_for_task(&task);
        // slug part (after "feat/t-004-") should be truncated
        let slug = branch.strip_prefix("feat/t-004-").unwrap();
        assert!(slug.len() <= 40);
    }

    #[test]
    fn test_branch_for_special_chars() {
        let task = json!({"id": "t-005", "work_type": "implement", "subject": "What's the deal? (100% done!)"});
        let branch = branch_for_task(&task);
        assert_eq!(branch, "feat/t-005-what-s-the-deal-100-done");
    }

    #[test]
    fn test_worktree_path_feat() {
        let task = json!({"id": "t-001", "work_type": "implement"});
        assert_eq!(worktree_path_for_task(&task, "thebrana"), "../thebrana-feat/t-001");
    }

    #[test]
    fn test_worktree_path_fix() {
        let task = json!({"id": "t-002", "kind": "fix", "work_type": "implement"});
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

    // t-3166: the run gate shares the blocked_by resolver with classify —
    // cancelled and missing blockers stay unmet; a done epic resolves.
    #[test]
    fn test_validate_runnable_cancelled_blocker_still_blocks() {
        let tasks = vec![
            json!({"id": "t-001", "status": "pending", "blocked_by": ["t-002"]}),
            json!({"id": "t-002", "status": "cancelled", "blocked_by": []}),
        ];
        let err = validate_task_runnable(&tasks[0], &tasks).unwrap_err();
        assert!(err.contains("blocked by t-002"), "{err}");
    }

    #[test]
    fn test_validate_runnable_missing_blocker_blocks() {
        let tasks = vec![
            json!({"id": "t-001", "status": "pending", "blocked_by": ["t-ghost"]}),
        ];
        let err = validate_task_runnable(&tasks[0], &tasks).unwrap_err();
        assert!(err.contains("blocked by t-ghost"), "{err}");
    }

    #[test]
    fn test_validate_runnable_done_epic_blocker_resolves() {
        let tasks = vec![
            json!({"id": "t-001", "status": "pending", "blocked_by": ["in-1"]}),
            json!({"id": "in-1", "status": "done", "type": "epic", "blocked_by": []}),
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

    /// t-2380: a torn/truncated read caused by a concurrent out-of-band, non-atomic
    /// writer (e.g. `git checkout` rewriting the working-tree file in place on a
    /// shared checkout) should self-heal once that writer's own write completes,
    /// instead of surfacing a one-shot parse error. Proxy for the real race: seed
    /// the file with content that fails to parse, then fix it up from another
    /// thread shortly after — well inside the retry window — and confirm load_raw
    /// still returns the valid, final content rather than the earlier error.
    #[test]
    fn test_load_raw_retries_past_transient_parse_failure() {
        let dir = std::env::temp_dir().join("brana-test-load-raw-retry");
        std::fs::create_dir_all(&dir).ok();
        let path = dir.join("tasks.json");
        // Simulates a torn read: truncated/garbled bytes mid-write.
        std::fs::write(&path, "{\"project\":\"test\",\"tasks\":[{\"id\":\"t-1\"\u{0}").unwrap();

        let fixer_path = path.clone();
        let handle = std::thread::spawn(move || {
            std::thread::sleep(std::time::Duration::from_millis(20));
            std::fs::write(&fixer_path, r#"{"project":"test","tasks":[{"id":"t-1"}]}"#).unwrap();
        });

        let val = load_raw(&path).expect("load_raw should retry past the transient failure");
        handle.join().unwrap();

        assert_eq!(val["tasks"][0]["id"], "t-1");
        std::fs::remove_dir_all(&dir).ok();
    }

    // ── complexity_score edge cases ──────────────────────────────────

    #[test]
    fn test_complexity_score_max_components() {
        // All 5 components at max: 0.3 + 0.2 + 0.2 + 0.1 + 0.1 = 0.9
        let task = json!({
            "description": std::iter::repeat("word ").take(200).collect::<String>(),
            "blocked_by": ["t-1","t-2","t-3","t-4","t-5"],
            "kind": "feature",
            "work_type": "implement",
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
    fn test_complexity_score_implement_feature_only() {
        let task = json!({"kind": "feature", "work_type": "implement", "blocked_by": [], "tags": [], "effort": "S"});
        let score = complexity_score(&task);
        assert!((score - 0.2).abs() < f64::EPSILON, "implement-feature-only should be 0.2, got {score}");
    }

    #[test]
    fn test_recommended_model_boundary() {
        assert_eq!(recommended_model(0.0), "haiku");
        assert_eq!(recommended_model(0.3), "sonnet");
        assert_eq!(recommended_model(0.7), "sonnet");
        assert_eq!(recommended_model(0.700001), "opus");
    }

    // ── burndown tests ──────────────────────────────────────────────

    #[test]
    fn test_burndown_week() {
        let today = chrono::Local::now().date_naive().format("%Y-%m-%d").to_string();
        let old = "2020-01-01";
        let tasks = vec![
            json!({"id": "t-1", "type": "task", "created": today, "completed": null}),
            json!({"id": "t-2", "type": "task", "created": old, "completed": today}),
            json!({"id": "t-3", "type": "phase", "created": today, "completed": today}), // excluded
        ];
        let result = burndown(&tasks, "week");
        assert_eq!(result["created"], 1); // only t-1 (t-3 is phase)
        assert_eq!(result["completed"], 1); // only t-2 (t-3 is phase)
        assert_eq!(result["delta"], 0);
        assert_eq!(result["direction"], "stable");
    }

    #[test]
    fn test_burndown_shrinking() {
        let today = chrono::Local::now().date_naive().format("%Y-%m-%d").to_string();
        let tasks = vec![
            json!({"id": "t-1", "type": "task", "created": "2020-01-01", "completed": &today}),
            json!({"id": "t-2", "type": "task", "created": "2020-01-02", "completed": &today}),
        ];
        let result = burndown(&tasks, "week");
        assert_eq!(result["created"], 0);
        assert_eq!(result["completed"], 2);
        assert_eq!(result["direction"], "shrinking");
    }

    // ── blocked_chain tests ─────────────────────────────────────────

    #[test]
    fn test_blocked_chain_simple() {
        let tasks = vec![
            json!({"id": "t-1", "status": "pending", "blocked_by": ["t-2"]}),
            json!({"id": "t-2", "status": "pending", "blocked_by": []}),
        ];
        let mut visited = HashSet::new();
        let chain = blocked_chain("t-1", &tasks, 0, &mut visited);
        assert_eq!(chain.len(), 2);
        assert_eq!(chain[0].0, 0); // depth 0: t-1
        assert_eq!(chain[1].0, 1); // depth 1: t-2
    }

    #[test]
    fn test_blocked_chain_cycle_detection() {
        let tasks = vec![
            json!({"id": "t-1", "status": "pending", "blocked_by": ["t-2"]}),
            json!({"id": "t-2", "status": "pending", "blocked_by": ["t-1"]}),
        ];
        let mut visited = HashSet::new();
        let chain = blocked_chain("t-1", &tasks, 0, &mut visited);
        // Should not infinite loop — cycle detected
        assert_eq!(chain.len(), 2); // t-1 at depth 0, t-2 at depth 1, then stops
    }

    #[test]
    fn test_blocked_chain_skips_done() {
        let tasks = vec![
            json!({"id": "t-1", "status": "pending", "blocked_by": ["t-2"]}),
            json!({"id": "t-2", "status": "completed", "blocked_by": []}),
        ];
        let mut visited = HashSet::new();
        let chain = blocked_chain("t-1", &tasks, 0, &mut visited);
        assert_eq!(chain.len(), 1); // only t-1, t-2 is done so not traversed
    }

    // ── stale_tasks tests ───────────────────────────────────────────

    #[test]
    fn test_stale_tasks_finds_old() {
        let tasks = vec![
            json!({"id": "t-1", "type": "task", "status": "pending", "created": "2020-01-01", "blocked_by": []}),
            json!({"id": "t-2", "type": "task", "status": "pending", "created": "2099-01-01", "blocked_by": []}),
            json!({"id": "t-3", "type": "task", "status": "completed", "created": "2020-01-01", "blocked_by": []}),
        ];
        let stale = stale_tasks(&tasks, &tasks, 14);
        assert_eq!(stale.len(), 1);
        assert_eq!(stale[0]["id"], "t-1");
    }

    #[test]
    fn test_stale_tasks_excludes_phases() {
        let tasks = vec![
            json!({"id": "ph-1", "type": "phase", "status": "pending", "created": "2020-01-01", "blocked_by": []}),
        ];
        let stale = stale_tasks(&tasks, &tasks, 14);
        assert_eq!(stale.len(), 0);
    }

    #[test]
    fn test_stale_tasks_sorted_oldest_first() {
        let tasks = vec![
            json!({"id": "t-1", "type": "task", "status": "pending", "created": "2021-06-01", "blocked_by": []}),
            json!({"id": "t-2", "type": "task", "status": "pending", "created": "2020-01-01", "blocked_by": []}),
        ];
        let stale = stale_tasks(&tasks, &tasks, 14);
        assert_eq!(stale.len(), 2);
        assert_eq!(stale[0]["id"], "t-2"); // oldest first
        assert_eq!(stale[1]["id"], "t-1");
    }

    // ── write_atomic ─────────────────────────────────────────────────

    #[test]
    fn test_write_atomic_creates_file() {
        let dir = tempfile::TempDir::new().unwrap();
        let path = dir.path().join("tasks.json");
        write_atomic(&path, "{\"tasks\":[]}").unwrap();
        assert!(path.exists());
        assert_eq!(std::fs::read_to_string(&path).unwrap(), "{\"tasks\":[]}");
    }

    #[test]
    fn test_write_atomic_no_tmp_remains() {
        let dir = tempfile::TempDir::new().unwrap();
        let path = dir.path().join("tasks.json");
        write_atomic(&path, "{}").unwrap();
        let tmp_files: Vec<_> = std::fs::read_dir(dir.path())
            .unwrap()
            .filter_map(|e| e.ok())
            .filter(|e| e.file_name().to_string_lossy().ends_with(".tmp"))
            .collect();
        assert!(tmp_files.is_empty(), "tmp files left behind: {:?}", tmp_files);
    }

    #[test]
    fn test_write_atomic_replaces_existing() {
        let dir = tempfile::TempDir::new().unwrap();
        let path = dir.path().join("tasks.json");
        std::fs::write(&path, "old content").unwrap();
        write_atomic(&path, "new content").unwrap();
        assert_eq!(std::fs::read_to_string(&path).unwrap(), "new content");
    }

    #[test]
    fn test_save_tasks_uses_atomic_write() {
        let dir = tempfile::TempDir::new().unwrap();
        let path = dir.path().join("tasks.json");
        let val = serde_json::json!({"version": "1", "tasks": []});
        save_tasks(&path, &val).unwrap();
        let on_disk: serde_json::Value =
            serde_json::from_str(&std::fs::read_to_string(&path).unwrap()).unwrap();
        assert_eq!(on_disk["tasks"], serde_json::json!([]));
        let tmp_files: Vec<_> = std::fs::read_dir(dir.path())
            .unwrap()
            .filter_map(|e| e.ok())
            .filter(|e| e.file_name().to_string_lossy().ends_with(".tmp"))
            .collect();
        assert!(tmp_files.is_empty(), "save_tasks left tmp files: {:?}", tmp_files);
    }

    // ── t-2166: tasks.json write locking (concurrent read-modify-write) ──

    #[test]
    fn lock_tasks_serializes_concurrent_appends() {
        use std::sync::Arc;
        use std::time::Duration;

        let dir = tempfile::TempDir::new().unwrap();
        let path = Arc::new(dir.path().join("tasks.json"));
        save_tasks(&path, &serde_json::json!({"tasks": []})).unwrap();

        const N: usize = 16;
        let mut handles = Vec::new();
        for i in 0..N {
            let path = Arc::clone(&path);
            handles.push(std::thread::spawn(move || {
                // Full read-modify-write under the tasks lock. The window is
                // deliberately widened (sleep between load and save) so that,
                // absent real serialization, concurrent writers would read the
                // same snapshot and clobber each other on save.
                let _lock = lock_tasks(&path).expect("acquire tasks lock");
                let mut val = load_raw(&path).unwrap();
                let id = next_id(val["tasks"].as_array().unwrap());
                std::thread::sleep(Duration::from_millis(2));
                val["tasks"].as_array_mut().unwrap().push(serde_json::json!({
                    "id": id,
                    "subject": format!("concurrent task {i}"),
                    "type": "task",
                }));
                save_tasks(&path, &val).unwrap();
            }));
        }
        for h in handles {
            h.join().unwrap();
        }

        let val = load_raw(&path).unwrap();
        let tasks = val["tasks"].as_array().unwrap();
        assert_eq!(tasks.len(), N, "all {N} concurrent appends must persist (no lost writes)");
        let ids: std::collections::HashSet<&str> =
            tasks.iter().filter_map(|t| t["id"].as_str()).collect();
        assert_eq!(ids.len(), N, "every id must be distinct — next_id computed under lock");
    }

    #[test]
    fn lock_tasks_excludes_second_writer_until_released() {
        use std::sync::atomic::{AtomicBool, Ordering};
        use std::sync::Arc;
        use std::time::Duration;

        let dir = tempfile::TempDir::new().unwrap();
        let path = Arc::new(dir.path().join("tasks.json"));
        save_tasks(&path, &serde_json::json!({"tasks": []})).unwrap();

        let held = lock_tasks(&path).expect("first lock");
        let acquired = Arc::new(AtomicBool::new(false));

        let t = {
            let path = Arc::clone(&path);
            let acquired = Arc::clone(&acquired);
            std::thread::spawn(move || {
                let _lock = lock_tasks(&path).expect("second lock");
                acquired.store(true, Ordering::SeqCst);
            })
        };

        std::thread::sleep(Duration::from_millis(50));
        assert!(
            !acquired.load(Ordering::SeqCst),
            "second writer must block while the first holds the lock"
        );

        drop(held);
        t.join().unwrap();
        assert!(
            acquired.load(Ordering::SeqCst),
            "second writer must acquire the lock once it is released"
        );
    }

    // ── t-1672: spawn / agent_config / agent_result / spawn_strategy ─────

    #[test]
    fn test_set_field_spawn_subagent() {
        let mut task = json!({"id": "t-1"});
        set_field(&mut task, "spawn", "subagent", false).unwrap();
        assert_eq!(task["spawn"], json!("subagent"));
    }

    #[test]
    fn test_set_field_spawn_null() {
        let mut task = json!({"id": "t-1", "spawn": "subagent"});
        set_field(&mut task, "spawn", "null", false).unwrap();
        assert!(task["spawn"].is_null());
    }

    #[test]
    fn test_set_field_spawn_strategy() {
        let mut task = json!({"id": "t-1"});
        set_field(&mut task, "spawn_strategy", "parallel", false).unwrap();
        assert_eq!(task["spawn_strategy"], json!("parallel"));
    }

    #[test]
    fn test_set_field_agent_config_json_object() {
        let mut task = json!({"id": "t-1"});
        set_field(&mut task, "agent_config", r#"{"type":"debrief-analyst","model":"sonnet"}"#, false).unwrap();
        assert_eq!(task["agent_config"]["type"], json!("debrief-analyst"));
        assert_eq!(task["agent_config"]["model"], json!("sonnet"));
    }

    #[test]
    fn test_set_field_agent_config_null() {
        let mut task = json!({"id": "t-1", "agent_config": {"type": "scout"}});
        set_field(&mut task, "agent_config", "null", false).unwrap();
        assert!(task["agent_config"].is_null());
    }

    #[test]
    fn test_set_field_agent_result_json_object() {
        let mut task = json!({"id": "t-1"});
        set_field(&mut task, "agent_result", r#"{"status":"done","summary":"shipped"}"#, false).unwrap();
        assert_eq!(task["agent_result"]["status"], json!("done"));
    }

    #[test]
    fn test_set_field_spawn_accepted_not_unknown() {
        let mut task = json!({"id": "t-1"});
        assert!(set_field(&mut task, "spawn", "subagent", false).is_ok());
    }

    // ── TaskFilter struct API (t-1529) ───────────────────────────────────────

    #[test]
    fn task_filter_default_types() {
        let f = TaskFilter::default();
        assert_eq!(f.types, vec!["task", "subtask"]);
        assert!(f.tag.is_none());
        assert!(f.status.is_none());
    }

    #[test]
    fn task_filter_by_tag() {
        let tasks = sample_tasks();
        let f = TaskFilter { tag: Some("scheduler"), types: vec!["task", "subtask"], ..Default::default() };
        let result = filter_tasks_by(&tasks, &tasks, &f);
        assert_eq!(result.len(), 2);
    }

    // ── t-2311: key:value tag matching (backlog-v3 schema, D8) ──────────────

    #[test]
    fn tag_matches_exact_key_value() {
        let tags = vec!["layer:backend", "urgent"];
        assert!(tag_matches(&tags, "layer:backend"));
        assert!(!tag_matches(&tags, "layer:frontend"));
    }

    #[test]
    fn tag_matches_key_only_matches_any_value() {
        let tags = vec!["layer:backend"];
        assert!(tag_matches(&tags, "layer"));
    }

    #[test]
    fn tag_matches_key_only_still_matches_bare_tag_backward_compat() {
        // Pre-existing bare tag "backend" (no colon) must keep matching
        // `--tag backend` exactly as before this feature.
        let tags = vec!["backend"];
        assert!(tag_matches(&tags, "backend"));
    }

    #[test]
    fn tag_matches_key_only_matches_both_bare_and_keyed_forms() {
        // --tag backend finds a task tagged bare "backend" AND a task
        // tagged "backend:api" — the D8 disambiguation decision.
        assert!(tag_matches(&["backend"], "backend"));
        assert!(tag_matches(&["backend:api"], "backend"));
        assert!(!tag_matches(&["backend-legacy"], "backend")); // no substring false-positive
    }

    #[test]
    fn tag_matches_colon_value_boundary_splits_on_first_colon_only() {
        // A tag value containing multiple colons (e.g. a URL) must not
        // break key-only matching — split on the FIRST ':' only.
        let tags = vec!["url:https://example.com"];
        assert!(tag_matches(&tags, "url"));
        assert!(tag_matches(&tags, "url:https://example.com"));
        assert!(!tag_matches(&tags, "https"));
    }

    #[test]
    fn tag_matches_mixed_and_query_layer_and_urgent() {
        // Mirrors cmd_query's multi-tag AND composition: each comma-split
        // token is matched independently via tag_matches, then AND'd.
        let task_tags = vec!["layer:backend", "urgent"];
        let query = ["layer:backend", "urgent"];
        assert!(query.iter().all(|q| tag_matches(&task_tags, q)));

        let query_miss = ["layer:backend", "dx"];
        assert!(!query_miss.iter().all(|q| tag_matches(&task_tags, q)));
    }

    // ── t-2326: unify cmd_tags --filter/--any with tag_matches() ────────────

    #[test]
    fn tags_query_match_and_requires_key_value_exact() {
        let tags = vec!["layer:backend", "urgent"];
        assert!(tags_query_match(&tags, &["layer:backend", "urgent"], true));
        assert!(!tags_query_match(&tags, &["layer:frontend", "urgent"], true));
    }

    #[test]
    fn tags_query_match_any_matches_key_only_bare_or_any_value() {
        let tags = vec!["layer:backend"];
        // key-only query matches any value for that key, OR'd across the list.
        assert!(tags_query_match(&tags, &["layer", "dx"], false));
        assert!(!tags_query_match(&tags, &["dx", "urgent"], false));
    }

    #[test]
    fn task_filter_by_tag_key_value_exact() {
        let tasks = vec![
            json!({"id": "t-a", "type": "task", "status": "pending", "tags": ["layer:backend"], "blocked_by": []}),
            json!({"id": "t-b", "type": "task", "status": "pending", "tags": ["layer:frontend"], "blocked_by": []}),
        ];
        let f = TaskFilter { tag: Some("layer:backend"), types: vec!["task", "subtask"], ..Default::default() };
        let result = filter_tasks_by(&tasks, &tasks, &f);
        assert_eq!(result.len(), 1);
        assert_eq!(result[0]["id"], "t-a");
    }

    #[test]
    fn task_filter_by_tag_key_only_any_value() {
        let tasks = vec![
            json!({"id": "t-a", "type": "task", "status": "pending", "tags": ["layer:backend"], "blocked_by": []}),
            json!({"id": "t-b", "type": "task", "status": "pending", "tags": ["layer:frontend"], "blocked_by": []}),
            json!({"id": "t-c", "type": "task", "status": "pending", "tags": ["other"], "blocked_by": []}),
        ];
        let f = TaskFilter { tag: Some("layer"), types: vec!["task", "subtask"], ..Default::default() };
        let result = filter_tasks_by(&tasks, &tasks, &f);
        assert_eq!(result.len(), 2);
    }

    #[test]
    fn task_filter_by_status() {
        let tasks = sample_tasks();
        let f = TaskFilter { status: Some("in_progress"), types: vec!["task", "subtask"], ..Default::default() };
        let result = filter_tasks_by(&tasks, &tasks, &f);
        assert_eq!(result.len(), 1);
        assert_eq!(result[0]["id"], "t-002");
    }

    #[test]
    fn task_filter_by_initiative() {
        let tasks = vec![
            json!({"id": "ep-cc", "type": "epic", "subject": "cc-alignment", "parent": null}),
            json!({"id": "ep-ruflo", "type": "epic", "subject": "ruflo", "parent": null}),
            json!({"id": "t-a", "type": "task", "status": "pending", "tags": [], "blocked_by": [], "parent": "ep-cc"}),
            json!({"id": "t-b", "type": "task", "status": "pending", "tags": [], "blocked_by": [], "parent": "ep-ruflo"}),
        ];
        let f = TaskFilter { epic: Some("cc-alignment"), types: vec!["task"], ..Default::default() };
        let result = filter_tasks_by(&tasks, &tasks, &f);
        assert_eq!(result.len(), 1);
        assert_eq!(result[0]["id"], "t-a");
    }

    #[test]
    fn task_filter_wrapper_parity() {
        let tasks = sample_tasks();
        let old = filter_tasks(&tasks, &tasks, Some("scheduler"), Some("pending"), None, None, None, &["task", "subtask"], None, None);
        let new = filter_tasks_by(&tasks, &tasks, &TaskFilter {
            tag: Some("scheduler"),
            status: Some("pending"),
            types: vec!["task", "subtask"],
            ..Default::default()
        });
        let old_ids: Vec<_> = old.iter().map(|t| t["id"].as_str().unwrap()).collect();
        let new_ids: Vec<_> = new.iter().map(|t| t["id"].as_str().unwrap()).collect();
        assert_eq!(old_ids, new_ids);
    }

    // ── t-1614: migrate_initiative_to_epic ───────────────────────────────────

    #[test]
    fn migrate_renames_initiative_key_to_epic() {
        let task = json!({"id": "in-001", "level": "initiative", "initiative": "backlog-git-alignment"});
        let result = migrate_initiative_to_epic(task);
        assert_eq!(result["epic"], "backlog-git-alignment");
        assert!(result.get("initiative").is_none(), "old key must be gone");
        assert_eq!(result["level"], "initiative", "level value must not change");
    }

    #[test]
    fn migrate_noop_when_no_initiative_key() {
        let task = json!({"id": "t-001", "type": "task", "epic": "existing"});
        let result = migrate_initiative_to_epic(task);
        assert_eq!(result["epic"], "existing");
        assert!(result.get("initiative").is_none());
    }

    #[test]
    fn migrate_preserves_type_initiative_value() {
        let task = json!({"id": "in-002", "type": "initiative", "initiative": "some-epic"});
        let result = migrate_initiative_to_epic(task);
        assert_eq!(result["epic"], "some-epic", "initiative key renamed to epic");
        assert_eq!(result["type"], "initiative", "type value must not change");
        assert!(result.get("initiative").is_none());
    }

    // ── t-1982: execution enum validation ───────────────────────────────────

    #[test]
    fn test_validate_execution_accepts_code() {
        assert!(validate_execution("code").is_ok());
    }

    #[test]
    fn test_validate_execution_accepts_autonomous() {
        assert!(validate_execution("autonomous").is_ok());
    }

    #[test]
    fn test_validate_execution_accepts_null_and_empty() {
        assert!(validate_execution("null").is_ok());
        assert!(validate_execution("").is_ok());
    }

    #[test]
    fn test_validate_execution_rejects_bogus() {
        let err = validate_execution("bogus").unwrap_err();
        assert!(err.contains("code"), "error must list allowed values: {err}");
        assert!(err.contains("autonomous"), "error must list allowed values: {err}");
    }

    #[test]
    fn test_set_field_execution_accepts_autonomous() {
        let mut task = json!({"id": "t-1", "execution": "code"});
        set_field(&mut task, "execution", "autonomous", false).unwrap();
        assert_eq!(task["execution"], "autonomous");
    }

    #[test]
    fn test_set_field_execution_accepts_code() {
        let mut task = json!({"id": "t-1", "execution": null});
        set_field(&mut task, "execution", "code", false).unwrap();
        assert_eq!(task["execution"], "code");
    }

    #[test]
    fn test_set_field_execution_accepts_null() {
        let mut task = json!({"id": "t-1", "execution": "code"});
        set_field(&mut task, "execution", "null", false).unwrap();
        assert!(task["execution"].is_null());
    }

    #[test]
    fn test_set_field_execution_rejects_bogus() {
        let mut task = json!({"id": "t-1", "execution": "code"});
        let err = set_field(&mut task, "execution", "bogus", false).unwrap_err();
        assert!(err.contains("code"), "error must list allowed values: {err}");
        assert!(err.contains("autonomous"), "error must list allowed values: {err}");
        // Task must be unchanged on error
        assert_eq!(task["execution"], "code");
    }

    #[test]
    fn test_existing_tasks_with_null_execution_pass_validation() {
        // Regression: tasks with execution=null must not be rejected when loaded
        let mut task = json!({"id": "t-existing", "execution": null});
        // set_field with null is fine
        set_field(&mut task, "execution", "null", false).unwrap();
        assert!(task["execution"].is_null());
    }

    // ── t-2283: ac_state forward-only slice ──────────────────────────────

    #[test]
    fn test_set_field_ac_state_none_adds_key() {
        // AC#5: opt-in a legacy task by adding the ac_state key.
        let mut task = json!({"id": "t-1", "subject": "s"});
        assert!(task.get("ac_state").is_none());
        set_field(&mut task, "ac_state", "none", false).unwrap();
        assert_eq!(task["ac_state"], "none");
    }

    #[test]
    fn test_set_field_ac_state_valid_values() {
        // "approved" removed 2026-08-13 (t-2815, ADR-079 §1): the generic set
        // path now rejects it — the sanctioned transition is the approve verb.
        for v in ["none", "proposed"] {
            let mut task = json!({"id": "t-1"});
            set_field(&mut task, "ac_state", v, false).unwrap();
            assert_eq!(task["ac_state"], v);
        }
    }

    // ── t-2812/t-2815 (ADR-079 §1): approved is verb-only; AC edits reset ──

    #[test]
    fn test_set_field_ac_state_approved_rejected_with_verb_pointer() {
        let mut task = json!({"id": "t-1", "ac_state": "proposed"});
        let err = set_field(&mut task, "ac_state", "approved", false).unwrap_err();
        assert!(
            err.contains("ac") && err.contains("approve"),
            "rejection must point at the sanctioned verb: {err}"
        );
        assert_eq!(task["ac_state"], "proposed", "task unchanged on rejection");
    }

    #[test]
    fn test_set_field_ac_edit_replace_resets_approved_to_proposed() {
        // ADR-079 §1 content-binding: an approval of criteria that were then
        // edited is an approval of nothing (ADR-076-D2 moving-target class).
        let mut task = json!({
            "id":"t-1","ac_state":"approved","acceptance_criteria":["old contract"]
        });
        set_field(&mut task, "acceptance_criteria", r#"["new contract"]"#, false).unwrap();
        assert_eq!(task["acceptance_criteria"], json!(["new contract"]));
        assert_eq!(task["ac_state"], "proposed", "full-array replace must reset approval");
    }

    #[test]
    fn test_set_field_ac_edit_append_resets_approved_to_proposed() {
        let mut task = json!({
            "id":"t-1","ac_state":"approved","acceptance_criteria":["kept"]
        });
        set_field(&mut task, "acceptance_criteria", "+also this", false).unwrap();
        assert_eq!(task["acceptance_criteria"], json!(["kept", "also this"]));
        assert_eq!(task["ac_state"], "proposed", "+item append must reset approval");
    }

    #[test]
    fn test_set_field_ac_edit_remove_resets_approved_to_proposed() {
        let mut task = json!({
            "id":"t-1","ac_state":"approved","acceptance_criteria":["kept","dropped"]
        });
        set_field(&mut task, "acceptance_criteria", "-dropped", false).unwrap();
        assert_eq!(task["acceptance_criteria"], json!(["kept"]));
        assert_eq!(task["ac_state"], "proposed", "-item remove must reset approval");
    }

    #[test]
    fn test_set_field_ac_edit_no_reset_when_not_approved() {
        for state in ["none", "proposed"] {
            let mut task = json!({
                "id":"t-1","ac_state":state,"acceptance_criteria":[]
            });
            set_field(&mut task, "acceptance_criteria", r#"["x"]"#, false).unwrap();
            assert_eq!(task["ac_state"], state, "non-approved state must not change");
        }
        // Legacy key-absent task must not gain the key from an AC edit.
        let mut legacy = json!({"id":"t-1","acceptance_criteria":[]});
        set_field(&mut legacy, "acceptance_criteria", r#"["x"]"#, false).unwrap();
        assert!(legacy.get("ac_state").is_none(), "AC edit must not opt a legacy task in");
    }

    #[test]
    fn test_set_fields_atomic_rejects_approved_and_rolls_back() {
        // The MCP backlog_batch path: set_fields_atomic must surface the
        // verb-only rejection and leave the task untouched (all-or-nothing).
        let mut task = json!({"id":"t-1","ac_state":"proposed","priority":"P2"});
        let before = task.clone();
        let errs = set_fields_atomic(
            &mut task,
            &[
                ("priority".to_string(), "P1".to_string()),
                ("ac_state".to_string(), "approved".to_string()),
            ],
            false,
        )
        .unwrap_err();
        assert!(
            errs.iter().any(|e| e.contains("approve")),
            "batch error must carry the verb pointer: {errs:?}"
        );
        assert_eq!(task, before, "atomic batch must roll back the priority write too");
    }

    #[test]
    fn test_set_field_ac_edit_failed_write_does_not_reset() {
        // Boundary: a rejected write is not an edit — approval must survive it.
        let mut task = json!({
            "id":"t-1","ac_state":"approved","acceptance_criteria":["kept"]
        });
        assert!(set_field(&mut task, "acceptance_criteria", "not json", false).is_err());
        assert_eq!(task["ac_state"], "approved", "failed write must not reset approval");
        assert_eq!(task["acceptance_criteria"], json!(["kept"]));
    }

    #[test]
    fn test_set_field_ac_state_rejects_invalid() {
        let mut task = json!({"id": "t-1"});
        let err = set_field(&mut task, "ac_state", "bogus", false).unwrap_err();
        assert!(err.contains("none"), "err must list valid values: {err}");
        assert!(task.get("ac_state").is_none(), "task unchanged on validation error");
    }

    #[test]
    fn test_set_field_ac_state_clears_with_null() {
        let mut task = json!({"id": "t-1", "ac_state": "proposed"});
        set_field(&mut task, "ac_state", "null", false).unwrap();
        assert!(task["ac_state"].is_null());
    }

    #[test]
    fn test_set_field_unrelated_preserves_ac_state() {
        // AC#2 (core): both write paths share set_field over a raw Value, so an
        // unrelated field update must not clobber a previously-written ac_state.
        let mut task = json!({"id": "t-1", "ac_state": "proposed", "priority": "P2"});
        set_field(&mut task, "priority", "P1", false).unwrap();
        assert_eq!(task["ac_state"], "proposed", "unrelated set clobbered ac_state");
    }

    #[test]
    fn test_load_raw_upgrades_version_1_to_3() {
        use std::io::Write;
        let mut f = tempfile::NamedTempFile::new().unwrap();
        write!(f, r#"{{"version":1,"project":"p","tasks":[]}}"#).unwrap();
        let val = load_raw(f.path()).unwrap();
        assert_eq!(val["version"], 3, "v1 must upgrade to the canonical floor (3)");
    }

    #[test]
    fn test_load_raw_stamps_version_when_absent() {
        use std::io::Write;
        let mut f = tempfile::NamedTempFile::new().unwrap();
        write!(f, r#"{{"project":"p","tasks":[]}}"#).unwrap();
        let val = load_raw(f.path()).unwrap();
        assert_eq!(val["version"], 3, "absent version must normalize to the canonical floor (3)");
    }

    #[test]
    fn test_load_raw_upgrades_version_2_to_3() {
        // t-2308: the floor moved from 2 (t-2283's ac_state slice) to 3
        // (t-2284's level/epic-collapse awareness) — files already at 2 are
        // no longer canonical and must upgrade on load.
        use std::io::Write;
        let mut f = tempfile::NamedTempFile::new().unwrap();
        write!(f, r#"{{"version":2,"project":"p","tasks":[]}}"#).unwrap();
        let val = load_raw(f.path()).unwrap();
        assert_eq!(val["version"], 3);
    }

    #[test]
    fn test_load_raw_keeps_version_3() {
        use std::io::Write;
        let mut f = tempfile::NamedTempFile::new().unwrap();
        write!(f, r#"{{"version":3,"project":"p","tasks":[]}}"#).unwrap();
        let val = load_raw(f.path()).unwrap();
        assert_eq!(val["version"], 3);
    }

    #[test]
    fn test_save_tasks_stamps_version_3() {
        let f = tempfile::NamedTempFile::new().unwrap();
        let val = json!({"project": "p", "tasks": []});
        save_tasks(f.path(), &val).unwrap();
        let reloaded: Value =
            serde_json::from_str(&std::fs::read_to_string(f.path()).unwrap()).unwrap();
        assert_eq!(reloaded["version"], 3, "save must stamp the canonical floor (3)");
    }

    #[test]
    fn test_load_raw_upgrades_string_version_1_to_numeric_3() {
        // Challenger CRITICAL: the live tasks.json stores version as a STRING
        // ("1"), which a numbers-only check silently never upgraded.
        use std::io::Write;
        let mut f = tempfile::NamedTempFile::new().unwrap();
        write!(f, r#"{{"version":"1","project":"p","tasks":[]}}"#).unwrap();
        let val = load_raw(f.path()).unwrap();
        assert_eq!(val["version"], json!(3), "string \"1\" must upgrade to numeric 3");
        assert!(val["version"].is_number(), "version must normalize to a JSON number");
    }

    #[test]
    fn test_save_tasks_rewrites_string_version_to_numeric_3() {
        let f = tempfile::NamedTempFile::new().unwrap();
        let val = json!({"version": "1", "project": "p", "tasks": []});
        save_tasks(f.path(), &val).unwrap();
        let reloaded: Value =
            serde_json::from_str(&std::fs::read_to_string(f.path()).unwrap()).unwrap();
        assert_eq!(reloaded["version"], json!(3));
        assert!(reloaded["version"].is_number(), "string version must be coerced to a number");
    }

    #[test]
    fn test_save_tasks_preserves_canonical_version() {
        // Version == CANONICAL_VERSION must round-trip unchanged. Distinct
        // from unknown-newer (version > CANONICAL_VERSION), which now hits
        // the forward-only guard instead — see
        // test_save_tasks_refuses_unknown_newer_version below.
        let f = tempfile::NamedTempFile::new().unwrap();
        let val = json!({"version": 3, "project": "p", "tasks": []});
        save_tasks(f.path(), &val).unwrap();
        let reloaded: Value =
            serde_json::from_str(&std::fs::read_to_string(f.path()).unwrap()).unwrap();
        assert_eq!(reloaded["version"], 3, "must not touch a value already at the canonical floor");
    }

    #[test]
    fn test_normalize_version_leaves_unknown_newer_untouched() {
        // t-2308 forward-only guard: a version this binary doesn't
        // understand (here, a hypothetical future 99) must not be
        // coerced/downgraded.
        let mut val = json!({"version": 99, "project": "p", "tasks": []});
        normalize_version(&mut val);
        assert_eq!(val["version"], json!(99), "unknown-newer version must be left untouched");
    }

    #[test]
    fn test_is_unknown_newer_version() {
        assert!(!is_unknown_newer_version(&json!({"version": 1})));
        assert!(!is_unknown_newer_version(&json!({"version": 3})));
        assert!(is_unknown_newer_version(&json!({"version": 99})));
        assert!(!is_unknown_newer_version(&json!({})), "absent version is not 'newer', just unversioned");
    }

    #[test]
    fn test_save_tasks_refuses_unknown_newer_version() {
        // t-2308 forward-only guard: refuse to write (read-only + warning)
        // rather than blindly serializing a schema shape this binary
        // predates. NOTE: this only protects binaries built from this
        // change onward — an already-compiled binary hardcoding `>= 2` has
        // no way to learn about this guard after the fact.
        let f = tempfile::NamedTempFile::new().unwrap();
        let before = std::fs::read_to_string(f.path()).unwrap_or_default();
        let val = json!({"version": 99, "project": "p", "tasks": []});
        let result = save_tasks(f.path(), &val);
        assert!(result.is_err(), "must refuse to save an unknown-newer version");
        let after = std::fs::read_to_string(f.path()).unwrap_or_default();
        assert_eq!(before, after, "refused save must not modify the file on disk");
    }

    #[test]
    fn test_perform_rollup_preserves_ac_state() {
        // Finding #3: perform_rollup writes tasks.json outside the set_field
        // pipeline — prove it does not drop ac_state on untouched tasks.
        use std::io::Write;
        let mut f = tempfile::NamedTempFile::new().unwrap();
        write!(
            f,
            r#"{{"version":2,"project":"p","tasks":[
                {{"id":"ms-1","subject":"m","status":"pending","type":"milestone","tags":[],"blocked_by":[],"ac_state":"approved"}},
                {{"id":"t-1","subject":"c","status":"completed","type":"task","parent":"ms-1","tags":[],"blocked_by":[],"ac_state":"proposed"}}
            ]}}"#
        )
        .unwrap();
        let done = perform_rollup(f.path(), false).unwrap();
        assert_eq!(done, vec!["ms-1"], "milestone with all-done children should roll up");
        let reloaded: Value =
            serde_json::from_str(&std::fs::read_to_string(f.path()).unwrap()).unwrap();
        let arr = reloaded["tasks"].as_array().unwrap();
        let ms = arr.iter().find(|t| t["id"] == "ms-1").unwrap();
        let t1 = arr.iter().find(|t| t["id"] == "t-1").unwrap();
        assert_eq!(ms["ac_state"], "approved", "rollup must preserve parent ac_state");
        assert_eq!(t1["ac_state"], "proposed", "rollup must preserve child ac_state");
        assert_eq!(ms["status"], "completed");
    }

    #[test]
    fn test_filter_by_ac_state_matches_present_key_only() {
        // AC#4: only key-present matches; legacy (absent) never appears.
        let tasks = vec![
            json!({"id":"t-1","type":"task","ac_state":"none"}),
            json!({"id":"t-2","type":"task","ac_state":"proposed"}),
            json!({"id":"t-3","type":"task"}),
        ];
        let filter = TaskFilter { ac_state: Some("none"), ..Default::default() };
        let out = filter_tasks_by(&tasks, &tasks, &filter);
        let ids: Vec<&str> = out.iter().filter_map(|t| t["id"].as_str()).collect();
        assert_eq!(ids, vec!["t-1"]);
    }

    #[test]
    fn test_filter_ac_state_excludes_legacy_absent() {
        let tasks = vec![json!({"id":"t-3","type":"task"})];
        let filter = TaskFilter { ac_state: Some("none"), ..Default::default() };
        let out = filter_tasks_by(&tasks, &tasks, &filter);
        assert!(out.is_empty(), "absent-key task must never match --ac-state");
    }

    #[test]
    fn test_ac_propose_candidates_excludes_research_and_review() {
        // AC#7: drain queue = ac_state==none MINUS work_type in {research, review}.
        let tasks = vec![
            json!({"id":"t-1","type":"task","ac_state":"none","work_type":"implement"}),
            json!({"id":"t-2","type":"task","ac_state":"none","work_type":"research"}),
            json!({"id":"t-3","type":"task","ac_state":"none","work_type":"review"}),
            json!({"id":"t-4","type":"task","ac_state":"proposed","work_type":"implement"}),
            json!({"id":"t-5","type":"task","work_type":"implement"}),
        ];
        let out = ac_propose_candidates(&tasks);
        let ids: Vec<&str> = out.iter().filter_map(|t| t["id"].as_str()).collect();
        assert_eq!(ids, vec!["t-1"], "only ac_state==none, non-research/review");
    }

    #[test]
    fn test_apply_ac_proposals_mutates_only_ac_state_and_proposed_field() {
        // AC#3 (scoped mutation) + AC#4 (inert) + AC#5 (legacy untouched): the loop's
        // write touches ONLY ac_state + proposed_acceptance_criteria, and never a
        // non-candidate (legacy key-absent / already-proposed / research).
        let mut tasks = vec![
            json!({
                "id":"t-1","subject":"add widget","status":"pending","type":"task",
                "priority":"P2","effort":"M","tags":["a","b"],"blocked_by":[],
                "work_type":"implement","kind":"feature","ac_state":"none",
                "description":"do the thing","context":"AC: something","order":3
            }),
            // legacy: NO ac_state key — must stay byte-identical even with a proposal.
            json!({"id":"t-2","subject":"legacy","type":"task","work_type":"implement","tags":[]}),
            // already proposed — not a candidate.
            json!({"id":"t-3","subject":"p","type":"task","ac_state":"proposed","tags":[]}),
            // research candidate excluded by the helper.
            json!({"id":"t-4","subject":"spike","type":"task","ac_state":"none","work_type":"research","tags":[]}),
            // already approved — not a candidate; the human-approved state is terminal.
            json!({"id":"t-5","subject":"live","type":"task","ac_state":"approved","tags":[]}),
        ];
        let before: Vec<Value> = tasks.clone();

        let mut proposals: HashMap<String, Vec<String>> = HashMap::new();
        proposals.insert("t-1".into(), vec!["Widget renders and is tested".into()]);
        proposals.insert("t-2".into(), vec!["ignored: legacy".into()]);
        proposals.insert("t-3".into(), vec!["ignored: already proposed".into()]);
        proposals.insert("t-4".into(), vec!["ignored: research".into()]);
        proposals.insert("t-5".into(), vec!["ignored: already approved".into()]);
        proposals.insert("t-9".into(), vec!["ignored: no such task".into()]);

        let applied = apply_ac_proposals(&mut tasks, &proposals);
        assert_eq!(applied, vec!["t-1"], "only the eligible candidate is applied");

        // t-1: the two intended fields changed to the intended values...
        assert_eq!(tasks[0]["ac_state"], "proposed");
        assert_eq!(
            tasks[0]["proposed_acceptance_criteria"],
            json!(["Widget renders and is tested"])
        );
        // ...and NOTHING else moved: strip the two mutated keys, compare the rest.
        let strip = |v: &Value| {
            let mut o = v.as_object().unwrap().clone();
            o.remove("ac_state");
            o.remove("proposed_acceptance_criteria");
            o
        };
        assert_eq!(
            strip(&tasks[0]),
            strip(&before[0]),
            "no field beyond ac_state + proposed_acceptance_criteria may change"
        );
        // proposed AC did NOT leak into the live gating field (AC#4 inert).
        assert!(
            tasks[0].get("acceptance_criteria").is_none(),
            "proposed AC must not be written to acceptance_criteria"
        );

        // legacy / proposed / research: fully identical to before.
        assert_eq!(tasks[1], before[1], "legacy (key-absent) task untouched");
        assert!(tasks[1].get("ac_state").is_none(), "legacy must not gain ac_state");
        assert!(
            tasks[1].get("proposed_acceptance_criteria").is_none(),
            "legacy must not gain the proposed field"
        );
        assert_eq!(tasks[2], before[2], "already-proposed task untouched");
        assert_eq!(tasks[3], before[3], "research candidate untouched");
        assert_eq!(tasks[4], before[4], "already-approved task untouched");
    }

    #[test]
    fn test_perform_ac_propose_persists_and_dry_run_is_noop() {
        use std::io::Write;
        let body = r#"{"version":2,"project":"p","tasks":[
            {"id":"t-1","subject":"a","status":"pending","type":"task","tags":[],"blocked_by":[],"work_type":"implement","ac_state":"none"},
            {"id":"t-2","subject":"legacy","status":"pending","type":"task","tags":[],"blocked_by":[]}
        ]}"#;

        let mut proposals: HashMap<String, Vec<String>> = HashMap::new();
        proposals.insert("t-1".into(), vec!["done when green".into()]);
        proposals.insert("t-2".into(), vec!["ignored: legacy".into()]);

        // dry_run: reports the applied set but writes nothing.
        let mut f = tempfile::NamedTempFile::new().unwrap();
        write!(f, "{body}").unwrap();
        let applied = perform_ac_propose(f.path(), &proposals, true).unwrap();
        assert_eq!(applied, vec!["t-1"], "dry_run reports what would apply");
        let after_dry: Value =
            serde_json::from_str(&std::fs::read_to_string(f.path()).unwrap()).unwrap();
        assert_eq!(
            after_dry["tasks"][0]["ac_state"], "none",
            "dry_run must not write"
        );

        // real apply: persists ac_state:proposed + the field, legacy untouched.
        let mut f2 = tempfile::NamedTempFile::new().unwrap();
        write!(f2, "{body}").unwrap();
        let applied = perform_ac_propose(f2.path(), &proposals, false).unwrap();
        assert_eq!(applied, vec!["t-1"]);
        let reloaded: Value =
            serde_json::from_str(&std::fs::read_to_string(f2.path()).unwrap()).unwrap();
        let arr = reloaded["tasks"].as_array().unwrap();
        let t1 = arr.iter().find(|t| t["id"] == "t-1").unwrap();
        let t2 = arr.iter().find(|t| t["id"] == "t-2").unwrap();
        assert_eq!(t1["ac_state"], "proposed");
        assert_eq!(t1["proposed_acceptance_criteria"], json!(["done when green"]));
        assert!(t2.get("ac_state").is_none(), "legacy task stays key-less on disk");
    }

    // ── t-2812 (ADR-079 §1): ac approve — promote + flip ─────────────────

    #[test]
    fn test_approve_ac_promotes_proposed_and_flips() {
        let mut task = json!({
            "id":"t-1","subject":"s","type":"task","ac_state":"proposed",
            "proposed_acceptance_criteria":["a is tested","b is wired"]
        });
        let out = approve_ac(&mut task).unwrap();
        assert_eq!(task["ac_state"], "approved");
        assert_eq!(task["acceptance_criteria"], json!(["a is tested","b is wired"]));
        assert!(
            task.get(PROPOSED_AC_FIELD).is_none(),
            "proposed field must be cleared on promote"
        );
        assert_eq!(out.promoted, 2);
        assert!(!out.already_approved);
    }

    #[test]
    fn test_approve_ac_union_when_both_non_empty() {
        // ADR-079 §1 addendum (challenger-confirmed assumption): when both fields
        // are non-empty, promote is a dedup-union — existing order first, so a
        // human-authored contract is never destroyed by a loop proposal.
        let mut task = json!({
            "id":"t-1","ac_state":"proposed",
            "acceptance_criteria":["human authored","shared item"],
            "proposed_acceptance_criteria":["shared item","loop proposed"]
        });
        let out = approve_ac(&mut task).unwrap();
        assert_eq!(
            task["acceptance_criteria"],
            json!(["human authored","shared item","loop proposed"])
        );
        assert_eq!(out.promoted, 1, "only the genuinely new criterion counts");
        assert_eq!(task["ac_state"], "approved");
    }

    #[test]
    fn test_approve_ac_both_empty_errors_task_untouched() {
        // Rejected approve is atomic: the task stays byte-identical.
        let mut task = json!({"id":"t-1","ac_state":"none","acceptance_criteria":[]});
        let before = task.clone();
        let err = approve_ac(&mut task).unwrap_err();
        assert!(err.contains("no acceptance criteria to approve"), "got: {err}");
        assert_eq!(task, before, "failed approve must not mutate the task");
    }

    #[test]
    fn test_approve_ac_idempotent_on_approved() {
        let mut task = json!({
            "id":"t-1","ac_state":"approved","acceptance_criteria":["done when green"]
        });
        let before = task.clone();
        let out = approve_ac(&mut task).unwrap();
        assert!(out.already_approved);
        assert_eq!(out.promoted, 0);
        assert_eq!(task, before, "re-approve is a no-op");
    }

    #[test]
    fn test_approve_ac_key_absent_treated_as_none() {
        // Legacy opt-in — same precedent as set_field's ac_state arm (AC#5, t-2283).
        let mut task = json!({"id":"t-1","acceptance_criteria":["authored by hand"]});
        approve_ac(&mut task).unwrap();
        assert_eq!(task["ac_state"], "approved");
        assert_eq!(task["acceptance_criteria"], json!(["authored by hand"]));
    }

    #[test]
    fn test_approve_ac_bare_string_coerced_to_array() {
        // Legacy string-valued acceptance_criteria: whole-string coercion, never
        // comma-split — the normalize_array_fields exclusion for this field stands.
        let mut task = json!({
            "id":"t-1","ac_state":"none",
            "acceptance_criteria":"works, even with commas"
        });
        approve_ac(&mut task).unwrap();
        assert_eq!(task["acceptance_criteria"], json!(["works, even with commas"]));
        assert_eq!(task["ac_state"], "approved");
    }

    // ── t-2842 (ADR-080 §4): wave approve — batch AC valve, cap 10 ───────

    fn wave_q(selector: &str) -> Value {
        json!({"id": "wave-9", "name": "w", "selector": selector, "status": "queued"})
    }

    fn ac_task(id: &str, ac_state: &str, tag: &str) -> Value {
        json!({"id": id, "subject": format!("s-{id}"), "status": "pending",
               "tags": [tag], "ac_state": ac_state,
               "proposed_acceptance_criteria": if ac_state == "proposed" {
                   json!(["criterion for", id])
               } else { Value::Null }})
    }

    #[test]
    fn plan_wave_approve_partitions_proposed_and_none() {
        let tasks = vec![
            ac_task("t-1", "proposed", "w1"),
            ac_task("t-2", "none", "w1"),
            ac_task("t-3", "approved", "w1"),
        ];
        let plan = plan_wave_approve(&wave_q("tag:w1"), &tasks).unwrap();
        assert_eq!(plan.batches.len(), 1);
        assert_eq!(plan.batches[0].len(), 1, "only proposed tasks are batched");
        assert_eq!(plan.batches[0][0].0, "t-1");
        assert_eq!(plan.none_ids, vec!["t-2"],
            "none tasks are listed, not silently absorbed");
        // t-3 (already approved) is neither batched nor listed — nothing to do.
    }

    #[test]
    fn plan_wave_approve_caps_batches_at_ten() {
        let tasks: Vec<Value> = (1..=23)
            .map(|i| ac_task(&format!("t-{i}"), "proposed", "w1"))
            .collect();
        let plan = plan_wave_approve(&wave_q("tag:w1"), &tasks).unwrap();
        let sizes: Vec<usize> = plan.batches.iter().map(|b| b.len()).collect();
        assert_eq!(sizes, vec![10, 10, 3],
            "batches capped at 10 — the rubber-stamp guard (challenge finding 8)");
    }

    #[test]
    fn plan_wave_approve_carries_proposed_criteria_for_display() {
        let tasks = vec![ac_task("t-1", "proposed", "w1")];
        let plan = plan_wave_approve(&wave_q("tag:w1"), &tasks).unwrap();
        assert_eq!(plan.batches[0][0].1, vec!["criterion for", "t-1"]);
    }

    #[test]
    fn plan_wave_approve_routes_through_resolve_wave_selector_only() {
        // parent: form must work too — same resolver as every other consumer,
        // zero direct selector parsing in this new code (ADR-080 §1 discipline
        // extends to §4's new consumer).
        let tasks = vec![
            json!({"id":"ms-1","status":"pending","tags":[],"ac_state":"none"}),
            {
                let mut t = ac_task("t-1", "proposed", "unused");
                t["parent"] = Value::String("ms-1".into());
                t
            },
        ];
        let plan = plan_wave_approve(&wave_q("parent:ms-1"), &tasks).unwrap();
        assert_eq!(plan.batches.len(), 1);
        assert_eq!(plan.batches[0][0].0, "t-1");
    }

    #[test]
    fn plan_wave_approve_unknown_selector_rejected_loud() {
        let err = plan_wave_approve(&wave_q("bogus:x"), &[]).unwrap_err();
        assert!(err.contains("selector form not supported"));
    }

    #[test]
    fn plan_wave_approve_empty_match_is_ok_empty_plan() {
        let plan = plan_wave_approve(&wave_q("tag:nothing"), &[]).unwrap();
        assert!(plan.batches.is_empty());
        assert!(plan.none_ids.is_empty());
    }

    #[test]
    fn test_approve_ac_from_none_with_authored_ac() {
        // §1: a human may author + approve directly — proposed never involved.
        let mut task = json!({
            "id":"t-1","ac_state":"none","acceptance_criteria":["tests green"]
        });
        let out = approve_ac(&mut task).unwrap();
        assert_eq!(out.promoted, 0);
        assert_eq!(task["ac_state"], "approved");
    }

    #[test]
    fn test_approve_ac_reapprove_merges_lingering_proposed() {
        // Challenger observation (t-2812 gate): "idempotent on approved" is a
        // STATE guarantee, not a content no-op. approved + non-empty proposed is
        // unreachable via sanctioned paths (ac-propose only targets ac_state:none;
        // set_field has no proposed_acceptance_criteria arm), but if the state
        // exists on disk, re-approve deliberately merges the lingering items
        // rather than silently dropping them — pinned here so t-2813's grading
        // semantics can rely on it.
        let mut task = json!({
            "id":"t-1","ac_state":"approved",
            "acceptance_criteria":["live"],
            "proposed_acceptance_criteria":["lingering"]
        });
        let out = approve_ac(&mut task).unwrap();
        assert!(out.already_approved);
        assert_eq!(out.promoted, 1);
        assert_eq!(task["acceptance_criteria"], json!(["live","lingering"]));
        assert!(task.get(PROPOSED_AC_FIELD).is_none());
    }

    #[test]
    fn test_approve_ac_empty_string_is_empty() {
        // Boundary: an empty-string acceptance_criteria counts as no criteria.
        let mut task = json!({"id":"t-1","ac_state":"none","acceptance_criteria":""});
        assert!(approve_ac(&mut task).is_err());
    }

    #[test]
    fn test_approve_ac_non_string_element_errors() {
        // Boundary: silently dropping non-string criteria would approve a
        // different contract than the one on disk — fail loud instead.
        let mut task = json!({
            "id":"t-1","ac_state":"proposed",
            "proposed_acceptance_criteria":["ok", 42]
        });
        let before = task.clone();
        assert!(approve_ac(&mut task).is_err());
        assert_eq!(task, before, "failed approve must not mutate the task");
    }

    #[test]
    fn test_perform_ac_approve_persists_and_missing_task_errors() {
        use std::io::Write;
        let body = r#"{"version":2,"project":"p","tasks":[
            {"id":"t-1","subject":"a","status":"pending","type":"task","tags":[],"blocked_by":[],"ac_state":"proposed","proposed_acceptance_criteria":["done when green"]}
        ]}"#;
        let mut f = tempfile::NamedTempFile::new().unwrap();
        write!(f, "{body}").unwrap();

        let out = perform_ac_approve(f.path(), "t-1").unwrap();
        assert_eq!(out.promoted, 1);
        let reloaded: Value =
            serde_json::from_str(&std::fs::read_to_string(f.path()).unwrap()).unwrap();
        let t1 = &reloaded["tasks"][0];
        assert_eq!(t1["ac_state"], "approved");
        assert_eq!(t1["acceptance_criteria"], json!(["done when green"]));
        assert!(t1.get("proposed_acceptance_criteria").is_none());

        let err = perform_ac_approve(f.path(), "t-99").unwrap_err();
        assert!(err.contains("t-99"), "missing task must error with the id: {err}");
    }
}
