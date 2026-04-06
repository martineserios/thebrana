//! Session state types and I/O.
//!
//! Shared between brana-cli (terminal commands) and brana-mcp (MCP tools).
//!
//! State:   ~/.claude/projects/{encoded}/memory/session-state.json
//! History: ~/.claude/projects/{encoded}/memory/session-history.jsonl

use anyhow::{Context, Result};
use chrono::Utc;
use serde::{Deserialize, Serialize};
use std::fs;
use std::io::{BufWriter, Write};
use std::path::{Path, PathBuf};

use crate::util;

// ── Path helpers ────────────────────────────────────────────────────────

/// Encode a project root path into the CC project directory name.
///
/// CC convention: replace `/` and `_` with `-`.
fn encode_path(project_root: &Path) -> String {
    project_root
        .to_string_lossy()
        .replace('/', "-")
        .replace('_', "-")
}

/// Resolve the CC project memory dir for a given project root.
pub fn resolve_memory_dir(project_root: &Path) -> PathBuf {
    util::home()
        .join(".claude/projects")
        .join(encode_path(project_root))
        .join("memory")
}

/// Resolve the session-state.json path for the current project.
pub fn session_state_path(project_root: &Path) -> PathBuf {
    resolve_memory_dir(project_root).join("session-state.json")
}

/// Resolve the session-history.jsonl path for the current project.
pub fn session_history_path(project_root: &Path) -> PathBuf {
    resolve_memory_dir(project_root).join("session-history.jsonl")
}

// ── Data types ──────────────────────────────────────────────────────────

/// Category for next-action items.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "kebab-case")]
pub enum NextCategory {
    FollowUp,
    Maintenance,
    Suggestion,
}

/// A single next-action item.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct NextItem {
    pub text: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub task_id: Option<String>,
    pub category: NextCategory,
}

/// A blocker item.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct Blocker {
    pub text: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub task_id: Option<String>,
}

/// Back-propagation state.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct Backprop {
    pub needed: bool,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub files: Vec<String>,
}

/// Doc drift detection state.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct DocDrift {
    pub detected: bool,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub stale_docs: Vec<String>,
}

/// Test status snapshot.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct TestStatus {
    pub passing: u32,
    pub failing: u32,
}

/// Session state metadata (key files, test status).
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct SessionMeta {
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub key_files: Vec<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub test_status: Option<TestStatus>,
}

/// Session metrics from telemetry JSONL.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct SessionMetrics {
    #[serde(default)]
    pub events: u32,
    #[serde(default)]
    pub corrections: u32,
    #[serde(default)]
    pub test_writes: u32,
    #[serde(default)]
    pub correction_rate: f64,
    #[serde(default)]
    pub test_write_rate: f64,
    #[serde(default)]
    pub cascade_rate: f64,
    #[serde(default)]
    pub delegation_count: u32,
}

/// The full session state (v1 schema).
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct SessionState {
    pub version: u32,
    pub written_at: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub branch: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub session_label: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub consumed_at: Option<String>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub accomplished: Vec<String>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub learnings: Vec<String>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub next: Vec<NextItem>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub blockers: Vec<Blocker>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub backprop: Option<Backprop>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub doc_drift: Option<DocDrift>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub state: Option<SessionMeta>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub metrics: Option<SessionMetrics>,
}

impl SessionState {
    /// Validate the session state. Returns Ok(()) or descriptive errors.
    pub fn validate(&self) -> Result<()> {
        if self.version != 1 {
            anyhow::bail!("unsupported schema version: {} (expected 1)", self.version);
        }
        if self.written_at.is_empty() {
            anyhow::bail!("written_at is required");
        }
        // Validate written_at is parseable as RFC3339
        chrono::DateTime::parse_from_rfc3339(&self.written_at)
            .with_context(|| format!("written_at is not valid RFC3339: {}", self.written_at))?;
        // Validate consumed_at if present
        if let Some(ref ts) = self.consumed_at {
            chrono::DateTime::parse_from_rfc3339(ts)
                .with_context(|| format!("consumed_at is not valid RFC3339: {ts}"))?;
        }
        // Validate next items have non-empty text
        for item in &self.next {
            if item.text.is_empty() {
                anyhow::bail!("next item has empty text");
            }
        }
        Ok(())
    }

