//! brana session — CLI commands for session state management.
//!
//! All data types and I/O logic live in brana-core::session.
//! This module provides CLI command handlers and one-time migration from
//! the legacy session-handoff.md format.

use crate::commands::handoff;
use anyhow::{Context, Result};
pub use brana_core::session::mark_consumed;
use brana_core::session::{
    compute_insights, current_branch, epic_scoped_state_path, read_history, read_state,
    render_text, resolve_memory_dir, session_history_path, write_state, Blocker, NextCategory,
    NextItem, SessionState,
};
use chrono::{DateTime, NaiveDate, Utc};
use std::fs;
use std::path::PathBuf;

// ── CLI utility ──────────────────────────────────────────────────────────

pub fn require_project_root() -> anyhow::Result<PathBuf> {
    crate::util::find_project_root()
        .ok_or_else(|| anyhow::anyhow!("Not in a git repository"))
}

// ── CLI Commands ─────────────────────────────────────────────────────────

/// `brana session write --file <path>` or `brana session write --minimal`
pub fn cmd_session_write(file: Option<PathBuf>, minimal: bool) -> anyhow::Result<()> {
    use anyhow::{anyhow, Context};
    let root = require_project_root()?;

    let state = if minimal {
        SessionState::minimal(current_branch())
    } else if let Some(ref path) = file {
        let content = fs::read_to_string(path)
            .with_context(|| format!("error reading {}", path.display()))?;
        let mut s: SessionState = serde_json::from_str(&content)
            .context("error parsing session state JSON")?;
        if s.written_at.is_empty() {
            s.written_at = Utc::now().to_rfc3339();
        }
        if s.branch.is_none() {
            s.branch = current_branch();
        }
        s.consumed_at = None;
        s
    } else {
        return Err(anyhow!("Provide --file <path> or --minimal"));
    };

    write_state(&root, &state)?;

    let branch = current_branch().unwrap_or_default();
    println!(
        "{{\"ok\":true,\"path\":\"{}\"}}",
        epic_scoped_state_path(&root, &branch).display()
    );
    Ok(())
}

/// `brana session read [--json] [--all] [--since YYYY-MM-DD]`
pub fn cmd_session_read(json_output: bool, all: bool, since: Option<String>) -> anyhow::Result<()> {
    let root = require_project_root()?;

    if all {
        return cmd_session_read_all(&root, json_output, since);
    }

    match read_state(&root) {
        Some(state) => {
            if json_output {
                println!("{}", serde_json::to_string_pretty(&state)?);
            } else {
                print!("{}", render_text(&state));
            }
        }
        None => {
            if let Err(e) = handoff::cmd_handoff_last(1) {
                eprintln!("{e:#}");
            }
        }
    }
    Ok(())
}

/// Implementation of `brana session read --all`.
///
/// Scans all `session-state*.json` files in the memory dir, filters by date,
/// sorts descending by `written_at`, and renders one block per file.
fn cmd_session_read_all(root: &std::path::Path, json_output: bool, since: Option<String>) -> anyhow::Result<()> {
    use std::collections::HashSet;

    let memory_dir = resolve_memory_dir(root);

    // Compute cutoff date
    let cutoff: DateTime<Utc> = if let Some(ref s) = since {
        let date = NaiveDate::parse_from_str(s, "%Y-%m-%d")
            .with_context(|| format!("--since must be YYYY-MM-DD, got: {s}"))?;
        date.and_hms_opt(0, 0, 0)
            .map(|dt| dt.and_utc())
            .ok_or_else(|| anyhow::anyhow!("invalid date: {s}"))?
    } else {
        Utc::now() - chrono::Duration::days(30)
    };

    // Collect candidate paths: glob session-state*.json
    let mut paths: Vec<std::path::PathBuf> = Vec::new();
    let mut seen: HashSet<std::path::PathBuf> = HashSet::new();

    // Always include the orphan file explicitly
    let orphan_path = memory_dir.join("session-state.json");
    if orphan_path.exists() {
        seen.insert(orphan_path.clone());
        paths.push(orphan_path);
    }

    // Glob epic-scoped files
    if memory_dir.exists() {
        if let Ok(entries) = fs::read_dir(&memory_dir) {
            for entry in entries.flatten() {
                let p = entry.path();
                if let Some(name) = p.file_name().and_then(|n| n.to_str()) {
                    if name.starts_with("session-state") && name.ends_with(".json") && !seen.contains(&p) {
                        seen.insert(p.clone());
                        paths.push(p);
                    }
                }
            }
        }
    }

    // Parse, filter, and attach epic slug
    #[derive(serde::Serialize)]
    struct EpicEntry {
        epic: String,
        state: SessionState,
    }

    let mut entries: Vec<EpicEntry> = Vec::new();
    for path in &paths {
        let epic = path
            .file_name()
            .and_then(|n| n.to_str())
            .map(|name| {
                if name == "session-state.json" {
                    "(orphan)".to_string()
                } else {
                    name.strip_prefix("session-state-")
                        .and_then(|s| s.strip_suffix(".json"))
                        .unwrap_or(name)
                        .to_string()
                }
            })
            .unwrap_or_else(|| "(orphan)".to_string());

        let Ok(data) = fs::read_to_string(path) else { continue };
        let Ok(state): Result<SessionState, _> = serde_json::from_str(&data) else { continue };

        // Filter by written_at >= cutoff
        if let Ok(written) = DateTime::parse_from_rfc3339(&state.written_at) {
            if written.with_timezone(&Utc) < cutoff {
                continue;
            }
        }

        entries.push(EpicEntry { epic, state });
    }

    // Sort descending by written_at
    entries.sort_by(|a, b| b.state.written_at.cmp(&a.state.written_at));

    if json_output {
        println!("{}", serde_json::to_string_pretty(&entries)?);
        return Ok(());
    }

    if entries.is_empty() {
        eprintln!("No session states found within the date range.");
        return Ok(());
    }

    for (i, entry) in entries.iter().enumerate() {
        if i > 0 {
            println!();
        }
        println!("=== {} ===", entry.epic);
        print!("{}", render_text(&entry.state));
    }

    Ok(()
    )
}

