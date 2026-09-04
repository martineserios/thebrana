//! LEARN worker core drain loop (v3 wave 2 — design: t-2404, implementation: t-2405).
//!
//! Ports `system/cron/close-extraction.sh`'s per-entry extraction loop into
//! Rust, against the real close-queue store (`crate::queue`) and reminder
//! store (`crate::remind`) — never a new store. Engine chain: agy-first,
//! Claude fallback on failure, per
//! `docs/architecture/features/learn-worker-compute-chain.md`.
//!
//! Out of scope for this file (later wave-2 tasks build on top of it):
//! the per-run token ceiling and cooperative ceiling-stop (t-2406), the
//! curation gate — dedup/decay before `write_reminder` (t-2407), the L3
//! propagation pass (stays in the shell script; not ported here), and the
//! Tier B scoped-mutation observe-invariant test (t-2408, though this file's
//! writes already satisfy that invariant's substance: no task/git/memory
//! mutation, only reminder-store + queue-bookkeeping writes that gate
//! nothing until a human reviews `brana remind list`).
//!
//! One behavioral difference from the shell script by design: when both agy
//! and the Claude fallback fail for an entry, this loop `fail_entry`s that
//! one entry and continues to the next — it never `skip_entry`+`break`s the
//! whole run. The shell script's skip-and-defer path (t-2409's removal
//! target) assumed a double-engine failure predicts every remaining entry
//! will fail identically; this implementation makes no such assumption.

use crate::queue::{self, Entry};
use crate::remind::{self, NewReminder, Priority};
use std::collections::HashSet;
use std::path::Path;

/// Learnings above this confidence are kept (mirrors close-extraction.txt's
/// prompt contract: "entries below 0.5 are discarded").
pub const MIN_CONFIDENCE: f64 = 0.5;
/// Per-entry cap on routed learnings (matches close-extraction.sh).
pub const MAX_LEARNINGS_PER_ENTRY: usize = 3;

/// One validated learning extracted from a diff.
#[derive(Debug, Clone, PartialEq)]
pub struct Learning {
    /// One of "errata" | "pattern" | "field-note".
    pub kind: String,
    /// One of "SMALL" | "LARGE" (normalized uppercase).
    pub size: String,
    pub title: String,
    pub body: String,
    pub confidence: f64,
}

/// Outcome of one `drain_queue` call.
#[derive(Debug, Default, Clone, PartialEq)]
pub struct DrainReport {
    pub processed: usize,
    pub failed: usize,
}

/// Validate an engine's raw extraction output against the contract in
/// `system/cron/prompts/close-extraction.txt`: `{"learnings": [...]}`, each
/// item `type` in {errata, pattern, field-note}, `size` in {SMALL, LARGE}
/// (case-insensitive on input, normalized to uppercase), non-empty `title`.
/// Confidence filter + per-entry cap apply AFTER full contract validation —
/// a malformed low-confidence item still fails the whole output, matching
/// close-extraction.sh's python validator ordering exactly.
pub fn parse_learnings(raw: &serde_json::Value) -> Result<Vec<Learning>, String> {
    let arr = raw
        .get("learnings")
        .and_then(|v| v.as_array())
        .ok_or_else(|| "missing or non-array \"learnings\" field".to_string())?;

    let mut out = Vec::with_capacity(arr.len());
    for item in arr {
        let kind = item
            .get("type")
            .and_then(|v| v.as_str())
            .unwrap_or("")
            .to_string();
        if !matches!(kind.as_str(), "errata" | "pattern" | "field-note") {
            return Err(format!("bad type: {kind:?}"));
        }

        // Tolerate agy returning lowercase ("small"/"large") — normalize to
        // uppercase before validating, matching close-extraction.sh's python
        // validator (`l["size"].upper()`).
        let size = item
            .get("size")
            .and_then(|v| v.as_str())
            .unwrap_or("SMALL")
            .to_uppercase();
        if !matches!(size.as_str(), "SMALL" | "LARGE") {
            return Err(format!("bad size: {size:?}"));
        }

        let title = item
            .get("title")
            .and_then(|v| v.as_str())
            .unwrap_or("")
            .trim()
            .to_string();
        if title.is_empty() {
            return Err("empty title".to_string());
        }

        let body = item
            .get("body")
            .and_then(|v| v.as_str())
            .unwrap_or("")
            .to_string();
        let confidence = item.get("confidence").and_then(|v| v.as_f64()).unwrap_or(1.0);

        out.push(Learning {
            kind,
            size,
            title,
            body,
            confidence,
        });
    }

    // Low-confidence filter + per-entry cap run AFTER full contract
    // validation above — a malformed low-confidence item still fails the
    // whole output, it is never silently dropped instead of erroring.
    out.retain(|l| l.confidence >= MIN_CONFIDENCE);
    out.truncate(MAX_LEARNINGS_PER_ENTRY);
    Ok(out)
}

