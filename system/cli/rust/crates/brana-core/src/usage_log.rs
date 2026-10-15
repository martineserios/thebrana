//! The recall usage log (t-3517, ADR-099 §5-6): one append-only JSONL file per project,
//! `~/.claude/projects/<main-checkout>/brana/recall-usage.jsonl`, written only through this
//! module.
//!
//! Rows carry ids only: note names, types, ranks, flags, leg states, counts. No query text, no
//! gists, no note bodies, so the file cannot leak a note. The file is created mode 0600, lives in
//! a `brana/` subfolder (the transcript scanners read only the top level of the project folder)
//! and is never backed up or synced.
//!
//! Two row kinds:
//! - `offered`: a bundle was computed for a task (`shown` says whether the worker saw it);
//! - `outcome`: the worker said which offered notes it used or ignored. It names its offered row
//!   by id, and every ref must be one the offered row listed.

use crate::recall_bundle::Pointer;
use serde::Serialize;
use serde_json::{Value, json};
use std::collections::{BTreeMap, BTreeSet};
use std::io::Write;
use std::path::{Path, PathBuf};

pub const LOG_FILE: &str = "recall-usage.jsonl";
const ROW_VERSION: u64 = 1;

/// The log under the current project-folder encoding and under the legacy one (`/` only). Both
/// can exist on disk; writers use the first, readers read both.
pub fn log_paths(projects_dir: &Path, root: &Path) -> [PathBuf; 2] {
    let at = |name: String| projects_dir.join(name).join("brana").join(LOG_FILE);
    [at(crate::util::encode_project_dir(root)), at(crate::util::encode_project_dir_legacy(root))]
}

/// What an `offered` row records. Built from a bundle's fields, never from the query.
pub struct Offered<'a> {
    pub task: &'a str,
    pub shown: bool,
    pub fts: &'a str,
    pub vector: &'a str,
    pub elapsed_ms: u64,
    pub pointers: &'a [Pointer],
    /// The bundle's freshness block (counts and a state word, no text).
    pub freshness: Value,
    /// The Claude Code session file's stem (not a path), when it could be resolved.
    pub session: Option<&'a str>,
}

pub fn offered_row(o: &Offered, now: chrono::DateTime<chrono::Utc>) -> Value {
    json!({
        "v": ROW_VERSION,
        "kind": "offered",
        "id": crate::util::random_store_id("o"),
        "task": o.task,
        "ts": now.format("%Y-%m-%dT%H:%M:%SZ").to_string(),
        "shown": o.shown,
        "legs": {"fts": o.fts, "vector": o.vector},
        "elapsed_ms": o.elapsed_ms,
        "pointers": o.pointers.iter().map(|p| json!({
            "ref": p.ref_, "type": p.ptype, "rank": p.rank, "flags": p.flags,
        })).collect::<Vec<_>>(),
        "freshness": o.freshness,
        "session": o.session.map(safe_stem),
    })
}

/// A session-file stem reduced to `[A-Za-z0-9_-]`, so a stored stem can never name another path.
fn safe_stem(s: &str) -> String {
    s.chars().filter(|c| c.is_ascii_alphanumeric() || matches!(c, '_' | '-')).take(80).collect()
}

/// Append one row: lock, then a single `write_all` of the whole line. The file is created 0600
/// in a 0700 folder. Concurrent appenders each add one parseable line.
pub fn append(path: &Path, row: &Value) -> Result<(), String> {
    use std::os::unix::fs::{DirBuilderExt, OpenOptionsExt};
    if let Some(dir) = path.parent() {
        std::fs::DirBuilder::new()
            .recursive(true)
            .mode(0o700)
            .create(dir)
            .map_err(|e| format!("creating {}: {e}", dir.display()))?;
    }
    let _guard = crate::util::lock_sidecar(path)?;
    let mut line = serde_json::to_string(row).map_err(|e| e.to_string())?;
    line.push('\n');
    let mut f = std::fs::OpenOptions::new()
        .create(true)
        .append(true)
        .mode(0o600)
        .open(path)
        .map_err(|e| format!("opening {}: {e}", path.display()))?;
    f.write_all(line.as_bytes()).map_err(|e| format!("appending to {}: {e}", path.display()))
}

/// Rows read from the log files, oldest first (by `ts`, ties keep file order), plus the number
/// of lines that were not valid rows (skipped, never fatal).
pub struct Rows {
    pub rows: Vec<Value>,
    pub malformed: usize,
}