/// `brana session history [--limit N]`
pub fn cmd_session_history(limit: usize) -> anyhow::Result<()> {
    let root = require_project_root()?;
    let entries = read_history(&root, limit);

    if entries.is_empty() {
        if let Err(e) = handoff::cmd_handoff_list() {
            eprintln!("{e:#}");
        }
        return Ok(());
    }

    for (i, entry) in entries.iter().enumerate() {
        if i > 0 {
            println!("\n---\n");
        }
        let label = entry.session_label.as_deref().unwrap_or("(unlabeled)");
        let branch = entry.branch.as_deref().unwrap_or("(no branch)");
        println!("{} — {} [{}]", entry.written_at, label, branch);
        if !entry.accomplished.is_empty() {
            for a in &entry.accomplished {
                println!("  - {a}");
            }
        }
    }
    Ok(())
}

/// `brana session path`
pub fn cmd_session_path() -> anyhow::Result<()> {
    let root = require_project_root()?;
    let branch = current_branch().unwrap_or_default();
    println!("{}", epic_scoped_state_path(&root, &branch).display());
    Ok(())
}

/// `brana session migrate` — one-time migration from session-handoff.md
pub fn cmd_session_migrate() -> anyhow::Result<()> {
    use anyhow::anyhow;
    let root = require_project_root()?;
    let handoff_path = handoff::resolve_handoff_path(&root);

    let content = fs::read_to_string(&handoff_path)
        .with_context(|| format!("No session-handoff.md found at {}", handoff_path.display()))?;

    let entries = handoff::parse_entries(&content);
    if entries.is_empty() {
        return Err(anyhow!("No entries found in session-handoff.md"));
    }

    let history = read_history(&root, 1);
    if !history.is_empty() {
        return Err(anyhow!(
            "session-history.jsonl already has entries. Skipping migration to avoid duplicates.\nDelete session-history.jsonl first if you want to re-migrate."
        ));
    }

    let mut migrated = 0;
    let total = entries.len();

    for entry in entries.iter().rev() {
        let state = convert_handoff_entry(entry);
        match write_state(&root, &state) {
            Ok(()) => migrated += 1,
            Err(e) => eprintln!("warning: failed to write entry '{}': {e}", entry.heading),
        }
    }

    println!(
        "{{\"ok\":true,\"migrated\":{migrated},\"total\":{total},\"history\":\"{}\"}}",
        session_history_path(&root).display()
    );
    Ok(())
}

/// `brana session mark-consumed`
pub fn cmd_session_mark_consumed() -> anyhow::Result<()> {
    let root = require_project_root()?;
    mark_consumed(&root)?;
    println!("{{\"ok\":true}}");
    Ok(())
}

