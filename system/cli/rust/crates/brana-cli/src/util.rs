//! Shared helpers used across command modules.

use std::collections::HashMap;
use std::path::PathBuf;
use std::process::Command;

pub fn find_tasks_file() -> Option<PathBuf> {
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

pub fn find_project_root() -> Option<PathBuf> {
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

pub fn home() -> PathBuf {
    PathBuf::from(std::env::var("HOME").unwrap_or_default())
}

pub fn delegate_python(args: &[&str]) {
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

pub fn load_scheduler() -> HashMap<String, serde_json::Value> {
    let path = home().join(".claude/scheduler/scheduler.json");
    std::fs::read_to_string(&path).ok()
        .and_then(|c| serde_json::from_str(&c).ok())
        .unwrap_or_default()
}

pub fn load_status() -> HashMap<String, serde_json::Value> {
    let path = home().join(".claude/scheduler/last-status.json");
    let content = std::fs::read_to_string(&path).unwrap_or_default();
    let content = content.trim();
    if content.is_empty() { return HashMap::new(); }
    serde_json::from_str(content).unwrap_or_default()
}
