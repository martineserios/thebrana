//! GitHub Issues sync via `gh api` subprocesses with parallel execution.
//!
//! Zero new dependencies — uses `std::thread::scope` for parallelism
//! and `gh api` for all GitHub API calls (auth handled by `gh`).

use crate::tasks;
use serde_json::Value;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::Mutex;

// ── Types ──────────────────────────────────────────────────────

struct SyncConfig {
    owner: String,
    repo: String,
    keep_streams: Vec<String>,
    label_stream: bool,
    label_priority: bool,
    label_tags: usize,
}

struct SyncPlan {
    creates: Vec<SyncItem>,
    closes: Vec<SyncItem>,
}

struct SyncItem {
    task_id: String,
    subject: String,
    issue_number: Option<u64>,
}

struct SyncResult {
    succeeded: usize,
    failed: usize,
    errors: Vec<String>,
}

// ── Entry point ────────────────────────────────────────────────

pub fn cmd_sync(dry_run: bool, force: bool, parallel: usize) {
    let tasks_file = match find_tasks_file() {
        Some(p) => p,
        None => {
            eprintln!("error: tasks.json not found");
            std::process::exit(1);
        }
    };

    let config = match load_sync_config() {
        Ok(c) => c,
        Err(e) => {
            eprintln!("error: {e}");
            std::process::exit(1);
        }
    };

    if let Err(e) = check_gh_auth() {
        eprintln!("error: {e}");
        std::process::exit(2);
    }

    let data = match tasks::load_raw(&tasks_file) {
        Ok(d) => d,
        Err(e) => {
            eprintln!("error: {e}");
            std::process::exit(1);
        }
    };

    let all_tasks = match data["tasks"].as_array() {
        Some(t) => t,
        None => {
            eprintln!("error: tasks is not an array");
            std::process::exit(1);
        }
    };

    let plan = plan_sync(all_tasks, &config, force);

    eprintln!(
        "[sync] plan: {} to create, {} to close",
        plan.creates.len(),
        plan.closes.len()
    );

    if dry_run {
        eprintln!("[sync] === DRY RUN ===");
        for item in &plan.creates {
            eprintln!("[sync]   + {} — {}", item.task_id, item.subject);
        }
        for item in &plan.closes {
            eprintln!(
                "[sync]   - {} — issue #{}",
                item.task_id,
                item.issue_number.unwrap_or(0)
            );
        }
        return;
    }

    if plan.creates.is_empty() && plan.closes.is_empty() {
        eprintln!("[sync] nothing to do");
        return;
    }

    let parallel = parallel.clamp(1, 20);
    let data = Mutex::new(data);

    // Execute creates
    let create_result = if !plan.creates.is_empty() {
        execute_creates(&plan.creates, &tasks_file, &data, &config, parallel)
    } else {
        SyncResult {
            succeeded: 0,
            failed: 0,
            errors: vec![],
        }
    };

    // Execute closes
    let close_result = if !plan.closes.is_empty() {
        execute_closes(&plan.closes, &config, parallel)
    } else {
        SyncResult {
            succeeded: 0,
            failed: 0,
            errors: vec![],
        }
    };

    eprintln!();
    eprintln!(
        "[sync] done: {} created, {} closed, {} errors",
        create_result.succeeded,
        close_result.succeeded,
        create_result.failed + close_result.failed
    );

    for e in create_result
        .errors
        .iter()
        .chain(close_result.errors.iter())
    {
        eprintln!("[sync]   error: {e}");
    }
}

// ── Planning ───────────────────────────────────────────────────

fn plan_sync(all_tasks: &[Value], config: &SyncConfig, force: bool) -> SyncPlan {
    let mut creates = Vec::new();
    let mut closes = Vec::new();

    for task in all_tasks {
        let id = match task["id"].as_str() {
            Some(id) => id,
            None => continue,
        };
        let subject = task["subject"].as_str().unwrap_or("untitled");
        let status = task["status"].as_str().unwrap_or("pending");
        let stream = task["stream"].as_str().unwrap_or("");
        let has_issue = task["github_issue"].as_u64().is_some()
            || task["github_issue"]
                .as_str()
                .and_then(|s| s.parse::<u64>().ok())
                .is_some();

        // Stream filtering
        if !config.keep_streams.is_empty() && !config.keep_streams.iter().any(|s| s == stream) {
            continue;
        }

        match status {
            "completed" | "cancelled" => {
                // Close issues for completed/cancelled tasks
                if let Some(num) = get_issue_number(task) {
                    closes.push(SyncItem {
                        task_id: id.to_string(),
                        subject: subject.to_string(),
                        issue_number: Some(num),
                    });
                }
            }
            _ => {
                // Create issues for tasks without one
                if !has_issue || force {
                    creates.push(SyncItem {
                        task_id: id.to_string(),
                        subject: subject.to_string(),
                        issue_number: None,
                    });
                }
            }
        }
    }

    SyncPlan { creates, closes }
}