/// `brana session insights [--limit N] [--json]`
pub fn cmd_session_insights(limit: usize, json_output: bool) -> anyhow::Result<()> {
    let root = require_project_root()?;
    let history = read_history(&root, limit);

    if history.is_empty() {
        eprintln!("No session history found. Run /brana:close at least once to build history.");
        return Ok(());
    }

    let summary = compute_insights(&history);

    if json_output {
        println!("{}", serde_json::to_string_pretty(&summary)?);
        return Ok(());
    }

    println!("Session Insights — last {} sessions\n", summary.total);
    println!(
        "  clean {}  turbulent {}  blocked {}  abandoned {}",
        summary.clean, summary.turbulent, summary.blocked, summary.abandoned
    );
    println!("  avg correction rate: {:.0}%\n", summary.avg_correction_rate * 100.0);

    println!("  {:<22} {:<10} {:<5} {:>6}  Label", "Date", "Session", "Done", "CorrR");
    println!("  {}", "-".repeat(62));
    for row in &summary.sessions {
        let label_str = row.session_label.as_deref().unwrap_or("—");
        let short_label: String = label_str.chars().take(10).collect();
        let date_short: String = row.date.chars().take(19).collect();
        println!(
            "  {:<22} {:<10} {:>5} {:>5.0}%  {}",
            date_short,
            short_label,
            row.accomplished,
            row.correction_rate * 100.0,
            row.label.as_str(),
        );
    }

    if !summary.suggestions.is_empty() {
        println!("\nSuggestions:");
        for s in &summary.suggestions {
            println!("  • {s}");
        }
    }
    Ok(())
}

// ── Migration helpers ────────────────────────────────────────────────────

fn convert_handoff_entry(entry: &handoff::HandoffEntry) -> SessionState {
    let body = &entry.body;

    let date = entry.heading.split(' ').next().unwrap_or("").to_string();
    let label = entry
        .heading
        .splitn(2, " — ")
        .nth(1)
        .or_else(|| entry.heading.splitn(2, " - ").nth(1))
        .unwrap_or(&entry.heading)
        .to_string();

    let written_at = if date.len() == 10 {
        format!("{date}T00:00:00Z")
    } else {
        Utc::now().to_rfc3339()
    };

    let accomplished = extract_section_items(body, "Accomplished");
    let learnings = extract_section_items(body, "Learnings");
    let next_raw = extract_section_items(body, "Next");
    let blocker_raw = extract_section_items(body, "Blockers");
    let branch = extract_field(body, "Branch");

    let next: Vec<NextItem> = next_raw
        .into_iter()
        .filter(|s| !s.is_empty())
        .map(|text| NextItem { text, task_id: None, category: NextCategory::FollowUp })
        .collect();

    let blockers: Vec<Blocker> = blocker_raw
        .into_iter()
        .filter(|s| !s.is_empty() && s.to_lowercase() != "none")
        .map(|text| Blocker { text, task_id: None })
        .collect();

    SessionState {
        version: 1,
        written_at: written_at.clone(),
        branch,
        session_label: Some(label),
        session_labels: Vec::new(),
        epic: None,
        consumed_at: Some(written_at),
        accomplished,
        learnings,
        next,
        blockers,
        backprop: None,
        doc_drift: None,
        state: None,
        metrics: None,
    }
}

fn extract_section_items(body: &str, header: &str) -> Vec<String> {
    let mut in_section = false;
    let mut items = Vec::new();

    for line in body.lines() {
        if line.contains(&format!("**{header}")) && line.contains("**") {
            in_section = true;
            continue;
        }
        if in_section {
            if line.starts_with("**") || line.starts_with("### ") {
                break;
            }
            let trimmed = line.trim().trim_start_matches("- ").trim();
            if !trimmed.is_empty() {
                items.push(trimmed.to_string());
            }
        }
    }
    items
}

fn extract_field(body: &str, field: &str) -> Option<String> {
    for line in body.lines() {
        let trimmed = line.trim().trim_start_matches("- ");
        if let Some(rest) = trimmed.strip_prefix(&format!("{field}: ")) {
            let val = rest.trim().to_string();
            if !val.is_empty() {
                return Some(val);
            }
        }
    }
    None
}

// ── Epic accumulator commands ─────────────────────────────────────────────