    /// Create a minimal session state (for session-end safety net).
    pub fn minimal(branch: Option<String>) -> Self {
        Self {
            version: 1,
            written_at: Utc::now().to_rfc3339(),
            branch,
            session_label: None,
            consumed_at: None,
            accomplished: Vec::new(),
            learnings: Vec::new(),
            next: Vec::new(),
            blockers: Vec::new(),
            backprop: None,
            doc_drift: None,
            state: None,
            metrics: None,
        }
    }
}

// ── I/O ─────────────────────────────────────────────────────────────────

/// Read the current session state, if it exists.
pub fn read_state(project_root: &Path) -> Option<SessionState> {
    let path = session_state_path(project_root);
    fs::read_to_string(&path)
        .ok()
        .and_then(|data| serde_json::from_str(&data).ok())
}

/// Write session state atomically (.tmp → rename).
/// Archives the previous state to history JSONL before overwriting.
pub fn write_state(project_root: &Path, state: &SessionState) -> Result<()> {
    state.validate()?;

    let state_path = session_state_path(project_root);
    let history_path = session_history_path(project_root);

    // Ensure directory exists
    if let Some(parent) = state_path.parent() {
        fs::create_dir_all(parent)?;
    }

    // Archive current state to history before overwriting
    if let Ok(existing) = fs::read_to_string(&state_path) {
        if !existing.trim().is_empty() {
            let file = fs::OpenOptions::new()
                .create(true)
                .append(true)
                .open(&history_path)
                .context("opening session-history.jsonl")?;
            let mut w = BufWriter::new(file);
            // Write the existing state as a single JSONL line
            let compact =
                serde_json::to_string(&serde_json::from_str::<serde_json::Value>(&existing)?)?;
            writeln!(w, "{compact}")?;
        }
    }

    // Atomic write
    let tmp = state_path.with_extension("tmp");
    let json = serde_json::to_string_pretty(state)?;
    fs::write(&tmp, &json)?;
    fs::rename(&tmp, &state_path)?;

    // Rotate history (drop entries > 30 days)
    rotate_history(&history_path)?;

    Ok(())
}

/// Remove history entries older than 30 days.
fn rotate_history(history_path: &Path) -> Result<()> {
    let content = match fs::read_to_string(history_path) {
        Ok(c) => c,
        Err(_) => return Ok(()), // no history file yet
    };

    let cutoff = Utc::now() - chrono::Duration::days(30);
    let mut kept = Vec::new();

    for line in content.lines() {
        if line.trim().is_empty() {
            continue;
        }
        // Try to parse written_at to check age
        if let Ok(entry) = serde_json::from_str::<serde_json::Value>(line) {
            if let Some(ts) = entry.get("written_at").and_then(|v| v.as_str()) {
                if let Ok(dt) = chrono::DateTime::parse_from_rfc3339(ts) {
                    if dt < cutoff {
                        continue; // drop old entry
                    }
                }
            }
        }
        kept.push(line);
    }

    // Rewrite file
    let tmp = history_path.with_extension("rotate-tmp");
    fs::write(&tmp, kept.join("\n") + "\n")?;
    fs::rename(&tmp, history_path)?;

    Ok(())
}

/// Read history entries, most recent first.
pub fn read_history(project_root: &Path, limit: usize) -> Vec<SessionState> {
    let path = session_history_path(project_root);
    let content = match fs::read_to_string(&path) {
        Ok(c) => c,
        Err(_) => return Vec::new(),
    };

    let mut entries: Vec<SessionState> = content
        .lines()
        .filter(|l| !l.trim().is_empty())
        .filter_map(|l| serde_json::from_str(l).ok())
        .collect();

    // Most recent first (by written_at)
    entries.reverse();
    entries.truncate(limit);
    entries
}

// ── Git helpers ─────────────────────────────────────────────────────────