pub fn read_rows(paths: &[PathBuf]) -> Rows {
    let mut rows = Vec::new();
    let mut malformed = 0;
    // The two encodings coincide for a root without `_`: read that file once.
    let mut seen = BTreeSet::new();
    for p in paths.iter().filter(|p| seen.insert(p.as_path())) {
        let Ok(text) = std::fs::read_to_string(p) else { continue };
        for line in text.lines().filter(|l| !l.trim().is_empty()) {
            match serde_json::from_str::<Value>(line) {
                Ok(v) if v["kind"].is_string() && v["task"].is_string() => rows.push(v),
                _ => malformed += 1,
            }
        }
    }
    rows.sort_by(|a, b| a["ts"].as_str().cmp(&b["ts"].as_str()));
    Rows { rows, malformed }
}

fn is_offered(r: &Value) -> bool {
    r["kind"] == "offered"
}

fn resolved(rows: &[Value], offered_id: &str) -> bool {
    rows.iter().any(|r| r["kind"] == "outcome" && r["offered"] == offered_id)
}

/// The latest offered row of `task`, shown or not when `shown_only` is false.
fn latest_offered<'a>(rows: &'a [Value], task: &str, shown_only: bool) -> Option<&'a Value> {
    rows.iter()
        .rev()
        .find(|r| is_offered(r) && r["task"] == task && (!shown_only || r["shown"] == true))
}

// ── --check ──────────────────────────────────────────────────────────────────

#[derive(Debug, PartialEq, Serialize)]
pub struct Check {
    /// The shown offered row still waiting for an outcome; `None` when nothing blocks.
    pub unresolved: Option<String>,
    /// Older shown, unresolved offered rows for the task: reported, never blocking.
    pub orphans: Vec<String>,
}

/// Looks only at the latest shown offered row for the task.
pub fn check(rows: &[Value], task: &str) -> Check {
    let latest = latest_offered(rows, task, true);
    let latest_id = latest.and_then(|r| r["id"].as_str());
    let unresolved = latest_id.filter(|id| !resolved(rows, id)).map(str::to_string);
    let orphans = rows
        .iter()
        .filter(|r| is_offered(r) && r["task"] == task && r["shown"] == true)
        .filter_map(|r| r["id"].as_str())
        .filter(|id| Some(*id) != latest_id && !resolved(rows, id))
        .map(str::to_string)
        .collect();
    Check { unresolved, orphans }
}

// ── outcome ──────────────────────────────────────────────────────────────────

pub enum Answer {
    Given { used: Vec<String>, ignored: Vec<String> },
    NoAnswer,
}

/// What `opened` holds: the offered refs the transcript shows being read, or `unavailable`.
pub enum Opened {
    Refs(Vec<String>),
    Unavailable,
}

/// Build the outcome row for the latest unresolved offered row of `task`. Fails, writing
/// nothing, when there is no such row, when a ref is not among that row's pointers, or when a
/// ref is both used and ignored.
pub fn outcome_row(
    rows: &[Value],
    task: &str,
    answer: &Answer,
    opened: impl FnOnce(&Value) -> Opened,
    now: chrono::DateTime<chrono::Utc>,
) -> Result<Value, String> {
    let offered = rows
        .iter()
        .rev()
        .find(|r| is_offered(r) && r["task"] == task && !r["id"].as_str().is_some_and(|id| resolved(rows, id)))
        .ok_or_else(|| format!("no unresolved offered row for {task}"))?;
    let listed: BTreeSet<&str> =
        offered["pointers"].as_array().into_iter().flatten().filter_map(|p| p["ref"].as_str()).collect();
    let (answer_word, used, ignored) = match answer {
        Answer::NoAnswer => ("no-answer", Vec::new(), Vec::new()),
        Answer::Given { used, ignored } => {
            let unknown: Vec<&str> =
                used.iter().chain(ignored).map(String::as_str).filter(|r| !listed.contains(r)).collect();
            if !unknown.is_empty() {
                return Err(format!(
                    "not in the offered bundle for {task}: {} (offered: {})",
                    unknown.join(", "),
                    listed.iter().copied().collect::<Vec<_>>().join(", ")
                ));
            }
            if let Some(both) = used.iter().find(|u| ignored.contains(u)) {
                return Err(format!("{both} is both used and ignored"));
            }
            ("given", dedup(used), dedup(ignored))
        }
    };
    let opened = match opened(offered) {
        Opened::Refs(r) => json!(r),
        Opened::Unavailable => json!("unavailable"),
    };
    Ok(json!({
        "v": ROW_VERSION,
        "kind": "outcome",
        "offered": offered["id"],
        "task": task,
        "ts": now.format("%Y-%m-%dT%H:%M:%SZ").to_string(),
        "answer": answer_word,
        "used": used,
        "ignored": ignored,
        "opened": opened,
    }))
}

