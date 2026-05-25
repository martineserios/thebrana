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
    Watch,
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
    #[serde(default)]
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

    /// Strip non-existent filesystem paths from `doc_drift.stale_docs`.
    ///
    /// Called by `write_state()` as a safety net so procedural drift in close
    /// doesn't pollute the next session's drift signals. Paths that don't exist
    /// at write time are heuristic artifacts that have already been invalidated.
    pub fn sanitize(mut self) -> Self {
        // Invariant: consumed_at is set by session-start, never persisted by a write.
        self.consumed_at = None;
        if let Some(ref mut drift) = self.doc_drift {
            drift.stale_docs.retain(|p| Path::new(p).exists());
        }
        self
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
/// Non-existent paths in `doc_drift.stale_docs` are silently stripped before write.
pub fn write_state(project_root: &Path, state: &SessionState) -> Result<()> {
    let state_path = session_state_path(project_root);
    let history_path = session_history_path(project_root);

    // Ensure directory exists
    if let Some(parent) = state_path.parent() {
        fs::create_dir_all(parent)?;
    }

    // Same-day + same-branch merge: union two closes from the same session context.
    // Uses local timezone — UTC comparison misclassifies late-night closes (e.g. 23:30
    // local = next UTC day) and prevents valid same-day merges.
    // Branch check prevents feat-A accomplishments bleeding into main when branches are
    // switched within the same directory on the same calendar day.
    let state_to_write = if let Some(existing) = read_state(project_root) {
        let same_day = chrono::DateTime::parse_from_rfc3339(&existing.written_at)
            .ok()
            .zip(chrono::DateTime::parse_from_rfc3339(&state.written_at).ok())
            .map(|(ex, nw)| {
                ex.with_timezone(&chrono::Local).date_naive()
                    == nw.with_timezone(&chrono::Local).date_naive()
            })
            .unwrap_or(false);
        let same_branch = existing.branch == state.branch;

        if same_day && same_branch {
            merge_states(&existing, state).sanitize()
        } else {
            state.clone().sanitize()
        }
    } else {
        state.clone().sanitize()
    };

    state_to_write.validate()?;

    // Archive current state to history before overwriting.
    // NOTE: archives the pre-merge snapshot, not the merged result — history is a
    // changelog (state *before* each write). To reconstruct end-of-day state, read
    // session-state.json directly; don't replay history expecting the merged output.
    if let Ok(existing_raw) = fs::read_to_string(&state_path) {
        if !existing_raw.trim().is_empty() {
            let file = fs::OpenOptions::new()
                .create(true)
                .append(true)
                .open(&history_path)
                .context("opening session-history.jsonl")?;
            let mut w = BufWriter::new(file);
            let compact = serde_json::to_string(
                &serde_json::from_str::<serde_json::Value>(&existing_raw)?,
            )?;
            writeln!(w, "{compact}")?;
        }
    }

    // Atomic write
    let tmp = state_path.with_extension("tmp");
    let json = serde_json::to_string_pretty(&state_to_write)?;
    fs::write(&tmp, &json)?;
    fs::rename(&tmp, &state_path)?;

    // Rotate history (drop entries > 365 days)
    rotate_history(&history_path)?;

    Ok(())
}

/// Remove history entries older than 365 days.
fn rotate_history(history_path: &Path) -> Result<()> {
    let content = match fs::read_to_string(history_path) {
        Ok(c) => c,
        Err(_) => return Ok(()), // no history file yet
    };

    let cutoff = Utc::now() - chrono::Duration::days(365);
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

/// Merge two session states written on the same day.
///
/// Existing items come first; new items are appended when not already present.
/// consumed_at is always cleared — session-start marks it fresh on next read.
pub fn merge_states(existing: &SessionState, new: &SessionState) -> SessionState {
    let mut merged = new.clone();

    // accomplished: existing first, append new non-duplicates
    let mut accomplished = existing.accomplished.clone();
    for item in &new.accomplished {
        if !accomplished.contains(item) {
            accomplished.push(item.clone());
        }
    }
    merged.accomplished = accomplished;

    // learnings: same order-preserving dedup
    let mut learnings = existing.learnings.clone();
    for item in &new.learnings {
        if !learnings.contains(item) {
            learnings.push(item.clone());
        }
    }
    merged.learnings = learnings;

    // next: dedup by .text (existing wins on collision)
    let mut next = existing.next.clone();
    for item in &new.next {
        if !next.iter().any(|x| x.text == item.text) {
            next.push(item.clone());
        }
    }
    merged.next = next;

    // blockers: dedup by .text
    let mut blockers = existing.blockers.clone();
    for item in &new.blockers {
        if !blockers.iter().any(|x| x.text == item.text) {
            blockers.push(item.clone());
        }
    }
    merged.blockers = blockers;

    // session_label: combine with " | " unless one contains the other
    merged.session_label = match (&existing.session_label, &new.session_label) {
        (Some(el), Some(nl)) => {
            if el == nl || el.contains(nl.as_str()) {
                Some(el.clone())
            } else if nl.contains(el.as_str()) {
                Some(nl.clone())
            } else {
                Some(format!("{el} | {nl}"))
            }
        }
        (Some(el), None) => Some(el.clone()),
        (None, Some(nl)) => Some(nl.clone()),
        (None, None) => None,
    };

    // metrics: sum numeric fields; rates recomputed from totals
    merged.metrics = match (&existing.metrics, &new.metrics) {
        (Some(em), Some(nm)) => {
            let events = em.events + nm.events;
            let corrections = em.corrections + nm.corrections;
            let test_writes = em.test_writes + nm.test_writes;
            let correction_rate = if events > 0 { corrections as f64 / events as f64 } else { 0.0 };
            let test_write_rate = if events > 0 { test_writes as f64 / events as f64 } else { 0.0 };
            Some(SessionMetrics {
                events,
                corrections,
                test_writes,
                correction_rate,
                test_write_rate,
                // Weighted average: approximate raw cascade count from rate × events,
                // sum, then recompute — avoids naive average error when session sizes differ.
                cascade_rate: {
                    let cascades = (em.cascade_rate * em.events as f64).round() as u64
                        + (nm.cascade_rate * nm.events as f64).round() as u64;
                    if events > 0 { cascades as f64 / events as f64 } else { 0.0 }
                },
                delegation_count: em.delegation_count + nm.delegation_count,
            })
        }
        (Some(em), None) => Some(em.clone()),
        (None, Some(nm)) => Some(nm.clone()),
        (None, None) => None,
    };

    // state (SessionMeta): merge key_files; latest test_status wins
    merged.state = match (&existing.state, &new.state) {
        (Some(es), Some(ns)) => {
            let mut key_files = es.key_files.clone();
            for f in &ns.key_files {
                if !key_files.contains(f) {
                    key_files.push(f.clone());
                }
            }
            Some(SessionMeta {
                key_files,
                test_status: ns.test_status.clone().or_else(|| es.test_status.clone()),
            })
        }
        (Some(es), None) => Some(es.clone()),
        (None, Some(ns)) => Some(ns.clone()),
        (None, None) => None,
    };

    // backprop: OR needed; merge files
    merged.backprop = match (&existing.backprop, &new.backprop) {
        (Some(eb), Some(nb)) => {
            let mut files = eb.files.clone();
            for f in &nb.files {
                if !files.contains(f) {
                    files.push(f.clone());
                }
            }
            Some(Backprop { needed: eb.needed || nb.needed, files })
        }
        (Some(eb), None) => Some(eb.clone()),
        (None, Some(nb)) => Some(nb.clone()),
        (None, None) => None,
    };

    // doc_drift: OR detected; merge stale_docs
    merged.doc_drift = match (&existing.doc_drift, &new.doc_drift) {
        (Some(ed), Some(nd)) => {
            let mut stale_docs = ed.stale_docs.clone();
            for d in &nd.stale_docs {
                if !stale_docs.contains(d) {
                    stale_docs.push(d.clone());
                }
            }
            Some(DocDrift { detected: ed.detected || nd.detected, stale_docs })
        }
        (Some(ed), None) => Some(ed.clone()),
        (None, Some(nd)) => Some(nd.clone()),
        (None, None) => None,
    };

    // consumed_at: always None — session-start marks it consumed fresh
    merged.consumed_at = None;

    merged
}

/// Set consumed_at on the current state (atomic in-place update).
///
/// Intentionally bypasses `write_state()` — `sanitize()` always strips `consumed_at`,
/// so routing through it would defeat the purpose. Uses the same .tmp→rename atomic
/// guarantee. Does NOT append to history (consumed_at is a read-side marker, not a
/// new session write).
pub fn mark_consumed(project_root: &Path) -> Result<()> {
    let path = session_state_path(project_root);
    let content = fs::read_to_string(&path).context("reading session-state.json")?;
    let mut state: SessionState = serde_json::from_str(&content).context("parsing session-state.json")?;

    state.consumed_at = Some(Utc::now().to_rfc3339());

    let tmp = path.with_extension("tmp");
    let json = serde_json::to_string_pretty(&state)?;
    fs::write(&tmp, &json)?;
    fs::rename(&tmp, &path)?;

    Ok(())
}

/// Render session state as human-readable text (pure formatting, no I/O).
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

// ── Session insights ─────────────────────────────────────────────────────

/// Friction classification for a single session.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "snake_case")]
pub enum FrictionLabel {
    /// Session was productive — accomplished items, low correction rate, no blockers.
    Clean,
    /// High correction rate or nothing accomplished despite activity.
    Turbulent,
    /// Session ended with active blockers.
    Blocked,
    /// No accomplished items and no learnings — nothing to show.
    Abandoned,
}

impl FrictionLabel {
    pub fn as_str(&self) -> &'static str {
        match self {
            FrictionLabel::Clean => "clean",
            FrictionLabel::Turbulent => "turbulent",
            FrictionLabel::Blocked => "blocked",
            FrictionLabel::Abandoned => "abandoned",
        }
    }
}

/// Per-session row in the insights report.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SessionInsightRow {
    pub date: String,
    pub label: FrictionLabel,
    pub session_label: Option<String>,
    pub accomplished: usize,
    pub correction_rate: f64,
    pub blockers: usize,
}