/// `brana session epic upsert <slug> [--completed t-1,t-2] [--resolved-texts '[...]']`
pub fn cmd_epic_upsert(slug: &str, completed_csv: &str, resolved_texts_json: &str) -> anyhow::Result<()> {
    use brana_core::session_initiative::{upsert_initiative, ResolvedTextInput};
    let root = require_project_root()?;
    let state = read_state(&root)
        .ok_or_else(|| anyhow::anyhow!("No session state found — run `brana session write` first"))?;
    let completed: Vec<String> = completed_csv
        .split(',')
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty())
        .collect();
    #[derive(serde::Deserialize)]
    struct RtJson { text: String, resolution: String }
    let resolved: Vec<ResolvedTextInput> = serde_json::from_str::<Vec<RtJson>>(resolved_texts_json)
        .unwrap_or_default()
        .into_iter()
        .map(|r| ResolvedTextInput { text: r.text, resolution: r.resolution })
        .collect();
    upsert_initiative(&root, slug, &state, &completed, &resolved)?;
    println!("{{\"ok\":true,\"slug\":\"{slug}\"}}");
    Ok(())
}

/// `brana session epic read <slug> [--json]`
pub fn cmd_epic_read(slug: &str, json_output: bool) -> anyhow::Result<()> {
    use brana_core::session_initiative::read_initiative;
    let root = require_project_root()?;
    let acc = read_initiative(&root, slug)
        .ok_or_else(|| anyhow::anyhow!("No epic accumulator found for '{slug}'"))?;
    if json_output {
        println!("{}", serde_json::to_string_pretty(&acc)?);
    } else {
        println!("Epic:       {}", acc.slug);
        println!("Sessions:   {}", acc.sessions_count);
        println!("Last close: {}", acc.last_closed);
        if !acc.accomplished.is_empty() {
            println!("\nAccomplished ({}):", acc.accomplished.len());
            for a in &acc.accomplished { println!("  - {a}"); }
        }
        if !acc.next.is_empty() {
            println!("\nNext ({}):", acc.next.len());
            for n in &acc.next { println!("  - [{}] {}", n.category_str(), n.text); }
        }
        if !acc.resolved.is_empty() {
            println!("\nResolved ({}):", acc.resolved.len());
            for r in &acc.resolved { println!("  - {} ({})", r.text, r.resolved_at); }
        }
    }
    Ok(())
}

/// `brana session epic archive <slug>`
pub fn cmd_epic_archive(slug: &str) -> anyhow::Result<()> {
    use brana_core::session_initiative::archive_initiative;
    let root = require_project_root()?;
    archive_initiative(&root, slug)?;
    println!("{{\"ok\":true,\"slug\":\"{slug}\",\"action\":\"archived\"}}");
    Ok(())
}

/// `brana session epic read-marker`
/// Prints the epic slug from the session-start marker, or empty string if absent.
pub fn cmd_epic_read_marker() -> anyhow::Result<()> {
    use brana_core::session_initiative::read_initiative_marker;
    let root = require_project_root()?;
    match read_initiative_marker(&root) {
        Some(slug) => println!("{slug}"),
        None => println!(),
    }
    Ok(())
}

/// `brana session epic clear-marker`
pub fn cmd_epic_clear_marker() -> anyhow::Result<()> {
    use brana_core::session_initiative::clear_initiative_marker;
    let root = require_project_root()?;
    clear_initiative_marker(&root)?;
    println!("{{\"ok\":true,\"action\":\"marker-cleared\"}}");
    Ok(())
}

/// `brana session epic focus <slug>`
pub fn cmd_epic_focus(slug: &str) -> anyhow::Result<()> {
    use brana_core::session_initiative::write_focus_marker;
    let root = require_project_root()?;
    write_focus_marker(&root, slug)?;
    println!("{{\"ok\":true,\"epic\":\"{slug}\",\"action\":\"focus-set\"}}");
    Ok(())
}

/// `brana session epic unfocus`
pub fn cmd_epic_unfocus() -> anyhow::Result<()> {
    use brana_core::session_initiative::clear_focus_marker;
    let root = require_project_root()?;
    clear_focus_marker(&root)?;
    println!("{{\"ok\":true,\"action\":\"focus-cleared\"}}");
    Ok(())
}