fn dedup(v: &[String]) -> Vec<String> {
    let mut seen = BTreeSet::new();
    v.iter().filter(|s| seen.insert((*s).clone())).cloned().collect()
}

/// Which of `refs` the session transcript at `path` shows being read: a tool-use line naming
/// `Read` and `<ref>.md`. Advisory only (the newest transcript can be another session's, and
/// subagent reads are not counted). `None` when the transcript cannot be read.
pub fn opened_in_transcript(path: &Path, refs: &[String]) -> Option<Vec<String>> {
    use std::io::BufRead;
    let f = std::fs::File::open(path).ok()?;
    let mut found = BTreeSet::new();
    for line in std::io::BufReader::new(f).lines().map_while(Result::ok) {
        if !line.contains("\"Read\"") {
            continue;
        }
        for r in refs {
            if line.contains(&format!("{r}.md")) {
                found.insert(r.clone());
            }
        }
    }
    Some(refs.iter().filter(|r| found.contains(*r)).cloned().collect())
}

/// The offered refs of a row, in rank order.
pub fn offered_refs(offered: &Value) -> Vec<String> {
    offered["pointers"].as_array().into_iter().flatten().filter_map(|p| p["ref"].as_str().map(str::to_string)).collect()
}

// ── --report ─────────────────────────────────────────────────────────────────

#[derive(Debug, Default, Serialize)]
pub struct Report {
    pub tasks: usize,
    pub offered: usize,
    pub shown: usize,
    pub shadow: usize,
    pub outcomes: usize,
    pub unresolved_shown: usize,
    pub empty_bundles: usize,
    pub bundle_size_mean: f64,
    pub bundle_size_max: usize,
    /// `"fts:timeout"` → rows with that leg state, for every state except `ok`.
    pub legs_not_ok: BTreeMap<String, usize>,
    pub malformed_lines: usize,
}

pub fn report(rows: &Rows) -> Report {
    let mut r = Report { malformed_lines: rows.malformed, ..Report::default() };
    let mut tasks = BTreeSet::new();
    let mut total = 0usize;
    for row in rows.rows.iter().filter(|x| is_offered(x)) {
        r.offered += 1;
        tasks.insert(row["task"].as_str().unwrap_or_default().to_string());
        if row["shown"] == true {
            r.shown += 1;
            if !row["id"].as_str().is_some_and(|id| resolved(&rows.rows, id)) {
                r.unresolved_shown += 1;
            }
        } else {
            r.shadow += 1;
        }
        let n = row["pointers"].as_array().map_or(0, Vec::len);
        total += n;
        r.bundle_size_max = r.bundle_size_max.max(n);
        r.empty_bundles += usize::from(n == 0);
        for leg in ["fts", "vector"] {
            let state = row["legs"][leg].as_str().unwrap_or("unknown");
            if state != "ok" {
                *r.legs_not_ok.entry(format!("{leg}:{state}")).or_default() += 1;
            }
        }
    }
    r.outcomes = rows.rows.iter().filter(|x| x["kind"] == "outcome").count();
    r.tasks = tasks.len();
    r.bundle_size_mean = if r.offered == 0 { 0.0 } else { total as f64 / r.offered as f64 };
    r
}

#[cfg(test)]
mod tests {
    use super::*;
    use chrono::TimeZone;

    fn at(h: u32, m: u32) -> chrono::DateTime<chrono::Utc> {
        chrono::Utc.with_ymd_and_hms(2026, 10, 20, h, m, 0).unwrap()
    }

    fn ptr(name: &str, rank: usize) -> Pointer {
        Pointer {
            ptype: "pattern".into(),
            ref_: name.into(),
            gist: Some("SENTINEL-GIST-do-not-log".into()),
            rank,
            flags: vec![],
        }
    }