/// Build the extraction prompt for one queue entry's diff. `truncated_note`,
/// when present, is appended to the intro sentence (matches
/// close-extraction.sh's single-truncation-note rule: the argv-cap note
/// subsumes the snapshot_truncated note, never both).
pub fn build_prompt(
    project: &str,
    branch: &str,
    git_range: &str,
    diff: &str,
    contract: &str,
    truncated_note: Option<&str>,
) -> String {
    let mut prompt = format!(
        "You are extracting learnings from a coding session diff for project '{project}' (branch {branch}, commits {git_range})."
    );
    if let Some(note) = truncated_note {
        prompt.push(' ');
        prompt.push_str(note);
    }
    prompt.push('\n');
    prompt.push_str(contract);
    prompt.push_str("\n\n--- DIFF ---\n");
    prompt.push_str(diff);
    prompt
}

/// Drain every eligible unprocessed close-queue entry once: extract via
/// `agy`, falling back to `claude_fallback` on failure; validate the
/// learnings contract; route each learning to the reminder store; append
/// the daily summary; mark the entry processed or failed. Entries with
/// `retry_count >= max_retries` are skipped (left for a human, matching
/// close-extraction.sh's `MAX_RETRIES` gate). `agy`/`claude_fallback` are
/// injected so this loop is unit-testable without shelling out — production
/// callers wire in `knowledge_pipeline::call_gemini_json` /
/// `call_claude_json`.
#[allow(clippy::too_many_arguments)]
pub fn drain_queue(
    queue_path: &Path,
    reminder_path: &Path,
    summary_path: &Path,
    contract: &str,
    max_retries: u64,
    max_diff_bytes: usize,
    mut agy: impl FnMut(&str) -> Result<serde_json::Value, String>,
    mut claude_fallback: impl FnMut(&str) -> Result<serde_json::Value, String>,
) -> Result<DrainReport, String> {
    let mut report = DrainReport::default();
    // Re-read the queue per iteration via the store API (ADR-052 §2 — no
    // cached shell-variable view across mutations); track ids already
    // attempted this run so a just-failed entry isn't retried in the same
    // pass (matches close-extraction.sh's `ATTEMPTED` set).
    let mut attempted: HashSet<String> = HashSet::new();

    loop {
        let entries = queue::list(queue_path, true)?;
        let next = entries
            .into_iter()
            .find(|e| e.retry_count < max_retries && !attempted.contains(&e.id));
        let Some(entry) = next else { break };
        attempted.insert(entry.id.clone());

        if !Path::new(&entry.snapshot_path).is_file() {
            queue::mark_failed(
                queue_path,
                &entry.id,
                &format!("snapshot-missing: {}", entry.snapshot_path),
            )?;
            report.failed += 1;
            continue;
        }

        let raw_diff = std::fs::read_to_string(&entry.snapshot_path)
            .map_err(|e| format!("reading snapshot {}: {e}", entry.snapshot_path))?;

        // Char-count truncation, not byte-slicing: safe against splitting a
        // UTF-8 boundary (raw `head -c` in the shell script risks that; the
        // guard here trades exactness for never panicking on non-ASCII diff
        // content). One truncation note only, matching the shell script's
        // rule: the argv-cap note subsumes the snapshot_truncated note.
        let (diff, note) = if raw_diff.len() > max_diff_bytes {
            (
                raw_diff.chars().take(max_diff_bytes).collect::<String>(),
                Some(
                    "Only the first bytes of the diff are included — extract from what is present, do not flag the truncation."
                        .to_string(),
                ),
            )
        } else if entry.snapshot_truncated {
            (
                raw_diff,
                Some(
                    "The diff was truncated — extract from what is present, do not flag the truncation."
                        .to_string(),
                ),
            )
        } else {
            (raw_diff, None)
        };

        let prompt = build_prompt(
            &entry.project,
            &entry.branch,
            &entry.git_range,
            &diff,
            contract,
            note.as_deref(),
        );

        // Engine chain: agy-first, Claude fallback on failure. Both failing
        // fails THIS entry only (burns its retry budget) — it never stops
        // the run. See module doc: this is the behavioral change from the
        // shell script's skip-and-defer path (t-2409's removal target).
        let extraction = match agy(&prompt) {
            Ok(v) => v,
            Err(agy_err) => match claude_fallback(&prompt) {
                Ok(v) => v,
                Err(claude_err) => {
                    queue::mark_failed(
                        queue_path,
                        &entry.id,
                        &format!(
                            "quota-exhausted: agy failed ({agy_err}), claude fallback failed ({claude_err})"
                        ),
                    )?;
                    report.failed += 1;
                    continue;
                }
            },
        };

        let learnings = match parse_learnings(&extraction) {
            Ok(l) => l,
            Err(e) => {
                queue::mark_failed(queue_path, &entry.id, &format!("schema-invalid: {e}"))?;
                report.failed += 1;
                continue;
            }
        };

        for l in &learnings {
            let priority = if l.size == "LARGE" {
                Priority::High
            } else {
                Priority::Low
            };
            let slug = slugify(&l.title);
            remind::write_reminder(
                reminder_path,
                NewReminder {
                    text: format!("[{}/{}] {} — {}", l.kind, l.size, l.title, l.body),
                    priority: Some(priority),
                    dedup_key: Some(format!("extract:{}:{}:{}", entry.project, l.kind, slug)),
                    project: Some(entry.project.clone()),
                    tags: vec!["extraction".to_string(), l.kind.clone()],
                    ..Default::default()
                },
            )?;
        }

        append_daily_summary(summary_path, &entry, &learnings)?;

        // Summary path is the same for every entry this run — matches the
        // shell script's single rolling SUMMARY_FILE, appended, never
        // replaced (ADR-052, challenger M9).
        queue::mark_processed(queue_path, &entry.id, &summary_path.to_string_lossy())?;
        report.processed += 1;
    }

    Ok(report)
}