// ── Parallel execution ─────────────────────────────────────────

fn execute_creates(
    items: &[SyncItem],
    tasks_file: &Path,
    data: &Mutex<Value>,
    config: &SyncConfig,
    parallel: usize,
) -> SyncResult {
    let succeeded = AtomicUsize::new(0);
    let failed = AtomicUsize::new(0);
    let errors: Mutex<Vec<String>> = Mutex::new(Vec::new());
    let counter = AtomicUsize::new(0);
    let total = items.len();

    // Read task data for each item before spawning threads
    let task_data: Vec<(&SyncItem, Value)> = {
        let d = data.lock().unwrap();
        items
            .iter()
            .filter_map(|item| {
                d["tasks"]
                    .as_array()?
                    .iter()
                    .find(|t| t["id"].as_str() == Some(&item.task_id))
                    .map(|t| (item, t.clone()))
            })
            .collect()
    };

    let chunk_size = (task_data.len() + parallel - 1) / parallel;
    let chunks: Vec<&[(&SyncItem, Value)]> = task_data.chunks(chunk_size.max(1)).collect();

    std::thread::scope(|s| {
        let succeeded = &succeeded;
        let failed = &failed;
        let errors = &errors;
        let counter = &counter;

        for chunk in chunks {
            s.spawn(move || {
                for (item, task) in chunk {
                    let title = format!("Task: {} — {}", item.task_id, item.subject);
                    let body = build_issue_body(task);
                    let labels = build_labels(task, config);

                    // Ensure labels exist (best-effort)
                    for label in &labels {
                        let color = label_color(label);
                        let _ = ensure_label(&config.owner, &config.repo, label, color);
                    }

                    // Dedup: check if issue already exists
                    if let Some(existing) =
                        gh_issue_exists(&config.owner, &config.repo, &item.task_id)
                    {
                        let n = counter.fetch_add(1, Ordering::Relaxed) + 1;
                        eprint!("\r[{n}/{total}] {} — already exists #{}    ", item.task_id, existing);

                        // Write back the existing issue number
                        let mut d = data.lock().unwrap();
                        set_github_issue(&mut d, &item.task_id, existing);
                        let _ = tasks::save_tasks(tasks_file, &d);
                        succeeded.fetch_add(1, Ordering::Relaxed);
                        continue;
                    }

                    match gh_create_issue(
                        &config.owner,
                        &config.repo,
                        &title,
                        &body,
                        &labels,
                    ) {
                        Ok(number) => {
                            let n = counter.fetch_add(1, Ordering::Relaxed) + 1;
                            eprint!("\r[{n}/{total}] {} → #{}    ", item.task_id, number);

                            // Write back immediately
                            let mut d = data.lock().unwrap();
                            set_github_issue(&mut d, &item.task_id, number);
                            let _ = tasks::save_tasks(tasks_file, &d);
                            succeeded.fetch_add(1, Ordering::Relaxed);
                        }
                        Err(e) => {
                            let n = counter.fetch_add(1, Ordering::Relaxed) + 1;
                            eprint!("\r[{n}/{total}] {} — FAILED    ", item.task_id);
                            failed.fetch_add(1, Ordering::Relaxed);
                            errors
                                .lock()
                                .unwrap()
                                .push(format!("{}: {e}", item.task_id));
                        }
                    }
                }
            });
        }
    });

    SyncResult {
        succeeded: succeeded.load(Ordering::Relaxed),
        failed: failed.load(Ordering::Relaxed),
        errors: errors.into_inner().unwrap(),
    }
}

