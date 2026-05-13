//! Linear sync for brana backlog — initiatives, phases, milestones.
//!
//! Auth:   LINEAR_API_KEY env var  OR  ~/.config/brana/linear.env (KEY=VALUE format)
//! Config: ~/.claude/linear-sync-config.json
//!
//! Hierarchy (3-pass):
//!   in-XXX (initiative) → Linear Initiative + initiativeToProject link
//!   ph-XXX (phase)      → Linear ProjectMilestone on the project
//!   ms-XXX (milestone)  → Linear Issue with projectMilestoneId pointing to parent phase
//!   t-XXX  (task)       → stays in brana backlog only
//!
//! Stored IDs:
//!   in-XXX → linear_initiative_id
//!   ph-XXX → linear_milestone_id
//!   ms-XXX → linear_issue_id

use anyhow::Context;
use crate::tasks;
use serde_json::{json, Value};
use std::collections::HashMap;
use std::path::PathBuf;
use std::process::{Command, Stdio};

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

    if let Some(slug) = project {
        let project_id = config
            .tag_project_map
            .get(slug)
            .cloned()
            .unwrap_or_else(|| config.default_project_id.clone());
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

    // ── Pass 0: in-XXX → Linear Initiatives ───────────────────

    let initiatives: Vec<&Value> = all_tasks
        .iter()
        .filter(|t| t["id"].as_str().map(|id| id.starts_with("in-")).unwrap_or(false))
        .filter(|t| passes_status_filter(t, &config))
        .collect();

    for initiative in &initiatives {
        let id = initiative["id"].as_str().unwrap();
        let subject = initiative["subject"].as_str().unwrap_or("untitled");

        if initiative["linear_initiative_id"].as_str().is_some() && !force {
            skipped += 1;
            continue;
        }

        let project_id = resolve_project(initiative, &config);

        if dry_run {
            eprintln!(
                "[linear-sync] initiative + {} → project …{} — {}",
                id,
                &project_id[project_id.len().saturating_sub(6)..],
                &subject.chars().take(60).collect::<String>()
            );
            created += 1;
            continue;
        }

        let description = initiative["description"].as_str().unwrap_or("");
        match create_initiative(&api_key, subject, description) {
            Ok(initiative_linear_id) => {
                eprintln!(
                    "[linear-sync] ✓ initiative {} → {}",
                    id,
                    &initiative_linear_id[..initiative_linear_id.len().min(8)]
                );
                // Link initiative to project
                if let Err(e) = link_initiative_to_project(&api_key, &initiative_linear_id, &project_id) {
                    eprintln!("[linear-sync] ⚠ could not link {} to project: {}", id, e);
                }
                write_back_initiative_id(&mut data, id, &initiative_linear_id);
                let _ = tasks::save_tasks(&tasks_file, &data);
                created += 1;
            }
            Err(e) => {
                eprintln!("[linear-sync] ✗ {}: {}", id, e);
                errors.push(format!("{}: {}", id, e));
            }
        }
    }

    // ── Pass 1: ph-XXX → Linear Milestones ────────────────────

    // Pre-load already-synced phase → milestone_id mappings
    let mut phase_milestone_map: HashMap<String, String> = all_tasks
        .iter()
        .filter_map(|t| {
            let id = t["id"].as_str()?;
            let mid = t["linear_milestone_id"].as_str()?;
            if id.starts_with("ph-") { Some((id.to_string(), mid.to_string())) } else { None }
        })
        .collect();

    let phases: Vec<&Value> = all_tasks
        .iter()
        .filter(|t| t["id"].as_str().map(|id| id.starts_with("ph-")).unwrap_or(false))
        .filter(|t| passes_status_filter(t, &config))
        .collect();

    for phase in &phases {
        let id = phase["id"].as_str().unwrap();
        let subject = phase["subject"].as_str().unwrap_or("untitled");

        if phase_milestone_map.contains_key(id) && !force {
            skipped += 1;
            continue;
        }

        let project_id = resolve_project(phase, &config);

        if dry_run {
            eprintln!(
                "[linear-sync] milestone + {} → project …{} — {}",
                id,
                &project_id[project_id.len().saturating_sub(6)..],
                &subject.chars().take(60).collect::<String>()
            );
            created += 1;
            continue;
        }

        match create_milestone(&api_key, &project_id, subject) {
            Ok(milestone_id) => {
                eprintln!(
                    "[linear-sync] ✓ milestone {} → {}",
                    id,
                    &milestone_id[..milestone_id.len().min(8)]
                );
                phase_milestone_map.insert(id.to_string(), milestone_id.clone());
                write_back_milestone_id(&mut data, id, &milestone_id);
                let _ = tasks::save_tasks(&tasks_file, &data);
                created += 1;
            }
            Err(e) => {
                eprintln!("[linear-sync] ✗ {}: {}", id, e);
                errors.push(format!("{}: {}", id, e));
            }
        }
    }

    // ── Pass 2: ms-XXX → Linear Issues ────────────────────────

    let milestones: Vec<&Value> = all_tasks
        .iter()
        .filter(|t| t["id"].as_str().map(|id| id.starts_with("ms-")).unwrap_or(false))
        .filter(|t| passes_status_filter(t, &config))
        .collect();

    for task in &milestones {
        let id = task["id"].as_str().unwrap();
        let subject = task["subject"].as_str().unwrap_or("untitled");
        let status = task["status"].as_str().unwrap_or("pending");

        if task["linear_issue_id"].as_str().is_some() && !force {
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

        // Resolve Linear milestone from parent phase
        let linear_milestone_id = task["parent"]
            .as_str()
            .and_then(|p| phase_milestone_map.get(p))
            .cloned();

        if dry_run {
            eprintln!(
                "[linear-sync] + {} → project …{}{} — {}",
                id,
                &project_id[project_id.len().saturating_sub(6)..],
                if linear_milestone_id.is_some() { " (milestone)" } else { "" },
                &subject.chars().take(60).collect::<String>()
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
            linear_milestone_id.as_deref(),
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

/// Status-only filter for structural items (in-XXX, ph-XXX, ms-XXX) — no stream check.
fn passes_status_filter(task: &Value, config: &LinearSyncConfig) -> bool {
    let status = task["status"].as_str().unwrap_or("pending");
    config.keep_statuses.iter().any(|s| s == status)
}

/// Full filter for regular tasks — status + stream.
fn passes_filters(task: &Value, config: &LinearSyncConfig) -> bool {
    let stream = task["stream"].as_str().unwrap_or("");
    if !config.keep_streams.is_empty() && !config.keep_streams.iter().any(|s| s == stream) {
        return false;
    }
    passes_status_filter(task, config)
}

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

fn write_back_initiative_id(data: &mut Value, task_id: &str, initiative_id: &str) {
    if let Some(tasks) = data["tasks"].as_array_mut() {
        for t in tasks.iter_mut() {
            if t["id"].as_str() == Some(task_id) {
                t["linear_initiative_id"] = Value::String(initiative_id.to_string());
                break;
            }
        }
    }
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

fn write_back_milestone_id(data: &mut Value, task_id: &str, milestone_id: &str) {
    if let Some(tasks) = data["tasks"].as_array_mut() {
        for t in tasks.iter_mut() {
            if t["id"].as_str() == Some(task_id) {
                t["linear_milestone_id"] = Value::String(milestone_id.to_string());
                break;
            }
        }
    }
}

// ── Linear GraphQL calls (via curl — avoids ureq content-type issues) ─────

fn gql(api_key: &str, query: &str, variables: Value) -> anyhow::Result<Value> {
    let body = json!({ "query": query, "variables": variables });
    let body_str = serde_json::to_string(&body).context("serializing request")?;

    let output = Command::new("curl")
        .args([
            "-s", "-X", "POST",
            LINEAR_API,
            "-H", &format!("Authorization: {api_key}"),
            "-H", "Content-Type: application/json",
            "-d", "@-",
        ])
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .and_then(|mut child| {
            use std::io::Write;
            if let Some(ref mut stdin) = child.stdin {
                stdin.write_all(body_str.as_bytes())?;
            }
            child.wait_with_output()
        })
        .context("curl not found")?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        anyhow::bail!("curl error: {stderr}");
    }

    let json: Value = serde_json::from_slice(&output.stdout)
        .context("parsing Linear response JSON")?;

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
        query($teamId: ID!) {
            workflowStates(filter: { team: { id: { eq: $teamId } } }) {
                nodes { id name type }
            }
        }
    "#;
    let resp = gql(api_key, q, json!({ "teamId": team_id }))?;
    let nodes = resp["data"]["workflowStates"]["nodes"]
        .as_array()
        .context("no workflowStates nodes")?;

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

fn create_milestone(api_key: &str, project_id: &str, name: &str) -> anyhow::Result<String> {
    let q = r#"
        mutation CreateProjectMilestone($input: ProjectMilestoneCreateInput!) {
            projectMilestoneCreate(input: $input) {
                success
                projectMilestone { id }
            }
        }
    "#;
    let resp = gql(api_key, q, json!({
        "input": { "projectId": project_id, "name": name }
    }))?;

    let success = resp["data"]["projectMilestoneCreate"]["success"]
        .as_bool()
        .unwrap_or(false);
    if !success {
        anyhow::bail!("projectMilestoneCreate returned success=false");
    }
    resp["data"]["projectMilestoneCreate"]["projectMilestone"]["id"]
        .as_str()
        .map(String::from)
        .context("no projectMilestone id in response")
}

fn create_issue(
    api_key: &str,
    team_id: &str,
    project_id: &str,
    state_id: &str,
    priority: u8,
    title: &str,
    description: &str,
    milestone_id: Option<&str>,
) -> anyhow::Result<String> {
    let q = r#"
        mutation CreateIssue($input: IssueCreateInput!) {
            issueCreate(input: $input) {
                success
                issue { id }
            }
        }
    "#;

    let mut input = json!({
        "teamId": team_id,
        "projectId": project_id,
        "stateId": state_id,
        "priority": priority,
        "title": title,
        "description": description
    });
    if let Some(mid) = milestone_id {
        input["projectMilestoneId"] = Value::String(mid.to_string());
    }

    let resp = gql(api_key, q, json!({ "input": input }))?;

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

fn create_initiative(api_key: &str, name: &str, description: &str) -> anyhow::Result<String> {
    let q = r#"
        mutation CreateInitiative($input: InitiativeCreateInput!) {
            initiativeCreate(input: $input) {
                success
                initiative { id }
            }
        }
    "#;
    let resp = gql(api_key, q, json!({
        "input": { "name": name, "description": description }
    }))?;

    let success = resp["data"]["initiativeCreate"]["success"]
        .as_bool()
        .unwrap_or(false);
    if !success {
        anyhow::bail!("initiativeCreate returned success=false");
    }
    resp["data"]["initiativeCreate"]["initiative"]["id"]
        .as_str()
        .map(String::from)
        .context("no initiative id in response")
}

fn link_initiative_to_project(api_key: &str, initiative_id: &str, project_id: &str) -> anyhow::Result<()> {
    let q = r#"
        mutation LinkInitiativeToProject($input: InitiativeToProjectCreateInput!) {
            initiativeToProjectCreate(input: $input) {
                success
            }
        }
    "#;
    let resp = gql(api_key, q, json!({
        "input": { "initiativeId": initiative_id, "projectId": project_id }
    }))?;

    let success = resp["data"]["initiativeToProjectCreate"]["success"]
        .as_bool()
        .unwrap_or(false);
    if !success {
        anyhow::bail!("initiativeToProjectCreate returned success=false");
    }
    Ok(())
}

// ── Auth ───────────────────────────────────────────────────────

fn load_api_key() -> anyhow::Result<String> {
    if let Ok(key) = std::env::var("LINEAR_API_KEY") {
        if !key.is_empty() {
            return Ok(key);
        }
    }
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
