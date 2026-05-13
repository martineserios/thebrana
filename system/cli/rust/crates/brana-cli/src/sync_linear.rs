//! Linear Issues sync for brana backlog.
//!
//! Auth:   LINEAR_API_KEY env var  OR  ~/.config/brana/linear.env (KEY=VALUE format)
//! Config: ~/.claude/linear-sync-config.json
//!
//! Maps tasks → Linear Issues via tag_project_map.
//! Stores linear_issue_id back in tasks.json for idempotency.

use anyhow::Context;
use crate::tasks;
use serde_json::{json, Value};
use std::collections::HashMap;
use std::path::PathBuf;
use std::process::Command;

const LINEAR_API: &str = "https://api.linear.app/graphql";

// ── Config ─────────────────────────────────────────────────────

struct LinearSyncConfig {
    team_id: String,
    default_project_id: String,
    tag_project_map: HashMap<String, String>,
    keep_streams: Vec<String>,
    keep_statuses: Vec<String>,
}

struct WorkflowStates {
    todo_id: String,
    in_progress_id: String,
}

// ── Entry point ────────────────────────────────────────────────

pub fn cmd_sync_linear(dry_run: bool, force: bool, project: Option<&str>) -> anyhow::Result<()> {
    let api_key = load_api_key().context("LINEAR_API_KEY not found")?;
    let mut config = load_config().context("linear-sync-config.json not found or invalid")?;

    // --project flag narrows to a single Linear project
    if let Some(slug) = project {
        let project_id = config
            .tag_project_map
            .get(slug)
            .cloned()
            .unwrap_or_else(|| config.default_project_id.clone());
        // Restrict map to only that project
        config.tag_project_map.retain(|_, v| v == &project_id);
        config.default_project_id = project_id;
    }

    let tasks_file = find_tasks_file().context("tasks.json not found")?;
    let mut data = tasks::load_raw(&tasks_file).map_err(|e| anyhow::anyhow!(e))?;

    let states = fetch_workflow_states(&api_key, &config.team_id)?;

    let all_tasks: Vec<Value> = data["tasks"]
        .as_array()
        .context("tasks is not an array")?
        .clone();

    let mut created = 0usize;
    let mut skipped = 0usize;
    let mut errors: Vec<String> = Vec::new();

    for task in &all_tasks {
        let id = match task["id"].as_str() {
            Some(s) => s,
            None => continue,
        };
        let subject = task["subject"].as_str().unwrap_or("untitled");
        let status = task["status"].as_str().unwrap_or("pending");
        let stream = task["stream"].as_str().unwrap_or("");

        // Stream filter
        if !config.keep_streams.is_empty()
            && !config.keep_streams.iter().any(|s| s == stream)
        {
            continue;
        }

        // Status filter
        if !config.keep_statuses.iter().any(|s| s == status) {
            continue;
        }

        // Skip if already synced (unless --force)
        let has_id = task["linear_issue_id"].as_str().is_some();
        if has_id && !force {
            skipped += 1;
            continue;
        }

        let project_id = resolve_project(task, &config);
        let state_id = if status == "in_progress" {
            &states.in_progress_id
        } else {
            &states.todo_id
        };
        let priority = map_priority(task["priority"].as_str());
        let title = format!("[{}] {}", id, subject);
        let description = build_description(task);

        if dry_run {
            eprintln!(
                "[linear-sync] + {} → project …{} — {}",
                id,
                &project_id[project_id.len().saturating_sub(6)..],
                &subject[..subject.len().min(60)]
            );
            created += 1;
            continue;
        }

        match create_issue(
            &api_key,
            &config.team_id,
            &project_id,
            state_id,
            priority,
            &title,
            &description,
        ) {
            Ok(issue_id) => {
                eprintln!(
                    "[linear-sync] ✓ {} → {}",
                    id,
                    &issue_id[..issue_id.len().min(8)]
                );
                write_back_id(&mut data, id, &issue_id);
                let _ = tasks::save_tasks(&tasks_file, &data);
                created += 1;
            }
            Err(e) => {
                eprintln!("[linear-sync] ✗ {}: {}", id, e);
                errors.push(format!("{}: {}", id, e));
            }
        }
    }

    eprintln!(
        "\n[linear-sync] done — {} pushed, {} skipped, {} errors",
        created,
        skipped,
        errors.len()
    );
    if !errors.is_empty() {
        for e in &errors {
            eprintln!("  error: {e}");
        }
        anyhow::bail!("{} errors during sync", errors.len());
    }
    Ok(())
}

