use std::path::{Path, PathBuf};

use anyhow::{Context, Result};
use chrono::Utc;
use serde::{Deserialize, Serialize};

use crate::session::{resolve_memory_dir, NextItem, SessionState};

// ── Path helpers ─────────────────────────────────────────────────────────

pub fn initiative_dir(project_root: &Path) -> PathBuf {
    resolve_memory_dir(project_root).join("session-initiatives")
}

pub fn initiative_path(project_root: &Path, slug: &str) -> PathBuf {
    initiative_dir(project_root).join(format!("{slug}.json"))
}

pub fn initiative_archive_path(project_root: &Path, slug: &str, date: &str) -> PathBuf {
    initiative_dir(project_root).join("archive").join(format!("{slug}-{date}.json"))
}

// ── Schema ───────────────────────────────────────────────────────────────

/// An item moved out of next[] because it was completed or addressed.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct ResolvedItem {
    pub text: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub task_id: Option<String>,
    pub resolved_at: String,
    pub resolved_by: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub resolution: Option<String>,
}

/// Cross-day accumulator for a single initiative.
/// All fields are serde(default) for backward compat — old files missing any field
/// deserialize cleanly.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct InitiativeAccumulator {
    /// Initiative slug (e.g. "rust-cli", "session-continuity").
    pub slug: String,
    /// Human-readable display name (optional).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub name: Option<String>,
    /// RFC3339 timestamp of first session that touched this initiative.
    #[serde(default)]
    pub started_at: String,
    /// RFC3339 timestamp of most recent upsert.
    #[serde(default)]
    pub last_closed: String,
    /// Total number of session closes that contributed to this accumulator.
    #[serde(default)]
    pub sessions_count: u32,
    /// All accomplished items across sessions, deduped by task_id or normalized text.
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub accomplished: Vec<String>,
    /// Outstanding next-action items carrying forward across sessions.
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub next: Vec<NextItem>,
    /// Items moved out of next[] (completed tasks or addressed text-only items).
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub resolved: Vec<ResolvedItem>,
    /// Cross-session learnings, deduped by first 60 chars.
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub learnings: Vec<String>,
    /// All task IDs completed as part of this initiative.
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub tasks_completed: Vec<String>,
    /// All session labels that contributed to this accumulator.
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub session_labels: Vec<String>,
}

impl InitiativeAccumulator {
    pub fn new(slug: &str) -> Self {
        let now = Utc::now().to_rfc3339();
        Self {
            slug: slug.to_string(),
            name: None,
            started_at: now.clone(),
            last_closed: now,
            sessions_count: 0,
            accomplished: Vec::new(),
            next: Vec::new(),
            resolved: Vec::new(),
            learnings: Vec::new(),
            tasks_completed: Vec::new(),
            session_labels: Vec::new(),
        }
    }

    pub fn validate(&self) -> Result<()> {
        if self.slug.is_empty() {
            anyhow::bail!("initiative slug must not be empty");
        }
        if self.slug.contains('/') || self.slug.contains('\\') {
            anyhow::bail!("initiative slug must not contain path separators: {}", self.slug);
        }
        Ok(())
    }
}

// ── I/O ──────────────────────────────────────────────────────────────────

/// Read an existing initiative accumulator, if it exists.
pub fn read_initiative(project_root: &Path, slug: &str) -> Option<InitiativeAccumulator> {
    let path = initiative_path(project_root, slug);
    std::fs::read_to_string(&path)
        .ok()
        .and_then(|data| serde_json::from_str(&data).ok())
}

