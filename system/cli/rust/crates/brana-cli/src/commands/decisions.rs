//! `brana decisions` — append-only JSONL decision log.
//!
//! State directory: system/state/decisions/
//! Each session writes to a single file: {date}-{session_id}.jsonl
//! Ported from system/scripts/decisions.py.

use anyhow::{bail, Context, Result};
use chrono::{NaiveDate, Utc};
use serde_json::{json, Value};
use std::fs::{self, OpenOptions};
use std::io::{BufRead, BufReader, Write};
use std::path::PathBuf;

use crate::cli::DecisionsCmd;
use crate::util::find_project_root;

const VALID_TYPES: &[&str] = &["decision", "finding", "concern", "action", "error", "cost"];

// ── State dir resolution ──────────────────────────────────────────────────────

fn state_dir() -> Result<PathBuf> {
    if let Ok(dir) = std::env::var("BRANA_DECISIONS_DIR") {
        return Ok(PathBuf::from(dir));
    }
    let root = find_project_root().context("not in a git repository")?;
    Ok(root.join("system/state/decisions"))
}

fn ensure_dirs(dir: &PathBuf) -> Result<()> {
    fs::create_dir_all(dir)?;
    fs::create_dir_all(dir.join("archive"))?;
    Ok(())
}

// ── Session file naming ───────────────────────────────────────────────────────

fn session_id() -> String {
    if let Ok(id) = std::env::var("BRANA_SESSION_ID") {
        return id;
    }
    let now = Utc::now();
    let pid = std::process::id();
    // Use low 16 bits of sub-second microseconds as the random component.
    let sub = now.timestamp_subsec_micros() & 0xFFFF;
    format!("{}-{}-{:04x}", now.format("%H%M%S"), pid, sub)
}

fn today_session_file() -> String {
    let today = Utc::now().format("%Y-%m-%d");
    format!("{}-{}.jsonl", today, session_id())
}

// ── Public entry point ────────────────────────────────────────────────────────

pub fn cmd_decisions(cmd: DecisionsCmd) -> Result<()> {
    match cmd {
        DecisionsCmd::Log { agent, entry_type, content, severity, refs, target } => {
            cmd_log(&agent, &entry_type, &content, severity.as_deref(), refs.as_deref(), target.as_deref())
        }
        DecisionsCmd::Read { last, entry_type, agent, severity, json } => {
            cmd_read(last, entry_type.as_deref(), agent.as_deref(), severity.as_deref(), json)
        }
        DecisionsCmd::Archive { days, dry_run } => cmd_archive(days, dry_run),
    }
}

// ── log ───────────────────────────────────────────────────────────────────────

fn cmd_log(
    agent: &str,
    entry_type: &str,
    content: &str,
    severity: Option<&str>,
    refs: Option<&str>,
    target: Option<&str>,
) -> Result<()> {
    if !VALID_TYPES.contains(&entry_type) {
        bail!(
            "invalid type '{}'. Must be one of: {}",
            entry_type,
            VALID_TYPES.join(", ")
        );
    }

    let dir = state_dir()?;
    ensure_dirs(&dir)?;

    let mut entry = json!({
        "ts": Utc::now().to_rfc3339(),
        "agent": agent,
        "type": entry_type,
        "content": content,
    });

    if let Some(sev) = severity {
        entry["severity"] = Value::String(sev.to_uppercase());
    }
    if let Some(refs_str) = refs {
        let ref_list: Vec<&str> = refs_str.split(',').map(str::trim).collect();
        entry["refs"] = Value::Array(ref_list.iter().map(|r| Value::String(r.to_string())).collect());
    }
    if let Some(tgt) = target {
        entry["target"] = Value::String(tgt.to_string());
    }

    let filepath = dir.join(today_session_file());
    let mut file = OpenOptions::new().create(true).append(true).open(&filepath)
        .with_context(|| format!("could not open {}", filepath.display()))?;
    writeln!(file, "{}", entry)?;

    Ok(())
}