// ── Helpers ────────────────────────────────────────────────────

fn resolve_project(task: &Value, config: &LinearSyncConfig) -> String {
    if let Some(tags) = task["tags"].as_array() {
        for tag in tags {
            if let Some(t) = tag.as_str() {
                if let Some(pid) = config.tag_project_map.get(t) {
                    return pid.clone();
                }
            }
        }
    }
    config.default_project_id.clone()
}

fn map_priority(p: Option<&str>) -> u8 {
    match p {
        Some("P0") => 1,
        Some("P1") => 2,
        Some("P2") => 3,
        Some("P3") => 4,
        _ => 0,
    }
}

fn build_description(task: &Value) -> String {
    let id = task["id"].as_str().unwrap_or("?");
    let stream = task["stream"].as_str().unwrap_or("—");
    let priority = task["priority"].as_str().unwrap_or("—");
    let effort = task["effort"].as_str().unwrap_or("—");
    let description = task["description"].as_str().unwrap_or("");
    let context = task["context"].as_str();
    let notes = task["notes"].as_str();

    let mut body = format!(
        "**brana id:** `{id}` | **stream:** {stream} | **priority:** {priority} | **effort:** {effort}\n"
    );
    if !description.is_empty() {
        body.push_str(&format!("\n{description}"));
    }
    if let Some(ctx) = context {
        body.push_str(&format!("\n\n## Context\n{ctx}"));
    }
    if let Some(n) = notes {
        body.push_str(&format!("\n\n## Notes\n{n}"));
    }
    body.push_str("\n\n---\n*Synced from brana backlog*");
    body
}

fn write_back_id(data: &mut Value, task_id: &str, issue_id: &str) {
    if let Some(tasks) = data["tasks"].as_array_mut() {
        for t in tasks.iter_mut() {
            if t["id"].as_str() == Some(task_id) {
                t["linear_issue_id"] = Value::String(issue_id.to_string());
                break;
            }
        }
    }
}

// ── Linear GraphQL calls ───────────────────────────────────────

fn gql(api_key: &str, query: &str, variables: Value) -> anyhow::Result<Value> {
    let body = json!({ "query": query, "variables": variables });
    let body_str = serde_json::to_string(&body).context("serializing request")?;
    let resp = ureq::post(LINEAR_API)
        .header("Authorization", api_key)
        .header("Content-Type", "application/json")
        .send(body_str.as_str())
        .context("Linear API request failed")?;

    let body = resp.into_body().read_to_string().context("reading Linear response")?;
    let json: Value = serde_json::from_str(&body).context("parsing Linear response JSON")?;

    if let Some(errors) = json["errors"].as_array() {
        let msg = errors
            .iter()
            .filter_map(|e| e["message"].as_str().map(String::from))
            .collect::<Vec<String>>()
            .join("; ");
        anyhow::bail!("Linear GraphQL errors: {msg}");
    }
    Ok(json)
}

fn fetch_workflow_states(api_key: &str, team_id: &str) -> anyhow::Result<WorkflowStates> {
    let q = r#"
        query($teamId: String!) {
            workflowStates(filter: { team: { id: { eq: $teamId } } }) {
                nodes { id name type }
            }
        }
    "#;
    let resp = gql(api_key, q, json!({ "teamId": team_id }))?;
    let nodes = resp["data"]["workflowStates"]["nodes"]
        .as_array()
        .context("no workflowStates nodes")?;

    // Find first state of each type
    let mut todo_id = None::<String>;
    let mut in_progress_id = None::<String>;

    for node in nodes {
        let id = node["id"].as_str().unwrap_or("").to_string();
        let state_type = node["type"].as_str().unwrap_or("");
        match state_type {
            "unstarted" if todo_id.is_none() => todo_id = Some(id),
            "started" if in_progress_id.is_none() => in_progress_id = Some(id),
            _ => {}
        }
    }

    Ok(WorkflowStates {
        todo_id: todo_id.context("no 'unstarted' state found in team")?,
        in_progress_id: in_progress_id.context("no 'started' state found in team")?,
    })
}