fn execute_closes(items: &[SyncItem], config: &SyncConfig, parallel: usize) -> SyncResult {
    let succeeded = AtomicUsize::new(0);
    let failed = AtomicUsize::new(0);
    let errors: Mutex<Vec<String>> = Mutex::new(Vec::new());
    let counter = AtomicUsize::new(0);
    let total = items.len();

    let chunk_size = (items.len() + parallel - 1) / parallel;
    let chunks: Vec<&[SyncItem]> = items.chunks(chunk_size.max(1)).collect();

    std::thread::scope(|s| {
        let succeeded = &succeeded;
        let failed = &failed;
        let errors = &errors;
        let counter = &counter;

        for chunk in chunks {
            s.spawn(move || {
                for item in chunk {
                    let number = match item.issue_number {
                        Some(n) => n,
                        None => continue,
                    };

                    match gh_close_issue(&config.owner, &config.repo, number) {
                        Ok(()) => {
                            let n = counter.fetch_add(1, Ordering::Relaxed) + 1;
                            eprint!("\r[{n}/{total}] Closed #{number}    ");
                            succeeded.fetch_add(1, Ordering::Relaxed);
                        }
                        Err(e) => {
                            let n = counter.fetch_add(1, Ordering::Relaxed) + 1;
                            eprint!("\r[{n}/{total}] Close #{number} — FAILED    ");
                            failed.fetch_add(1, Ordering::Relaxed);
                            errors
                                .lock()
                                .unwrap()
                                .push(format!("#{number}: {e}"));
                        }
                    }
                }
            });
        }
    });

    SyncResult {
        succeeded: succeeded.load(Ordering::Relaxed),
        failed: failed.load(Ordering::Relaxed),
        errors: errors.into_inner().unwrap(),
    }
}

// ── GitHub API calls (via `gh api`) ────────────────────────────

fn gh_create_issue(
    owner: &str,
    repo: &str,
    title: &str,
    body: &str,
    labels: &[String],
) -> Result<u64, String> {
    let payload = serde_json::json!({
        "title": title,
        "body": body,
        "labels": labels,
    });

    let output = Command::new("gh")
        .args([
            "api",
            &format!("repos/{owner}/{repo}/issues"),
            "--method",
            "POST",
            "--input",
            "-",
        ])
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .and_then(|mut child| {
            use std::io::Write;
            if let Some(ref mut stdin) = child.stdin {
                stdin.write_all(payload.to_string().as_bytes())?;
            }
            child.wait_with_output()
        })
        .map_err(|e| format!("gh not found: {e}"))?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        // Retry on rate limit (403 with "rate limit")
        if stderr.contains("rate limit") || stderr.contains("secondary rate") {
            std::thread::sleep(std::time::Duration::from_secs(5));
            return gh_create_issue(owner, repo, title, body, labels);
        }
        return Err(format!("API error: {stderr}"));
    }

    let resp: Value =
        serde_json::from_slice(&output.stdout).map_err(|e| format!("JSON parse: {e}"))?;
    resp["number"]
        .as_u64()
        .ok_or_else(|| "no issue number in response".to_string())
}

fn gh_close_issue(owner: &str, repo: &str, number: u64) -> Result<(), String> {
    // Check current state first
    let output = Command::new("gh")
        .args([
            "api",
            &format!("repos/{owner}/{repo}/issues/{number}"),
        ])
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .output()
        .map_err(|e| format!("gh not found: {e}"))?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        if stderr.contains("404") {
            return Ok(()); // Already gone
        }
        return Err(format!("API error: {stderr}"));
    }

    let resp: Value =
        serde_json::from_slice(&output.stdout).map_err(|e| format!("JSON parse: {e}"))?;
    if resp["state"].as_str() == Some("closed") {
        return Ok(()); // Already closed
    }

    // Close it
    let payload = serde_json::json!({"state": "closed"});
    let output = Command::new("gh")
        .args([
            "api",
            &format!("repos/{owner}/{repo}/issues/{number}"),
            "--method",
            "PATCH",
            "--input",
            "-",
        ])
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .and_then(|mut child| {
            use std::io::Write;
            if let Some(ref mut stdin) = child.stdin {
                stdin.write_all(payload.to_string().as_bytes())?;
            }
            child.wait_with_output()
        })
        .map_err(|e| format!("gh: {e}"))?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        return Err(format!("close failed: {stderr}"));
    }

    Ok(())
}

fn gh_issue_exists(owner: &str, repo: &str, task_id: &str) -> Option<u64> {
    let search = format!("Task: {task_id} in:title repo:{owner}/{repo}");
    let output = Command::new("gh")
        .args([
            "api",
            "search/issues",
            "-f",
            &format!("q={search}"),
            "-f",
            "per_page=1",
        ])
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .output()
        .ok()?;

    if !output.status.success() {
        return None;
    }

    let resp: Value = serde_json::from_slice(&output.stdout).ok()?;
    let items = resp["items"].as_array()?;
    if items.is_empty() {
        return None;
    }

    // Verify the title actually matches (search can be fuzzy)
    let title = items[0]["title"].as_str()?;
    if title.starts_with(&format!("Task: {task_id} ")) || title.starts_with(&format!("Task: {task_id}\u{2014}")) {
        items[0]["number"].as_u64()
    } else {
        None
    }
}

