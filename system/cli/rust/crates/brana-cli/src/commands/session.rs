//! brana session — CLI commands for session state management.
//!
//! All data types and I/O logic live in brana-core::session.
//! This module provides CLI command handlers and one-time migration from
//! the legacy session-handoff.md format.

use crate::commands::handoff;
use anyhow::{Context, Result};
pub use brana_core::session::mark_consumed;
use brana_core::session::{
    compute_insights, current_branch, read_history, read_state, render_text,
    session_history_path, session_state_path, write_state, Blocker, NextCategory, NextItem,
    SessionState,
};
use chrono::Utc;
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

    println!(
        "{{\"ok\":true,\"path\":\"{}\"}}",
        session_state_path(&root).display()
    );
    Ok(())
}

/// `brana session read [--json]`
pub fn cmd_session_read(json_output: bool) -> anyhow::Result<()> {
    let root = require_project_root()?;

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
    println!("{}", session_state_path(&root).display());
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
        initiative: None,
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

// ── Initiative accumulator commands ─────────────────────────────────────

/// `brana session initiative upsert <slug> [--completed t-1,t-2]`
pub fn cmd_initiative_upsert(slug: &str, completed_csv: &str) -> anyhow::Result<()> {
    use brana_core::session_initiative::upsert_initiative;
    let root = require_project_root()?;
    let state = read_state(&root)
        .ok_or_else(|| anyhow::anyhow!("No session state found — run `brana session write` first"))?;
    let completed: Vec<String> = completed_csv
        .split(',')
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty())
        .collect();
    upsert_initiative(&root, slug, &state, &completed)?;
    println!("{{\"ok\":true,\"slug\":\"{slug}\"}}");
    Ok(())
}

/// `brana session initiative read <slug> [--json]`
pub fn cmd_initiative_read(slug: &str, json_output: bool) -> anyhow::Result<()> {
    use brana_core::session_initiative::read_initiative;
    let root = require_project_root()?;
    let acc = read_initiative(&root, slug)
        .ok_or_else(|| anyhow::anyhow!("No initiative accumulator found for '{slug}'"))?;
    if json_output {
        println!("{}", serde_json::to_string_pretty(&acc)?);
    } else {
        println!("Initiative: {}", acc.slug);
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

/// `brana session initiative archive <slug>`
pub fn cmd_initiative_archive(slug: &str) -> anyhow::Result<()> {
    use brana_core::session_initiative::archive_initiative;
    let root = require_project_root()?;
    archive_initiative(&root, slug)?;
    println!("{{\"ok\":true,\"slug\":\"{slug}\",\"action\":\"archived\"}}");
    Ok(())
}

// ── Tests ────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;
    use brana_core::session::{read_state, render_text, session_history_path, session_state_path,
        write_state, Backprop, DocDrift, SessionMeta, SessionMetrics, TestStatus};
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
            }),
        }
    }

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

        let mut state1 = sample_state();
        state1.written_at = recent_ts(2);
        write_state(root, &state1).unwrap();

        let mut state2 = sample_state();
        state2.session_label = Some("second session".into());
        state2.written_at = recent_ts(1);
        write_state(root, &state2).unwrap();

        let current = read_state(root).unwrap();
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
        assert!(read_state(root).unwrap().consumed_at.is_none());

        mark_consumed(root).unwrap();
        assert!(read_state(root).unwrap().consumed_at.is_some());
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
        let tmp_path = session_state_path(root).with_extension("tmp");
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
}