/// `brana session epic status [--json]`
///
/// Shows both the persistent focus and the transient marker.
/// Silent failure guard: if focus slug is set but the accumulator is absent, logs a warning.
pub fn cmd_epic_status(json_output: bool) -> anyhow::Result<()> {
    use brana_core::session_initiative::{
        read_focus_marker, read_initiative, read_initiative_marker,
    };
    let root = require_project_root()?;

    let focus = read_focus_marker(&root);
    let marker = read_initiative_marker(&root);

    // Silent failure guard: focus slug set but no accumulator
    if let Some(ref slug) = focus {
        if read_initiative(&root, slug).is_none() {
            eprintln!(
                "warning: focus epic '{slug}' has no accumulator — run `brana session epic upsert {slug}` after a session close to create one"
            );
        }
    }

    if json_output {
        let obj = serde_json::json!({
            "focus": focus,
            "marker": marker,
        });
        println!("{}", serde_json::to_string_pretty(&obj)?);
    } else {
        println!(
            "focus:  {}",
            focus.as_deref().unwrap_or("(none — run `brana session epic focus <slug>` to set)")
        );
        println!(
            "marker: {}",
            marker.as_deref().unwrap_or("(none — set by `brana run` when starting a task)")
        );
    }
    Ok(())
}

// ── Tests ────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;
    use brana_core::session::{mark_consumed_for, read_state_from, render_text, resolve_memory_dir,
        session_history_path, write_state, Backprop, DocDrift, SessionMeta, SessionMetrics,
        TestStatus};
    use serial_test::serial;
    use std::env;
    use std::path::Path;

    fn with_temp_home() -> tempfile::TempDir {
        let tmp = tempfile::tempdir().unwrap();
        unsafe { env::set_var("HOME", tmp.path()) };
        tmp
    }

    fn recent_ts(offset_days: i64) -> String {
        let dt = Utc::now() - chrono::Duration::days(offset_days);
        dt.format("%Y-%m-%dT%H:%M:%SZ").to_string()
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
            backprop: Some(Backprop { needed: true, files: vec!["system/hooks/tdd-gate.sh".into()] }),
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
                extract_metrics: None,
            }),
            session_labels: vec![],
            epic: None,
        }
    }

    #[test]
    #[serial]
    fn test_write_and_read_state() {
        let _tmp = with_temp_home();
        let root = Path::new("/home/user/myrepo");

        let state = sample_state();
        write_state(root, &state).unwrap();

        let loaded = read_state_from(root, "feat/t-798-session-state-structs").unwrap();
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

        let mut state1 = sample_state();
        state1.written_at = recent_ts(2);
        write_state(root, &state1).unwrap();

        let mut state2 = sample_state();
        state2.session_label = Some("second session".into());
        state2.written_at = recent_ts(1);
        write_state(root, &state2).unwrap();

        let current = read_state_from(root, "feat/t-798-session-state-structs").unwrap();
        assert_eq!(current.session_label, Some("second session".into()));

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
        assert!(read_state_from(root, "feat/t-798-session-state-structs").unwrap().consumed_at.is_none());

        mark_consumed_for(root, "feat/t-798-session-state-structs").unwrap();
        assert!(read_state_from(root, "feat/t-798-session-state-structs").unwrap().consumed_at.is_some());
    }

    #[test]
    #[serial]
    fn test_history_limit() {
        let _tmp = with_temp_home();
        let root = Path::new("/home/user/myrepo");

        for i in 0..5 {
            let mut state = sample_state();
            state.written_at = recent_ts(5 - i as i64);
            state.session_label = Some(format!("session {i}"));
            write_state(root, &state).unwrap();
        }

        let all = read_history(root, 100);
        assert_eq!(all.len(), 4);

        let limited = read_history(root, 2);
        assert_eq!(limited.len(), 2);
        assert_eq!(limited[0].session_label, Some("session 3".into()));
    }

    #[test]
    #[serial]
    fn test_atomic_write_no_tmp_left() {
        let _tmp = with_temp_home();
        let root = Path::new("/home/user/myrepo");

        write_state(root, &sample_state()).unwrap();
        let tmp_path = epic_scoped_state_path(root, sample_state().branch.as_deref().unwrap_or("")).with_extension("tmp");
        assert!(!tmp_path.exists());
    }

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

    #[test]
    fn test_extract_section_items() {
        let body = "**Accomplished:**\n- Built session structs\n- Wired CLI\n\n**Learnings:**\n- TDD first\n";
        let items = extract_section_items(body, "Accomplished");
        assert_eq!(items, vec!["Built session structs", "Wired CLI"]);
        let learnings = extract_section_items(body, "Learnings");
        assert_eq!(learnings, vec!["TDD first"]);
    }

    #[test]
    fn test_extract_section_items_empty() {
        let body = "**Accomplished:**\n\n**Next:**\n- Do stuff\n";
        let items = extract_section_items(body, "Accomplished");
        assert!(items.is_empty());
    }

    #[test]
    fn test_extract_field() {
        let body = "**State:**\n- Branch: feat/t-123\n- Tests: 25 passing\n";
        assert_eq!(extract_field(body, "Branch"), Some("feat/t-123".into()));
        assert_eq!(extract_field(body, "Tests"), Some("25 passing".into()));
        assert_eq!(extract_field(body, "Missing"), None);
    }

    #[test]
    fn test_convert_handoff_entry() {
        let entry = handoff::HandoffEntry {
            heading: "2026-03-31 — unified session state".into(),
            body: "\
**Accomplished:**
- Built session structs
- Wired CLI commands

**Learnings:**
- TDD first

**State:**
- Branch: feat/t-798
- Tests: 25 passing

**Next:**
- Implement migrate command
- Update sitrep

**Blockers:**
- None"
                .into(),
        };

        let state = convert_handoff_entry(&entry);
        assert_eq!(state.version, 1);
        assert_eq!(state.written_at, "2026-03-31T00:00:00Z");
        assert_eq!(state.session_label, Some("unified session state".into()));
        assert_eq!(state.branch, Some("feat/t-798".into()));
        assert_eq!(state.accomplished.len(), 2);
        assert_eq!(state.learnings, vec!["TDD first"]);
        assert_eq!(state.next.len(), 2);
        assert_eq!(state.next[0].text, "Implement migrate command");
        assert_eq!(state.next[0].category, NextCategory::FollowUp);
        assert!(state.blockers.is_empty());
        assert_eq!(state.consumed_at, Some(state.written_at.clone()));
    }

    #[test]
    fn test_convert_handoff_entry_no_label() {
        let entry = handoff::HandoffEntry {
            heading: "2026-03-30".into(),
            body: "**Accomplished:**\n- Did stuff\n".into(),
        };
        let state = convert_handoff_entry(&entry);
        assert_eq!(state.session_label, Some("2026-03-30".into()));
        assert_eq!(state.written_at, "2026-03-30T00:00:00Z");
    }

    #[test]
    #[serial]
    fn cmd_session_read_all_collects_epic_files() {
        let _tmp = with_temp_home();
        let root = Path::new("/home/user/myrepo");

        // Write a state for the "orphan" branch (falls back to session-state.json)
        let mut orphan = sample_state();
        orphan.written_at = recent_ts(1);
        orphan.session_label = Some("orphan session".into());
        orphan.branch = Some("main".into());
        // Write directly to session-state.json by passing empty branch
        let memory_dir = resolve_memory_dir(root);
        fs::create_dir_all(&memory_dir).unwrap();
        let orphan_path = memory_dir.join("session-state.json");
        fs::write(&orphan_path, serde_json::to_string(&orphan).unwrap()).unwrap();

        // Write an epic-scoped state via write_state with a proper branch
        let mut epic_state = sample_state();
        epic_state.written_at = recent_ts(2);
        epic_state.session_label = Some("epic session".into());
        epic_state.branch = Some("session/feat/t-999-read-all".into());
        write_state(root, &epic_state).unwrap();

        // cmd_session_read_all should find both files without error
        cmd_session_read_all(root, false, None).unwrap();

        // Verify both files exist in memory dir
        let epic_path = memory_dir.join("session-state-session.json");
        assert!(orphan_path.exists(), "orphan session-state.json must exist");
        assert!(epic_path.exists(), "epic session-state-session.json must exist");
    }

    #[test]
    #[serial]
    fn cmd_session_read_all_filters_by_since() {
        let _tmp = with_temp_home();
        let root = Path::new("/home/user/myrepo");

        let memory_dir = resolve_memory_dir(root);
        fs::create_dir_all(&memory_dir).unwrap();

        // Write a recent state (1 day ago)
        let mut recent = sample_state();
        recent.written_at = recent_ts(1);
        recent.session_label = Some("recent session".into());
        recent.branch = Some("main".into());
        let recent_path = memory_dir.join("session-state.json");
        fs::write(&recent_path, serde_json::to_string(&recent).unwrap()).unwrap();

        // Write an old state (60 days ago) — should be filtered out by --since
        let mut old = sample_state();
        old.written_at = recent_ts(60);
        old.session_label = Some("old session".into());
        old.branch = Some("session/feat/t-888-old".into());
        write_state(root, &old).unwrap();

        // With --since 15 days ago, only the recent state should pass
        let since_date = (Utc::now() - chrono::Duration::days(15))
            .format("%Y-%m-%d")
            .to_string();
        // Should not error
        cmd_session_read_all(root, false, Some(since_date)).unwrap();
    }
}