/// Aggregate insights over a window of sessions.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct InsightsSummary {
    pub total: usize,
    pub clean: usize,
    pub turbulent: usize,
    pub blocked: usize,
    pub abandoned: usize,
    pub avg_correction_rate: f64,
    pub sessions: Vec<SessionInsightRow>,
    pub suggestions: Vec<String>,
}

/// Classify a session into a friction label using metrics-only rules (no LLM).
///
/// Rules (in priority order):
/// 1. `abandoned` — nothing accomplished AND no learnings
/// 2. `blocked`   — had active blockers at close
/// 3. `turbulent` — correction_rate > 0.35
/// 4. `clean`     — default
pub fn friction_label(state: &SessionState) -> FrictionLabel {
    if state.accomplished.is_empty() && state.learnings.is_empty() {
        return FrictionLabel::Abandoned;
    }
    if !state.blockers.is_empty() {
        return FrictionLabel::Blocked;
    }
    if let Some(ref m) = state.metrics {
        if m.correction_rate > 0.35 {
            return FrictionLabel::Turbulent;
        }
    }
    FrictionLabel::Clean
}

/// Compute aggregate insights over a slice of session history entries.
pub fn compute_insights(history: &[SessionState]) -> InsightsSummary {
    let mut clean = 0usize;
    let mut turbulent = 0usize;
    let mut blocked = 0usize;
    let mut abandoned = 0usize;
    let mut total_correction_rate = 0.0f64;
    let mut sessions = Vec::new();

    for state in history {
        let label = friction_label(state);
        match label {
            FrictionLabel::Clean => clean += 1,
            FrictionLabel::Turbulent => turbulent += 1,
            FrictionLabel::Blocked => blocked += 1,
            FrictionLabel::Abandoned => abandoned += 1,
        }
        let correction_rate = state.metrics.as_ref().map(|m| m.correction_rate).unwrap_or(0.0);
        total_correction_rate += correction_rate;
        sessions.push(SessionInsightRow {
            date: state.written_at.clone(),
            label,
            session_label: state.session_label.clone(),
            accomplished: state.accomplished.len(),
            correction_rate,
            blockers: state.blockers.len(),
        });
    }

    let total = history.len();
    let avg_correction_rate = if total > 0 {
        total_correction_rate / total as f64
    } else {
        0.0
    };

    let mut suggestions = Vec::new();
    if abandoned > 0 {
        suggestions.push(format!(
            "{abandoned} session(s) produced no output — run /brana:sitrep before starting long sessions"
        ));
    }
    if turbulent > 0 {
        let pct = (turbulent as f64 / total as f64 * 100.0).round() as u32;
        suggestions.push(format!(
            "{turbulent} session(s) ({pct}%) had high correction rate — spec before code reduces rework"
        ));
    }
    if blocked > 0 {
        suggestions.push(format!(
            "{blocked} session(s) ended with active blockers — run /brana:backlog to clear stale blocked tasks"
        ));
    }

    InsightsSummary {
        total,
        clean,
        turbulent,
        blocked,
        abandoned,
        avg_correction_rate,
        sessions,
        suggestions,
    }
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

    // ── friction_label tests ──────────────────────────────────────────────

    fn make_state_with(
        written_at: &str,
        accomplished: Vec<&str>,
        learnings: Vec<&str>,
        blockers: Vec<&str>,
        correction_rate: Option<f64>,
    ) -> SessionState {
        SessionState {
            version: 1,
            written_at: written_at.to_string(),
            branch: None,
            session_label: None,
            consumed_at: None,
            accomplished: accomplished.into_iter().map(String::from).collect(),
            learnings: learnings.into_iter().map(String::from).collect(),
            next: Vec::new(),
            blockers: blockers
                .into_iter()
                .map(|t| Blocker { text: t.to_string(), task_id: None })
                .collect(),
            backprop: None,
            doc_drift: None,
            state: None,
            metrics: correction_rate.map(|r| SessionMetrics {
                events: 10,
                corrections: 0,
                test_writes: 0,
                correction_rate: r,
                test_write_rate: 0.0,
                cascade_rate: 0.0,
                delegation_count: 0,
            }),
        }
    }

    #[test]
    fn friction_label_clean() {
        let s = make_state_with("2026-04-06T10:00:00Z", vec!["shipped X"], vec![], vec![], None);
        assert_eq!(friction_label(&s), FrictionLabel::Clean);
    }

    #[test]
    fn friction_label_abandoned_nothing() {
        let s = make_state_with("2026-04-06T10:00:00Z", vec![], vec![], vec![], None);
        assert_eq!(friction_label(&s), FrictionLabel::Abandoned);
    }

    #[test]
    fn friction_label_abandoned_only_if_no_learnings_either() {
        // Has learnings but no accomplished → not abandoned
        let s = make_state_with(
            "2026-04-06T10:00:00Z",
            vec![],
            vec!["learned something"],
            vec![],
            None,
        );
        // no blockers, no high correction rate → clean
        assert_eq!(friction_label(&s), FrictionLabel::Clean);
    }

    #[test]
    fn friction_label_blocked() {
        let s = make_state_with(
            "2026-04-06T10:00:00Z",
            vec!["did A"],
            vec![],
            vec!["waiting on infra"],
            None,
        );
        assert_eq!(friction_label(&s), FrictionLabel::Blocked);
    }

    #[test]
    fn friction_label_turbulent_high_correction() {
        let s = make_state_with(
            "2026-04-06T10:00:00Z",
            vec!["did A"],
            vec![],
            vec![],
            Some(0.40), // > 0.35 threshold
        );
        assert_eq!(friction_label(&s), FrictionLabel::Turbulent);
    }

    #[test]
    fn friction_label_not_turbulent_below_threshold() {
        let s = make_state_with(
            "2026-04-06T10:00:00Z",
            vec!["did A"],
            vec![],
            vec![],
            Some(0.30), // below 0.35 threshold
        );
        assert_eq!(friction_label(&s), FrictionLabel::Clean);
    }

    #[test]
    fn friction_label_abandoned_takes_priority_over_blocked() {
        // Empty accomplished + empty learnings → abandoned, even if blockers present
        let s = make_state_with("2026-04-06T10:00:00Z", vec![], vec![], vec!["thing"], None);
        assert_eq!(friction_label(&s), FrictionLabel::Abandoned);
    }

    // ── compute_insights tests ────────────────────────────────────────────

    #[test]
    fn insights_empty_history() {
        let summary = compute_insights(&[]);
        assert_eq!(summary.total, 0);
        assert_eq!(summary.avg_correction_rate, 0.0);
        assert!(summary.suggestions.is_empty());
        assert!(summary.sessions.is_empty());
    }

    #[test]
    fn insights_counts_labels() {
        let history = vec![
            make_state_with("2026-04-06T08:00:00Z", vec!["A"], vec![], vec![], None), // clean
            make_state_with("2026-04-06T09:00:00Z", vec![], vec![], vec![], None),    // abandoned
            make_state_with(
                "2026-04-06T10:00:00Z",
                vec!["B"],
                vec![],
                vec!["blocker"],
                None,
            ), // blocked
            make_state_with(
                "2026-04-06T11:00:00Z",
                vec!["C"],
                vec![],
                vec![],
                Some(0.50),
            ), // turbulent
        ];
        let summary = compute_insights(&history);
        assert_eq!(summary.total, 4);
        assert_eq!(summary.clean, 1);
        assert_eq!(summary.abandoned, 1);
        assert_eq!(summary.blocked, 1);
        assert_eq!(summary.turbulent, 1);
    }

    #[test]
    fn insights_avg_correction_rate() {
        let history = vec![
            make_state_with("2026-04-06T08:00:00Z", vec!["A"], vec![], vec![], Some(0.2)),
            make_state_with("2026-04-06T09:00:00Z", vec!["B"], vec![], vec![], Some(0.4)),
        ];
        let summary = compute_insights(&history);
        let expected = (0.2 + 0.4) / 2.0;
        assert!((summary.avg_correction_rate - expected).abs() < 1e-9);
    }

    #[test]
    fn insights_suggestions_for_abandoned() {
        let history = vec![make_state_with(
            "2026-04-06T08:00:00Z",
            vec![],
            vec![],
            vec![],
            None,
        )];
        let summary = compute_insights(&history);
        assert!(summary.suggestions.iter().any(|s| s.contains("no output")));
    }

    #[test]
    fn insights_suggestions_for_turbulent() {
        let history = vec![make_state_with(
            "2026-04-06T08:00:00Z",
            vec!["A"],
            vec![],
            vec![],
            Some(0.50),
        )];
        let summary = compute_insights(&history);
        assert!(summary.suggestions.iter().any(|s| s.contains("correction rate")));
    }

    #[test]
    fn insights_no_suggestions_for_clean() {
        let history = vec![make_state_with(
            "2026-04-06T08:00:00Z",
            vec!["A"],
            vec![],
            vec![],
            Some(0.10),
        )];
        let summary = compute_insights(&history);
        assert!(summary.suggestions.is_empty());
    }

    // ── stale_docs path sanitization ─────────────────────────────────────

    #[test]
    fn stale_docs_nonexistent_paths_filtered_on_write() {
        let dir = tempdir().unwrap();
        let root = dir.path();

        // Create a real file to include
        let real_file = root.join("existing.md");
        fs::write(&real_file, "content").unwrap();

        let mut state = make_state("2026-05-18T10:00:00Z");
        state.doc_drift = Some(DocDrift {
            detected: true,
            stale_docs: vec![
                real_file.to_string_lossy().to_string(),
                "/nonexistent/docs/architecture/cli.md".to_string(),
            ],
        });

        write_state(root, &state).unwrap();

        let loaded = read_state(root).unwrap();
        let stale = &loaded.doc_drift.as_ref().unwrap().stale_docs;
        assert_eq!(stale.len(), 1, "non-existent path should be filtered out");
        assert!(stale[0].ends_with("existing.md"), "real path should be kept");
    }

    #[test]
    fn stale_docs_all_nonexistent_yields_empty_vec() {
        let dir = tempdir().unwrap();
        let root = dir.path();

        let mut state = make_state("2026-05-18T10:00:00Z");
        state.doc_drift = Some(DocDrift {
            detected: true,
            stale_docs: vec![
                "/nonexistent/path/a.md".to_string(),
                "/nonexistent/path/b.md".to_string(),
            ],
        });

        write_state(root, &state).unwrap();

        let loaded = read_state(root).unwrap();
        let stale = &loaded.doc_drift.as_ref().unwrap().stale_docs;
        assert!(stale.is_empty(), "all non-existent paths should be filtered");
    }

    #[test]
    fn stale_docs_all_existing_kept_intact() {
        let dir = tempdir().unwrap();
        let root = dir.path();

        let file_a = root.join("a.md");
        let file_b = root.join("b.md");
        fs::write(&file_a, "a").unwrap();
        fs::write(&file_b, "b").unwrap();

        let mut state = make_state("2026-05-18T10:00:00Z");
        state.doc_drift = Some(DocDrift {
            detected: true,
            stale_docs: vec![
                file_a.to_string_lossy().to_string(),
                file_b.to_string_lossy().to_string(),
            ],
        });

        write_state(root, &state).unwrap();

        let loaded = read_state(root).unwrap();
        let stale = &loaded.doc_drift.as_ref().unwrap().stale_docs;
        assert_eq!(stale.len(), 2, "all existing paths should be preserved");
    }

    // ── merge_states ─────────────────────────────────────────────────────

    fn make_next(text: &str, cat: NextCategory) -> NextItem {
        NextItem { text: text.to_string(), task_id: None, category: cat }
    }

    fn make_blocker(text: &str) -> Blocker {
        Blocker { text: text.to_string(), task_id: None }
    }

    #[test]
    fn merge_states_deduplicates_accomplished() {
        let existing = SessionState {
            accomplished: vec!["a".to_string(), "b".to_string()],
            ..SessionState::minimal(None)
        };
        let new = SessionState {
            accomplished: vec!["b".to_string(), "c".to_string()],
            ..SessionState::minimal(None)
        };
        let merged = merge_states(&existing, &new);
        assert_eq!(merged.accomplished, vec!["a", "b", "c"]);
    }

    #[test]
    fn merge_states_deduplicates_next_by_text() {
        let existing = SessionState {
            next: vec![make_next("do x", NextCategory::FollowUp)],
            ..SessionState::minimal(None)
        };
        let new = SessionState {
            next: vec![
                make_next("do x", NextCategory::Maintenance),
                make_next("do y", NextCategory::FollowUp),
            ],
            ..SessionState::minimal(None)
        };
        let merged = merge_states(&existing, &new);
        assert_eq!(merged.next.len(), 2);
        assert_eq!(merged.next[0].text, "do x");
        assert_eq!(merged.next[1].text, "do y");
    }

    #[test]
    fn merge_states_consumed_at_always_none() {
        let ts = "2026-05-24T10:00:00Z".to_string();
        let existing = SessionState {
            consumed_at: Some(ts.clone()),
            ..SessionState::minimal(None)
        };
        let new = SessionState {
            consumed_at: None,
            ..SessionState::minimal(None)
        };
        let merged = merge_states(&existing, &new);
        assert_eq!(merged.consumed_at, None, "consumed_at must always be None after merge");
    }

    #[test]
    fn merge_states_metrics_sum() {
        let existing = SessionState {
            metrics: Some(SessionMetrics {
                events: 10, corrections: 2, test_writes: 3,
                correction_rate: 0.0, test_write_rate: 0.0,
                cascade_rate: 0.0, delegation_count: 1,
            }),
            ..SessionState::minimal(None)
        };
        let new = SessionState {
            metrics: Some(SessionMetrics {
                events: 5, corrections: 1, test_writes: 2,
                correction_rate: 0.0, test_write_rate: 0.0,
                cascade_rate: 0.0, delegation_count: 0,
            }),
            ..SessionState::minimal(None)
        };
        let merged = merge_states(&existing, &new);
        let m = merged.metrics.unwrap();
        assert_eq!(m.events, 15);
        assert_eq!(m.corrections, 3);
        assert_eq!(m.test_writes, 5);
        assert_eq!(m.delegation_count, 1);
    }

    #[test]
    fn merge_states_cascade_rate_weighted() {
        // Session A: 100 events, cascade_rate 0.10 → ~10 cascades
        // Session B: 10 events,  cascade_rate 0.50 → ~5 cascades
        // Naive average: (0.10 + 0.50) / 2 = 0.30  ← wrong
        // Weighted:      15 / 110             = 0.136 ← correct
        let a = SessionState {
            metrics: Some(SessionMetrics {
                events: 100, corrections: 0, test_writes: 0,
                correction_rate: 0.0, test_write_rate: 0.0,
                cascade_rate: 0.10, delegation_count: 0,
            }),
            ..SessionState::minimal(None)
        };
        let b = SessionState {
            metrics: Some(SessionMetrics {
                events: 10, corrections: 0, test_writes: 0,
                correction_rate: 0.0, test_write_rate: 0.0,
                cascade_rate: 0.50, delegation_count: 0,
            }),
            ..SessionState::minimal(None)
        };
        let merged = merge_states(&a, &b);
        let rate = merged.metrics.unwrap().cascade_rate;
        // Should be ~0.136, not 0.30
        assert!(rate < 0.20, "cascade_rate should be weighted by events, got {rate}");
        assert!(rate > 0.10, "cascade_rate should be above the lower bound, got {rate}");
    }

    #[test]
    fn merge_states_session_label_separator() {
        let existing = SessionState {
            session_label: Some("Session A".to_string()),
            ..SessionState::minimal(None)
        };
        let new = SessionState {
            session_label: Some("Session B".to_string()),
            ..SessionState::minimal(None)
        };
        let merged = merge_states(&existing, &new);
        assert_eq!(merged.session_label, Some("Session A | Session B".to_string()));
    }

    #[test]
    fn merge_states_deduplicates_blockers() {
        let existing = SessionState {
            blockers: vec![make_blocker("blocker 1")],
            ..SessionState::minimal(None)
        };
        let new = SessionState {
            blockers: vec![make_blocker("blocker 1"), make_blocker("blocker 2")],
            ..SessionState::minimal(None)
        };
        let merged = merge_states(&existing, &new);
        assert_eq!(merged.blockers.len(), 2);
    }

    #[test]
    fn write_state_clears_consumed_at_on_different_day_write() {
        // Simulates MCP surface: no call-site guard, state arrives with consumed_at set,
        // written_at is in the past (different day → no same-day merge path).
        let dir = tempdir().unwrap();
        let root = dir.path();
        let mut state = make_state("2026-04-05T10:00:00Z");
        state.consumed_at = Some("2026-04-05T08:00:00Z".to_string());
        write_state(root, &state).unwrap();
        let loaded = read_state(root).expect("state must exist after write");
        assert!(loaded.consumed_at.is_none(), "write_state must clear consumed_at regardless of call site");
    }

    #[test]
    fn next_item_watch_roundtrip() {
        let item = NextItem {
            text: "monitor this".to_string(),
            task_id: None,
            category: NextCategory::Watch,
        };
        let json = serde_json::to_string(&item).unwrap();
        assert!(json.contains("\"watch\""), "Watch variant must serialize as kebab-case 'watch'");
        let back: NextItem = serde_json::from_str(&json).unwrap();
        assert_eq!(back, item, "Watch round-trip must produce identical NextItem");
    }

    #[test]
    fn session_state_missing_written_at_deserializes() {
        // Verifies #[serde(default)] on written_at — JSON without the field must deserialize
        // successfully so read_state() can handle old/partial session files.
        let json = r#"{"version":1,"accomplished":["did x"]}"#;
        let state: SessionState = serde_json::from_str(json)
            .expect("session state missing written_at must deserialize with serde(default)");
        assert!(state.written_at.is_empty(), "written_at must default to empty when omitted");
    }
}