    fn offered(task: &str, shown: bool, refs: &[&str], when: chrono::DateTime<chrono::Utc>) -> Value {
        let ptrs: Vec<Pointer> = refs.iter().enumerate().map(|(i, r)| ptr(r, i + 1)).collect();
        offered_row(
            &Offered {
                task,
                shown,
                fts: "ok",
                vector: "ok",
                elapsed_ms: 12,
                pointers: &ptrs,
                freshness: json!({"outcome": {"state": "fresh"}}),
                session: Some("abc-123"),
            },
            when,
        )
    }

    fn given(used: &[&str], ignored: &[&str]) -> Answer {
        Answer::Given {
            used: used.iter().map(|s| s.to_string()).collect(),
            ignored: ignored.iter().map(|s| s.to_string()).collect(),
        }
    }

    #[test]
    fn offered_row_carries_ids_only() {
        let row = offered("t-1", false, &["pattern_a"], at(10, 0));
        let text = row.to_string();
        assert!(!text.contains("SENTINEL"), "gist leaked into the log: {text}");
        assert_eq!(row["v"], 1);
        assert_eq!(row["kind"], "offered");
        assert_eq!(row["shown"], false);
        assert_eq!(row["pointers"][0]["ref"], "pattern_a");
        assert!(row["id"].as_str().unwrap().starts_with("o-"));
    }

    #[test]
    fn the_session_stem_cannot_name_another_path() {
        let ptrs = [];
        let row = offered_row(
            &Offered {
                task: "t-1",
                shown: false,
                fts: "ok",
                vector: "ok",
                elapsed_ms: 0,
                pointers: &ptrs,
                freshness: json!({}),
                session: Some("../../etc/passwd"),
            },
            at(10, 0),
        );
        assert_eq!(row["session"], "etcpasswd");
    }

    #[test]
    fn append_creates_a_private_file_in_a_private_folder() {
        use std::os::unix::fs::PermissionsExt;
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("proj/brana").join(LOG_FILE);
        append(&path, &offered("t-1", false, &[], at(10, 0))).unwrap();
        let mode = |p: &Path| std::fs::metadata(p).unwrap().permissions().mode() & 0o777;
        assert_eq!(mode(&path), 0o600);
        assert_eq!(mode(path.parent().unwrap()), 0o700);
    }