fn ensure_label(owner: &str, repo: &str, name: &str, color: &str) -> Result<(), String> {
    let payload = serde_json::json!({
        "name": name,
        "color": color,
    });

    // Try to create; if it already exists (422), that's fine
    let output = Command::new("gh")
        .args([
            "api",
            &format!("repos/{owner}/{repo}/labels"),
            "--method",
            "POST",
            "--input",
            "-",
        ])
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .and_then(|mut child| {
            use std::io::Write;
            if let Some(ref mut stdin) = child.stdin {
                stdin.write_all(payload.to_string().as_bytes())?;
            }
            child.wait_with_output()
        })
        .map_err(|e| format!("gh: {e}"))?;

    // 422 = already exists, that's OK
    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        if !stderr.contains("already_exists") && !stderr.contains("422") {
            return Err(format!("label create failed: {stderr}"));
        }
    }

    Ok(())
}

// ── Helpers ────────────────────────────────────────────────────

fn build_issue_body(task: &Value) -> String {
    let id = task["id"].as_str().unwrap_or("?");
    let stream = task["stream"].as_str().unwrap_or("—");
    let priority = task["priority"].as_str().unwrap_or("—");
    let effort = task["effort"].as_str().unwrap_or("—");
    let strategy = task["strategy"].as_str().unwrap_or("—");
    let execution = task["execution"].as_str().unwrap_or("—");
    let description = task["description"].as_str().unwrap_or("No description.");
    let context = task["context"].as_str();
    let notes = task["notes"].as_str();

    let mut body = format!(
        "**Task:** {id} | **Stream:** {stream} | **Priority:** {priority} | **Effort:** {effort}\n\
         **Strategy:** {strategy} | **Execution:** {execution}\n\
         \n---\n\n\
         {description}"
    );

    if let Some(ctx) = context {
        body.push_str(&format!("\n\n## Context\n{ctx}"));
    }
    if let Some(n) = notes {
        body.push_str(&format!("\n\n## Notes\n{n}"));
    }
    body.push_str("\n\n---\n*Synced from tasks.json by brana*");
    body
}

fn build_labels(task: &Value, config: &SyncConfig) -> Vec<String> {
    let mut labels = Vec::new();

    if config.label_stream {
        if let Some(stream) = task["stream"].as_str() {
            if !stream.is_empty() {
                labels.push(format!("stream:{stream}"));
            }
        }
    }

    if config.label_priority {
        if let Some(priority) = task["priority"].as_str() {
            if !priority.is_empty() {
                labels.push(format!("priority:{priority}"));
            }
        }
    }

    if config.label_tags > 0 {
        if let Some(tags) = task["tags"].as_array() {
            for tag in tags.iter().take(config.label_tags) {
                if let Some(t) = tag.as_str() {
                    labels.push(format!("tag:{t}"));
                }
            }
        }
    }

    // Phase/milestone get enhancement label
    if matches!(task["type"].as_str(), Some("phase" | "milestone")) {
        labels.push("enhancement".to_string());
    }

    labels
}

fn label_color(label: &str) -> &str {
    if label.starts_with("stream:") {
        "0075ca"
    } else if label.starts_with("priority:") {
        "e11d48"
    } else if label.starts_with("tag:") {
        "6b7280"
    } else {
        "ededed"
    }
}

fn get_issue_number(task: &Value) -> Option<u64> {
    task["github_issue"]
        .as_u64()
        .or_else(|| {
            task["github_issue"]
                .as_str()
                .and_then(|s| s.parse::<u64>().ok())
        })
}

fn set_github_issue(data: &mut Value, task_id: &str, number: u64) {
    if let Some(tasks) = data["tasks"].as_array_mut() {
        for t in tasks.iter_mut() {
            if t["id"].as_str() == Some(task_id) {
                t["github_issue"] = Value::Number(number.into());
                break;
            }
        }
    }
}

fn check_gh_auth() -> Result<(), String> {
    let output = Command::new("gh")
        .args(["auth", "status"])
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .map_err(|_| "gh CLI not installed. Install: https://cli.github.com/".to_string())?;

    if !output.success() {
        return Err("GitHub auth required. Run: gh auth login".to_string());
    }
    Ok(())
}