/// Lowercase, non-alnum -> `-`, collapsed, capped at 48 chars — mirrors
/// close-extraction.sh's `tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-'`.
fn slugify(title: &str) -> String {
    let mut out = String::new();
    let mut last_dash = false;
    for c in title.to_lowercase().chars() {
        if c.is_ascii_alphanumeric() {
            out.push(c);
            last_dash = false;
        } else if !last_dash {
            out.push('-');
            last_dash = true;
        }
    }
    out.trim_matches('-').chars().take(48).collect()
}

/// Append (never replace, ADR-052 challenger M9) one entry's section to the
/// rolling daily summary file, creating the parent directory if needed.
fn append_daily_summary(path: &Path, entry: &Entry, learnings: &[Learning]) -> Result<(), String> {
    use std::io::Write;

    let mut section = format!(
        "## {} {} ({}) — entry {}\n",
        entry.project, entry.branch, entry.git_range, entry.id
    );
    if learnings.is_empty() {
        section.push_str("- no notable learnings\n");
    } else {
        for l in learnings {
            section.push_str(&format!("- [{}/{}] {}: {}\n", l.kind, l.size, l.title, l.body));
        }
    }
    section.push('\n');

    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent).map_err(|e| e.to_string())?;
    }
    let mut f = std::fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(path)
        .map_err(|e| format!("opening summary file {}: {e}", path.display()))?;
    f.write_all(section.as_bytes()).map_err(|e| e.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;
    use std::path::PathBuf;

    fn tmp_paths(dir: &tempfile::TempDir) -> (PathBuf, PathBuf, PathBuf) {
        (
            dir.path().join("close-queue.json"),
            dir.path().join("reminders.json"),
            dir.path().join("daily-summary.md"),
        )
    }

    fn seed_entry(queue_path: &Path, project: &str, branch: &str, range: &str, snap: &Path) -> Entry {
        std::fs::write(snap, "diff --git a/x b/x\n+fix\n").unwrap();
        queue::append(
            queue_path,
            queue::NewEntry {
                project: project.into(),
                branch: branch.into(),
                git_root: "/repo".into(),
                git_range: range.into(),
                snapshot_path: snap.to_string_lossy().into_owned(),
                commit_count: 1,
                ..Default::default()
            },
        )
        .unwrap()
        .entry
    }

    // ── parse_learnings ──────────────────────────────────────────────

    #[test]
    fn parse_learnings_accepts_valid_contract() {
        let raw = json!({"learnings": [
            {"type": "pattern", "size": "SMALL", "title": "use lock_sidecar for stores", "body": "...", "confidence": 0.9}
        ]});
        let out = parse_learnings(&raw).unwrap();
        assert_eq!(out.len(), 1);
        assert_eq!(out[0].kind, "pattern");
        assert_eq!(out[0].size, "SMALL");
        assert_eq!(out[0].title, "use lock_sidecar for stores");
    }

    #[test]
    fn parse_learnings_empty_array_is_valid() {
        let raw = json!({"learnings": []});
        assert_eq!(parse_learnings(&raw).unwrap().len(), 0);
    }

    #[test]
    fn parse_learnings_normalizes_lowercase_size() {
        let raw = json!({"learnings": [
            {"type": "errata", "size": "large", "title": "t", "body": "b", "confidence": 0.9}
        ]});
        assert_eq!(parse_learnings(&raw).unwrap()[0].size, "LARGE");
    }

    #[test]
    fn parse_learnings_defaults_missing_size_to_small() {
        let raw = json!({"learnings": [
            {"type": "errata", "title": "t", "body": "b", "confidence": 0.9}
        ]});
        assert_eq!(parse_learnings(&raw).unwrap()[0].size, "SMALL");
    }

    #[test]
    fn parse_learnings_rejects_bad_type() {
        let raw = json!({"learnings": [
            {"type": "not-a-real-type", "size": "SMALL", "title": "t", "body": "b", "confidence": 0.9}
        ]});
        assert!(parse_learnings(&raw).is_err());
    }

    #[test]
    fn parse_learnings_rejects_bad_size() {
        let raw = json!({"learnings": [
            {"type": "pattern", "size": "MEDIUM", "title": "t", "body": "b", "confidence": 0.9}
        ]});
        assert!(parse_learnings(&raw).is_err());
    }

    #[test]
    fn parse_learnings_rejects_empty_title() {
        let raw = json!({"learnings": [
            {"type": "pattern", "size": "SMALL", "title": "  ", "body": "b", "confidence": 0.9}
        ]});
        assert!(parse_learnings(&raw).is_err());
    }

    #[test]
    fn parse_learnings_rejects_missing_learnings_key() {
        let raw = json!({"not_learnings": []});
        assert!(parse_learnings(&raw).is_err());
    }

    #[test]
    fn parse_learnings_filters_low_confidence_after_validation() {
        // A malformed low-confidence item still fails the WHOLE output —
        // the filter runs after contract validation, not instead of it.
        let raw = json!({"learnings": [
            {"type": "bogus", "size": "SMALL", "title": "t", "body": "b", "confidence": 0.1}
        ]});
        assert!(parse_learnings(&raw).is_err());

        // A valid low-confidence item is silently dropped, not an error.
        let raw2 = json!({"learnings": [
            {"type": "pattern", "size": "SMALL", "title": "t", "body": "b", "confidence": 0.2}
        ]});
        assert_eq!(parse_learnings(&raw2).unwrap().len(), 0);
    }

    #[test]
    fn parse_learnings_caps_at_max_per_entry() {
        let items: Vec<_> = (0..5)
            .map(|i| json!({"type": "pattern", "size": "SMALL", "title": format!("t{i}"), "body": "b", "confidence": 0.9}))
            .collect();
        let raw = json!({"learnings": items});
        assert_eq!(parse_learnings(&raw).unwrap().len(), MAX_LEARNINGS_PER_ENTRY);
    }

    // ── build_prompt ─────────────────────────────────────────────────

    #[test]
    fn build_prompt_includes_project_branch_range_and_diff() {
        let p = build_prompt("thebrana", "feat/x", "a..b", "DIFFCONTENT", "CONTRACT", None);
        assert!(p.contains("thebrana"));
        assert!(p.contains("feat/x"));
        assert!(p.contains("a..b"));
        assert!(p.contains("DIFFCONTENT"));
        assert!(p.contains("CONTRACT"));
    }

    #[test]
    fn build_prompt_appends_truncation_note_when_present() {
        let p = build_prompt("p", "b", "r", "d", "c", Some("TRUNCATED-NOTE"));
        assert!(p.contains("TRUNCATED-NOTE"));
    }

    // ── drain_queue ──────────────────────────────────────────────────

    #[test]
    fn drain_queue_happy_path_processes_entry_and_writes_reminder() {
        let dir = tempfile::TempDir::new().unwrap();
        let (qp, rp, sp) = tmp_paths(&dir);
        let snap = dir.path().join("snap.diff");
        let entry = seed_entry(&qp, "thebrana", "feat/x", "a..b", &snap);

        let report = drain_queue(
            &qp,
            &rp,
            &sp,
            "CONTRACT",
            3,
            100_000,
            |_prompt| Ok(json!({"learnings": [
                {"type": "pattern", "size": "SMALL", "title": "found a thing", "body": "detail", "confidence": 0.9}
            ]})),
            |_prompt| panic!("claude fallback should not be called when agy succeeds"),
        )
        .unwrap();

        assert_eq!(report.processed, 1);
        assert_eq!(report.failed, 0);

        let entries = queue::list(&qp, false).unwrap();
        assert!(entries[0].processed);
        assert_eq!(entries[0].id, entry.id);

        let reminders = remind::list(&rp).unwrap();
        assert_eq!(reminders.len(), 1);
        assert!(reminders[0].text.contains("found a thing"));
        assert_eq!(reminders[0].project.as_deref(), Some("thebrana"));

        let summary = std::fs::read_to_string(&sp).unwrap();
        assert!(summary.contains("found a thing"));
    }

    #[test]
    fn drain_queue_falls_back_to_claude_on_agy_failure() {
        let dir = tempfile::TempDir::new().unwrap();
        let (qp, rp, sp) = tmp_paths(&dir);
        let snap = dir.path().join("snap.diff");
        seed_entry(&qp, "thebrana", "feat/x", "a..b", &snap);

        let report = drain_queue(
            &qp,
            &rp,
            &sp,
            "CONTRACT",
            3,
            100_000,
            |_prompt| Err("429 rate limited".to_string()),
            |_prompt| Ok(json!({"learnings": []})),
        )
        .unwrap();

        assert_eq!(report.processed, 1);
        assert_eq!(report.failed, 0);
    }

    #[test]
    fn drain_queue_fails_entry_not_whole_run_when_both_engines_fail() {
        // The behavioral core of what this file replaces (see module doc):
        // a double-engine failure on one entry must NOT stop the run.
        let dir = tempfile::TempDir::new().unwrap();
        let (qp, rp, sp) = tmp_paths(&dir);
        let snap1 = dir.path().join("snap1.diff");
        let snap2 = dir.path().join("snap2.diff");
        seed_entry(&qp, "thebrana", "feat/x", "a..b", &snap1);
        seed_entry(&qp, "thebrana", "feat/y", "c..d", &snap2);

        let mut calls = 0;
        let report = drain_queue(
            &qp,
            &rp,
            &sp,
            "CONTRACT",
            3,
            100_000,
            |_prompt| {
                calls += 1;
                if calls == 1 {
                    Err("429 rate limited".to_string())
                } else {
                    Ok(json!({"learnings": []}))
                }
            },
            |_prompt| Err("claude also failed".to_string()),
        )
        .unwrap();

        // Entry 1: agy fails, claude fallback fails too -> fail_entry, continue.
        // Entry 2: agy succeeds outright.
        assert_eq!(report.processed, 1);
        assert_eq!(report.failed, 1);

        let entries = queue::list(&qp, false).unwrap();
        let failed = entries.iter().find(|e| e.branch == "feat/x").unwrap();
        assert!(failed.failed);
        assert!(!failed.processed);
        assert!(failed.error.as_deref().unwrap().contains("quota-exhausted"));
    }

    #[test]
    fn drain_queue_fails_entry_on_missing_snapshot() {
        let dir = tempfile::TempDir::new().unwrap();
        let (qp, rp, sp) = tmp_paths(&dir);
        let missing = dir.path().join("does-not-exist.diff");
        queue::append(
            &qp,
            queue::NewEntry {
                project: "thebrana".into(),
                branch: "feat/x".into(),
                git_root: "/repo".into(),
                git_range: "a..b".into(),
                snapshot_path: missing.to_string_lossy().into_owned(),
                commit_count: 1,
                ..Default::default()
            },
        )
        .unwrap();

        let report = drain_queue(&qp, &rp, &sp, "CONTRACT", 3, 100_000, |_| unreachable!(), |_| unreachable!())
            .unwrap();

        assert_eq!(report.failed, 1);
        assert_eq!(report.processed, 0);
        let entries = queue::list(&qp, false).unwrap();
        assert!(entries[0].error.as_deref().unwrap().contains("snapshot-missing"));
    }

    #[test]
    fn drain_queue_fails_entry_on_schema_invalid_output() {
        let dir = tempfile::TempDir::new().unwrap();
        let (qp, rp, sp) = tmp_paths(&dir);
        let snap = dir.path().join("snap.diff");
        seed_entry(&qp, "thebrana", "feat/x", "a..b", &snap);

        let report = drain_queue(
            &qp,
            &rp,
            &sp,
            "CONTRACT",
            3,
            100_000,
            |_| Ok(json!({"not_learnings": []})),
            |_| unreachable!("agy succeeded, no fallback expected"),
        )
        .unwrap();

        assert_eq!(report.failed, 1);
        let entries = queue::list(&qp, false).unwrap();
        assert!(entries[0].error.as_deref().unwrap().contains("schema-invalid"));
    }

    #[test]
    fn drain_queue_skips_entries_past_max_retries() {
        let dir = tempfile::TempDir::new().unwrap();
        let (qp, rp, sp) = tmp_paths(&dir);
        let snap = dir.path().join("snap.diff");
        let entry = seed_entry(&qp, "thebrana", "feat/x", "a..b", &snap);
        queue::mark_failed(&qp, &entry.id, "e1").unwrap();
        queue::mark_failed(&qp, &entry.id, "e2").unwrap();
        queue::mark_failed(&qp, &entry.id, "e3").unwrap(); // retry_count == 3

        let report = drain_queue(&qp, &rp, &sp, "CONTRACT", 3, 100_000, |_| unreachable!(), |_| unreachable!())
            .unwrap();

        assert_eq!(report.processed, 0);
        assert_eq!(report.failed, 0); // never attempted — left for a human
    }

    #[test]
    fn drain_queue_processes_all_eligible_entries_in_one_call() {
        let dir = tempfile::TempDir::new().unwrap();
        let (qp, rp, sp) = tmp_paths(&dir);
        for i in 0..3 {
            let snap = dir.path().join(format!("snap{i}.diff"));
            seed_entry(&qp, "thebrana", &format!("feat/{i}"), &format!("r{i}"), &snap);
        }

        let report = drain_queue(
            &qp,
            &rp,
            &sp,
            "CONTRACT",
            3,
            100_000,
            |_| Ok(json!({"learnings": []})),
            |_| unreachable!(),
        )
        .unwrap();

        assert_eq!(report.processed, 3);
        assert_eq!(queue::list(&qp, true).unwrap().len(), 0); // none left unprocessed
    }
}