/// Merge session state into the initiative accumulator and write atomically.
/// Creates the accumulator if it doesn't exist. Pass 1 pruning (task_id-linked
/// completed tasks) runs at merge time. Pass 2 (LLM text-only pruning) is a
/// procedure-level step run by close.md before calling this function.
pub fn upsert_initiative(
    project_root: &Path,
    slug: &str,
    state: &SessionState,
    completed_task_ids: &[String],
) -> Result<()> {
    let mut acc = read_initiative(project_root, slug).unwrap_or_else(|| InitiativeAccumulator::new(slug));

    acc.validate()?;

    let now = Utc::now().to_rfc3339();
    acc.last_closed = now.clone();
    acc.sessions_count += 1;

    // accomplished: append new items, dedup by exact text
    for item in &state.accomplished {
        if !acc.accomplished.contains(item) {
            acc.accomplished.push(item.clone());
        }
    }

    // learnings: append new, dedup by first 60 chars (char-boundary safe)
    for item in &state.learnings {
        let boundary = item.char_indices().nth(60).map(|(i, _)| i).unwrap_or(item.len());
        let prefix = &item[..boundary];
        let already = acc.learnings.iter().any(|l| l.starts_with(prefix));
        if !already {
            acc.learnings.push(item.clone());
        }
    }

    // Pass 1 pruning: move task_id-linked next[] items to resolved[] if task is done.
    let mut surviving_next: Vec<NextItem> = Vec::new();
    for item in acc.next.drain(..) {
        if let Some(ref tid) = item.task_id {
            if completed_task_ids.contains(tid) {
                acc.resolved.push(ResolvedItem {
                    text: item.text,
                    task_id: Some(tid.clone()),
                    resolved_at: now.clone(),
                    resolved_by: "session-close".to_string(),
                    resolution: Some(format!("Task {tid} completed")),
                });
                continue;
            }
        }
        surviving_next.push(item);
    }

    // Merge new next[] from session: dedup by task_id or text
    for item in &state.next {
        let dup = surviving_next.iter().any(|x| {
            (item.task_id.is_some() && x.task_id == item.task_id)
                || x.text == item.text
        });
        if !dup {
            surviving_next.push(item.clone());
        }
    }
    acc.next = surviving_next;

    // tasks_completed: append new IDs from session accomplishments
    for tid in completed_task_ids {
        if !acc.tasks_completed.contains(tid) {
            acc.tasks_completed.push(tid.clone());
        }
    }

    // session_labels: collect from session_labels (breadcrumb) then session_label fallback
    for label in &state.session_labels {
        if !acc.session_labels.contains(label) {
            acc.session_labels.push(label.clone());
        }
    }
    if let Some(ref label) = state.session_label {
        if !state.session_labels.contains(label) && !acc.session_labels.contains(label) {
            acc.session_labels.push(label.clone());
        }
    }

    // Set started_at only on first creation (don't overwrite)
    if acc.sessions_count == 1 {
        acc.started_at = now;
    }

    write_initiative(project_root, &acc)
}

/// Archive an initiative (move to archive/ subdirectory with datestamp).
pub fn archive_initiative(project_root: &Path, slug: &str) -> Result<()> {
    let src = initiative_path(project_root, slug);
    if !src.exists() {
        anyhow::bail!("initiative file not found: {}", src.display());
    }
    let date = Utc::now().format("%Y-%m-%d").to_string();
    let dst = initiative_archive_path(project_root, slug, &date);
    if let Some(parent) = dst.parent() {
        std::fs::create_dir_all(parent)?;
    }
    std::fs::rename(&src, &dst)
        .with_context(|| format!("archiving initiative {slug} to {}", dst.display()))
}

// ── Private helpers ──────────────────────────────────────────────────────

fn write_initiative(project_root: &Path, acc: &InitiativeAccumulator) -> Result<()> {
    acc.validate()?;
    let dir = initiative_dir(project_root);
    std::fs::create_dir_all(&dir)?;
    let path = initiative_path(project_root, &acc.slug);
    let tmp = path.with_extension("tmp");
    let json = serde_json::to_string_pretty(acc)?;
    std::fs::write(&tmp, &json)?;
    std::fs::rename(&tmp, &path)?;
    Ok(())
}

