//! brana session — unified session state management.
//!
//! Replaces session-handoff.md + .needs-backprop with structured JSON.
//! State:   ~/.claude/projects/{encoded}/memory/session-state.json
//! History: ~/.claude/projects/{encoded}/memory/session-history.jsonl

use crate::commands::handoff;
use anyhow::{Context, Result};
use chrono::Utc;
use serde::{Deserialize, Serialize};
use std::fs;
use std::io::{BufWriter, Write};
use std::path::PathBuf;

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
        // Validate next categories are valid (enforced by enum, but check emptiness)
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

// ── Paths ───────────────────────────────────────────────────────────────

/// Resolve the session-state.json path for the current project.
pub fn session_state_path(project_root: &std::path::Path) -> PathBuf {
    handoff::resolve_memory_dir(project_root).join("session-state.json")
}

/// Resolve the session-history.jsonl path for the current project.
pub fn session_history_path(project_root: &std::path::Path) -> PathBuf {
    handoff::resolve_memory_dir(project_root).join("session-history.jsonl")
}

// ── I/O ─────────────────────────────────────────────────────────────────

/// Read the current session state, if it exists.
pub fn read_state(project_root: &std::path::Path) -> Option<SessionState> {
    let path = session_state_path(project_root);
    fs::read_to_string(&path)
        .ok()
        .and_then(|data| serde_json::from_str(&data).ok())
}