// ── read ──────────────────────────────────────────────────────────────────────

fn cmd_read(
    last: Option<usize>,
    entry_type: Option<&str>,
    agent: Option<&str>,
    severity: Option<&str>,
    as_json: bool,
) -> Result<()> {
    let dir = state_dir()?;
    ensure_dirs(&dir)?;

    let mut entries: Vec<Value> = Vec::new();

    let mut paths: Vec<_> = fs::read_dir(&dir)?
        .filter_map(|e| e.ok())
        .map(|e| e.path())
        .filter(|p| {
            p.parent() == Some(dir.as_path())
                && p.extension().map(|e| e == "jsonl").unwrap_or(false)
        })
        .collect();
    paths.sort();

    for path in &paths {
        let file = fs::File::open(path)?;
        for line in BufReader::new(file).lines() {
            let line = line?;
            let trimmed = line.trim();
            if trimmed.is_empty() {
                continue;
            }
            if let Ok(v) = serde_json::from_str::<Value>(trimmed) {
                entries.push(v);
            }
        }
    }

    // Sort by timestamp
    entries.sort_by(|a, b| {
        let ts_a = a.get("ts").and_then(Value::as_str).unwrap_or("");
        let ts_b = b.get("ts").and_then(Value::as_str).unwrap_or("");
        ts_a.cmp(ts_b)
    });

    // Filters
    if let Some(t) = entry_type {
        entries.retain(|e| e.get("type").and_then(Value::as_str) == Some(t));
    }
    if let Some(a) = agent {
        entries.retain(|e| e.get("agent").and_then(Value::as_str) == Some(a));
    }
    if let Some(s) = severity {
        let upper = s.to_uppercase();
        entries.retain(|e| e.get("severity").and_then(Value::as_str) == Some(upper.as_str()));
    }

    // Last N
    if let Some(n) = last {
        let len = entries.len();
        if n < len {
            entries = entries.into_iter().skip(len - n).collect();
        }
    }

    // Output
    for e in &entries {
        if as_json {
            println!("{}", e);
        } else {
            let ts = e.get("ts").and_then(Value::as_str).unwrap_or("");
            let ts_short = ts.get(..16).unwrap_or(ts);
            let agent_str = e.get("agent").and_then(Value::as_str).unwrap_or("?");
            let type_str = e.get("type").and_then(Value::as_str).unwrap_or("?");
            let content_str = e.get("content").and_then(Value::as_str).unwrap_or("");
            let sev_prefix = if let Some(sev) = e.get("severity").and_then(Value::as_str) {
                format!("[{}] ", sev)
            } else {
                String::new()
            };
            println!("[{}] {}/{}: {}{}", ts_short, agent_str, type_str, sev_prefix, content_str);
        }
    }

    Ok(())
}

// ── archive ───────────────────────────────────────────────────────────────────

fn cmd_archive(days: u64, dry_run: bool) -> Result<()> {
    let dir = state_dir()?;
    ensure_dirs(&dir)?;

    let archive_dir = dir.join("archive");
    let today = Utc::now().date_naive();
    let cutoff = today - chrono::Duration::days(days as i64);

    let mut paths: Vec<_> = fs::read_dir(&dir)?
        .filter_map(|e| e.ok())
        .map(|e| e.path())
        .filter(|p| {
            p.parent() == Some(dir.as_path())
                && p.extension().map(|e| e == "jsonl").unwrap_or(false)
        })
        .collect();
    paths.sort();

    let mut count = 0usize;
    for path in &paths {
        let name = path.file_name().and_then(|n| n.to_str()).unwrap_or("");
        // Expect YYYY-MM-DD prefix
        if name.len() < 10 {
            continue;
        }
        let date_part = &name[..10];
        if let Ok(file_date) = NaiveDate::parse_from_str(date_part, "%Y-%m-%d") {
            if file_date <= cutoff {
                count += 1;
                if !dry_run {
                    fs::rename(path, archive_dir.join(path.file_name().unwrap()))?;
                }
            }
        }
    }

    if dry_run {
        println!("Would archive {} files", count);
    } else {
        println!("Archived {} files", count);
    }

    Ok(())
}