// ── Tests ─────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;
    use crate::session::{NextCategory, NextItem, SessionState};
    use tempfile::tempdir;

    fn make_session(label: &str, accomplished: &[&str], next: Vec<NextItem>, learnings: &[&str]) -> SessionState {
        SessionState {
            version: 1,
            written_at: "2026-05-25T10:00:00Z".to_string(),
            branch: Some("main".to_string()),
            session_label: Some(label.to_string()),
            session_labels: vec![label.to_string()],
            initiative: None,
            consumed_at: None,
            accomplished: accomplished.iter().map(|s| s.to_string()).collect(),
            learnings: learnings.iter().map(|s| s.to_string()).collect(),
            next,
            blockers: Vec::new(),
            backprop: None,
            doc_drift: None,
            state: None,
            metrics: None,
        }
    }

    fn make_next(text: &str, task_id: Option<&str>) -> NextItem {
        NextItem {
            text: text.to_string(),
            task_id: task_id.map(|s| s.to_string()),
            category: NextCategory::FollowUp,
        }
    }

    #[test]
    fn upsert_creates_new_accumulator() {
        let dir = tempdir().unwrap();
        let state = make_session("Session A", &["shipped thing X"], vec![], &[]);
        upsert_initiative(dir.path(), "rust-cli", &state, &[]).unwrap();

        let acc = read_initiative(dir.path(), "rust-cli").expect("accumulator must exist after upsert");
        assert_eq!(acc.slug, "rust-cli");
        assert_eq!(acc.sessions_count, 1);
        assert!(acc.accomplished.contains(&"shipped thing X".to_string()));
        assert!(acc.session_labels.contains(&"Session A".to_string()));
    }

    #[test]
    fn upsert_merges_on_second_call() {
        let dir = tempdir().unwrap();
        let s1 = make_session("Session A", &["did X"], vec![], &["learned Y"]);
        let s2 = make_session("Session B", &["did Z"], vec![], &["learned W"]);
        upsert_initiative(dir.path(), "rust-cli", &s1, &[]).unwrap();
        upsert_initiative(dir.path(), "rust-cli", &s2, &[]).unwrap();

        let acc = read_initiative(dir.path(), "rust-cli").unwrap();
        assert_eq!(acc.sessions_count, 2);
        assert!(acc.accomplished.contains(&"did X".to_string()));
        assert!(acc.accomplished.contains(&"did Z".to_string()));
        assert_eq!(acc.session_labels, vec!["Session A", "Session B"]);
    }

    #[test]
    fn accomplished_deduplicates() {
        let dir = tempdir().unwrap();
        let s1 = make_session("S1", &["same thing"], vec![], &[]);
        let s2 = make_session("S2", &["same thing", "new thing"], vec![], &[]);
        upsert_initiative(dir.path(), "slug", &s1, &[]).unwrap();
        upsert_initiative(dir.path(), "slug", &s2, &[]).unwrap();

        let acc = read_initiative(dir.path(), "slug").unwrap();
        let count = acc.accomplished.iter().filter(|a| a.as_str() == "same thing").count();
        assert_eq!(count, 1, "duplicate accomplished item must not be repeated");
    }

    #[test]
    fn pass1_pruning_moves_completed_tasks_to_resolved() {
        let dir = tempdir().unwrap();
        let s1 = make_session("S1", &[], vec![make_next("do the thing", Some("t-999"))], &[]);
        upsert_initiative(dir.path(), "slug", &s1, &[]).unwrap();

        // Second session: t-999 is now completed
        let s2 = make_session("S2", &[], vec![], &[]);
        upsert_initiative(dir.path(), "slug", &s2, &["t-999".to_string()]).unwrap();

        let acc = read_initiative(dir.path(), "slug").unwrap();
        assert!(acc.next.iter().all(|n| n.task_id.as_deref() != Some("t-999")), "completed task must leave next[]");
        assert!(acc.resolved.iter().any(|r| r.task_id.as_deref() == Some("t-999")), "completed task must appear in resolved[]");
    }

    #[test]
    fn next_deduplicates_by_text() {
        let dir = tempdir().unwrap();
        let s1 = make_session("S1", &[], vec![make_next("do X", None)], &[]);
        let s2 = make_session("S2", &[], vec![make_next("do X", None), make_next("do Y", None)], &[]);
        upsert_initiative(dir.path(), "slug", &s1, &[]).unwrap();
        upsert_initiative(dir.path(), "slug", &s2, &[]).unwrap();

        let acc = read_initiative(dir.path(), "slug").unwrap();
        let x_count = acc.next.iter().filter(|n| n.text == "do X").count();
        assert_eq!(x_count, 1, "duplicate next item by text must not repeat");
        assert_eq!(acc.next.len(), 2);
    }

    #[test]
    fn learnings_dedup_by_prefix() {
        let dir = tempdir().unwrap();
        let long = "A".repeat(80);
        let s1 = make_session("S1", &[], vec![], &[&long]);
        let s2 = make_session("S2", &[], vec![], &[&long]);
        upsert_initiative(dir.path(), "slug", &s1, &[]).unwrap();
        upsert_initiative(dir.path(), "slug", &s2, &[]).unwrap();

        let acc = read_initiative(dir.path(), "slug").unwrap();
        assert_eq!(acc.learnings.len(), 1, "duplicate learning by prefix must not repeat");
    }

    #[test]
    fn validate_rejects_empty_slug() {
        let acc = InitiativeAccumulator::new("");
        assert!(acc.validate().is_err());
    }

    #[test]
    fn validate_rejects_path_separator_in_slug() {
        let acc = InitiativeAccumulator::new("a/b");
        assert!(acc.validate().is_err());
    }

    #[test]
    fn archive_moves_file() {
        let dir = tempdir().unwrap();
        let state = make_session("S1", &["x"], vec![], &[]);
        upsert_initiative(dir.path(), "slug", &state, &[]).unwrap();
        assert!(initiative_path(dir.path(), "slug").exists());

        archive_initiative(dir.path(), "slug").unwrap();
        assert!(!initiative_path(dir.path(), "slug").exists(), "archived file must be removed from active dir");
        let archived: Vec<_> = std::fs::read_dir(initiative_dir(dir.path()).join("archive"))
            .unwrap()
            .filter_map(|e| e.ok())
            .collect();
        assert!(!archived.is_empty(), "archive dir must contain the moved file");
    }

    #[test]
    fn old_json_without_session_labels_deserializes() {
        let json = r#"{"slug":"rust-cli","started_at":"2026-05-01T00:00:00Z","last_closed":"2026-05-01T00:00:00Z","sessions_count":1}"#;
        let acc: InitiativeAccumulator = serde_json::from_str(json)
            .expect("old accumulator JSON without session_labels must deserialize");
        assert!(acc.session_labels.is_empty());
    }
}