fn create_issue(
    api_key: &str,
    team_id: &str,
    project_id: &str,
    state_id: &str,
    priority: u8,
    title: &str,
    description: &str,
) -> anyhow::Result<String> {
    let q = r#"
        mutation CreateIssue($input: IssueCreateInput!) {
            issueCreate(input: $input) {
                success
                issue { id }
            }
        }
    "#;
    let resp = gql(
        api_key,
        q,
        json!({
            "input": {
                "teamId": team_id,
                "projectId": project_id,
                "stateId": state_id,
                "priority": priority,
                "title": title,
                "description": description
            }
        }),
    )?;

    let success = resp["data"]["issueCreate"]["success"]
        .as_bool()
        .unwrap_or(false);
    if !success {
        anyhow::bail!("issueCreate returned success=false");
    }
    resp["data"]["issueCreate"]["issue"]["id"]
        .as_str()
        .map(String::from)
        .context("no issue id in response")
}

// ── Auth ───────────────────────────────────────────────────────

fn load_api_key() -> anyhow::Result<String> {
    if let Ok(key) = std::env::var("LINEAR_API_KEY") {
        if !key.is_empty() {
            return Ok(key);
        }
    }
    // Fall back to ~/.config/brana/linear.env
    let path = home_dir().join(".config/brana/linear.env");
    if path.exists() {
        let content = std::fs::read_to_string(&path)?;
        for line in content.lines() {
            let line = line.trim();
            if line.starts_with('#') || line.is_empty() {
                continue;
            }
            if let Some((k, v)) = line.split_once('=') {
                if k.trim() == "LINEAR_API_KEY" {
                    return Ok(v.trim().to_string());
                }
            }
        }
    }
    anyhow::bail!(
        "LINEAR_API_KEY not set. Export it or add it to ~/.config/brana/linear.env"
    )
}

// ── Config ─────────────────────────────────────────────────────

fn load_config() -> anyhow::Result<LinearSyncConfig> {
    let path = home_dir().join(".claude/linear-sync-config.json");
    let content = std::fs::read_to_string(&path)
        .with_context(|| format!("reading {}", path.display()))?;
    let val: Value = serde_json::from_str(&content)
        .context("parsing linear-sync-config.json")?;

    let team_id = val["team_id"]
        .as_str()
        .context("linear-sync-config.json: missing team_id")?
        .to_string();

    let default_project_id = val["default_project_id"]
        .as_str()
        .context("linear-sync-config.json: missing default_project_id")?
        .to_string();

    let tag_project_map = val["tag_project_map"]
        .as_object()
        .map(|m| {
            m.iter()
                .filter_map(|(k, v)| v.as_str().map(|s| (k.clone(), s.to_string())))
                .collect()
        })
        .unwrap_or_default();

    let keep_streams = val["keep_streams"]
        .as_array()
        .map(|a| a.iter().filter_map(|v| v.as_str().map(String::from)).collect())
        .unwrap_or_else(|| vec!["roadmap".into(), "bugs".into()]);

    let keep_statuses = val["keep_statuses"]
        .as_array()
        .map(|a| a.iter().filter_map(|v| v.as_str().map(String::from)).collect())
        .unwrap_or_else(|| vec!["pending".into(), "in_progress".into()]);

    Ok(LinearSyncConfig {
        team_id,
        default_project_id,
        tag_project_map,
        keep_streams,
        keep_statuses,
    })
}

// ── Utilities ──────────────────────────────────────────────────

fn home_dir() -> PathBuf {
    PathBuf::from(std::env::var("HOME").unwrap_or_default())
}

fn find_tasks_file() -> Option<PathBuf> {
    let common_root = Command::new("git")
        .args(["rev-parse", "--git-common-dir"])
        .output()
        .ok()
        .and_then(|o| {
            if o.status.success() {
                let p = PathBuf::from(String::from_utf8_lossy(&o.stdout).trim().to_string());
                p.parent().map(|x| x.to_path_buf())
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
    f.exists().then_some(f)
}
