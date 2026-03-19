//! Miscellaneous command handlers: portfolio, validate, version, transcribe

use std::path::PathBuf;

use crate::tasks;
use crate::transcribe;

// ── portfolio command ───────────────────────────────────────────────────

pub fn cmd_portfolio() {
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

// ── validate ─────────────────────────────────────────────────────────────

pub fn cmd_validate(file: &PathBuf) {
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

// ── version ─────────────────────────────────────────────────────────────

pub fn cmd_version() {
    println!("brana-cli {} (Rust)", env!("CARGO_PKG_VERSION"));
}

// ── transcribe ──────────────────────────────────────────────────────────

pub fn cmd_transcribe(file: &PathBuf, model: &str) {
    let model_size: transcribe::ModelSize = match model.parse() {
        Ok(s) => s,
        Err(e) => {
            eprintln!("Error: {e}");
            std::process::exit(1);
        }
    };
    match transcribe::transcribe(file.as_path(), &model_size) {
        Ok(text) => println!("{text}"),
        Err(e) => {
            eprintln!("Error: {e:#}");
            std::process::exit(1);
        }
    }
}
