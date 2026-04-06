//! Shared helpers for path discovery and config loading.

use std::collections::HashMap;
use std::path::PathBuf;
use std::process::Command;

/// Find the authoritative tasks.json, shared across git worktrees.
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

    // Fallback: try worktree root
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

/// Find the git repository root via `git rev-parse --show-toplevel`.
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

/// Return the user's home directory.
pub fn home() -> PathBuf {
    PathBuf::from(std::env::var("HOME").unwrap_or_default())
}

/// Load scheduler config from `~/.claude/scheduler/scheduler.json`.
pub fn load_scheduler() -> HashMap<String, serde_json::Value> {
    let path = home().join(".claude/scheduler/scheduler.json");
    std::fs::read_to_string(&path).ok()
        .and_then(|c| serde_json::from_str(&c).ok())
        .unwrap_or_default()
}

/// Load scheduler status from `~/.claude/scheduler/last-status.json`.
pub fn load_status() -> HashMap<String, serde_json::Value> {
    let path = home().join(".claude/scheduler/last-status.json");
    let content = std::fs::read_to_string(&path).unwrap_or_default();
    let content = content.trim();
    if content.is_empty() { return HashMap::new(); }
    serde_json::from_str(content).unwrap_or_default()
}