/// Get current git branch name, if in a git repo.
pub fn current_branch() -> Option<String> {
    std::process::Command::new("git")
        .args(["rev-parse", "--abbrev-ref", "HEAD"])
        .output()
        .ok()
        .and_then(|o| {
            if o.status.success() {
                let branch = String::from_utf8_lossy(&o.stdout).trim().to_string();
                if branch.is_empty() || branch == "HEAD" {
                    None
                } else {
                    Some(branch)
                }
            } else {
                None
            }
        })
}

// ── Tests ────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    fn make_state(written_at: &str) -> SessionState {
        SessionState {
            version: 1,
            written_at: written_at.to_string(),
            branch: Some("main".to_string()),
            session_label: Some("test session".to_string()),
            consumed_at: None,
            accomplished: vec!["did thing A".to_string()],
            learnings: vec!["learned X".to_string()],
            next: vec![NextItem {
                text: "do Y next".to_string(),
                task_id: Some("t-001".to_string()),
                category: NextCategory::FollowUp,
            }],
            blockers: Vec::new(),
            backprop: None,
            doc_drift: None,
            state: None,
            metrics: None,
        }
    }

    #[test]
    fn validate_valid_state() {
        let state = make_state("2026-04-06T10:00:00Z");
        assert!(state.validate().is_ok());
    }

    #[test]
    fn validate_wrong_version() {
        let mut state = make_state("2026-04-06T10:00:00Z");
        state.version = 2;
        assert!(state.validate().is_err());
    }

    #[test]
    fn validate_bad_timestamp() {
        let mut state = make_state("not-a-timestamp");
        state.written_at = "not-a-timestamp".to_string();
        assert!(state.validate().is_err());
    }

    #[test]
    fn validate_empty_next_text() {
        let mut state = make_state("2026-04-06T10:00:00Z");
        state.next.push(NextItem {
            text: "".to_string(),
            task_id: None,
            category: NextCategory::Suggestion,
        });
        assert!(state.validate().is_err());
    }

    #[test]
    fn write_and_read_roundtrip() {
        let dir = tempdir().unwrap();
        let root = dir.path();
        let state = make_state("2026-04-06T10:00:00Z");

        write_state(root, &state).unwrap();

        let loaded = read_state(root).expect("state should exist after write");
        assert_eq!(loaded.written_at, "2026-04-06T10:00:00Z");
        assert_eq!(loaded.branch, Some("main".to_string()));
        assert_eq!(loaded.accomplished, vec!["did thing A"]);
    }

    #[test]
    fn write_archives_to_history() {
        let dir = tempdir().unwrap();
        let root = dir.path();

        let state1 = make_state("2026-04-06T10:00:00Z");
        write_state(root, &state1).unwrap();

        let state2 = make_state("2026-04-06T11:00:00Z");
        write_state(root, &state2).unwrap();

        let history = read_history(root, 10);
        assert_eq!(history.len(), 1, "first state should be in history");
        assert_eq!(history[0].written_at, "2026-04-06T10:00:00Z");
    }

    #[test]
    fn read_state_missing_returns_none() {
        let dir = tempdir().unwrap();
        assert!(read_state(dir.path()).is_none());
    }

    #[test]
    fn read_history_empty_returns_vec() {
        let dir = tempdir().unwrap();
        let history = read_history(dir.path(), 5);
        assert!(history.is_empty());
    }

    #[test]
    fn history_limit_respected() {
        let dir = tempdir().unwrap();
        let root = dir.path();

        // Write 3 states in sequence to build up history
        write_state(root, &make_state("2026-04-06T08:00:00Z")).unwrap();
        write_state(root, &make_state("2026-04-06T09:00:00Z")).unwrap();
        write_state(root, &make_state("2026-04-06T10:00:00Z")).unwrap();
        write_state(root, &make_state("2026-04-06T11:00:00Z")).unwrap();

        let history = read_history(root, 2);
        assert_eq!(history.len(), 2);
    }

    #[test]
    fn encode_path_replaces_slashes_and_underscores() {
        let path = PathBuf::from("/home/user/my_project");
        assert_eq!(encode_path(&path), "-home-user-my-project");
    }
}