// ── Tests ─────────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;
    use serial_test::serial;
    use std::env;
    use tempfile::TempDir;

    fn with_state_dir(dir: &TempDir) -> PathBuf {
        let path = dir.path().join("decisions");
        // SAFETY: tests are single-threaded (serial_test or isolated processes)
        unsafe {
            env::set_var("BRANA_DECISIONS_DIR", &path);
            env::set_var("BRANA_SESSION_ID", "test-session");
        }
        path
    }

    fn cleanup() {
        // SAFETY: tests are single-threaded (serial_test or isolated processes)
        unsafe {
            env::remove_var("BRANA_DECISIONS_DIR");
            env::remove_var("BRANA_SESSION_ID");
        }
    }

    #[test]
    #[serial]
    fn test_log_creates_jsonl_entry() {
        let tmp = TempDir::new().unwrap();
        let dir = with_state_dir(&tmp);
        cmd_log("main", "decision", "chose Rust for CLI", None, None, None).unwrap();
        cleanup();

        let files: Vec<_> = fs::read_dir(&dir).unwrap()
            .filter_map(|e| e.ok())
            .filter(|e| e.path().extension().map(|x| x == "jsonl").unwrap_or(false))
            .collect();
        assert_eq!(files.len(), 1);

        let content = fs::read_to_string(files[0].path()).unwrap();
        let entry: Value = serde_json::from_str(content.trim()).unwrap();
        assert_eq!(entry["agent"], "main");
        assert_eq!(entry["type"], "decision");
        assert_eq!(entry["content"], "chose Rust for CLI");
        assert!(entry.get("ts").is_some());
    }

    #[test]
    #[serial]
    fn test_log_with_severity_and_refs() {
        let tmp = TempDir::new().unwrap();
        let dir = with_state_dir(&tmp);
        cmd_log("checker", "finding", "dependency outdated", Some("HIGH"), Some("t-001,t-002"), None).unwrap();
        cleanup();

        let files: Vec<_> = fs::read_dir(&dir).unwrap()
            .filter_map(|e| e.ok())
            .filter(|e| e.path().extension().map(|x| x == "jsonl").unwrap_or(false))
            .collect();
        let content = fs::read_to_string(files[0].path()).unwrap();
        let entry: Value = serde_json::from_str(content.trim()).unwrap();
        assert_eq!(entry["severity"], "HIGH");
        assert_eq!(entry["refs"], json!(["t-001", "t-002"]));
    }

    #[test]
    #[serial]
    fn test_log_invalid_type_returns_error() {
        let tmp = TempDir::new().unwrap();
        with_state_dir(&tmp);
        let result = cmd_log("main", "bogus", "content", None, None, None);
        cleanup();
        assert!(result.is_err());
        assert!(result.unwrap_err().to_string().contains("invalid type"));
    }

    #[test]
    #[serial]
    fn test_read_all_entries() {
        let tmp = TempDir::new().unwrap();
        with_state_dir(&tmp);
        cmd_log("main", "decision", "entry one", None, None, None).unwrap();
        cmd_log("agent", "finding", "entry two", None, None, None).unwrap();

        // Capture stdout via a buffer approach — just check no error for now
        let result = cmd_read(None, None, None, None, false);
        cleanup();
        assert!(result.is_ok());
    }

    #[test]
    #[serial]
    fn test_read_filter_by_type() {
        let tmp = TempDir::new().unwrap();
        let dir = with_state_dir(&tmp);
        cmd_log("main", "decision", "keep this", None, None, None).unwrap();
        cmd_log("main", "finding", "drop this", None, None, None).unwrap();

        // Read state directly to verify filtering logic.
        // dir IS the state dir (set by with_state_dir). Find the session file:
        let files: Vec<_> = fs::read_dir(&dir).unwrap()
            .filter_map(|e| e.ok())
            .filter(|e| e.path().extension().map(|x| x == "jsonl").unwrap_or(false))
            .collect();
        let content = fs::read_to_string(files[0].path()).unwrap();
        let entries: Vec<Value> = content.lines()
            .filter(|l| !l.trim().is_empty())
            .map(|l| serde_json::from_str(l).unwrap())
            .collect();

        let decisions: Vec<_> = entries.iter().filter(|e| e["type"] == "decision").collect();
        let findings: Vec<_> = entries.iter().filter(|e| e["type"] == "finding").collect();
        assert_eq!(decisions.len(), 1);
        assert_eq!(findings.len(), 1);
        assert_eq!(decisions[0]["content"], "keep this");
        cleanup();
    }

    #[test]
    #[serial]
    fn test_read_last_n() {
        let tmp = TempDir::new().unwrap();
        let dir = with_state_dir(&tmp);
        for i in 0..5 {
            cmd_log("main", "action", &format!("entry {}", i), None, None, None).unwrap();
        }

        let files: Vec<_> = fs::read_dir(&dir).unwrap()
            .filter_map(|e| e.ok())
            .filter(|e| e.path().extension().map(|x| x == "jsonl").unwrap_or(false))
            .collect();
        let content = fs::read_to_string(files[0].path()).unwrap();
        let all_entries: Vec<Value> = content.lines()
            .filter(|l| !l.trim().is_empty())
            .map(|l| serde_json::from_str(l).unwrap())
            .collect();

        // Verify 5 were written
        assert_eq!(all_entries.len(), 5);

        // cmd_read with last=2 should not error
        let result = cmd_read(Some(2), None, None, None, false);
        cleanup();
        assert!(result.is_ok());
    }

    #[test]
    #[serial]
    fn test_read_json_flag_no_error() {
        let tmp = TempDir::new().unwrap();
        with_state_dir(&tmp);
        cmd_log("main", "decision", "test", None, None, None).unwrap();
        let result = cmd_read(None, None, None, None, true);
        cleanup();
        assert!(result.is_ok());
    }

    #[test]
    #[serial]
    fn test_archive_moves_old_files() {
        let tmp = TempDir::new().unwrap();
        let dir = with_state_dir(&tmp);
        ensure_dirs(&dir).unwrap();

        // Create a fake old file (40 days ago)
        let old_date = (Utc::now() - chrono::Duration::days(40)).format("%Y-%m-%d");
        let old_file = dir.join(format!("{}-old-session.jsonl", old_date));
        fs::write(&old_file, "{\"ts\":\"old\"}\n").unwrap();

        // Create a recent file (today)
        let new_file = dir.join(format!("{}-new-session.jsonl", Utc::now().format("%Y-%m-%d")));
        fs::write(&new_file, "{\"ts\":\"new\"}\n").unwrap();

        cmd_archive(30, false).unwrap();
        cleanup();

        // Old file should be moved to archive/
        assert!(!old_file.exists(), "old file should be archived");
        assert!(dir.join("archive").join(old_file.file_name().unwrap()).exists());
        // New file should remain
        assert!(new_file.exists(), "new file should stay");
    }

    #[test]
    #[serial]
    fn test_archive_dry_run_does_not_move() {
        let tmp = TempDir::new().unwrap();
        let dir = with_state_dir(&tmp);
        ensure_dirs(&dir).unwrap();

        let old_date = (Utc::now() - chrono::Duration::days(40)).format("%Y-%m-%d");
        let old_file = dir.join(format!("{}-dry-test.jsonl", old_date));
        fs::write(&old_file, "{\"ts\":\"x\"}\n").unwrap();

        cmd_archive(30, true).unwrap();
        cleanup();

        // File should still exist — dry run doesn't move
        assert!(old_file.exists(), "dry-run should not move file");
    }
}