    #[test]
    fn concurrent_appends_each_leave_one_parseable_line() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("brana").join(LOG_FILE);
        let handles: Vec<_> = (0..16)
            .map(|i| {
                let p = path.clone();
                std::thread::spawn(move || {
                    let refs: Vec<String> = (0..30).map(|k| format!("pattern_with_a_long_name_{i}_{k}")).collect();
                    let refs: Vec<&str> = refs.iter().map(String::as_str).collect();
                    append(&p, &offered(&format!("t-{i}"), false, &refs, at(10, 0))).unwrap();
                })
            })
            .collect();
        handles.into_iter().for_each(|h| h.join().unwrap());
        let rows = read_rows(&[path]);
        assert_eq!(rows.rows.len(), 16);
        assert_eq!(rows.malformed, 0);
    }

    #[test]
    fn both_encodings_are_read_and_rows_come_back_oldest_first() {
        let dir = tempfile::tempdir().unwrap();
        let root = Path::new("/home/u/my_proj");
        let [cur, legacy] = log_paths(dir.path(), root);
        assert_ne!(cur, legacy);
        append(&cur, &offered("t-1", false, &[], at(11, 0))).unwrap();
        append(&legacy, &offered("t-1", false, &[], at(9, 0))).unwrap();
        let rows = read_rows(&[cur, legacy]);
        assert_eq!(rows.rows.len(), 2);
        assert_eq!(rows.rows[0]["ts"], "2026-10-20T09:00:00Z");
    }

    #[test]
    fn a_path_given_twice_is_read_once() {
        let dir = tempfile::tempdir().unwrap();
        let [cur, legacy] = log_paths(dir.path(), Path::new("/home/u/proj"));
        assert_eq!(cur, legacy, "no underscore: the encodings coincide");
        append(&cur, &offered("t-1", false, &[], at(10, 0))).unwrap();
        assert_eq!(read_rows(&[cur, legacy]).rows.len(), 1);
    }

    #[test]
    fn a_malformed_line_is_counted_and_skipped() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join(LOG_FILE);
        std::fs::write(&path, format!("not json\n{}\n{{\"x\":1}}\n", offered("t-1", false, &[], at(10, 0)))).unwrap();
        let rows = read_rows(&[path]);
        assert_eq!((rows.rows.len(), rows.malformed), (1, 2));
    }

    #[test]
    fn check_blocks_only_on_a_shown_unresolved_row() {
        let shadow = offered("t-1", false, &["pattern_a"], at(10, 0));
        assert_eq!(check(&[shadow], "t-1").unresolved, None, "a shadow row never blocks");
        assert_eq!(check(&[], "t-1").unresolved, None);

        let shown = offered("t-1", true, &["pattern_a"], at(10, 0));
        let id = shown["id"].as_str().unwrap().to_string();
        assert_eq!(check(&[shown.clone()], "t-1").unresolved, Some(id.clone()));
        assert_eq!(check(&[shown.clone()], "t-2").unresolved, None, "another task's row is not ours");

        let out = outcome_row(&[shown.clone()], "t-1", &given(&["pattern_a"], &[]), |_| Opened::Unavailable, at(11, 0))
            .unwrap();
        assert_eq!(check(&[shown, out], "t-1").unresolved, None);
    }

    #[test]
    fn check_looks_at_the_latest_shown_row_and_reports_older_ones_as_orphans() {
        let old = offered("t-1", true, &["pattern_a"], at(9, 0));
        let new = offered("t-1", true, &["pattern_a"], at(10, 0));
        let c = check(&[old.clone(), new.clone()], "t-1");
        assert_eq!(c.unresolved.as_deref(), new["id"].as_str());
        assert_eq!(c.orphans, vec![old["id"].as_str().unwrap().to_string()]);

        // Resolving the latest clears the block even though an older row is still open.
        let out = outcome_row(&[old.clone(), new.clone()], "t-1", &Answer::NoAnswer, |_| Opened::Unavailable, at(11, 0))
            .unwrap();
        let c = check(&[old, new, out], "t-1");
        assert_eq!(c.unresolved, None);
        assert_eq!(c.orphans.len(), 1);
    }

    #[test]
    fn an_outcome_binds_to_the_latest_unresolved_offered_row() {
        let first = offered("t-1", true, &["pattern_a"], at(9, 0));
        let second = offered("t-1", true, &["pattern_b"], at(10, 0));
        let out = outcome_row(&[first.clone(), second.clone()], "t-1", &given(&["pattern_b"], &[]), |_| Opened::Unavailable, at(11, 0))
            .unwrap();
        assert_eq!(out["offered"], second["id"]);
        // With the second resolved, the next outcome falls back to the first.
        let next = outcome_row(&[first.clone(), second, out], "t-1", &given(&["pattern_a"], &[]), |_| Opened::Unavailable, at(12, 0))
            .unwrap();
        assert_eq!(next["offered"], first["id"]);
    }

    #[test]
    fn an_outcome_with_a_ref_the_bundle_never_offered_is_rejected() {
        let o = offered("t-1", true, &["pattern_a", "pattern_b"], at(10, 0));
        let err = outcome_row(&[o.clone()], "t-1", &given(&["pattern_zzz"], &[]), |_| Opened::Unavailable, at(11, 0))
            .unwrap_err();
        assert!(err.contains("pattern_zzz"), "{err}");
        let err = outcome_row(&[o.clone()], "t-1", &given(&[], &["pattern_zzz"]), |_| Opened::Unavailable, at(11, 0))
            .unwrap_err();
        assert!(err.contains("pattern_zzz"), "{err}");
        let err = outcome_row(&[o], "t-1", &given(&["pattern_a"], &["pattern_a"]), |_| Opened::Unavailable, at(11, 0))
            .unwrap_err();
        assert!(err.contains("both"), "{err}");
    }

    #[test]
    fn an_outcome_without_an_offered_row_is_an_error() {
        assert!(outcome_row(&[], "t-1", &Answer::NoAnswer, |_| Opened::Unavailable, at(11, 0)).is_err());
        let o = offered("t-1", true, &[], at(10, 0));
        let done = outcome_row(&[o.clone()], "t-1", &Answer::NoAnswer, |_| Opened::Unavailable, at(11, 0)).unwrap();
        assert!(outcome_row(&[o, done], "t-1", &Answer::NoAnswer, |_| Opened::Unavailable, at(12, 0)).is_err());
    }

    #[test]
    fn outcome_rows_hold_refs_and_words_only() {
        let o = offered("t-1", true, &["pattern_a", "pattern_b"], at(10, 0));
        let out = outcome_row(
            &[o],
            "t-1",
            &given(&["pattern_a", "pattern_a"], &["pattern_b"]),
            |_| Opened::Refs(vec!["pattern_a".into()]),
            at(11, 0),
        )
        .unwrap();
        assert_eq!(out["answer"], "given");
        assert_eq!(out["used"], json!(["pattern_a"]));
        assert_eq!(out["ignored"], json!(["pattern_b"]));
        assert_eq!(out["opened"], json!(["pattern_a"]));
        assert!(!out.to_string().contains("SENTINEL"));

        let none = outcome_row(&[offered("t-2", true, &["pattern_a"], at(10, 0))], "t-2", &given(&[], &[]), |_| Opened::Unavailable, at(11, 0))
            .unwrap();
        assert_eq!(none["answer"], "given");
        assert_eq!(none["used"], json!([]));
        assert_eq!(none["opened"], "unavailable");
    }

    #[test]
    fn the_opened_closure_sees_the_offered_row() {
        let o = offered("t-1", true, &["pattern_a"], at(10, 0));
        let out = outcome_row(&[o], "t-1", &Answer::NoAnswer, |row| {
            assert_eq!(row["session"], "abc-123");
            Opened::Unavailable
        }, at(11, 0))
        .unwrap();
        assert_eq!(out["answer"], "no-answer");
    }

    #[test]
    fn opened_counts_only_read_tool_lines_naming_the_note() {
        let dir = tempfile::tempdir().unwrap();
        let p = dir.path().join("s.jsonl");
        std::fs::write(
            &p,
            concat!(
                "{\"name\":\"Read\",\"input\":{\"file_path\":\"/m/pattern_a.md\"}}\n",
                "{\"name\":\"Bash\",\"input\":{\"command\":\"cat /m/pattern_b.md\"}}\n",
            ),
        )
        .unwrap();
        let refs = vec!["pattern_a".to_string(), "pattern_b".to_string()];
        assert_eq!(opened_in_transcript(&p, &refs), Some(vec!["pattern_a".to_string()]));
        assert_eq!(opened_in_transcript(&dir.path().join("missing.jsonl"), &refs), None);
    }

    #[test]
    fn the_report_counts_rows_sizes_and_degraded_legs() {
        let mut slow = offered("t-2", false, &[], at(10, 5));
        slow["legs"]["vector"] = json!("timeout");
        let shown = offered("t-1", true, &["pattern_a", "pattern_b", "pattern_c"], at(10, 0));
        let done = outcome_row(&[shown.clone()], "t-1", &Answer::NoAnswer, |_| Opened::Unavailable, at(11, 0)).unwrap();
        let open = offered("t-3", true, &["pattern_a"], at(12, 0));
        let r = report(&Rows { rows: vec![shown, slow, open, done], malformed: 2 });
        assert_eq!((r.tasks, r.offered, r.shown, r.shadow), (3, 3, 2, 1));
        assert_eq!((r.outcomes, r.unresolved_shown, r.empty_bundles), (1, 1, 1));
        assert_eq!(r.bundle_size_max, 3);
        assert!((r.bundle_size_mean - 4.0 / 3.0).abs() < 1e-9);
        assert_eq!(r.legs_not_ok.get("vector:timeout"), Some(&1));
        assert_eq!(r.malformed_lines, 2);
    }

    #[test]
    fn a_log_append_does_not_change_the_newest_transcript_pick() {
        // The log sits in `brana/`, below the project folder. Scanners that read only the top
        // level of the folder (brana time, skills usage) must still see just the transcript.
        let dir = tempfile::tempdir().unwrap();
        let proj = dir.path().join("-home-u-proj");
        std::fs::create_dir_all(&proj).unwrap();
        std::fs::write(proj.join("sess.jsonl"), "{}\n").unwrap();
        append(&proj.join("brana").join(LOG_FILE), &offered("t-1", false, &[], at(10, 0))).unwrap();
        let top: Vec<_> = std::fs::read_dir(&proj)
            .unwrap()
            .flatten()
            .filter(|e| e.path().extension().and_then(|x| x.to_str()) == Some("jsonl"))
            .map(|e| e.file_name())
            .collect();
        assert_eq!(top, vec![std::ffi::OsString::from("sess.jsonl")]);
    }
}