/// Write session state atomically (.tmp → rename).
/// Archives the previous state to history JSONL before overwriting.
pub fn write_state(project_root: &std::path::Path, state: &SessionState) -> Result<()> {
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
            let compact = serde_json::to_string(&serde_json::from_str::<serde_json::Value>(&existing)?)?;
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
fn rotate_history(history_path: &std::path::Path) -> Result<()> {
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
pub fn read_history(project_root: &std::path::Path, limit: usize) -> Vec<SessionState> {
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

/// Set consumed_at on the current state (optimistic write-first).
pub fn mark_consumed(project_root: &std::path::Path) -> Result<()> {
    let path = session_state_path(project_root);
    let content = fs::read_to_string(&path)
        .context("reading session-state.json")?;
    let mut state: SessionState = serde_json::from_str(&content)
        .context("parsing session-state.json")?;

    state.consumed_at = Some(Utc::now().to_rfc3339());

    // Write directly (no archive, no rotation — just updating consumed_at)
    let tmp = path.with_extension("tmp");
    let json = serde_json::to_string_pretty(&state)?;
    fs::write(&tmp, &json)?;
    fs::rename(&tmp, &path)?;

    Ok(())
}

/// Render session state as human-readable text.
pub fn render_text(state: &SessionState) -> String {
    let mut out = String::new();

    out.push_str(&format!("Session: {}\n", state.written_at));
    if let Some(ref label) = state.session_label {
        out.push_str(&format!("Label: {label}\n"));
    }
    if let Some(ref branch) = state.branch {
        out.push_str(&format!("Branch: {branch}\n"));
    }
    if let Some(ref ts) = state.consumed_at {
        out.push_str(&format!("Consumed: {ts}\n"));
    }

    if !state.accomplished.is_empty() {
        out.push_str("\nAccomplished:\n");
        for item in &state.accomplished {
            out.push_str(&format!("  - {item}\n"));
        }
    }

    if !state.learnings.is_empty() {
        out.push_str("\nLearnings:\n");
        for item in &state.learnings {
            out.push_str(&format!("  - {item}\n"));
        }
    }

    if !state.next.is_empty() {
        out.push_str("\nNext:\n");
        for item in &state.next {
            let cat = serde_json::to_value(&item.category)
                .ok()
                .and_then(|v| v.as_str().map(String::from))
                .unwrap_or_default();
            let task = item.task_id.as_deref().unwrap_or("");
            let suffix = if task.is_empty() {
                format!(" [{cat}]")
            } else {
                format!(" [{cat}, {task}]")
            };
            out.push_str(&format!("  - {}{suffix}\n", item.text));
        }
    }

    if !state.blockers.is_empty() {
        out.push_str("\nBlockers:\n");
        for item in &state.blockers {
            let task = item.task_id.as_deref().map(|t| format!(" ({t})")).unwrap_or_default();
            out.push_str(&format!("  - {}{task}\n", item.text));
        }
    }

    if let Some(ref bp) = state.backprop {
        if bp.needed {
            out.push_str(&format!("\nBackprop needed: {}\n", bp.files.join(", ")));
        }
    }

    if let Some(ref dd) = state.doc_drift {
        if dd.detected {
            out.push_str(&format!("\nDoc drift: {}\n", dd.stale_docs.join(", ")));
        }
    }

    if let Some(ref m) = state.metrics {
        out.push_str(&format!(
            "\nMetrics: {} events, {} corrections ({:.0}%), {} test writes ({:.0}%), {} delegations\n",
            m.events, m.corrections, m.correction_rate * 100.0,
            m.test_writes, m.test_write_rate * 100.0, m.delegation_count
        ));
    }

    out
}

// ── Tests ───────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;
    use serial_test::serial;
    use std::env;
    use std::path::Path;

    fn with_temp_home() -> tempfile::TempDir {
        let tmp = tempfile::tempdir().unwrap();
        unsafe { env::set_var("HOME", tmp.path()) };
        tmp
    }

    fn sample_state() -> SessionState {
        SessionState {
            version: 1,
            written_at: "2026-03-31T20:15:00Z".into(),
            branch: Some("feat/t-798-session-state-structs".into()),
            session_label: Some("session state structs".into()),
            consumed_at: None,
            accomplished: vec!["Built session structs".into()],
            learnings: vec!["TDD first".into()],
            next: vec![
                NextItem {
                    text: "Implement write command".into(),
                    task_id: Some("t-799".into()),
                    category: NextCategory::FollowUp,
                },
                NextItem {
                    text: "Run maintain-specs".into(),
                    task_id: None,
                    category: NextCategory::Maintenance,
                },
            ],
            blockers: vec![Blocker {
                text: "Waiting on CC #24529".into(),
                task_id: Some("t-235".into()),
            }],
            backprop: Some(Backprop {
                needed: true,
                files: vec!["system/hooks/tdd-gate.sh".into()],
            }),
            doc_drift: Some(DocDrift {
                detected: true,
                stale_docs: vec!["docs/reference/hooks.md".into()],
            }),
            state: Some(SessionMeta {
                key_files: vec!["cli/session.rs".into()],
                test_status: Some(TestStatus { passing: 12, failing: 0 }),
            }),
            metrics: Some(SessionMetrics {
                events: 47,
                corrections: 2,
                test_writes: 5,
                correction_rate: 0.04,
                test_write_rate: 0.11,
                cascade_rate: 0.0,
                delegation_count: 3,
            }),
        }
    }

    // ── Struct tests ────────────────────────────────────────────────────

    #[test]
    fn test_session_state_roundtrip() {
        let state = sample_state();
        let json = serde_json::to_string_pretty(&state).unwrap();
        let parsed: SessionState = serde_json::from_str(&json).unwrap();
        assert_eq!(state, parsed);
    }

    #[test]
    fn test_minimal_state() {
        let state = SessionState::minimal(Some("main".into()));
        assert_eq!(state.version, 1);
        assert_eq!(state.branch, Some("main".into()));
        assert!(state.accomplished.is_empty());
        assert!(state.next.is_empty());
        assert!(state.metrics.is_none());
        assert!(state.validate().is_ok());
    }

    #[test]
    fn test_validate_ok() {
        let state = sample_state();
        assert!(state.validate().is_ok());
    }

    #[test]
    fn test_validate_bad_version() {
        let mut state = sample_state();
        state.version = 2;
        let err = state.validate().unwrap_err();
        assert!(err.to_string().contains("unsupported schema version"));
    }

    #[test]
    fn test_validate_empty_written_at() {
        let mut state = sample_state();
        state.written_at = String::new();
        let err = state.validate().unwrap_err();
        assert!(err.to_string().contains("written_at is required"));
    }

    #[test]
    fn test_validate_bad_written_at() {
        let mut state = sample_state();
        state.written_at = "not-a-date".into();
        let err = state.validate().unwrap_err();
        assert!(err.to_string().contains("not valid RFC3339"));
    }

    #[test]
    fn test_validate_bad_consumed_at() {
        let mut state = sample_state();
        state.consumed_at = Some("garbage".into());
        let err = state.validate().unwrap_err();
        assert!(err.to_string().contains("consumed_at"));
    }

    #[test]
    fn test_validate_empty_next_text() {
        let mut state = sample_state();
        state.next.push(NextItem {
            text: String::new(),
            task_id: None,
            category: NextCategory::Suggestion,
        });
        let err = state.validate().unwrap_err();
        assert!(err.to_string().contains("empty text"));
    }

    // ── Serialization edge cases ────────────────────────────────────────

    #[test]
    fn test_next_category_kebab_case() {
        let item = NextItem {
            text: "test".into(),
            task_id: None,
            category: NextCategory::FollowUp,
        };
        let json = serde_json::to_string(&item).unwrap();
        assert!(json.contains("\"follow-up\""));
    }

    #[test]
    fn test_next_category_deserialize_kebab() {
        let json = r#"{"text":"test","category":"follow-up"}"#;
        let item: NextItem = serde_json::from_str(json).unwrap();
        assert_eq!(item.category, NextCategory::FollowUp);
    }

    #[test]
    fn test_skip_serializing_empty_vecs() {
        let state = SessionState::minimal(None);
        let json = serde_json::to_string(&state).unwrap();
        // Empty vecs should be skipped
        assert!(!json.contains("accomplished"));
        assert!(!json.contains("learnings"));
        assert!(!json.contains("\"next\""));
        assert!(!json.contains("blockers"));
    }

    #[test]
    fn test_skip_serializing_none_optionals() {
        let state = SessionState::minimal(None);
        let json = serde_json::to_string(&state).unwrap();
        assert!(!json.contains("branch"));
        assert!(!json.contains("session_label"));
        assert!(!json.contains("consumed_at"));
        assert!(!json.contains("backprop"));
        assert!(!json.contains("doc_drift"));
        assert!(!json.contains("metrics"));
    }

    #[test]
    fn test_deserialize_with_missing_optional_fields() {
        let json = r#"{"version":1,"written_at":"2026-03-31T20:00:00Z"}"#;
        let state: SessionState = serde_json::from_str(json).unwrap();
        assert_eq!(state.version, 1);
        assert!(state.branch.is_none());
        assert!(state.accomplished.is_empty());
        assert!(state.metrics.is_none());
    }

    #[test]
    fn test_metrics_defaults() {
        let json = r#"{"events":10}"#;
        let m: SessionMetrics = serde_json::from_str(json).unwrap();
        assert_eq!(m.events, 10);
        assert_eq!(m.corrections, 0);
        assert_eq!(m.correction_rate, 0.0);
    }

    // ── Path tests ──────────────────────────────────────────────────────

    #[test]
    fn test_session_state_path() {
        let root = Path::new("/home/user/myrepo");
        let path = session_state_path(root);
        assert!(path.to_str().unwrap().contains("memory/session-state.json"));
    }

    #[test]
    fn test_session_history_path() {
        let root = Path::new("/home/user/myrepo");
        let path = session_history_path(root);
        assert!(path.to_str().unwrap().contains("memory/session-history.jsonl"));
    }

    // ── I/O tests ───────────────────────────────────────────────────────

    #[test]
    #[serial]
    fn test_write_and_read_state() {
        let _tmp = with_temp_home();
        let root = Path::new("/home/user/myrepo");

        let state = sample_state();
        write_state(root, &state).unwrap();

        let loaded = read_state(root).unwrap();
        assert_eq!(loaded.version, 1);
        assert_eq!(loaded.branch, Some("feat/t-798-session-state-structs".into()));
        assert_eq!(loaded.accomplished.len(), 1);
        assert_eq!(loaded.next.len(), 2);
    }

    #[test]
    #[serial]
    fn test_read_state_missing_returns_none() {
        let _tmp = with_temp_home();
        let root = Path::new("/home/user/nonexistent");
        assert!(read_state(root).is_none());
    }

    #[test]
    #[serial]
    fn test_write_archives_previous() {
        let _tmp = with_temp_home();
        let root = Path::new("/home/user/myrepo");

        // Write first state
        let state1 = sample_state();
        write_state(root, &state1).unwrap();

        // Write second state
        let mut state2 = sample_state();
        state2.session_label = Some("second session".into());
        state2.written_at = "2026-03-31T21:00:00Z".into();
        write_state(root, &state2).unwrap();

        // Current state should be state2
        let current = read_state(root).unwrap();
        assert_eq!(current.session_label, Some("second session".into()));

        // History should contain state1
        let history = read_history(root, 10);
        assert_eq!(history.len(), 1);
        assert_eq!(history[0].session_label, Some("session state structs".into()));
    }

    #[test]
    #[serial]
    fn test_mark_consumed() {
        let _tmp = with_temp_home();
        let root = Path::new("/home/user/myrepo");

        let state = sample_state();
        write_state(root, &state).unwrap();

        assert!(read_state(root).unwrap().consumed_at.is_none());

        mark_consumed(root).unwrap();

        let loaded = read_state(root).unwrap();
        assert!(loaded.consumed_at.is_some());
    }

    #[test]
    #[serial]
    fn test_history_limit() {
        let _tmp = with_temp_home();
        let root = Path::new("/home/user/myrepo");

        // Write 5 states (each archives the previous)
        for i in 0..5 {
            let mut state = sample_state();
            state.written_at = format!("2026-03-31T{:02}:00:00Z", 10 + i);
            state.session_label = Some(format!("session {i}"));
            write_state(root, &state).unwrap();
        }

        // History should have 4 entries (5 writes, first 4 archived)
        let all = read_history(root, 100);
        assert_eq!(all.len(), 4);

        // Limit works
        let limited = read_history(root, 2);
        assert_eq!(limited.len(), 2);
        // Most recent first
        assert_eq!(limited[0].session_label, Some("session 3".into())); // most recent archived
    }

    #[test]
    #[serial]
    fn test_atomic_write_no_tmp_left() {
        let _tmp = with_temp_home();
        let root = Path::new("/home/user/myrepo");

        let state = sample_state();
        write_state(root, &state).unwrap();

        let tmp_path = session_state_path(root).with_extension("tmp");
        assert!(!tmp_path.exists());
    }

    // ── Render tests ────────────────────────────────────────────────────

    #[test]
    fn test_render_text_basic() {
        let state = sample_state();
        let text = render_text(&state);
        assert!(text.contains("Session: 2026-03-31T20:15:00Z"));
        assert!(text.contains("Branch: feat/t-798-session-state-structs"));
        assert!(text.contains("Built session structs"));
        assert!(text.contains("TDD first"));
        assert!(text.contains("Implement write command"));
        assert!(text.contains("[follow-up, t-799]"));
        assert!(text.contains("[maintenance]"));
        assert!(text.contains("Waiting on CC #24529"));
        assert!(text.contains("Backprop needed"));
        assert!(text.contains("Doc drift"));
        assert!(text.contains("47 events"));
    }

    #[test]
    fn test_render_text_minimal() {
        let state = SessionState::minimal(Some("main".into()));
        let text = render_text(&state);
        assert!(text.contains("Branch: main"));
        assert!(!text.contains("Accomplished"));
        assert!(!text.contains("Next"));
    }

    // ── Rotation test ───────────────────────────────────────────────────

    #[test]
    #[serial]
    fn test_rotate_drops_old_entries() {
        let _tmp = with_temp_home();
        let root = Path::new("/home/user/myrepo");
        let history_path = session_history_path(root);

        // Ensure parent dir
        fs::create_dir_all(history_path.parent().unwrap()).unwrap();

        // Write entries: one recent, one old
        let recent = sample_state();
        let mut old = sample_state();
        old.written_at = "2025-01-01T00:00:00Z".into(); // > 30 days ago

        let recent_line = serde_json::to_string(&recent).unwrap();
        let old_line = serde_json::to_string(&old).unwrap();
        fs::write(&history_path, format!("{old_line}\n{recent_line}\n")).unwrap();

        rotate_history(&history_path).unwrap();

        let entries = read_history(root, 100);
        assert_eq!(entries.len(), 1);
        assert_eq!(entries[0].written_at, "2026-03-31T20:15:00Z");
    }
}