fn find_tasks_file() -> Option<PathBuf> {
    // Prefer git common dir so worktrees share the main repo's tasks.json
    let common_root = Command::new("git")
        .args(["rev-parse", "--git-common-dir"])
        .output()
        .ok()
        .and_then(|o| {
            if o.status.success() {
                let common_git = PathBuf::from(String::from_utf8_lossy(&o.stdout).trim().to_string());
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

    // Fallback: worktree root
    let root = Command::new("git")
        .args(["rev-parse", "--show-toplevel"])
        .output()
        .ok()
        .and_then(|o| {
            if o.status.success() {
                Some(PathBuf::from(
                    String::from_utf8_lossy(&o.stdout).trim().to_string(),
                ))
            } else {
                None
            }
        })?;

    let f = root.join(".claude/tasks.json");
    if f.exists() {
        Some(f)
    } else {
        None
    }
}

fn detect_repo() -> Result<(String, String), String> {
    let output = Command::new("gh")
        .args(["repo", "view", "--json", "owner,name"])
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .output()
        .map_err(|e| format!("gh: {e}"))?;

    if !output.status.success() {
        return Err("could not detect repo".to_string());
    }

    let resp: Value =
        serde_json::from_slice(&output.stdout).map_err(|e| format!("JSON: {e}"))?;
    let owner = resp["owner"]["login"]
        .as_str()
        .ok_or("no owner")?
        .to_string();
    let name = resp["name"].as_str().ok_or("no repo name")?.to_string();
    Ok((owner, name))
}

fn load_sync_config() -> Result<SyncConfig, String> {
    let home = std::env::var("HOME").unwrap_or_default();
    let config_path = PathBuf::from(&home).join(".claude/task-sync-config.json");

    // Detect repo from git remote (fallback)
    let (detected_owner, detected_repo) = detect_repo().unwrap_or_default();

    if config_path.exists() {
        let content = std::fs::read_to_string(&config_path)
            .map_err(|e| format!("config read: {e}"))?;
        let val: Value =
            serde_json::from_str(&content).map_err(|e| format!("config parse: {e}"))?;

        let owner = val["owner"]
            .as_str()
            .unwrap_or(&detected_owner)
            .to_string();

        let keep_streams: Vec<String> = val["keep_streams"]
            .as_array()
            .map(|a| a.iter().filter_map(|v| v.as_str().map(String::from)).collect())
            .unwrap_or_default();

        // Try to find this project in the config
        let repo = if let Some(projects) = val["projects"].as_object() {
            // Find matching project by detecting current project slug
            let current_slug = detect_project_slug();
            if let Some(slug) = &current_slug {
                if let Some(proj) = projects.get(slug.as_str()) {
                    proj["repo"]
                        .as_str()
                        .unwrap_or(&format!("{owner}/{detected_repo}"))
                        .to_string()
                } else {
                    format!("{owner}/{detected_repo}")
                }
            } else {
                format!("{owner}/{detected_repo}")
            }
        } else {
            format!("{owner}/{detected_repo}")
        };

        // Split "owner/repo" into parts
        let (final_owner, final_repo) = if repo.contains('/') {
            let parts: Vec<&str> = repo.splitn(2, '/').collect();
            (parts[0].to_string(), parts[1].to_string())
        } else {
            (owner, repo)
        };

        Ok(SyncConfig {
            owner: final_owner,
            repo: final_repo,
            keep_streams,
            label_stream: true,
            label_priority: true,
            label_tags: 2,
        })
    } else {
        // No config file — use detected repo with defaults
        if detected_owner.is_empty() || detected_repo.is_empty() {
            return Err("no sync config and could not detect repo".to_string());
        }
        Ok(SyncConfig {
            owner: detected_owner,
            repo: detected_repo,
            keep_streams: vec![
                "roadmap".into(),
                "tech-debt".into(),
                "bugs".into(),
            ],
            label_stream: true,
            label_priority: true,
            label_tags: 2,
        })
    }
}

fn detect_project_slug() -> Option<String> {
    let root = Command::new("git")
        .args(["rev-parse", "--show-toplevel"])
        .output()
        .ok()
        .and_then(|o| {
            if o.status.success() {
                Some(String::from_utf8_lossy(&o.stdout).trim().to_string())
            } else {
                None
            }
        })?;

    Path::new(&root)
        .file_name()
        .map(|n| n.to_string_lossy().to_string())
}
